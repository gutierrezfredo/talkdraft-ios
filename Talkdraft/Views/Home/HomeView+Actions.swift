import SwiftUI

extension HomeView {
    func presentGuestPaywallIfNeeded() -> Bool {
        guard authStore.isGuest, noteStore.notes.count >= AuthStore.guestNoteLimit else {
            return false
        }
        showGuestPaywall = true
        return true
    }

    func beginSearch() {
        selectionSearchTransitionTask?.cancel()
        showsSelectionSearchTransition = false
        searchPreviousCategory = selectedCategory
        withAnimation(.snappy) {
            selectedCategory = nil
            isSearching = true
        }
        searchFocused = true
    }

    func endSearch() {
        selectionSearchTransitionTask?.cancel()
        withAnimation(.snappy) {
            isSearching = false
            query = ""
            searchFocused = false
            showsSelectionSearchTransition = false
            selectedCategory = searchPreviousCategory
        }
        searchPreviousCategory = nil
    }

    func enterSelection(_ noteId: UUID) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let shouldAnimateSearchContext = isSearching && !query.isEmpty
        selectionSearchTransitionTask?.cancel()
        withAnimation(.snappy) {
            searchFocused = false
            showsSelectionSearchTransition = shouldAnimateSearchContext
            isSelecting = true
            selectedIds = [noteId]
        }
        guard shouldAnimateSearchContext else { return }
        selectionSearchTransitionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                showsSelectionSearchTransition = false
            }
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
        selectionSearchTransitionTask?.cancel()
        withAnimation(.snappy) {
            isSelecting = false
            showsSelectionSearchTransition = false
            selectedIds = []
        }
    }

    func handleAudioImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let sourceURL = urls.first else { return }
        pendingImportURL = sourceURL
    }

    func confirmAudioImport(multiSpeaker: Bool) {
        guard let sourceURL = pendingImportURL else { return }
        pendingImportURL = nil
        guard !presentGuestPaywallIfNeeded() else { return }

        Task { @MainActor in
            do {
                let note = try await noteStore.importAudioNote(
                    from: sourceURL,
                    userId: authStore.userId,
                    categoryId: selectedCategory,
                    language: settingsStore.language == "auto" ? nil : settingsStore.language,
                    customDictionary: settingsStore.customDictionary,
                    multiSpeaker: multiSpeaker
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
        guard !presentGuestPaywallIfNeeded() else { return }

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
