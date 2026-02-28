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
    var categories: [Category] = []
    var selectedCategoryId: UUID?
    var isLoading = false
    var lastError: String?

    /// Retry any notes stuck in "Waiting for connection…".
    /// Scans the notes array directly — works even after app restart.
    /// Each note goes through transcribeNote which has its own connectivity probe.
    func retryWaitingNotes(language: String?, userId: UUID?) {
        let waiting = notes.filter {
            $0.content == "Waiting for connection…" || $0.content == "Transcription failed — tap to edit"
        }
        guard !waiting.isEmpty else { return }

        for note in waiting {
            guard let urlString = note.audioUrl,
                  let url = URL(string: urlString),
                  url.isFileURL,
                  FileManager.default.fileExists(atPath: url.path)
            else { continue }

            setNoteContent(id: note.id, content: "Transcribing…")
            transcribeNote(id: note.id, audioFileURL: url, language: language, userId: userId)
        }
    }

    var filteredNotes: [Note] {
        guard let categoryId = selectedCategoryId else { return notes }
        return notes.filter { $0.categoryId == categoryId }
    }

    // MARK: - Fetch

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        async let fetchedNotes: () = fetchNotes()
        async let fetchedCategories: () = fetchCategories()
        _ = try? await (fetchedNotes, fetchedCategories)
    }

    func fetchNotes() async throws {
        let fetched: [Note] = try await supabase
            .from("notes")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value
        notes = fetched
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
        let removed = notes.remove(at: index)

        Task {
            do {
                try await supabase
                    .from("notes")
                    .delete()
                    .eq("id", value: id)
                    .execute()
            } catch {
                // Rollback on failure
                notes.insert(removed, at: min(index, notes.count))
            }
        }
    }

    func removeNotes(ids: Set<UUID>) {
        let removed = notes.filter { ids.contains($0.id) }
        notes.removeAll { ids.contains($0.id) }

        Task {
            do {
                try await supabase
                    .from("notes")
                    .delete()
                    .in("id", values: Array(ids))
                    .execute()
            } catch {
                // Rollback on failure
                notes.append(contentsOf: removed)
                notes.sort { $0.createdAt > $1.createdAt }
            }
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
                    .in("id", values: Array(ids))
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

    func transcribeNote(id: UUID, audioFileURL: URL, language: String?, userId: UUID?) {
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
                    setNoteContent(id: id, content: "Transcription failed — tap to edit")
                    return
                }

                // Connectivity probe — fast HEAD request to detect offline before heavy upload
                do {
                    var probe = URLRequest(url: AppConfig.supabaseUrl)
                    probe.httpMethod = "HEAD"
                    probe.timeoutInterval = 5
                    _ = try await URLSession.shared.data(for: probe)
                } catch {
                    logger.info("Connectivity probe failed — device appears offline: \(error)")
                    setNoteContent(id: id, content: "Waiting for connection…")
                    return
                }

                // Compress audio to 16kHz mono AAC (what Whisper uses internally)
                let uploadURL: URL
                do {
                    let compressed = try await AudioCompressor.compress(sourceURL: audioFileURL)
                    compressedURL = compressed
                    uploadURL = compressed
                } catch {
                    logger.warning("Compression failed, using original: \(error)")
                    uploadURL = audioFileURL
                }

                let audioData = try Data(contentsOf: uploadURL)
                let fileName = uploadURL.lastPathComponent

                let service = TranscriptionService()
                let result = try await service.transcribe(
                    audioData: audioData,
                    fileName: fileName,
                    language: language,
                    userId: userId
                )

                // Guard against empty transcription
                let transcribedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !transcribedText.isEmpty else {
                    logger.warning("transcribeNote: received empty transcription for \(id)")
                    setNoteContent(id: id, content: "Transcription failed — tap to edit")
                    return
                }

                // Update note with transcription
                guard var note = notes.first(where: { $0.id == id }) else {
                    logger.error("transcribeNote: note \(id) not found in local store after transcription")
                    return
                }
                note.content = transcribedText
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

                if error is URLError {
                    notes[noteIndex].content = "Waiting for connection…"
                    notes[noteIndex].updatedAt = Date()
                } else {
                    notes[noteIndex].content = "Transcription failed — tap to edit"
                    notes[noteIndex].updatedAt = Date()
                }
            }
        }
    }

    // MARK: - AI Title

    func generateTitle(for noteId: UUID, content: String, language: String?) {
        Task {
            do {
                let aiTitle = try await AIService.generateTitle(for: content, language: language)
                guard var note = notes.first(where: { $0.id == noteId }) else { return }
                note.title = aiTitle
                note.updatedAt = Date()
                updateNote(note)
            } catch {
                // AI title failed — keep the quick title, no big deal
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

private struct CategorySortUpdate: Encodable {
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case sortOrder = "sort_order"
    }
}
