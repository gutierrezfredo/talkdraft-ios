import Foundation
import Supabase

enum AppConfig {
    static let supabaseUrl = URL(string: "https://tftwvuduzzymqxdvkwwd.supabase.co")!
    static let supabaseAnonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRmdHd2dWR1enp5bXF4ZHZrd3dkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE2NTA3MTAsImV4cCI6MjA4NzIyNjcxMH0.LyFLwFsWTmpa55lFpTi0Pbk-FAuJDvJ5W5vlHCjb1sA"
}

let supabase = SupabaseClient(
    supabaseURL: AppConfig.supabaseUrl,
    supabaseKey: AppConfig.supabaseAnonKey
)
