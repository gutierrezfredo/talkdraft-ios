import SwiftUI

struct ContentView: View {
    @Environment(AuthStore.self) private var authStore

    var body: some View {
        // Show home directly for now (auth will be wired up later)
        HomeView()
            .ignoresSafeArea(.keyboard)
    }
}
