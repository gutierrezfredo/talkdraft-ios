import SwiftUI

struct ContentView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(NoteStore.self) private var noteStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptionStore

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
                HomeView()
            } else {
                LoginView()
            }
        }
        .preferredColorScheme(colorScheme)
        .task {
            await authStore.initialize()
        }
        .onChange(of: authStore.isAuthenticated) { _, authenticated in
            if authenticated {
                Task { await noteStore.refresh() }
                if let userId = authStore.userId {
                    Task { await subscriptionStore.login(userId: userId) }
                }
            } else {
                Task { await subscriptionStore.logout() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task {
                // Wait for connectivity to stabilize after coming from airplane mode
                try? await Task.sleep(for: .seconds(3))
                let language = settingsStore.language == "auto" ? nil : settingsStore.language
                noteStore.retryWaitingNotes(language: language, userId: authStore.userId)
            }
        }
    }
}
