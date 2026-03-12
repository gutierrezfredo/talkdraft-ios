import Foundation

enum NoteBodyState: Equatable, Sendable {
    case content
    case transcribing
    case waitingForConnection
    case transcriptionFailed

    init(content: String, source: Note.NoteSource? = nil) {
        guard source == nil || source == .voice else {
            self = .content
            return
        }

        switch content {
        case NoteBodyState.transcribingPlaceholder:
            self = .transcribing
        case NoteBodyState.waitingForConnectionPlaceholder:
            self = .waitingForConnection
        case NoteBodyState.transcriptionFailedPlaceholder:
            self = .transcriptionFailed
        default:
            self = .content
        }
    }

    static let recordingPlaceholder = "Recording…"
    static let transcribingPlaceholder = "Transcribing…"
    static let waitingForConnectionPlaceholder = "Waiting for connection…"
    static let transcriptionFailedPlaceholder = "Transcription failed — tap to edit"

    var placeholderContent: String? {
        switch self {
        case .content:
            return nil
        case .transcribing:
            return Self.transcribingPlaceholder
        case .waitingForConnection:
            return Self.waitingForConnectionPlaceholder
        case .transcriptionFailed:
            return Self.transcriptionFailedPlaceholder
        }
    }

    var isTransientTranscriptionState: Bool {
        switch self {
        case .content:
            return false
        case .transcribing, .waitingForConnection, .transcriptionFailed:
            return true
        }
    }
}

struct Note: Identifiable, Codable, Hashable, Sendable {
    var bodyState: NoteBodyState {
        NoteBodyState(content: content, source: source)
    }

    let id: UUID
    var userId: UUID?
    var categoryId: UUID?
    var captureId: UUID?
    var title: String?
    var content: String
    var originalContent: String?
    var activeRewriteId: UUID?
    var source: NoteSource
    var language: String?
    var audioUrl: String?
    var durationSeconds: Int?
    var speakerNames: [String: String]?
    let createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

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
        case activeRewriteId = "active_rewrite_id"
        case source
        case language
        case audioUrl = "audio_url"
        case durationSeconds = "duration_seconds"
        case speakerNames = "speaker_names"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}
