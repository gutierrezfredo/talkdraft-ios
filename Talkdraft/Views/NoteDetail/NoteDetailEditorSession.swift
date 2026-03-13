import Foundation

struct NoteDetailEditorSession: Equatable {
    var title: String
    var content: String
    var bodyState: NoteBodyState
    var titleBaseline: String
    var contentBaseline: String

    init(title: String, content: String, bodyState: NoteBodyState) {
        self.title = title
        self.content = content
        self.bodyState = bodyState
        self.titleBaseline = title
        self.contentBaseline = content
    }

    func hasUnsavedChanges(persistedContent: String) -> Bool {
        title != titleBaseline || persistedContent != contentBaseline
    }

    mutating func syncSavedBaselines(title: String? = nil, content: String? = nil) {
        if let title {
            titleBaseline = title
        }
        if let content {
            contentBaseline = content
        }
    }

    mutating func markCurrentStateAsSaved(persistedContent: String) {
        syncSavedBaselines(title: title, content: persistedContent)
    }

    mutating func acceptStoreDrivenContent(_ content: String, bodyState: NoteBodyState) {
        contentBaseline = content
        self.content = content
        self.bodyState = bodyState
    }

    mutating func acceptResolvedContent(_ content: String, bodyState: NoteBodyState) {
        contentBaseline = content
        self.content = content
        self.bodyState = bodyState
    }

    mutating func syncBodyState(_ bodyState: NoteBodyState) {
        self.bodyState = bodyState
    }

    static func resolvedBodyState(
        for content: String,
        source: Note.NoteSource,
        fallbackBodyState: NoteBodyState,
        appendPlaceholder: NoteAppendPlaceholderState?
    ) -> NoteBodyState {
        let strippedContent = NoteAppendPlaceholderEditor.strippedContent(from: content, placeholder: appendPlaceholder)
        let inferredState = NoteBodyState(content: strippedContent, source: source)
        if inferredState == .content, source == .voice, strippedContent.isEmpty {
            return fallbackBodyState
        }
        return inferredState
    }
}
