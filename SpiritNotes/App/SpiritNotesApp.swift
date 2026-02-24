import SwiftUI

@main
struct SpiritNotesApp: App {
    @State private var authStore = AuthStore()
    @State private var noteStore = NoteStore()
    @State private var settingsStore = SettingsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authStore)
                .environment(noteStore)
                .environment(settingsStore)
        }
    }
}
