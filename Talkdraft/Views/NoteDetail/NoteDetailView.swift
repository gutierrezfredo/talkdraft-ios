import AVFoundation
import SwiftUI

/// Walks up from a SwiftUI scroll content view to find the parent UIScrollView
/// and configures it for native interactive keyboard dismissal.
private struct ScrollViewKeyboardDismissSetup: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            var view: UIView? = uiView.superview
            while let v = view {
                if let sv = v as? UIScrollView {
                    sv.keyboardDismissMode = .interactive
                    sv.alwaysBounceVertical = true
                    return
                }
                view = v.superview
            }
        }
    }
}

struct NoteDetailView: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(AuthStore.self) var authStore
    @Environment(SettingsStore.self) var settingsStore
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    let noteId: UUID
    let initialNote: Note

    @State var editedTitle: String
    @State var editedContent: String
    @State var noteBodyState: NoteBodyState
    @State var showDeleteConfirmation = false
    @State var pendingDeleteRewrite: NoteRewrite?
    @State var didDelete = false
    @State var showCategoryPicker = false
    @State var showRewriteSheet = false
    @State var pendingRewrite: (tone: String?, instructions: String?, toneLabel: String?, toneEmoji: String?)?
    @State var isRewriting = false
    @State var rewritingLabel: String = ""
    @State var rewrites: [NoteRewrite] = []
    @State var activeRewriteId: UUID?
    @State var rewriteLabelOpacity: Double = 0
    @State var audioExpanded = false
    @State var player = AudioPlayer()
    @State var typewriterTask: Task<Void, Never>?
    @State var scrollProxy: ScrollViewProxy?
    @State var contentFocused = false
    @State var moveCursorToEnd = false
    @FocusState var titleFocused: Bool
    @State var contentOpacity: Double = 1
    @State var titleBaseline: String = ""
    @State var contentBaseline: String = ""
    @State var errorMessage: String?
    @State var isDownloadingAudio = false
    @State var audioShareItem: URL?
    @State var textShareItem: String?
    @State var appendRecorder = AudioRecorder()
    @State var isAppendRecording = false
    @State var isAppendTranscribing = false
    @State var appendPlaceholder: NoteAppendPlaceholderState?
    @State var cursorPosition: Int = 0
    @State var lastKnownCursorPosition: Int = 0
    @State var isCursorReady = false
    @State var appendInsertPosition: Int = 0
    @State var highlightRange: NSRange?
    @State var preserveScroll = false
    @State var autosaveTask: Task<Void, Never>?

    @State var transcribingVideoPlayer: AVQueuePlayer?
    @State var transcribingPresentationTask: Task<Void, Never>?
    @State var showTranscribingIndicator = false
    @State var transcribingPlayerLooper: AVPlayerLooper?
    @State var transcribingPhraseIndex = 0
    @State var transcribingIsLong = false
    @State var whileIndex = 0
    @State var renamingSpeaker: String? = nil
    @State var renameText: String = ""
    @State var rewriteSweep: CGFloat = 0

    static let speakerColors: [Color] = [
        Color(hex: "#7C3AED"), // violet (brand)
        Color(hex: "#0284C7"), // sky blue
        Color(hex: "#D97706"), // amber
        Color(hex: "#059669"), // emerald
        Color(hex: "#DC2626"), // red
        Color(hex: "#DB2777"), // pink
        Color(hex: "#7C3AED"), // wrap
    ]

    static let speakerUIColors: [UIColor] = [
        UIColor(red: 0x7C/255, green: 0x3A/255, blue: 0xED/255, alpha: 1),
        UIColor(red: 0x02/255, green: 0x84/255, blue: 0xC7/255, alpha: 1),
        UIColor(red: 0xD9/255, green: 0x77/255, blue: 0x06/255, alpha: 1),
        UIColor(red: 0x05/255, green: 0x96/255, blue: 0x69/255, alpha: 1),
        UIColor(red: 0xDC/255, green: 0x26/255, blue: 0x26/255, alpha: 1),
        UIColor(red: 0xDB/255, green: 0x27/255, blue: 0x77/255, alpha: 1),
    ]

    var speakerColorMap: [String: UIColor] {
        Dictionary(uniqueKeysWithValues: detectedSpeakers.enumerated().map { index, key in
            (key, Self.speakerUIColors[index % Self.speakerUIColors.count])
        })
    }

    let transcribingPhrases: [String] = [
        "Feel free to leave — your note will be waiting for you",
        "Safe to navigate away — we'll finish in the background",
        "Nothing will be lost if you leave — come back when you're ready",
        "You're free to go. We'll finish this in the background",
    ]

    let whilePhrases: [(video: String, subtitle: String)] = [
        ("while-binge", "This one might take a bit — maybe catch up on your favorite show? Your note will be waiting when you're back"),
        ("while-hobby", "This one might take a bit — maybe pick up a new hobby? Your note will be waiting when you're back"),
        ("while-read", "This one might take a bit — maybe read a page of your favorite book? Your note will be here when you're done"),
        ("while-snack", "This one might take a bit — maybe grab your favorite snack? Your note will be right here when you're back"),
        ("while-work", "This one might take a bit — maybe tackle something on your list? Your note will be waiting when you're back"),
        ("while-rest", "This one might take a bit — maybe take a little rest? Your note will be waiting when you wake up"),
    ]
    @State var titlePhraseIndex = 0
    @State var titleTypewriterTask: Task<Void, Never>?

    let titlePhrases = [
        "Naming this masterpiece…",
        "Cooking up a title…",

        "Consulting the title gods…",
        "Squeezing out a title…",
    ]

    var isGeneratingTitle: Bool {
        noteStore.generatingTitleIds.contains(noteId)
    }

    init(note: Note, initialContent: String? = nil) {
        self.noteId = note.id
        self.initialNote = note
        let title = note.title ?? ""
        let content = initialContent ?? note.content
        // If the note has an active rewrite but no cached content yet, the task will
        // switch content after fetching — start invisible to prevent the flash.
        let willSwitch = note.activeRewriteId != nil && initialContent == nil
        self._editedTitle = State(initialValue: title)
        self._editedContent = State(initialValue: content)
        self._noteBodyState = State(initialValue: NoteBodyState(content: content, source: note.source))
        self._contentFocused = State(initialValue: false)
        self._titleBaseline = State(initialValue: title)
        self._contentBaseline = State(initialValue: content)
        self._contentOpacity = State(initialValue: willSwitch ? 0 : 1)
    }

    var note: Note {
        noteStore.notes.first { $0.id == noteId } ?? initialNote
    }

    var isInStore: Bool {
        noteStore.notes.contains { $0.id == noteId }
    }

    var hasChanges: Bool {
        typewriterTask == nil
            && titleTypewriterTask == nil
            && !isRewriting
            && (editedTitle != titleBaseline || persistedEditedContent != contentBaseline)
    }

    var category: Category? {
        noteStore.categories.first { $0.id == note.categoryId }
    }

    var audioURL: URL? {
        guard let urlString = note.audioUrl else { return nil }
        return URL(string: urlString)
    }

    var bodyState: NoteBodyState {
        noteBodyState
    }

    var persistedEditedContent: String {
        NoteAppendPlaceholderEditor.strippedContent(from: editedContent, placeholder: appendPlaceholder)
    }

    var isTranscribing: Bool {
        bodyState == .transcribing
    }

    var showsTranscribingIndicator: Bool {
        isTranscribing && showTranscribingIndicator
    }

    /// Unique speaker display names in order of first appearance.
    /// Uses note.speakerNames as the authoritative source (survives renames),
    /// falling back to content parsing for notes without it.
    var detectedSpeakers: [String] {
        // Authoritative: use speakerNames dict (keys sorted to preserve original order)
        if let names = note.speakerNames, !names.isEmpty {
            return names.keys.sorted().map { names[$0] ?? $0 }
        }
        // New format: standalone "Speaker N" lines
        var seen: [String] = []
        for line in editedContent.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if trimmed.range(of: #"^Speaker \d+$"#, options: .regularExpression) != nil,
               !seen.contains(trimmed) {
                seen.append(trimmed)
            }
        }
        if !seen.isEmpty { return seen }
        // Legacy format: [Speaker N]: inline
        let pattern = /\[([^\]]+)\]:/
        for match in editedContent.matches(of: pattern) {
            let key = String(match.output.1)
            if !seen.contains(key) { seen.append(key) }
        }
        return seen
    }

    func speakerColor(for key: String) -> Color {
        let index = detectedSpeakers.firstIndex(of: key) ?? 0
        return Self.speakerColors[index % Self.speakerColors.count]
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

    var body: some View {
        ZStack(alignment: .bottom) {
            (colorScheme == .dark ? Color.darkBackground : Color.warmBackground)
                .ignoresSafeArea()

            GeometryReader { geo in
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    scrollContent
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: 500, maxHeight: geo.size.height)
                        .contentShape(Rectangle())
                        .onTapGesture { contentFocused = true; moveCursorToEnd = true }
                }
                .frame(minHeight: geo.size.height, alignment: .top)
                .background(ScrollViewKeyboardDismissSetup())
                Color.clear.frame(height: 0).id("scrollBottom")
            }
            .ignoresSafeArea(.all, edges: .bottom)
            .onAppear { scrollProxy = proxy }
            } // ScrollViewReader
            } // GeometryReader

            bottomFade
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !titleFocused && bodyState == .content && renamingSpeaker == nil {
                bottomBarContainer
                    .transition(.opacity)
                    .id(contentFocused)
            }
        }
        .animation(.easeOut(duration: 0.2), value: contentFocused)
        .animation(.easeInOut(duration: 0.4), value: isRewriting)
        .animation(.easeOut(duration: 0.25), value: renamingSpeaker == nil)
        .animation(.easeOut(duration: 0.2), value: bodyState)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await noteStore.fetchRewrites(for: noteId)
            rewrites = noteStore.rewritesCache[noteId] ?? []
            activeRewriteId = note.activeRewriteId
            let resolvedContent = noteStore.resolvedContent(for: note)
            if editedContent != resolvedContent {
                acceptResolvedNoteContent(resolvedContent)
            } else if contentOpacity == 0 {
                withAnimation(.easeIn(duration: 0.2)) { contentOpacity = 1 }
            }
            if !rewrites.isEmpty {
                try? await Task.sleep(for: .milliseconds(32))
                rewriteLabelOpacity = 1
            }
        }
        .task {
            // Auto-focus for new text notes — delay lets the view hierarchy and trait
            // collection fully settle before the keyboard appears, preventing a color flash.
            guard initialNote.source == .text && initialNote.content.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(450))
            contentFocused = true
            moveCursorToEnd = true
        }
        .toolbar { toolbarContent() }
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
                    removeAppendPlaceholder()
                    isAppendRecording = false
                }
            }
            autosaveTask?.cancel()
            guard !didDelete else { return }
            let hasContent = !editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !persistedEditedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                let oldState = resolvedBodyState(for: oldValue)
                let isPlaceholder = oldState.isTransientTranscriptionState
                if isPlaceholder && newValue != oldValue {
                    acceptStoreDrivenContent(newValue, revealIfNeeded: true)
                } else {
                    acceptStoreDrivenContent(newValue)
                }
            }
        }
        .onChange(of: note.title) { oldValue, newValue in
            if editedTitle == (oldValue ?? "") {
                syncStoreTitle(newValue ?? "")
            }
        }
        .onChange(of: isGeneratingTitle) { _, generating in
            guard generating else { return }
            titlePhraseIndex = Int.random(in: 0..<titlePhrases.count)
        }
        .onAppear {
            updateTranscribingPresentation(for: bodyState)
        }
        .renameSpeakerAlert(
            renamingSpeaker: $renamingSpeaker,
            renameText: $renameText,
            onConfirm: renameSpeaker
        )
        .onChange(of: bodyState) { _, state in
            updateTranscribingPresentation(for: state)
        }
        .onChange(of: contentFocused) { _, focused in
            if focused, typewriterTask != nil {
                cancelContentTypewriterAndRestoreFromStore()
            }
            if !focused { isCursorReady = false }
        }
        .onDisappear {
            typewriterTask?.cancel()
            titleTypewriterTask?.cancel()
            transcribingPresentationTask?.cancel()
        }
        .onChange(of: editedTitle) {
            scheduleAutosave()
        }
        .onChange(of: editedContent) { _, newValue in
            syncBodyState(with: newValue)
            scheduleAutosave()
        }
        .onChange(of: cursorPosition) { _, newPos in
            if contentFocused {
                lastKnownCursorPosition = newPos
                isCursorReady = true
            }
        }
        .onChange(of: appendRecorder.elapsedSeconds) { _, elapsed in
            if Int(elapsed) >= 900 && appendRecorder.isRecording {
                stopAppendRecording()
            }
        }
    }

    @ViewBuilder
    private func deadZone(height: CGFloat) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .contentShape(Rectangle())
            .onTapGesture {}
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

            // Date — non-tappable
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

    // MARK: - Shimmer Label

    private func shimmerLabel(_ text: String) -> some View {
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

    // MARK: - Title

    private var bottomFade: some View {
        let bg = colorScheme == .dark ? Color.darkBackground : Color.warmBackground
        return VStack {
            Spacer()
            LinearGradient(colors: [.clear, bg], startPoint: .top, endPoint: .bottom)
                .frame(height: 160)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var bottomBarContainer: some View {
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
    private func toolbarContent() -> some ToolbarContent {
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

    private var scrollContent: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 0).id("scrollTop")

            if !showsTranscribingIndicator {
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
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1)
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

    private var titleField: some View {
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

    // MARK: - Transcribing Indicator

    private var transcribingSubtitle: String {
        transcribingIsLong
            ? whilePhrases[whileIndex].subtitle
            : transcribingPhrases[transcribingPhraseIndex]
    }

    private var transcribingIndicator: some View {
        NoteDetailTranscribingIndicatorView(
            videoPlayer: transcribingVideoPlayer,
            subtitle: transcribingSubtitle,
            onAppear: setupTranscribingVideo,
            onDisappear: { transcribingVideoPlayer?.pause() }
        )
    }

    private func updateTranscribingPresentation(for state: NoteBodyState) {
        transcribingPresentationTask?.cancel()
        guard state == .transcribing else {
            withAnimation(.easeOut(duration: 0.12)) {
                showTranscribingIndicator = false
            }
            return
        }

        setupTranscribingState()
        showTranscribingIndicator = false
        transcribingPresentationTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, noteBodyState == .transcribing else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.18)) {
                    showTranscribingIndicator = true
                }
            }
        }
    }

    private func setupTranscribingState() {
        let duration = note.durationSeconds ?? 0
        transcribingIsLong = duration >= 300
        // Derive index from note ID — deterministic per note, no runtime randomness,
        // prevents ghosting from multiple onAppear calls while still rotating across notes.
        let hash = abs(noteId.hashValue)
        if transcribingIsLong {
            whileIndex = hash % whilePhrases.count
        } else {
            transcribingPhraseIndex = hash % transcribingPhrases.count
        }
    }

    private func setupTranscribingVideo() {
        guard transcribingVideoPlayer == nil else { return }
        let name: String
        if transcribingIsLong {
            name = whilePhrases[whileIndex].video
        } else {
            let shortVideos = ["transcribing-1", "transcribing-2"]
            name = shortVideos[abs(noteId.hashValue) % shortVideos.count]
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp4") else { return }
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: item)
        transcribingPlayerLooper = AVPlayerLooper(player: player, templateItem: item)
        player.isMuted = true
        player.play()
        transcribingVideoPlayer = player
    }

    // MARK: - Waiting for Connection

    private var waitingForConnectionView: some View {
        NoteDetailWaitingForConnectionView()
    }

    // MARK: - Transcription Failed

    private var transcriptionFailedView: some View {
        NoteDetailTranscriptionFailedView(
            hasLocalAudio: localAudioFileURL != nil,
            onRetry: retryTranscription
        )
    }

    private func retryTranscription() {
        guard let audioFileURL = localAudioFileURL else { return }

        // Update local UI only — transcribeNote handles server sync on success
        editedContent = NoteBodyState.transcribingPlaceholder
        noteBodyState = .transcribing
        noteStore.setNoteContent(id: noteId, content: NoteBodyState.transcribingPlaceholder)

        let language = settingsStore.language == "auto" ? nil : settingsStore.language
        noteStore.transcribeNote(
            id: noteId,
            audioFileURL: audioFileURL,
            language: language,
            userId: authStore.userId,
            customDictionary: settingsStore.customDictionary
        )
    }

    // MARK: - Speaker Chips

    private var speakerChipsRow: some View {
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
            placeholder: "Start typing...",
            speakerColors: speakerColorMap,
            horizontalPadding: 24,
            moveCursorToEnd: $moveCursorToEnd
        )
        .opacity(contentOpacity)
    }

    private var keyboardVisible: Bool { contentFocused }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
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

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func presentAfterKeyboardDismiss(_ action: @escaping () -> Void) {
        contentFocused = false
        dismissKeyboard()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            action()
        }
    }

    private func presentCategoryPicker() {
        presentAfterKeyboardDismiss {
            showCategoryPicker = true
        }
    }

    private func presentRewriteSheet() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        presentAfterKeyboardDismiss {
            showRewriteSheet = true
        }
    }

    private func presentTextShareSheet() {
        presentAfterKeyboardDismiss {
            textShareItem = buildShareText()
        }
    }


}
