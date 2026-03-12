import Testing
@testable import Talkdraft
import UIKit

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
