import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

enum NoteSortOrder: String, CaseIterable {
    case updatedAt = "Last Updated"
    case createdAt = "Creation Date"
    case uncategorized = "Uncategorized First"
    case actionItems = "Action Items First"
}

struct HomeView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(NoteStore.self) private var noteStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptionStore
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
    @State private var editingCategory: Category?
    @State private var categoryToDelete: Category?
    @State private var pendingNote: Note?
    @State private var keyboardHeight: CGFloat = 0
    @State private var showPaywall = false
    @State private var draggingCategory: Category?
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
                (colorScheme == .dark ? Color.darkBackground : Color.warmBackground)
                    .ignoresSafeArea()

                // Main content
                ScrollView {
                    VStack(spacing: 12) {
                        // Category chips
                        categoryChips

                        // Notes grid + swipeable area
                        VStack(spacing: 0) {
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

                            // Fill remaining space
                            Color.clear
                                .frame(maxWidth: .infinity, minHeight: 300)
                        }
                        .contentShape(Rectangle())
                        .simultaneousGesture(categorySwipeGesture)
                    }
                    .padding(.bottom, 120)
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
                            (colorScheme == .dark ? Color.darkBackground : Color.warmBackground),
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
                        Section {
                            Picker("Sort by", selection: $sortOrder) {
                                Text(NoteSortOrder.updatedAt.rawValue).tag(NoteSortOrder.updatedAt)
                                Text(NoteSortOrder.createdAt.rawValue).tag(NoteSortOrder.createdAt)
                            }
                        }
                        Section {
                            Picker("Sort by", selection: $sortOrder) {
                                Text(NoteSortOrder.uncategorized.rawValue).tag(NoteSortOrder.uncategorized)
                                Text(NoteSortOrder.actionItems.rawValue).tag(NoteSortOrder.actionItems)
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
        .fullScreenCover(isPresented: $showRecordView, onDismiss: {
            if let note = pendingNote {
                selectedNote = note
                pendingNote = nil
            }
        }) {
            RecordView(categoryId: selectedCategory) { savedNote in
                pendingNote = savedNote
            }
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
                .presentationDetents([.medium, .large])
                .presentationBackground {
                    SheetBackground()
                }
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
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .alert("Error", isPresented: .init(
            get: { noteStore.lastError != nil },
            set: { if !$0 { noteStore.lastError = nil } }
        )) {
            Button("OK") { noteStore.lastError = nil }
        } message: {
            Text(noteStore.lastError ?? "")
        }
    }

    // MARK: - Category Chips

    private var categoryChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CategoryChip(
                        name: "All",
                        color: .brand,
                        isSelected: selectedCategory == nil
                    ) {
                        withAnimation(.snappy) { selectedCategory = nil }
                    }
                    .id("all")

                    ForEach(noteStore.categories) { category in
                        CategoryChip(
                            name: category.name,
                            color: Color.categoryColor(hex: category.color),
                            isSelected: selectedCategory == category.id
                        ) {
                            withAnimation(.snappy) {
                                selectedCategory = selectedCategory == category.id ? nil : category.id
                            }
                        }
                        .onDrag {
                            draggingCategory = category
                            return NSItemProvider(object: category.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: CategoryReorderDelegate(
                            target: category,
                            categories: noteStore.categories,
                            dragging: $draggingCategory,
                            onMove: { noteStore.moveCategory(from: $0, to: $1) }
                        ))
                        .id(category.id.uuidString)
                    }

                    Button {
                        if let limit = subscriptionStore.categoriesLimit, noteStore.categories.count >= limit {
                            showPaywall = true
                        } else {
                            showAddCategory = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(colorScheme == .dark ? Color.darkSurface : .white)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .onChange(of: selectedCategory) {
                withAnimation(.snappy) {
                    let targetId = selectedCategory?.uuidString ?? "all"
                    proxy.scrollTo(targetId, anchor: .center)
                }
            }
        }
        .sheet(isPresented: $showAddCategory) {
            CategoryFormSheet(mode: .add) { category in
                selectedCategory = category.id
            }
        }
        .sheet(item: $editingCategory) { category in
            CategoryFormSheet(mode: .edit(category))
        }
        .confirmationDialog(
            "Delete Category",
            isPresented: .init(
                get: { categoryToDelete != nil },
                set: { if !$0 { categoryToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let category = categoryToDelete {
                Button("Delete", role: .destructive) {
                    if selectedCategory == category.id {
                        withAnimation(.snappy) { selectedCategory = nil }
                    }
                    withAnimation(.snappy) {
                        noteStore.removeCategory(id: category.id)
                    }
                    categoryToDelete = nil
                }
            }
        } message: {
            let count = noteStore.notes.filter { $0.categoryId == categoryToDelete?.id }.count
            Text("This will unassign \(count) note\(count == 1 ? "" : "s") from this category. Notes won't be deleted.")
        }
    }

    // MARK: - Empty State

    private var selectedCategoryModel: Category? {
        guard let id = selectedCategory else { return nil }
        return noteStore.categories.first { $0.id == id }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            if isSearching && !query.isEmpty {
                Label("No results", systemImage: "magnifyingglass")
            } else {
                Label(
                    selectedCategory == nil
                        ? "Capture your thoughts"
                        : "No notes yet",
                    systemImage: selectedCategory == nil
                        ? "waveform"
                        : "tray"
                )
            }
        } description: {
            if isSearching && !query.isEmpty, let cat = selectedCategoryModel {
                Text("No notes matching \"\(query)\" in ")
                    + Text(cat.name).foregroundColor(Color.categoryColor(hex: cat.color))
                    + Text(".")
            } else if isSearching && !query.isEmpty {
                Text("No notes matching \"\(query)\".")
            } else if let cat = selectedCategoryModel {
                Text("No notes in ")
                    + Text(cat.name).foregroundColor(Color.categoryColor(hex: cat.color))
                    + Text(".")
            } else {
                Text("Tap the mic to record your first thought.")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding(.bottom, 0)
    }

    // MARK: - Floating Buttons

    private var floatingButtons: some View {
        HStack(spacing: 40) {
            // Create text note button (left)
            Button {
                if let limit = subscriptionStore.notesLimit, noteStore.notes.count >= limit {
                    showPaywall = true
                } else {
                    createTextNote()
                }
            } label: {
                Image(systemName: "pencil")
                    .fontWeight(.medium)
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)

            // Record button (center) — long-press to import audio
            Image(systemName: "mic.fill")
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(Circle().fill(Color.brand))
                .glassEffect(.regular.interactive(), in: .circle)
                .onTapGesture {
                    if let limit = subscriptionStore.notesLimit, noteStore.notes.count >= limit {
                        showPaywall = true
                    } else {
                        showRecordView = true
                    }
                }
                .onLongPressGesture {
                    if let limit = subscriptionStore.notesLimit, noteStore.notes.count >= limit {
                        showPaywall = true
                    } else {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        showAudioImporter = true
                    }
                }
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
            .frame(height: 44)
            .glassEffect(.regular, in: .capsule)

            Button {
                withAnimation(.snappy) {
                    isSearching = false
                    query = ""
                    searchFocused = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
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
            ScrollView {
                VStack(spacing: 20) {
                    FlowLayout(spacing: 8) {
                        ForEach(noteStore.categories) { cat in
                            Button {
                                noteStore.moveNotes(ids: selectedIds, toCategoryId: cat.id)
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                exitSelection()
                                showCategoryPicker = false
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
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)

                    Button {
                        noteStore.moveNotes(ids: selectedIds, toCategoryId: nil)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        exitSelection()
                        showCategoryPicker = false
                    } label: {
                        Text("Remove category")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 20)
            }
            .navigationTitle("Move to Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
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

            let asset = AVURLAsset(url: destinationURL)
            let duration = CMTimeGetSeconds(asset.duration)

            let noteId = UUID()
            let note = Note(
                id: noteId,
                userId: authStore.userId,
                categoryId: selectedCategory,
                title: sourceURL.deletingPathExtension().lastPathComponent,
                content: "Transcribing…",
                source: .voice,
                audioUrl: destinationURL.path,
                durationSeconds: duration.isFinite ? Int(duration) : nil,
                createdAt: .now,
                updatedAt: .now
            )

            withAnimation(.snappy) {
                noteStore.addNote(note)
            }

            selectedNote = note

            let language = settingsStore.language == "auto" ? nil : settingsStore.language
            let userId = authStore.userId
            noteStore.transcribeNote(id: noteId, audioFileURL: destinationURL, language: language, userId: userId)
        } catch {
            noteStore.lastError = "Failed to import audio file"
        }
    }

    private func createTextNote() {
        let note = Note(
            id: UUID(),
            userId: authStore.userId,
            categoryId: selectedCategory,
            title: nil,
            content: "",
            source: .text,
            createdAt: .now,
            updatedAt: .now
        )

        selectedNote = note
    }

    private var bottomSafeArea: CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.keyWindow else { return 0 }
        return window.safeAreaInsets.bottom
    }

    private var categorySwipeGesture: some Gesture {
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

                Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    isSwiping = false
                }
            }
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
            case .updatedAt: return $0.updatedAt > $1.updatedAt
            case .createdAt: return $0.createdAt > $1.createdAt
            case .uncategorized:
                if ($0.categoryId == nil) != ($1.categoryId == nil) {
                    return $0.categoryId == nil
                }
                return $0.updatedAt > $1.updatedAt
            case .actionItems:
                let aHas = $0.content.contains("☐") || $0.content.contains("☑")
                let bHas = $1.content.contains("☐") || $1.content.contains("☑")
                if aHas != bHas { return aHas }
                return $0.updatedAt > $1.updatedAt
            }
        }
    }
}

// MARK: - Category Reorder

private struct CategoryReorderDelegate: DropDelegate {
    let target: Category
    let categories: [Category]
    @Binding var dragging: Category?
    let onMove: (IndexSet, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging,
              dragging.id != target.id,
              let fromIndex = categories.firstIndex(where: { $0.id == dragging.id }),
              let toIndex = categories.firstIndex(where: { $0.id == target.id }) else { return }

        withAnimation(.snappy) {
            onMove(IndexSet(integer: fromIndex), toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}
