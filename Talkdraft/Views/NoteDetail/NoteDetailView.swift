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
    @State var rewriteLabelFallback: String?
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
        let opensOnUnresolvedRewrite = note.activeRewriteId == nil
            && note.originalContent != nil
            && content != note.originalContent
        // If the note has an active rewrite but no cached content yet, the task will
        // switch content after fetching — start invisible to prevent the flash.
        let willSwitch = note.activeRewriteId != nil && initialContent == nil
        self._editedTitle = State(initialValue: title)
        self._editedContent = State(initialValue: content)
        self._noteBodyState = State(initialValue: NoteBodyState(content: content, source: note.source))
        self._contentFocused = State(initialValue: false)
        self._activeRewriteId = State(initialValue: note.activeRewriteId)
        self._rewriteLabelFallback = State(initialValue: opensOnUnresolvedRewrite ? "Rewrite" : nil)
        self._rewriteLabelOpacity = State(initialValue: (note.originalContent != nil || note.activeRewriteId != nil) ? 1 : 0)
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

    var category: Category? {
        noteStore.categories.first { $0.id == note.categoryId }
    }


    var persistedEditedContent: String {
        NoteAppendPlaceholderEditor.strippedContent(from: editedContent, placeholder: appendPlaceholder)
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
            rewrites = noteStore.rewritesCache[noteId] ?? []
            activeRewriteId = note.activeRewriteId
            if activeRewriteId != nil {
                rewriteLabelFallback = nil
            }
            repairMissingActiveRewriteSelection()

            await noteStore.fetchRewrites(for: noteId)
            rewrites = noteStore.rewritesCache[noteId] ?? []
            activeRewriteId = note.activeRewriteId
            if activeRewriteId != nil {
                rewriteLabelFallback = nil
            }
            repairMissingActiveRewriteSelection()
            let displayContent = noteStore.displayContent(for: note)
            if editedContent != displayContent {
                acceptResolvedNoteContent(displayContent)
            } else if contentOpacity == 0 {
                withAnimation(.easeIn(duration: 0.2)) { contentOpacity = 1 }
            }
            if showsRewriteToolbarLabel, rewriteLabelOpacity == 0 {
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
        .onChange(of: noteStore.displayContent(for: note)) { oldValue, newValue in
            if editedContent == oldValue || persistedEditedContent == oldValue {
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
        .onChange(of: note.activeRewriteId) { _, newValue in
            activeRewriteId = newValue
            if newValue != nil || note.originalContent == nil || noteStore.displayContent(for: note) == note.originalContent {
                rewriteLabelFallback = nil
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

}
