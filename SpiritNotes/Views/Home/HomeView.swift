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

                // Bottom blur edge
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .frame(height: 90)
                        .mask(
                            LinearGradient(
                                colors: [.clear, .black],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
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
                Text(note.title ?? "Note Detail") // TODO: NoteDetailView
            }
            .fullScreenCover(isPresented: $showRecordView) {
                RecordView(categoryId: selectedCategory)
            }
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
            // Spacer to balance the layout (same width as search button)
            Color.clear.frame(width: 56, height: 56)

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

            // Search button (right)
            Button {
                // TODO: Navigate to search
            } label: {
                Image(systemName: "magnifyingglass")
                    .fontWeight(.medium)
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 12)
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

// MARK: - Category Chip

private struct CategoryChip: View {
    let name: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(color)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(colorScheme == .dark ? Color(hex: "#1f1f1f") : .white)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? color : .clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}
