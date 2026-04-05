import AVFoundation
import Testing
@testable import Talkdraft
import SwiftUI
import UIKit

@Test func appLaunches() async throws {
    #expect(true)
}

@Test func transcriptionPromptUsesCustomDictionaryOnly() {
    let prompt = TranscriptionService.transcriptionPrompt(customDictionary: ["Surest", "Done"])

    #expect(prompt == "Surest, Done")
}

@Test func transcriptionPromptWithoutCustomDictionaryIsNil() {
    let prompt = TranscriptionService.transcriptionPrompt(customDictionary: [])

    #expect(prompt == nil)
}

@Test func mandatoryPaywallSkipsGuests() {
    let shouldPresent = ContentView.shouldPresentMandatoryPaywall(
        isAuthenticated: true,
        isGuest: true,
        isPostAuthBootstrapReady: true,
        isPro: false
    )

    #expect(shouldPresent == false)
}

@Test func mandatoryPaywallShowsForSignedInNonProUsers() {
    let shouldPresent = ContentView.shouldPresentMandatoryPaywall(
        isAuthenticated: true,
        isGuest: false,
        isPostAuthBootstrapReady: true,
        isPro: false
    )

    #expect(shouldPresent == true)
}

@Test func postOnboardingBootstrapUsesSplashInsteadOfLoginTransition() {
    let shouldShowSplash = ContentView.shouldShowSplashAfterOnboardingCompletion(
        completedOnboardingUserId: UUID(),
        isPostAuthBootstrapReady: false
    )

    #expect(shouldShowSplash == true)
}

@Test func regularPostAuthBootstrapDoesNotForceSplashWithoutOnboardingCompletion() {
    let shouldShowSplash = ContentView.shouldShowSplashAfterOnboardingCompletion(
        completedOnboardingUserId: nil,
        isPostAuthBootstrapReady: false
    )

    #expect(shouldShowSplash == false)
}

@Test func guestOnboardingCompletionCanShowHomeBeforeBootstrapFinishes() {
    let shouldShowHome = ContentView.shouldShowHomeDuringGuestBootstrap(
        completedOnboardingUserId: UUID(),
        isAuthenticated: true,
        isGuest: true
    )

    #expect(shouldShowHome == true)
}

@Test func signedInNonGuestOnboardingCompletionDoesNotBypassToHomeEarly() {
    let shouldShowHome = ContentView.shouldShowHomeDuringGuestBootstrap(
        completedOnboardingUserId: UUID(),
        isAuthenticated: true,
        isGuest: false
    )

    #expect(shouldShowHome == false)
}

@Test func onboardingPaywallUsesGuestDismissOnlyBeforeSignIn() {
    let actionBeforeSignIn = OnboardingPaywallStep.dismissActionKind(
        isAuthenticated: false,
        hasDismissAction: false,
        hasGuestContinueAction: true
    )
    let actionAfterSignIn = OnboardingPaywallStep.dismissActionKind(
        isAuthenticated: true,
        hasDismissAction: false,
        hasGuestContinueAction: true
    )

    #expect(actionBeforeSignIn == .continueAsGuest)
    #expect(actionAfterSignIn == nil)
}

@Test func paywallDismissActionPrefersExplicitDismiss() {
    let action = OnboardingPaywallStep.dismissActionKind(
        isAuthenticated: false,
        hasDismissAction: true,
        hasGuestContinueAction: true
    )

    #expect(action == .dismiss)
}

@Test func paywallPlanFallsBackToMonthlyWhenLifetimeProductIsUnavailable() {
    let plan = PaywallPlan.normalized(
        selected: .lifetime,
        hasMonthly: true,
        hasLifetime: false
    )

    #expect(plan == .monthly)
}

@Test func paywallPlanKeepsLifetimeSelectedWhenAvailable() {
    let plan = PaywallPlan.normalized(
        selected: .lifetime,
        hasMonthly: true,
        hasLifetime: true
    )

    #expect(plan == .lifetime)
}

@Test func emailSignInSheetStaysOpenForGuests() {
    let shouldAutoDismiss = EmailSignInSheet.shouldAutoDismiss(
        isAuthenticated: true,
        isGuest: true
    )

    #expect(shouldAutoDismiss == false)
}

@Test func emailSignInSheetAutoDismissesForAuthenticatedNonGuests() {
    let shouldAutoDismiss = EmailSignInSheet.shouldAutoDismiss(
        isAuthenticated: true,
        isGuest: false
    )

    #expect(shouldAutoDismiss == true)
}

@Test func onboardingTrialReminderShowsForStartedTrial() {
    let shouldShow = OnboardingView.shouldShowTrialReminderAfterPurchase(
        plan: .monthly,
        startedTrial: true,
        showsReminderForDebugPurchases: false
    )

    #expect(shouldShow == true)
}

@Test func onboardingTrialReminderCanBeForcedForDebugPurchases() {
    let shouldShow = OnboardingView.shouldShowTrialReminderAfterPurchase(
        plan: .monthly,
        startedTrial: false,
        showsReminderForDebugPurchases: true
    )

    #expect(shouldShow == true)
}

@Test func onboardingTrialReminderSkipsLifetimePurchasesEvenInDebug() {
    let shouldShow = OnboardingView.shouldShowTrialReminderAfterPurchase(
        plan: .lifetime,
        startedTrial: false,
        showsReminderForDebugPurchases: true
    )

    #expect(shouldShow == false)
}

@Test func debugResetOnboardingStateForcesOnboardingAndClearsCompletionFlags() throws {
    #if DEBUG
    let userId = UUID()
    let suiteName = "SettingsViewTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    let deviceKey = "onboarding.completed.device"
    let userKey = SettingsView.onboardingCompletedUserKey(for: userId)

    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    defaults.set(false, forKey: SettingsView.forceOnboardingKey)
    defaults.set(true, forKey: deviceKey)
    defaults.set(true, forKey: userKey)

    SettingsView.resetOnboardingState(
        userId: userId,
        forceOnboardingFlow: true,
        defaults: defaults
    )

    #expect(defaults.bool(forKey: SettingsView.forceOnboardingKey) == true)
    #expect(defaults.object(forKey: deviceKey) == nil)
    #expect(defaults.object(forKey: userKey) == nil)
    #else
    Issue.record("DEBUG-only onboarding reset helper unavailable in release configuration.")
    #endif
}

@Test func trialReminderPermissionStateTreatsAuthorizedStatusAsEnabled() {
    let state = TrialReminderPermissionState.from(.authorized)

    #expect(state == .enabled)
}

@Test func trialReminderPermissionStateTreatsProvisionalStatusAsEnabled() {
    let state = TrialReminderPermissionState.from(.provisional)

    #expect(state == .enabled)
}

@Test func trialReminderPermissionStateTreatsUndecidedStatusAsNeedingPermission() {
    let state = TrialReminderPermissionState.from(.notDetermined)

    #expect(state == .needsPermission)
}

@Test func trialReminderPermissionStateTreatsDeniedStatusAsBlocked() {
    let state = TrialReminderPermissionState.from(.denied)

    #expect(state == .blocked)
}

@Test func savedNoteHandoffPreselectsNoteAndUnlocksAfterRecordDismiss() {
    let note = makeNote(content: "", source: .voice)
    let started = SavedNoteHandoffLogic.begin(with: note, isMandatoryPaywallPresented: false)
    let resumed = SavedNoteHandoffLogic.resume(
        pendingNote: started.pendingNote,
        selectedNote: started.selectedNote,
        isMandatoryPaywallPresented: false
    )

    #expect(started.pendingNote == note)
    #expect(started.selectedNote == note)
    #expect(started.isInteractionLocked == true)
    #expect(resumed.pendingNote == nil)
    #expect(resumed.selectedNote == note)
    #expect(resumed.isInteractionLocked == false)
}

@Test func savedNoteHandoffWaitsUntilMandatoryPaywallClears() {
    let note = makeNote(content: "", source: .voice)
    let started = SavedNoteHandoffLogic.begin(with: note, isMandatoryPaywallPresented: true)
    let whilePaywallPresented = SavedNoteHandoffLogic.resume(
        pendingNote: started.pendingNote,
        selectedNote: started.selectedNote,
        isMandatoryPaywallPresented: true
    )
    let afterPaywallDismisses = SavedNoteHandoffLogic.resume(
        pendingNote: whilePaywallPresented.pendingNote,
        selectedNote: whilePaywallPresented.selectedNote,
        isMandatoryPaywallPresented: false
    )

    #expect(started.pendingNote == note)
    #expect(started.selectedNote == nil)
    #expect(started.isInteractionLocked == true)
    #expect(whilePaywallPresented.pendingNote == note)
    #expect(whilePaywallPresented.selectedNote == nil)
    #expect(whilePaywallPresented.isInteractionLocked == true)
    #expect(afterPaywallDismisses.pendingNote == nil)
    #expect(afterPaywallDismisses.selectedNote == note)
    #expect(afterPaywallDismisses.isInteractionLocked == false)
}

@Test func recordDeepLinkUnwindsOpenNoteBeforePresentingRecorder() {
    let note = makeNote(content: "Body", source: .text)

    let routing = RecordDeepLinkRoutingLogic.prepare(
        selectedNote: note,
        showCategoryPicker: false,
        showWidgetDiscovery: false,
        showAudioImporter: false,
        pendingImportURL: nil
    )

    #expect(routing.selectedNote == nil)
    #expect(routing.showCategoryPicker == false)
    #expect(routing.showWidgetDiscovery == false)
    #expect(routing.showAudioImporter == false)
    #expect(routing.pendingImportURL == nil)
    #expect(routing.shouldAttemptRecordImmediately == false)
    #expect(routing.shouldResumeAfterNoteDismissal == true)
}

@Test func recordDeepLinkResumesOnlyAfterHomePresentationIsClear() {
    #expect(
        RecordDeepLinkRoutingLogic.shouldResumeDeferredRecord(
            hasPendingDeferredRecord: true,
            selectedNote: nil,
            showCategoryPicker: false,
            showWidgetDiscovery: false,
            showAudioImporter: false,
            pendingImportURL: nil,
            isMandatoryPaywallPresented: false
        ) == true
    )

    #expect(
        RecordDeepLinkRoutingLogic.shouldResumeDeferredRecord(
            hasPendingDeferredRecord: true,
            selectedNote: makeNote(content: "Body", source: .text),
            showCategoryPicker: false,
            showWidgetDiscovery: false,
            showAudioImporter: false,
            pendingImportURL: nil,
            isMandatoryPaywallPresented: false
        ) == false
    )
}

@Test func shareTextExportsOnlyBodyContent() {
    let sharedText = NoteShareTextLogic.build(
        title: "Visible title",
        body: "Actual body line 1\nActual body line 2"
    )

    #expect(sharedText == "Actual body line 1\nActual body line 2")
}

@Test func widgetDiscoveryWaitsForSecondSuccessfulVoiceTranscription() {
    let firstVoice = makeNote(content: "First transcript", source: .voice)
    let secondVoice = makeNote(content: "Second transcript", source: .voice)
    let initial = WidgetDiscoveryProgressState(
        trackedSuccessfulVoiceNoteIDs: [],
        isInitialized: false,
        isPendingPresentation: false
    )

    let afterFirst = WidgetDiscoveryLogic.syncedState(
        notes: [firstVoice],
        deletedNotes: [],
        persistedState: initial
    )
    let afterSecond = WidgetDiscoveryLogic.syncedState(
        notes: [secondVoice, firstVoice],
        deletedNotes: [],
        persistedState: afterFirst
    )
    let shouldPresentAfterSecond = WidgetDiscoveryLogic.shouldPresent(
        isDismissed: false,
        isPresented: false,
        isRecording: false,
        completedTitleNoteID: secondVoice.id,
        notes: [secondVoice, firstVoice],
        persistedState: afterSecond
    )

    #expect(afterFirst.trackedSuccessfulVoiceNoteIDs == [firstVoice.id])
    #expect(afterFirst.isPendingPresentation == false)
    #expect(afterSecond.trackedSuccessfulVoiceNoteIDs == [firstVoice.id, secondVoice.id])
    #expect(afterSecond.isPendingPresentation == true)
    #expect(shouldPresentAfterSecond == true)
}

@Test func widgetDiscoveryIgnoresTextNotesWhenCountingTranscriptions() {
    let textNote = makeNote(content: "Typed note", source: .text)
    let voiceNote = makeNote(content: "Transcribed audio", source: .voice)
    let initial = WidgetDiscoveryProgressState(
        trackedSuccessfulVoiceNoteIDs: [],
        isInitialized: false,
        isPendingPresentation: false
    )

    let updated = WidgetDiscoveryLogic.syncedState(
        notes: [voiceNote, textNote],
        deletedNotes: [],
        persistedState: initial
    )
    let shouldPresent = WidgetDiscoveryLogic.shouldPresent(
        isDismissed: false,
        isPresented: false,
        isRecording: false,
        completedTitleNoteID: voiceNote.id,
        notes: [voiceNote, textNote],
        persistedState: updated
    )

    #expect(updated.trackedSuccessfulVoiceNoteIDs == [voiceNote.id])
    #expect(updated.isPendingPresentation == false)
    #expect(shouldPresent == false)
}

@Test func widgetDiscoveryCanRecoverAfterEarlierVoiceTitleFailure() {
    let firstVoice = makeNote(content: "First transcript", source: .voice)
    let secondVoice = makeNote(content: "Second transcript", source: .voice)
    let thirdVoice = makeNote(content: "Third transcript", source: .voice)
    let initial = WidgetDiscoveryProgressState(
        trackedSuccessfulVoiceNoteIDs: [],
        isInitialized: false,
        isPendingPresentation: false
    )

    let afterFirst = WidgetDiscoveryLogic.syncedState(
        notes: [firstVoice],
        deletedNotes: [],
        persistedState: initial
    )
    let afterSecondTranscription = WidgetDiscoveryLogic.syncedState(
        notes: [secondVoice, firstVoice],
        deletedNotes: [],
        persistedState: afterFirst
    )
    let afterThirdTranscription = WidgetDiscoveryLogic.syncedState(
        notes: [thirdVoice, secondVoice, firstVoice],
        deletedNotes: [],
        persistedState: afterSecondTranscription
    )
    let shouldPresent = WidgetDiscoveryLogic.shouldPresent(
        isDismissed: false,
        isPresented: false,
        isRecording: false,
        completedTitleNoteID: thirdVoice.id,
        notes: [thirdVoice, secondVoice, firstVoice],
        persistedState: afterThirdTranscription
    )

    #expect(afterSecondTranscription.isPendingPresentation == true)
    #expect(shouldPresent == true)
}

@Test func widgetDiscoveryDoesNotResetAfterDeletingEarlierVoiceNotes() {
    let priorVoiceNotes = (0..<5).map { index in
        makeNote(content: "Prior transcript \(index)", source: .voice)
    }
    let newFirstVoice = makeNote(content: "New transcript 1", source: .voice)
    let newSecondVoice = makeNote(content: "New transcript 2", source: .voice)
    let initial = WidgetDiscoveryProgressState(
        trackedSuccessfulVoiceNoteIDs: [],
        isInitialized: false,
        isPendingPresentation: false
    )

    let seeded = WidgetDiscoveryLogic.syncedState(
        notes: [],
        deletedNotes: priorVoiceNotes,
        persistedState: initial
    )
    let afterNewRecordings = WidgetDiscoveryLogic.syncedState(
        notes: [newSecondVoice, newFirstVoice],
        deletedNotes: priorVoiceNotes,
        persistedState: seeded
    )
    let shouldPresent = WidgetDiscoveryLogic.shouldPresent(
        isDismissed: false,
        isPresented: false,
        isRecording: false,
        completedTitleNoteID: newSecondVoice.id,
        notes: [newSecondVoice, newFirstVoice],
        persistedState: afterNewRecordings
    )

    #expect(seeded.trackedSuccessfulVoiceNoteIDs.count == 5)
    #expect(seeded.isPendingPresentation == false)
    #expect(afterNewRecordings.trackedSuccessfulVoiceNoteIDs.count == 7)
    #expect(afterNewRecordings.isPendingPresentation == false)
    #expect(shouldPresent == false)
}

@Suite(.serialized)
struct AudioWorkflowRegressionTests {
@Test func audioCompressorWrites16kMonoOutput() async throws {
    let sourceURL = try makeSineWaveFile()
    let compressedURL = try await AudioCompressor.compress(sourceURL: sourceURL)
    defer {
        try? FileManager.default.removeItem(at: sourceURL)
        AudioCompressor.cleanup(compressedURL)
    }

    let compressedFile = try AVAudioFile(forReading: compressedURL)

    #expect(FileManager.default.fileExists(atPath: compressedURL.path))
    #expect(abs(compressedFile.fileFormat.sampleRate - 16_000) < 0.5)
    #expect(compressedFile.fileFormat.channelCount == 1)
}

@MainActor
@Test func audioPlayerPreloadsAndSeeksLocalAudio() async throws {
    let sourceURL = try makeSineWaveFile(duration: 1.0)
    let player = AudioPlayer()
    defer {
        player.stop()
        try? FileManager.default.removeItem(at: sourceURL)
    }

    player.preload(url: sourceURL)
    for _ in 0..<40 {
        if player.duration > 0 {
            break
        }
        try await Task.sleep(for: .milliseconds(50))
    }

    #expect(player.duration > 0)

    player.play(url: sourceURL)
    #expect(player.isPlaying)

    let midpoint = player.duration * 0.5
    player.seek(to: midpoint)
    #expect(abs(player.currentTime - midpoint) < 0.1)

    player.pause()
    #expect(!player.isPlaying)
}

@MainActor
@Test func audioRecorderSupportsPauseResumeAndCancel() async throws {
    let recorder = AudioRecorder()

    try await recorder.startRecording()
    #expect(recorder.isRecording)
    #expect(!recorder.isPaused)

    recorder.pauseRecording()
    #expect(recorder.isPaused)

    recorder.resumeRecording()
    #expect(recorder.isRecording)
    #expect(!recorder.isPaused)

    recorder.cancelRecording()
    #expect(!recorder.isRecording)
    #expect(!recorder.isPaused)
    #expect(recorder.elapsedSeconds == 0)
}

@MainActor
@Test func noteStoreImportAudioNoteCopiesAndTranscribesImportedAudio() async throws {
    let sourceURL = try makeSineWaveFile(duration: 0.6)
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    let store = NoteStore(
        persistsLocalVoiceBodyStates: false,
        persistsPendingNoteUpserts: false,
        noteUpsertExecutor: { _ in },
        transcriptionConnectivityProbe: {},
        transcriptionUploadExecutor: { request in
            #expect(!request.audioData.isEmpty)
            #expect(request.fileName.hasSuffix(".caf"))
            #expect(request.language == "en")
            #expect(request.customDictionary == ["Talkdraft"])
            #expect(request.whisperData != nil)
            #expect(request.whisperFileName?.hasSuffix(".m4a") == true)
            return TranscriptionResult(
                text: "Imported transcript",
                language: "en",
                audioUrl: "https://example.com/audio/imported.m4a",
                durationSeconds: 2
            )
        },
        aiTitleExecutor: { _, _ in
            "Imported title"
        }
    )

    let note = try await store.importAudioNote(
        from: sourceURL,
        userId: nil,
        categoryId: nil,
        language: "en",
        customDictionary: ["Talkdraft"],
        requiresSecurityScopedAccess: false
    )

    for _ in 0..<60 {
        if let updated = store.notes.first(where: { $0.id == note.id }),
           updated.content == "Imported transcript",
           updated.audioUrl == "https://example.com/audio/imported.m4a",
           updated.title == "Imported title" {
            break
        }
        try await Task.sleep(for: .milliseconds(50))
    }

    guard let updated = store.notes.first(where: { $0.id == note.id }) else {
        Issue.record("Expected imported note to remain in the store")
        return
    }

    #expect(updated.source == .voice)
    #expect(updated.content == "Imported transcript")
    #expect(updated.language == "en")
    #expect(updated.audioUrl == "https://example.com/audio/imported.m4a")
    #expect(updated.durationSeconds == 2)
    #expect(updated.title == "Imported title")
    #expect(store.bodyState(for: updated) == .content)
    #expect(store.localAudioFileURL(for: updated.id, audioUrl: updated.audioUrl) == nil)
}

@MainActor
@Test func noteStoreRetriesTransientTitleGenerationFailures() async throws {
    actor AttemptRecorder {
        private(set) var count = 0

        func next() -> Int {
            count += 1
            return count
        }
    }

    let attempts = AttemptRecorder()
    let note = makeNote(content: "Body", source: .voice)
    let store = NoteStore(
        persistsLocalVoiceBodyStates: false,
        persistsPendingNoteUpserts: false,
        persistsPendingTitleGenerations: false,
        noteSyncDebounceDuration: .milliseconds(1),
        noteUpsertExecutor: { _ in },
        aiTitleExecutor: { _, _ in
            let attempt = await attempts.next()
            if attempt < 3 {
                throw AIError.serverError(statusCode: 503, message: "high demand")
            }
            return "Recovered title"
        }
    )
    store.notes = [note]

    store.generateTitle(for: note.id, content: note.content, language: "en")

    for _ in 0..<120 {
        if store.notes.first?.title == "Recovered title" {
            break
        }
        try await Task.sleep(for: .milliseconds(50))
    }

    #expect(store.notes.first?.title == "Recovered title")
    #expect(store.generatingTitleIds.isEmpty)
    #expect(store.pendingTitleGenerationIds.isEmpty)
}

@MainActor
@Test func noteStoreKeepsTransientTitleFailuresQueuedForRepair() async throws {
    let note = makeNote(
        content: "Body",
        source: .voice,
        durationSeconds: 120,
        createdAt: .now.addingTimeInterval(-60),
        updatedAt: .now.addingTimeInterval(-30)
    )
    let store = NoteStore(
        persistsLocalVoiceBodyStates: false,
        persistsPendingNoteUpserts: false,
        persistsPendingTitleGenerations: false,
        noteUpsertExecutor: { _ in },
        aiTitleExecutor: { _, _ in
            throw AIError.serverError(statusCode: 503, message: "high demand")
        }
    )
    store.notes = [note]

    store.generateTitle(for: note.id, content: note.content, language: "en")

    for _ in 0..<120 {
        if store.generatingTitleIds.isEmpty {
            break
        }
        try await Task.sleep(for: .milliseconds(50))
    }

    #expect(store.notes.first?.title == nil)
    #expect(store.pendingTitleGenerationIds.contains(note.id))
}

@MainActor
@Test func noteStoreClearsPendingTitleRepairWhenUserSetsTitle() {
    let note = makeNote(content: "Body", source: .voice)
    let store = NoteStore(
        persistsLocalVoiceBodyStates: false,
        persistsPendingNoteUpserts: false,
        pendingTitleGenerationIds: [note.id],
        persistsPendingTitleGenerations: false
    )
    store.notes = [note]

    var updated = note
    updated.title = "Manual title"
    store.updateNote(updated)

    #expect(!store.pendingTitleGenerationIds.contains(note.id))
}
}

@Test func noteBodyStateRecognizesVoiceTranscriptionStates() {
    #expect(NoteBodyState(content: NoteBodyState.transcribingPlaceholder, source: .voice) == .transcribing)
    #expect(NoteBodyState(content: NoteBodyState.waitingForConnectionPlaceholder, source: .voice) == .waitingForConnection)
    #expect(NoteBodyState(content: NoteBodyState.transcriptionFailedPlaceholder, source: .voice) == .transcriptionFailed)
    #expect(NoteBodyState(content: "Plain note body", source: .voice) == .content)
}

@Test func noteBodyStateTreatsTextPlaceholderPhrasesAsContent() {
    #expect(NoteBodyState(content: NoteBodyState.transcribingPlaceholder, source: .text) == .content)
    #expect(NoteBodyState(content: NoteBodyState.waitingForConnectionPlaceholder, source: .text) == .content)
    #expect(NoteBodyState(content: NoteBodyState.transcriptionFailedPlaceholder, source: .text) == .content)
}

@MainActor
@Test func noteStoreResolvedContentPrefersActiveRewrite() {
    let store = NoteStore(persistsLocalVoiceBodyStates: false)
    let noteId = UUID()
    let rewriteId = UUID()
    let note = makeNote(
        id: noteId,
        content: "Original content",
        activeRewriteId: rewriteId
    )
    let rewrite = NoteRewrite(
        id: rewriteId,
        noteId: noteId,
        content: "Rewrite content",
        createdAt: .now
    )

    store.rewritesCache[noteId] = [rewrite]

    #expect(store.resolvedContent(for: note) == "Rewrite content")
    #expect(store.bodyState(for: note) == .content)
}

@MainActor
@Test func noteStoreResolvedContentFallsBackToNoteContentWithoutCachedRewrite() {
    let store = NoteStore(persistsLocalVoiceBodyStates: false)
    let rewriteId = UUID()
    let note = makeNote(
        content: NoteBodyState.waitingForConnectionPlaceholder,
        activeRewriteId: rewriteId,
        source: .voice
    )

    #expect(store.resolvedContent(for: note) == NoteBodyState.waitingForConnectionPlaceholder)
    #expect(store.bodyState(for: note) == .waitingForConnection)
}

@MainActor
@Test func noteStoreRepairsStaleVoiceTranscriptionWithoutLocalAudio() {
    let store = NoteStore(persistsLocalVoiceBodyStates: false)
    store.notes = [
        makeNote(
            content: NoteBodyState.transcribingPlaceholder,
            source: .voice,
            durationSeconds: 60,
            updatedAt: .now.addingTimeInterval(-400)
        )
    ]

    store.repairOrphanedTranscriptions()

    #expect(store.bodyState(for: store.notes[0]) == .transcriptionFailed)
    #expect(store.notes[0].content == "")
}

@MainActor
@Test func noteStoreLeavesFreshVoiceTranscriptionAloneWithoutLocalAudio() {
    let store = NoteStore(persistsLocalVoiceBodyStates: false)
    store.notes = [
        makeNote(
            content: NoteBodyState.transcribingPlaceholder,
            source: .voice,
            durationSeconds: 60,
            updatedAt: .now.addingTimeInterval(-20)
        )
    ]

    store.repairOrphanedTranscriptions()

    #expect(store.bodyState(for: store.notes[0]) == .transcribing)
}

@MainActor
@Test func noteStoreUsesLocalVoiceBodyStateForDisplayContent() {
    let note = makeNote(content: "", source: .voice)
    let store = NoteStore(
        localVoiceBodyStates: [note.id: .transcribing],
        persistsLocalVoiceBodyStates: false
    )
    store.notes = [note]

    #expect(store.resolvedContent(for: note) == "")
    #expect(store.bodyState(for: note) == .transcribing)
    #expect(store.displayContent(for: note) == NoteBodyState.transcribingPlaceholder)
}

@Test func noteStoreExtractsRemoteAudioPathFromSupabaseStorageURLs() {
    #expect(
        NoteStore.remoteAudioPath(
            for: "https://tftwvuduzzymqxdvkwwd.supabase.co/storage/v1/object/public/audio/user-123/My%20File.m4a"
        ) == "user-123/My File.m4a"
    )
    #expect(
        NoteStore.remoteAudioPath(
            for: "https://tftwvuduzzymqxdvkwwd.supabase.co/storage/v1/object/sign/audio/folder/clip.m4a?token=abc"
        ) == "folder/clip.m4a"
    )
    #expect(NoteStore.remoteAudioPath(for: "folder/raw.m4a") == "folder/raw.m4a")
    #expect(NoteStore.remoteAudioPath(for: "file:///tmp/audio.m4a") == nil)
}

@MainActor
@Test func noteStoreFlushesPendingHardDeleteWithStoredRemoteAudioPath() async {
    let noteId = UUID()
    let pendingDelete = PendingHardDelete(noteId: noteId, remoteAudioPath: "folder/audio.m4a")
    var executedDeletes: [PendingHardDelete] = []

    let store = NoteStore(
        persistsLocalVoiceBodyStates: false,
        persistsPendingNoteUpserts: false,
        pendingHardDeletes: [noteId: pendingDelete],
        persistsPendingHardDeletes: false,
        noteUpsertExecutor: { _ in },
        hardDeleteExecutor: { pendingDelete in
            executedDeletes.append(pendingDelete)
        }
    )

    await store.flushPendingHardDelete(id: noteId)

    #expect(executedDeletes.count == 1)
    #expect(executedDeletes.first?.noteId == noteId)
    #expect(executedDeletes.first?.remoteAudioPath == "folder/audio.m4a")
    #expect(store.pendingHardDeletes[noteId] == nil)
}

@MainActor
@Test func transcribeNoteDeletesUploadedAudioWhenNoteIsMissingAfterSuccess() async throws {
    let sourceURL = try makeSineWaveFile(duration: 0.4)
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    var deletedPaths: [String] = []
    let store = NoteStore(
        persistsLocalVoiceBodyStates: false,
        persistsPendingNoteUpserts: false,
        persistsPendingHardDeletes: false,
        noteUpsertExecutor: { _ in },
        audioDeleteExecutor: { path in
            deletedPaths.append(path)
        },
        transcriptionConnectivityProbe: {},
        transcriptionUploadExecutor: { _ in
            TranscriptionResult(
                text: "Recovered transcript",
                language: "en",
                audioUrl: "https://tftwvuduzzymqxdvkwwd.supabase.co/storage/v1/object/public/audio/orphans/missing-note.m4a",
                durationSeconds: 2
            )
        },
        aiTitleExecutor: { _, _ in
            "Unused title"
        }
    )

    store.transcribeNote(id: UUID(), audioFileURL: sourceURL, language: "en", userId: nil)

    for _ in 0..<40 {
        if deletedPaths == ["orphans/missing-note.m4a"] {
            break
        }
        try await Task.sleep(for: .milliseconds(25))
    }

    #expect(deletedPaths == ["orphans/missing-note.m4a"])
}

@MainActor
@Test func noteStoreSetNoteContentClearsTransientVoiceOverrideWhenRealContentArrives() {
    let note = makeNote(content: "", source: .voice)
    let store = NoteStore(
        localVoiceBodyStates: [note.id: .waitingForConnection],
        persistsLocalVoiceBodyStates: false
    )
    store.notes = [note]

    store.setNoteContent(id: note.id, content: "Actual transcript")

    #expect(store.resolvedContent(for: store.notes[0]) == "Actual transcript")
    #expect(store.bodyState(for: store.notes[0]) == .content)
    #expect(store.displayContent(for: store.notes[0]) == "Actual transcript")
}

@Test func noteAppendPlaceholderEditorTracksInsertedRanges() {
    let result = NoteAppendPlaceholderEditor.insert(.recording, into: "HelloWorld", at: 5)

    #expect(result.content == "Hello Recording… World")
    #expect(result.placeholder.phase == .recording)
    #expect(result.placeholder.fullRange == NSRange(location: 5, length: 12))
    #expect(result.placeholder.placeholderRange == NSRange(location: 6, length: 10))
}

@Test func noteAppendPlaceholderEditorTransitionsWithoutScanningContent() {
    let inserted = NoteAppendPlaceholderEditor.insert(.recording, into: "HelloWorld", at: 5)
    let transitioned = NoteAppendPlaceholderEditor.transition(inserted.placeholder, to: .transcribing, in: inserted.content)

    #expect(transitioned?.content == "Hello Transcribing… World")
    #expect(transitioned?.placeholder.phase == .transcribing)
    #expect(transitioned?.placeholder.fullRange == NSRange(location: 5, length: 15))
    #expect(transitioned?.placeholder.placeholderRange == NSRange(location: 6, length: 13))
}

@Test func noteAppendPlaceholderEditorRemovesFullInsertedSpan() {
    let inserted = NoteAppendPlaceholderEditor.insert(.recording, into: "HelloWorld", at: 5)
    let stripped = NoteAppendPlaceholderEditor.strippedContent(from: inserted.content, placeholder: inserted.placeholder)

    #expect(stripped == "HelloWorld")
}

@Test func noteAppendPlaceholderEditorReplacesPlaceholderAndReturnsHighlightRange() {
    let inserted = NoteAppendPlaceholderEditor.insert(.transcribing, into: "HelloWorld", at: 5)
    let replaced = NoteAppendPlaceholderEditor.replace(inserted.placeholder, in: inserted.content, with: "new transcript")

    #expect(replaced?.content == "Hello new transcript World")
    #expect(replaced?.replacementRange == NSRange(location: 6, length: 14))
    #expect(replaced?.fullRange == NSRange(location: 5, length: 16))
}

@Test func noteEditorRulesToggleCheckbox() {
    let updated = NoteEditorRules.toggleCheckbox(in: "☐ Task", at: 0)
    #expect(updated == "☑ Task")
}

@Test func noteEditorRulesAutoConvertBracketPairToCheckbox() {
    let mutation = NoteEditorRules.mutation(
        for: "[",
        range: NSRange(location: 1, length: 0),
        replacementText: "]"
    )

    #expect(mutation == .apply(
        updatedText: "☐ ",
        selectedRange: NSRange(location: 2, length: 0)
    ))
}

@Test func noteEditorRulesDoNotAutoConvertBracketPairMidParagraph() {
    let mutation = NoteEditorRules.mutation(
        for: "Papi [",
        range: NSRange(location: 6, length: 0),
        replacementText: "]"
    )

    #expect(mutation == .allowSystem)
}

@Test func noteEditorRulesAutoConvertDashToBullet() {
    let mutation = NoteEditorRules.mutation(
        for: "-",
        range: NSRange(location: 1, length: 0),
        replacementText: " "
    )

    #expect(mutation == .apply(
        updatedText: "• ",
        selectedRange: NSRange(location: 2, length: 0)
    ))
}

@Test func noteEditorRulesContinueCheckboxLine() {
    let mutation = NoteEditorRules.mutation(
        for: "☐ Task",
        range: NSRange(location: 6, length: 0),
        replacementText: "\n"
    )

    #expect(mutation == .apply(
        updatedText: "☐ Task\n☐ ",
        selectedRange: NSRange(location: 9, length: 0)
    ))
}

@Test func noteEditorRulesExitEmptyCheckboxLine() {
    let mutation = NoteEditorRules.mutation(
        for: "☐ ",
        range: NSRange(location: 2, length: 0),
        replacementText: "\n"
    )

    #expect(mutation == .apply(
        updatedText: "",
        selectedRange: NSRange(location: 0, length: 0)
    ))
}

@Test func noteEditorRulesContinueBulletLine() {
    let mutation = NoteEditorRules.mutation(
        for: "• Task",
        range: NSRange(location: 6, length: 0),
        replacementText: "\n"
    )

    #expect(mutation == .apply(
        updatedText: "• Task\n• ",
        selectedRange: NSRange(location: 9, length: 0)
    ))
}

@Test func noteEditorRulesExitEmptyBulletLine() {
    let mutation = NoteEditorRules.mutation(
        for: "• ",
        range: NSRange(location: 2, length: 0),
        replacementText: "\n"
    )

    #expect(mutation == .apply(
        updatedText: "",
        selectedRange: NSRange(location: 0, length: 0)
    ))
}

@Test func noteEditorRulesRejectInsertionAtCheckboxPrefix() {
    let mutation = NoteEditorRules.mutation(
        for: "☐ Task",
        range: NSRange(location: 1, length: 0),
        replacementText: "A"
    )

    #expect(mutation == .reject)
}

@Test func noteEditorRulesRemoveCheckboxPrefixFromNonEmptyLineOnDelete() {
    let mutation = NoteEditorRules.mutation(
        for: "☐ Task",
        range: NSRange(location: 0, length: 2),
        replacementText: ""
    )

    #expect(mutation == .apply(
        updatedText: "Task",
        selectedRange: NSRange(location: 0, length: 0)
    ))
}

@Test func noteEditorRulesRejectEditsOnProtectedSpeakerLines() {
    let mutation = NoteEditorRules.mutation(
        for: "Speaker 1\nHello",
        range: NSRange(location: 0, length: 0),
        replacementText: "A",
        protectedLines: ["Speaker 1"]
    )

    #expect(mutation == .reject)
}

@Test func noteEditorRulesDoNotRestartChecklistAfterExitOnEmptyLine() {
    let mutation = NoteEditorRules.mutation(
        for: "☐ hila\n",
        range: NSRange(location: 7, length: 0),
        replacementText: "\n"
    )

    #expect(mutation == .allowSystem)
}


@Test func noteEditorRulesToggleCheckedCheckboxBackToUnchecked() {
    let updated = NoteEditorRules.toggleCheckbox(in: "☑ Done", at: 0)
    #expect(updated == "☐ Done")
}

@Test func noteEditorRulesContinueCheckedCheckboxLineWithUncheckedPrefix() {
    let mutation = NoteEditorRules.mutation(
        for: "☑ Done",
        range: NSRange(location: 6, length: 0),
        replacementText: "\n"
    )

    #expect(mutation == .apply(
        updatedText: "☑ Done\n☐ ",
        selectedRange: NSRange(location: 9, length: 0)
    ))
}

@Test func noteEditorRulesExitEmptyCheckedCheckboxLine() {
    let mutation = NoteEditorRules.mutation(
        for: "☑ ",
        range: NSRange(location: 2, length: 0),
        replacementText: "\n"
    )

    #expect(mutation == .apply(
        updatedText: "",
        selectedRange: NSRange(location: 0, length: 0)
    ))
}

@MainActor
@Test func noteTextMapperExtractsCheckboxPlainText() {
    let attributed = makeAttributedCheckboxLine()
    let mapper = NoteTextMapper(attributedText: attributed)

    #expect(mapper.plainText == "☐ Task")
}

@MainActor
@Test func noteTextMapperTranslatesOffsetsAcrossCheckboxAttachment() {
    let attributed = makeAttributedCheckboxLine()
    let mapper = NoteTextMapper(attributedText: attributed)

    #expect(mapper.plainOffset(forAttributedOffset: 0) == 0)
    #expect(mapper.plainOffset(forAttributedOffset: 1) == 2)
    #expect(mapper.plainOffset(forAttributedOffset: 2) == 3)

    #expect(mapper.attributedOffset(forPlainOffset: 0) == 0)
    #expect(mapper.attributedOffset(forPlainOffset: 1) == 1)
    #expect(mapper.attributedOffset(forPlainOffset: 2) == 1)
    #expect(mapper.attributedOffset(forPlainOffset: 3) == 2)
}

@MainActor
@Test func noteTextMapperTranslatesRangesAcrossCheckboxAttachment() {
    let attributed = makeAttributedCheckboxLine()
    let mapper = NoteTextMapper(attributedText: attributed)

    #expect(mapper.plainRange(forAttributedRange: NSRange(location: 1, length: 2)) == NSRange(location: 2, length: 2))
    #expect(mapper.attributedRange(forPlainRange: NSRange(location: 0, length: 2)) == NSRange(location: 0, length: 1))
}


@MainActor
@Test func noteTextMapperExtractsCheckedCheckboxPlainText() {
    let attributed = makeAttributedCheckboxLine(checked: true, text: "Done")
    let mapper = NoteTextMapper(attributedText: attributed)

    #expect(mapper.plainText == "☑ Done")
}

@MainActor
@Test func noteTextMapperMapsEndOfDocumentAcrossMultipleCheckboxLines() {
    let attributed = makeAttributedCheckboxDocument()
    let mapper = NoteTextMapper(attributedText: attributed)
    let plainLength = (mapper.plainText as NSString).length

    #expect(mapper.plainText == "☐ Task\n☑ Done\n\nTail")
    #expect(mapper.plainOffset(forAttributedOffset: attributed.length) == plainLength)
    #expect(mapper.attributedOffset(forPlainOffset: plainLength) == attributed.length)
    #expect(mapper.plainRange(forAttributedRange: NSRange(location: attributed.length, length: 0)) == NSRange(location: plainLength, length: 0))
}

@MainActor
@Test func expandingTextViewGestureRejectsTapJustRightOfCheckboxIcon() {
    let harness = makeEditorHarness(text: "☐ Task")
    guard let hit = firstCheckboxHit(in: harness.textView, using: harness.coordinator) else {
        Issue.record("Expected to find checkbox icon hit region")
        return
    }

    let tap = FixedPointTapGestureRecognizer()
    harness.textView.addGestureRecognizer(tap)
    tap.name = "checkboxTap"
    tap.fixedPoint = CGPoint(x: hit.iconRect.maxX + 8, y: hit.iconRect.midY)

    #expect(!harness.coordinator.gestureRecognizerShouldBegin(tap))
}

@MainActor
@Test func expandingTextViewToggleCheckboxPreservesSavedPlainSelection() {
    var toggledText: String?
    let harness = makeEditorHarness(text: "☐ Task") { updatedText in
        toggledText = updatedText
    }
    let savedSelection = NSRange(location: 6, length: 0)

    ExpandingTextView.setSelectedPlainRange(savedSelection, in: harness.textView)
    harness.coordinator.pendingCheckboxTapSelection = savedSelection
    harness.coordinator.toggleCheckbox(at: 0, in: harness.textView)

    let mapper = NoteTextMapper(attributedText: harness.textView.attributedText)
    #expect(harness.state.text == "☑ Task")
    #expect(mapper.plainRange(forAttributedRange: harness.textView.selectedRange) == savedSelection)
    #expect(harness.state.cursorPosition == savedSelection.location)
    #expect(toggledText == "☑ Task")
}

@MainActor
@Test func expandingTextViewNudgesCursorOffCheckboxAttachment() {
    let harness = makeEditorHarness(text: "☐ Task")

    harness.textView.selectedRange = NSRange(location: 0, length: 0)
    harness.coordinator.nudgeCursorOffCheckbox(harness.textView)

    #expect(harness.textView.selectedRange == NSRange(location: 1, length: 0))
}

@MainActor
@Test func expandingTextViewNudgesCursorOffSpeakerLine() {
    let harness = makeEditorHarness(
        text: "Speaker 1\nHello",
        speakerColors: ["Speaker 1": .systemBlue]
    )

    ExpandingTextView.setSelectedPlainRange(NSRange(location: 3, length: 0), in: harness.textView)
    harness.coordinator.nudgeCursorOffSpeakerLine(harness.textView)

    let mapper = NoteTextMapper(attributedText: harness.textView.attributedText)
    #expect(mapper.plainRange(forAttributedRange: harness.textView.selectedRange) == NSRange(location: 10, length: 0))
}

@Test func rewriteToolbarStateInfersVisibleRewriteFromPersistedContent() {
    let rewrite = NoteRewrite(
        id: UUID(),
        noteId: UUID(),
        toneLabel: "Action Items",
        toneEmoji: "✅",
        content: "☐ First task",
        createdAt: .now
    )

    let state = RewriteToolbarState(
        isRewriting: false,
        activeRewriteId: nil,
        originalContent: "Original body",
        persistedContent: rewrite.content,
        rewrites: [rewrite],
        fallbackLabel: "Rewrite"
    )

    #expect(state.showsLabel)
    #expect(state.inferredVisibleRewrite == rewrite)
    #expect(state.effectiveSelectionId == rewrite.id)
    #expect(state.labelText == "✅ Action Items")
}

@Test func rewriteToolbarStateUsesGenericRewriteLabelUntilActiveRewriteLoads() {
    let state = RewriteToolbarState(
        isRewriting: false,
        activeRewriteId: UUID(),
        originalContent: "Original body",
        persistedContent: "Edited rewrite body",
        rewrites: [],
        fallbackLabel: nil
    )

    #expect(state.showsLabel)
    #expect(state.inferredVisibleRewrite == nil)
    #expect(state.labelText == "Rewrite")
}

@Test func rewriteToolbarStateFallsBackToOriginalForOriginalSelection() {
    let state = RewriteToolbarState(
        isRewriting: false,
        activeRewriteId: nil,
        originalContent: "Original body",
        persistedContent: "Original body",
        rewrites: [],
        fallbackLabel: nil
    )

    #expect(state.showsLabel)
    #expect(state.inferredVisibleRewrite == nil)
    #expect(state.effectiveSelectionId == nil)
    #expect(state.labelText == "Original")
}

@Test func rewriteToolbarStateHidesLabelForPlainNotes() {
    let state = RewriteToolbarState(
        isRewriting: false,
        activeRewriteId: nil,
        originalContent: nil,
        persistedContent: "Plain note",
        rewrites: [],
        fallbackLabel: nil
    )

    #expect(!state.showsLabel)
    #expect(state.labelText == "Original")
}

@Test func noteDetailEditorSessionTracksUnsavedChangesAgainstPersistedContent() {
    var session = NoteDetailEditorSession(title: "Title", content: "Body", bodyState: .content)

    #expect(!session.hasUnsavedChanges(persistedContent: "Body"))

    session.content = "Edited body"
    #expect(session.hasUnsavedChanges(persistedContent: "Edited body"))

    session.markCurrentStateAsSaved(persistedContent: "Edited body")
    #expect(!session.hasUnsavedChanges(persistedContent: "Edited body"))
}

@Test func noteDetailEditorSessionAcceptsStoreDrivenContentAndBodyState() {
    var session = NoteDetailEditorSession(title: "Title", content: "Body", bodyState: .content)

    session.acceptStoreDrivenContent(
        NoteBodyState.waitingForConnectionPlaceholder,
        bodyState: .waitingForConnection
    )

    #expect(session.content == NoteBodyState.waitingForConnectionPlaceholder)
    #expect(session.contentBaseline == NoteBodyState.waitingForConnectionPlaceholder)
    #expect(session.bodyState == .waitingForConnection)
}

@Test func noteDetailTitleInputLeavesPlainEditsInTitleField() {
    let transition = NoteDetailView.normalizedTitleInput("Updated title")

    #expect(transition.title == "Updated title")
    #expect(transition.moveFocusToBody == false)
}

@Test func noteDetailTitleInputReturnNormalizesTitleAndMovesFocusToBody() {
    let transition = NoteDetailView.normalizedTitleInput("Project title\n")

    #expect(transition.title == "Project title")
    #expect(transition.moveFocusToBody == true)
}

@Test func noteDetailEditorSessionResolvesVoiceFallbackStateWhenPlaceholderStripsToEmpty() {
    let inserted = NoteAppendPlaceholderEditor.insert(.transcribing, into: "", at: 0)

    let resolvedState = NoteDetailEditorSession.resolvedBodyState(
        for: inserted.content,
        source: .voice,
        fallbackBodyState: .transcribing,
        appendPlaceholder: inserted.placeholder
    )

    #expect(resolvedState == .transcribing)
}

@Test func transcriptSpeakerDetectorPrefersVisibleTranscriptLinesOverStaleMetadata() {
    let content = """
    Chaaaaaco
    Dice algo

    Claclacla
    Responde algo
    """

    let speakers = TranscriptSpeakerDetector.detectedSpeakers(
        in: content,
        speakerNames: ["0": "Old Speaker", "1": "Another Old Speaker"]
    )

    #expect(speakers == ["Chaaaaaco", "Claclacla"])
}

@Test func transcriptSpeakerDetectorFallsBackToMetadataWhenVisibleLinesAreAbsent() {
    let speakers = TranscriptSpeakerDetector.detectedSpeakers(
        in: "Regular note body",
        speakerNames: ["a": "First Speaker", "b": "Second Speaker"]
    )

    #expect(speakers == ["First Speaker", "Second Speaker"])
}

@Test func transcriptSpeakerDetectorDetectsGenericSpeakerLinesWithoutMetadata() {
    let content = """
    Speaker 1
    Hello there

    Speaker 2
    General Kenobi
    """

    #expect(TranscriptSpeakerDetector.detectedSpeakers(in: content, speakerNames: nil) == ["Speaker 1", "Speaker 2"])
}

@Test func expandingTextScrollMathMovesDownWhenCaretFallsBelowVisibleBottom() {
    let targetOffsetY = ExpandingTextScrollMath.targetOffsetY(
        currentOffsetY: 100,
        adjustedTopInset: 0,
        caretMinY: 410,
        caretMaxY: 430,
        visibleTop: 200,
        visibleBottom: 400
    )

    #expect(targetOffsetY == 150)
}

@Test func expandingTextScrollMathMovesUpWhenCaretFallsAboveVisibleTop() {
    let targetOffsetY = ExpandingTextScrollMath.targetOffsetY(
        currentOffsetY: 100,
        adjustedTopInset: 12,
        caretMinY: 180,
        caretMaxY: 198,
        visibleTop: 200,
        visibleBottom: 400
    )

    #expect(targetOffsetY == 68)
}

@Test func expandingTextScrollMathIgnoresVisibleCaret() {
    let targetOffsetY = ExpandingTextScrollMath.targetOffsetY(
        currentOffsetY: 100,
        adjustedTopInset: 0,
        caretMinY: 240,
        caretMaxY: 260,
        visibleTop: 200,
        visibleBottom: 400
    )

    #expect(targetOffsetY == nil)
}

@Test func expandingTextScrollMathRestoresOnlyAfterUpwardJump() {
    #expect(ExpandingTextScrollMath.restoredOffsetY(currentOffsetY: 40, savedOffsetY: 80) == 80)
    #expect(ExpandingTextScrollMath.restoredOffsetY(currentOffsetY: 70, savedOffsetY: 80) == nil)
}

@Test func expandingTextScrollMathFollowsDeletionCaretUpward() {
    let targetOffsetY = ExpandingTextScrollMath.deletionFollowOffsetY(
        currentOffsetY: 200,
        adjustedTopInset: 20,
        anchorCaretBottom: 500,
        currentCaretBottom: 470
    )

    #expect(targetOffsetY == 170)
}

actor NoteUpsertRecorder {
    private(set) var syncedNoteIds: [UUID] = []

    func record(_ noteId: UUID) {
        syncedNoteIds.append(noteId)
    }
}

actor HardDeleteRecorder {
    private(set) var deletedItems: [PendingHardDelete] = []

    func record(_ pendingDelete: PendingHardDelete) {
        deletedItems.append(pendingDelete)
    }
}

@Suite(.serialized)
struct NoteStoreDebounceTests {
@MainActor
@Test func noteStoreUpdateNoteDebouncesPerNoteSync() async {
    let recorder = NoteUpsertRecorder()
    let note = makeNote(content: "Original")
    let store = NoteStore(
        persistsLocalVoiceBodyStates: false,
        persistsPendingNoteUpserts: false,
        noteSyncDebounceDuration: .milliseconds(50),
        noteUpsertExecutor: { note in
            await recorder.record(note.id)
        }
    )
    store.notes = [note]

    var updated = note
    updated.content = "First edit"
    updated.updatedAt = .now
    store.updateNote(updated)

    updated.content = "Second edit"
    updated.updatedAt = .now.addingTimeInterval(1)
    store.updateNote(updated)

    for _ in 0..<20 {
        if store.pendingNoteUpserts.isEmpty, await recorder.syncedNoteIds == [note.id] {
            break
        }
        try? await Task.sleep(for: .milliseconds(25))
    }

    #expect(store.pendingNoteUpserts.isEmpty)
    #expect(await recorder.syncedNoteIds == [note.id])
}
}

@MainActor
@Test func noteStoreFlushPendingUpsertsUsesZeroRevisionFallback() async {
    let recorder = NoteUpsertRecorder()
    let note = makeNote(content: "Queued")
    let store = NoteStore(
        persistsLocalVoiceBodyStates: false,
        pendingNoteUpserts: [note.id: note],
        persistsPendingNoteUpserts: false,
        noteSyncDebounceDuration: .milliseconds(50),
        noteUpsertExecutor: { note in
            await recorder.record(note.id)
        }
    )

    await store.flushPendingNoteUpserts()

    #expect(store.pendingNoteUpserts.isEmpty)
    #expect(await recorder.syncedNoteIds == [note.id])
}

@MainActor
@Test func noteStoreBeginSessionReloadsPersistedPendingUpsertsForSameUser() {
    let userId = UUID()
    let pendingKey = "pendingNoteUpserts.\(userId.uuidString)"
    let note = makeNote(content: "Original")
    defer { UserDefaults.standard.removeObject(forKey: pendingKey) }

    let store = NoteStore(
        persistsLocalVoiceBodyStates: false,
        persistsPendingNoteUpserts: true,
        noteSyncDebounceDuration: .seconds(60),
        noteUpsertExecutor: { _ in }
    )
    store.beginSession(userId: userId)
    store.notes = [note]

    var updated = note
    updated.content = "Queued change"
    updated.updatedAt = .now.addingTimeInterval(1)
    store.updateNote(updated)
    store.resetSession()

    let reloaded = NoteStore(
        persistsLocalVoiceBodyStates: false,
        persistsPendingNoteUpserts: true,
        noteSyncDebounceDuration: .seconds(60),
        noteUpsertExecutor: { _ in }
    )
    reloaded.beginSession(userId: userId)

    #expect(reloaded.pendingNoteUpserts[updated.id]?.content == "Queued change")
    #expect(reloaded.notes.map(\.id) == [updated.id])
    #expect(reloaded.notes.first?.content == "Queued change")

    reloaded.resetSession()
}

@MainActor
@Test func noteStoreBeginSessionKeepsPendingUpsertsScopedToCurrentUser() {
    let firstUserId = UUID()
    let secondUserId = UUID()
    let firstKey = "pendingNoteUpserts.\(firstUserId.uuidString)"
    let secondKey = "pendingNoteUpserts.\(secondUserId.uuidString)"
    let note = makeNote(content: "User one")
    defer {
        UserDefaults.standard.removeObject(forKey: firstKey)
        UserDefaults.standard.removeObject(forKey: secondKey)
    }

    let store = NoteStore(
        persistsLocalVoiceBodyStates: false,
        persistsPendingNoteUpserts: true,
        noteSyncDebounceDuration: .seconds(60),
        noteUpsertExecutor: { _ in }
    )
    store.beginSession(userId: firstUserId)
    store.notes = [note]

    var updated = note
    updated.content = "Queued for first user"
    updated.updatedAt = .now.addingTimeInterval(1)
    store.updateNote(updated)
    store.resetSession()

    let otherSession = NoteStore(
        persistsLocalVoiceBodyStates: false,
        persistsPendingNoteUpserts: true,
        noteSyncDebounceDuration: .seconds(60),
        noteUpsertExecutor: { _ in }
    )
    otherSession.beginSession(userId: secondUserId)

    #expect(otherSession.pendingNoteUpserts.isEmpty)
    #expect(otherSession.notes.isEmpty)

    otherSession.resetSession()
}

@MainActor
@Test func noteStoreRemoveNoteQueuesSoftDeleteAsPendingUpsert() {
    let note = makeNote(content: "Delete me")
    let store = NoteStore(persistsLocalVoiceBodyStates: false, persistsPendingNoteUpserts: false)
    store.notes = [note]

    store.removeNote(id: note.id)

    #expect(store.notes.isEmpty)
    #expect(store.deletedNotes.map(\.id) == [note.id])
    #expect(store.pendingNoteUpserts[note.id]?.deletedAt != nil)
}

@MainActor
@Test func noteStoreRestoreNoteReplacesQueuedSoftDeleteWithActiveUpsert() {
    let note = makeNote(content: "Restore me")
    let store = NoteStore(persistsLocalVoiceBodyStates: false, persistsPendingNoteUpserts: false)
    store.notes = [note]

    store.removeNote(id: note.id)
    store.restoreNote(id: note.id)

    #expect(store.deletedNotes.isEmpty)
    #expect(store.notes.map(\.id) == [note.id])
    #expect(store.pendingNoteUpserts[note.id]?.deletedAt == nil)
}

@MainActor
@Test func noteStoreBeginSessionKeepsPendingSoftDeletesOutOfActiveNotes() {
    let userId = UUID()
    let key = "pendingNoteUpserts.\(userId.uuidString)"
    let note = makeNote(content: "Deleted")
    defer { UserDefaults.standard.removeObject(forKey: key) }

    let deleting = NoteStore(
        persistsLocalVoiceBodyStates: false,
        persistsPendingNoteUpserts: true,
        noteSyncDebounceDuration: .seconds(60),
        noteUpsertExecutor: { _ in }
    )
    deleting.beginSession(userId: userId)
    deleting.notes = [note]
    deleting.removeNote(id: note.id)
    deleting.resetSession()

    let reloaded = NoteStore(
        persistsLocalVoiceBodyStates: false,
        persistsPendingNoteUpserts: true,
        noteSyncDebounceDuration: .seconds(60),
        noteUpsertExecutor: { _ in }
    )
    reloaded.beginSession(userId: userId)

    #expect(reloaded.notes.isEmpty)
    #expect(reloaded.pendingNoteUpserts[note.id]?.deletedAt != nil)

    reloaded.resetSession()
}

@MainActor
@Test func noteStorePermanentlyDeleteQueuesHardDeleteAndClearsPendingUpsert() {
    let note = makeNote(
        content: "Trash me",
        source: .voice,
        audioUrl: "https://tftwvuduzzymqxdvkwwd.supabase.co/storage/v1/object/public/audio/folder/trash-me.m4a"
    )
    let store = NoteStore(persistsLocalVoiceBodyStates: false, persistsPendingNoteUpserts: false, persistsPendingHardDeletes: false)
    store.deletedNotes = [note]
    store.pendingNoteUpserts = [note.id: note]

    store.permanentlyDeleteNote(id: note.id)

    #expect(store.deletedNotes.isEmpty)
    #expect(store.pendingNoteUpserts[note.id] == nil)
    #expect(store.pendingHardDeletes[note.id]?.noteId == note.id)
    #expect(store.pendingHardDeletes[note.id]?.remoteAudioPath == "folder/trash-me.m4a")
}

@MainActor
@Test func noteStoreFlushPendingHardDeletesClearsQueueAfterSuccess() async {
    let recorder = HardDeleteRecorder()
    let noteId = UUID()
    let store = NoteStore(
        persistsLocalVoiceBodyStates: false,
        persistsPendingNoteUpserts: false,
        pendingHardDeletes: [noteId: PendingHardDelete(noteId: noteId, remoteAudioPath: "folder/audio.m4a")],
        persistsPendingHardDeletes: false,
        hardDeleteExecutor: { pendingDelete in
            await recorder.record(pendingDelete)
        }
    )

    await store.flushPendingHardDeletes()

    #expect(store.pendingHardDeletes.isEmpty)
    #expect(await recorder.deletedItems.map(\.noteId) == [noteId])
    #expect(await recorder.deletedItems.first?.remoteAudioPath == "folder/audio.m4a")
}

@MainActor
@Test func noteStoreBeginSessionReloadsPendingHardDeletesForSameUser() {
    let userId = UUID()
    let key = "pendingHardDeletes.\(userId.uuidString)"
    let note = makeNote(content: "Trash me")
    defer { UserDefaults.standard.removeObject(forKey: key) }

    let deleting = NoteStore(
        persistsLocalVoiceBodyStates: false,
        persistsPendingNoteUpserts: false,
        persistsPendingHardDeletes: true,
        hardDeleteExecutor: { _ in }
    )
    deleting.beginSession(userId: userId)
    deleting.deletedNotes = [note]
    deleting.permanentlyDeleteNote(id: note.id)
    deleting.resetSession()

    let reloaded = NoteStore(
        persistsLocalVoiceBodyStates: false,
        persistsPendingNoteUpserts: false,
        persistsPendingHardDeletes: true,
        hardDeleteExecutor: { _ in }
    )
    reloaded.beginSession(userId: userId)

    #expect(reloaded.pendingHardDeletes[note.id]?.noteId == note.id)

    reloaded.resetSession()
}

@MainActor
@Test func noteStoreBeginSessionKeepsPendingHardDeletesScopedToCurrentUser() {
    let firstUserId = UUID()
    let secondUserId = UUID()
    let firstKey = "pendingHardDeletes.\(firstUserId.uuidString)"
    let secondKey = "pendingHardDeletes.\(secondUserId.uuidString)"
    let note = makeNote(content: "Trash me")
    defer {
        UserDefaults.standard.removeObject(forKey: firstKey)
        UserDefaults.standard.removeObject(forKey: secondKey)
    }

    let deleting = NoteStore(
        persistsLocalVoiceBodyStates: false,
        persistsPendingNoteUpserts: false,
        persistsPendingHardDeletes: true,
        hardDeleteExecutor: { _ in }
    )
    deleting.beginSession(userId: firstUserId)
    deleting.deletedNotes = [note]
    deleting.permanentlyDeleteNote(id: note.id)
    deleting.resetSession()

    let otherSession = NoteStore(
        persistsLocalVoiceBodyStates: false,
        persistsPendingNoteUpserts: false,
        persistsPendingHardDeletes: true,
        hardDeleteExecutor: { _ in }
    )
    otherSession.beginSession(userId: secondUserId)

    #expect(otherSession.pendingHardDeletes.isEmpty)

    otherSession.resetSession()
}

@MainActor
@Test func noteStoreMoveNotesQueuesEachChangedNoteForSync() {
    let originalCategory = UUID()
    let targetCategory = UUID()
    let first = makeNote(content: "First")
    var second = makeNote(content: "Second")
    var third = makeNote(content: "Third")
    second.categoryId = originalCategory
    third.categoryId = originalCategory

    let store = NoteStore(persistsLocalVoiceBodyStates: false, persistsPendingNoteUpserts: false)
    store.notes = [first, second, third]

    store.moveNotes(ids: [second.id, third.id], toCategoryId: targetCategory)

    #expect(store.notes.first(where: { $0.id == first.id })?.categoryId == nil)
    #expect(store.notes.first(where: { $0.id == second.id })?.categoryId == targetCategory)
    #expect(store.notes.first(where: { $0.id == third.id })?.categoryId == targetCategory)
    #expect(Set(store.pendingNoteUpserts.keys) == Set([second.id, third.id]))
}

@Test func homeNoteQueryFiltersBySelectedCategoryAndSearchesResolvedContent() {
    let categoryId = UUID()
    let otherCategoryId = UUID()
    var matching = makeNote(content: "Original")
    matching.categoryId = categoryId
    matching.title = "Irrelevant"
    var otherInCategory = makeNote(content: "Nothing here")
    otherInCategory.categoryId = categoryId
    var otherCategory = makeNote(content: "needle")
    otherCategory.categoryId = otherCategoryId

    let filtered = HomeNoteQuery.filteredNotes(
        notes: [matching, otherInCategory, otherCategory],
        selectedCategory: categoryId,
        query: "needle",
        sortOrder: .updatedAt,
        resolvedContent: { note in note.id == matching.id ? "Hidden needle" : note.content }
    )

    #expect(filtered.map(\.id) == [matching.id])
}

@Test func homeNoteQueryMatchesTitleSearch() {
    var titled = makeNote(content: "Body")
    titled.title = "Project Apollo"
    let untitled = makeNote(content: "Project body")

    let filtered = HomeNoteQuery.filteredNotes(
        notes: [titled, untitled],
        selectedCategory: nil,
        query: "apollo",
        sortOrder: .updatedAt,
        resolvedContent: { $0.content }
    )

    #expect(filtered.map(\.id) == [titled.id])
}

@Test func homeNoteQuerySortsUncategorizedFirst() {
    let now = Date()
    let categoryId = UUID()
    var uncategorized = makeNote(content: "A", updatedAt: now)
    var categorized = makeNote(content: "B", updatedAt: now.addingTimeInterval(10))
    categorized.categoryId = categoryId
    uncategorized.title = "Uncategorized"

    let filtered = HomeNoteQuery.filteredNotes(
        notes: [categorized, uncategorized],
        selectedCategory: nil,
        query: "",
        sortOrder: .uncategorized,
        resolvedContent: { $0.content }
    )

    #expect(filtered.map(\.id) == [uncategorized.id, categorized.id])
}

@Test func homeNoteQuerySortsActionItemsFirstUsingResolvedContent() {
    let now = Date()
    let plain = makeNote(content: "Plain", updatedAt: now.addingTimeInterval(20))
    let actionable = makeNote(content: "Original", updatedAt: now)

    let filtered = HomeNoteQuery.filteredNotes(
        notes: [plain, actionable],
        selectedCategory: nil,
        query: "",
        sortOrder: .actionItems,
        resolvedContent: { note in note.id == actionable.id ? "☐ Task" : note.content }
    )

    #expect(filtered.map(\.id) == [actionable.id, plain.id])
}

@Test func homeNoteQueryUsesCreatedAtSortWhenRequested() {
    let older = makeNote(content: "Older", createdAt: .now.addingTimeInterval(-100), updatedAt: .now)
    let newer = makeNote(content: "Newer", createdAt: .now, updatedAt: .now.addingTimeInterval(-200))

    let filtered = HomeNoteQuery.filteredNotes(
        notes: [older, newer],
        selectedCategory: nil,
        query: "",
        sortOrder: .createdAt,
        resolvedContent: { $0.content }
    )

    #expect(filtered.map(\.id) == [newer.id, older.id])
}


@MainActor
@Test func noteStoreRemovingCategoryQueuesAffectedNotesForSync() {
    let categoryId = UUID()
    let category = Category(id: categoryId, name: "Work", color: "#FFAA00", sortOrder: 0, createdAt: .now)
    let unaffected = makeNote(content: "Unaffected")
    var affected = makeNote(content: "Affected")
    affected.categoryId = categoryId

    let store = NoteStore(persistsLocalVoiceBodyStates: false, persistsPendingNoteUpserts: false)
    store.categories = [category]
    store.notes = [affected, unaffected]

    store.removeCategory(id: categoryId)

    #expect(store.categories.isEmpty)
    #expect(store.notes.first(where: { $0.id == affected.id })?.categoryId == nil)
    #expect(store.notes.first(where: { $0.id == unaffected.id })?.categoryId == nil)
    #expect(Set(store.pendingNoteUpserts.keys) == Set([affected.id]))
}

@MainActor
private final class EditorStateBox {
    var text: String
    var isFocused = false
    var cursorPosition = 0
    var highlightRange: NSRange?
    var preserveScroll = false
    var moveCursorToEnd = false

    init(text: String) {
        self.text = text
    }
}

private final class FixedPointTapGestureRecognizer: UITapGestureRecognizer {
    var fixedPoint: CGPoint = .zero

    override func location(in view: UIView?) -> CGPoint {
        fixedPoint
    }
}

@MainActor
private func makeEditorHarness(
    text: String,
    speakerColors: [String: UIColor] = [:],
    onCheckboxToggle: ((String) -> Void)? = nil
) -> (state: EditorStateBox, coordinator: ExpandingTextView.Coordinator, textView: CheckboxTextView) {
    let state = EditorStateBox(text: text)
    let parent = ExpandingTextView(
        text: Binding(get: { state.text }, set: { state.text = $0 }),
        isFocused: Binding(get: { state.isFocused }, set: { state.isFocused = $0 }),
        cursorPosition: Binding(get: { state.cursorPosition }, set: { state.cursorPosition = $0 }),
        highlightRange: Binding(get: { state.highlightRange }, set: { state.highlightRange = $0 }),
        preserveScroll: Binding(get: { state.preserveScroll }, set: { state.preserveScroll = $0 }),
        isEditable: true,
        font: .preferredFont(forTextStyle: .body),
        lineSpacing: 6,
        placeholder: "",
        speakerColors: speakerColors,
        horizontalPadding: 0,
        moveCursorToEnd: Binding(get: { state.moveCursorToEnd }, set: { state.moveCursorToEnd = $0 }),
        onCheckboxToggle: onCheckboxToggle
    )

    let coordinator = parent.makeCoordinator()
    let textStorage = NSTextStorage()
    let layoutManager = NSLayoutManager()
    let textContainer = NSTextContainer(size: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude))
    textContainer.widthTracksTextView = true
    textContainer.heightTracksTextView = false
    layoutManager.addTextContainer(textContainer)
    textStorage.addLayoutManager(layoutManager)

    let textView = CheckboxTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 200), textContainer: textContainer)
    textView.isScrollEnabled = false
    textView.backgroundColor = UIColor.clear
    textView.textContainerInset = UIEdgeInsets.zero
    textView.textContainer.lineFragmentPadding = 0
    textView.delegate = coordinator
    textView.coordinator = coordinator
    coordinator.textView = textView
    parent.applyTextAttributes(textView)
    textView.layoutIfNeeded()
    textView.layoutManager.ensureLayout(for: textView.textContainer)

    return (state, coordinator, textView)
}

@MainActor
private func firstCheckboxHit(
    in textView: UITextView,
    using coordinator: ExpandingTextView.Coordinator
) -> (plainIndex: Int, iconRect: CGRect)? {
    for y in stride(from: 0 as CGFloat, through: 72, by: 1) {
        for x in stride(from: 0 as CGFloat, through: 72, by: 1) {
            if let hit = coordinator.checkboxHit(near: CGPoint(x: x, y: y), in: textView) {
                return hit
            }
        }
    }
    return nil
}

private func makeNote(
    id: UUID = UUID(),
    content: String,
    activeRewriteId: UUID? = nil,
    source: Note.NoteSource = .text,
    audioUrl: String? = nil,
    durationSeconds: Int? = nil,
    createdAt: Date = .now,
    updatedAt: Date = .now
) -> Note {
    Note(
        id: id,
        userId: nil,
        categoryId: nil,
        captureId: nil,
        title: nil,
        content: content,
        originalContent: nil,
        activeRewriteId: activeRewriteId,
        source: source,
        language: nil,
        audioUrl: audioUrl,
        durationSeconds: durationSeconds,
        speakerNames: nil,
        createdAt: createdAt,
        updatedAt: updatedAt,
        deletedAt: nil
    )
}

@MainActor
private func makeAttributedCheckboxLine(
    checked: Bool = false,
    text: String = "Task"
) -> NSAttributedString {
    let prefix = checked ? "☑ " : "☐ "
    let attributed = NSMutableAttributedString(string: prefix + text)
    let attachment = CheckboxAttachment(
        checked: checked,
        font: .preferredFont(forTextStyle: .body),
        color: checked ? .systemPurple : .secondaryLabel
    )
    attributed.replaceCharacters(in: NSRange(location: 0, length: 2), with: NSAttributedString(attachment: attachment))
    return attributed
}

@MainActor
private func makeAttributedCheckboxDocument() -> NSAttributedString {
    let attributed = NSMutableAttributedString(attributedString: makeAttributedCheckboxLine())
    attributed.append(NSAttributedString(string: "\n"))
    attributed.append(makeAttributedCheckboxLine(checked: true, text: "Done"))
    attributed.append(NSAttributedString(string: "\n\nTail"))
    return attributed
}

private func makeSineWaveFile(
    sampleRate: Double = 44_100,
    duration: Double = 0.35,
    frequency: Double = 440
) throws -> URL {
    let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("caf")
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let frameCount = AVAudioFrameCount(sampleRate * duration)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount

    let samples = buffer.floatChannelData![0]
    for frame in 0..<Int(frameCount) {
        let sampleTime = Double(frame) / sampleRate
        samples[frame] = Float(sin(2 * .pi * frequency * sampleTime) * 0.25)
    }

    let file = try AVAudioFile(
        forWriting: outputURL,
        settings: format.settings,
        commonFormat: .pcmFormatFloat32,
        interleaved: false
    )
    try file.write(from: buffer)

    return outputURL
}
