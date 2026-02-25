import Foundation
import Observation

@MainActor @Observable
final class AuthStore {
    var isAuthenticated = false
    var isLoading = false
    var user: Profile?

    func initialize() async {
        // TODO: Check Supabase session
    }

    func signIn(email: String, password: String) async throws {
        // TODO: Supabase auth sign in
    }

    func signUp(email: String, password: String) async throws {
        // TODO: Supabase auth sign up
    }

    func signOut() async throws {
        // TODO: Supabase auth sign out
    }
}
