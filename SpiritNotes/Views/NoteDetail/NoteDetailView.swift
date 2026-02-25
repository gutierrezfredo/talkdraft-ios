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
            (colorScheme == .dark ? Color(.systemBackground) : Color.warmBackground)
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
                        (colorScheme == .dark ? Color(.systemBackground) : Color.warmBackground),
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
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    if hasChanges {
                        Button {
                            saveChanges()
                        } label: {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color.brand))
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.success, trigger: hasChanges)
                    }

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
            RewriteSheet()
                .presentationDetents([.medium, .large])
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
                            .fill(colorScheme == .dark ? Color(hex: "#1f1f1f") : Color(hex: "#EDE5E2"))
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
            .font(.system(size: 28, weight: .bold))
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
                                        .fill(colorScheme == .dark ? Color(hex: "#1f1f1f") : .white.opacity(0.7))
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
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(colorScheme == .dark ? Color(hex: "#1f1f1f") : .white.opacity(0.7))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)

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

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}

// MARK: - Rewrite Sheet (Stub)

private struct RewriteSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("AI Rewrite", systemImage: "wand.and.stars")
            } description: {
                Text("Rewrite with different tones coming soon.")
            }
            .navigationTitle("Rewrite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
