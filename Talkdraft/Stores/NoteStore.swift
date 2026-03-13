import AVFoundation
import Foundation
import Observation
import os
import Supabase
import UIKit

let noteStoreLogger = Logger(subsystem: "com.pleymob.talkdraft", category: "NoteStore")
typealias TranscriptionConnectivityProbe = @MainActor () async throws -> Void
typealias TranscriptionUploadExecutor = @MainActor (TranscriptionUploadRequest) async throws -> TranscriptionResult
typealias AITitleExecutor = @MainActor (String, String?) async throws -> String

struct TranscriptionUploadRequest: Sendable {
    let audioData: Data
    let fileName: String
    let language: String?
    let userId: UUID?
}

enum ImportedAudioNoteError: LocalizedError {
    case accessDenied
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied, .copyFailed:
            "Failed to import audio file"
        }
    }
}

struct NoteUpdate: Encodable {
    var categoryId: UUID?
    var title: String?
    var content: String
    var originalContent: String?
    var source: Note.NoteSource
    var language: String?
    var audioUrl: String?
    var durationSeconds: Int?
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case title, content
        case originalContent = "original_content"
        case source, language
        case audioUrl = "audio_url"
        case durationSeconds = "duration_seconds"
        case updatedAt = "updated_at"
    }

    init(from note: Note) {
        self.categoryId = note.categoryId
        self.title = note.title
        self.content = note.content
        self.originalContent = note.originalContent
        self.source = note.source
        self.language = note.language
        self.audioUrl = note.audioUrl
        self.durationSeconds = note.durationSeconds
        self.updatedAt = note.updatedAt
    }
}

@MainActor
@Observable
final class NoteStore {
    var notes: [Note] = []
    var deletedNotes: [Note] = []
    var categories: [Category] = []
    var selectedCategoryId: UUID?
    var isLoading = false
    var lastError: String?
    @ObservationIgnored let transcriptionConnectivityProbe: TranscriptionConnectivityProbe
    @ObservationIgnored let transcriptionUploadExecutor: TranscriptionUploadExecutor
    @ObservationIgnored let aiTitleExecutor: AITitleExecutor

    init(
        transcriptionConnectivityProbe: TranscriptionConnectivityProbe? = nil,
        transcriptionUploadExecutor: TranscriptionUploadExecutor? = nil,
        aiTitleExecutor: AITitleExecutor? = nil
    ) {
        self.transcriptionConnectivityProbe = transcriptionConnectivityProbe ?? {
            var probe = URLRequest(url: AppConfig.supabaseUrl.appendingPathComponent("rest/v1/"))
            probe.httpMethod = "GET"
            probe.timeoutInterval = 15
            probe.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            probe.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
            let (_, response) = try await URLSession.shared.data(for: probe)
            guard let http = response as? HTTPURLResponse, http.statusCode < 500 else {
                throw URLError(.cannotConnectToHost)
            }
        }
        self.transcriptionUploadExecutor = transcriptionUploadExecutor ?? { request in
            let service = TranscriptionService()
            return try await service.transcribe(
                audioData: request.audioData,
                fileName: request.fileName,
                language: request.language,
                userId: request.userId
            )
        }
        self.aiTitleExecutor = aiTitleExecutor ?? { content, language in
            try await AIService.generateTitle(for: content, language: language)
        }
    }

    var filteredNotes: [Note] {
        guard let categoryId = selectedCategoryId else { return notes }
        return notes.filter { $0.categoryId == categoryId }
    }
}

// MARK: - Partial Update Models

struct NoteCategoryUpdate: Encodable {
    let categoryId: UUID?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case updatedAt = "updated_at"
    }
}

struct SoftDeleteUpdate: Encodable {
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case deletedAt = "deleted_at"
    }
}

struct CategorySortUpdate: Encodable {
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case sortOrder = "sort_order"
    }
}
