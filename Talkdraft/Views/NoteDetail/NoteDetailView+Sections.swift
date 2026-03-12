import SwiftUI

extension NoteDetailView {
    @ViewBuilder
    func deadZone(height: CGFloat) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .contentShape(Rectangle())
            .onTapGesture {}
    }

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

            HStack(spacing: 0) {
                Text(note.createdAt, format: .dateTime.month(.wide).day().year())
                Text(" · ")
                    .foregroundStyle(.tertiary)
                Text(note.createdAt, format: .dateTime.hour().minute())
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    var audioPlayerView: some View {
        HStack(spacing: 12) {
            Button {
                guard let url = audioURL else { return }
                player.togglePlayback(url: url)
            } label: {
                ZStack {
                    if player.isBuffering {
                        ProgressView()
                            .tint(Color.brand)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.body)
                            .foregroundStyle(Color.brand)
                    }
                }
                .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(player.isBuffering)

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

    func shimmerLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .fontWeight(.medium)
            .hidden()
            .overlay {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Color.primary.opacity(0.35)
                        LinearGradient(
                            colors: [.clear, Color.primary.opacity(0.95), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.55)
                        .offset(
                            x: rewriteSweep * (geo.size.width + geo.size.width * 0.55)
                                - geo.size.width * 0.55
                        )
                    }
                }
                .mask(
                    Text(text)
                        .font(.subheadline)
                        .fontWeight(.medium)
                )
            }
            .onAppear {
                rewriteSweep = 0
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    rewriteSweep = 1
                }
            }
            .onDisappear { rewriteSweep = 0 }
    }

    var bottomFade: some View {
        let bg = colorScheme == .dark ? Color.darkBackground : Color.warmBackground
        return VStack {
            Spacer()
            LinearGradient(colors: [.clear, bg], startPoint: .top, endPoint: .bottom)
                .frame(height: 160)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    var bottomBarContainer: some View {
        let bg = colorScheme == .dark ? Color.darkBackground : Color.warmBackground
        return VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, bg.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 50)

            bottomBar
                .padding(.vertical, keyboardVisible ? 4 : 0)
                .padding(.bottom, keyboardVisible ? 0 : 12)
                .frame(maxWidth: .infinity)
                .background(bg.opacity(0.5))
        }
    }

    @ToolbarContentBuilder
    func toolbarContent() -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            let activeRewrite = rewrites.first { $0.id == activeRewriteId }
            let label = activeRewriteId == nil ? "Original" : (activeRewrite?.displayLabel ?? "Rewrite")
            ZStack {
                if isRewriting {
                    shimmerLabel(rewritingLabel.isEmpty ? label : rewritingLabel)
                } else {
                    Menu {
                        Section {
                            Button {
                                switchToOriginal()
                            } label: {
                                if activeRewriteId == nil {
                                    Label("Original", systemImage: "checkmark")
                                } else {
                                    Text("Original")
                                }
                            }
                        }
                        Section {
                            ForEach(rewrites) { rewrite in
                                Button {
                                    switchToRewrite(rewrite)
                                } label: {
                                    if rewrite.id == activeRewriteId {
                                        Label(rewrite.displayLabel, systemImage: "checkmark")
                                    } else {
                                        Text(rewrite.displayLabel)
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(label)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            if !rewrites.isEmpty {
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 9))
                                    .fontWeight(.regular)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .frame(maxWidth: 240, alignment: .center)
                        .foregroundStyle(Color.primary)
                    }
                    .disabled(rewrites.isEmpty)
                }
            }
            .opacity(rewriteLabelOpacity)
            .animation(.easeIn(duration: 0.25), value: rewriteLabelOpacity)
        }

        if !isTranscribing {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        startAppendRecording(scrollToBottom: true)
                    } label: {
                        Label("Record More", systemImage: "mic")
                    }
                    .disabled(isAppendRecording || isAppendTranscribing || isRewriting)

                    if note.audioUrl != nil {
                        Button {
                            downloadAudio()
                        } label: {
                            if isDownloadingAudio {
                                Label { Text("Downloading…") } icon: { ProgressView() }
                            } else {
                                Label("Download Audio", systemImage: "arrow.down.circle")
                            }
                        }
                        .disabled(isDownloadingAudio)
                    }

                    if let rewriteId = activeRewriteId,
                       let rewrite = rewrites.first(where: { $0.id == rewriteId }) {
                        Button(role: .destructive) {
                            pendingDeleteRewrite = rewrite
                        } label: {
                            Label("Delete This Rewrite", systemImage: "wand.and.sparkles")
                        }
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Note", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .fontWeight(.medium)
                        .frame(width: 36, height: 36)
                }
            }
        }
    }

    var scrollContent: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 0).id("scrollTop")

            if !isTranscribing {
                deadZone(height: 12)
                metadataRow

                if audioExpanded, audioURL != nil {
                    deadZone(height: 12)
                    audioPlayerView
                        .padding(.horizontal, 24)
                }

                deadZone(height: 20)
                titleField
            }

            if showsTranscribingIndicator {
                transcribingIndicator
            } else if isTranscribing {
                transcribingPlaceholderView
            } else if isWaitingForConnection {
                waitingForConnectionView
                    .padding(.top, 40)
            } else if isTranscriptionFailed {
                transcriptionFailedView
                    .padding(.top, 40)
            } else {
                if !detectedSpeakers.isEmpty {
                    speakerChipsRow
                        .padding(.top, 28)
                        .padding(.horizontal, 24)
                }
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
                    .contentShape(Rectangle())
                    .onTapGesture {}
                contentField
            }
        }
    }

    var titleField: some View {
        Group {
            if isGeneratingTitle {
                Text(titlePhrases[titlePhraseIndex])
                    .font(.brandTitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 24)
            } else {
                TextField("Untitled", text: $editedTitle, axis: .vertical)
                    .font(.brandTitle)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .focused($titleFocused)
                    .padding(.horizontal, 24)
            }
        }
    }

    var speakerChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(detectedSpeakers, id: \.self) { key in
                    let color = speakerColor(for: key)

                    Button {
                        renamingSpeaker = key
                        renameText = ""
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(color)
                                .frame(width: 8, height: 8)
                            Text(key)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(color)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(color.opacity(colorScheme == .dark ? 0.15 : 0.1))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(color.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
            placeholder: "Start typing...",
            speakerColors: speakerColorMap,
            horizontalPadding: 24,
            moveCursorToEnd: $moveCursorToEnd
        )
        .opacity(contentOpacity)
    }

    var keyboardVisible: Bool { contentFocused }

    var bottomBar: some View {
        Group {
            if isAppendRecording {
                NoteDetailAppendRecordingControls(
                    isTranscribing: isAppendTranscribing,
                    isPaused: appendRecorder.isPaused,
                    remainingSeconds: max(0, 900 - Int(appendRecorder.elapsedSeconds)),
                    onCancel: cancelAppendRecording,
                    onRestart: restartAppendRecording,
                    onStop: stopAppendRecording,
                    onTogglePause: toggleAppendPause
                )
            } else {
                NoteDetailNormalBottomBar(
                    keyboardVisible: keyboardVisible,
                    categoryColor: category.map { Color.categoryColor(hex: $0.color) },
                    isAppendTranscribing: isAppendTranscribing,
                    onShowCategoryPicker: presentCategoryPicker,
                    onShowRewriteSheet: presentRewriteSheet,
                    onShare: presentTextShareSheet,
                    onStartAppendRecording: { startAppendRecording() },
                    onDismissKeyboard: { contentFocused = false }
                )
                .sensoryFeedback(.selection, trigger: showCategoryPicker)
            }
        }
    }
}
