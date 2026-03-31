import SwiftUI

extension NoteDetailView {
    var audioURL: URL? {
        guard let urlString = note.audioUrl else { return nil }
        return URL(string: urlString)
    }

    var bodyState: NoteBodyState {
        noteBodyState
    }

    var isTranscribing: Bool {
        bodyState == .transcribing
    }

    var isTranscriptionFailed: Bool {
        bodyState == .transcriptionFailed
    }

    var isWaitingForConnection: Bool {
        bodyState == .waitingForConnection
    }

    /// Returns the local audio file URL if it still exists on disk,
    /// falling back to the persisted index in case the app was restarted after a failed transcription.
    var localAudioFileURL: URL? {
        noteStore.localAudioFileURL(for: noteId, audioUrl: note.audioUrl)
    }

    var transcribingSubtitle: String {
        transcribingIsLong
            ? whilePhrases[whileIndex].subtitle
            : transcribingPhrases[transcribingPhraseIndex]
    }

    var transcribingLunaPose: LunaPose {
        if transcribingIsLong {
            return whilePhrases[whileIndex].pose
        } else {
            return .moon
        }
    }

    var transcribingIndicator: some View {
        NoteDetailTranscribingIndicatorView(
            lunaPose: transcribingLunaPose,
            subtitle: transcribingSubtitle
        )
    }

    func updateTranscribingPresentation(for state: NoteBodyState) {
        guard state == .transcribing else { return }
        setupTranscribingState()
    }

    func setupTranscribingState() {
        let duration = note.durationSeconds ?? 0
        transcribingIsLong = duration >= 30
        // Derive index from note ID — deterministic per note, no runtime randomness,
        // prevents ghosting from multiple onAppear calls while still rotating across notes.
        let hash = abs(noteId.hashValue)
        if transcribingIsLong {
            whileIndex = hash % whilePhrases.count
        } else {
            transcribingPhraseIndex = hash % transcribingPhrases.count
        }
    }

    var waitingForConnectionView: some View {
        NoteDetailWaitingForConnectionView()
    }

    var transcriptionFailedView: some View {
        NoteDetailTranscriptionFailedView(
            hasLocalAudio: localAudioFileURL != nil,
            onRetry: retryTranscription
        )
    }

    func retryTranscription() {
        guard let audioFileURL = localAudioFileURL else { return }

        // Update local UI only — transcribeNote handles server sync on success
        editedContent = NoteBodyState.transcribingPlaceholder
        noteBodyState = .transcribing
        noteStore.setNoteBodyState(id: noteId, state: .transcribing)

        let language = settingsStore.language == "auto" ? nil : settingsStore.language
        noteStore.transcribeNote(
            id: noteId,
            audioFileURL: audioFileURL,
            language: language,
            userId: authStore.userId,
            customDictionary: settingsStore.customDictionary
        )
    }
}
