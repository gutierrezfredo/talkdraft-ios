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
    var userId: UUID?
    var user: Profile?
    var error: String?

    private var authListener: Task<Void, Never>?
    private var currentNonce: String?

    func initialize() async {
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

    func signIn(email: String, password: String) async throws {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let session = try await supabase.auth.signIn(
                email: email.trimmingCharacters(in: .whitespaces),
                password: password
            )
            await handleSession(session)
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    func signUp(email: String, password: String) async throws {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let response = try await supabase.auth.signUp(
                email: email.trimmingCharacters(in: .whitespaces),
                password: password
            )
            if let session = response.session {
                await handleSession(session)
            }
        } catch {
            self.error = error.localizedDescription
            throw error
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
        try await supabase.auth.signOut()
        isAuthenticated = false
        userId = nil
        user = nil
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
            let profile: Profile = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            user = profile
        } catch {
            // Profile may not exist yet (new signup) — create one
            let newProfile = Profile(
                id: userId,
                displayName: nil,
                plan: .free,
                createdAt: Date(),
                deletionScheduledAt: nil,
                language: nil
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
                default:
                    break
                }
            }
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
