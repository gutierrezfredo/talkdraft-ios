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
        // Show home directly for now (auth will be wired up later)
        HomeView()
            .preferredColorScheme(colorScheme)
    }
}
