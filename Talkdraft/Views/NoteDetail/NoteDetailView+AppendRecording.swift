import SwiftUI

extension NoteDetailView {
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
