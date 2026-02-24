import SwiftUI

struct HomeView: View {
    @Environment(NoteStore.self) private var noteStore
    @State private var searchText = ""
    @State private var selectedCategory: UUID?

    var body: some View {
        @Bindable var store = noteStore

        NavigationStack {
            List {
                ForEach(filteredNotes) { note in
                    let category = noteStore.categories.first { $0.id == note.categoryId }
                    NoteRow(note: note, category: category)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let note = filteredNotes[index]
                        noteStore.removeNote(id: note.id)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("SpiritNotes")
            .searchable(text: $searchText, prompt: "Search notes")
            .overlay {
                if filteredNotes.isEmpty {
                    if searchText.isEmpty && selectedCategory == nil {
                        ContentUnavailableView(
                            "No Notes",
                            systemImage: "waveform",
                            description: Text("Tap the mic to record your first thought.")
                        )
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    categoryMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        Text("Settings") // TODO: SettingsView
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    recordButton
                }
            }
        }
    }

    // MARK: - Category Menu

    private var categoryMenu: some View {
        Menu {
            Button {
                selectedCategory = nil
            } label: {
                Label("All Notes", systemImage: selectedCategory == nil ? "checkmark" : "")
            }

            Divider()

            ForEach(noteStore.categories) { category in
                Button {
                    selectedCategory = category.id
                } label: {
                    Label(category.name, systemImage: selectedCategory == category.id ? "checkmark" : "circle.fill")
                        .tint(Color(hex: category.color))
                }
            }
        } label: {
            Label(selectedCategoryName, systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    // MARK: - Record Button

    private var recordButton: some View {
        Button {
            // TODO: Navigate to record
        } label: {
            Label("Record", systemImage: "mic.fill")
                .font(.headline)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }

    // MARK: - Helpers

    private var selectedCategoryName: String {
        guard let id = selectedCategory,
              let cat = noteStore.categories.first(where: { $0.id == id }) else {
            return "All Notes"
        }
        return cat.name
    }

    private var filteredNotes: [Note] {
        var notes = selectedCategory == nil
            ? noteStore.notes
            : noteStore.notes.filter { $0.categoryId == selectedCategory }

        if !searchText.isEmpty {
            notes = notes.filter {
                ($0.title ?? "").localizedCaseInsensitiveContains(searchText) ||
                $0.content.localizedCaseInsensitiveContains(searchText)
            }
        }

        return notes
    }
}
