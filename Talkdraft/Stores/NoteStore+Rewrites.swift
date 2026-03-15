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
        guard let userId else {
            rewriteErrorsByNoteId[noteSnapshot.id] = "You need to be signed in to rewrite notes."
            return
        }
        guard rewriteJobsByNoteId[noteSnapshot.id]?.status.isActive != true else { return }

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

        let optimisticJob = NoteRewriteJob(
            id: UUID(),
            noteId: note.id,
            userId: userId,
            status: .queued,
            sourceContent: sourceContent,
            titleSnapshot: title.isEmpty ? nil : title,
            tone: tone,
            toneLabel: toneLabel,
            toneEmoji: toneEmoji,
            instructions: instructions,
            noteUpdatedAtSnapshot: note.updatedAt,
            rewriteId: nil,
            errorMessage: nil,
            createdAt: Date(),
            startedAt: nil,
            finishedAt: nil
        )
        applyRewriteJobSnapshot([optimisticJob])

        Task {
            do {
                let created: NoteRewriteJob = try await supabase
                    .from("note_rewrite_jobs")
                    .insert(
                        RewriteJobCreatePayload(
                            noteId: optimisticJob.noteId,
                            userId: optimisticJob.userId,
                            status: optimisticJob.status,
                            sourceContent: optimisticJob.sourceContent,
                            titleSnapshot: optimisticJob.titleSnapshot,
                            tone: optimisticJob.tone,
                            toneLabel: optimisticJob.toneLabel,
                            toneEmoji: optimisticJob.toneEmoji,
                            instructions: optimisticJob.instructions,
                            noteUpdatedAtSnapshot: optimisticJob.noteUpdatedAtSnapshot
                        )
                    )
                    .select()
                    .single()
                    .execute()
                    .value

                applyRewriteJobSnapshot([created])
                try await triggerRewriteJob(created.id)
            } catch {
                if introducedOriginalContent,
                   var reverted = notes.first(where: { $0.id == note.id }) {
                    reverted.originalContent = nil
                    reverted.updatedAt = Date()
                    updateNote(reverted)
                }

                rewriteJobsByNoteId[note.id] = nil
                activeRewriteIds.remove(note.id)
                rewriteLabelsByNoteId[note.id] = nil
                rewriteErrorsByNoteId[note.id] = "Rewrite failed: \(error.localizedDescription)"
                logger.error("startRewrite failed for \(note.id): \(error.localizedDescription, privacy: .public)")
                ErrorLogger.shared.log(
                    type: "rewrite_job_start_failed",
                    message: error.localizedDescription,
                    context: ["note_id": note.id.uuidString]
                )
            }
        }
    }

    func startRewriteJobPolling() {
        guard rewriteJobPollingTask == nil else { return }
        rewriteJobPollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshRewriteJobs()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stopRewriteJobPolling() {
        rewriteJobPollingTask?.cancel()
        rewriteJobPollingTask = nil
    }

    func refreshRewriteJobs() async {
        guard currentSessionUserId != nil, !isRefreshingRewriteJobs else { return }
        isRefreshingRewriteJobs = true
        defer { isRefreshingRewriteJobs = false }

        do {
            let fetched: [NoteRewriteJob] = try await supabase
                .from("note_rewrite_jobs")
                .select()
                .order("created_at", ascending: false)
                .limit(200)
                .execute()
                .value

            let noteIds = Set(notes.map(\.id))
            let relevant = fetched.filter { noteIds.contains($0.noteId) }
            let previousByNote = rewriteJobsByNoteId
            let previousActiveIds = Set(previousByNote.values.compactMap { $0.status.isActive ? $0.noteId : nil })

            applyRewriteJobSnapshot(relevant, replacingAll: true)

            for job in rewriteJobsByNoteId.values where job.status == .queued && !attemptedRewriteTriggerIds.contains(job.id) {
                do {
                    try await triggerRewriteJob(job.id)
                } catch {
                    rewriteErrorsByNoteId[job.noteId] = "Rewrite failed to start. Please try again."
                    logger.error("triggerRewriteJob failed for queued job \(job.id): \(error.localizedDescription, privacy: .public)")
                }
            }

            let currentActiveIds = Set(rewriteJobsByNoteId.values.compactMap { $0.status.isActive ? $0.noteId : nil })
            let completedIds = previousActiveIds.subtracting(currentActiveIds)

            for (noteId, job) in rewriteJobsByNoteId {
                let previousStatus = previousByNote[noteId]?.status
                guard previousStatus != job.status else { continue }
                switch job.status {
                case .failed:
                    rewriteErrorsByNoteId[noteId] = job.errorMessage ?? "Rewrite failed."
                case .completedDetached:
                    rewriteErrorsByNoteId[noteId] = "Rewrite finished, but the note changed before it could be applied."
                case .queued, .processing, .completed, .canceled:
                    rewriteErrorsByNoteId[noteId] = nil
                }
            }

            guard !completedIds.isEmpty else { return }
            try? await fetchNotes()
            for noteId in completedIds {
                await fetchRewrites(for: noteId)
            }
        } catch {
            logger.error("refreshRewriteJobs failed: \(error)")
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

    private func rewriteDisplayLabel(
        toneLabel: String?,
        toneEmoji: String?,
        instructions: String?
    ) -> String {
        if let emoji = toneEmoji, let name = toneLabel {
            return "\(emoji) \(name)"
        } else if let name = toneLabel {
            return name
        } else if let instructions, !instructions.isEmpty {
            let preview = String(instructions.prefix(30))
            return instructions.count > 30 ? "\(preview)…" : preview
        }
        return "Rewriting…"
    }

    private func applyRewriteJobSnapshot(_ jobs: [NoteRewriteJob], replacingAll: Bool = false) {
        let grouped = Dictionary(grouping: jobs, by: \.noteId)
        let trackedNoteIds = Set(notes.map(\.id))
        var updated: [UUID: NoteRewriteJob] = replacingAll ? [:] : rewriteJobsByNoteId

        for noteId in trackedNoteIds where replacingAll || grouped[noteId] != nil {
            if let selected = grouped[noteId]?.first(where: { $0.status.isActive }) ?? grouped[noteId]?.first {
                updated[noteId] = selected
            } else if replacingAll {
                updated[noteId] = nil
            }
        }

        updated = updated.filter { trackedNoteIds.contains($0.key) }

        rewriteJobsByNoteId = updated
        activeRewriteIds = Set(updated.values.compactMap { $0.status.isActive ? $0.noteId : nil })
        rewriteLabelsByNoteId = Dictionary(
            uniqueKeysWithValues: updated.compactMap { noteId, job in
                guard job.status.isActive else { return nil }
                return (noteId, job.displayLabel)
            }
        )
        attemptedRewriteTriggerIds = Set(
            updated.values.compactMap { job in
                job.status == .queued ? nil : job.id
            }
        )
    }

    private func triggerRewriteJob(_ jobId: UUID) async throws {
        attemptedRewriteTriggerIds.insert(jobId)
        let accessToken = try await supabase.auth.session.accessToken
        let _: RewriteJobTriggerResponse = try await supabase.functions.invoke(
            "process-rewrite-job",
            options: .init(
                method: .post,
                headers: ["Authorization": "Bearer \(accessToken)"],
                body: RewriteJobTriggerPayload(jobId: jobId)
            )
        )
    }
}
