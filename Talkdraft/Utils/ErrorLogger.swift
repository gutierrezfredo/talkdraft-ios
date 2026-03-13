import Foundation
import os
import UIKit

private let logger = Logger(subsystem: "com.pleymob.talkdraft", category: "ErrorLogger")

// MARK: - Entry

struct ErrorEntry: Codable {
    let id: UUID
    let timestamp: Date
    let type: String
    let message: String
    let context: [String: String]
    let appVersion: String
    let iosVersion: String
}

// MARK: - Logger

@MainActor
final class ErrorLogger {
    static let shared = ErrorLogger()

    private static let storageKey = "errorLog_v1"
    private static let maxEntries = 100

    private(set) var entries: [ErrorEntry] = []

    private init() {
        loadEntries()
    }

    /// Log an error to the local ring buffer and send to Supabase asynchronously.
    /// - Parameters:
    ///   - type: A short snake_case identifier (e.g. "transcription_failed")
    ///   - message: Human-readable description of the error
    ///   - context: Optional metadata (note_id, duration, file_size, etc.) — no PII
    ///   - userId: The current user's UUID for Supabase attribution
    func log(type: String, message: String, context: [String: String] = [:], userId: UUID? = nil) {
        let entry = ErrorEntry(
            id: UUID(),
            timestamp: Date(),
            type: type,
            message: message,
            context: context,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            iosVersion: UIDevice.current.systemVersion
        )

        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
        saveEntries()

        logger.error("[\(type)] \(message)")

        Task { await sendToSupabase(entry, userId: userId) }
    }

    /// Formatted plain-text export for support emails and share sheets.
    func exportText(maxEntries: Int = 50) -> String {
        let header = "=== Talkdraft Diagnostic Log ===\nGenerated: \(Date().formatted())\n\n"
        let body = entries.prefix(maxEntries).map { entry in
            var line = "[\(entry.timestamp.formatted(date: .numeric, time: .standard))] [\(entry.type)]\n  \(entry.message)"
            if !entry.context.isEmpty {
                let ctx = entry.context.map { "  \($0.key): \($0.value)" }.sorted().joined(separator: "\n")
                line += "\n\(ctx)"
            }
            return line
        }.joined(separator: "\n\n")
        return header + (body.isEmpty ? "No errors logged." : body)
    }

    // MARK: - Private

    private func saveEntries() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func loadEntries() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([ErrorEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func sendToSupabase(_ entry: ErrorEntry, userId: UUID?) async {
        struct Payload: Encodable {
            let userId: UUID?
            let errorType: String
            let message: String
            let context: [String: String]?
            let appVersion: String
            let iosVersion: String

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case errorType = "error_type"
                case message
                case context
                case appVersion = "app_version"
                case iosVersion = "ios_version"
            }
        }

        let payload = Payload(
            userId: userId,
            errorType: entry.type,
            message: entry.message,
            context: entry.context.isEmpty ? nil : entry.context,
            appVersion: entry.appVersion,
            iosVersion: entry.iosVersion
        )

        do {
            try await supabase.from("error_logs").insert(payload).execute()
        } catch {
            // Never let logging failures surface to the user
            logger.warning("ErrorLogger: failed to send to Supabase — \(error)")
        }
    }
}
