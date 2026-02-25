import SwiftUI

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
    @State private var showSearch = false
    @Namespace private var namespace

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
                        // Greeting
                        greeting

                        // Category chips
                        categoryChips

                        // Notes grid
                        if filteredNotes.isEmpty {
                            emptyState
                        } else {
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(filteredNotes) { note in
                                    let category = noteStore.categories.first { $0.id == note.categoryId }
                                    NavigationLink(value: note) {
                                        NoteCard(note: note, category: category)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                    .padding(.bottom, 120) // space for floating button
                }
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

                // Floating action buttons
                floatingButtons
            }
            .navigationBarTitleDisplayMode(.inline)
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
                        Text("Settings") // TODO: SettingsView
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .navigationDestination(for: Note.self) { note in
                NoteDetailView(note: note)
            }
            .navigationDestination(isPresented: $showSearch) {
                SearchView()
            }
        }
        .fullScreenCover(isPresented: $showRecordView) {
            RecordView(categoryId: selectedCategory)
                .navigationTransition(.zoom(sourceID: "record", in: namespace))
        }
    }

    // MARK: - Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hey! 👋")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("What's on your mind?")
                .font(.title)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 8)
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

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                selectedCategory == nil
                    ? "Capture your thoughts"
                    : "No notes in this category",
                systemImage: selectedCategory == nil
                    ? "waveform"
                    : "tray"
            )
        } description: {
            Text(
                selectedCategory == nil
                    ? "Tap the mic to record your first thought."
                    : "Notes you add to this category will appear here."
            )
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // MARK: - Floating Buttons

    private var floatingButtons: some View {
        HStack(spacing: 40) {
            // Upload audio button (left)
            Button {
                // TODO: Import audio file
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
                showSearch = true
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

    // MARK: - Helpers

    private var filteredNotes: [Note] {
        let notes = selectedCategory == nil
            ? noteStore.notes
            : noteStore.notes.filter { $0.categoryId == selectedCategory }
        return notes.sorted {
            switch sortOrder {
            case .updatedAt: $0.updatedAt > $1.updatedAt
            case .createdAt: $0.createdAt > $1.createdAt
            }
        }
    }
}

