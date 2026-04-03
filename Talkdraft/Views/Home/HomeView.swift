import SwiftUI
import UniformTypeIdentifiers

enum NoteSortOrder: String, CaseIterable {
    case updatedAt = "Last Updated"
    case createdAt = "Creation Date"
    case uncategorized = "Uncategorized First"
    case actionItems = "Action Items First"
}

struct WidgetDiscoveryProgressState: Equatable {
    var trackedSuccessfulVoiceNoteIDs: Set<UUID>
    var isInitialized: Bool
    var isPendingPresentation: Bool
}

enum WidgetDiscoveryLogic {
    static let trackedSuccessfulVoiceNoteIDsKey = "widgetDiscovery.trackedSuccessfulVoiceNoteIDs"
    static let initializedKey = "widgetDiscovery.initialized"
    static let pendingPresentationKey = "widgetDiscovery.pendingPresentation"

    static func persistedState(defaults: UserDefaults = .standard) -> WidgetDiscoveryProgressState {
        let rawIDs = defaults.stringArray(forKey: trackedSuccessfulVoiceNoteIDsKey) ?? []
        let trackedIDs = Set(rawIDs.compactMap(UUID.init(uuidString:)))
        return WidgetDiscoveryProgressState(
            trackedSuccessfulVoiceNoteIDs: trackedIDs,
            isInitialized: defaults.bool(forKey: initializedKey),
            isPendingPresentation: defaults.bool(forKey: pendingPresentationKey)
        )
    }

    static func persist(_ state: WidgetDiscoveryProgressState, defaults: UserDefaults = .standard) {
        defaults.set(state.trackedSuccessfulVoiceNoteIDs.map(\.uuidString).sorted(), forKey: trackedSuccessfulVoiceNoteIDsKey)
        defaults.set(state.isInitialized, forKey: initializedKey)
        defaults.set(state.isPendingPresentation, forKey: pendingPresentationKey)
    }

    static func clearPendingPresentation(defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: pendingPresentationKey)
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: trackedSuccessfulVoiceNoteIDsKey)
        defaults.removeObject(forKey: initializedKey)
        defaults.removeObject(forKey: pendingPresentationKey)
    }

    nonisolated static func syncedState(
        notes: [Note],
        deletedNotes: [Note],
        persistedState: WidgetDiscoveryProgressState
    ) -> WidgetDiscoveryProgressState {
        let knownSuccessfulVoiceNoteIDs = Set<UUID>(
            (notes + deletedNotes).compactMap { note in
                guard note.source == .voice,
                      !note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { return nil }
                return note.id
            }
        )

        guard persistedState.isInitialized else {
            return WidgetDiscoveryProgressState(
                trackedSuccessfulVoiceNoteIDs: knownSuccessfulVoiceNoteIDs,
                isInitialized: true,
                isPendingPresentation: false
            )
        }

        let updatedTrackedIDs = persistedState.trackedSuccessfulVoiceNoteIDs.union(knownSuccessfulVoiceNoteIDs)
        let crossedThreshold = persistedState.trackedSuccessfulVoiceNoteIDs.count < 2 && updatedTrackedIDs.count >= 2

        return WidgetDiscoveryProgressState(
            trackedSuccessfulVoiceNoteIDs: updatedTrackedIDs,
            isInitialized: true,
            isPendingPresentation: persistedState.isPendingPresentation || crossedThreshold
        )
    }

    nonisolated static func shouldPresent(
        isDismissed: Bool,
        isPresented: Bool,
        isRecording: Bool,
        completedTitleNoteID: UUID?,
        notes: [Note],
        persistedState: WidgetDiscoveryProgressState
    ) -> Bool {
        guard persistedState.isPendingPresentation,
              !isDismissed,
              !isPresented,
              !isRecording,
              let completedTitleNoteID
        else { return false }

        return notes.contains { note in
            note.id == completedTitleNoteID
                && note.source == .voice
                && !note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

struct SavedNoteHandoffState: Equatable {
    var pendingNote: Note?
    var selectedNote: Note?
    var isInteractionLocked: Bool
}

enum SavedNoteHandoffLogic {
    static func begin(with savedNote: Note, isMandatoryPaywallPresented: Bool) -> SavedNoteHandoffState {
        SavedNoteHandoffState(
            pendingNote: savedNote,
            selectedNote: isMandatoryPaywallPresented ? nil : savedNote,
            isInteractionLocked: true
        )
    }

    static func resume(
        pendingNote: Note?,
        selectedNote: Note?,
        isMandatoryPaywallPresented: Bool
    ) -> SavedNoteHandoffState {
        guard let pendingNote else {
            return SavedNoteHandoffState(
                pendingNote: nil,
                selectedNote: selectedNote,
                isInteractionLocked: false
            )
        }

        guard !isMandatoryPaywallPresented else {
            return SavedNoteHandoffState(
                pendingNote: pendingNote,
                selectedNote: selectedNote,
                isInteractionLocked: true
            )
        }

        let resolvedSelectedNote = selectedNote ?? pendingNote
        let routeCompleted = resolvedSelectedNote.id == pendingNote.id

        return SavedNoteHandoffState(
            pendingNote: routeCompleted ? nil : pendingNote,
            selectedNote: resolvedSelectedNote,
            isInteractionLocked: !routeCompleted
        )
    }
}

struct HomeView: View {
    @Environment(AuthStore.self) var authStore
    @Environment(NoteStore.self) var noteStore
    @Environment(SettingsStore.self) var settingsStore
    @Environment(\.colorScheme) var colorScheme
    @Binding var pendingDeepLink: DeepLink?
    var isMandatoryPaywallPresented: Bool
    @State var selectedCategory: UUID?
    @State var showRecordView = false
    @State var sortOrder: NoteSortOrder = .updatedAt
    @State var isSearching = false
    @State var query = ""
    @State var isScrolled = false
    @State var isSwiping = false
    @State var selectedNote: Note?
    @State var isSelecting = false
    @State var selectedIds: Set<UUID> = []
    @State var showDeleteConfirmation = false
    @State var showCategoryPicker = false

    @State var showGuestPaywall = false
    @State var showWidgetDiscovery = false
    @State var showAudioImporter = false
    @State var pendingImportURL: URL?
    @State var showAddCategory = false
    @State var addCategoryFromBulk = false
    @State var editingCategory: Category?
    @State var categoryToDelete: Category?
    @State var pendingNote: Note?
    @State var isRoutingToSavedNote = false
    @State var keyboardHeight: CGFloat = 0
    @State var draggingCategory: Category?
    @State var chipsBarHeight: CGFloat = 0
    @State var searchPreviousCategory: UUID?
    @State var showsSelectionSearchTransition = false
    @State var selectionSearchTransitionTask: Task<Void, Never>?
    @State var suppressNextRecordButtonTap = false
    @Namespace var namespace
    @Namespace var bottomBarNamespace
    @FocusState var searchFocused: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    private var isGuestAtLimit: Bool {
        authStore.isGuest && noteStore.notes.count >= AuthStore.guestNoteLimit
    }

    private func syncWidgetDiscoveryProgress() {
        let current = WidgetDiscoveryLogic.persistedState()
        let updated = WidgetDiscoveryLogic.syncedState(
            notes: noteStore.notes,
            deletedNotes: noteStore.deletedNotes,
            persistedState: current
        )
        guard updated != current else { return }
        WidgetDiscoveryLogic.persist(updated)
    }

    private func applySavedNoteHandoff(_ state: SavedNoteHandoffState) {
        pendingNote = state.pendingNote
        selectedNote = state.selectedNote
        isRoutingToSavedNote = state.isInteractionLocked
    }

    @MainActor
    func attemptRecord() {
        guard !isRoutingToSavedNote else { return }
        if isGuestAtLimit {
            showGuestPaywall = true
        } else {
            AudioRecorder.prewarmRecordingSession()
            showRecordView = true
        }
    }

    private func consumePendingRecordDeepLinkIfPossible() {
        guard pendingDeepLink == .record, !isMandatoryPaywallPresented else { return }
        attemptRecord()
        pendingDeepLink = nil
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Background
                (colorScheme == .dark ? Color.darkBackground : Color.warmBackground)
                    .ignoresSafeArea()

                // Main content — chips float over scroll view via ZStack to avoid
                // safeAreaInset measurement races on iOS 26 cold launch
                ZStack(alignment: .top) {
                    ScrollView {
                        VStack(spacing: 0) {
                            if filteredNotes.isEmpty {
                                emptyState
                            } else {
                                LazyVGrid(columns: columns, spacing: 8) {
                                    ForEach(filteredNotes) { note in
                                        let category = noteStore.categories.first { $0.id == note.categoryId }
                                        NoteCard(
                                            note: note,
                                            category: category,
                                            content: noteStore.displayContent(for: note),
                                            selectionMode: isSelecting,
                                            isSelected: selectedIds.contains(note.id)
                                        )
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            guard !isSwiping else { return }
                                            if isSelecting {
                                                toggleSelection(note.id)
                                            } else {
                                                if isSearching {
                                                    searchFocused = false
                                                    keyboardHeight = 0
                                                }
                                                selectedNote = note
                                            }
                                        }
                                        .onLongPressGesture {
                                            enterSelection(note.id)
                                        }
                                    }
                                }
                                .padding(.horizontal, 12)
                            }
                        }
                    }
                    .simultaneousGesture(isSearching ? nil : categorySwipeGesture)
                    .onScrollGeometryChange(for: Bool.self) { geometry in
                        geometry.contentOffset.y > 20
                    } action: { _, newValue in
                        withAnimation(.snappy) { isScrolled = newValue }
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        Color.clear.frame(height: 120)
                    }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        Color.clear.frame(height: isSearching ? 0 : chipsBarHeight)
                    }
                    .scrollBounceBehavior(.always)
                    .scrollIndicators(filteredNotes.isEmpty ? .hidden : .automatic)
                    .scrollDismissesKeyboard(.interactively)
                    .refreshable {
                        await noteStore.refresh()
                    }
                    .animation(.snappy, value: isSearching)

                    if !isSearching {
                        chipsBar
                    }
                }

                // Bottom fade
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [
                            .clear,
                            colorScheme == .dark ? Color.darkBackground : Color.warmBackground,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 160)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                // Bottom bar — floating buttons, search bar, or selection toolbar
                if isSelecting {
                    bottomBarWrapper {
                        selectionToolbar
                            .padding(.bottom, 12)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if isSearching {
                    bottomBarWrapper {
                        searchBar
                            .padding(.bottom, keyboardHeight > 0 ? keyboardHeight - bottomSafeArea + 8 : 12)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    bottomBarWrapper {
                        floatingButtons
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if isRoutingToSavedNote {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                }
            }
            .ignoresSafeArea(.keyboard)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(isSearching ? "Search" : "")
            .toolbar(isSelecting ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                if !isSearching {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Section {
                                Picker("Sort by", selection: $sortOrder) {
                                    Text(NoteSortOrder.updatedAt.rawValue).tag(NoteSortOrder.updatedAt)
                                    Text(NoteSortOrder.createdAt.rawValue).tag(NoteSortOrder.createdAt)
                                }
                            }
                            Section {
                                Picker("Sort by", selection: $sortOrder) {
                                    Text(NoteSortOrder.uncategorized.rawValue).tag(NoteSortOrder.uncategorized)
                                    Text(NoteSortOrder.actionItems.rawValue).tag(NoteSortOrder.actionItems)
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 12) {
                            NavigationLink {
                                SettingsView()
                            } label: {
                                Image(systemName: "gearshape")
                            }
                        }
                    }
                }
            }
            .navigationDestination(item: $selectedNote) { note in
                NoteDetailView(note: note, initialContent: noteStore.displayContent(for: note))
            }
            .task {
                // Catch any cold-launch race where categories failed to load
                if noteStore.categories.isEmpty {
                    try? await noteStore.fetchCategories()
                }
                if noteStore.notes.isEmpty {
                    await noteStore.refresh()
                }
            }
        }
        .fullScreenCover(isPresented: $showRecordView, onDismiss: {
            applySavedNoteHandoff(
                SavedNoteHandoffLogic.resume(
                    pendingNote: pendingNote,
                    selectedNote: selectedNote,
                    isMandatoryPaywallPresented: isMandatoryPaywallPresented
                )
            )
        }) {
            RecordView(categoryId: selectedCategory) { savedNote in
                applySavedNoteHandoff(
                    SavedNoteHandoffLogic.begin(
                        with: savedNote,
                        isMandatoryPaywallPresented: isMandatoryPaywallPresented
                    )
                )
            }
            .navigationTransition(.zoom(sourceID: "record", in: namespace))
        }
        .fullScreenCover(isPresented: $showGuestPaywall) {
            OnboardingPaywallStep(
                onPurchaseCompleted: { _ in showGuestPaywall = false },
                onRestored: { showGuestPaywall = false },
                onDismiss: { showGuestPaywall = false }
            )
        }
        .sheet(isPresented: $showWidgetDiscovery) {
            WidgetDiscoverySheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground { SheetBackground() }
        }
        .fileImporter(
            isPresented: $showAudioImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            handleAudioImport(result)
        }
        .sheet(isPresented: .init(
            get: { pendingImportURL != nil },
            set: { if !$0 { pendingImportURL = nil } }
        )) {
            AudioImportSheet(fileName: pendingImportURL?.lastPathComponent ?? "") { multiSpeaker in
                confirmAudioImport(multiSpeaker: multiSpeaker)
            }
            .presentationDetents([.height(220)])
            .presentationBackground { SheetBackground() }
        }
        .alert("Delete \(selectedIds.count) Note\(selectedIds.count == 1 ? "" : "s")?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                noteStore.removeNotes(ids: selectedIds)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                exitSelection()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .sheet(isPresented: $showCategoryPicker) {
            bulkCategoryPicker
                .presentationDetents([.medium, .large])
                .presentationBackground { SheetBackground() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
                withAnimation(.interpolatingSpring(duration: duration, bounce: 0)) {
                    keyboardHeight = frame.height
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
            let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            withAnimation(.interpolatingSpring(duration: duration, bounce: 0)) {
                keyboardHeight = 0
            }
        }
        .alert("Error", isPresented: .init(
            get: { noteStore.lastError != nil },
            set: { if !$0 { noteStore.lastError = nil } }
        )) {
            Button("OK") { noteStore.lastError = nil }
        } message: {
            Text(noteStore.lastError ?? "")
        }
        .onAppear {
            syncWidgetDiscoveryProgress()
            consumePendingRecordDeepLinkIfPossible()
        }
        .onChange(of: noteStore.notes) { _, _ in
            syncWidgetDiscoveryProgress()
        }
        .onChange(of: noteStore.deletedNotes) { _, _ in
            syncWidgetDiscoveryProgress()
        }
        .onChange(of: pendingDeepLink) { _, link in
            guard link == .record else { return }
            consumePendingRecordDeepLinkIfPossible()
        }
        .onChange(of: isMandatoryPaywallPresented) { _, presented in
            guard !presented else { return }
            applySavedNoteHandoff(
                SavedNoteHandoffLogic.resume(
                    pendingNote: pendingNote,
                    selectedNote: selectedNote,
                    isMandatoryPaywallPresented: presented
                )
            )
            consumePendingRecordDeepLinkIfPossible()
        }
        .onChange(of: noteStore.lastCompletedTitleGenerationNoteId) { _, noteId in
            syncWidgetDiscoveryProgress()
            let progress = WidgetDiscoveryLogic.persistedState()
            guard WidgetDiscoveryLogic.shouldPresent(
                isDismissed: WidgetDiscoverySheet.wasDismissed,
                isPresented: showWidgetDiscovery,
                isRecording: showRecordView,
                completedTitleNoteID: noteId,
                notes: noteStore.notes,
                persistedState: progress
            )
            else { return }

            WidgetDiscoveryLogic.clearPendingPresentation()
            // Small delay so the user sees their note card update first
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                showWidgetDiscovery = true
            }
        }
    }
}
