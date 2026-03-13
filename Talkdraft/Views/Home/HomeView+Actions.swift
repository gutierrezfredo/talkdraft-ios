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
        HomeNoteQuery.filteredNotes(
            notes: noteStore.notes,
            selectedCategory: selectedCategory,
            query: isSearching ? query : "",
            sortOrder: sortOrder,
            resolvedContent: noteStore.resolvedContent(for:)
        )
    }
}
