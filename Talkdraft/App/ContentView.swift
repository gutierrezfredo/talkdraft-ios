import SwiftUI

struct ContentView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(NoteStore.self) private var noteStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptionStore
    @Environment(\.scenePhase) private var scenePhase
    @Binding var pendingDeepLink: DeepLink?
    @AppStorage("onboarding.completed.device") private var deviceOnboardingCompleted = false
    @State private var completedOnboardingUserId: UUID?
    @State private var didFinishInitialAuthBootstrap = false
    @State private var showPostAuthTransition = false
    @State private var isPerformingInteractiveAuth = false
    @State private var startedPreAuthOnboarding = false

    private var showMandatoryPaywall: Binding<Bool> {
        Binding(
            get: {
                #if DEBUG
                return false
                #else
                return authStore.isAuthenticated
                    && isPostAuthBootstrapReady
                    && !subscriptionStore.isPro
                #endif
            },
            set: { _ in }
        )
    }

    /// Device-level onboarding check (works before and after auth).
    private var shouldShowOnboarding: Bool {
        if deviceOnboardingCompleted { return false }
        // Legacy: user-specific flag for existing users
        if let userId = authStore.userId,
           UserDefaults.standard.bool(forKey: "onboarding.completed.\(userId.uuidString)") {
            markOnboardingComplete(for: userId)
            return false
        }

        // Returning authenticated users need their notes/categories loaded before we
        // can tell whether onboarding should be skipped. Keep the pre-auth flow alive
        // for users who are already inside onboarding.
        if authStore.isAuthenticated, !startedPreAuthOnboarding {
            guard noteStore.hasInitiallyLoaded else { return false }
            if !noteStore.notes.isEmpty || !noteStore.categories.isEmpty {
                markOnboardingComplete(for: authStore.userId)
                return false
            }
        }

        return completedOnboardingUserId == nil
    }

    private func markOnboardingComplete(for userId: UUID?) {
        deviceOnboardingCompleted = true
        if let userId {
            UserDefaults.standard.set(true, forKey: "onboarding.completed.\(userId.uuidString)")
        }
    }

    private var colorScheme: ColorScheme? {
        switch settingsStore.theme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private var effectiveSplashColorScheme: ColorScheme {
        colorScheme ?? splashColorScheme
    }

    private var isPostAuthBootstrapReady: Bool {
        subscriptionStore.entitlementChecked && noteStore.hasInitiallyLoaded
    }

    private var shouldShowPostAuthTransition: Bool {
        authStore.isAuthenticated && (showPostAuthTransition || isPerformingInteractiveAuth) && !isPostAuthBootstrapReady
    }

    @Environment(\.colorScheme) private var splashColorScheme

    private var splashView: some View {
        ZStack {
            Group {
                if effectiveSplashColorScheme == .dark {
                    Color.darkBackground
                } else {
                    LinearGradient(
                        colors: [Color(hex: "#8B5CF6"), Color(hex: "#6D28D9")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .ignoresSafeArea()

            if effectiveSplashColorScheme == .dark {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.brand.opacity(0.15),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 40,
                            endRadius: 180
                        )
                    )
                    .frame(width: 360, height: 360)
            }

            ZStack(alignment: .topLeading) {
                Image("talkdraft-logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                SplashFloatingZs(colorScheme: effectiveSplashColorScheme)
                    .offset(x: -10, y: -20)
            }
            .accessibilityHidden(true)
        }
    }

    var body: some View {
        Group {
            if authStore.isLoading && !didFinishInitialAuthBootstrap {
                splashView
            } else if shouldShowOnboarding {
                // Onboarding shown regardless of auth state (auth happens inside paywall)
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        completedOnboardingUserId = authStore.userId
                        startedPreAuthOnboarding = false
                    }
                }
                .onAppear {
                    if !authStore.isAuthenticated {
                        startedPreAuthOnboarding = true
                    }
                }
            } else if authStore.isAuthenticated {
                if isPostAuthBootstrapReady {
                    HomeView(
                        pendingDeepLink: $pendingDeepLink,
                        isMandatoryPaywallPresented: showMandatoryPaywall.wrappedValue
                    )
                        .fullScreenCover(isPresented: showMandatoryPaywall) {
                            PaywallView(mandatory: true)
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
                startedPreAuthOnboarding = false
                pendingDeepLink = nil
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

// MARK: - Splash Floating Z's

private struct SplashFloatingZs: View {
    let colorScheme: ColorScheme

    var body: some View {
        ZStack {
            SplashFloatingZ(delay: 0.0, xOffset: 0, colorScheme: colorScheme)
            SplashFloatingZ(delay: 1.2, xOffset: 10, colorScheme: colorScheme)
            SplashFloatingZ(delay: 2.4, xOffset: -6, colorScheme: colorScheme)
        }
        .frame(width: 60, height: 60)
    }
}

private struct SplashFloatingZ: View {
    let delay: Double
    let xOffset: CGFloat
    let colorScheme: ColorScheme
    @State private var visible = false
    @State private var animate = false

    var body: some View {
        Text("z")
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(colorScheme == .dark ? Color.secondary : Color.white)
            .opacity(visible ? (animate ? 0 : 0.45) : 0)
            .offset(x: xOffset + (animate ? 4 : 0), y: animate ? -18 : 0)
            .scaleEffect(animate ? 0.82 : 1.0)
            .onAppear {
                Task {
                    try? await Task.sleep(for: .seconds(delay))
                    visible = true
                    withAnimation(
                        .easeOut(duration: 3.8)
                        .repeatForever(autoreverses: false)
                    ) {
                        animate = true
                    }
                }
            }
    }
}
