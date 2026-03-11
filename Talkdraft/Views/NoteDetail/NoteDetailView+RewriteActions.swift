import SwiftUI

extension NoteDetailView {
    // MARK: - Helpers

    func downloadAudio() {
        guard let urlString = note.audioUrl, let url = URL(string: urlString) else { return }

        isDownloadingAudio = true
        Task {
            do {
                let (tempURL, _) = try await URLSession.shared.download(from: url)
                let fileName = note.title.map { $0.prefix(50) + ".m4a" } ?? "audio.m4a"
                let destURL = FileManager.default.temporaryDirectory.appendingPathComponent(String(fileName))
                try? FileManager.default.removeItem(at: destURL)
                try FileManager.default.moveItem(at: tempURL, to: destURL)
                audioShareItem = destURL
            } catch {
                errorMessage = "Failed to download audio"
            }
            isDownloadingAudio = false
        }
    }

    func performRewrite(tone: String?, instructions: String?, toneLabel: String? = nil, toneEmoji: String? = nil) {
        if let emoji = toneEmoji, let name = toneLabel { rewritingLabel = "\(emoji) \(name)" }
        else if let name = toneLabel { rewritingLabel = name }
        else if let instructions { rewritingLabel = String(instructions.prefix(30)) + (instructions.count > 30 ? "…" : "") }
        else { rewritingLabel = "Rewriting…" }
        isRewriting = true
        rewriteLabelOpacity = 1
        Task {
            do {
                let sourceContent = note.originalContent ?? editedContent

                // Preserve original before streaming starts
                var updated = note
                if updated.originalContent == nil {
                    updated.originalContent = editedContent
                    noteStore.updateNote(updated)
                }

                // Stream with typewriter reveal
                scrollToTop()

                let stream = AIService.rewriteStreaming(
                    content: sourceContent,
                    tone: tone,
                    customInstructions: instructions,
                    language: note.language,
                    multiSpeaker: !(note.speakerNames ?? [:]).isEmpty
                )

                // Buffer streamed chunks, reveal progressively by character index
                var fullText = ""
                var revealed = 0
                var firstChunk = true

                for try await chunk in stream {
                    fullText += chunk

                    // Clear old content when first chunk arrives
                    if firstChunk {
                        editedContent = ""
                        firstChunk = false
                    }

                    // Reveal buffered text a few characters at a time
                    while revealed < fullText.count {
                        let end = min(revealed + 3, fullText.count)
                        let startIdx = fullText.index(fullText.startIndex, offsetBy: revealed)
                        let endIdx = fullText.index(fullText.startIndex, offsetBy: end)
                        editedContent += fullText[startIdx..<endIdx]
                        revealed = end
                        try await Task.sleep(for: .milliseconds(15))
                    }
                }

                // Flush any remaining
                if revealed < fullText.count {
                    let startIdx = fullText.index(fullText.startIndex, offsetBy: revealed)
                    editedContent += fullText[startIdx...]
                }

                // Normalize any "- " line starts to "• " (safety net if model ignores prompt)
                editedContent = editedContent
                    .components(separatedBy: "\n")
                    .map { $0.hasPrefix("- ") ? "• " + $0.dropFirst(2) : $0 }
                    .joined(separator: "\n")

                // Save rewrite version
                let rewrite = NoteRewrite(
                    id: UUID(),
                    noteId: noteId,
                    userId: authStore.userId,
                    tone: tone,
                    toneLabel: toneLabel,
                    toneEmoji: toneEmoji,
                    instructions: instructions,
                    content: editedContent,
                    createdAt: Date()
                )
                await noteStore.saveRewrite(rewrite)
                rewrites = noteStore.rewritesCache[noteId] ?? []
                activeRewriteId = rewrite.id
                if rewriteLabelOpacity == 0 {
                    try? await Task.sleep(for: .milliseconds(32))
                    rewriteLabelOpacity = 1
                }

                // Save note content
                updated.content = editedContent
                updated.activeRewriteId = rewrite.id
                updated.title = editedTitle.isEmpty ? nil : editedTitle
                updated.updatedAt = Date()
                noteStore.updateNote(updated)
                markCurrentStateAsSaved()

                // Auto-save custom instructions as a recent preset
                if tone == nil, let instructions, !instructions.isEmpty {
                    RecentPresetsStore.add(instructions: instructions)
                }
            } catch {
                if editedContent.isEmpty {
                    editedContent = note.originalContent ?? note.content
                }
                errorMessage = "Rewrite failed: \(error.localizedDescription)"
            }
            isRewriting = false
        }
    }

    func switchToRewrite(_ rewrite: NoteRewrite) {
        guard rewrite.id != activeRewriteId else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        rewriteLabelOpacity = 0
        activeRewriteId = rewrite.id
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
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            rewriteLabelOpacity = 1
        }
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
        rewriteLabelOpacity = 0
        activeRewriteId = nil
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
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            rewriteLabelOpacity = 1
        }
    }

    func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, hasChanges else { return }
            saveChanges()
        }
    }

    func saveChanges() {
        // Keep the note's displayed content canonical even while a rewrite is active.
        if let rewriteId = activeRewriteId,
           let rewrite = rewrites.first(where: { $0.id == rewriteId }),
           editedContent != rewrite.content {
            var updatedRewrite = rewrite
            updatedRewrite.content = editedContent
            rewrites = rewrites.map { $0.id == rewriteId ? updatedRewrite : $0 }
            noteStore.updateRewrite(updatedRewrite)
        }

        var updated = note
        updated.title = editedTitle.isEmpty ? nil : editedTitle
        updated.content = editedContent
        updated.updatedAt = Date()
        if isInStore {
            noteStore.updateNote(updated)
        } else {
            withAnimation(.snappy) {
                noteStore.addNote(updated)
            }
        }
        markCurrentStateAsSaved()
    }

    func buildShareText() -> String {
        let title = editedTitle.isEmpty ? "" : editedTitle + "\n\n"
        return title + editedContent
    }

}
