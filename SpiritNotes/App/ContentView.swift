import SwiftUI

struct ContentView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(SettingsStore.self) private var settingsStore

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
    }
}
