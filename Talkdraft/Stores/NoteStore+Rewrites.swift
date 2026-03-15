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

    func rewriteLabel(for noteId: UUID) -> String? {
        rewriteLabelsByNoteId[noteId]
    }

    func rewriteError(for noteId: UUID) -> String? {
        rewriteErrorsByNoteId[noteId]
    }

    func clearRewriteError(for noteId: UUID) {
        rewriteErrorsByNoteId[noteId] = nil
    }

    func startRewrite(
        for noteSnapshot: Note,
        title: String,
        visibleContent: String,
        sourceContent: String,
        userId: UUID?,
        tone: String?,
        instructions: String?,
        toneLabel: String?,
        toneEmoji: String?
    ) {
        guard activeRewriteIds.insert(noteSnapshot.id).inserted else { return }

        let label: String
        if let emoji = toneEmoji, let name = toneLabel {
            label = "\(emoji) \(name)"
        } else if let name = toneLabel {
            label = name
        } else if let instructions, !instructions.isEmpty {
            let preview = String(instructions.prefix(30))
            label = instructions.count > 30 ? "\(preview)…" : preview
        } else {
            label = "Rewriting…"
        }

        rewriteLabelsByNoteId[noteSnapshot.id] = label
        rewriteErrorsByNoteId[noteSnapshot.id] = nil

        var note = notes.first(where: { $0.id == noteSnapshot.id }) ?? noteSnapshot
        let introducedOriginalContent = note.originalContent == nil
        note.userId = note.userId ?? userId
        note.title = title.isEmpty ? nil : title
        note.content = visibleContent
        if introducedOriginalContent {
            note.originalContent = sourceContent
        }
        note.updatedAt = Date()

        if notes.contains(where: { $0.id == note.id }) {
            updateNote(note)
        } else {
            addNote(note)
        }

        pendingRewriteTasks[note.id]?.cancel()
        pendingRewriteTasks[note.id] = Task { [weak self] in
            guard let self else { return }
            defer {
                self.activeRewriteIds.remove(note.id)
                self.rewriteLabelsByNoteId[note.id] = nil
                self.pendingRewriteTasks[note.id] = nil
            }

            do {
                let stream = self.aiRewriteStreamExecutor(
                    sourceContent,
                    tone,
                    instructions,
                    note.language,
                    !(note.speakerNames ?? [:]).isEmpty
                )

                var fullText = ""
                for try await chunk in stream {
                    fullText += chunk
                }

                let rewrittenContent = self.normalizedRewriteContent(from: fullText)

                let rewrite = NoteRewrite(
                    id: UUID(),
                    noteId: note.id,
                    userId: userId,
                    tone: tone,
                    toneLabel: toneLabel,
                    toneEmoji: toneEmoji,
                    instructions: instructions,
                    content: rewrittenContent,
                    createdAt: Date()
                )
                await self.saveRewrite(rewrite)

                guard var updated = self.notes.first(where: { $0.id == note.id }) else { return }
                updated.title = title.isEmpty ? nil : title
                updated.content = rewrittenContent
                updated.activeRewriteId = rewrite.id
                updated.updatedAt = Date()
                self.updateNote(updated)
            } catch is CancellationError {
                self.rewriteErrorsByNoteId[note.id] = nil
            } catch {
                if introducedOriginalContent,
                   var reverted = self.notes.first(where: { $0.id == note.id }) {
                    reverted.originalContent = nil
                    reverted.updatedAt = Date()
                    self.updateNote(reverted)
                }

                self.rewriteErrorsByNoteId[note.id] = "Rewrite failed: \(error.localizedDescription)"
                logger.error("rewrite failed for \(note.id): \(error.localizedDescription, privacy: .public)")
                ErrorLogger.shared.log(
                    type: "rewrite_failed",
                    message: error.localizedDescription,
                    context: ["note_id": note.id.uuidString]
                )
            }
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

    private func normalizedRewriteContent(from text: String) -> String {
        text
            .components(separatedBy: "\n")
            .map { $0.hasPrefix("- ") ? "• " + $0.dropFirst(2) : $0 }
            .joined(separator: "\n")
    }
}
