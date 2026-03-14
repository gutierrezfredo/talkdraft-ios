import Foundation
import os
import Supabase

private let logger = Logger(subsystem: "com.pleymob.talkdraft", category: "NoteStore")

extension NoteStore {
    // MARK: - AI Title

    func generateTitle(for noteId: UUID, content: String, language: String?) {
        generatingTitleIds.insert(noteId)
        Task {
            do {
                let aiTitle = try await aiTitleExecutor(content, language)
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

    func fetchAllRewrites() async {
        do {
            let fetched: [NoteRewrite] = try await supabase
                .from("note_rewrites")
                .select()
                .order("created_at", ascending: true)
                .execute()
                .value
            rewritesCache = Dictionary(grouping: fetched, by: \.noteId)
        } catch {
            logger.error("fetchAllRewrites failed: \(error)")
        }
    }

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
}
