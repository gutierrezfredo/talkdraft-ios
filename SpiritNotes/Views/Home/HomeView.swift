import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

enum NoteSortOrder: String, CaseIterable {
    case updatedAt = "Last Updated"
    case createdAt = "Creation Date"
}

struct HomeView: View {
    @Environment(NoteStore.self) private var noteStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedCategory: UUID?
    @State private var showRecordView = false
    @State private var sortOrder: NoteSortOrder = .updatedAt
    @State private var isSearching = false
    @State private var query = ""
    @State private var isSwiping = false
    @State private var selectedNote: Note?
    @State private var isSelecting = false
    @State private var selectedIds: Set<UUID> = []
    @State private var showDeleteConfirmation = false
    @State private var showCategoryPicker = false
    @State private var showAudioImporter = false
    @State private var showAddCategory = false
    @State private var keyboardHeight: CGFloat = 0
    @Namespace private var namespace
    @FocusState private var searchFocused: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Background
                (colorScheme == .dark ? Color(.systemBackground) : Color.warmBackground)
                    .ignoresSafeArea()

                // Main content
                ScrollView {
                    VStack(spacing: 12) {
                        // Greeting (hidden when searching or selecting)
                        if !isSearching && !isSelecting {
                            greeting
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // Category chips
                        categoryChips

                        // Notes grid
                        if filteredNotes.isEmpty {
                            emptyState
                        } else {
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(filteredNotes) { note in
                                    let category = noteStore.categories.first { $0.id == note.categoryId }
                                    NoteCard(
                                        note: note,
                                        category: category,
                                        selectionMode: isSelecting,
                                        isSelected: selectedIds.contains(note.id)
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        guard !isSwiping else { return }
                                        if isSelecting {
                                            toggleSelection(note.id)
                                        } else {
                                            if isSearching {
                                                searchFocused = false
                                                keyboardHeight = 0
                                            }
                                            selectedNote = note
                                        }
                                    }
                                    .onLongPressGesture {
                                        enterSelection(note.id)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                    .padding(.bottom, 120)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 30)
                            .onChanged { _ in
                                isSwiping = true
                            }
                            .onEnded { value in
                                let horizontal = value.predictedEndTranslation.width
                                let vertical = abs(value.predictedEndTranslation.height)

                                if abs(horizontal) > vertical * 1.5 {
                                    if horizontal < 0 {
                                        cycleCategory(forward: true)
                                    } else {
                                        cycleCategory(forward: false)
                                    }
                                }

                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    isSwiping = false
                                }
                            }
                    )
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable {
                    await noteStore.refresh()
                }

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

                // Bottom bar — floating buttons, search bar, or selection toolbar
                if isSelecting {
                    selectionToolbar
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if isSearching {
                    searchBar
                        .padding(.bottom, keyboardHeight > 0 ? keyboardHeight - bottomSafeArea + 8 : 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    floatingButtons
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .ignoresSafeArea(.keyboard)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(isSearching || isSelecting ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Sort by", selection: $sortOrder) {
                            ForEach(NoteSortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .navigationDestination(item: $selectedNote) { note in
                NoteDetailView(note: note)
            }
        }
        .fullScreenCover(isPresented: $showRecordView) {
            RecordView(categoryId: selectedCategory)
                .navigationTransition(.zoom(sourceID: "record", in: namespace))
        }
        .fileImporter(
            isPresented: $showAudioImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            handleAudioImport(result)
        }
        .confirmationDialog(
            "Delete \(selectedIds.count) Note\(selectedIds.count == 1 ? "" : "s")",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                noteStore.removeNotes(ids: selectedIds)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                exitSelection()
            }
        } message: {
            Text("This can't be undone.")
        }
        .sheet(isPresented: $showCategoryPicker) {
            bulkCategoryPicker
                .presentationDetents([.medium])
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
                withAnimation(.interpolatingSpring(duration: duration, bounce: 0)) {
                    keyboardHeight = frame.height
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
            let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            withAnimation(.interpolatingSpring(duration: duration, bounce: 0)) {
                keyboardHeight = 0
            }
        }
    }

    // MARK: - Greeting

    private var greeting: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("Say it ")
            Text("messy")
                .foregroundStyle(.secondary)
                .overlay(alignment: .bottom) {
                    ScribbleUnderline()
                        .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .frame(height: 8)
                        .offset(y: 4)
                }
            Text(".  ")
                .foregroundStyle(.secondary)
            Text("Read it ")
            Text("clean")
                .foregroundStyle(Color.brand)
                .overlay(alignment: .bottom) {
                    SmoothArcUnderline()
                        .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .foregroundStyle(Color.brand)
                        .frame(height: 5)
                        .offset(y: 2)
                }
            Text(".")
        }
        .font(.title3)
        .fontWeight(.semibold)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Category Chips

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryChip(
                    name: "All",
                    color: .brand,
                    isSelected: selectedCategory == nil
                ) {
                    withAnimation(.snappy) { selectedCategory = nil }
                }

                ForEach(noteStore.categories) { category in
                    CategoryChip(
                        name: category.name,
                        color: Color(hex: category.color),
                        isSelected: selectedCategory == category.id
                    ) {
                        withAnimation(.snappy) {
                            selectedCategory = selectedCategory == category.id ? nil : category.id
                        }
                    }
                }

                Button {
                    showAddCategory = true
                } label: {
                    Image(systemName: "plus")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(colorScheme == .dark ? Color(hex: "#1f1f1f") : .white)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .sheet(isPresented: $showAddCategory) {
            CategoryFormSheet(mode: .add)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            if isSearching && !query.isEmpty {
                Label("No results", systemImage: "magnifyingglass")
            } else {
                Label(
                    selectedCategory == nil
                        ? "Capture your thoughts"
                        : "No notes in this category",
                    systemImage: selectedCategory == nil
                        ? "waveform"
                        : "tray"
                )
            }
        } description: {
            if isSearching && !query.isEmpty {
                Text("No notes matching \"\(query)\".")
            } else {
                Text(
                    selectedCategory == nil
                        ? "Tap the mic to record your first thought."
                        : "Notes you add to this category will appear here."
                )
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding(.bottom, 0)
    }

    // MARK: - Floating Buttons

    private var floatingButtons: some View {
        HStack(spacing: 40) {
            // Upload audio button (left)
            Button {
                showAudioImporter = true
            } label: {
                Image(systemName: "icloud.and.arrow.up")
                    .fontWeight(.medium)
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)

            // Record button (center)
            Button {
                showRecordView = true
            } label: {
                Image(systemName: "mic.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(Color.brand))
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .matchedTransitionSource(id: "record", in: namespace)

            // Search button (right)
            Button {
                withAnimation(.snappy) {
                    isSearching = true
                }
                searchFocused = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .fontWeight(.medium)
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 12)
        .padding(.horizontal, 20)
        .contentShape(Rectangle())
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.body)
                    .foregroundStyle(.secondary)

                TextField("Search", text: $query)
                    .font(.body)
                    .focused($searchFocused)
                    .submitLabel(.search)

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .glassEffect(.regular, in: .capsule)

            Button {
                withAnimation(.snappy) {
                    isSearching = false
                    query = ""
                    searchFocused = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    // MARK: - Selection Toolbar

    private var selectionToolbar: some View {
        HStack(spacing: 12) {
            // Move to category
            Button {
                showCategoryPicker = true
            } label: {
                Image(systemName: "tag")
                    .fontWeight(.medium)
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)

            // Delete
            Button {
                showDeleteConfirmation = true
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "trash")
                        .fontWeight(.medium)
                    Text("\(selectedIds.count)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.red)
                .frame(width: 56, height: 56)
                .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)

            // Close selection
            Button {
                withAnimation(.snappy) {
                    exitSelection()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .contentShape(Rectangle())
    }

    // MARK: - Bulk Category Picker

    private var bulkCategoryPicker: some View {
        NavigationStack {
            List {
                Button {
                    noteStore.moveNotes(ids: selectedIds, toCategoryId: nil)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    exitSelection()
                    showCategoryPicker = false
                } label: {
                    Label("Uncategorized", systemImage: "tray")
                        .foregroundStyle(.secondary)
                }

                ForEach(noteStore.categories) { category in
                    Button {
                        noteStore.moveNotes(ids: selectedIds, toCategoryId: category.id)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        exitSelection()
                        showCategoryPicker = false
                    } label: {
                        Label {
                            Text(category.name)
                        } icon: {
                            Circle()
                                .fill(Color(hex: category.color))
                                .frame(width: 12, height: 12)
                        }
                    }
                    .tint(.primary)
                }
            }
            .navigationTitle("Move to Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showCategoryPicker = false
                    }
                }
            }
        }
    }

    // MARK: - Selection Helpers

    private func enterSelection(_ noteId: UUID) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.snappy) {
            isSelecting = true
            selectedIds = [noteId]
        }
    }

    private func toggleSelection(_ noteId: UUID) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if selectedIds.contains(noteId) {
            selectedIds.remove(noteId)
            if selectedIds.isEmpty {
                withAnimation(.snappy) {
                    isSelecting = false
                }
            }
        } else {
            selectedIds.insert(noteId)
        }
    }

    private func exitSelection() {
        withAnimation(.snappy) {
            isSelecting = false
            selectedIds = []
        }
    }

    // MARK: - Helpers

    private func handleAudioImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let sourceURL = urls.first else { return }
        guard sourceURL.startAccessingSecurityScopedResource() else { return }
        defer { sourceURL.stopAccessingSecurityScopedResource() }

        let recordingsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

            let fileName = "\(UUID().uuidString).\(sourceURL.pathExtension)"
            let destinationURL = recordingsDir.appendingPathComponent(fileName)
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

            // Get audio duration
            let asset = AVURLAsset(url: destinationURL)
            let duration = CMTimeGetSeconds(asset.duration)

            let note = Note(
                id: UUID(),
                categoryId: selectedCategory,
                title: sourceURL.deletingPathExtension().lastPathComponent,
                content: "Imported audio — pending transcription.",
                source: .voice,
                audioUrl: destinationURL.path,
                durationSeconds: duration.isFinite ? duration : nil,
                createdAt: .now,
                updatedAt: .now
            )

            withAnimation(.snappy) {
                noteStore.addNote(note)
            }
        } catch {
            // TODO: Surface error to user
        }
    }

    private var bottomSafeArea: CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.keyWindow else { return 0 }
        return window.safeAreaInsets.bottom
    }

    private func cycleCategory(forward: Bool) {
        let categoryIds: [UUID?] = [nil] + noteStore.categories.map(\.id)
        guard let currentIndex = categoryIds.firstIndex(of: selectedCategory) else { return }

        let nextIndex: Int
        if forward {
            nextIndex = currentIndex + 1 < categoryIds.count ? currentIndex + 1 : 0
        } else {
            nextIndex = currentIndex - 1 >= 0 ? currentIndex - 1 : categoryIds.count - 1
        }

        withAnimation(.snappy) {
            selectedCategory = categoryIds[nextIndex]
        }
    }

    private var filteredNotes: [Note] {
        var notes = selectedCategory == nil
            ? noteStore.notes
            : noteStore.notes.filter { $0.categoryId == selectedCategory }

        if isSearching && !query.isEmpty {
            let lowered = query.lowercased()
            notes = notes.filter { note in
                (note.title?.lowercased().contains(lowered) ?? false)
                    || note.content.lowercased().contains(lowered)
            }
        }

        return notes.sorted {
            switch sortOrder {
            case .updatedAt: $0.updatedAt > $1.updatedAt
            case .createdAt: $0.createdAt > $1.createdAt
            }
        }
    }
}

// MARK: - Greeting Underlines

private struct ScribbleUnderline: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: 0, y: h * 0.5))
        path.addCurve(
            to: CGPoint(x: w * 0.2, y: h * 0.35),
            control1: CGPoint(x: w * 0.05, y: h * 0.7),
            control2: CGPoint(x: w * 0.12, y: h * 0.2)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.45, y: h * 0.65),
            control1: CGPoint(x: w * 0.28, y: h * 0.45),
            control2: CGPoint(x: w * 0.35, y: h * 0.75)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.7, y: h * 0.3),
            control1: CGPoint(x: w * 0.55, y: h * 0.55),
            control2: CGPoint(x: w * 0.62, y: h * 0.2)
        )
        path.addCurve(
            to: CGPoint(x: w, y: h * 0.5),
            control1: CGPoint(x: w * 0.78, y: h * 0.4),
            control2: CGPoint(x: w * 0.9, y: h * 0.7)
        )
        return path
    }
}

private struct SmoothArcUnderline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height))
        path.addQuadCurve(
            to: CGPoint(x: rect.width, y: rect.height),
            control: CGPoint(x: rect.width * 0.5, y: 0)
        )
        return path
    }
}
