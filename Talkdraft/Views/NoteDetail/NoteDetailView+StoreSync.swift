import SwiftUI

extension NoteDetailView {
    func syncSavedBaselines(title: String? = nil, content: String? = nil) {
        if let title {
            titleBaseline = title
        }
        if let content {
            contentBaseline = content
        }
    }

    func markCurrentStateAsSaved() {
        syncSavedBaselines(title: editedTitle, content: persistedEditedContent)
    }

    func acceptStoreDrivenContent(_ content: String, revealIfNeeded: Bool = false) {
        contentBaseline = content
        if revealIfNeeded {
            contentFocused = false
            revealContent(content)
            return
        }
        withAnimation(.easeOut(duration: 0.4)) {
            appendPlaceholder = nil
            editedContent = content
            syncBodyState(with: content)
        }
    }

    func acceptResolvedNoteContent(_ content: String, fadeInIfNeeded: Bool = true) {
        contentBaseline = content
        appendPlaceholder = nil
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
        let displayContent = noteStore.displayContent(for: note)
        appendPlaceholder = nil
        editedContent = displayContent
        syncBodyState(with: displayContent)
        contentBaseline = displayContent
    }
}
