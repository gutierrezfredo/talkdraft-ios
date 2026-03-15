import SwiftUI

extension HomeView {
    var chipsBar: some View {
        let bg = colorScheme == .dark ? Color.darkBackground : Color.warmBackground
        return categoryChips
            .padding(.bottom, 12)
            .background(
                LinearGradient(
                    colors: [bg.opacity(0.7), bg.opacity(0.5), bg.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            )
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { chipsBarHeight = $0 }
    }

    var categoryChips: some View {
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
                        showAddCategory = true
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
        .alert("Delete Category?", isPresented: .init(
            get: { categoryToDelete != nil },
            set: { if !$0 { categoryToDelete = nil } }
        )) {
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
            Button("Cancel", role: .cancel) {}
        } message: {
            let count = noteStore.notes.filter { $0.categoryId == categoryToDelete?.id }.count
            Text("This will unassign \(count) note\(count == 1 ? "" : "s") from this category. Notes won't be deleted.")
        }
    }

    var selectedCategoryModel: Category? {
        guard let id = selectedCategory else { return nil }
        return noteStore.categories.first { $0.id == id }
    }

    var filteredEmptyStateMessage: Text? {
        if isSearching && !query.isEmpty, let cat = selectedCategoryModel {
            return Text("No notes matching \"\(query)\" in \(Text(cat.name).foregroundStyle(Color.categoryColor(hex: cat.color))).")
        }
        if isSearching && !query.isEmpty {
            return Text("No notes matching \"\(query)\".")
        }
        if let cat = selectedCategoryModel {
            return Text("No notes in \(Text(cat.name).foregroundStyle(Color.categoryColor(hex: cat.color))).")
        }
        return nil
    }

    var emptyState: some View {
        SwiftUI.Group {
            if isSearching && !query.isEmpty || selectedCategory != nil {
                VStack(spacing: 12) {
                    Group {
                        if isSearching && !query.isEmpty {
                            Image("search-empty")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 60)
                        } else {
                            Image("notes-empty")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 60)
                        }
                    }
                    .foregroundStyle(.secondary)

                    Text(isSearching && !query.isEmpty ? "No results" : "No notes yet")
                        .font(.brandTitle2)

                    if let filteredEmptyStateMessage {
                        filteredEmptyStateMessage
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            } else {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        VStack(spacing: 0) {
                            Text("Your voice,")
                            Text("turned into words")
                                .foregroundStyle(Color.brand)
                        }
                        .font(.brandLargeTitle)
                        .multilineTextAlignment(.center)

                        Text("Tap the mic and start talking")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HandDrawnArrow()
                        .padding(.top, 40)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 200)
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity)
    }

    func bottomBarWrapper<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    .clear,
                    (colorScheme == .dark ? Color.darkBackground : Color.warmBackground).opacity(0.5),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 50)

            content()
                .frame(maxWidth: .infinity)
                .background((colorScheme == .dark ? Color.darkBackground : Color.warmBackground).opacity(0.5))
        }
    }

    var floatingButtons: some View {
        HStack(spacing: 40) {
            Button {
                createTextNote()
            } label: {
                Image(systemName: "pencil")
                    .fontWeight(.medium)
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)

            Image(systemName: "mic.fill")
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(Circle().fill(Color.brand))
                .glassEffect(.regular.interactive(), in: .circle)
                .onTapGesture {
                    showRecordView = true
                }
                .onLongPressGesture {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showAudioImporter = true
                }
                .matchedTransitionSource(id: "record", in: namespace)

            Button {
                beginSearch()
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

    var searchBar: some View {
        HStack(spacing: 12) {
            searchFieldShell

            Button {
                endSearch()
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

    var searchFieldShell: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(.secondary)

            TextField("Search", text: $query)
                .font(.body)
                .tint(Color.brand)
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
        .matchedGeometryEffect(id: "home-search-shell", in: bottomBarNamespace)
    }

    var selectionSearchTransitionPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(Color.brand)

            Text(query)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 44)
        .glassEffect(.regular, in: .capsule)
        .matchedGeometryEffect(id: "home-search-shell", in: bottomBarNamespace)
    }

    var selectionToolbar: some View {
        HStack(spacing: 12) {
            Button {
                showCategoryPicker = true
            } label: {
                Image(systemName: "tag")
                    .fontWeight(.medium)
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)

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
        .overlay(alignment: .top) {
            if showsSelectionSearchTransition, isSearching, !query.isEmpty {
                selectionSearchTransitionPill
                    .padding(.horizontal, 20)
                    .offset(y: -52)
                    .transition(.opacity)
            }
        }
    }

    var bulkCategoryPicker: some View {
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
}

private struct HandDrawnArrow: View {
    var body: some View {
        Image("hand-drawn-arrow")
            .resizable()
            .scaledToFit()
            .frame(height: 130)
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(15))
    }
}

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
