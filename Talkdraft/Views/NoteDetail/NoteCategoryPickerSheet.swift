import SwiftUI

// MARK: - Category Picker Sheet

struct CategoryPickerSheet: View {
    @Environment(NoteStore.self) private var noteStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let note: Note

    @State private var selectedCategoryId: UUID?
    @State private var showAddCategory = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Category grid
                    FlowLayout(spacing: 8) {
                        ForEach(noteStore.categories) { cat in
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
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(
                                                isSelected ? Color.categoryColor(hex: cat.color) : .clear,
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
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    Capsule()
                                        .fill(colorScheme == .dark ? Color.darkSurface : .white.opacity(0.7))
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

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
                }
                .padding(.top, 20)
            }
            .navigationTitle("Move to category")
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
            }
            .sensoryFeedback(.selection, trigger: selectedCategoryId)
        }
        .sheet(isPresented: $showAddCategory) {
            CategoryFormSheet(mode: .add) { newCategory in
                selectedCategoryId = newCategory.id
                var updated = note
                updated.categoryId = newCategory.id
                updated.updatedAt = Date()
                noteStore.updateNote(updated)
            }
        }
        .onAppear {
            selectedCategoryId = note.categoryId
        }
    }
}
