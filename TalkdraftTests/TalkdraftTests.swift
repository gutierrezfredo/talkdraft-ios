import Testing
@testable import Talkdraft
import SwiftUI
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

@MainActor
@Test func expandingTextViewGestureRejectsTapJustRightOfCheckboxIcon() {
    let harness = makeEditorHarness(text: "☐ Task")
    guard let hit = firstCheckboxHit(in: harness.textView, using: harness.coordinator) else {
        Issue.record("Expected to find checkbox icon hit region")
        return
    }

    let tap = FixedPointTapGestureRecognizer()
    harness.textView.addGestureRecognizer(tap)
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
