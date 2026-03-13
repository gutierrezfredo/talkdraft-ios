import SwiftUI

extension NoteDetailView {
    var isTranscribing: Bool {
        editedContent == "Transcribing…"
    }

    var isTranscriptionFailed: Bool {
        editedContent == "Transcription failed — tap to edit"
    }

    var isWaitingForConnection: Bool {
        editedContent == "Waiting for connection…"
    }

    var localAudioFileURL: URL? {
        guard let urlString = note.audioUrl,
              let url = URL(string: urlString),
              url.isFileURL,
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    var transcribingIndicator: some View {
        Text("Transcribing…")
            .font(.body)
            .foregroundStyle(Color.brand)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .phaseAnimator([false, true]) { content, pulse in
                content.opacity(pulse ? 0.3 : 1.0)
            } animation: { _ in
                .easeInOut(duration: 1.2)
            }
    }

    var waitingForConnectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "wifi.slash")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text("Waiting for connection…")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .phaseAnimator([false, true]) { content, pulse in
                content.opacity(pulse ? 0.4 : 1.0)
            } animation: { _ in
                .easeInOut(duration: 1.5)
            }

            Text("Will transcribe automatically when online.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }

    var transcriptionFailedView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcription failed")
                .font(.body)
                .foregroundStyle(.secondary)

            if localAudioFileURL != nil {
                Button {
                    retryTranscription()
                } label: {
                    Label("Retry Transcription", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.brand))
                }

                Text("Your audio recording is still saved on this device.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("Audio file is no longer available on this device.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }

    func retryTranscription() {
        guard let audioFileURL = localAudioFileURL else { return }

        editedContent = "Transcribing…"
        noteStore.setNoteContent(id: noteId, content: "Transcribing…")

        let language = settingsStore.language == "auto" ? nil : settingsStore.language
        noteStore.transcribeNote(
            id: noteId,
            audioFileURL: audioFileURL,
            language: language,
            userId: authStore.userId
        )
    }
}
