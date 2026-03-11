import Testing
@testable import Talkdraft

@Test func appLaunches() async throws {
    #expect(true)
}

@Test func noteBodyStateRecognizesTranscriptionStates() {
    #expect(NoteBodyState(content: NoteBodyState.transcribingPlaceholder) == .transcribing)
    #expect(NoteBodyState(content: NoteBodyState.waitingForConnectionPlaceholder) == .waitingForConnection)
    #expect(NoteBodyState(content: NoteBodyState.transcriptionFailedPlaceholder) == .transcriptionFailed)
    #expect(NoteBodyState(content: "Plain note body") == .content)
}

@MainActor
@Test func noteStoreResolvedContentPrefersActiveRewrite() {
    let store = NoteStore()
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
    let store = NoteStore()
    let rewriteId = UUID()
    let note = makeNote(
        content: NoteBodyState.waitingForConnectionPlaceholder,
        activeRewriteId: rewriteId
    )

    #expect(store.resolvedContent(for: note) == NoteBodyState.waitingForConnectionPlaceholder)
    #expect(store.bodyState(for: note) == .waitingForConnection)
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

private func makeNote(
    id: UUID = UUID(),
    content: String,
    activeRewriteId: UUID? = nil
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
        source: .text,
        language: nil,
        audioUrl: nil,
        durationSeconds: nil,
        speakerNames: nil,
        createdAt: .now,
        updatedAt: .now,
        deletedAt: nil
    )
}
