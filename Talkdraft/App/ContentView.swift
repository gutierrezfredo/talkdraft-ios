import SwiftUI

struct ContentView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(NoteStore.self) private var noteStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptionStore
    @Environment(\.scenePhase) private var scenePhase

    private var showMandatoryPaywall: Binding<Bool> {
        Binding(
            get: { false },
            set: { _ in }
        )
    }

    private var colorScheme: ColorScheme? {
        switch settingsStore.theme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var body: some View {
        Group {
            if authStore.isLoading {
                // Splash / loading
                ZStack {
                    Color.darkBackground.ignoresSafeArea()
                    ProgressView()
                        .tint(Color.brand)
                        .scaleEffect(1.5)
                }
            } else if authStore.isAuthenticated {
                if subscriptionStore.entitlementChecked && noteStore.hasInitiallyLoaded {
                    HomeView()
                        .fullScreenCover(isPresented: showMandatoryPaywall) {
                            PaywallView(mandatory: true)
                        }
                } else {
                    ZStack {
                        Color.darkBackground.ignoresSafeArea()
                        ProgressView()
                            .tint(Color.brand)
                            .scaleEffect(1.5)
                    }
                }
            } else {
                LoginView()
            }
        }
        .preferredColorScheme(colorScheme)
        .task {
            await authStore.initialize(settingsStore: settingsStore, noteStore: noteStore)
            // Belt-and-suspenders: if startup auth state was already available before onChange
            // hooks settled, initialize the user session here too.
            if authStore.isAuthenticated, let userId = authStore.userId {
                noteStore.beginSession(userId: userId)
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
                if let userId = authStore.userId {
                    noteStore.beginSession(userId: userId)
                    Task { await noteStore.refresh() }
                    Task { await subscriptionStore.login(userId: userId) }
                }
            } else {
                noteStore.resetSession()
                settingsStore.resetSession()
                Task { await subscriptionStore.logout() }
            }
        }
        .onChange(of: authStore.userId) { oldValue, newValue in
            guard authStore.isAuthenticated,
                  let oldValue,
                  let newValue,
                  oldValue != newValue
            else { return }

            noteStore.resetSession()
            noteStore.beginSession(userId: newValue)
            Task { await noteStore.refresh() }
            Task { await subscriptionStore.login(userId: newValue) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task {
                // Wait for connectivity to stabilize after coming from airplane mode
                try? await Task.sleep(for: .seconds(3))
                noteStore.repairOrphanedTranscriptions()
                noteStore.retryPendingNoteUpserts()
                let language = settingsStore.language == "auto" ? nil : settingsStore.language
                noteStore.retryWaitingNotes(language: language, userId: authStore.userId, customDictionary: settingsStore.customDictionary)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            Task {
                await noteStore.flushPendingNoteUpserts()
            }
        }
    }
}
