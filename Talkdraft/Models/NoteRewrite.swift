import Foundation

struct NoteRewrite: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let noteId: UUID
    var userId: UUID?
    var tone: String?
    var toneLabel: String?
    var toneEmoji: String?
    var instructions: String?
    var content: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case noteId = "note_id"
        case userId = "user_id"
        case tone
        case toneLabel = "tone_label"
        case toneEmoji = "tone_emoji"
        case instructions
        case content
        case createdAt = "created_at"
    }

    var displayLabel: String {
        if let emoji = toneEmoji, let label = toneLabel {
            return "\(emoji) \(label)"
        } else if let label = toneLabel {
            return label
        } else if let instructions {
            let preview = String(instructions.prefix(30))
            return instructions.count > 30 ? "\(preview)…" : preview
        }
        return "Rewrite"
    }
}
