import GoogleSignIn
import SwiftUI

enum DeepLink: Equatable {
    case record
}

private enum AppRuntime {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

@main
struct TalkdraftApp: App {
    @State private var authStore = AuthStore()
    @State private var noteStore = NoteStore()
    @State private var settingsStore = SettingsStore()
    @State private var subscriptionStore = SubscriptionStore()
    @State private var pendingDeepLink: DeepLink?

    init() {
        settingsStore.loadSettings()
        if !AppRuntime.isRunningTests {
            subscriptionStore.configure()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(pendingDeepLink: $pendingDeepLink)
                .fontDesign(.rounded)
                .environment(authStore)
                .environment(noteStore)
                .environment(settingsStore)
                .environment(subscriptionStore)
                .onOpenURL { url in
                    if url.scheme == "talkdraft", url.host == "record" {
                        pendingDeepLink = .record
                    } else if url.scheme == "talkdraft" {
                        Task { await authStore.handleURL(url) }
                    } else {
                        GIDSignIn.sharedInstance.handle(url)
                    }
                }
        }
    }
}
