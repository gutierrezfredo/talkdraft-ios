import SwiftUI

struct CategoriesView: View {
    @Environment(NoteStore.self) private var noteStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var editingCategory: Category?
    @State private var showAddSheet = false
    @State private var categoryToDelete: Category?

    private var backgroundColor: Color {
        colorScheme == .dark ? .darkBackground : .warmBackground
    }

    private var cardColor: Color {
        colorScheme == .dark ? .darkSurface : .white
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if noteStore.categories.isEmpty {
                    emptyState
                } else {
                    categoryList
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            CategoryFormSheet(mode: .add)
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
                Button("Delete \"\(category.name)\"", role: .destructive) {
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

    // MARK: - Category List

    private var categoryList: some View {
        VStack(spacing: 0) {
            ForEach(Array(noteStore.categories.enumerated()), id: \.element.id) { index, category in
                let noteCount = noteStore.notes.filter { $0.categoryId == category.id }.count

                Button {
                    editingCategory = category
                } label: {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(Color(hex: category.color))
                            .frame(width: 14, height: 14)

                        Text(category.name)
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        Spacer()

                        Text("\(noteCount)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        editingCategory = category
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        categoryToDelete = category
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }

                if index < noteStore.categories.count - 1 {
                    Divider()
                        .padding(.leading, 44)
                }
            }
        }
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Categories", systemImage: "folder")
        } description: {
            Text("Tap + to create your first category.")
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }
}

// MARK: - Category Form Sheet

struct CategoryFormSheet: View {
    enum Mode: Identifiable {
        case add
        case edit(Category)

        var id: String {
            switch self {
            case .add: "add"
            case .edit(let cat): cat.id.uuidString
            }
        }
    }

    let mode: Mode
    @Environment(NoteStore.self) private var noteStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var selectedColor: String = "#3B82F6"

    private let colorOptions: [(String, String)] = [
        ("#3B82F6", "Blue"),
        ("#EF4444", "Red"),
        ("#10B981", "Green"),
        ("#F59E0B", "Amber"),
        ("#7C3AED", "Violet"),
        ("#EC4899", "Pink"),
        ("#14B8A6", "Teal"),
        ("#F97316", "Orange"),
        ("#6366F1", "Indigo"),
        ("#84CC16", "Lime"),
        ("#06B6D4", "Cyan"),
        ("#A855F7", "Purple"),
    ]

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // MARK: - Name Field

                    VStack(alignment: .leading, spacing: 8) {
                        Text("NAME")
                            .font(.footnote)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)

                        TextField("Category name", text: $name)
                            .font(.body)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 16)
                            .frame(height: 56)
                            .background(
                                colorScheme == .dark ? Color.darkSurface : .white
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                    }

                    // MARK: - Color Picker

                    VStack(alignment: .leading, spacing: 8) {
                        Text("COLOR")
                            .font(.footnote)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6),
                            spacing: 12
                        ) {
                            ForEach(colorOptions, id: \.0) { hex, _ in
                                Button {
                                    selectedColor = hex
                                } label: {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 44, height: 44)
                                        .overlay {
                                            if selectedColor == hex {
                                                Image(systemName: "checkmark")
                                                    .font(.callout)
                                                    .fontWeight(.bold)
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .sensoryFeedback(.selection, trigger: selectedColor)
                            }
                        }
                        .padding(16)
                        .background(
                            colorScheme == .dark ? Color.darkSurface : .white
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                    }

                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .background(
                (colorScheme == .dark ? Color.darkBackground : .warmBackground)
                    .ignoresSafeArea()
            )
            .navigationTitle(isEditing ? "Edit Category" : "New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
        }
        .onAppear {
            if case .edit(let category) = mode {
                name = category.name
                selectedColor = category.color
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        switch mode {
        case .add:
            let category = Category(
                id: UUID(),
                name: trimmedName,
                color: selectedColor,
                sortOrder: noteStore.categories.count,
                createdAt: .now
            )
            withAnimation(.snappy) {
                noteStore.addCategory(category)
            }
        case .edit(var category):
            category.name = trimmedName
            category.color = selectedColor
            withAnimation(.snappy) {
                noteStore.updateCategory(category)
            }
        }
    }
}
