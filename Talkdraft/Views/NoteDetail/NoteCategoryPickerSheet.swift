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
            VStack {
                ScrollView {
                    if noteStore.categories.isEmpty {
                        VStack(spacing: 0) {
                            LunaMascotView(.box, size: 180)

                            VStack(spacing: 4) {
                                Text("No Categories Yet")
                                    .font(.brandTitle2)

                                Text("Create your first category to organize this note.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                        .padding(.horizontal, 24)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(noteStore.categories) { cat in
                                let isSelected = selectedCategoryId == cat.id
                                Button {
                                    assignCategory(cat.id)
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
                                                    isSelected
                                                        ? Color.categoryColor(hex: cat.color)
                                                        : (colorScheme == .dark ? Color.white.opacity(0.10) : .clear),
                                                    lineWidth: isSelected ? 2 : 1
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                showAddCategory = true
                            } label: {
                                AddCategoryBadge()
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }
                }

                Spacer()

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
                    .padding(.bottom, 32)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if noteStore.categories.isEmpty {
                    Button {
                        showAddCategory = true
                    } label: {
                        Text("Create Category")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                Capsule()
                                    .fill(Color.brand)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                    .background(.clear)
                }
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
                assignCategory(newCategory.id)
            }
        }
        .onAppear {
            selectedCategoryId = note.categoryId
        }
    }

    private func assignCategory(_ categoryId: UUID?) {
        selectedCategoryId = categoryId
        var updated = note
        updated.categoryId = categoryId
        updated.updatedAt = Date()
        noteStore.updateNote(updated)
        dismiss()
    }
}
