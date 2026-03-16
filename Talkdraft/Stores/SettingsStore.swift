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
    func configure(userId: UUID, language: String?, dictionary: [String]) {
        self.userId = userId
        if let language, !language.isEmpty {
            self.language = language
        } else {
            self.language = "auto"
        }
        customDictionary = dictionary
    }

    /// Persist the current language to the user's Supabase profile.
    func saveLanguageToProfile() {
        guard let userId else { return }
        Task {
            do {
                try await supabase
                    .from("profiles")
                    .update(LanguageUpdate(language: language == "auto" ? nil : language))
                    .eq("id", value: userId)
                    .execute()
            } catch {
                // Non-fatal — language is also cached in UserDefaults
            }
        }
    }

    private struct LanguageUpdate: Encodable {
        let language: String?
    }

    func resetSession() {
        userId = nil
        language = "auto"
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

    // MARK: - Language Data

    static let supportedLanguages: [(code: String, name: String)] = [
        ("af", "Afrikaans"),
        ("ar", "Arabic"),
        ("hy", "Armenian"),
        ("az", "Azerbaijani"),
        ("be", "Belarusian"),
        ("bs", "Bosnian"),
        ("bg", "Bulgarian"),
        ("ca", "Catalan"),
        ("zh", "Chinese"),
        ("hr", "Croatian"),
        ("cs", "Czech"),
        ("da", "Danish"),
        ("nl", "Dutch"),
        ("en", "English"),
        ("et", "Estonian"),
        ("fi", "Finnish"),
        ("fr", "French"),
        ("gl", "Galician"),
        ("de", "German"),
        ("el", "Greek"),
        ("he", "Hebrew"),
        ("hi", "Hindi"),
        ("hu", "Hungarian"),
        ("is", "Icelandic"),
        ("id", "Indonesian"),
        ("it", "Italian"),
        ("ja", "Japanese"),
        ("kn", "Kannada"),
        ("kk", "Kazakh"),
        ("ko", "Korean"),
        ("lv", "Latvian"),
        ("lt", "Lithuanian"),
        ("mk", "Macedonian"),
        ("ms", "Malay"),
        ("mr", "Marathi"),
        ("mi", "Maori"),
        ("ne", "Nepali"),
        ("no", "Norwegian"),
        ("fa", "Persian"),
        ("pl", "Polish"),
        ("pt", "Portuguese"),
        ("ro", "Romanian"),
        ("ru", "Russian"),
        ("sr", "Serbian"),
        ("sk", "Slovak"),
        ("sl", "Slovenian"),
        ("es", "Spanish"),
        ("sw", "Swahili"),
        ("sv", "Swedish"),
        ("tl", "Tagalog"),
        ("ta", "Tamil"),
        ("th", "Thai"),
        ("tr", "Turkish"),
        ("uk", "Ukrainian"),
        ("ur", "Urdu"),
        ("vi", "Vietnamese"),
        ("cy", "Welsh"),
    ]
}
