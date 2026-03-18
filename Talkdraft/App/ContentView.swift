import SwiftUI

struct ContentView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(NoteStore.self) private var noteStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptionStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var completedOnboardingUserId: UUID?
    @State private var didFinishInitialAuthBootstrap = false
    @State private var showPostAuthTransition = false
    @State private var isPerformingInteractiveAuth = false

    private var showMandatoryPaywall: Binding<Bool> {
        Binding(
            get: {
                authStore.isAuthenticated
                    && isPostAuthBootstrapReady
                    && !shouldShowOnboarding
                    && !subscriptionStore.isPro
            },
            set: { _ in }
        )
    }

    private var shouldShowOnboarding: Bool {
        guard let userId = authStore.userId else { return false }
        if UserDefaults.standard.bool(forKey: "onboarding.completed.\(userId.uuidString)") { return false }
        if !noteStore.notes.isEmpty || !noteStore.categories.isEmpty { return false }
        return completedOnboardingUserId != userId
    }

    private var colorScheme: ColorScheme? {
        switch settingsStore.theme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private var isPostAuthBootstrapReady: Bool {
        subscriptionStore.entitlementChecked && noteStore.hasInitiallyLoaded
    }

    private var shouldShowPostAuthTransition: Bool {
        authStore.isAuthenticated && (showPostAuthTransition || isPerformingInteractiveAuth) && !isPostAuthBootstrapReady
    }

    private var splashView: some View {
        ZStack {
            Color.darkBackground.ignoresSafeArea()
            LunaMascotView(.moon, size: 200, zColor: .white)
        }
    }

    var body: some View {
        Group {
            if authStore.isLoading && !didFinishInitialAuthBootstrap {
                splashView
            } else if authStore.isAuthenticated {
                if isPostAuthBootstrapReady {
                    if shouldShowOnboarding {
                        OnboardingView {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                completedOnboardingUserId = authStore.userId
                            }
                        }
                    } else {
                        HomeView()
                            .fullScreenCover(isPresented: showMandatoryPaywall) {
                                PaywallView(mandatory: true)
                            }
                    }
                } else if shouldShowPostAuthTransition {
                    LoginView(phase: .transitioning)
                } else {
                    splashView
                }
            } else {
                LoginView(phase: authStore.isLoading ? .authenticating : .signIn)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: noteStore.hasInitiallyLoaded)
        .animation(.easeInOut(duration: 0.4), value: showPostAuthTransition)
        .preferredColorScheme(colorScheme)
        .task {
            await authStore.initialize(settingsStore: settingsStore, noteStore: noteStore)
            didFinishInitialAuthBootstrap = true
            // Belt-and-suspenders: if startup auth state was already available before onChange
            // hooks settled, initialize the user session here too.
            if authStore.isAuthenticated, let userId = authStore.userId {
                noteStore.beginSession(userId: userId)
                noteStore.startRewriteJobPolling()
                if !subscriptionStore.entitlementChecked {
                    await subscriptionStore.login(userId: userId)
                }
                if !noteStore.hasInitiallyLoaded {
                    await noteStore.refresh()
                }
            }
        }
        .onChange(of: authStore.isAuthenticated) { _, authenticated in
            if authenticated {
                if didFinishInitialAuthBootstrap {
                    showPostAuthTransition = true
                }
                if let userId = authStore.userId {
                    noteStore.beginSession(userId: userId)
                    noteStore.startRewriteJobPolling()
                    Task { await noteStore.refresh() }
                    Task { await subscriptionStore.login(userId: userId) }
                }
            } else {
                completedOnboardingUserId = nil
                isPerformingInteractiveAuth = false
                showPostAuthTransition = false
                noteStore.resetSession()
                settingsStore.resetSession()
                Task { await subscriptionStore.logout() }
            }
        }
        .onChange(of: authStore.isLoading) { _, isLoading in
            guard didFinishInitialAuthBootstrap, !authStore.isAuthenticated else { return }
            isPerformingInteractiveAuth = isLoading
        }
        .onChange(of: authStore.userId) { oldValue, newValue in
            guard authStore.isAuthenticated,
                  let oldValue,
                  let newValue,
                  oldValue != newValue
            else { return }

            completedOnboardingUserId = nil
            if didFinishInitialAuthBootstrap {
                showPostAuthTransition = true
            }
            noteStore.resetSession()
            noteStore.beginSession(userId: newValue)
            noteStore.startRewriteJobPolling()
            Task { await noteStore.refresh() }
            Task { await subscriptionStore.login(userId: newValue) }
        }
        .onChange(of: isPostAuthBootstrapReady) { _, ready in
            if ready {
                isPerformingInteractiveAuth = false
                showPostAuthTransition = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task {
                // Wait for connectivity to stabilize after coming from airplane mode
                try? await Task.sleep(for: .seconds(3))
                noteStore.repairOrphanedTranscriptions()
                noteStore.retryPendingNoteUpserts()
                noteStore.retryPendingHardDeletes()
                await noteStore.refreshRewriteJobs()
                let language = settingsStore.language == "auto" ? nil : settingsStore.language
                noteStore.retryWaitingNotes(language: language, userId: authStore.userId, customDictionary: settingsStore.customDictionary)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                noteStore.startRewriteJobPolling()
            case .background:
                noteStore.stopRewriteJobPolling()
                Task {
                    await noteStore.flushPendingNoteUpserts()
                    await noteStore.flushPendingHardDeletes()
                }
            default:
                break
            }
        }
    }
}
