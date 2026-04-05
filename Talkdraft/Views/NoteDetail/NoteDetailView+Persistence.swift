import SwiftUI

enum NoteShareTextLogic {
    static func build(title: String, body: String) -> String {
        _ = title
        return NoteTextFormatting.plainDisplayText(for: body)
    }
}

extension NoteDetailView {
    var hasChanges: Bool {
        typewriterTask == nil
            && !isRewriting
            && editorSession.hasUnsavedChanges(persistedContent: persistedEditedContent)
    }

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

    func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, hasChanges else { return }
            saveChanges()
        }
    }

    func saveChanges() {
        let saveableContent = persistedEditedContent

        // Keep the note's displayed content canonical even while a rewrite is active.
        if let rewriteId = activeRewriteId,
           let rewrite = rewrites.first(where: { $0.id == rewriteId }),
           saveableContent != rewrite.content {
            var updatedRewrite = rewrite
            updatedRewrite.content = saveableContent
            rewrites = rewrites.map { $0.id == rewriteId ? updatedRewrite : $0 }
            noteStore.updateRewrite(updatedRewrite)
        }

        var updated = note
        updated.title = editedTitle.isEmpty ? nil : editedTitle
        updated.content = saveableContent
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
        NoteShareTextLogic.build(title: editedTitle, body: persistedEditedContent)
    }

    func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    func presentAfterKeyboardDismiss(_ action: @escaping () -> Void) {
        contentFocused = false
        dismissKeyboard()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            action()
        }
    }

    func presentCategoryPicker() {
        UISelectionFeedbackGenerator().selectionChanged()
        presentAfterKeyboardDismiss {
            showCategoryPicker = true
        }
    }

    func presentRewriteSheet() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        rewriteSourceChoice = .original
        showRewriteSourceDialog = false
        presentAfterKeyboardDismiss {
            showRewriteSheet = true
        }
    }

    func presentRewriteSheet(using sourceChoice: RewriteSourceChoice) {
        rewriteSourceChoice = sourceChoice
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        showRewriteSourceDialog = false
        presentAfterKeyboardDismiss {
            showRewriteSheet = true
        }
    }

    func presentRewriteSourceOptions() {
        guard canChooseRewriteSource else {
            presentRewriteSheet()
            return
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.snappy) {
            showRewriteSourceDialog = true
        }
    }

    func presentTextShareSheet() {
        presentAfterKeyboardDismiss {
            textShareItem = buildShareText()
        }
    }
}
