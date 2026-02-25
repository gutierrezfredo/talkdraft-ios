import SwiftUI

struct SearchView: View {
    @Environment(NoteStore.self) private var noteStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedCategory: UUID?
    @State private var keyboardHeight: CGFloat = 0
    @State private var selectedNote: Note?
    @State private var isSwiping = false
    @FocusState private var searchFocused: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    private var displayedNotes: [Note] {
        var notes = noteStore.notes

        // Filter by category
        if let categoryId = selectedCategory {
            notes = notes.filter { $0.categoryId == categoryId }
        }

        // Filter by query
        if !query.isEmpty {
            let lowered = query.lowercased()
            notes = notes.filter { note in
                (note.title?.lowercased().contains(lowered) ?? false)
                    || note.content.lowercased().contains(lowered)
            }
        }

        return notes.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Content area
            VStack(spacing: 0) {
                // Category pills
                categoryChips
                    .padding(.top, 4)

                // Notes
                if displayedNotes.isEmpty && !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .frame(maxHeight: .infinity)
                        .padding(.bottom, keyboardHeight > 0 ? keyboardHeight + 60 : 0)
                } else if displayedNotes.isEmpty {
                    ContentUnavailableView {
                        Label("No notes", systemImage: "tray")
                    } description: {
                        Text("No notes in this category.")
                    }
                    .frame(maxHeight: .infinity)
                    .padding(.bottom, keyboardHeight > 0 ? keyboardHeight + 60 : 0)
                } else {
                    ScrollView {
                        notesGrid(displayedNotes)
                            .padding(.top, 8)
                            .padding(.bottom, keyboardHeight > 0 ? keyboardHeight + 60 : 90)
                    }
                    .scrollDismissesKeyboard(.immediately)
                }
            }
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

            // Search bar — floats above keyboard
            searchBar
                .padding(.bottom, keyboardHeight > 0 ? keyboardHeight - 28 : 0)
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .background(
            (colorScheme == .dark ? Color.darkBackground : Color.warmBackground)
                .ignoresSafeArea()
        )
        .ignoresSafeArea(.keyboard)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $selectedNote) { note in
            NoteDetailView(note: note)
        }
        .onAppear {
            searchFocused = true
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Notes Grid

    private func notesGrid(_ notes: [Note]) -> some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(notes) { note in
                let category = noteStore.categories.first { $0.id == note.categoryId }
                Button {
                    guard !isSwiping else { return }
                    selectedNote = note
                } label: {
                    NoteCard(note: note, category: category)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
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
                dismiss()
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

    // MARK: - Helpers

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
}
