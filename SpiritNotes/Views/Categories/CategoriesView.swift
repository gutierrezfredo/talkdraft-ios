import os
import SwiftUI

private let logger = Logger(subsystem: "com.pleymob.spiritnotes", category: "CategoriesView")

struct CategoriesView: View {
    @Environment(NoteStore.self) private var noteStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var editingCategory: Category?
    @State private var showAddSheet = false
    @State private var categoryToDelete: Category?

    private var backgroundColor: Color {
        colorScheme == .dark ? .darkBackground : .warmBackground
    }


    var body: some View {
        List {
            if noteStore.categories.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(noteStore.categories) { category in
                    let noteCount = noteStore.notes.filter { $0.categoryId == category.id }.count

                    Button {
                        editingCategory = category
                    } label: {
                        HStack(spacing: 14) {
                            Circle()
                                .fill(Color.categoryColor(hex: category.color))
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
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            categoryToDelete = category
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .listRowBackground(colorScheme == .dark ? Color.darkSurface : Color.white)
                }
            }
        }
        .contentMargins(.top, 12)
        .scrollContentBackground(.hidden)
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
                Button("Delete", role: .destructive) {
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
    var onCreated: ((Category) -> Void)?
    @Environment(AuthStore.self) private var authStore
    @Environment(NoteStore.self) private var noteStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var selectedColor: String = "#3B82F6"
    @FocusState private var isNameFocused: Bool

    private let colorOptions: [(String, String)] = [
        ("#3B82F6", "Blue"),
        ("#EF4444", "Red"),
        ("#10B981", "Green"),
        ("#F59E0B", "Amber"),
        ("#F43F5E", "Rose"),
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
                            .focused($isNameFocused)
                            .font(.body)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 16)
                            .frame(height: 56)
                            .background(
                                colorScheme == .dark ? Color.darkSurface : .white
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                            .onChange(of: name) { _, newValue in
                                if newValue.count > 50 {
                                    name = String(newValue.prefix(50))
                                }
                            }
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
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await save()
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.brand)
                    }
                    .disabled(!isValid)
                }
            }
        }
        .onAppear {
            if case .edit(let category) = mode {
                name = category.name
                selectedColor = category.color
            }
            isNameFocused = true
        }
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        switch mode {
        case .add:
            let category = Category(
                id: UUID(),
                userId: authStore.userId,
                name: trimmedName,
                color: selectedColor,
                sortOrder: noteStore.categories.count,
                createdAt: .now
            )
            do {
                try await noteStore.addCategory(category)
                onCreated?(category)
            } catch {
                logger.error("Failed to create category: \(error)")
                noteStore.lastError = "Failed to create category"
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
