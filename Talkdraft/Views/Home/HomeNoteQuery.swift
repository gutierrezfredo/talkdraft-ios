import Foundation

struct HomeNoteQuery {
    static func filteredNotes(
        notes: [Note],
        selectedCategory: UUID?,
        query: String,
        sortOrder: NoteSortOrder,
        resolvedContent: (Note) -> String
    ) -> [Note] {
        var filtered = selectedCategory == nil
            ? notes
            : notes.filter { $0.categoryId == selectedCategory }

        if !query.isEmpty {
            let lowered = query.lowercased()
            filtered = filtered.filter { note in
                let normalizedContent = NoteTextFormatting.plainDisplayText(for: resolvedContent(note))
                return (note.title?.lowercased().contains(lowered) ?? false)
                    || normalizedContent.lowercased().contains(lowered)
            }
        }

        return filtered.sorted { lhs, rhs in
            switch sortOrder {
            case .updatedAt:
                return lhs.updatedAt > rhs.updatedAt
            case .createdAt:
                return lhs.createdAt > rhs.createdAt
            case .uncategorized:
                if (lhs.categoryId == nil) != (rhs.categoryId == nil) {
                    return lhs.categoryId == nil
                }
                return lhs.updatedAt > rhs.updatedAt
            case .actionItems:
                let lhsHasActionItems = hasActionItems(in: resolvedContent(lhs))
                let rhsHasActionItems = hasActionItems(in: resolvedContent(rhs))
                if lhsHasActionItems != rhsHasActionItems {
                    return lhsHasActionItems
                }
                return lhs.updatedAt > rhs.updatedAt
            }
        }
    }

    private static func hasActionItems(in content: String) -> Bool {
        content.contains("☐") || content.contains("☑")
    }
}
