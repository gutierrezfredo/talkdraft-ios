import Foundation
import Observation
import os
import Supabase
import UIKit

private let logger = Logger(subsystem: "com.pleymob.talkdraft", category: "NoteStore")

private struct NoteUpdate: Encodable {
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
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case title, content
        case originalContent = "original_content"
        case activeRewriteId = "active_rewrite_id"
        case source, language
        case audioUrl = "audio_url"
        case durationSeconds = "duration_seconds"
        case speakerNames = "speaker_names"
        case updatedAt = "updated_at"
    }

    init(from note: Note) {
        self.categoryId = note.categoryId
        self.title = note.title
        self.content = note.content
        self.originalContent = note.originalContent
        self.activeRewriteId = note.activeRewriteId
        self.source = note.source
        self.language = note.language
        self.audioUrl = note.audioUrl
        self.durationSeconds = note.durationSeconds
        self.speakerNames = note.speakerNames
        self.updatedAt = note.updatedAt
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

    private func registerLocalAudio(_ url: URL, for noteId: UUID) {
        var index = (UserDefaults.standard.dictionary(forKey: Self.localAudioKey) as? [String: String]) ?? [:]
        index[noteId.uuidString] = url.path
        UserDefaults.standard.set(index, forKey: Self.localAudioKey)
    }

    private func unregisterLocalAudio(for noteId: UUID) {
        var index = (UserDefaults.standard.dictionary(forKey: Self.localAudioKey) as? [String: String]) ?? [:]
        index.removeValue(forKey: noteId.uuidString)
        UserDefaults.standard.set(index, forKey: Self.localAudioKey)
    }

    /// Returns the local audio file URL for a note, checking note.audioUrl first,
    /// then falling back to the persisted UserDefaults index.
    func localAudioFileURL(for noteId: UUID, audioUrl: String?) -> URL? {
        // Primary: note's own audioUrl (only valid if it's a local file)
        if let urlString = audioUrl,
           let url = URL(string: urlString),
           url.isFileURL,
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        // Fallback: persisted index (survives app restart after failed transcription)
        if let index = UserDefaults.standard.dictionary(forKey: Self.localAudioKey) as? [String: String],
           let path = index[noteId.uuidString] {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            // File gone — clean up stale entry
            unregisterLocalAudio(for: noteId)
        }
        return nil
    }

    func activeRewrite(for note: Note) -> NoteRewrite? {
        guard let rewriteId = note.activeRewriteId else { return nil }
        return rewritesCache[note.id]?.first { $0.id == rewriteId }
    }

    func resolvedContent(for note: Note) -> String {
        activeRewrite(for: note)?.content ?? note.content
    }

    func bodyState(for note: Note) -> NoteBodyState {
        NoteBodyState(content: resolvedContent(for: note))
    }

    /// Retry any notes stuck in "Waiting for connection…".
    /// Scans the notes array directly — works even after app restart.
    /// Each note goes through transcribeNote which has its own connectivity probe.
    func retryWaitingNotes(language: String?, userId: UUID?, customDictionary: [String] = []) {
        let waiting = notes.filter {
            let state = NoteBodyState(content: $0.content)
            return state == .waitingForConnection || state == .transcriptionFailed
        }
        guard !waiting.isEmpty else { return }

        for note in waiting {
            guard let url = localAudioFileURL(for: note.id, audioUrl: note.audioUrl) else { continue }
            setNoteContent(id: note.id, content: NoteBodyState.transcribingPlaceholder)
            transcribeNote(id: note.id, audioFileURL: url, language: language, userId: userId, customDictionary: customDictionary)
        }
    }

    var filteredNotes: [Note] {
        guard let categoryId = selectedCategoryId else { return notes }
        return notes.filter { $0.categoryId == categoryId }
    }

    // MARK: - Fetch

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
        notes = fetched

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
    }

    // MARK: - Note CRUD

    func addNote(_ note: Note) {
        notes.insert(note, at: 0)

        Task {
            do {
                try await supabase
                    .from("notes")
                    .insert(note)
                    .execute()
            } catch {
                logger.error("addNote sync failed (note saved locally): \(error)")
            }
        }
    }

    func updateNote(_ note: Note) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        let previous = notes[index]
        notes[index] = note

        Task {
            do {
                try await supabase
                    .from("notes")
                    .update(NoteUpdate(from: note))
                    .eq("id", value: note.id)
                    .execute()
            } catch {
                logger.error("updateNote failed: \(error)")
                // Rollback on failure
                if let i = notes.firstIndex(where: { $0.id == note.id }) {
                    notes[i] = previous
                }
            }
        }
    }

    func removeNote(id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        var removed = notes.remove(at: index)
        removed.deletedAt = Date()
        deletedNotes.insert(removed, at: 0)

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

        Task {
            do {
                let update = SoftDeleteUpdate(deletedAt: nil)
                try await supabase
                    .from("notes")
                    .update(update)
                    .eq("id", value: id)
                    .execute()
            } catch {
                // Rollback on failure
                notes.removeAll { $0.id == id }
                restored.deletedAt = Date()
                deletedNotes.insert(restored, at: min(index, deletedNotes.count))
            }
        }
    }

    func permanentlyDeleteNote(id: UUID) {
        deletedNotes.removeAll { $0.id == id }

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
        var previousValues: [(UUID, UUID?)] = []
        for i in notes.indices where ids.contains(notes[i].id) {
            previousValues.append((notes[i].id, notes[i].categoryId))
            notes[i].categoryId = categoryId
            notes[i].updatedAt = Date()
        }

        Task {
            do {
                let update = NoteCategoryUpdate(categoryId: categoryId, updatedAt: Date())
                try await supabase
                    .from("notes")
                    .update(update)
                    .in("id", values: ids.map(\.uuidString))
                    .execute()
            } catch {
                // Rollback on failure
                for (noteId, prevCategoryId) in previousValues {
                    if let i = notes.firstIndex(where: { $0.id == noteId }) {
                        notes[i].categoryId = prevCategoryId
                    }
                }
            }
        }
    }

    // MARK: - Transcription

    func transcribeNote(id: UUID, audioFileURL: URL, language: String?, userId: UUID?, customDictionary: [String] = [], multiSpeaker: Bool = false) {
        // Persist the local file path so it survives app restarts
        registerLocalAudio(audioFileURL, for: id)

        Task {
            var compressedURL: URL?
            defer { if let compressedURL { AudioCompressor.cleanup(compressedURL) } }

            do {
                // Validate audio file before processing
                guard FileManager.default.fileExists(atPath: audioFileURL.path),
                      let attrs = try? FileManager.default.attributesOfItem(atPath: audioFileURL.path),
                      let fileSize = attrs[.size] as? Int, fileSize > 0
                else {
                    logger.error("transcribeNote: audio file missing or empty at \(audioFileURL.path)")
                    setNoteContent(id: id, content: NoteBodyState.transcriptionFailedPlaceholder)
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
                    setNoteContent(id: id, content: NoteBodyState.waitingForConnectionPlaceholder)
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
                let result = try await service.transcribe(
                    audioData: audioData,
                    fileName: fileName,
                    language: language,
                    userId: userId,
                    customDictionary: customDictionary,
                    whisperData: whisperData,
                    whisperFileName: whisperFileName,
                    multiSpeaker: multiSpeaker
                )

                // Guard against empty transcription
                let transcribedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !transcribedText.isEmpty else {
                    logger.warning("transcribeNote: received empty transcription for \(id)")
                    setNoteContent(id: id, content: NoteBodyState.transcriptionFailedPlaceholder)
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
                guard let noteIndex = notes.firstIndex(where: { $0.id == id }) else {
                    logger.error("transcribeNote: note \(id) not found in local store after failure")
                    return
                }

                let fileSizeMB = (try? FileManager.default.attributesOfItem(atPath: audioFileURL.path)[.size] as? Int)
                    .map { String(format: "%.1f", Double($0) / 1_048_576.0) } ?? "?"

                if error is URLError {
                    notes[noteIndex].content = NoteBodyState.waitingForConnectionPlaceholder
                    notes[noteIndex].updatedAt = Date()
                    ErrorLogger.shared.log(
                        type: "transcription_offline",
                        message: "Network unavailable during transcription",
                        context: ["note_id": id.uuidString, "file_size_mb": fileSizeMB],
                        userId: userId
                    )
                } else {
                    notes[noteIndex].content = NoteBodyState.transcriptionFailedPlaceholder
                    notes[noteIndex].updatedAt = Date()
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

        Task {
            do {
                try await supabase
                    .from("categories")
                    .update(category)
                    .eq("id", value: category.id)
                    .execute()
            } catch {
                if let i = categories.firstIndex(where: { $0.id == category.id }) {
                    categories[i] = previous
                }
            }
        }
    }

    func removeCategory(id: UUID) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        let removed = categories.remove(at: index)

        // Unassign notes locally
        for i in notes.indices where notes[i].categoryId == id {
            notes[i].categoryId = nil
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

private struct NoteCategoryUpdate: Encodable {
    let categoryId: UUID?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case updatedAt = "updated_at"
    }
}

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
