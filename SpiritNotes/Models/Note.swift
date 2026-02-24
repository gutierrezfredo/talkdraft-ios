import Foundation

struct Note: Identifiable, Codable, Hashable {
    let id: UUID
    var categoryId: UUID?
    var captureId: UUID?
    var title: String?
    var content: String
    var originalContent: String?
    var source: NoteSource
    var language: String?
    var audioUrl: String?
    var durationSeconds: Double?
    let createdAt: Date
    var updatedAt: Date

    enum NoteSource: String, Codable {
        case voice
        case text
    }
}
