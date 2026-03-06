import Foundation
import Observation

@Observable
final class SettingsStore {
    var language: String = "auto" {
        didSet { UserDefaults.standard.set(language, forKey: "settings.language") }
    }

    var theme: AppTheme = .system {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "settings.theme") }
    }

    var customDictionary: [String] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(customDictionary) {
                UserDefaults.standard.set(data, forKey: "settings.customDictionary")
            }
        }
    }

    enum AppTheme: String, CaseIterable {
        case system
        case light
        case dark

        var displayName: String {
            switch self {
            case .system: "System"
            case .light: "Light"
            case .dark: "Dark"
            }
        }
    }

    func loadSettings() {
        if let lang = UserDefaults.standard.string(forKey: "settings.language") {
            language = lang
        }
        if let themeRaw = UserDefaults.standard.string(forKey: "settings.theme"),
           let saved = AppTheme(rawValue: themeRaw) {
            theme = saved
        }
        if let data = UserDefaults.standard.data(forKey: "settings.customDictionary"),
           let words = try? JSONDecoder().decode([String].self, from: data) {
            customDictionary = words
        }
    }
}
