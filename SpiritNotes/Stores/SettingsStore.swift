import Foundation
import Observation

@Observable
final class SettingsStore {
    var language: String = "auto"
    var theme: AppTheme = .system

    enum AppTheme: String, CaseIterable {
        case system
        case light
        case dark
    }

    func loadSettings() {
        // TODO: Load from UserDefaults / Supabase
    }

    func setLanguage(_ language: String) async throws {
        self.language = language
        // TODO: Persist to Supabase
    }

    func setTheme(_ theme: AppTheme) {
        self.theme = theme
        // TODO: Persist to UserDefaults
    }
}
