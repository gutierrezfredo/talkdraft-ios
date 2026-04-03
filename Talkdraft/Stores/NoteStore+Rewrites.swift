import Foundation
import os
import Supabase

private let logger = Logger(subsystem: "com.pleymob.talkdraft", category: "NoteStore")

extension NoteStore {
    // MARK: - AI Title

    func generateTitle(for noteId: UUID, content: String, language: String?) {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            clearPendingTitleGeneration(id: noteId)
            return
        }

        queuePendingTitleGeneration(id: noteId)
        guard generatingTitleIds.insert(noteId).inserted else { return }

        Task {
            do {
                let aiTitle = try await generateTitleWithRetries(content: trimmedContent, language: language)
                generatingTitleIds.remove(noteId)
                guard var note = notes.first(where: { $0.id == noteId }) else {
                    clearPendingTitleGeneration(id: noteId)
                    return
                }
                guard pendingTitleGenerationIds.contains(noteId) else {
                    clearPendingTitleGeneration(id: noteId)
                    return
                }
                note.title = aiTitle
                note.updatedAt = Date()
                updateNote(note)
                lastCompletedTitleGenerationNoteId = noteId
                clearPendingTitleGeneration(id: noteId)
            } catch is CancellationError {
                generatingTitleIds.remove(noteId)
            } catch {
                generatingTitleIds.remove(noteId)
                let willRetry = shouldKeepPendingTitleGeneration(after: error)
                if !willRetry {
                    clearPendingTitleGeneration(id: noteId)
                }
                logger.error("generateTitle failed for \(noteId): \(error)")
                ErrorLogger.shared.log(
                    type: "title_generation_failed",
                    message: error.localizedDescription,
                    context: [
                        "note_id": noteId.uuidString,
                        "will_retry": willRetry ? "true" : "false",
                    ]
                )
            }
        }
    }

    func retryPendingTitleGenerations() {
        seedRecoverableTitleGenerationRepairs()

        let orderedIds = pendingTitleGenerationIds.sorted { lhs, rhs in
            let lhsDate = notes.first(where: { $0.id == lhs })?.updatedAt ?? .distantPast
            let rhsDate = notes.first(where: { $0.id == rhs })?.updatedAt ?? .distantPast
            return lhsDate > rhsDate
        }

        for noteId in orderedIds {
            guard !generatingTitleIds.contains(noteId) else { continue }
            guard let note = notes.first(where: { $0.id == noteId }) else {
                clearPendingTitleGeneration(id: noteId)
                continue
            }
            guard shouldRetryPendingTitleGeneration(for: note) else {
                clearPendingTitleGeneration(id: noteId)
                continue
            }
            generateTitle(for: noteId, content: note.content, language: note.language)
        }
    }

    private func generateTitleWithRetries(content: String, language: String?) async throws -> String {
        let retryDelays: [Duration] = [.seconds(1), .seconds(3)]

        for (attempt, delay) in retryDelays.enumerated() {
            do {
                return try await aiTitleExecutor(content, language)
            } catch {
                guard shouldKeepPendingTitleGeneration(after: error) else { throw error }
                logger.notice("Retrying title generation after transient failure on attempt \(attempt + 1): \(error.localizedDescription, privacy: .public)")
                try await Task.sleep(for: delay)
            }
        }

        return try await aiTitleExecutor(content, language)
    }

    private func shouldKeepPendingTitleGeneration(after error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if error is URLError {
            return true
        }
        if let aiError = error as? AIError {
            return aiError.isTransient
        }
        return false
    }

    private func shouldRetryPendingTitleGeneration(for note: Note) -> Bool {
        pendingTitleGenerationIds.contains(note.id)
            && note.bodyState == .content
            && !note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func noteHasMissingTitle(_ note: Note) -> Bool {
        (note.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
    }

    private func seedRecoverableTitleGenerationRepairs(now: Date = .now) {
        let recencyThreshold: TimeInterval = 24 * 60 * 60
        let titleGenerationWindow: TimeInterval = 15 * 60

        for note in notes {
            guard note.source == .voice,
                  noteHasMissingTitle(note),
                  note.bodyState == .content,
                  note.durationSeconds != nil,
                  !note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  now.timeIntervalSince(note.createdAt) <= recencyThreshold,
                  note.updatedAt.timeIntervalSince(note.createdAt) <= titleGenerationWindow
            else {
                continue
            }

            queuePendingTitleGeneration(id: note.id)
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
                startRewriteJobPolling()

                do {
                    try await triggerRewriteJob(created.id)
                    await refreshRewriteJobs()
                } catch {
                    logger.error("triggerRewriteJob failed for new job \(created.id): \(error.localizedDescription, privacy: .public)")
                    await refreshRewriteJobs()
                }
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
        let token = UUID()
        rewriteJobPollingToken = token
        rewriteJobPollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshRewriteJobs()
                guard !Task.isCancelled else { break }
                guard !self.activeRewriteIds.isEmpty else { break }
                try? await Task.sleep(for: .seconds(5))
            }
            if self.rewriteJobPollingToken == token {
                self.rewriteJobPollingTask = nil
                self.rewriteJobPollingToken = nil
            }
        }
    }

    func stopRewriteJobPolling() {
        rewriteJobPollingTask?.cancel()
        rewriteJobPollingTask = nil
        rewriteJobPollingToken = nil
    }

    func refreshRewriteJobs() async {
        guard let userId = currentSessionUserId, !isRefreshingRewriteJobs else { return }
        isRefreshingRewriteJobs = true
        defer { isRefreshingRewriteJobs = false }

        do {
            let fetched: [NoteRewriteJob] = try await supabase
                .from("note_rewrite_jobs")
                .select()
                .eq("user_id", value: userId)
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
        guard let userId = currentSessionUserId else {
            rewritesCache[noteId] = []
            return
        }

        do {
            let fetched: [NoteRewrite] = try await supabase
                .from("note_rewrites")
                .select()
                .eq("note_id", value: noteId)
                .eq("user_id", value: userId)
                .order("created_at", ascending: true)
                .execute()
                .value
            rewritesCache[noteId] = fetched
        } catch {
            logger.error("fetchRewrites failed: \(error)")
        }
    }

    func saveRewrite(_ rewrite: NoteRewrite) async {
        guard let userId = currentSessionUserId ?? rewrite.userId else { return }

        var scopedRewrite = rewrite
        scopedRewrite.userId = userId

        var current = rewritesCache[scopedRewrite.noteId] ?? []
        current.append(scopedRewrite)
        rewritesCache[scopedRewrite.noteId] = current

        do {
            try await supabase
                .from("note_rewrites")
                .insert(scopedRewrite)
                .execute()
        } catch {
            logger.error("saveRewrite failed: \(error)")
            rewritesCache[scopedRewrite.noteId]?.removeAll { $0.id == scopedRewrite.id }
        }
    }

    func updateRewrite(_ rewrite: NoteRewrite) {
        guard let userId = currentSessionUserId else { return }
        guard let idx = rewritesCache[rewrite.noteId]?.firstIndex(where: { $0.id == rewrite.id }) else { return }
        rewritesCache[rewrite.noteId]?[idx] = rewrite
        Task {
            do {
                try await supabase
                    .from("note_rewrites")
                    .update(["content": rewrite.content])
                    .eq("id", value: rewrite.id.uuidString)
                    .eq("user_id", value: userId)
                    .execute()
            } catch {
                logger.error("updateRewrite failed: \(error)")
            }
        }
    }

    func renameSpeakerInRewrites(noteId: UUID, oldName: String, newName: String) {
        guard let userId = currentSessionUserId else { return }
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
                        .eq("user_id", value: userId)
                        .execute()
                } catch {
                    logger.error("renameSpeakerInRewrites failed: \(error)")
                }
            }
        }
    }

    func deleteRewrite(_ rewrite: NoteRewrite) {
        guard let userId = currentSessionUserId else { return }
        rewritesCache[rewrite.noteId]?.removeAll { $0.id == rewrite.id }

        Task {
            do {
                try await supabase
                    .from("note_rewrites")
                    .delete()
                    .eq("id", value: rewrite.id.uuidString)
                    .eq("user_id", value: userId)
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
        guard let userId = currentSessionUserId else { return }
        rewritesCache[noteId] = nil

        Task {
            do {
                try await supabase
                    .from("note_rewrites")
                    .delete()
                    .eq("note_id", value: noteId.uuidString)
                    .eq("user_id", value: userId)
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

        do {
            try await invokeRewriteJobTrigger(jobId: jobId, accessToken: accessToken)
        } catch {
            logger.warning("triggerRewriteJob first attempt failed for \(jobId): \(error.localizedDescription, privacy: .public)")
            try? await Task.sleep(for: .seconds(1))
            try await invokeRewriteJobTrigger(jobId: jobId, accessToken: accessToken)
        }
    }

    private func invokeRewriteJobTrigger(jobId: UUID, accessToken: String) async throws {
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
