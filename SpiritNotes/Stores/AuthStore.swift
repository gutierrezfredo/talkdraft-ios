import Foundation
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

    func signOut() async throws {
        try await supabase.auth.signOut()
        isAuthenticated = false
        userId = nil
        user = nil
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
