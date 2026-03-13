import SwiftUI

extension HomeView {
    func enterSelection(_ noteId: UUID) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.snappy) {
            isSelecting = true
            selectedIds = [noteId]
        }
    }

    func toggleSelection(_ noteId: UUID) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if selectedIds.contains(noteId) {
            selectedIds.remove(noteId)
            if selectedIds.isEmpty {
                withAnimation(.snappy) {
                    isSelecting = false
                }
            }
        } else {
            selectedIds.insert(noteId)
        }
    }

    func exitSelection() {
        withAnimation(.snappy) {
            isSelecting = false
            selectedIds = []
        }
    }

    func handleAudioImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let sourceURL = urls.first else { return }

        Task { @MainActor in
            do {
                let note = try await noteStore.importAudioNote(
                    from: sourceURL,
                    userId: authStore.userId,
                    categoryId: selectedCategory,
                    language: settingsStore.language == "auto" ? nil : settingsStore.language,
                    customDictionary: settingsStore.customDictionary
                )
                withAnimation(.snappy) {
                    selectedNote = note
                }
            } catch {
                noteStore.lastError = error.localizedDescription
            }
        }
    }

    func createTextNote() {
        let note = Note(
            id: UUID(),
            userId: authStore.userId,
            categoryId: selectedCategory,
            title: nil,
            content: "",
            source: .text,
            createdAt: .now,
            updatedAt: .now
        )

        selectedNote = note
    }

    var bottomSafeArea: CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.keyWindow else { return 0 }
        return window.safeAreaInsets.bottom
    }

    var categorySwipeGesture: some Gesture {
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

                Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    isSwiping = false
                }
            }
    }

    func cycleCategory(forward: Bool) {
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

    var filteredNotes: [Note] {
        var notes = selectedCategory == nil
            ? noteStore.notes
            : noteStore.notes.filter { $0.categoryId == selectedCategory }

        if isSearching && !query.isEmpty {
            let lowered = query.lowercased()
            notes = notes.filter { note in
                (note.title?.lowercased().contains(lowered) ?? false)
                    || noteStore.resolvedContent(for: note).lowercased().contains(lowered)
            }
        }

        return notes.sorted {
            switch sortOrder {
            case .updatedAt: return $0.updatedAt > $1.updatedAt
            case .createdAt: return $0.createdAt > $1.createdAt
            case .uncategorized:
                if ($0.categoryId == nil) != ($1.categoryId == nil) {
                    return $0.categoryId == nil
                }
                return $0.updatedAt > $1.updatedAt
            case .actionItems:
                let aContent = noteStore.resolvedContent(for: $0)
                let bContent = noteStore.resolvedContent(for: $1)
                let aHas = aContent.contains("☐") || aContent.contains("☑")
                let bHas = bContent.contains("☐") || bContent.contains("☑")
                if aHas != bHas { return aHas }
                return $0.updatedAt > $1.updatedAt
            }
        }
    }
}
