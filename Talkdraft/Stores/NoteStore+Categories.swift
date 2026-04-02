import Foundation
import os
import Supabase

private let logger = Logger(subsystem: "com.pleymob.talkdraft", category: "NoteStore")

extension NoteStore {
    // MARK: - Category CRUD

    func addCategory(_ category: Category) {
        guard let userId = currentSessionUserId ?? category.userId else {
            lastError = "Failed to create category"
            return
        }

        var scopedCategory = category
        scopedCategory.userId = userId
        categories.append(scopedCategory)

        Task {
            do {
                try await supabase
                    .from("categories")
                    .insert(scopedCategory)
                    .execute()
            } catch {
                categories.removeAll { $0.id == scopedCategory.id }
                lastError = "Failed to create category"
            }
        }
    }

    func updateCategory(_ category: Category) {
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { return }
        let previous = categories[index]
        let userId = currentSessionUserId ?? previous.userId ?? category.userId
        var scopedCategory = category
        scopedCategory.userId = userId
        categories[index] = scopedCategory
        let revision = bumpCategorySyncRevision(for: category.id)

        Task {
            do {
                if let userId {
                    try await supabase
                        .from("categories")
                        .update(scopedCategory)
                        .eq("id", value: category.id)
                        .eq("user_id", value: userId)
                        .execute()
                } else {
                    try await supabase
                        .from("categories")
                        .update(scopedCategory)
                        .eq("id", value: category.id)
                        .execute()
                }
            } catch {
                guard categorySyncRevisions[category.id] == revision else { return }
                if let i = categories.firstIndex(where: { $0.id == category.id }) {
                    categories[i] = previous
                }
            }
        }
    }

    func removeCategory(id: UUID) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        let removed = categories.remove(at: index)
        let userId = currentSessionUserId ?? removed.userId
        let now = Date()
        let affectedNotes = notes
            .filter { $0.categoryId == id }
            .map { note -> Note in
                var updated = note
                updated.categoryId = nil
                updated.updatedAt = now
                return updated
            }

        for note in affectedNotes {
            updateNote(note)
        }

        Task {
            do {
                if let userId {
                    try await supabase
                        .from("categories")
                        .delete()
                        .eq("id", value: id)
                        .eq("user_id", value: userId)
                        .execute()
                } else {
                    try await supabase
                        .from("categories")
                        .delete()
                        .eq("id", value: id)
                        .execute()
                }
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

        let updates = categories.map { ($0.id, $0.sortOrder, currentSessionUserId ?? $0.userId) }
        Task {
            for (catId, order, userId) in updates {
                let sortUpdate = CategorySortUpdate(sortOrder: order)
                do {
                    if let userId {
                        try await supabase
                            .from("categories")
                            .update(sortUpdate)
                            .eq("id", value: catId)
                            .eq("user_id", value: userId)
                            .execute()
                    } else {
                        try await supabase
                            .from("categories")
                            .update(sortUpdate)
                            .eq("id", value: catId)
                            .execute()
                    }
                } catch {
                    logger.error("moveCategory failed for \(catId): \(error)")
                }
            }
        }
    }
}

private struct CategorySortUpdate: Encodable {
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case sortOrder = "sort_order"
    }
}
