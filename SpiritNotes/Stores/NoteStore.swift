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

    // MARK: - Category CRUD

    func addCategory(_ category: Category) {
        categories.append(category)
    }

    func updateCategory(_ category: Category) {
        if let index = categories.firstIndex(where: { $0.id == category.id }) {
            categories[index] = category
        }
    }

    func removeCategory(id: UUID) {
        categories.removeAll { $0.id == id }
        // Unassign notes from deleted category
        for i in notes.indices where notes[i].categoryId == id {
            notes[i].categoryId = nil
        }
    }

    func moveCategory(from source: IndexSet, to destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)
        for i in categories.indices {
            categories[i].sortOrder = i
        }
    }
}
