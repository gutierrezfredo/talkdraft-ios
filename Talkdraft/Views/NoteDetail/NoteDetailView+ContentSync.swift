import SwiftUI

extension NoteDetailView {
    func resolvedBodyState(for content: String) -> NoteBodyState {
        NoteDetailEditorSession.resolvedBodyState(
            for: content,
            source: note.source,
            fallbackBodyState: noteStore.bodyState(for: note),
            appendPlaceholder: appendPlaceholder
        )
    }

    func syncBodyState(with content: String) {
        editorSession.syncBodyState(resolvedBodyState(for: content))
    }
}
