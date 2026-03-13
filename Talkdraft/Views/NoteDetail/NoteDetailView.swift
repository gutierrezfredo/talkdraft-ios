import SwiftUI

struct NoteDetailView: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(AuthStore.self) var authStore
    @Environment(SettingsStore.self) var settingsStore
    @Environment(SubscriptionStore.self) var subscriptionStore
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    let noteId: UUID
    let initialNote: Note

    @State var editedTitle: String
    @State var editedContent: String
    @State var showDeleteConfirmation = false
    @State var showCategoryPicker = false
    @State var showRewriteSheet = false
    @State var showRestoreConfirmation = false
    @State var pendingRewrite: (tone: String?, instructions: String?)?
    @State var isRewriting = false
    @State var audioExpanded = false
    @State var player = AudioPlayer()
    @State var typewriterTask: Task<Void, Never>?
    @State var scrollProxy: ScrollViewProxy?
    @State var contentFocused = false
    @State var contentOpacity: Double = 1
    @State var errorMessage: String?
    @State var isDownloadingAudio = false
    @State var audioShareItem: URL?
    @State var textShareItem: String?
    @State var appendRecorder = AudioRecorder()
    @State var isAppendRecording = false
    @State var isAppendTranscribing = false
    @State var cursorPosition: Int = 0
    @State var appendInsertPosition: Int = 0
    @State var highlightRange: NSRange?
    @State var preserveScroll = false
    @State var autosaveTask: Task<Void, Never>?

    static let recordingPlaceholder = "Recording…"
    static let transcribingPlaceholder = "Transcribing…"

    init(note: Note) {
        self.noteId = note.id
        self.initialNote = note
        self._editedTitle = State(initialValue: note.title ?? "")
        self._editedContent = State(initialValue: note.content)
    }

    var note: Note {
        noteStore.notes.first { $0.id == noteId } ?? initialNote
    }

    var isInStore: Bool {
        noteStore.notes.contains { $0.id == noteId }
    }

    var hasChanges: Bool {
        typewriterTask == nil
            && !isRewriting
            && (editedTitle != (note.title ?? "") || editedContent != note.content)
    }

    var category: Category? {
        noteStore.categories.first { $0.id == note.categoryId }
    }

    var audioURL: URL? {
        guard let urlString = note.audioUrl else { return nil }
        return URL(string: urlString)
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
                            .onTapGesture {
                                if !subscriptionStore.isReadOnly { contentFocused = true }
                            }
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
                            (colorScheme == .dark ? Color.darkBackground : Color.warmBackground).opacity(0.9),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 32)

                    bottomBar
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background((colorScheme == .dark ? Color.darkBackground : Color.warmBackground).opacity(0.9))
                }
            } else {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [
                            .clear,
                            (colorScheme == .dark ? Color.darkBackground : Color.warmBackground).opacity(0.9),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 32)

                    bottomBar
                        .padding(.bottom, 12)
                        .frame(maxWidth: .infinity)
                        .background((colorScheme == .dark ? Color.darkBackground : Color.warmBackground).opacity(0.9))
                }
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
            if Int(elapsed) >= 3600 && appendRecorder.isRecording {
                stopAppendRecording()
            }
        }
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
