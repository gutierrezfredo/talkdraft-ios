import SwiftUI

enum NoteAppendPlaceholderPhase: Equatable {
    case recording
    case transcribing

    var text: String {
        switch self {
        case .recording:
            return NoteBodyState.recordingPlaceholder
        case .transcribing:
            return NoteBodyState.transcribingPlaceholder
        }
    }
}

struct NoteAppendPlaceholderState: Equatable {
    var phase: NoteAppendPlaceholderPhase
    var fullRange: NSRange
    var placeholderRange: NSRange
}

enum NoteAppendPlaceholderEditor {
    static func insert(
        _ phase: NoteAppendPlaceholderPhase,
        into content: String,
        at position: Int
    ) -> (content: String, placeholder: NoteAppendPlaceholderState) {
        let nsContent = content as NSString
        let safePosition = max(0, min(position, nsContent.length))
        let leading = safePosition > 0 && !isWhitespace(nsContent.character(at: safePosition - 1)) ? " " : ""
        let trailing = safePosition < nsContent.length && !isWhitespace(nsContent.character(at: safePosition)) ? " " : ""
        let inserted = leading + phase.text + trailing
        let updatedContent = nsContent.replacingCharacters(in: NSRange(location: safePosition, length: 0), with: inserted)
        let fullRange = NSRange(location: safePosition, length: (inserted as NSString).length)
        let placeholderRange = NSRange(
            location: safePosition + (leading as NSString).length,
            length: (phase.text as NSString).length
        )
        let placeholder = NoteAppendPlaceholderState(
            phase: phase,
            fullRange: fullRange,
            placeholderRange: placeholderRange
        )
        return (updatedContent, placeholder)
    }

    static func transition(
        _ placeholder: NoteAppendPlaceholderState,
        to phase: NoteAppendPlaceholderPhase,
        in content: String
    ) -> (content: String, placeholder: NoteAppendPlaceholderState)? {
        replace(placeholder, in: content, with: phase.text).map { result in
            (
                result.content,
                NoteAppendPlaceholderState(
                    phase: phase,
                    fullRange: result.fullRange,
                    placeholderRange: result.replacementRange
                )
            )
        }
    }

    static func replace(
        _ placeholder: NoteAppendPlaceholderState,
        in content: String,
        with replacement: String
    ) -> (content: String, replacementRange: NSRange, fullRange: NSRange)? {
        let nsContent = content as NSString
        guard rangeIsValid(placeholder.fullRange, in: nsContent),
              rangeIsValid(placeholder.placeholderRange, in: nsContent)
        else { return nil }

        let updatedContent = nsContent.replacingCharacters(in: placeholder.placeholderRange, with: replacement)
        let leadingLength = placeholder.placeholderRange.location - placeholder.fullRange.location
        let trailingLength = NSMaxRange(placeholder.fullRange) - NSMaxRange(placeholder.placeholderRange)
        let replacementRange = NSRange(
            location: placeholder.fullRange.location + leadingLength,
            length: (replacement as NSString).length
        )
        let fullRange = NSRange(
            location: placeholder.fullRange.location,
            length: leadingLength + replacementRange.length + trailingLength
        )
        return (updatedContent, replacementRange, fullRange)
    }

    static func remove(_ placeholder: NoteAppendPlaceholderState, from content: String) -> String {
        let nsContent = content as NSString
        guard rangeIsValid(placeholder.fullRange, in: nsContent) else { return content }
        return nsContent.replacingCharacters(in: placeholder.fullRange, with: "")
    }

    static func strippedContent(from content: String, placeholder: NoteAppendPlaceholderState?) -> String {
        guard let placeholder else { return content }
        return remove(placeholder, from: content)
    }

    private static func rangeIsValid(_ range: NSRange, in content: NSString) -> Bool {
        range.location != NSNotFound && range.length >= 0 && NSMaxRange(range) <= content.length
    }

    private static func isWhitespace(_ unit: unichar) -> Bool {
        switch unit {
        case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20:
            return true
        default:
            return false
        }
    }
}

extension NoteDetailView {
    // MARK: - Append Recording Actions

    @MainActor
    func startAppendRecording(scrollToBottom: Bool = false) {
        AudioRecorder.prewarmRecordingSession()
        // Use last known cursor position, or end of content if cursor was never placed
        let contentLength = (editedContent as NSString).length
        let position = scrollToBottom ? contentLength : (contentFocused && isCursorReady ? cursorPosition : (lastKnownCursorPosition > 0 ? lastKnownCursorPosition : contentLength))
        appendInsertPosition = min(position, contentLength)
        contentFocused = false
        insertAppendPlaceholder(.recording)
        isAppendRecording = true
        scheduleAppendRecordingStart()
        if scrollToBottom {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeOut(duration: 0.3)) {
                    scrollProxy?.scrollTo("scrollBottom", anchor: .bottom)
                }
            }
        }
    }

    func scheduleAppendRecordingStart() {
        cancelPendingAppendRecordingStart(discardPreparedSession: false)
        appendRecordingStartTask = Task(priority: .userInitiated) { @MainActor in
            guard !Task.isCancelled else { return }
            do {
                try await appendRecorder.startRecording()
                appendRecordingStartTask = nil
            } catch {
                appendRecordingStartTask = nil
                removeAppendPlaceholder()
                isAppendRecording = false
                errorMessage = "Failed to start recording: \(error.localizedDescription)"
            }
        }
    }

    func cancelPendingAppendRecordingStart(discardPreparedSession: Bool = true) {
        appendRecordingStartTask?.cancel()
        appendRecordingStartTask = nil
        if discardPreparedSession, !appendRecorder.isRecording, !appendRecorder.isStarting {
            Task { @MainActor in
                AudioRecorder.discardPreparedRecordingSession()
            }
        }
    }

    func insertAppendPlaceholder(_ phase: NoteAppendPlaceholderPhase) {
        preserveScroll = true
        let inserted = NoteAppendPlaceholderEditor.insert(phase, into: editedContent, at: appendInsertPosition)
        editedContent = inserted.content
        appendPlaceholder = inserted.placeholder
    }

    func removeAppendPlaceholder() {
        preserveScroll = true
        guard let appendPlaceholder else { return }
        editedContent = NoteAppendPlaceholderEditor.remove(appendPlaceholder, from: editedContent)
        self.appendPlaceholder = nil
    }

    func transitionAppendPlaceholder(to phase: NoteAppendPlaceholderPhase) {
        preserveScroll = true
        guard let appendPlaceholder,
              let result = NoteAppendPlaceholderEditor.transition(appendPlaceholder, to: phase, in: editedContent)
        else { return }
        editedContent = result.content
        self.appendPlaceholder = result.placeholder
    }

    func replaceAppendPlaceholder(with text: String) {
        preserveScroll = true
        if let appendPlaceholder,
           let result = NoteAppendPlaceholderEditor.replace(appendPlaceholder, in: editedContent, with: text) {
            editedContent = result.content
            highlightRange = result.replacementRange
            self.appendPlaceholder = nil
            return
        }

        let insertLocation = (editedContent as NSString).length
        let separator = editedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
        editedContent = editedContent + separator + text
        highlightRange = NSRange(location: insertLocation + (separator as NSString).length, length: (text as NSString).length)
    }

    func stopAppendRecording() {
        cancelPendingAppendRecordingStart()
        guard let audioFileURL = appendRecorder.stopRecording() else {
            isAppendRecording = false
            removeAppendPlaceholder()
            return
        }

        isAppendRecording = false
        isAppendTranscribing = true

        transitionAppendPlaceholder(to: .transcribing)

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
                    removeAppendPlaceholder()
                    errorMessage = "Could not transcribe the recording."
                    isAppendTranscribing = false
                    return
                }

                // Replace placeholder with transcribed text
                replaceAppendPlaceholder(with: transcribedText)

                // Save to store + server
                var updated = note
                updated.content = persistedEditedContent
                updated.title = editedTitle.isEmpty ? nil : editedTitle
                updated.updatedAt = Date()
                noteStore.updateNote(updated)
                markCurrentStateAsSaved()
            } catch {
                removeAppendPlaceholder()
                errorMessage = "Transcription failed: \(error.localizedDescription)"
            }
            // Clean up local audio — append recordings don't need to be kept
            try? FileManager.default.removeItem(at: audioFileURL)
            isAppendTranscribing = false
        }
    }

    func cancelAppendRecording() {
        cancelPendingAppendRecordingStart()
        appendRecorder.cancelRecording()
        removeAppendPlaceholder()
        isAppendRecording = false
    }

    func restartAppendRecording() {
        cancelPendingAppendRecordingStart()
        appendRecorder.cancelRecording()
        scheduleAppendRecordingStart()
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
