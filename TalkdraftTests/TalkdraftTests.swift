import Testing
@testable import Talkdraft
import UIKit

@Test func appLaunches() async throws {
    #expect(true)
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
