import SwiftUI

struct NoteDetailView: View {
    @Environment(NoteStore.self) private var noteStore
    @Environment(AuthStore.self) private var authStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptionStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    private let noteId: UUID
    private let initialNote: Note

    @State private var editedTitle: String
    @State private var editedContent: String
    @State private var showDeleteConfirmation = false
    @State private var showCategoryPicker = false
    @State private var showRewriteSheet = false
    @State private var showRestoreConfirmation = false
    @State private var pendingRewrite: (tone: String?, instructions: String?)?
    @State private var isRewriting = false
    @State private var audioExpanded = false
    @State private var player = AudioPlayer()
    @State private var typewriterTask: Task<Void, Never>?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var contentFocused = false
    @State private var contentOpacity: Double = 1
    @State private var errorMessage: String?
    @State private var isDownloadingAudio = false
    @State private var audioShareItem: URL?
    @State private var appendRecorder = AudioRecorder()
    @State private var isAppendRecording = false
    @State private var isAppendTranscribing = false
    @State private var cursorPosition: Int = 0
    @State private var appendInsertPosition: Int = 0
    @State private var highlightRange: NSRange?
    @State private var preserveScroll = false
    @State private var autosaveTask: Task<Void, Never>?

    private static let recordingPlaceholder = "Recording…"
    private static let transcribingPlaceholder = "Transcribing…"

    init(note: Note) {
        self.noteId = note.id
        self.initialNote = note
        self._editedTitle = State(initialValue: note.title ?? "")
        self._editedContent = State(initialValue: note.content)
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

                    // Rewriting indicator
                    if isRewriting {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(Color.brand)
                            Text("Rewriting…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 20)
                        .transition(.opacity)
                    }

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

                        // Tap zone below content to focus editor
                        Color.clear
                            .frame(minHeight: 500)
                            .contentShape(Rectangle())
                            .onTapGesture { contentFocused = true }
                    }
                }
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { scrollProxy = proxy }
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
                .frame(height: 90)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Bottom bar
            if keyboardVisible {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [
                            .clear,
                            colorScheme == .dark ? Color.darkBackground : Color.warmBackground,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 40)

                    bottomBar
                        .padding(.vertical, 4)
                        .background((colorScheme == .dark ? Color.darkBackground : Color.warmBackground).opacity(0.95))
                }
            } else {
                bottomBar
                    .padding(.bottom, 12)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if note.originalContent != nil {
                ToolbarItem(placement: .principal) {
                    Button {
                        showRestoreConfirmation = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.caption2)
                            Text("Restore Original")
                                .font(.caption)
                        }
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.impact(weight: .light), trigger: note.originalContent == nil)
                }
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
        .confirmationDialog(
            "Delete this note?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                noteStore.removeNote(id: note.id)
                dismiss()
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerSheet(
                note: note,
                categories: noteStore.categories
            )
            .presentationDetents([.medium, .large])
            .presentationBackground {
                SheetBackground()
            }
        }
        .sheet(isPresented: $showRewriteSheet, onDismiss: {
            guard let rewrite = pendingRewrite else { return }
            pendingRewrite = nil
            performRewrite(tone: rewrite.tone, instructions: rewrite.instructions)
        }) {
            RewriteSheet { tone, instructions in
                pendingRewrite = (tone, instructions)
            }
            .presentationDetents([.large])
            .presentationBackground {
                SheetBackground()
            }
        }
        .onDisappear {
            player.stop()
            if isAppendRecording || isAppendTranscribing {
                appendRecorder.cancelRecording()
                removePlaceholder()
                isAppendRecording = false
                isAppendTranscribing = false
            }
            autosaveTask?.cancel()
            let hasContent = !editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !editedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if hasContent && (hasChanges || !isInStore) {
                saveChanges()
            }
        }
        .alert("Restore Original?", isPresented: $showRestoreConfirmation) {
            Button("Restore", role: .destructive) { restoreOriginal() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will discard all rewrites and restore the original content.")
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
        .sensoryFeedback(.impact(weight: .light), trigger: audioExpanded)
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
        .onChange(of: appendRecorder.elapsedSeconds) { _, elapsed in
            if Int(elapsed) >= subscriptionStore.recordingLimitSeconds && appendRecorder.isRecording {
                stopAppendRecording()
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
            Text(note.createdAt, format: .dateTime.month(.wide).day().year())
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
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.body)
                    .foregroundStyle(Color.brand)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

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
            .font(.system(size: 28, weight: .bold))
            .multilineTextAlignment(.center)
            .autocorrectionDisabled()
            .contentTransition(.opacity)
    }

    // MARK: - Transcribing Indicator

    private var transcribingIndicator: some View {
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
            userId: authStore.userId
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
                shareText()
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

    private func performRewrite(tone: String?, instructions: String?) {
        isRewriting = true
        Task {
            do {
                // Map "action-items" tone to custom instructions
                let rewriteTone: String?
                let rewriteInstructions: String?
                if tone == "action-items" {
                    rewriteTone = nil
                    rewriteInstructions = "Extract action items from this text. Start with the action items using checkboxes (☐ ) for each task, one per line. Then add two line breaks and include the original content below, cleaned up and organized using bullet points (• ) where appropriate. Do not use markdown formatting (no **, no ##, no backticks). Only use ☐ for action items and • for bullet points. Keep the same language as the original."
                } else {
                    rewriteTone = tone
                    rewriteInstructions = instructions
                }

                let result = try await AIService.rewrite(
                    content: editedContent,
                    tone: rewriteTone,
                    customInstructions: rewriteInstructions,
                    language: note.language
                )
                var updated = note
                if updated.originalContent == nil {
                    updated.originalContent = editedContent
                }
                updated.content = result
                updated.title = editedTitle.isEmpty ? nil : editedTitle
                updated.updatedAt = Date()
                noteStore.updateNote(updated)
                revealContent(result)
            } catch {
                errorMessage = "Rewrite failed: \(error.localizedDescription)"
            }
            isRewriting = false
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

    private func restoreOriginal() {
        guard let original = note.originalContent else { return }
        contentOpacity = 0
        editedContent = original
        var updated = note
        updated.content = original
        updated.originalContent = nil
        updated.updatedAt = Date()
        noteStore.updateNote(updated)
        scrollToTop()
        withAnimation(.easeIn(duration: 0.5)) {
            contentOpacity = 1
        }
    }

    private func buildShareText() -> String {
        let title = editedTitle.isEmpty ? "" : editedTitle + "\n\n"
        return title + editedContent
    }

    private func shareText() {
        let text = buildShareText()
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = windowScene.keyWindow?.rootViewController else { return }
        var presenter = root
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        activityVC.popoverPresentationController?.sourceView = presenter.view
        activityVC.popoverPresentationController?.sourceRect = CGRect(
            x: presenter.view.bounds.midX,
            y: presenter.view.bounds.maxY,
            width: 0,
            height: 0
        )
        presenter.present(activityVC, animated: true)
    }

    // MARK: - Append Recording Actions

    private func startAppendRecording() {
        // Capture cursor position and insert placeholder
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
                // Skip compression — AudioRecorder already outputs 16kHz mono AAC
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
    let categories: [Category]

    @State private var selectedCategoryId: UUID?
    @State private var showAddCategory = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Category grid
                    FlowLayout(spacing: 8) {
                        ForEach(categories) { cat in
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
                dismiss()
            }
        }
        .onAppear {
            selectedCategoryId = note.categoryId
        }
    }
}

// MARK: - Rewrite Sheet

private struct RewriteTone: Identifiable {
    let id: String
    let label: String
    let emoji: String
}

private struct ToneGroup: Identifiable {
    let id: String
    let label: String
    let tones: [RewriteTone]
}

private let toneGroups: [ToneGroup] = [
    ToneGroup(id: "practical", label: "Practical", tones: [
        RewriteTone(id: "clean-up", label: "Clean up", emoji: "✨"),
        RewriteTone(id: "sharpen", label: "Sharpen", emoji: "⚡"),
        RewriteTone(id: "structure", label: "Structure", emoji: "📋"),
        RewriteTone(id: "formalize", label: "Formalize", emoji: "👔"),
        RewriteTone(id: "action-items", label: "Action Items", emoji: "☑️"),
    ]),
    ToneGroup(id: "playful", label: "Playful", tones: [
        RewriteTone(id: "flirty", label: "Flirty", emoji: "😘"),
        RewriteTone(id: "for-kids", label: "For kids", emoji: "🧒"),
        RewriteTone(id: "hype", label: "Hype", emoji: "🔥"),
        RewriteTone(id: "poetic", label: "Poetic", emoji: "🍃"),
        RewriteTone(id: "sarcastic", label: "Sarcastic", emoji: "😏"),
    ]),
    ToneGroup(id: "occasions", label: "Occasions", tones: [
        RewriteTone(id: "birthday", label: "Birthday", emoji: "🎂"),
        RewriteTone(id: "holiday", label: "Holiday", emoji: "❄️"),
        RewriteTone(id: "thank-you", label: "Thank you", emoji: "🙏"),
        RewriteTone(id: "congratulations", label: "Congrats", emoji: "🏆"),
        RewriteTone(id: "apology", label: "Apology", emoji: "💐"),
        RewriteTone(id: "love-letter", label: "Love letter", emoji: "💌"),
        RewriteTone(id: "wedding-toast", label: "Wedding toast", emoji: "🥂"),
    ]),
]

private struct RewriteSheet: View {
    let onSelect: (String?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedTab = 0
    @State private var customInstructions = ""
    @FocusState private var customFocused: Bool

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
    }

    // MARK: - Presets

    private var presetsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(toneGroups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.label.uppercased())
                            .font(.footnote)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)

                        FlowLayout(spacing: 8) {
                            ForEach(group.tones) { tone in
                                tonePill(tone)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
    }

    private func tonePill(_ tone: RewriteTone) -> some View {
        Button {
            onSelect(tone.id, nil)
            dismiss()
        } label: {
            HStack(spacing: 6) {
                Text(tone.emoji)
                    .font(.caption)
                Text(tone.label)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(colorScheme == .dark ? Color.darkSurface : .white.opacity(0.7))
            )
        }
        .buttonStyle(.plain)
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
                onSelect(nil, customInstructions.trimmingCharacters(in: .whitespaces))
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
        .onAppear { customFocused = true }
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
