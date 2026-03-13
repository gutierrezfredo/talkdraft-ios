import Foundation

struct RewriteToolbarState {
    let showsLabel: Bool
    let inferredVisibleRewrite: NoteRewrite?
    let effectiveSelectionId: UUID?
    let labelText: String

    init(
        isRewriting: Bool,
        activeRewriteId: UUID?,
        originalContent: String?,
        persistedContent: String,
        rewrites: [NoteRewrite],
        fallbackLabel: String?
    ) {
        showsLabel = isRewriting || activeRewriteId != nil || originalContent != nil || !rewrites.isEmpty

        let activeRewrite = activeRewriteId.flatMap { id in
            rewrites.first { $0.id == id }
        }

        if let activeRewrite {
            inferredVisibleRewrite = activeRewrite
        } else if activeRewriteId == nil,
                  let originalContent,
                  persistedContent != originalContent {
            inferredVisibleRewrite = rewrites.last { $0.content == persistedContent }
        } else {
            inferredVisibleRewrite = nil
        }

        effectiveSelectionId = activeRewriteId ?? inferredVisibleRewrite?.id

        if let inferredVisibleRewrite {
            labelText = inferredVisibleRewrite.displayLabel
        } else if let fallbackLabel {
            labelText = fallbackLabel
        } else if activeRewriteId != nil {
            labelText = "Rewrite"
        } else {
            labelText = "Original"
        }
    }
}
