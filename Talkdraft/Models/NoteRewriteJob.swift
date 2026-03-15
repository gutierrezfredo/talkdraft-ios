import Foundation

enum NoteRewriteJobStatus: String, Codable, Sendable {
    case queued
    case processing
    case completed
    case failed
    case completedDetached = "completed_detached"
    case canceled

    var isActive: Bool {
        switch self {
        case .queued, .processing:
            true
        case .completed, .failed, .completedDetached, .canceled:
            false
        }
    }
}

struct NoteRewriteJob: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let noteId: UUID
    let userId: UUID
    var status: NoteRewriteJobStatus
    var sourceContent: String
    var titleSnapshot: String?
    var tone: String?
    var toneLabel: String?
    var toneEmoji: String?
    var instructions: String?
    let noteUpdatedAtSnapshot: Date
    var rewriteId: UUID?
    var errorMessage: String?
    let createdAt: Date
    var startedAt: Date?
    var finishedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case noteId = "note_id"
        case userId = "user_id"
        case status
        case sourceContent = "source_content"
        case titleSnapshot = "title_snapshot"
        case tone
        case toneLabel = "tone_label"
        case toneEmoji = "tone_emoji"
        case instructions
        case noteUpdatedAtSnapshot = "note_updated_at_snapshot"
        case rewriteId = "rewrite_id"
        case errorMessage = "error_message"
        case createdAt = "created_at"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
    }

    var displayLabel: String {
        if let emoji = toneEmoji, let label = toneLabel {
            return "\(emoji) \(label)"
        } else if let label = toneLabel {
            return label
        } else if let instructions, !instructions.isEmpty {
            let preview = String(instructions.prefix(30))
            return instructions.count > 30 ? "\(preview)…" : preview
        }
        return "Rewriting…"
    }
}

struct RewriteJobCreatePayload: Encodable {
    let noteId: UUID
    let userId: UUID
    let status: NoteRewriteJobStatus
    let sourceContent: String
    let titleSnapshot: String?
    let tone: String?
    let toneLabel: String?
    let toneEmoji: String?
    let instructions: String?
    let noteUpdatedAtSnapshot: Date

    enum CodingKeys: String, CodingKey {
        case noteId = "note_id"
        case userId = "user_id"
        case status
        case sourceContent = "source_content"
        case titleSnapshot = "title_snapshot"
        case tone
        case toneLabel = "tone_label"
        case toneEmoji = "tone_emoji"
        case instructions
        case noteUpdatedAtSnapshot = "note_updated_at_snapshot"
    }
}

struct RewriteJobTriggerPayload: Encodable {
    let jobId: UUID
}

struct RewriteJobTriggerResponse: Decodable {
    let ok: Bool
    let status: NoteRewriteJobStatus
}
