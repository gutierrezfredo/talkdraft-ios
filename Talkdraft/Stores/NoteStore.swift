import Foundation
import AVFoundation
import Observation
import os
import Supabase
import UIKit

private let logger = Logger(subsystem: "com.pleymob.talkdraft", category: "NoteStore")
typealias NoteUpsertExecutor = @MainActor (Note) async throws -> Void

private enum TranscriptionWorkflowError: LocalizedError {
    case timedOut(seconds: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .timedOut(let seconds):
            "Transcription timed out after \(Int(seconds)) seconds"
        }
    }
}

private enum ImportedAudioNoteError: LocalizedError {
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
    var localVoiceBodyStates: [UUID: NoteBodyState]
    var pendingNoteUpserts: [UUID: Note]
    let persistsLocalVoiceBodyStates: Bool
    let persistsPendingNoteUpserts: Bool
    @ObservationIgnored private let noteSyncDebounceDuration: Duration
    @ObservationIgnored private let noteUpsertExecutor: NoteUpsertExecutor
    @ObservationIgnored private var pendingNoteSyncTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var pendingNoteSyncTokens: [UUID: UUID] = [:]
    private var currentSessionUserId: UUID?
    private var noteSyncRevisions: [UUID: Int] = [:]
    private var categorySyncRevisions: [UUID: Int] = [:]

    init(
        localVoiceBodyStates: [UUID: NoteBodyState]? = nil,
        persistsLocalVoiceBodyStates: Bool = true,
        pendingNoteUpserts: [UUID: Note]? = nil,
        persistsPendingNoteUpserts: Bool = true,
        noteSyncDebounceDuration: Duration = .milliseconds(700),
        noteUpsertExecutor: NoteUpsertExecutor? = nil
    ) {
        self.persistsLocalVoiceBodyStates = persistsLocalVoiceBodyStates
        self.persistsPendingNoteUpserts = persistsPendingNoteUpserts
        self.noteSyncDebounceDuration = noteSyncDebounceDuration
        self.noteUpsertExecutor = noteUpsertExecutor ?? { note in
            try await supabase
                .from("notes")
                .upsert(NoteSyncPayload(from: note))
                .execute()
        }
        self.localVoiceBodyStates = localVoiceBodyStates ?? [:]
        self.pendingNoteUpserts = pendingNoteUpserts ?? [:]
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

    private static let localAudioKey = "localAudioPaths"
    private static let localVoiceBodyStateKey = "localVoiceBodyStates"
    private static let pendingNoteUpsertsKey = "pendingNoteUpserts"

    private static func scopedKey(_ base: String, userId: UUID?) -> String {
        "\(base).\(userId?.uuidString ?? "anonymous")"
    }

    private static func loadLocalVoiceBodyStates(for userId: UUID?) -> [UUID: NoteBodyState] {
        let scopedKey = scopedKey(Self.localVoiceBodyStateKey, userId: userId)
        let raw = (
            UserDefaults.standard.dictionary(forKey: scopedKey) as? [String: String]
        ) ?? (
            UserDefaults.standard.dictionary(forKey: Self.localVoiceBodyStateKey) as? [String: String]
        ) ?? [:]
        return raw.reduce(into: [:]) { result, item in
            guard let id = UUID(uuidString: item.key), let state = NoteBodyState(storageKey: item.value) else { return }
            result[id] = state
        }
    }

    private func persistLocalVoiceBodyStates() {
        guard persistsLocalVoiceBodyStates else { return }
        let raw = localVoiceBodyStates.reduce(into: [String: String]()) { result, item in
            guard let key = item.value.storageKey else { return }
            result[item.key.uuidString] = key
        }
        UserDefaults.standard.set(raw, forKey: Self.scopedKey(Self.localVoiceBodyStateKey, userId: currentSessionUserId))
    }

    private static func loadPendingNoteUpserts(for userId: UUID?) -> [UUID: Note] {
        guard let data = UserDefaults.standard.data(forKey: scopedKey(Self.pendingNoteUpsertsKey, userId: userId)),
              let notes = try? JSONDecoder().decode([Note].self, from: data)
        else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
    }

    private func persistPendingNoteUpserts() {
        guard persistsPendingNoteUpserts else { return }
        let notes = pendingNoteUpserts.values.sorted { $0.createdAt > $1.createdAt }
        let key = Self.scopedKey(Self.pendingNoteUpsertsKey, userId: currentSessionUserId)
        if notes.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(notes) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func setLocalVoiceBodyState(_ state: NoteBodyState?, for noteId: UUID) {
        if let state, state != .content {
            localVoiceBodyStates[noteId] = state
        } else {
            localVoiceBodyStates.removeValue(forKey: noteId)
        }
        persistLocalVoiceBodyStates()
    }

    private func pruneLocalVoiceBodyStates(validNoteIds: Set<UUID>) {
        let filtered = localVoiceBodyStates.filter { validNoteIds.contains($0.key) }
        guard filtered.count != localVoiceBodyStates.count else { return }
        localVoiceBodyStates = filtered
        persistLocalVoiceBodyStates()
    }

    private func registerLocalAudio(_ url: URL, for noteId: UUID) {
        let key = Self.scopedKey(Self.localAudioKey, userId: currentSessionUserId)
        var index = (
            UserDefaults.standard.dictionary(forKey: key) as? [String: String]
        ) ?? (
            UserDefaults.standard.dictionary(forKey: Self.localAudioKey) as? [String: String]
        ) ?? [:]
        index[noteId.uuidString] = url.absoluteString
        UserDefaults.standard.set(index, forKey: key)
    }

    private func unregisterLocalAudio(for noteId: UUID) {
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

    func beginSession(userId: UUID) {
        guard currentSessionUserId != userId else { return }
        cancelAllPendingNoteSyncTasks()
        currentSessionUserId = userId
        localVoiceBodyStates = persistsLocalVoiceBodyStates ? Self.loadLocalVoiceBodyStates(for: userId) : localVoiceBodyStates
        pendingNoteUpserts = persistsPendingNoteUpserts ? Self.loadPendingNoteUpserts(for: userId) : pendingNoteUpserts
        noteSyncRevisions = [:]
        categorySyncRevisions = [:]
        notes = mergedPendingNotes(with: [])
        deletedNotes = []
        categories = []
        rewritesCache = [:]
        selectedCategoryId = nil
        lastError = nil
        hasInitiallyLoaded = false
    }

    func resetSession() {
        cancelAllPendingNoteSyncTasks()
        notes = []
        deletedNotes = []
        categories = []
        rewritesCache = [:]
        selectedCategoryId = nil
        isLoading = false
        hasInitiallyLoaded = false
        lastError = nil
        generatingTitleIds = []
        activeTranscriptionIds = []
        localVoiceBodyStates = [:]
        pendingNoteUpserts = [:]
        noteSyncRevisions = [:]
        categorySyncRevisions = [:]
        currentSessionUserId = nil
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

    private func normalizeLocalVoiceNote(_ note: Note) -> Note {
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

    private func mergedPendingNotes(with remoteNotes: [Note]) -> [Note] {
        var merged = Dictionary(uniqueKeysWithValues: remoteNotes.map { ($0.id, normalizeLocalVoiceNote($0)) })
        for note in pendingNoteUpserts.values {
            merged[note.id] = normalizeLocalVoiceNote(note)
        }
        return merged.values.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func queuePendingNoteUpsert(_ note: Note) {
        pendingNoteUpserts[note.id] = note
        persistPendingNoteUpserts()
    }

    private func clearPendingNoteUpsert(id: UUID, expectedRevision: Int?) {
        guard pendingNoteUpserts[id] != nil else { return }
        if let expectedRevision, (noteSyncRevisions[id] ?? 0) != expectedRevision {
            return
        }
        pendingNoteUpserts.removeValue(forKey: id)
        persistPendingNoteUpserts()
    }

    @discardableResult
    private func bumpNoteSyncRevision(for noteId: UUID) -> Int {
        let next = (noteSyncRevisions[noteId] ?? 0) + 1
        noteSyncRevisions[noteId] = next
        return next
    }

    @discardableResult
    private func bumpCategorySyncRevision(for categoryId: UUID) -> Int {
        let next = (categorySyncRevisions[categoryId] ?? 0) + 1
        categorySyncRevisions[categoryId] = next
        return next
    }

    private func clearPendingNoteSyncTask(id: UUID, token: UUID? = nil) {
        guard token == nil || pendingNoteSyncTokens[id] == token else { return }
        pendingNoteSyncTasks[id] = nil
        pendingNoteSyncTokens[id] = nil
    }

    private func cancelPendingNoteSyncTask(id: UUID) {
        pendingNoteSyncTasks[id]?.cancel()
        clearPendingNoteSyncTask(id: id)
    }

    private func cancelAllPendingNoteSyncTasks() {
        for task in pendingNoteSyncTasks.values {
            task.cancel()
        }
        pendingNoteSyncTasks = [:]
        pendingNoteSyncTokens = [:]
    }

    private func schedulePendingNoteUpsertSync(id: UUID, expectedRevision: Int, delay: Duration) {
        cancelPendingNoteSyncTask(id: id)
        let token = UUID()
        pendingNoteSyncTokens[id] = token
        pendingNoteSyncTasks[id] = Task { [weak self] in
            guard let self else { return }
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            await self.syncPendingNoteUpsert(id: id, expectedRevision: expectedRevision, token: token)
        }
    }

    func flushPendingNoteUpsert(id: UUID) async {
        cancelPendingNoteSyncTask(id: id)
        let expectedRevision = noteSyncRevisions[id] ?? 0
        await syncPendingNoteUpsert(id: id, expectedRevision: expectedRevision)
    }

    func flushPendingNoteUpserts() async {
        let ids = pendingNoteUpserts.values
            .sorted(by: { $0.updatedAt < $1.updatedAt })
            .map(\.id)
        for id in ids {
            await flushPendingNoteUpsert(id: id)
        }
    }

    func retryPendingNoteUpserts() {
        guard !pendingNoteUpserts.isEmpty else { return }
        for note in pendingNoteUpserts.values.sorted(by: { $0.updatedAt < $1.updatedAt }) {
            let revision = noteSyncRevisions[note.id] ?? 0
            schedulePendingNoteUpsertSync(id: note.id, expectedRevision: revision, delay: .zero)
        }
    }

    private func syncPendingNoteUpsert(id: UUID, expectedRevision: Int, token: UUID? = nil) async {
        guard let note = pendingNoteUpserts[id] else {
            clearPendingNoteSyncTask(id: id, token: token)
            return
        }

        do {
            try await noteUpsertExecutor(note)
            clearPendingNoteSyncTask(id: id, token: token)
            clearPendingNoteUpsert(id: id, expectedRevision: expectedRevision)
        } catch {
            clearPendingNoteSyncTask(id: id, token: token)
            logger.error("note upsert failed for \(id): \(error)")
        }
    }

    // MARK: - Fetch

    private static func importedAudioDurationSeconds(for url: URL) async -> Int? {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            return seconds.isFinite ? Int(seconds) : nil
        } catch {
            return nil
        }
    }

    private static func copyImportedAudio(from sourceURL: URL) throws -> URL {
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

    func importAudioNote(
        from sourceURL: URL,
        userId: UUID?,
        categoryId: UUID?,
        language: String?,
        customDictionary: [String]
    ) async throws -> Note {
        guard sourceURL.startAccessingSecurityScopedResource() else {
            throw ImportedAudioNoteError.accessDenied
        }
        defer { sourceURL.stopAccessingSecurityScopedResource() }

        let destinationURL: URL
        do {
            destinationURL = try Self.copyImportedAudio(from: sourceURL)
        } catch {
            throw ImportedAudioNoteError.copyFailed
        }

        let noteId = UUID()
        let note = Note(
            id: noteId,
            userId: userId,
            categoryId: categoryId,
            title: sourceURL.deletingPathExtension().lastPathComponent,
            content: "",
            source: .voice,
            audioUrl: destinationURL.absoluteString,
            durationSeconds: await Self.importedAudioDurationSeconds(for: destinationURL),
            createdAt: .now,
            updatedAt: .now
        )

        addNote(note)
        setNoteBodyState(id: noteId, state: .transcribing)
        transcribeNote(
            id: noteId,
            audioFileURL: destinationURL,
            language: language,
            userId: userId,
            customDictionary: customDictionary
        )
        return note
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
    }

    func fetchNotes() async throws {
        let fetched: [Note] = try await supabase
            .from("notes")
            .select()
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
            .not("deleted_at", operator: .is, value: Bool?.none)
            .order("deleted_at", ascending: false)
            .execute()
            .value
        deletedNotes = deleted

        // Auto-purge notes deleted more than 30 days ago
        await purgeExpiredNotes()
        retryPendingNoteUpserts()
    }

    func fetchCategories() async throws {
        let fetched: [Category] = try await supabase
            .from("categories")
            .select()
            .order("sort_order", ascending: true)
            .execute()
            .value
        categories = fetched
    }

    /// Update note content locally without syncing to server.
    func setNoteContent(id: UUID, content: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].content = content
        notes[index].updatedAt = Date()
        if notes[index].source == .voice {
            let inferredState = NoteBodyState(content: content, source: notes[index].source)
            if inferredState.isTransientTranscriptionState {
                notes[index].content = ""
                setLocalVoiceBodyState(inferredState, for: id)
            } else {
                setLocalVoiceBodyState(nil, for: id)
            }
        }
        queuePendingNoteUpsert(notes[index])
    }

    // MARK: - Note CRUD

    func addNote(_ note: Note) {
        let localNote = normalizeLocalVoiceNote(note)
        notes.insert(localNote, at: 0)
        queuePendingNoteUpsert(localNote)
        let revision = bumpNoteSyncRevision(for: note.id)
        schedulePendingNoteUpsertSync(id: note.id, expectedRevision: revision, delay: .zero)
    }

    func updateNote(_ note: Note) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        let localNote = normalizeLocalVoiceNote(note)
        notes[index] = localNote
        queuePendingNoteUpsert(localNote)
        let revision = bumpNoteSyncRevision(for: note.id)
        schedulePendingNoteUpsertSync(id: note.id, expectedRevision: revision, delay: noteSyncDebounceDuration)
    }

    func removeNote(id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        var removed = notes.remove(at: index)
        removed.deletedAt = Date()
        deletedNotes.insert(removed, at: 0)
        setLocalVoiceBodyState(nil, for: id)
        pendingNoteUpserts.removeValue(forKey: id)
        persistPendingNoteUpserts()

        Task {
            do {
                let update = SoftDeleteUpdate(deletedAt: removed.deletedAt)
                try await supabase
                    .from("notes")
                    .update(update)
                    .eq("id", value: id)
                    .execute()
            } catch {
                // Sync failure is non-fatal — note is already removed locally
            }
        }
    }

    func removeNotes(ids: Set<UUID>) {
        let now = Date()
        var removed = notes.filter { ids.contains($0.id) }
        notes.removeAll { ids.contains($0.id) }
        for i in removed.indices { removed[i].deletedAt = now }
        deletedNotes.insert(contentsOf: removed, at: 0)
        ids.forEach { setLocalVoiceBodyState(nil, for: $0) }
        ids.forEach { pendingNoteUpserts.removeValue(forKey: $0) }
        persistPendingNoteUpserts()

        Task {
            // Batch in chunks of 20 to avoid oversized IN clauses
            let idArray = Array(ids)
            for chunk in stride(from: 0, to: idArray.count, by: 20).map({
                Array(idArray[$0..<min($0 + 20, idArray.count)])
            }) {
                do {
                    let update = SoftDeleteUpdate(deletedAt: now)
                    try await supabase
                        .from("notes")
                        .update(update)
                        .in("id", values: chunk.map(\.uuidString))
                        .execute()
                } catch {
                    // Sync failure is non-fatal — notes are already removed locally
                }
            }
        }
    }

    // MARK: - Restore & Purge

    func restoreNote(id: UUID) {
        guard let index = deletedNotes.firstIndex(where: { $0.id == id }) else { return }
        var restored = deletedNotes.remove(at: index)
        restored.deletedAt = nil
        restored.updatedAt = Date()
        notes.insert(restored, at: 0)
        notes.sort { $0.createdAt > $1.createdAt }
        queuePendingNoteUpsert(restored)
        let revision = bumpNoteSyncRevision(for: id)
        schedulePendingNoteUpsertSync(id: id, expectedRevision: revision, delay: .zero)
    }

    func permanentlyDeleteNote(id: UUID) {
        deletedNotes.removeAll { $0.id == id }
        pendingNoteUpserts.removeValue(forKey: id)
        persistPendingNoteUpserts()

        Task {
            do {
                try await supabase
                    .from("notes")
                    .delete()
                    .eq("id", value: id)
                    .execute()
            } catch {
                logger.error("permanentlyDeleteNote failed: \(error)")
            }
        }
    }

    private func purgeExpiredNotes() async {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let expired = deletedNotes.filter { note in
            guard let deletedAt = note.deletedAt else { return false }
            return deletedAt < cutoff
        }
        guard !expired.isEmpty else { return }

        let expiredIds = expired.map(\.id)
        deletedNotes.removeAll { expiredIds.contains($0.id) }

        do {
            try await supabase
                .from("notes")
                .delete()
                .in("id", values: expiredIds.map(\.uuidString))
                .execute()
        } catch {
            logger.error("purgeExpiredNotes failed: \(error)")
        }
    }

    func moveNotes(ids: Set<UUID>, toCategoryId categoryId: UUID?) {
        let now = Date()
        let movedNotes = notes
            .filter { ids.contains($0.id) && $0.categoryId != categoryId }
            .map { note -> Note in
                var updated = note
                updated.categoryId = categoryId
                updated.updatedAt = now
                return updated
            }

        for note in movedNotes {
            updateNote(note)
        }
    }

    // MARK: - Transcription

    func transcribeNote(id: UUID, audioFileURL: URL, language: String?, userId: UUID?, customDictionary: [String] = [], multiSpeaker: Bool = false) {
        guard activeTranscriptionIds.insert(id).inserted else {
            logger.info("Skipping duplicate transcription start for \(id)")
            return
        }

        // Persist the local file path so it survives app restarts
        registerLocalAudio(audioFileURL, for: id)
        setNoteBodyState(id: id, state: .transcribing)

        Task {
            defer { self.activeTranscriptionIds.remove(id) }
            var compressedURL: URL?
            defer { if let compressedURL { AudioCompressor.cleanup(compressedURL) } }

            do {
                // Validate audio file before processing
                guard FileManager.default.fileExists(atPath: audioFileURL.path),
                      let attrs = try? FileManager.default.attributesOfItem(atPath: audioFileURL.path),
                      let fileSize = attrs[.size] as? Int, fileSize > 0
                else {
                    logger.error("transcribeNote: audio file missing or empty at \(audioFileURL.path)")
                    setNoteBodyState(id: id, state: .transcriptionFailed)
                    ErrorLogger.shared.log(
                        type: "transcription_failed",
                        message: "Audio file missing or empty",
                        context: ["note_id": id.uuidString, "path": audioFileURL.lastPathComponent],
                        userId: userId
                    )
                    return
                }

                // Connectivity probe — quick request to verify network before heavy upload
                do {
                    var probe = URLRequest(url: AppConfig.supabaseUrl.appendingPathComponent("rest/v1/"))
                    probe.httpMethod = "GET"
                    probe.timeoutInterval = 15
                    probe.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
                    probe.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
                    let (_, response) = try await URLSession.shared.data(for: probe)
                    guard let http = response as? HTTPURLResponse, http.statusCode < 500 else {
                        throw URLError(.cannotConnectToHost)
                    }
                } catch {
                    logger.info("Connectivity probe failed — device appears offline: \(error)")
                    setNoteBodyState(id: id, state: .waitingForConnection)
                    return
                }

                // Always upload original for storage quality; compress separately for Whisper
                let audioData = try Data(contentsOf: audioFileURL)
                let fileName = audioFileURL.lastPathComponent

                var whisperData: Data? = nil
                var whisperFileName: String? = nil
                do {
                    let compressed = try await AudioCompressor.compress(sourceURL: audioFileURL)
                    compressedURL = compressed
                    whisperData = try Data(contentsOf: compressed)
                    whisperFileName = compressed.lastPathComponent
                } catch {
                    logger.warning("Compression failed, Whisper will use original: \(error)")
                }

                let service = TranscriptionService()
                let timeoutSeconds = transcriptionTimeoutSeconds(for: id)
                let requestAudioData = audioData
                let requestFileName = fileName
                let requestLanguage = language
                let requestUserId = userId
                let requestDictionary = customDictionary
                let requestWhisperData = whisperData
                let requestWhisperFileName = whisperFileName
                let requestMultiSpeaker = multiSpeaker
                let result = try await performTranscriptionWithTimeout(seconds: timeoutSeconds) {
                    try await service.transcribe(
                        audioData: requestAudioData,
                        fileName: requestFileName,
                        language: requestLanguage,
                        userId: requestUserId,
                        customDictionary: requestDictionary,
                        whisperData: requestWhisperData,
                        whisperFileName: requestWhisperFileName,
                        multiSpeaker: requestMultiSpeaker
                    )
                }

                // Guard against empty transcription
                let transcribedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !transcribedText.isEmpty else {
                    logger.warning("transcribeNote: received empty transcription for \(id)")
                    setNoteBodyState(id: id, state: .transcriptionFailed)
                    ErrorLogger.shared.log(
                        type: "transcription_empty",
                        message: "Whisper returned empty text",
                        context: ["note_id": id.uuidString, "language": language ?? "auto"],
                        userId: userId
                    )
                    return
                }

                // Update note with transcription
                guard var note = notes.first(where: { $0.id == id }) else {
                    logger.error("transcribeNote: note \(id) not found in local store after transcription")
                    return
                }
                let (formattedContent, initialSpeakerNames) = Self.formatMultiSpeakerTranscript(transcribedText)
                setLocalVoiceBodyState(nil, for: id)
                note.content = formattedContent
                if let initialSpeakerNames { note.speakerNames = initialSpeakerNames }
                note.language = result.language
                if let audioUrl = result.audioUrl {
                    note.audioUrl = audioUrl
                }
                if let duration = result.durationSeconds {
                    note.durationSeconds = duration
                }
                note.updatedAt = Date()
                updateNote(note)

                // Clean up local audio file after remote URL confirmed
                if result.audioUrl != nil {
                    unregisterLocalAudio(for: id)
                    try? FileManager.default.removeItem(at: audioFileURL)
                }

                // Generate AI title in background
                generateTitle(for: id, content: transcribedText, language: result.language)
            } catch {
                logger.error("transcribeNote failed for \(id): \(error)")
                guard notes.contains(where: { $0.id == id }) else {
                    logger.error("transcribeNote: note \(id) not found in local store after failure")
                    return
                }

                let fileSizeMB = (try? FileManager.default.attributesOfItem(atPath: audioFileURL.path)[.size] as? Int)
                    .map { String(format: "%.1f", Double($0) / 1_048_576.0) } ?? "?"

                if error is URLError {
                    setNoteBodyState(id: id, state: .waitingForConnection)
                    ErrorLogger.shared.log(
                        type: "transcription_offline",
                        message: "Network unavailable during transcription",
                        context: ["note_id": id.uuidString, "file_size_mb": fileSizeMB],
                        userId: userId
                    )
                } else if let timeoutError = error as? TranscriptionWorkflowError {
                    setNoteBodyState(id: id, state: .transcriptionFailed)
                    ErrorLogger.shared.log(
                        type: "transcription_timeout",
                        message: timeoutError.localizedDescription,
                        context: ["note_id": id.uuidString, "file_size_mb": fileSizeMB, "language": language ?? "auto"],
                        userId: userId
                    )
                } else {
                    setNoteBodyState(id: id, state: .transcriptionFailed)
                    ErrorLogger.shared.log(
                        type: "transcription_failed",
                        message: error.localizedDescription,
                        context: ["note_id": id.uuidString, "file_size_mb": fileSizeMB, "language": language ?? "auto"],
                        userId: userId
                    )
                }
            }
        }
    }

    private func transcriptionRepairThresholdSeconds(for note: Note) -> TimeInterval {
        transcriptionTimeoutSeconds(for: note.durationSeconds) + 30
    }

    private func transcriptionTimeoutSeconds(for noteId: UUID) -> TimeInterval {
        transcriptionTimeoutSeconds(for: notes.first(where: { $0.id == noteId })?.durationSeconds)
    }

    private func transcriptionTimeoutSeconds(for durationSeconds: Int?) -> TimeInterval {
        switch durationSeconds ?? 0 {
        case 900...:
            return 420
        case 300...:
            return 300
        default:
            return 180
        }
    }

    private func performTranscriptionWithTimeout(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> TranscriptionResult
    ) async throws -> TranscriptionResult {
        try await withThrowingTaskGroup(of: TranscriptionResult.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw TranscriptionWorkflowError.timedOut(seconds: seconds)
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - AI Title

    func generateTitle(for noteId: UUID, content: String, language: String?) {
        generatingTitleIds.insert(noteId)
        Task {
            do {
                let aiTitle = try await AIService.generateTitle(for: content, language: language)
                generatingTitleIds.remove(noteId)
                guard var note = notes.first(where: { $0.id == noteId }) else { return }
                note.title = aiTitle
                note.updatedAt = Date()
                updateNote(note)
            } catch {
                generatingTitleIds.remove(noteId)
                logger.error("generateTitle failed for \(noteId): \(error)")
                ErrorLogger.shared.log(
                    type: "title_generation_failed",
                    message: error.localizedDescription,
                    context: ["note_id": noteId.uuidString]
                )
            }
        }
    }

    // MARK: - Rewrites

    func fetchRewrites(for noteId: UUID) async {
        do {
            let fetched: [NoteRewrite] = try await supabase
                .from("note_rewrites")
                .select()
                .eq("note_id", value: noteId)
                .order("created_at", ascending: true)
                .execute()
                .value
            rewritesCache[noteId] = fetched
        } catch {
            logger.error("fetchRewrites failed: \(error)")
        }
    }

    func saveRewrite(_ rewrite: NoteRewrite) async {
        var current = rewritesCache[rewrite.noteId] ?? []
        current.append(rewrite)
        rewritesCache[rewrite.noteId] = current

        do {
            try await supabase
                .from("note_rewrites")
                .insert(rewrite)
                .execute()
        } catch {
            logger.error("saveRewrite failed: \(error)")
            rewritesCache[rewrite.noteId]?.removeAll { $0.id == rewrite.id }
        }
    }

    func updateRewrite(_ rewrite: NoteRewrite) {
        guard let idx = rewritesCache[rewrite.noteId]?.firstIndex(where: { $0.id == rewrite.id }) else { return }
        rewritesCache[rewrite.noteId]?[idx] = rewrite
        Task {
            do {
                try await supabase
                    .from("note_rewrites")
                    .update(["content": rewrite.content])
                    .eq("id", value: rewrite.id.uuidString)
                    .execute()
            } catch {
                logger.error("updateRewrite failed: \(error)")
            }
        }
    }

    /// Renames a speaker in all cached rewrites (in-memory + Supabase).
    func renameSpeakerInRewrites(noteId: UUID, oldName: String, newName: String) {
        guard var rewrites = rewritesCache[noteId] else { return }
        var changed: [NoteRewrite] = []
        for i in rewrites.indices {
            let updated = rewrites[i].content
                .components(separatedBy: "\n")
                .map { $0 == oldName ? newName : $0 }
                .joined(separator: "\n")
                .replacingOccurrences(of: "[\(oldName)]:", with: "[\(newName)]:")
            if updated != rewrites[i].content {
                rewrites[i].content = updated
                changed.append(rewrites[i])
            }
        }
        rewritesCache[noteId] = rewrites
        Task {
            for rewrite in changed {
                do {
                    try await supabase
                        .from("note_rewrites")
                        .update(["content": rewrite.content])
                        .eq("id", value: rewrite.id.uuidString)
                        .execute()
                } catch {
                    logger.error("renameSpeakerInRewrites failed: \(error)")
                }
            }
        }
    }

    func deleteRewrite(_ rewrite: NoteRewrite) {
        rewritesCache[rewrite.noteId]?.removeAll { $0.id == rewrite.id }

        Task {
            do {
                try await supabase
                    .from("note_rewrites")
                    .delete()
                    .eq("id", value: rewrite.id.uuidString)
                    .execute()
            } catch {
                logger.error("deleteRewrite failed: \(error)")
                var current = rewritesCache[rewrite.noteId] ?? []
                current.append(rewrite)
                rewritesCache[rewrite.noteId] = current
            }
        }
    }

    func deleteRewrites(for noteId: UUID) {
        rewritesCache[noteId] = nil

        Task {
            do {
                try await supabase
                    .from("note_rewrites")
                    .delete()
                    .eq("note_id", value: noteId.uuidString)
                    .execute()
            } catch {
                logger.error("deleteRewrites failed: \(error)")
            }
        }
    }

    // MARK: - Category CRUD

    func addCategory(_ category: Category) {
        categories.append(category)

        Task {
            do {
                try await supabase
                    .from("categories")
                    .insert(category)
                    .execute()
            } catch {
                categories.removeAll { $0.id == category.id }
                lastError = "Failed to create category"
            }
        }
    }

    func updateCategory(_ category: Category) {
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { return }
        let previous = categories[index]
        categories[index] = category
        let revision = bumpCategorySyncRevision(for: category.id)

        Task {
            do {
                try await supabase
                    .from("categories")
                    .update(category)
                    .eq("id", value: category.id)
                    .execute()
            } catch {
                guard categorySyncRevisions[category.id] == revision else { return }
                if let i = categories.firstIndex(where: { $0.id == category.id }) {
                    categories[i] = previous
                }
            }
        }
    }

    func removeCategory(id: UUID) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        let removed = categories.remove(at: index)
        let now = Date()
        let affectedNotes = notes
            .filter { $0.categoryId == id }
            .map { note -> Note in
                var updated = note
                updated.categoryId = nil
                updated.updatedAt = now
                return updated
            }

        for note in affectedNotes {
            updateNote(note)
        }

        Task {
            do {
                try await supabase
                    .from("categories")
                    .delete()
                    .eq("id", value: id)
                    .execute()
            } catch {
                categories.insert(removed, at: min(index, categories.count))
            }
        }
    }

    func moveCategory(from source: IndexSet, to destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)
        for i in categories.indices {
            categories[i].sortOrder = i
        }

        // Persist new sort orders
        let updates = categories.map { ($0.id, $0.sortOrder) }
        Task {
            for (catId, order) in updates {
                let sortUpdate = CategorySortUpdate(sortOrder: order)
                try? await supabase
                    .from("categories")
                    .update(sortUpdate)
                    .eq("id", value: catId)
                    .execute()
            }
        }
    }
}

// MARK: - Partial Update Models

private struct SoftDeleteUpdate: Encodable {
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case deletedAt = "deleted_at"
    }
}

private struct CategorySortUpdate: Encodable {
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case sortOrder = "sort_order"
    }
}
