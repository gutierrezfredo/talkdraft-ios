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
    @State private var showSearch = false
    @State private var showAudioImporter = false
    @State private var showAddCategory = false
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
                        SettingsView()
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
        .fileImporter(
            isPresented: $showAudioImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            handleAudioImport(result)
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
