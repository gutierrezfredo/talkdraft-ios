import AVFoundation
import SwiftUI

struct NoteDetailTranscribingIndicatorView: View {
    let videoPlayer: AVQueuePlayer?
    let subtitle: String
    let onAppear: () -> Void
    let onDisappear: () -> Void

    @State private var pulse = false

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.brand.opacity(0.12))
                    .frame(width: 220, height: 220)

                if let videoPlayer {
                    LoopingVideoView(player: videoPlayer)
                        .frame(width: 180, height: 180)
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.brand)
                }
            }
            .onAppear {
                onAppear()
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            .onDisappear {
                onDisappear()
                pulse = false
            }

            VStack(spacing: 8) {
                Text("Transcribing your note…")
                    .font(.brandTitle2)
                    .multilineTextAlignment(.center)
                    .opacity(pulse ? 0.4 : 1.0)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 40)
    }
}

struct NoteDetailWaitingForConnectionView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "wifi.slash")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text(NoteBodyState.waitingForConnectionPlaceholder)
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
}

struct NoteDetailTranscriptionFailedView: View {
    let hasLocalAudio: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcription failed")
                .font(.body)
                .foregroundStyle(.secondary)

            if hasLocalAudio {
                Button(action: onRetry) {
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
}
