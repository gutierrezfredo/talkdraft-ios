import AuthenticationServices
import CryptoKit
import Foundation
import GoogleSignIn
import Observation
import Supabase

@MainActor @Observable
final class AuthStore {
    var isAuthenticated = false
    var isLoading = false
    var isSendingMagicLink = false
    var userId: UUID?
    var user: Profile?
    var error: String?
    var magicLinkCooldownRemaining = 0

    private var authListener: Task<Void, Never>?
    private var currentNonce: String?
    @ObservationIgnored private var magicLinkCooldownTask: Task<Void, Never>?

    private var settingsStore: SettingsStore?
    private weak var noteStore: NoteStore?

    func initialize(settingsStore: SettingsStore, noteStore: NoteStore) async {
        self.settingsStore = settingsStore
        self.noteStore = noteStore
        await _initialize()
    }

    private func _initialize() async {
        isLoading = true
        defer { isLoading = false }

        // Check existing session
        do {
            let session = try await supabase.auth.session
            await handleSession(session)
        } catch {
            isAuthenticated = false
        }

        // Listen for auth state changes
        listenForAuthChanges()
    }

    func sendMagicLink(email: String) async throws {
        if magicLinkCooldownRemaining > 0 {
            let error = AuthFlowError.magicLinkRateLimited(seconds: magicLinkCooldownRemaining)
            self.error = error.localizedDescription
            throw error
        }

        error = nil
        isSendingMagicLink = true
        defer { isSendingMagicLink = false }

        do {
            try await supabase.auth.signInWithOTP(
                email: email.trimmingCharacters(in: .whitespaces),
                redirectTo: AppConfig.redirectURL
            )
        } catch {
            let message = error.localizedDescription
            if let seconds = Self.parseMagicLinkCooldownSeconds(from: message) {
                startMagicLinkCooldown(seconds: seconds)
                let rateLimitError = AuthFlowError.magicLinkRateLimited(seconds: seconds)
                self.error = rateLimitError.localizedDescription
                throw rateLimitError
            }

            self.error = message
            throw error
        }
    }

    func handleURL(_ url: URL) async {
        do {
            let session = try await supabase.auth.session(from: url)
            await handleSession(session)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Apple Sign-In

    /// Prepare an Apple authorization request with a hashed nonce.
    func appleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.email, .fullName]
        request.nonce = sha256(nonce)
    }

    /// Handle the completed Apple authorization.
    func handleAppleSignIn(_ result: Result<ASAuthorization, any Error>) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityTokenData = credential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8),
                  let nonce = currentNonce
            else {
                self.error = "Invalid Apple credential"
                return
            }

            let session = try await supabase.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: identityToken, nonce: nonce)
            )
            await handleSession(session)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func randomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Google Sign-In

    private static let googleClientID = "57065416742-u6rhipilni04e0df29lcbmpdsck1rpt7.apps.googleusercontent.com"

    func signInWithGoogle() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController
            else {
                self.error = "Unable to find root view controller"
                return
            }

            let config = GIDConfiguration(clientID: Self.googleClientID)
            GIDSignIn.sharedInstance.configuration = config

            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            guard let idToken = result.user.idToken?.tokenString else {
                self.error = "Missing Google ID token"
                return
            }

            let session = try await supabase.auth.signInWithIdToken(
                credentials: .init(provider: .google, idToken: idToken)
            )
            await handleSession(session)
        } catch let error as GIDSignInError where error.code == .canceled {
            // User cancelled — not an error
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Anonymous Sign-In

    func signInAnonymously() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let session = try await supabase.auth.signInAnonymously()
            await handleSession(session)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func signOut() async throws {
        await noteStore?.flushPendingNoteUpserts()
        await noteStore?.flushPendingHardDeletes()
        try await supabase.auth.signOut()
        isAuthenticated = false
        userId = nil
        user = nil
        settingsStore?.resetSession()
    }

    // MARK: - Account Deletion

    func scheduleDeleteAccount() async throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result: DeleteAccountResponse = try await supabase.functions.invoke(
            "delete-account",
            options: .init(method: .post),
            decoder: decoder
        )
        user?.deletionScheduledAt = result.scheduledAt
    }

    func cancelDeleteAccount() async throws {
        try await supabase.functions.invoke(
            "cancel-delete-account",
            options: .init(method: .post)
        )
        user?.deletionScheduledAt = nil
    }

    // MARK: - Private

    private func handleSession(_ session: Session) async {
        userId = session.user.id
        isAuthenticated = true
        await fetchProfile(userId: session.user.id)
    }

    private func fetchProfile(userId: UUID) async {
        do {
            let profiles: [Profile] = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .limit(1)
                .execute()
                .value

            if let profile = profiles.first {
                user = profile
                settingsStore?.configure(userId: userId, language: profile.language, dictionary: profile.customDictionary)
                return
            }

            // Profile may not exist yet (new signup) — create one
            let newProfile = Profile(
                id: userId,
                displayName: nil,
                plan: .free,
                createdAt: Date(),
                deletionScheduledAt: nil,
                language: nil,
                customDictionary: []
            )
            do {
                try await supabase
                    .from("profiles")
                    .insert(newProfile)
                    .execute()
                user = newProfile
            } catch {
                // Profile creation failed — user can still use the app
                user = newProfile
            }
            settingsStore?.configure(userId: userId, language: nil, dictionary: [])
        } catch {
            self.error = "Unable to load your profile right now."
        }
    }

    private func listenForAuthChanges() {
        authListener?.cancel()
        authListener = Task { [weak self] in
            for await (event, session) in supabase.auth.authStateChanges {
                guard !Task.isCancelled else { return }
                switch event {
                case .signedIn:
                    if let session {
                        await self?.handleSession(session)
                    }
                case .signedOut:
                    self?.isAuthenticated = false
                    self?.userId = nil
                    self?.user = nil
                    self?.settingsStore?.resetSession()
                default:
                    break
                }
            }
        }
    }

    private func startMagicLinkCooldown(seconds: Int) {
        magicLinkCooldownTask?.cancel()
        magicLinkCooldownRemaining = max(0, seconds)
        magicLinkCooldownTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.magicLinkCooldownRemaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.magicLinkCooldownRemaining -= 1
                if self.magicLinkCooldownRemaining > 0 {
                    self.error = AuthFlowError.magicLinkRateLimited(seconds: self.magicLinkCooldownRemaining).localizedDescription
                }
            }
            if self.error?.contains("For security purposes") == true {
                self.error = nil
            }
        }
    }

    private static func parseMagicLinkCooldownSeconds(from message: String) -> Int? {
        let pattern = #"after\s+(\d+)\s+seconds?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(message.startIndex..., in: message)
        guard let match = regex.firstMatch(in: message, range: range),
              let secondsRange = Range(match.range(at: 1), in: message),
              let seconds = Int(message[secondsRange])
        else {
            return nil
        }
        return seconds
    }
}

private enum AuthFlowError: LocalizedError {
    case magicLinkRateLimited(seconds: Int)

    var errorDescription: String? {
        switch self {
        case .magicLinkRateLimited(let seconds):
            return "For security purposes, you can only request this after \(seconds) second\(seconds == 1 ? "" : "s")."
        }
    }
}

// MARK: - Response Types

private struct DeleteAccountResponse: Decodable {
    let scheduledAt: Date

    enum CodingKeys: String, CodingKey {
        case scheduledAt = "scheduled_at"
    }
}
