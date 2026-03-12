import SwiftUI

extension NoteDetailView {
    func resolvedBodyState(for content: String) -> NoteBodyState {
        let strippedContent = NoteAppendPlaceholderEditor.strippedContent(from: content, placeholder: appendPlaceholder)
        let inferredState = NoteBodyState(content: strippedContent, source: note.source)
        if inferredState == .content, note.source == .voice, strippedContent.isEmpty {
            return noteStore.bodyState(for: note)
        }
        return inferredState
    }

    func syncBodyState(with content: String) {
        noteBodyState = resolvedBodyState(for: content)
    }

    // MARK: - Typewriter

    func scrollToTop() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.3)) {
                scrollProxy?.scrollTo("scrollTop", anchor: .top)
            }
        }
    }

    func revealContent(_ text: String) {
        typewriterTask?.cancel()
        typewriterTask = nil
        contentOpacity = 0
        appendPlaceholder = nil
        editedContent = text
        syncBodyState(with: text)
        scrollToTop()
        withAnimation(.easeIn(duration: 0.5)) {
            contentOpacity = 1
        }
    }

    // MARK: - Speaker Names

    func renameSpeaker(key: String, newName: String) {
        guard !newName.isEmpty else { return }

        func applyRename(to text: String) -> String {
            text
                .components(separatedBy: "\n")
                .map { $0 == key ? newName : $0 }
                .joined(separator: "\n")
                .replacingOccurrences(of: "[\(key)]:", with: "[\(newName)]:")
        }

        // Update current displayed content
        editedContent = applyRename(to: editedContent)

        // Update speakerNames: find the original key whose current value is `key`
        var names = note.speakerNames ?? [:]
        if let originalKey = names.first(where: { $0.value == key })?.key {
            names[originalKey] = newName
        } else {
            names[key] = newName
        }

        var updated = note
        updated.speakerNames = names
        // Also rename in originalContent so switching to Original stays consistent
        if let original = updated.originalContent {
            updated.originalContent = applyRename(to: original)
        }
        updated.updatedAt = Date()
        noteStore.updateNote(updated)

        // Rename in all cached rewrites so switching between prompts stays consistent
        noteStore.renameSpeakerInRewrites(noteId: noteId, oldName: key, newName: newName)
        rewrites = noteStore.rewritesCache[noteId] ?? []

        saveChanges()
    }

}
