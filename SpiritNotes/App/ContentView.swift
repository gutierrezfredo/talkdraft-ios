import SwiftUI

struct ContentView: View {
    @Environment(AuthStore.self) private var authStore

    var body: some View {
        Group {
            if authStore.isAuthenticated {
                HomeView()
            } else {
                LoginView()
            }
        }
    }
}
