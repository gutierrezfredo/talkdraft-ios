import SwiftUI

struct NoteDetailTranscribingIndicatorView: View {
    let lunaPose: LunaPose
    let subtitle: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.brand.opacity(colorScheme == .dark ? 1.0 : 0.20))
                    .frame(width: 220, height: 220)

                LunaMascotView(lunaPose, size: 180)
            }

            VStack(spacing: 20) {
                ShimmerTextView("Transcribing your note…")
                    .font(.brandTitle2)

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

// MARK: - Shimmer Text

private struct ShimmerTextView: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    @State private var shimmerOffset: CGFloat = -1

    var body: some View {
        Text(text)
            .multilineTextAlignment(.center)
            .overlay {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.6), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 80)
                .offset(x: shimmerOffset)
                .mask {
                    Text(text)
                        .multilineTextAlignment(.center)
                }
            }
            .onAppear {
                withAnimation(
                    .linear(duration: 2.0)
                    .repeatForever(autoreverses: false)
                ) {
                    shimmerOffset = 300
                }
            }
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
