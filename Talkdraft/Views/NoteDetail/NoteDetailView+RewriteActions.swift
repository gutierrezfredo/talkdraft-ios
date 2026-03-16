import SwiftUI

extension NoteDetailView {
    func performRewrite(
        tone: String?,
        instructions: String?,
        toneLabel: String? = nil,
        toneEmoji: String? = nil,
        sourceChoice: RewriteSourceChoice = .original
    ) {
        rewriteLabelOpacity = 1
        if let emoji = toneEmoji, let name = toneLabel {
            rewriteLabelFallback = "\(emoji) \(name)"
        } else if let name = toneLabel {
            rewriteLabelFallback = name
        } else if let instructions, !instructions.isEmpty {
            let preview = String(instructions.prefix(30))
            rewriteLabelFallback = instructions.count > 30 ? "\(preview)…" : preview
        } else {
            rewriteLabelFallback = "Rewriting…"
        }

        scrollToTop()
        contentFocused = false

        let rewriteSourceContent: String
        switch sourceChoice {
        case .original:
            rewriteSourceContent = note.originalContent ?? persistedEditedContent
        case .currentVersion:
            rewriteSourceContent = persistedEditedContent
        }

        noteStore.startRewrite(
            for: note,
            title: editedTitle,
            visibleContent: persistedEditedContent,
            sourceContent: rewriteSourceContent,
            userId: authStore.userId,
            tone: tone,
            instructions: instructions,
            toneLabel: toneLabel,
            toneEmoji: toneEmoji
        )

        if tone == nil, let instructions, !instructions.isEmpty {
            RecentPresetsStore.add(instructions: instructions)
        }
    }

    func switchToRewrite(_ rewrite: NoteRewrite) {
        guard rewrite.id != activeRewriteId else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        rewriteLabelOpacity = 1
        activeRewriteId = rewrite.id
        rewriteLabelFallback = nil
        contentOpacity = 0
        editedContent = rewrite.content
        scrollToTop()
        var updated = note
        updated.content = rewrite.content
        updated.activeRewriteId = rewrite.id
        updated.updatedAt = Date()
        noteStore.updateNote(updated)
        syncSavedBaselines(content: rewrite.content)
        withAnimation(.easeIn(duration: 0.4)) { contentOpacity = 1 }
    }

    func deleteActiveRewrite(_ rewrite: NoteRewrite) {
        noteStore.deleteRewrite(rewrite)
        rewrites.removeAll { $0.id == rewrite.id }

        // If there are remaining rewrites, switch to the last one; otherwise restore original
        if let last = rewrites.last {
            switchToRewrite(last)
        } else {
            switchToOriginal()
            // No rewrites left — clear originalContent and activeRewriteId so the note is back to plain state
            var updated = note
            updated.originalContent = nil
            updated.activeRewriteId = nil
            noteStore.updateNote(updated)
        }
    }

    func switchToOriginal() {
        guard let original = note.originalContent else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        rewriteLabelOpacity = 1
        activeRewriteId = nil
        rewriteLabelFallback = nil
        contentOpacity = 0
        editedContent = original
        scrollToTop()
        var updated = note
        updated.content = original
        updated.activeRewriteId = nil
        updated.updatedAt = Date()
        noteStore.updateNote(updated)
        syncSavedBaselines(content: original)
        withAnimation(.easeIn(duration: 0.4)) { contentOpacity = 1 }
    }
}
