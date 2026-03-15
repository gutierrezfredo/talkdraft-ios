import Foundation
import os

private let logger = Logger(subsystem: "com.pleymob.talkdraft", category: "NoteStore")

extension NoteStore {
    static func loadLocalVoiceBodyStates(for userId: UUID?) -> [UUID: NoteBodyState] {
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

    func persistLocalVoiceBodyStates() {
        guard persistsLocalVoiceBodyStates else { return }
        let raw = localVoiceBodyStates.reduce(into: [String: String]()) { result, item in
            guard let key = item.value.storageKey else { return }
            result[item.key.uuidString] = key
        }
        UserDefaults.standard.set(raw, forKey: Self.scopedKey(Self.localVoiceBodyStateKey, userId: currentSessionUserId))
    }

    static func loadPendingNoteUpserts(for userId: UUID?) -> [UUID: Note] {
        guard let data = UserDefaults.standard.data(forKey: scopedKey(Self.pendingNoteUpsertsKey, userId: userId)),
              let notes = try? JSONDecoder().decode([Note].self, from: data)
        else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
    }

    func persistPendingNoteUpserts() {
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

    static func loadPendingHardDeletes(for userId: UUID?) -> Set<UUID> {
        let key = scopedKey(Self.pendingHardDeletesKey, userId: userId)
        let raw = (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }

    func persistPendingHardDeletes() {
        guard persistsPendingHardDeletes else { return }
        let key = Self.scopedKey(Self.pendingHardDeletesKey, userId: currentSessionUserId)
        if pendingHardDeletes.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        let raw = pendingHardDeletes.map(\.uuidString).sorted()
        UserDefaults.standard.set(raw, forKey: key)
    }

    func setLocalVoiceBodyState(_ state: NoteBodyState?, for noteId: UUID) {
        if let state, state != .content {
            localVoiceBodyStates[noteId] = state
        } else {
            localVoiceBodyStates.removeValue(forKey: noteId)
        }
        persistLocalVoiceBodyStates()
    }

    func pruneLocalVoiceBodyStates(validNoteIds: Set<UUID>) {
        let filtered = localVoiceBodyStates.filter { validNoteIds.contains($0.key) }
        guard filtered.count != localVoiceBodyStates.count else { return }
        localVoiceBodyStates = filtered
        persistLocalVoiceBodyStates()
    }

    func beginSession(userId: UUID) {
        guard currentSessionUserId != userId else { return }
        cancelAllPendingNoteSyncTasks()
        cancelAllPendingHardDeleteTasks()
        stopRewriteJobPolling()
        rewriteJobsByNoteId = [:]
        activeRewriteIds = []
        rewriteLabelsByNoteId = [:]
        rewriteErrorsByNoteId = [:]
        attemptedRewriteTriggerIds = []
        generatingTitleIds = []
        activeTranscriptionIds = []
        currentSessionUserId = userId
        localVoiceBodyStates = persistsLocalVoiceBodyStates ? Self.loadLocalVoiceBodyStates(for: userId) : localVoiceBodyStates
        pendingNoteUpserts = persistsPendingNoteUpserts ? Self.loadPendingNoteUpserts(for: userId) : pendingNoteUpserts
        pendingHardDeletes = persistsPendingHardDeletes ? Self.loadPendingHardDeletes(for: userId) : pendingHardDeletes
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
        cancelAllPendingHardDeleteTasks()
        stopRewriteJobPolling()
        notes = []
        deletedNotes = []
        categories = []
        rewritesCache = [:]
        rewriteJobsByNoteId = [:]
        selectedCategoryId = nil
        isLoading = false
        hasInitiallyLoaded = false
        lastError = nil
        generatingTitleIds = []
        activeTranscriptionIds = []
        activeRewriteIds = []
        rewriteLabelsByNoteId = [:]
        rewriteErrorsByNoteId = [:]
        attemptedRewriteTriggerIds = []
        localVoiceBodyStates = [:]
        pendingNoteUpserts = [:]
        pendingHardDeletes = []
        noteSyncRevisions = [:]
        categorySyncRevisions = [:]
        currentSessionUserId = nil
    }

    var pendingDeletedNotesById: [UUID: Note] {
        Dictionary(uniqueKeysWithValues: pendingNoteUpserts.values.compactMap { note in
            guard note.deletedAt != nil, !pendingHardDeletes.contains(note.id) else { return nil }
            return (note.id, note)
        })
    }

    func mergedPendingNotes(with remoteNotes: [Note]) -> [Note] {
        let pendingDeletedIds = Set(pendingDeletedNotesById.keys)
        let hiddenIds = pendingDeletedIds.union(pendingHardDeletes)
        var merged = Dictionary(uniqueKeysWithValues: remoteNotes
            .filter { !hiddenIds.contains($0.id) }
            .map { ($0.id, normalizeLocalVoiceNote($0)) })
        for note in pendingNoteUpserts.values where note.deletedAt == nil && !pendingHardDeletes.contains(note.id) {
            merged[note.id] = normalizeLocalVoiceNote(note)
        }
        return merged.values.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    func queuePendingNoteUpsert(_ note: Note) {
        pendingNoteUpserts[note.id] = note
        persistPendingNoteUpserts()
    }

    func clearPendingNoteUpsert(id: UUID, expectedRevision: Int?) {
        guard pendingNoteUpserts[id] != nil else { return }
        if let expectedRevision, (noteSyncRevisions[id] ?? 0) != expectedRevision {
            return
        }
        pendingNoteUpserts.removeValue(forKey: id)
        persistPendingNoteUpserts()
    }

    func queuePendingHardDelete(_ id: UUID) {
        pendingHardDeletes.insert(id)
        persistPendingHardDeletes()
    }

    func clearPendingHardDelete(id: UUID) {
        guard pendingHardDeletes.contains(id) else { return }
        pendingHardDeletes.remove(id)
        persistPendingHardDeletes()
    }

    @discardableResult
    func bumpNoteSyncRevision(for noteId: UUID) -> Int {
        let next = (noteSyncRevisions[noteId] ?? 0) + 1
        noteSyncRevisions[noteId] = next
        return next
    }

    @discardableResult
    func bumpCategorySyncRevision(for categoryId: UUID) -> Int {
        let next = (categorySyncRevisions[categoryId] ?? 0) + 1
        categorySyncRevisions[categoryId] = next
        return next
    }

    func clearPendingNoteSyncTask(id: UUID, token: UUID? = nil) {
        guard token == nil || pendingNoteSyncTokens[id] == token else { return }
        pendingNoteSyncTasks[id] = nil
        pendingNoteSyncTokens[id] = nil
    }

    func cancelPendingNoteSyncTask(id: UUID) {
        pendingNoteSyncTasks[id]?.cancel()
        clearPendingNoteSyncTask(id: id)
    }

    func cancelAllPendingNoteSyncTasks() {
        for task in pendingNoteSyncTasks.values {
            task.cancel()
        }
        pendingNoteSyncTasks = [:]
        pendingNoteSyncTokens = [:]
    }

    func cancelPendingHardDeleteTask(id: UUID) {
        pendingHardDeleteTasks[id]?.cancel()
        pendingHardDeleteTasks[id] = nil
    }

    func cancelAllPendingHardDeleteTasks() {
        for task in pendingHardDeleteTasks.values {
            task.cancel()
        }
        pendingHardDeleteTasks = [:]
    }

    func schedulePendingHardDelete(id: UUID) {
        cancelPendingHardDeleteTask(id: id)
        pendingHardDeleteTasks[id] = Task { [weak self] in
            guard let self else { return }
            await self.syncPendingHardDelete(id: id)
        }
    }

    func flushPendingHardDelete(id: UUID) async {
        cancelPendingHardDeleteTask(id: id)
        await syncPendingHardDelete(id: id)
    }

    func flushPendingHardDeletes() async {
        for id in pendingHardDeletes.sorted(by: { $0.uuidString < $1.uuidString }) {
            await flushPendingHardDelete(id: id)
        }
    }

    func retryPendingHardDeletes() {
        for id in pendingHardDeletes.sorted(by: { $0.uuidString < $1.uuidString }) {
            schedulePendingHardDelete(id: id)
        }
    }

    func syncPendingHardDelete(id: UUID) async {
        guard pendingHardDeletes.contains(id) else {
            pendingHardDeleteTasks[id] = nil
            return
        }

        do {
            try await hardDeleteExecutor(id)
            pendingHardDeleteTasks[id] = nil
            clearPendingHardDelete(id: id)
        } catch {
            pendingHardDeleteTasks[id] = nil
            logger.error("pending hard delete failed for \(id): \(error)")
        }
    }

    func schedulePendingNoteUpsertSync(id: UUID, expectedRevision: Int, delay: Duration) {
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

    func syncPendingNoteUpsert(id: UUID, expectedRevision: Int, token: UUID? = nil) async {
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
}
