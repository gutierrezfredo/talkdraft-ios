import SwiftUI

extension NoteDetailView {
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

    func performRewrite(tone: String?, instructions: String?) {
        isRewriting = true
        Task {
            do {
                let rewriteTone: String?
                let rewriteInstructions: String?
                if tone == "action-items" {
                    rewriteTone = nil
                    rewriteInstructions = "Extract action items from this text. Start with the action items using checkboxes (☐ ) for each task, one per line. Then add two line breaks and include the original content below, cleaned up and organized using bullet points (• ) where appropriate. Do not use markdown formatting (no **, no ##, no backticks). Only use ☐ for action items and • for bullet points. Keep the same language as the original."
                } else {
                    rewriteTone = tone
                    rewriteInstructions = instructions
                }

                let result = try await AIService.rewrite(
                    content: editedContent,
                    tone: rewriteTone,
                    customInstructions: rewriteInstructions,
                    language: note.language
                )
                var updated = note
                if updated.originalContent == nil {
                    updated.originalContent = editedContent
                }
                updated.content = result
                updated.title = editedTitle.isEmpty ? nil : editedTitle
                updated.updatedAt = Date()
                noteStore.updateNote(updated)
                revealContent(result)
            } catch {
                errorMessage = "Rewrite failed: \(error.localizedDescription)"
            }
            isRewriting = false
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
        guard !subscriptionStore.isReadOnly else { return }
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
    }

    func restoreOriginal() {
        guard let original = note.originalContent else { return }
        contentOpacity = 0
        editedContent = original
        var updated = note
        updated.content = original
        updated.originalContent = nil
        updated.updatedAt = Date()
        noteStore.updateNote(updated)
        scrollToTop()
        withAnimation(.easeIn(duration: 0.5)) {
            contentOpacity = 1
        }
    }

    func buildShareText() -> String {
        let title = editedTitle.isEmpty ? "" : editedTitle + "\n\n"
        return title + editedContent
    }
}
