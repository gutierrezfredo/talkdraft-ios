import SwiftUI

extension NoteDetailView {
    func presentSpeakerRename(_ key: String) {
        contentFocused = false
        renamingSpeaker = key
        renameText = ""
    }

    func toggleSpeakerSelection(_ key: String) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.snappy) {
            selectedSpeaker = selectedSpeaker == key ? nil : key
        }
    }

    func renameSpeaker(key: String, newName: String) {
        guard !newName.isEmpty else { return }

        func applyRename(to text: String) -> String {
            text
                .components(separatedBy: "\n")
                .map { $0 == key ? newName : $0 }
                .joined(separator: "\n")
                .replacingOccurrences(of: "[\(key)]:", with: "[\(newName)]:")
        }

        editedContent = applyRename(to: editedContent)
        if selectedSpeaker == key {
            selectedSpeaker = newName
        }

        var names = note.speakerNames ?? [:]
        if let originalKey = names.first(where: { $0.value == key })?.key {
            names[originalKey] = newName
        } else {
            names[key] = newName
        }

        var updated = note
        updated.speakerNames = names
        if let original = updated.originalContent {
            updated.originalContent = applyRename(to: original)
        }
        updated.updatedAt = Date()
        noteStore.updateNote(updated)

        noteStore.renameSpeakerInRewrites(noteId: noteId, oldName: key, newName: newName)
        rewrites = noteStore.rewritesCache[noteId] ?? []

        saveChanges()
    }
}
