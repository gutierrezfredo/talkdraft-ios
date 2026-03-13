import SwiftUI

extension NoteDetailView {
    func startAppendRecording() {
        appendInsertPosition = min(cursorPosition, editedContent.count)
        contentFocused = false
        insertPlaceholder(Self.recordingPlaceholder)
        do {
            try appendRecorder.startRecording()
            isAppendRecording = true
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

        let leading = !before.isEmpty && !before.last!.isWhitespace ? " " : ""
        let trailing = !after.isEmpty && !after.first!.isWhitespace ? " " : ""

        editedContent = before + leading + placeholder + trailing + after
    }

    func removePlaceholder() {
        for placeholder in [Self.recordingPlaceholder, Self.transcribingPlaceholder] {
            editedContent = editedContent
                .replacingOccurrences(of: " " + placeholder + " ", with: " ")
                .replacingOccurrences(of: placeholder + " ", with: "")
                .replacingOccurrences(of: " " + placeholder, with: "")
                .replacingOccurrences(of: placeholder, with: "")
        }
    }

    func replacePlaceholder(with text: String) {
        preserveScroll = true
        for placeholder in [Self.transcribingPlaceholder, Self.recordingPlaceholder] {
            let nsContent = editedContent as NSString
            let placeholderRange = nsContent.range(of: placeholder)
            guard placeholderRange.location != NSNotFound else { continue }

            editedContent = editedContent.replacingOccurrences(of: placeholder, with: text)
            highlightRange = NSRange(location: placeholderRange.location, length: (text as NSString).length)
            return
        }

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

        preserveScroll = true
        if editedContent.contains(Self.recordingPlaceholder) {
            editedContent = editedContent.replacingOccurrences(
                of: Self.recordingPlaceholder,
                with: Self.transcribingPlaceholder
            )
        }

        Task {
            do {
                let audioData = try Data(contentsOf: audioFileURL)
                let fileName = audioFileURL.lastPathComponent

                let language = settingsStore.language == "auto" ? nil : settingsStore.language
                let service = TranscriptionService()
                let result = try await service.transcribe(
                    audioData: audioData,
                    fileName: fileName,
                    language: language,
                    userId: authStore.userId
                )

                let transcribedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !transcribedText.isEmpty else {
                    removePlaceholder()
                    errorMessage = "Could not transcribe the recording."
                    isAppendTranscribing = false
                    return
                }

                replacePlaceholder(with: transcribedText)

                var updated = note
                updated.content = editedContent
                updated.title = editedTitle.isEmpty ? nil : editedTitle
                updated.updatedAt = Date()
                noteStore.updateNote(updated)
            } catch {
                removePlaceholder()
                errorMessage = "Transcription failed: \(error.localizedDescription)"
            }
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
}
