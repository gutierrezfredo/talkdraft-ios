import SwiftUI

struct NoteDetailNormalBottomBar: View {
    let keyboardVisible: Bool
    let categoryColor: Color?
    let isAppendTranscribing: Bool
    let onShowCategoryPicker: () -> Void
    let onShowRewriteSheet: () -> Void
    let onShowRewriteSourceOptions: () -> Void
    let onShare: () -> Void
    let onStartAppendRecording: () -> Void
    let onDismissKeyboard: () -> Void

    @State private var suppressNextRewriteTap = false

    var body: some View {
        HStack(spacing: keyboardVisible ? 12 : 40) {
            Button(action: onShowCategoryPicker) {
                Image(systemName: "tag")
                    .font(keyboardVisible ? .callout : .title3)
                    .foregroundStyle(categoryColor ?? .secondary)
                    .frame(width: keyboardVisible ? 40 : 56, height: keyboardVisible ? 40 : 56)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)

            Button {
                if suppressNextRewriteTap {
                    suppressNextRewriteTap = false
                    return
                }
                onShowRewriteSheet()
            } label: {
                if keyboardVisible {
                    Image(systemName: "wand.and.stars")
                        .font(.callout)
                        .foregroundStyle(Color.brand)
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular.interactive(), in: .circle)
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(Color.brand))
                        .glassEffect(.regular.interactive(), in: .circle)
                }
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45)
                    .onEnded { _ in
                        suppressNextRewriteTap = true
                        onShowRewriteSourceOptions()
                    }
            )

            Button(action: onShare) {
                Image(systemName: "arrowshape.turn.up.right")
                    .font(keyboardVisible ? .callout : .title3)
                    .foregroundStyle(.primary)
                    .frame(width: keyboardVisible ? 40 : 56, height: keyboardVisible ? 40 : 56)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)

            if keyboardVisible {
                Spacer()

                Button(action: onStartAppendRecording) {
                    HStack(spacing: 6) {
                        Image(systemName: "mic")
                            .font(.callout)
                        Text("Record")
                            .font(.callout)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(Color.brand)
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(isAppendTranscribing)
                .opacity(isAppendTranscribing ? 0.5 : 1)

                Button(action: onDismissKeyboard) {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, keyboardVisible ? 16 : 20)
        .contentShape(Rectangle())
    }
}

struct NoteDetailAppendRecordingControls: View {
    let isTranscribing: Bool
    let isPaused: Bool
    let remainingSeconds: Int
    let onCancel: () -> Void
    let onRestart: () -> Void
    let onStop: () -> Void
    let onTogglePause: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 20) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)

            Button(action: onRestart) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)

            Button(action: onStop) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(.red)
                    .frame(width: 22, height: 22)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(colorScheme == .dark ? Color.darkSurface : .white))
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)

            Button(action: onTogglePause) {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .overlay(alignment: .top) {
            NoteDetailAppendRecordingPill(
                isTranscribing: isTranscribing,
                remainingSeconds: remainingSeconds
            )
            .offset(y: -44)
        }
    }
}

struct NoteDetailRewriteSourceSheet: View {
    let onRewriteOriginal: () -> Void
    let onRewriteCurrent: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text("Rewrite From")
                .font(.brandTitle2)
                .frame(maxWidth: .infinity, alignment: .leading)

            rewriteOption(
                title: "Rewrite Original",
                systemImage: "doc.text"
            ) {
                onRewriteOriginal()
            }

            rewriteOption(
                title: "Rewrite Current Version",
                systemImage: "wand.and.stars.inverse"
            ) {
                onRewriteCurrent()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func rewriteOption(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.brand)
                    .frame(width: 22)

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
        }
        .buttonStyle(.plain)
    }
}

private struct NoteDetailAppendRecordingPill: View {
    let isTranscribing: Bool
    let remainingSeconds: Int

    var body: some View {
        HStack(spacing: 8) {
            if isTranscribing {
                ProgressView()
                    .controlSize(.small)
                Text(NoteBodyState.transcribingPlaceholder)
                    .font(.subheadline)
                    .fontWeight(.medium)
            } else {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text(formatDuration(remainingSeconds))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .glassEffect(.regular, in: .capsule)
    }

    private func formatDuration(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
