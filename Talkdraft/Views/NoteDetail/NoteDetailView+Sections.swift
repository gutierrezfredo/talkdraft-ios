import SwiftUI

extension NoteDetailView {
    var metadataRow: some View {
        HStack(spacing: 12) {
            if let duration = note.durationSeconds, note.audioUrl != nil {
                Button {
                    withAnimation(.snappy(duration: 0.28)) {
                        audioExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .font(.caption2)
                        Text(formattedDuration(Int(duration)))
                            .font(.caption)
                            .monospacedDigit()
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.darkSurface : Color(hex: "#EDE5E2"))
                    )
                }
                .buttonStyle(.plain)
            }

            Text(note.createdAt, format: .dateTime.month(.wide).day().year())
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    var audioPlayerView: some View {
        HStack(spacing: 12) {
            Button {
                guard let url = audioURL else { return }
                player.togglePlayback(url: url)
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.body)
                    .foregroundStyle(Color.brand)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            GeometryReader { geo in
                let progress = player.duration > 0
                    ? player.currentTime / player.duration
                    : 0

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(colorScheme == .dark ? Color(hex: "#2a2a2a") : Color(hex: "#EDE5E2"))
                        .frame(height: 4)

                    Capsule()
                        .fill(Color.brand)
                        .frame(width: max(4, geo.size.width * progress), height: 4)

                    Circle()
                        .fill(Color.brand)
                        .frame(width: 14, height: 14)
                        .offset(x: max(0, geo.size.width * progress - 7))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = max(0, min(1, value.location.x / geo.size.width))
                            player.seek(to: fraction * player.duration)
                        }
                )
            }
            .frame(height: 14)

            Text(formattedDuration(Int(player.currentTime)))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    var titleField: some View {
        TextField("Untitled", text: $editedTitle, axis: .vertical)
            .font(.system(size: 28, weight: .bold))
            .multilineTextAlignment(.center)
            .autocorrectionDisabled()
            .contentTransition(.opacity)
            .disabled(subscriptionStore.isReadOnly)
    }

    var contentField: some View {
        ExpandingTextView(
            text: $editedContent,
            isFocused: $contentFocused,
            cursorPosition: $cursorPosition,
            highlightRange: $highlightRange,
            preserveScroll: $preserveScroll,
            isEditable: !isAppendRecording && !isAppendTranscribing,
            font: .preferredFont(forTextStyle: .body),
            lineSpacing: 6,
            placeholder: "Start typing..."
        )
        .opacity(contentOpacity)
        .disabled(subscriptionStore.isReadOnly)
    }

    var keyboardVisible: Bool { contentFocused }

    var bottomBar: some View {
        Group {
            if isAppendRecording {
                appendRecordingControls
            } else {
                normalBottomBar
            }
        }
    }

    var normalBottomBar: some View {
        HStack(spacing: keyboardVisible ? 12 : 40) {
            Button {
                if !subscriptionStore.isReadOnly {
                    showCategoryPicker = true
                }
            } label: {
                Image(systemName: "tag")
                    .font(keyboardVisible ? .callout : .title3)
                    .foregroundStyle(
                        category.map { Color.categoryColor(hex: $0.color) } ?? .secondary
                    )
                    .frame(width: keyboardVisible ? 40 : 56, height: keyboardVisible ? 40 : 56)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: showCategoryPicker)

            if !subscriptionStore.isReadOnly {
                Button {
                    showRewriteSheet = true
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
            }

            Button {
                textShareItem = buildShareText()
            } label: {
                Image(systemName: "arrowshape.turn.up.right")
                    .font(keyboardVisible ? .callout : .title3)
                    .foregroundStyle(.primary)
                    .frame(width: keyboardVisible ? 40 : 56, height: keyboardVisible ? 40 : 56)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)

            if keyboardVisible && !subscriptionStore.isReadOnly {
                Spacer()

                Button {
                    startAppendRecording()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "mic")
                            .font(.callout)
                        Text("Append")
                            .font(.callout)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(Color.brand)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(isAppendTranscribing)
                .opacity(isAppendTranscribing ? 0.5 : 1)

                Button {
                    contentFocused = false
                } label: {
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

    var appendRecordingControls: some View {
        HStack(spacing: 20) {
            Button {
                cancelAppendRecording()
            } label: {
                Image(systemName: "xmark")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)

            Button {
                restartAppendRecording()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)

            Button {
                stopAppendRecording()
            } label: {
                RoundedRectangle(cornerRadius: 5)
                    .fill(.red)
                    .frame(width: 22, height: 22)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(colorScheme == .dark ? Color.darkSurface : .white))
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)

            Button {
                toggleAppendPause()
            } label: {
                Image(systemName: appendRecorder.isPaused ? "play.fill" : "pause.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }

    var appendRecordingPill: some View {
        HStack(spacing: 8) {
            if isAppendTranscribing {
                ProgressView()
                    .tint(.white)
                    .controlSize(.small)
                Text("Transcribing…")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text(formattedDuration(Int(appendRecorder.elapsedSeconds)))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(Capsule().fill(Color(white: 0.1)))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func formattedDuration(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
