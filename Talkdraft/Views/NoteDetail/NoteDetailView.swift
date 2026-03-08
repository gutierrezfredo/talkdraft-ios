import SwiftUI

struct NoteDetailView: View {
    @Environment(NoteStore.self) private var noteStore
    @Environment(AuthStore.self) private var authStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    private let noteId: UUID
    private let initialNote: Note

    @State private var editedTitle: String
    @State private var editedContent: String
    @State private var showDeleteConfirmation = false
    @State private var pendingDeleteRewrite: NoteRewrite?
    @State private var didDelete = false
    @State private var showCategoryPicker = false
    @State private var showRewriteSheet = false
    @State private var pendingRewrite: (tone: String?, instructions: String?, toneLabel: String?, toneEmoji: String?)?
    @State private var isRewriting = false
    @State private var rewrites: [NoteRewrite] = []
    @State private var activeRewriteId: UUID?
    @State private var rewriteLabelOpacity: Double = 0
    @State private var audioExpanded = false
    @State private var player = AudioPlayer()
    @State private var typewriterTask: Task<Void, Never>?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var contentFocused = false
    @State private var contentOpacity: Double = 1
    @State private var errorMessage: String?
    @State private var isDownloadingAudio = false
    @State private var audioShareItem: URL?
    @State private var textShareItem: String?
    @State private var appendRecorder = AudioRecorder()
    @State private var isAppendRecording = false
    @State private var isAppendTranscribing = false
    @State private var cursorPosition: Int = 0
    @State private var lastKnownCursorPosition: Int = 0
    @State private var appendInsertPosition: Int = 0
    @State private var highlightRange: NSRange?
    @State private var preserveScroll = false
    @State private var autosaveTask: Task<Void, Never>?
    @State private var keyboardHeight: CGFloat = 0

    private static let recordingPlaceholder = "Recording…"
    private static let transcribingPlaceholder = "Transcribing…"

    init(note: Note) {
        self.noteId = note.id
        self.initialNote = note
        self._editedTitle = State(initialValue: note.title ?? "")
        self._editedContent = State(initialValue: note.content)
        // Auto-focus body for new text notes
        self._contentFocused = State(initialValue: note.source == .text && note.content.isEmpty)
    }

    private var note: Note {
        noteStore.notes.first { $0.id == noteId } ?? initialNote
    }

    private var isInStore: Bool {
        noteStore.notes.contains { $0.id == noteId }
    }

    private var hasChanges: Bool {
        typewriterTask == nil
            && !isRewriting
            && (editedTitle != (note.title ?? "") || editedContent != note.content)
    }

    private var category: Category? {
        noteStore.categories.first { $0.id == note.categoryId }
    }

    private var audioURL: URL? {
        guard let urlString = note.audioUrl else { return nil }
        return URL(string: urlString)
    }

    private var isTranscribing: Bool {
        editedContent == "Transcribing…"
    }

    private var isTranscriptionFailed: Bool {
        editedContent == "Transcription failed — tap to edit"
    }

    private var isWaitingForConnection: Bool {
        editedContent == "Waiting for connection…"
    }

    /// Returns the local audio file URL if it still exists on disk.
    private var localAudioFileURL: URL? {
        guard let urlString = note.audioUrl,
              let url = URL(string: urlString),
              url.isFileURL,
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            (colorScheme == .dark ? Color.darkBackground : Color.warmBackground)
                .ignoresSafeArea()

            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 0).id("scrollTop")

                    metadataRow
                        .padding(.top, 12)

                    if audioExpanded, audioURL != nil {
                        audioPlayerView
                            .padding(.top, 12)
                            .padding(.horizontal, 24)
                    }

                    titleField
                        .padding(.top, 20)
                        .padding(.horizontal, 24)


                    if isTranscribing {
                        transcribingIndicator
                            .padding(.top, 40)
                    } else if isWaitingForConnection {
                        waitingForConnectionView
                            .padding(.top, 40)
                    } else if isTranscriptionFailed {
                        transcriptionFailedView
                            .padding(.top, 40)
                    } else {
                        contentField
                            .padding(.top, 28)
                            .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, keyboardHeight > 0 ? keyboardHeight + 60 : 120)
            }
            .scrollDismissesKeyboard(.interactively)
            .ignoresSafeArea(.keyboard)
            .onAppear { scrollProxy = proxy }
            // Tap zone behind scroll to focus editor
            .contentShape(Rectangle())
            .onTapGesture {
                contentFocused = true
            }
            } // ScrollViewReader

            // Bottom fade
            VStack {
                Spacer()
                LinearGradient(
                    colors: [
                        .clear,
                        colorScheme == .dark ? Color.darkBackground : Color.warmBackground,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 160)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Bottom bar
            if keyboardVisible {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [
                            .clear,
                            (colorScheme == .dark ? Color.darkBackground : Color.warmBackground).opacity(0.5),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 50)

                    bottomBar
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background((colorScheme == .dark ? Color.darkBackground : Color.warmBackground).opacity(0.5))
                }
            } else {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [
                            .clear,
                            (colorScheme == .dark ? Color.darkBackground : Color.warmBackground).opacity(0.5),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 50)

                    bottomBar
                        .padding(.bottom, 12)
                        .frame(maxWidth: .infinity)
                        .background((colorScheme == .dark ? Color.darkBackground : Color.warmBackground).opacity(0.5))
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await noteStore.fetchRewrites(for: noteId)
            rewrites = noteStore.rewritesCache[noteId] ?? []
            activeRewriteId = note.activeRewriteId
            if !rewrites.isEmpty {
                try? await Task.sleep(for: .milliseconds(32))
                rewriteLabelOpacity = 1
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                let activeRewrite = rewrites.first { $0.id == activeRewriteId }
                let label = activeRewriteId == nil ? "Original" : (activeRewrite?.displayLabel ?? "Rewrite")
                ZStack {
                    if isRewriting {
                        HStack(spacing: 6) {
                            ProgressView()
                                .tint(.secondary)
                                .scaleEffect(0.8)
                            Text("Rewriting…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Menu {
                            Button {
                                switchToOriginal()
                            } label: {
                                if activeRewriteId == nil {
                                    Label("Original", systemImage: "checkmark")
                                } else {
                                    Text("Original")
                                }
                            }
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
                        } label: {
                            Text(label)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .frame(width: UIScreen.main.bounds.width * 0.55, alignment: .center)
                                .foregroundStyle(Color.primary)
                        }
                        .disabled(rewrites.isEmpty)
                    }
                }
                .opacity(rewriteLabelOpacity)
                .animation(.easeIn(duration: 0.25), value: rewriteLabelOpacity)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
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
                            Label("Delete this rewrite", systemImage: "wand.and.sparkles")
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
        .alert("Delete this note?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                didDelete = true
                noteStore.removeNote(id: note.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Delete this rewrite?", isPresented: .init(
            get: { pendingDeleteRewrite != nil },
            set: { if !$0 { pendingDeleteRewrite = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let rewrite = pendingDeleteRewrite {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    deleteActiveRewrite(rewrite)
                    pendingDeleteRewrite = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerSheet(
                note: note
            )
            .presentationDetents([.medium, .large])
            .presentationBackground {
                SheetBackground()
            }
        }
        .sheet(isPresented: $showRewriteSheet, onDismiss: {
            guard let rewrite = pendingRewrite else { return }
            pendingRewrite = nil
            performRewrite(tone: rewrite.tone, instructions: rewrite.instructions, toneLabel: rewrite.toneLabel, toneEmoji: rewrite.toneEmoji)
        }) {
            RewriteSheet { tone, instructions, toneLabel, toneEmoji in
                pendingRewrite = (tone, instructions, toneLabel, toneEmoji)
            }
            .presentationDetents([.large])
            .presentationContentInteraction(.scrolls)
            .presentationBackground {
                SheetBackground()
            }
        }
        .onDisappear {
            player.stop()
            if isAppendRecording {
                if appendRecorder.elapsedSeconds >= 1 {
                    // Stop and transcribe in background — don't discard what was recorded
                    stopAppendRecording()
                } else {
                    appendRecorder.cancelRecording()
                    removePlaceholder()
                    isAppendRecording = false
                }
            }
            autosaveTask?.cancel()
            guard !didDelete else { return }
            let hasContent = !editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !editedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if hasContent && (hasChanges || !isInStore) {
                saveChanges()
            }
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }

        .sheet(isPresented: .init(
            get: { audioShareItem != nil },
            set: { if !$0 { audioShareItem = nil } }
        )) {
            if let audioShareItem {
                ShareSheet(items: [audioShareItem])
                    .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: .init(
            get: { textShareItem != nil },
            set: { if !$0 { textShareItem = nil } }
        )) {
            if let textShareItem {
                ShareSheet(items: [textShareItem])
                    .presentationDetents([.medium])
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: audioExpanded)
        .onChange(of: audioExpanded) { _, expanded in
            if expanded, let url = audioURL {
                player.preload(url: url)
            }
        }
        .onChange(of: note.content) { oldValue, newValue in
            if editedContent == oldValue {
                let isPlaceholder = oldValue == "Transcribing…"
                    || oldValue == "Waiting for connection…"
                    || oldValue == "Transcription failed — tap to edit"
                if isPlaceholder && newValue != oldValue {
                    revealContent(newValue)
                } else {
                    withAnimation(.easeOut(duration: 0.4)) {
                        editedContent = newValue
                    }
                }
            }
        }
        .onChange(of: note.title) { oldValue, newValue in
            if editedTitle == (oldValue ?? "") {
                withAnimation(.easeOut(duration: 0.4)) {
                    editedTitle = newValue ?? ""
                }
            }
        }
        .onChange(of: contentFocused) { _, focused in
            if focused, typewriterTask != nil {
                typewriterTask?.cancel()
                typewriterTask = nil
                editedContent = note.content
            }
        }
        .onDisappear {
            typewriterTask?.cancel()
        }
        .onChange(of: editedTitle) {
            scheduleAutosave()
        }
        .onChange(of: editedContent) {
            scheduleAutosave()
        }
        .onChange(of: cursorPosition) { _, newPos in
            if contentFocused && newPos > 0 {
                lastKnownCursorPosition = newPos
            }
        }
        .onChange(of: appendRecorder.elapsedSeconds) { _, elapsed in
            if Int(elapsed) >= 900 && appendRecorder.isRecording {
                stopAppendRecording()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.easeOut(duration: 0.25)) {
                    keyboardHeight = frame.height
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = 0
            }
        }
    }

    // MARK: - Metadata Row

    private var metadataRow: some View {
        HStack(spacing: 12) {
            // Audio pill
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

            // Date
            (Text(note.createdAt, format: .dateTime.month(.wide).day().year())
                + Text(" · ").foregroundStyle(.tertiary)
                + Text(note.createdAt, format: .dateTime.hour().minute()))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Audio Player

    private var audioPlayerView: some View {
        HStack(spacing: 12) {
            // Play button
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

            // Progress bar
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

            // Time
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

    // MARK: - Title

    private var titleField: some View {
        TextField("Untitled", text: $editedTitle, axis: .vertical)
            .font(.brandTitle)
            .multilineTextAlignment(.center)
            .autocorrectionDisabled()
            .contentTransition(.opacity)
    }

    // MARK: - Transcribing Indicator

    private var transcribingIndicator: some View {
        Text("Transcribing…")
            .font(.body)
            .italic()
            .foregroundStyle(Color.brand)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .phaseAnimator([false, true]) { content, pulse in
                content.opacity(pulse ? 0.3 : 1.0)
            } animation: { _ in
                .easeInOut(duration: 1.2)
            }
    }

    // MARK: - Waiting for Connection

    private var waitingForConnectionView: some View {
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

    // MARK: - Transcription Failed

    private var transcriptionFailedView: some View {
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

    private func retryTranscription() {
        guard let audioFileURL = localAudioFileURL else { return }

        // Update local UI only — transcribeNote handles server sync on success
        editedContent = "Transcribing…"
        noteStore.setNoteContent(id: noteId, content: "Transcribing…")

        let language = settingsStore.language == "auto" ? nil : settingsStore.language
        noteStore.transcribeNote(
            id: noteId,
            audioFileURL: audioFileURL,
            language: language,
            userId: authStore.userId,
            customDictionary: settingsStore.customDictionary
        )
    }

    // MARK: - Content

    private var contentField: some View {
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
    }

    private var keyboardVisible: Bool { contentFocused }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        Group {
            if isAppendRecording {
                appendRecordingControls
            } else {
                normalBottomBar
            }
        }
    }

    private var normalBottomBar: some View {
        HStack(spacing: keyboardVisible ? 12 : 40) {
            // Tag
            Button {
                showCategoryPicker = true
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

            // Rewrite
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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

            // Share
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

            if keyboardVisible {
                Spacer()

                // Append recording
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
                    .frame(height: 50)
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

    // MARK: - Append Recording Controls

    private var appendRecordingControls: some View {
        HStack(spacing: 20) {
            // Cancel
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

            // Restart
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

            // Stop (red square)
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

            // Pause / Resume
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
        .overlay(alignment: .top) {
            appendRecordingPill
                .offset(y: -44)
        }
    }

    // MARK: - Append Recording Pill

    private var appendRecordingPill: some View {
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
                Text(formattedDuration(max(0, 900 - Int(appendRecorder.elapsedSeconds))))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(Capsule().fill(Color(white: 0.1)))
    }

    // MARK: - Typewriter

    private func scrollToTop() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.3)) {
                scrollProxy?.scrollTo("scrollTop", anchor: .top)
            }
        }
    }

    private func revealContent(_ text: String) {
        typewriterTask?.cancel()
        typewriterTask = nil
        contentOpacity = 0
        editedContent = text
        scrollToTop()
        withAnimation(.easeIn(duration: 0.5)) {
            contentOpacity = 1
        }
    }

    // MARK: - Helpers

    private func downloadAudio() {
        guard let urlString = note.audioUrl, let url = URL(string: urlString) else { return }

        isDownloadingAudio = true
        Task {
            do {
                let (tempURL, _) = try await URLSession.shared.download(from: url)
                let fileName = note.title.map { $0.prefix(50) + ".m4a" } ?? "audio.m4a"
                let destURL = FileManager.default.temporaryDirectory.appendingPathComponent(String(fileName))
                try? FileManager.default.removeItem(at: destURL)
                try FileManager.default.moveItem(at: tempURL, to: destURL)
                audioShareItem = destURL
            } catch {
                errorMessage = "Failed to download audio"
            }
            isDownloadingAudio = false
        }
    }

    private func performRewrite(tone: String?, instructions: String?, toneLabel: String? = nil, toneEmoji: String? = nil) {
        isRewriting = true
        Task {
            do {
                let sourceContent = note.originalContent ?? editedContent

                // Preserve original before streaming starts
                var updated = note
                if updated.originalContent == nil {
                    updated.originalContent = editedContent
                    noteStore.updateNote(updated)
                }

                // Stream with typewriter reveal
                scrollToTop()

                let stream = AIService.rewriteStreaming(
                    content: sourceContent,
                    tone: tone,
                    customInstructions: instructions,
                    language: note.language
                )

                // Buffer streamed chunks, reveal progressively by character index
                var fullText = ""
                var revealed = 0
                var firstChunk = true

                for try await chunk in stream {
                    fullText += chunk

                    // Clear old content when first chunk arrives
                    if firstChunk {
                        editedContent = ""
                        firstChunk = false
                    }

                    // Reveal buffered text a few characters at a time
                    while revealed < fullText.count {
                        let end = min(revealed + 3, fullText.count)
                        let startIdx = fullText.index(fullText.startIndex, offsetBy: revealed)
                        let endIdx = fullText.index(fullText.startIndex, offsetBy: end)
                        editedContent += fullText[startIdx..<endIdx]
                        revealed = end
                        try await Task.sleep(for: .milliseconds(15))
                    }
                }

                // Flush any remaining
                if revealed < fullText.count {
                    let startIdx = fullText.index(fullText.startIndex, offsetBy: revealed)
                    editedContent += fullText[startIdx...]
                }

                // Save rewrite version
                let rewrite = NoteRewrite(
                    id: UUID(),
                    noteId: noteId,
                    userId: authStore.userId,
                    tone: tone,
                    toneLabel: toneLabel,
                    toneEmoji: toneEmoji,
                    instructions: instructions,
                    content: editedContent,
                    createdAt: Date()
                )
                await noteStore.saveRewrite(rewrite)
                rewrites = noteStore.rewritesCache[noteId] ?? []
                activeRewriteId = rewrite.id
                if rewriteLabelOpacity == 0 {
                    try? await Task.sleep(for: .milliseconds(32))
                    rewriteLabelOpacity = 1
                }

                // Save note content
                updated.content = editedContent
                updated.activeRewriteId = rewrite.id
                updated.title = editedTitle.isEmpty ? nil : editedTitle
                updated.updatedAt = Date()
                noteStore.updateNote(updated)

                // Auto-save custom instructions as a recent preset
                if tone == nil, let instructions, !instructions.isEmpty {
                    RecentPresetsStore.add(instructions: instructions)
                }
            } catch {
                if editedContent.isEmpty {
                    editedContent = note.originalContent ?? note.content
                }
                errorMessage = "Rewrite failed: \(error.localizedDescription)"
            }
            isRewriting = false
        }
    }

    private func switchToRewrite(_ rewrite: NoteRewrite) {
        guard rewrite.id != activeRewriteId else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        rewriteLabelOpacity = 0
        activeRewriteId = rewrite.id
        contentOpacity = 0
        editedContent = rewrite.content
        scrollToTop()
        var updated = note
        updated.content = rewrite.content
        updated.activeRewriteId = rewrite.id
        updated.updatedAt = Date()
        noteStore.updateNote(updated)
        withAnimation(.easeIn(duration: 0.4)) { contentOpacity = 1 }
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            rewriteLabelOpacity = 1
        }
    }

    private func deleteActiveRewrite(_ rewrite: NoteRewrite) {
        noteStore.deleteRewrite(rewrite)
        rewrites.removeAll { $0.id == rewrite.id }

        // If there are remaining rewrites, switch to the last one; otherwise restore original
        if let last = rewrites.last {
            switchToRewrite(last)
        } else {
            switchToOriginal()
            // No rewrites left — clear originalContent and activeRewriteId so the note is back to plain state
            var updated = note
            updated.originalContent = nil
            updated.activeRewriteId = nil
            noteStore.updateNote(updated)
        }
    }

    private func switchToOriginal() {
        guard let original = note.originalContent else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        rewriteLabelOpacity = 0
        activeRewriteId = nil
        contentOpacity = 0
        editedContent = original
        scrollToTop()
        var updated = note
        updated.content = original
        updated.activeRewriteId = nil
        updated.updatedAt = Date()
        noteStore.updateNote(updated)
        withAnimation(.easeIn(duration: 0.4)) { contentOpacity = 1 }
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            rewriteLabelOpacity = 1
        }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, hasChanges else { return }
            saveChanges()
        }
    }

    private func saveChanges() {
        var updated = note
        updated.title = editedTitle.isEmpty ? nil : editedTitle
        updated.content = editedContent
        updated.updatedAt = Date()
        if isInStore {
            noteStore.updateNote(updated)
        } else {
            withAnimation(.snappy) {
                noteStore.addNote(updated)
            }
        }
    }

    private func buildShareText() -> String {
        let title = editedTitle.isEmpty ? "" : editedTitle + "\n\n"
        return title + editedContent
    }


    // MARK: - Append Recording Actions

    private func startAppendRecording() {
        // Use last known cursor position, or end of content if cursor was never placed
        let position = lastKnownCursorPosition > 0 ? lastKnownCursorPosition : editedContent.count
        appendInsertPosition = min(position, editedContent.count)
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

    private func insertPlaceholder(_ placeholder: String) {
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

    private func removePlaceholder() {
        // Remove placeholder and collapse any double spaces left behind
        for placeholder in [Self.recordingPlaceholder, Self.transcribingPlaceholder] {
            editedContent = editedContent
                .replacingOccurrences(of: " " + placeholder + " ", with: " ")
                .replacingOccurrences(of: placeholder + " ", with: "")
                .replacingOccurrences(of: " " + placeholder, with: "")
                .replacingOccurrences(of: placeholder, with: "")
        }
    }

    private func replacePlaceholder(with text: String) {
        preserveScroll = true
        // Replace whichever placeholder is present
        for placeholder in [Self.transcribingPlaceholder, Self.recordingPlaceholder] {
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

    private func stopAppendRecording() {
        guard let audioFileURL = appendRecorder.stopRecording() else {
            isAppendRecording = false
            removePlaceholder()
            return
        }

        isAppendRecording = false
        isAppendTranscribing = true

        // Swap recording placeholder → transcribing placeholder
        preserveScroll = true
        if editedContent.contains(Self.recordingPlaceholder) {
            editedContent = editedContent.replacingOccurrences(
                of: Self.recordingPlaceholder,
                with: Self.transcribingPlaceholder
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
            } catch {
                removePlaceholder()
                errorMessage = "Transcription failed: \(error.localizedDescription)"
            }
            // Clean up local audio — append recordings don't need to be kept
            try? FileManager.default.removeItem(at: audioFileURL)
            isAppendTranscribing = false
        }
    }

    private func cancelAppendRecording() {
        appendRecorder.cancelRecording()
        removePlaceholder()
        isAppendRecording = false
    }

    private func restartAppendRecording() {
        appendRecorder.cancelRecording()
        do {
            try appendRecorder.startRecording()
        } catch {
            isAppendRecording = false
            errorMessage = "Failed to restart recording: \(error.localizedDescription)"
        }
    }

    private func toggleAppendPause() {
        if appendRecorder.isPaused {
            appendRecorder.resumeRecording()
        } else {
            appendRecorder.pauseRecording()
        }
    }

    private func formattedDuration(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Category Picker Sheet

private struct CategoryPickerSheet: View {
    @Environment(NoteStore.self) private var noteStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let note: Note

    @State private var selectedCategoryId: UUID?
    @State private var showAddCategory = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Category grid
                    FlowLayout(spacing: 8) {
                        ForEach(noteStore.categories) { cat in
                            let isSelected = selectedCategoryId == cat.id
                            Button {
                                selectedCategoryId = cat.id
                                var updated = note
                                updated.categoryId = cat.id
                                updated.updatedAt = Date()
                                noteStore.updateNote(updated)
                                dismiss()
                            } label: {
                                Text(cat.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.categoryColor(hex: cat.color))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: 200)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .background(
                                        Capsule()
                                            .fill(colorScheme == .dark ? Color.darkSurface : .white.opacity(0.7))
                                    )
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(
                                                isSelected ? Color.categoryColor(hex: cat.color) : .clear,
                                                lineWidth: 2
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        // Add category button
                        Button {
                            showAddCategory = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    Capsule()
                                        .fill(colorScheme == .dark ? Color.darkSurface : .white.opacity(0.7))
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                    // Remove category
                    if selectedCategoryId != nil {
                        Button {
                            selectedCategoryId = nil
                            var updated = note
                            updated.categoryId = nil
                            updated.updatedAt = Date()
                            noteStore.updateNote(updated)
                            dismiss()
                        } label: {
                            Text("Remove category")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 20)
            }
            .navigationTitle("Move to category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.semibold)
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: selectedCategoryId)
        }
        .sheet(isPresented: $showAddCategory) {
            CategoryFormSheet(mode: .add) { newCategory in
                selectedCategoryId = newCategory.id
                var updated = note
                updated.categoryId = newCategory.id
                updated.updatedAt = Date()
                noteStore.updateNote(updated)
            }
        }
        .onAppear {
            selectedCategoryId = note.categoryId
        }
    }
}

// MARK: - Recent Presets

private struct RecentPreset: Codable, Identifiable {
    let id: UUID
    var instructions: String
    var pinned: Bool
    var usedAt: Date

    init(instructions: String) {
        self.id = UUID()
        self.instructions = instructions
        self.pinned = false
        self.usedAt = Date()
    }
}

private enum RecentPresetsStore {
    private static let key = "recentRewritePresets"
    private static let maxRecents = 8

    static var all: [RecentPreset] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([RecentPreset].self, from: data)) ?? []
    }

    static func add(instructions: String) {
        var presets = all
        // Don't duplicate — just bump to top
        presets.removeAll { $0.instructions == instructions }
        presets.insert(RecentPreset(instructions: instructions), at: 0)
        // Keep pinned + cap unpinned at maxRecents
        let pinned = presets.filter(\.pinned)
        let unpinned = presets.filter { !$0.pinned }.prefix(maxRecents)
        save(pinned + unpinned)
    }

    static func togglePin(id: UUID) {
        var presets = all
        guard let i = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[i].pinned.toggle()
        save(presets)
    }

    static func remove(id: UUID) {
        var presets = all
        presets.removeAll { $0.id == id }
        save(presets)
    }

    private static func save(_ presets: [RecentPreset]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(presets), forKey: key)
    }
}

// MARK: - Rewrite Sheet

private struct RewriteTone: Identifiable {
    let id: String
    let label: String
    let emoji: String
    let description: String
}

private struct RewriteFormat: Identifiable {
    let id: String
    let label: String
    let emoji: String
    let color: Color
    let tones: [RewriteTone]
}

private let rewriteFormats: [RewriteFormat] = [
    RewriteFormat(id: "text-editing", label: "Text Editing", emoji: "✏️", color: .blue, tones: [
        RewriteTone(id: "edit-grammar", label: "Grammar", emoji: "✨", description: "Fix grammar, punctuation, and flow"),
        RewriteTone(id: "edit-shorter", label: "Shorter", emoji: "⚡", description: "Reduce length, keep the meaning"),
        RewriteTone(id: "edit-list", label: "List", emoji: "📋", description: "Convert into bullet points"),
        RewriteTone(id: "extract-actions", label: "Action Items", emoji: "✅", description: "Pull out tasks as checkboxes"),
    ]),
    RewriteFormat(id: "emails", label: "Emails", emoji: "📧", color: .cyan, tones: [
        RewriteTone(id: "email-casual", label: "Casual Email", emoji: "😎", description: "Compose an informal email"),
        RewriteTone(id: "email-formal", label: "Formal Email", emoji: "👔", description: "Compose a professional email"),
    ]),
    RewriteFormat(id: "content", label: "Content Creation", emoji: "📱", color: .purple, tones: [
        RewriteTone(id: "content-blog", label: "Blog Post", emoji: "📝", description: "Intro, body, and conclusion"),
        RewriteTone(id: "content-facebook", label: "Facebook Post", emoji: "👍", description: "Conversational and engaging"),
        RewriteTone(id: "content-linkedin", label: "LinkedIn Post", emoji: "💼", description: "Professional with a takeaway"),
        RewriteTone(id: "content-instagram", label: "Instagram Post", emoji: "📸", description: "Punchy caption with line breaks"),
        RewriteTone(id: "content-x-post", label: "X Post", emoji: "𝕏", description: "Under 280 characters"),
        RewriteTone(id: "content-x-thread", label: "X Thread", emoji: "🧵", description: "Numbered tweets, each under 280"),
        RewriteTone(id: "content-video-script", label: "Video Script", emoji: "🎬", description: "Hook, sections, and CTA"),
        RewriteTone(id: "content-newsletter", label: "Newsletter", emoji: "📰", description: "Engaging intro and sign-off"),
    ]),
    RewriteFormat(id: "journaling", label: "Journaling", emoji: "📓", color: .indigo, tones: [
        RewriteTone(id: "journal-entry", label: "Journal Entry", emoji: "✍️", description: "Reflective and introspective"),
        RewriteTone(id: "journal-gratitude", label: "Gratitude", emoji: "🙏", description: "Focus on what to be thankful for"),
        RewriteTone(id: "journal-therapy", label: "Therapy Notes", emoji: "🧠", description: "Polish session notes, preserve raw thoughts"),
    ]),
    RewriteFormat(id: "personal", label: "Personal", emoji: "🏠", color: .green, tones: [
        RewriteTone(id: "personal-grocery", label: "Grocery List", emoji: "🛒", description: "Extract items, group by category"),
        RewriteTone(id: "personal-meal", label: "Meal Planner", emoji: "🍽️", description: "Organize meals with ingredients"),
        RewriteTone(id: "personal-study", label: "Study Notes", emoji: "📚", description: "Headings, bullets, key concepts"),
    ]),
    RewriteFormat(id: "work", label: "Work", emoji: "💼", color: .orange, tones: [
        RewriteTone(id: "work-brainstorm", label: "Brainstorming", emoji: "💡", description: "Group and organize ideas"),
        RewriteTone(id: "work-progress", label: "Progress Report", emoji: "📊", description: "Done, status, and next steps"),
        RewriteTone(id: "work-slides", label: "Presentation Slides", emoji: "🖥️", description: "Slide titles with bullet points"),
        RewriteTone(id: "work-speech", label: "Speech Outline", emoji: "🎤", description: "Hook, key points, and closing"),
        RewriteTone(id: "work-linkedin-msg", label: "LinkedIn Message", emoji: "💬", description: "Brief connection message"),
    ]),
    RewriteFormat(id: "style", label: "Writing Style", emoji: "🎨", color: .pink, tones: [
        RewriteTone(id: "style-casual", label: "Casual", emoji: "😎", description: "Relaxed, like texting a friend"),
        RewriteTone(id: "style-friendly", label: "Friendly", emoji: "😊", description: "Warm and approachable"),
        RewriteTone(id: "style-confident", label: "Confident", emoji: "💪", description: "Bold and assertive"),
        RewriteTone(id: "style-professional", label: "Professional", emoji: "💼", description: "Polished and work-ready"),
    ]),
    RewriteFormat(id: "summary", label: "Summary", emoji: "📄", color: .yellow, tones: [
        RewriteTone(id: "summary-detailed", label: "Detailed Summary", emoji: "📖", description: "All key points and context"),
        RewriteTone(id: "summary-short", label: "Short Summary", emoji: "⚡", description: "Essential points in 2-3 sentences"),
        RewriteTone(id: "summary-meeting", label: "Meeting Takeaways", emoji: "🤝", description: "Decisions, actions, follow-ups"),
    ]),
]

private struct RewriteSheet: View {
    /// (toneId, instructions, toneLabel, toneEmoji)
    let onSelect: (String?, String?, String?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedTab = 0
    @State private var customInstructions = ""
    @State private var searchText = ""
    @State private var keyboardVisible = false
    @State private var recentPresets: [RecentPreset] = RecentPresetsStore.all
    @AppStorage("rewriteFavorites") private var favoritesData = Data()
    @FocusState private var customFocused: Bool

    private var favoriteIds: Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: favoritesData)) ?? []
    }

    private func toggleFavorite(_ toneId: String) {
        var ids = favoriteIds
        if ids.contains(toneId) {
            ids.remove(toneId)
        } else {
            ids.insert(toneId)
        }
        favoritesData = (try? JSONEncoder().encode(ids)) ?? Data()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text("Presets").tag(0)
                    Text("Custom").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .animation(.snappy, value: selectedTab)
                .onChange(of: selectedTab) {
                    customFocused = false
                }

                if selectedTab == 0 {
                    presetsView
                } else {
                    customView
                }
            }
            .navigationTitle("Rewrite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .interactiveDismissDisabled(keyboardVisible)
        .onAppear { recentPresets = RecentPresetsStore.all }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
    }

    // MARK: - Presets

    private var filteredFormats: [(format: RewriteFormat, tones: [RewriteTone])] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else {
            return rewriteFormats.map { ($0, $0.tones) }
        }
        return rewriteFormats.compactMap { format in
            let matched = format.tones.filter {
                $0.label.lowercased().contains(query) ||
                $0.description.lowercased().contains(query) ||
                format.label.lowercased().contains(query)
            }
            return matched.isEmpty ? nil : (format, matched)
        }
    }

    private var favoriteTones: [(tone: RewriteTone, color: Color)] {
        let ids = favoriteIds
        guard !ids.isEmpty else { return [] }
        var result: [(RewriteTone, Color)] = []
        for format in rewriteFormats {
            for tone in format.tones where ids.contains(tone.id) {
                result.append((tone, format.color))
            }
        }
        return result
    }

    private var presetsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Recent custom presets
                if searchText.isEmpty, !recentPresets.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Text("🕐")
                            Text("RECENT CUSTOMS")
                        }
                        .font(.footnote)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)

                        recentPresetsGrid
                            .padding(.horizontal, 20)
                    }
                }

                // Favorites section
                if searchText.isEmpty, !favoriteTones.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Text("⭐")
                            Text("FAVORITES")
                        }
                        .font(.footnote)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)

                        favoritesGrid
                            .padding(.horizontal, 20)
                    }
                }

                ForEach(filteredFormats, id: \.format.id) { item in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Text(item.format.emoji)
                            Text(item.format.label.uppercased())
                        }
                        .font(.footnote)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)

                        toneGrid(for: item.tones, color: item.format.color)
                            .padding(.horizontal, 20)
                    }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.immediately)
        .searchable(text: $searchText, prompt: "Search presets")
    }

    private var recentPresetsGrid: some View {
        let items = recentPresets
        let rowCount = (items.count + 1) / 2
        return VStack(spacing: 12) {
            ForEach(0..<rowCount, id: \.self) { row in
                HStack(spacing: 12) {
                    recentPresetCard(items[row * 2])
                    if row * 2 + 1 < items.count {
                        recentPresetCard(items[row * 2 + 1])
                    } else {
                        Color.clear
                    }
                }
            }
        }
    }

    private func recentPresetCard(_ preset: RecentPreset) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("🕐")
                .font(.title2)

            Text(preset.instructions)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .overlay(alignment: .topTrailing) {
            if preset.pinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.4), value: preset.pinned)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.brand.opacity(colorScheme == .dark ? 0.12 : 0.1))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect(nil, preset.instructions, nil, nil)
            dismiss()
        }
        .contextMenu {
            Button {
                RecentPresetsStore.togglePin(id: preset.id)
                recentPresets = RecentPresetsStore.all
            } label: {
                Label(preset.pinned ? "Unpin" : "Pin", systemImage: preset.pinned ? "pin.slash" : "pin")
            }
            Button(role: .destructive) {
                RecentPresetsStore.remove(id: preset.id)
                recentPresets = RecentPresetsStore.all
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var favoritesGrid: some View {
        let items = favoriteTones
        let rowCount = (items.count + 1) / 2
        return VStack(spacing: 12) {
            ForEach(0..<rowCount, id: \.self) { row in
                HStack(spacing: 12) {
                    toneCard(items[row * 2].tone, color: items[row * 2].color)
                    if row * 2 + 1 < items.count {
                        toneCard(items[row * 2 + 1].tone, color: items[row * 2 + 1].color)
                    } else {
                        Color.clear
                    }
                }
            }
        }
    }

    private func toneGrid(for tones: [RewriteTone], color: Color) -> some View {
        let rowCount = (tones.count + 1) / 2
        return VStack(spacing: 12) {
            ForEach(0..<rowCount, id: \.self) { row in
                HStack(spacing: 12) {
                    toneCard(tones[row * 2], color: color)
                    if row * 2 + 1 < tones.count {
                        toneCard(tones[row * 2 + 1], color: color)
                    } else {
                        Color.clear
                    }
                }
            }
        }
    }

    private func toneCard(_ tone: RewriteTone, color: Color) -> some View {
        let isFavorite = favoriteIds.contains(tone.id)
        return VStack(alignment: .leading, spacing: 6) {
            Text(tone.emoji)
                .font(.title2)

            Text(tone.label)
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            Text(tone.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .overlay(alignment: .topTrailing) {
            if isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.4), value: isFavorite)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(color.opacity(colorScheme == .dark ? 0.12 : 0.1))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect(tone.id, nil, tone.label, tone.emoji)
            dismiss()
        }
        .onLongPressGesture {
            toggleFavorite(tone.id)
        }
    }

    // MARK: - Custom

    private var customView: some View {
        VStack(spacing: 20) {
            TextField("e.g. Make it sound like a TED talk", text: $customInstructions, axis: .vertical)
                .font(.body)
                .lineLimit(3...8)
                .focused($customFocused)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(colorScheme == .dark ? Color.darkSurface : .white.opacity(0.7))
                )
                .padding(.horizontal, 20)

            Button {
                onSelect(nil, customInstructions.trimmingCharacters(in: .whitespaces), nil, nil)
                dismiss()
            } label: {
                Text("Rewrite")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Capsule().fill(Color.brand))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .disabled(customInstructions.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(customInstructions.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)

            Spacer()
        }
        .padding(.top, 20)
    }
}

// MARK: - Sheet Background

struct SheetBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            (colorScheme == .dark ? Color.darkBackground : Color.warmBackground)
                .opacity(colorScheme == .dark ? 0.85 : 0.55)
        }
        .ignoresSafeArea()
    }
}
