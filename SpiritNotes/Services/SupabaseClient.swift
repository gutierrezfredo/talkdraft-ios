import Foundation
import Supabase

enum AppConfig {
    static let supabaseUrl = URL(string: "YOUR_SUPABASE_URL")!
    static let supabaseAnonKey = "YOUR_SUPABASE_ANON_KEY"
}

let supabase = SupabaseClient(
    supabaseURL: AppConfig.supabaseUrl,
    supabaseKey: AppConfig.supabaseAnonKey
)
