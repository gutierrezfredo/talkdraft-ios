import SwiftUI

extension NoteDetailView {
    func syncSavedBaselines(title: String? = nil, content: String? = nil) {
        editorSession.syncSavedBaselines(title: title, content: content)
    }

    func markCurrentStateAsSaved() {
        editorSession.markCurrentStateAsSaved(persistedContent: persistedEditedContent)
    }

    func acceptStoreDrivenContent(_ content: String, revealIfNeeded: Bool = false) {
        editorSession.syncSavedBaselines(content: content)
        if revealIfNeeded {
            contentFocused = false
            revealContent(content)
            return
        }
        withAnimation(.easeOut(duration: 0.4)) {
            appendPlaceholder = nil
            editorSession.acceptStoreDrivenContent(content, bodyState: resolvedBodyState(for: content))
        }
    }

    func acceptResolvedNoteContent(_ content: String, fadeInIfNeeded: Bool = true) {
        appendPlaceholder = nil
        editorSession.acceptResolvedContent(content, bodyState: resolvedBodyState(for: content))
        if fadeInIfNeeded, contentOpacity == 0 {
            withAnimation(.easeIn(duration: 0.2)) { contentOpacity = 1 }
        }
    }

    func syncStoreTitle(_ title: String) {
        editorSession.syncSavedBaselines(title: title)
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
        let displayContent = noteStore.displayContent(for: note)
        appendPlaceholder = nil
        editedContent = displayContent
        syncBodyState(with: displayContent)
        editorSession.syncSavedBaselines(content: displayContent)
    }
}
