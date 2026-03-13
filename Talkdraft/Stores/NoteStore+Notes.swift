import Foundation

extension NoteStore {
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

        await purgeExpiredNotes()
    }

    func setNoteContent(id: UUID, content: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].content = content
        notes[index].updatedAt = Date()
    }

    func addNote(_ note: Note) {
        notes.insert(note, at: 0)

        Task {
            do {
                try await supabase
                    .from("notes")
                    .insert(note)
                    .execute()
            } catch {
                noteStoreLogger.error("addNote sync failed (note saved locally): \(error)")
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
                noteStoreLogger.error("updateNote failed: \(error)")
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
                removed.deletedAt = nil
                deletedNotes.removeAll { $0.id == id }
                notes.insert(removed, at: min(index, notes.count))
            }
        }
    }

    func removeNotes(ids: Set<UUID>) {
        let now = Date()
        var removed = notes.filter { ids.contains($0.id) }
        notes.removeAll { ids.contains($0.id) }
        for i in removed.indices {
            removed[i].deletedAt = now
        }
        deletedNotes.insert(contentsOf: removed, at: 0)

        Task {
            do {
                let update = SoftDeleteUpdate(deletedAt: now)
                try await supabase
                    .from("notes")
                    .update(update)
                    .in("id", values: ids.map(\.uuidString))
                    .execute()
            } catch {
                for i in removed.indices {
                    removed[i].deletedAt = nil
                }
                deletedNotes.removeAll { ids.contains($0.id) }
                notes.append(contentsOf: removed)
                notes.sort { $0.createdAt > $1.createdAt }
            }
        }
    }

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
                noteStoreLogger.error("permanentlyDeleteNote failed: \(error)")
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
                    .in("id", values: ids.map(\.uuidString))
                    .execute()
            } catch {
                for (noteId, prevCategoryId) in previousValues {
                    if let i = notes.firstIndex(where: { $0.id == noteId }) {
                        notes[i].categoryId = prevCategoryId
                    }
                }
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
            noteStoreLogger.error("purgeExpiredNotes failed: \(error)")
        }
    }
}
