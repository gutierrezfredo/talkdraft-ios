import Foundation
import Observation
import Supabase

@MainActor @Observable
final class SettingsStore {
    var language: String = "auto" {
        didSet { UserDefaults.standard.set(language, forKey: "settings.language") }
    }

    var theme: AppTheme = .system {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "settings.theme") }
    }

    private(set) var customDictionary: [String] = []
    private var userId: UUID?

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

    /// Called after sign-in with the user's profile data from Supabase.
    /// Server value wins over any local UserDefaults cache.
    func configure(userId: UUID, dictionary: [String]) {
        self.userId = userId
        customDictionary = dictionary
    }

    func resetSession() {
        userId = nil
        customDictionary = []
    }

    func addWord(_ word: String) {
        guard !customDictionary.contains(word) else { return }
        customDictionary.append(word)
        Task { await saveToSupabase() }
    }

    func removeWord(at index: Int) {
        guard customDictionary.indices.contains(index) else { return }
        customDictionary.remove(at: index)
        Task { await saveToSupabase() }
    }

    private struct DictionaryUpdate: Encodable {
        let customDictionary: [String]
        enum CodingKeys: String, CodingKey {
            case customDictionary = "custom_dictionary"
        }
    }

    private func saveToSupabase() async {
        guard let userId else { return }
        do {
            try await supabase
                .from("profiles")
                .update(DictionaryUpdate(customDictionary: customDictionary))
                .eq("id", value: userId)
                .execute()
        } catch {
            print("❌ CustomDictionary save error:", error)
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
    }
}
