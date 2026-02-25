import Foundation
import Observation

@MainActor
@Observable
final class NoteStore {
    var notes: [Note] = []
    var categories: [Category] = []
    var selectedCategoryId: UUID?

    var filteredNotes: [Note] {
        guard let categoryId = selectedCategoryId else { return notes }
        return notes.filter { $0.categoryId == categoryId }
    }

    func loadMockData() {
        categories = MockData.categories
        notes = MockData.notes
    }

    func refresh() async {
        // TODO: Fetch notes + categories from Supabase
    }

    func fetchNotes() async throws {
        // TODO: Fetch from Supabase
    }

    func fetchCategories() async throws {
        // TODO: Fetch from Supabase
    }

    func addNote(_ note: Note) {
        notes.insert(note, at: 0)
    }

    func updateNote(_ note: Note) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        }
    }

    func removeNote(id: UUID) {
        notes.removeAll { $0.id == id }
    }
}
