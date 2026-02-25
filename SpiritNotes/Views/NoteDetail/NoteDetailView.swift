import SwiftUI

struct NoteDetailView: View {
    @Environment(NoteStore.self) private var noteStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    let note: Note

    @State private var editedTitle: String
    @State private var editedContent: String
    @State private var showDeleteConfirmation = false
    @State private var showCategoryPicker = false
    @State private var showRewriteSheet = false
    @State private var audioExpanded = false
    @State private var player = AudioPlayer()
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var contentFocused: Bool

    init(note: Note) {
        self.note = note
        self._editedTitle = State(initialValue: note.title ?? "")
        self._editedContent = State(initialValue: note.content)
    }

    private var hasChanges: Bool {
        editedTitle != (note.title ?? "") || editedContent != note.content
    }

    private var category: Category? {
        noteStore.categories.first { $0.id == note.categoryId }
    }

    private var audioURL: URL? {
        guard let urlString = note.audioUrl else { return nil }
        return URL(string: urlString)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            (colorScheme == .dark ? Color.darkBackground : Color.warmBackground)
                .ignoresSafeArea()

            // Scrollable content
            ScrollView {
                VStack(spacing: 0) {
                    // Audio pill + date
                    metadataRow
                        .padding(.top, 12)

                    // Audio player (expandable)
                    if audioExpanded, audioURL != nil {
                        audioPlayerView
                            .padding(.top, 12)
                            .padding(.horizontal, 24)
                    }

                    // Title
                    titleField
                        .padding(.top, 20)
                        .padding(.horizontal, 24)

                    // Content
                    contentField
                        .padding(.top, 28)
                        .padding(.horizontal, 24)

                    // Tap zone below content to focus editor
                    Color.clear
                        .frame(height: 100)
                        .contentShape(Rectangle())
                        .onTapGesture { contentFocused = true }
                }
                .padding(.bottom, keyboardHeight > 0 ? keyboardHeight + 60 : 120)
            }
            .scrollDismissesKeyboard(.interactively)

            // Bottom fade
            VStack {
                Spacer()
                LinearGradient(
                    colors: [
                        .clear,
                        (colorScheme == .dark ? Color.darkBackground : Color.warmBackground),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 90)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Bottom action bar
            bottomBar
                .padding(.bottom, 12)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if hasChanges {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        saveChanges()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.brand)
                    }
                    .sensoryFeedback(.success, trigger: hasChanges)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if note.audioUrl != nil {
                        Button {
                            // TODO: Download audio
                        } label: {
                            Label("Download Audio", systemImage: "arrow.down.circle")
                        }
                    }

                    if note.originalContent != nil {
                        Button {
                            restoreOriginal()
                        } label: {
                            Label("Restore Original", systemImage: "arrow.uturn.backward")
                        }
                    }

                    Divider()

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
            .presentationDetents([.medium])
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showRewriteSheet) {
            RewriteSheet(content: editedContent, language: note.language) { rewrittenText in
                // Save original before overwriting
                if note.originalContent == nil {
                    var updated = note
                    updated.originalContent = editedContent
                    noteStore.updateNote(updated)
                }
                editedContent = rewrittenText
                saveChanges()
            }
            .presentationDetents([.large])
            .presentationBackground(.ultraThinMaterial)
        }
        .onDisappear {
            player.stop()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: audioExpanded)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                keyboardHeight = frame.height
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
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
                try? player.togglePlayback(url: url)
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
            .font(.system(size: 28, weight: .bold, design: .serif))
            .multilineTextAlignment(.center)
            .autocorrectionDisabled()
    }

    // MARK: - Content

    private var contentField: some View {
        TextField("Start typing...", text: $editedContent, axis: .vertical)
            .font(.body)
            .lineSpacing(6)
            .focused($contentFocused)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 40) {
            // Tag (left — same position as Upload on home)
            Button {
                showCategoryPicker = true
            } label: {
                Image(systemName: "tag")
                    .font(.title3)
                    .foregroundStyle(
                        category != nil ? Color(hex: category!.color) : .secondary
                    )
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: showCategoryPicker)

            // Rewrite (center — same position as Record on home)
            Button {
                showRewriteSheet = true
            } label: {
                Image(systemName: "wand.and.stars")
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(Color.brand))
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)

            // Share (right — same position as Search on home)
            Button {
                shareText()
            } label: {
                Image(systemName: "arrowshape.turn.up.right")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 0)
        .padding(.horizontal, 20)
        .contentShape(Rectangle())
    }

    // MARK: - Helpers

    private func saveChanges() {
        var updated = note
        updated.title = editedTitle.isEmpty ? nil : editedTitle
        updated.content = editedContent
        updated.updatedAt = Date()
        noteStore.updateNote(updated)
    }

    private func restoreOriginal() {
        if let original = note.originalContent {
            editedContent = original
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
                                .foregroundStyle(Color(hex: cat.color))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    Capsule()
                                        .fill(colorScheme == .dark ? Color.darkSurface : .white.opacity(0.7))
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(
                                            isSelected ? Color(hex: cat.color) : .clear,
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
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(colorScheme == .dark ? Color.darkSurface : .white.opacity(0.7))
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

                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle("Move to category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sensoryFeedback(.selection, trigger: selectedCategoryId)
        }
        .sheet(isPresented: $showAddCategory) {
            CategoryFormSheet(mode: .add)
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
    let icon: String
}

private struct ToneGroup: Identifiable {
    let id: String
    let label: String
    let tones: [RewriteTone]
}

private let toneGroups: [ToneGroup] = [
    ToneGroup(id: "practical", label: "Practical", tones: [
        RewriteTone(id: "clean-up", label: "Clean up", icon: "sparkles"),
        RewriteTone(id: "sharpen", label: "Sharpen", icon: "bolt"),
        RewriteTone(id: "structure", label: "Structure", icon: "list.bullet"),
        RewriteTone(id: "formalize", label: "Formalize", icon: "briefcase"),
    ]),
    ToneGroup(id: "playful", label: "Playful", tones: [
        RewriteTone(id: "flirty", label: "Flirty", icon: "heart"),
        RewriteTone(id: "for-kids", label: "For kids", icon: "face.smiling"),
        RewriteTone(id: "hype", label: "Hype", icon: "flame"),
        RewriteTone(id: "poetic", label: "Poetic", icon: "leaf"),
        RewriteTone(id: "sarcastic", label: "Sarcastic", icon: "eyeglasses"),
    ]),
    ToneGroup(id: "occasions", label: "Occasions", tones: [
        RewriteTone(id: "birthday", label: "Birthday", icon: "gift"),
        RewriteTone(id: "holiday", label: "Holiday", icon: "snowflake"),
        RewriteTone(id: "thank-you", label: "Thank you", icon: "hand.thumbsup"),
        RewriteTone(id: "congratulations", label: "Congrats", icon: "trophy"),
        RewriteTone(id: "apology", label: "Apology", icon: "hand.raised"),
        RewriteTone(id: "love-letter", label: "Love letter", icon: "heart.text.clipboard"),
        RewriteTone(id: "wedding-toast", label: "Wedding toast", icon: "wineglass"),
    ]),
]

private struct RewriteSheet: View {
    let content: String
    let language: String?
    let onAccept: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedToneId: String?
    @State private var customInstructions = ""
    @State private var rewrittenText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var customFocused: Bool

    private enum SheetState {
        case selection, loading, preview
    }

    private var state: SheetState {
        if isLoading { return .loading }
        if !rewrittenText.isEmpty { return .preview }
        return .selection
    }

    private var canRewrite: Bool {
        selectedToneId != nil || !customInstructions.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .selection:
                    selectionView
                case .loading:
                    loadingView
                case .preview:
                    previewView
                }
            }
            .navigationTitle(state == .preview ? "Preview" : "Rewrite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Selection

    private var selectionView: some View {
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

                // Custom instructions
                VStack(alignment: .leading, spacing: 10) {
                    Text("CUSTOM INSTRUCTIONS")
                        .font(.footnote)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)

                    TextField("e.g. Keep my Dominican slang", text: $customInstructions, axis: .vertical)
                        .font(.body)
                        .lineLimit(1...4)
                        .focused($customFocused)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(colorScheme == .dark ? Color(hex: "#1f1f1f") : .white.opacity(0.7))
                        )
                        .padding(.horizontal, 20)
                }

                // Error
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 20)
                }

                // Rewrite button
                Button {
                    performRewrite()
                } label: {
                    Text("Rewrite")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            Capsule().fill(Color.brand)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canRewrite)
                .opacity(canRewrite ? 1 : 0.4)
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func tonePill(_ tone: RewriteTone) -> some View {
        let isSelected = selectedToneId == tone.id
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                selectedToneId = selectedToneId == tone.id ? nil : tone.id
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tone.icon)
                    .font(.caption)
                Text(tone.label)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isSelected ? Color.brand : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(colorScheme == .dark ? Color(hex: "#1f1f1f") : .white.opacity(0.7))
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.brand : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Color.brand)
                .scaleEffect(1.5)
            Text("Rewriting...")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Preview

    private var previewView: some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(rewrittenText)
                    .font(.body)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }

            VStack(spacing: 12) {
                Button {
                    onAccept(rewrittenText)
                    dismiss()
                } label: {
                    Text("Accept")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            Capsule().fill(Color.brand)
                        )
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.success, trigger: rewrittenText)

                Button {
                    rewrittenText = ""
                } label: {
                    Text("Try another")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    // MARK: - API

    private func performRewrite() {
        customFocused = false
        errorMessage = nil
        isLoading = true

        Task {
            do {
                let result = try await AIService.rewrite(
                    content: content,
                    tone: selectedToneId,
                    customInstructions: customInstructions.trimmingCharacters(in: .whitespaces).isEmpty ? nil : customInstructions,
                    language: language
                )
                rewrittenText = result
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
