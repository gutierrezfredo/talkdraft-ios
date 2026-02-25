import Foundation

struct Note: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var userId: UUID?
    var categoryId: UUID?
    var captureId: UUID?
    var title: String?
    var content: String
    var originalContent: String?
    var source: NoteSource
    var language: String?
    var audioUrl: String?
    var durationSeconds: Int?
    let createdAt: Date
    var updatedAt: Date

    enum NoteSource: String, Codable, Sendable {
        case voice
        case text
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case categoryId = "category_id"
        case captureId = "capture_id"
        case title
        case content
        case originalContent = "original_content"
        case source
        case language
        case audioUrl = "audio_url"
        case durationSeconds = "duration_seconds"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
