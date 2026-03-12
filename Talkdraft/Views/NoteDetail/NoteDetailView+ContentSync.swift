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
}
