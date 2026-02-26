import GoogleSignIn
import SwiftUI

@main
struct SpiritNotesApp: App {
    @State private var authStore = AuthStore()
    @State private var noteStore = NoteStore()
    @State private var settingsStore = SettingsStore()
    @State private var subscriptionStore = SubscriptionStore()

    init() {
        subscriptionStore.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authStore)
                .environment(noteStore)
                .environment(settingsStore)
                .environment(subscriptionStore)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
