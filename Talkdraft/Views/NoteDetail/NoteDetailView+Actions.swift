import SwiftUI

extension NoteDetailView {
    // MARK: - Typewriter

    func scrollToTop() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.3)) {
                scrollProxy?.scrollTo("scrollTop", anchor: .top)
            }
        }
    }

    func revealContent(_ text: String) {
        typewriterTask?.cancel()
        typewriterTask = nil
        contentOpacity = 0
        editedContent = text
        scrollToTop()
        withAnimation(.easeIn(duration: 0.5)) {
            contentOpacity = 1
        }
    }

    func syncSavedBaselines(title: String? = nil, content: String? = nil) {
        if let title {
            titleBaseline = title
        }
        if let content {
            contentBaseline = content
        }
    }

    func markCurrentStateAsSaved() {
        syncSavedBaselines(title: editedTitle, content: editedContent)
    }

    func acceptStoreDrivenContent(_ content: String, revealIfNeeded: Bool = false) {
        contentBaseline = content
        if revealIfNeeded {
            contentFocused = false
            revealContent(content)
            return
        }
        withAnimation(.easeOut(duration: 0.4)) {
            editedContent = content
        }
    }

    func acceptResolvedNoteContent(_ content: String, fadeInIfNeeded: Bool = true) {
        contentBaseline = content
        editedContent = content
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
        let resolvedContent = noteStore.resolvedContent(for: note)
        editedContent = resolvedContent
        contentBaseline = resolvedContent
    }

    // MARK: - Speaker Names

    func renameSpeaker(key: String, newName: String) {
        guard !newName.isEmpty else { return }

        func applyRename(to text: String) -> String {
            text
                .components(separatedBy: "\n")
                .map { $0 == key ? newName : $0 }
                .joined(separator: "\n")
                .replacingOccurrences(of: "[\(key)]:", with: "[\(newName)]:")
        }

        // Update current displayed content
        editedContent = applyRename(to: editedContent)

        // Update speakerNames: find the original key whose current value is `key`
        var names = note.speakerNames ?? [:]
        if let originalKey = names.first(where: { $0.value == key })?.key {
            names[originalKey] = newName
        } else {
            names[key] = newName
        }

        var updated = note
        updated.speakerNames = names
        // Also rename in originalContent so switching to Original stays consistent
        if let original = updated.originalContent {
            updated.originalContent = applyRename(to: original)
        }
        updated.updatedAt = Date()
        noteStore.updateNote(updated)

        // Rename in all cached rewrites so switching between prompts stays consistent
        noteStore.renameSpeakerInRewrites(noteId: noteId, oldName: key, newName: newName)
        rewrites = noteStore.rewritesCache[noteId] ?? []

        saveChanges()
    }

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


    // MARK: - Append Recording Actions

    func startAppendRecording(scrollToBottom: Bool = false) {
        // Use last known cursor position, or end of content if cursor was never placed
        let position = scrollToBottom ? editedContent.count : (contentFocused && isCursorReady ? cursorPosition : (lastKnownCursorPosition > 0 ? lastKnownCursorPosition : editedContent.count))
        appendInsertPosition = min(position, editedContent.count)
        contentFocused = false
        insertPlaceholder(NoteBodyState.recordingPlaceholder)
        do {
            try appendRecorder.startRecording()
            isAppendRecording = true
            if scrollToBottom {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        scrollProxy?.scrollTo("scrollBottom", anchor: .bottom)
                    }
                }
            }
        } catch {
            removePlaceholder()
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    func insertPlaceholder(_ placeholder: String) {
        preserveScroll = true
        let pos = min(appendInsertPosition, editedContent.count)
        let index = editedContent.index(editedContent.startIndex, offsetBy: pos)
        let before = editedContent[..<index]
        let after = editedContent[index...]

        // Insert inline — add a space only if adjacent to non-whitespace
        let leading = !before.isEmpty && !before.last!.isWhitespace ? " " : ""
        let trailing = !after.isEmpty && !after.first!.isWhitespace ? " " : ""

        editedContent = before + leading + placeholder + trailing + after
    }

    func removePlaceholder() {
        // Remove placeholder and collapse any double spaces left behind
        for placeholder in [NoteBodyState.recordingPlaceholder, NoteBodyState.transcribingPlaceholder] {
            editedContent = editedContent
                .replacingOccurrences(of: " " + placeholder + " ", with: " ")
                .replacingOccurrences(of: placeholder + " ", with: "")
                .replacingOccurrences(of: " " + placeholder, with: "")
                .replacingOccurrences(of: placeholder, with: "")
        }
    }

    func replacePlaceholder(with text: String) {
        preserveScroll = true
        // Replace whichever placeholder is present
        for placeholder in [NoteBodyState.transcribingPlaceholder, NoteBodyState.recordingPlaceholder] {
            let nsContent = editedContent as NSString
            let placeholderRange = nsContent.range(of: placeholder)
            guard placeholderRange.location != NSNotFound else { continue }

            editedContent = editedContent.replacingOccurrences(of: placeholder, with: text)
            highlightRange = NSRange(location: placeholderRange.location, length: (text as NSString).length)
            return
        }
        // Fallback: append at end
        let insertLocation = (editedContent as NSString).length
        let separator = editedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
        editedContent = editedContent + separator + text
        highlightRange = NSRange(location: insertLocation + (separator as NSString).length, length: (text as NSString).length)
    }

    func stopAppendRecording() {
        guard let audioFileURL = appendRecorder.stopRecording() else {
            isAppendRecording = false
            removePlaceholder()
            return
        }

        isAppendRecording = false
        isAppendTranscribing = true

        // Swap recording placeholder → transcribing placeholder
        preserveScroll = true
        if editedContent.contains(NoteBodyState.recordingPlaceholder) {
            editedContent = editedContent.replacingOccurrences(
                of: NoteBodyState.recordingPlaceholder,
                with: NoteBodyState.transcribingPlaceholder
            )
        }

        Task {
            do {
                let uploadURL = (try? await AudioCompressor.compress(sourceURL: audioFileURL)) ?? audioFileURL
                defer { if uploadURL != audioFileURL { AudioCompressor.cleanup(uploadURL) } }

                let audioData = try Data(contentsOf: uploadURL)
                let fileName = uploadURL.lastPathComponent

                let language = settingsStore.language == "auto" ? nil : settingsStore.language
                let service = TranscriptionService()
                let result = try await service.transcribe(
                    audioData: audioData,
                    fileName: fileName,
                    language: language,
                    userId: authStore.userId,
                    customDictionary: settingsStore.customDictionary
                )

                let transcribedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !transcribedText.isEmpty else {
                    removePlaceholder()
                    errorMessage = "Could not transcribe the recording."
                    isAppendTranscribing = false
                    return
                }

                // Replace placeholder with transcribed text
                replacePlaceholder(with: transcribedText)

                // Save to store + server
                var updated = note
                updated.content = editedContent
                updated.title = editedTitle.isEmpty ? nil : editedTitle
                updated.updatedAt = Date()
                noteStore.updateNote(updated)
                markCurrentStateAsSaved()
            } catch {
                removePlaceholder()
                errorMessage = "Transcription failed: \(error.localizedDescription)"
            }
            // Clean up local audio — append recordings don't need to be kept
            try? FileManager.default.removeItem(at: audioFileURL)
            isAppendTranscribing = false
        }
    }

    func cancelAppendRecording() {
        appendRecorder.cancelRecording()
        removePlaceholder()
        isAppendRecording = false
    }

    func restartAppendRecording() {
        appendRecorder.cancelRecording()
        do {
            try appendRecorder.startRecording()
        } catch {
            isAppendRecording = false
            errorMessage = "Failed to restart recording: \(error.localizedDescription)"
        }
    }

    func toggleAppendPause() {
        if appendRecorder.isPaused {
            appendRecorder.resumeRecording()
        } else {
            appendRecorder.pauseRecording()
        }
    }

    func formattedDuration(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
