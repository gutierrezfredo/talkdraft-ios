import Foundation
import AVFoundation
import Observation
import os
import Supabase
import UIKit

private let logger = Logger(subsystem: "com.pleymob.talkdraft", category: "NoteStore")
typealias NoteUpsertExecutor = @MainActor (Note) async throws -> Void
typealias AudioDeleteExecutor = @MainActor (String) async throws -> Void
typealias NoteHardDeleteExecutor = @MainActor (PendingHardDelete) async throws -> Void
typealias TranscriptionConnectivityProbe = @MainActor () async throws -> Void
typealias TranscriptionUploadExecutor = @MainActor (TranscriptionUploadRequest) async throws -> TranscriptionResult
typealias AITitleExecutor = @MainActor (String, String?) async throws -> String

struct PendingHardDelete: Codable, Sendable {
    let noteId: UUID
    let remoteAudioPath: String?
}

struct TranscriptionUploadRequest: Sendable {
    let audioData: Data
    let fileName: String
    let language: String?
    let userId: UUID?
    let customDictionary: [String]
    let whisperData: Data?
    let whisperFileName: String?
    let multiSpeaker: Bool
}

enum TranscriptionWorkflowError: LocalizedError {
    case timedOut(seconds: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .timedOut(let seconds):
            "Transcription timed out after \(Int(seconds)) seconds"
        }
    }
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

private struct NoteSyncPayload: Encodable {
    let id: UUID
    let userId: UUID?
    var categoryId: UUID?
    var title: String?
    var content: String
    var originalContent: String?
    var activeRewriteId: UUID?
    var source: Note.NoteSource
    var language: String?
    var audioUrl: String?
    var durationSeconds: Int?
    var speakerNames: [String: String]?
    let createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case categoryId = "category_id"
        case title, content
        case originalContent = "original_content"
        case activeRewriteId = "active_rewrite_id"
        case source, language
        case audioUrl = "audio_url"
        case durationSeconds = "duration_seconds"
        case speakerNames = "speaker_names"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(from note: Note) {
        self.id = note.id
        self.userId = note.userId
        self.categoryId = note.categoryId
        self.title = note.title
        self.content = note.content
        self.originalContent = note.originalContent
        self.activeRewriteId = note.activeRewriteId
        self.source = note.source
        self.language = note.language
        self.audioUrl = NoteStore.remoteAudioURL(for: note.audioUrl)
        self.durationSeconds = note.durationSeconds
        self.speakerNames = note.speakerNames
        self.createdAt = note.createdAt
        self.updatedAt = note.updatedAt
        self.deletedAt = note.deletedAt
    }
}

@MainActor
@Observable
final class NoteStore {
    var notes: [Note] = []
    var deletedNotes: [Note] = []
    var categories: [Category] = []
    var rewritesCache: [UUID: [NoteRewrite]] = [:]
    var selectedCategoryId: UUID?
    var isLoading = false
    var hasInitiallyLoaded = false
    var lastError: String?
    var generatingTitleIds: Set<UUID> = []
    var activeTranscriptionIds: Set<UUID> = []
    var rewriteJobsByNoteId: [UUID: NoteRewriteJob] = [:]
    var activeRewriteIds: Set<UUID> = []
    var rewriteLabelsByNoteId: [UUID: String] = [:]
    var rewriteErrorsByNoteId: [UUID: String] = [:]
    var localVoiceBodyStates: [UUID: NoteBodyState]
    var pendingNoteUpserts: [UUID: Note]
    var pendingHardDeletes: [UUID: PendingHardDelete]
    var pendingTitleGenerationIds: Set<UUID>
    let persistsLocalVoiceBodyStates: Bool
    let persistsPendingNoteUpserts: Bool
    let persistsPendingHardDeletes: Bool
    let persistsPendingTitleGenerations: Bool
    @ObservationIgnored let noteSyncDebounceDuration: Duration
    @ObservationIgnored let noteUpsertExecutor: NoteUpsertExecutor
    @ObservationIgnored let audioDeleteExecutor: AudioDeleteExecutor
    @ObservationIgnored let hardDeleteExecutor: NoteHardDeleteExecutor
    @ObservationIgnored let transcriptionConnectivityProbe: TranscriptionConnectivityProbe
    @ObservationIgnored let transcriptionUploadExecutor: TranscriptionUploadExecutor
    @ObservationIgnored let aiTitleExecutor: AITitleExecutor
    @ObservationIgnored var pendingNoteSyncTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored var pendingNoteSyncTokens: [UUID: UUID] = [:]
    @ObservationIgnored var pendingHardDeleteTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored var rewriteJobPollingTask: Task<Void, Never>?
    @ObservationIgnored var rewriteJobPollingToken: UUID?
    @ObservationIgnored var attemptedRewriteTriggerIds: Set<UUID> = []
    @ObservationIgnored var isRefreshingRewriteJobs = false
    var currentSessionUserId: UUID?
    var noteSyncRevisions: [UUID: Int] = [:]
    var categorySyncRevisions: [UUID: Int] = [:]

    init(
        localVoiceBodyStates: [UUID: NoteBodyState]? = nil,
        persistsLocalVoiceBodyStates: Bool = true,
        pendingNoteUpserts: [UUID: Note]? = nil,
        persistsPendingNoteUpserts: Bool = true,
        pendingHardDeletes: [UUID: PendingHardDelete]? = nil,
        persistsPendingHardDeletes: Bool = true,
        pendingTitleGenerationIds: Set<UUID>? = nil,
        persistsPendingTitleGenerations: Bool = true,
        noteSyncDebounceDuration: Duration = .milliseconds(700),
        noteUpsertExecutor: NoteUpsertExecutor? = nil,
        audioDeleteExecutor: AudioDeleteExecutor? = nil,
        hardDeleteExecutor: NoteHardDeleteExecutor? = nil,
        transcriptionConnectivityProbe: TranscriptionConnectivityProbe? = nil,
        transcriptionUploadExecutor: TranscriptionUploadExecutor? = nil,
        aiTitleExecutor: AITitleExecutor? = nil
    ) {
        self.persistsLocalVoiceBodyStates = persistsLocalVoiceBodyStates
        self.persistsPendingNoteUpserts = persistsPendingNoteUpserts
        self.persistsPendingHardDeletes = persistsPendingHardDeletes
        self.persistsPendingTitleGenerations = persistsPendingTitleGenerations
        self.noteSyncDebounceDuration = noteSyncDebounceDuration
        self.noteUpsertExecutor = noteUpsertExecutor ?? { note in
            try await supabase
                .from("notes")
                .upsert(NoteSyncPayload(from: note))
                .execute()
        }
        let resolvedAudioDeleteExecutor = audioDeleteExecutor ?? { audioPath in
            do {
                try await supabase.storage
                    .from("audio")
                    .remove(paths: [audioPath])
            } catch let error as StorageError {
                if let statusCode = error.statusCode.flatMap(Int.init),
                   [400, 404].contains(statusCode) {
                    logger.notice("Remote audio already missing at \(audioPath, privacy: .public)")
                    return
                }
                throw error
            }
        }
        self.audioDeleteExecutor = resolvedAudioDeleteExecutor
        self.hardDeleteExecutor = hardDeleteExecutor ?? { pendingDelete in
            if let remoteAudioPath = pendingDelete.remoteAudioPath {
                try await resolvedAudioDeleteExecutor(remoteAudioPath)
            }
            try await supabase
                .from("notes")
                .delete()
                .eq("id", value: pendingDelete.noteId)
                .execute()
        }
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
                userId: request.userId,
                customDictionary: request.customDictionary,
                whisperData: request.whisperData,
                whisperFileName: request.whisperFileName,
                multiSpeaker: request.multiSpeaker
            )
        }
        self.aiTitleExecutor = aiTitleExecutor ?? { content, language in
            try await AIService.generateTitle(for: content, language: language)
        }
        self.localVoiceBodyStates = localVoiceBodyStates ?? [:]
        self.pendingNoteUpserts = pendingNoteUpserts ?? [:]
        self.pendingHardDeletes = pendingHardDeletes ?? [:]
        self.pendingTitleGenerationIds = pendingTitleGenerationIds ?? []
    }

    // MARK: - Multi-Speaker Format

    /// Converts Groq's `[Speaker N]: text` format to the display format:
    ///   Speaker N
    ///   text
    ///
    /// Returns the formatted content and an initial speakerNames dict, or nil if not multi-speaker.
    static func formatMultiSpeakerTranscript(_ text: String) -> (content: String, speakerNames: [String: String]?) {
        guard text.contains("[Speaker") else { return (text, nil) }
        let pattern = /\[([^\]]+)\]: ?/
        var seen: [String] = []
        var result = text.replacing(pattern) { match in
            let key = String(match.output.1)
            if !seen.contains(key) { seen.append(key) }
            return "\n\n\(key)\n"
        }
        // Collapse 3+ consecutive newlines to 2, then trim edges
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        result = result.trimmingCharacters(in: .newlines)
        let speakerNames = seen.isEmpty ? nil : Dictionary(uniqueKeysWithValues: seen.map { ($0, $0) })
        return (result, speakerNames)
    }

    // MARK: - Local Audio Index
    // Persists noteId → local file path across app restarts.
    // Needed because note.audioUrl (from Supabase) is null until transcription succeeds,
    // so after a restart the app loses the reference to the local recording file.

    static let localAudioKey = "localAudioPaths"
    static let localVoiceBodyStateKey = "localVoiceBodyStates"
    static let pendingNoteUpsertsKey = "pendingNoteUpserts"
    static let pendingHardDeletesKey = "pendingHardDeletes"
    static let pendingTitleGenerationKey = "pendingTitleGenerationIds"

    static func scopedKey(_ base: String, userId: UUID?) -> String {
        "\(base).\(userId?.uuidString ?? "anonymous")"
    }

    func registerLocalAudio(_ url: URL, for noteId: UUID) {
        let key = Self.scopedKey(Self.localAudioKey, userId: currentSessionUserId)
        var index = (
            UserDefaults.standard.dictionary(forKey: key) as? [String: String]
        ) ?? (
            UserDefaults.standard.dictionary(forKey: Self.localAudioKey) as? [String: String]
        ) ?? [:]
        index[noteId.uuidString] = url.absoluteString
        UserDefaults.standard.set(index, forKey: key)
    }

    func unregisterLocalAudio(for noteId: UUID) {
        let key = Self.scopedKey(Self.localAudioKey, userId: currentSessionUserId)
        var index = (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
        index.removeValue(forKey: noteId.uuidString)
        UserDefaults.standard.set(index, forKey: key)
    }

    /// Returns the local audio file URL for a note, checking note.audioUrl first,
    /// then falling back to the persisted UserDefaults index.
    func localAudioFileURL(for noteId: UUID, audioUrl: String?) -> URL? {
        // Primary: note's own audioUrl (only valid if it's a local file)
        if let urlString = audioUrl {
            if let url = URL(string: urlString), url.isFileURL, FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            if urlString.hasPrefix("/") {
                let url = URL(fileURLWithPath: urlString)
                if FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
            }
        }
        // Fallback: persisted index (survives app restart after failed transcription)
        let key = Self.scopedKey(Self.localAudioKey, userId: currentSessionUserId)
        if let index = (
            UserDefaults.standard.dictionary(forKey: key) as? [String: String]
        ) ?? (
            UserDefaults.standard.dictionary(forKey: Self.localAudioKey) as? [String: String]
        ),
           let storedPath = index[noteId.uuidString] {
            let url = if let fileURL = URL(string: storedPath), fileURL.isFileURL {
                fileURL
            } else {
                URL(fileURLWithPath: storedPath)
            }
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            // File gone — clean up stale entry
            unregisterLocalAudio(for: noteId)
        }
        return nil
    }

    nonisolated fileprivate static func remoteAudioURL(for audioUrl: String?) -> String? {
        guard let audioUrl else { return nil }
        if audioUrl.hasPrefix("/") {
            return nil
        }
        if let url = URL(string: audioUrl), url.isFileURL {
            return nil
        }
        return audioUrl
    }

    nonisolated static func remoteAudioPath(for audioUrl: String?) -> String? {
        guard let remoteAudioURL = remoteAudioURL(for: audioUrl) else { return nil }

        if let url = URL(string: remoteAudioURL), url.scheme != nil {
            let supportedPrefixes = [
                "/storage/v1/object/public/audio/",
                "/storage/v1/object/sign/audio/",
                "/storage/v1/object/authenticated/audio/",
                "/storage/v1/object/audio/"
            ]

            for prefix in supportedPrefixes {
                guard let range = url.path.range(of: prefix) else { continue }
                let rawPath = String(url.path[range.upperBound...])
                guard !rawPath.isEmpty else { return nil }
                return rawPath.removingPercentEncoding ?? rawPath
            }

            return nil
        }

        let rawPath = remoteAudioURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return rawPath.isEmpty ? nil : rawPath
    }

    func deleteRemoteAudioIfNeeded(for audioUrl: String?, noteId: UUID, reason: String) async {
        guard let remoteAudioPath = Self.remoteAudioPath(for: audioUrl) else { return }

        do {
            try await audioDeleteExecutor(remoteAudioPath)
        } catch {
            logger.error(
                "Failed to delete remote audio for note \(noteId) during \(reason, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func activeRewrite(for note: Note) -> NoteRewrite? {
        guard let rewriteId = note.activeRewriteId else { return nil }
        return rewritesCache[note.id]?.first { $0.id == rewriteId }
    }

    func resolvedContent(for note: Note) -> String {
        activeRewrite(for: note)?.content ?? note.content
    }

    func bodyState(for note: Note) -> NoteBodyState {
        localVoiceBodyStates[note.id] ?? NoteBodyState(content: resolvedContent(for: note), source: note.source)
    }

    func displayContent(for note: Note) -> String {
        if let placeholder = bodyState(for: note).placeholderContent,
           activeRewrite(for: note) == nil {
            return placeholder
        }
        return resolvedContent(for: note)
    }

    func normalizeLocalVoiceNote(_ note: Note) -> Note {
        guard note.source == .voice else {
            setLocalVoiceBodyState(nil, for: note.id)
            return note
        }

        let inferredState = NoteBodyState(content: note.content, source: note.source)
        var normalized = note
        if inferredState.isTransientTranscriptionState {
            setLocalVoiceBodyState(inferredState, for: note.id)
            normalized.content = ""
            return normalized
        }

        if note.content.isEmpty,
           let existing = localVoiceBodyStates[note.id],
           existing.isTransientTranscriptionState {
            normalized.content = ""
            return normalized
        }

        setLocalVoiceBodyState(nil, for: note.id)
        return normalized
    }

    func setNoteBodyState(id: UUID, state: NoteBodyState) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        if notes[index].source == .voice, state.isTransientTranscriptionState {
            notes[index].content = ""
        }
        notes[index].updatedAt = Date()
        setLocalVoiceBodyState(state == .content ? nil : state, for: id)
    }

    func repairOrphanedTranscriptions() {
        let now = Date()
        for index in notes.indices {
            let note = notes[index]
            guard note.source == .voice,
                  bodyState(for: note) == .transcribing,
                  !activeTranscriptionIds.contains(note.id)
            else { continue }

            let hasLocalAudio = localAudioFileURL(for: note.id, audioUrl: note.audioUrl) != nil
            let isStale = now.timeIntervalSince(note.updatedAt) >= transcriptionRepairThresholdSeconds(for: note)
            guard hasLocalAudio || isStale else { continue }

            logger.warning("Repairing orphaned transcription state for \(note.id); localAudio=\(hasLocalAudio) stale=\(isStale)")
            setNoteBodyState(id: note.id, state: .transcriptionFailed)
        }
    }

    /// Retry notes that are explicitly waiting for connectivity.
    /// Failed notes stay failed until the user retries them manually.
    func retryWaitingNotes(language: String?, userId: UUID?, customDictionary: [String] = []) {
        let waiting = notes.filter { bodyState(for: $0) == .waitingForConnection }
        guard !waiting.isEmpty else { return }

        for note in waiting {
            guard let url = localAudioFileURL(for: note.id, audioUrl: note.audioUrl) else {
                logger.warning("Waiting transcription note \(note.id) is missing local audio; marking it as failed")
                setNoteBodyState(id: note.id, state: .transcriptionFailed)
                continue
            }
            setNoteBodyState(id: note.id, state: .transcribing)
            transcribeNote(id: note.id, audioFileURL: url, language: language, userId: userId, customDictionary: customDictionary)
        }
    }

    var filteredNotes: [Note] {
        guard let categoryId = selectedCategoryId else { return notes }
        return notes.filter { $0.categoryId == categoryId }
    }

    // MARK: - Fetch

    static func importedAudioDurationSeconds(for url: URL) async -> Int? {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            return seconds.isFinite ? Int(seconds) : nil
        } catch {
            return nil
        }
    }

    static func copyImportedAudio(from sourceURL: URL) throws -> URL {
        let recordingsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

        let fileName = if sourceURL.pathExtension.isEmpty {
            UUID().uuidString
        } else {
            "\(UUID().uuidString).\(sourceURL.pathExtension)"
        }
        let destinationURL = recordingsDir.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    func refresh() async {
        isLoading = true
        defer {
            isLoading = false
            hasInitiallyLoaded = true
        }

        async let fetchedNotes: () = fetchNotes()
        async let fetchedCategories: () = fetchCategories()
        // Await independently so a failure in one doesn't cancel the other.
        // Tuple await propagates the first error and implicitly cancels siblings.
        try? await fetchedNotes
        try? await fetchedCategories
        await refreshRewriteJobs()
        retryPendingTitleGenerations()
    }

    func fetchNotes() async throws {
        guard let userId = currentSessionUserId else {
            pruneLocalVoiceBodyStates(validNoteIds: [])
            notes = mergedPendingNotes(with: [])
            deletedNotes = []
            return
        }

        let fetched: [Note] = try await supabase
            .from("notes")
            .select()
            .eq("user_id", value: userId)
            .is("deleted_at", value: nil)
            .order("created_at", ascending: false)
            .execute()
            .value
        pruneLocalVoiceBodyStates(validNoteIds: Set(fetched.map(\.id)))
        notes = mergedPendingNotes(with: fetched)
        repairOrphanedTranscriptions()

        let deleted: [Note] = try await supabase
            .from("notes")
            .select()
            .eq("user_id", value: userId)
            .not("deleted_at", operator: .is, value: Bool?.none)
            .order("deleted_at", ascending: false)
            .execute()
            .value
        var mergedDeleted = Dictionary(uniqueKeysWithValues: deleted.map { ($0.id, $0) })
        for id in pendingHardDeletes.keys {
            mergedDeleted.removeValue(forKey: id)
        }
        for note in pendingDeletedNotesById.values {
            mergedDeleted[note.id] = note
        }
        deletedNotes = mergedDeleted.values.sorted { lhs, rhs in
            switch (lhs.deletedAt, rhs.deletedAt) {
            case let (left?, right?) where left != right:
                return left > right
            case (nil, .some):
                return false
            case (.some, nil):
                return true
            default:
                return lhs.updatedAt > rhs.updatedAt
            }
        }

        // Auto-purge notes deleted more than 30 days ago
        await purgeExpiredNotes()
        retryPendingNoteUpserts()
        retryPendingHardDeletes()
    }

    func fetchCategories() async throws {
        guard let userId = currentSessionUserId else {
            categories = []
            return
        }

        let fetched: [Category] = try await supabase
            .from("categories")
            .select()
            .eq("user_id", value: userId)
            .order("sort_order", ascending: true)
            .execute()
            .value
        categories = fetched
    }


}
