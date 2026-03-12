import SwiftUI

extension NoteDetailView {
    func resolvedBodyState(for content: String) -> NoteBodyState {
        NoteBodyState(content: content, source: note.source)
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
        editedContent = text
        syncBodyState(with: text)
        scrollToTop()
        withAnimation(.easeIn(duration: 0.5)) {
            contentOpacity = 1
        }
    }

    func syncSavedBaselines(title: String? = nil, content: String? = nil) {
        if let title {
            titleBaseline = title
        }
        if let content {
            contentBaseline = content
        }
    }

    func markCurrentStateAsSaved() {
        syncSavedBaselines(title: editedTitle, content: editedContent)
    }

    func acceptStoreDrivenContent(_ content: String, revealIfNeeded: Bool = false) {
        contentBaseline = content
        if revealIfNeeded {
            contentFocused = false
            revealContent(content)
            return
        }
        withAnimation(.easeOut(duration: 0.4)) {
            editedContent = content
            syncBodyState(with: content)
        }
    }

    func acceptResolvedNoteContent(_ content: String, fadeInIfNeeded: Bool = true) {
        contentBaseline = content
        editedContent = content
        syncBodyState(with: content)
        if fadeInIfNeeded, contentOpacity == 0 {
            withAnimation(.easeIn(duration: 0.2)) { contentOpacity = 1 }
        }
    }

    func syncStoreTitle(_ title: String) {
        titleBaseline = title
        guard !title.isEmpty else {
            editedTitle = title
            return
        }
        titleTypewriterTask?.cancel()
        editedTitle = ""
        titleTypewriterTask = Task {
            for char in title {
                guard !Task.isCancelled else { break }
                editedTitle.append(char)
                try? await Task.sleep(for: .milliseconds(25))
            }
            titleTypewriterTask = nil
        }
    }

    func cancelContentTypewriterAndRestoreFromStore() {
        typewriterTask?.cancel()
        typewriterTask = nil
        let resolvedContent = noteStore.resolvedContent(for: note)
        editedContent = resolvedContent
        syncBodyState(with: resolvedContent)
        contentBaseline = resolvedContent
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
