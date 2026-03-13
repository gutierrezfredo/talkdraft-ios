import Foundation

extension NoteStore {
    func importAudioNote(
        from sourceURL: URL,
        userId: UUID?,
        categoryId: UUID?,
        language: String?,
        customDictionary: [String],
        requiresSecurityScopedAccess: Bool = true
    ) async throws -> Note {
        if requiresSecurityScopedAccess {
            guard sourceURL.startAccessingSecurityScopedResource() else {
                throw ImportedAudioNoteError.accessDenied
            }
            defer { sourceURL.stopAccessingSecurityScopedResource() }

            return try await importAudioNote(
                from: sourceURL,
                userId: userId,
                categoryId: categoryId,
                language: language,
                customDictionary: customDictionary,
                requiresSecurityScopedAccess: false
            )
        }

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
        queuePendingNoteUpsert(removed)
        let revision = bumpNoteSyncRevision(for: id)
        schedulePendingNoteUpsertSync(id: id, expectedRevision: revision, delay: .zero)
    }

    func removeNotes(ids: Set<UUID>) {
        let now = Date()
        var removed = notes.filter { ids.contains($0.id) }
        notes.removeAll { ids.contains($0.id) }
        for i in removed.indices { removed[i].deletedAt = now }
        deletedNotes.insert(contentsOf: removed, at: 0)
        for note in removed {
            setLocalVoiceBodyState(nil, for: note.id)
            queuePendingNoteUpsert(note)
            let revision = bumpNoteSyncRevision(for: note.id)
            schedulePendingNoteUpsertSync(id: note.id, expectedRevision: revision, delay: .zero)
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
        let deletedNote = deletedNotes.first(where: { $0.id == id })
        deletedNotes.removeAll { $0.id == id }
        cancelPendingNoteSyncTask(id: id)
        pendingNoteUpserts.removeValue(forKey: id)
        persistPendingNoteUpserts()
        noteSyncRevisions[id] = nil
        setLocalVoiceBodyState(nil, for: id)
        if let audioURL = localAudioFileURL(for: id, audioUrl: deletedNote?.audioUrl) {
            unregisterLocalAudio(for: id)
            try? FileManager.default.removeItem(at: audioURL)
        } else {
            unregisterLocalAudio(for: id)
        }
        queuePendingHardDelete(id)
        schedulePendingHardDelete(id: id)
    }

    func purgeExpiredNotes() async {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let expired = deletedNotes.filter { note in
            guard let deletedAt = note.deletedAt else { return false }
            return deletedAt < cutoff
        }
        guard !expired.isEmpty else { return }

        for note in expired {
            permanentlyDeleteNote(id: note.id)
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

}
