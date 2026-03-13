import UIKit

extension ExpandingTextView.Coordinator {
    // MARK: - Checkbox Tap Handling

    @objc func handleCheckboxTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              let tv = recognizer.view as? CheckboxTextView else { return }
        let point = recognizer.location(in: tv)
        guard let cbIdx = checkboxIndex(near: point, in: tv) else { return }
        toggleCheckbox(at: cbIdx, in: tv)
        // Reset suppression after all gesture recognizer actions on this run loop
        // cycle have fired (UITextView's simultaneous tap recognizer included).
        DispatchQueue.main.async { tv.suppressBecomeFirstResponder = false }
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Only begin for taps that land on a checkbox attachment. Returning false
        // immediately for all other taps lets UIKit process them normally (cursor
        // placement, focus) without any interference from our recognizer.
        guard let tv = gestureRecognizer.view as? CheckboxTextView else { return true }
        let point = gestureRecognizer.location(in: tv)
        let maxTapX: CGFloat = tv.textContainerInset.left + 44
        guard point.x <= maxTapX,
              checkboxIndex(near: point, in: tv) != nil else {
            pendingCheckboxTapSelection = nil
            return false
        }
        if tv.isFirstResponder {
            let mapper = NoteTextMapper(attributedText: tv.attributedText)
            pendingCheckboxTapSelection = mapper.plainRange(forAttributedRange: tv.selectedRange)
        } else {
            pendingCheckboxTapSelection = nil
        }
        // Suppress becomeFirstResponder for the duration of the gesture so UITextView's
        // built-in tap recognizer (which fires simultaneously) can't show the keyboard.
        // Only suppress if the view isn't already editing — if it is, keep the keyboard open.
        if !tv.isFirstResponder {
            tv.suppressBecomeFirstResponder = true
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        false
    }

    /// Toggles the checkbox at the given plain-text index. Called from handleCheckboxTap.
    func toggleCheckbox(at plainIndex: Int, in tv: CheckboxTextView) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let mapper = NoteTextMapper(attributedText: tv.attributedText)
        let savedSelection = pendingCheckboxTapSelection ?? mapper.plainRange(forAttributedRange: tv.selectedRange)
        pendingCheckboxTapSelection = nil
        guard let updatedText = NoteEditorRules.toggleCheckbox(in: parent.text, at: plainIndex) else { return }
        applyPlainTextEdit(
            updatedText: updatedText,
            selectedPlainRange: savedSelection,
            in: tv,
            preserveScroll: true
        )
        parent.onCheckboxToggle?(updatedText)
    }

    /// Returns the plain-text index of the checkbox character if the touch point is within
    /// the checkbox icon hit rect on a checkbox line, else nil.
    /// Uses NSLayoutManager exclusively — no UITextInput methods — so it is safe to call
    /// from touchesBegan without disturbing UITextInteraction's cursor placement state.
    func checkboxIndex(near point: CGPoint, in tv: UITextView) -> Int? {
        checkboxHit(near: point, in: tv)?.plainIndex
    }

    func checkboxHit(near point: CGPoint, in tv: UITextView) -> (plainIndex: Int, iconRect: CGRect)? {
        let lm = tv.layoutManager
        let tc = tv.textContainer
        lm.ensureLayout(for: tc)

        let layoutPoint = CGPoint(
            x: point.x - tv.textContainerInset.left,
            y: point.y - tv.textContainerInset.top
        )

        var fraction: CGFloat = 0
        let charIdx = lm.characterIndex(for: layoutPoint, in: tc, fractionOfDistanceBetweenInsertionPoints: &fraction)

        let mapper = NoteTextMapper(attributedText: tv.attributedText)
        let plainOffset = mapper.plainOffset(forAttributedOffset: charIdx)

        let nsText = parent.text as NSString
        guard nsText.length > 0 else { return nil }
        let safeOffset = min(max(plainOffset, 0), nsText.length - 1)
        let lineRange = nsText.lineRange(for: NSRange(location: safeOffset, length: 0))
        guard lineRange.length > 0 else { return nil }

        let firstChar = nsText.character(at: lineRange.location)
        guard firstChar == 0x2610 || firstChar == 0x2611 else { return nil }

        let attrCheckboxOffset = mapper.attributedOffset(forPlainOffset: lineRange.location)
        guard attrCheckboxOffset < (tv.attributedText?.length ?? 0) else { return nil }
        guard let attachment = tv.attributedText?.attribute(.attachment, at: attrCheckboxOffset, effectiveRange: nil) as? CheckboxAttachment else {
            return nil
        }

        let glyphRange = lm.glyphRange(forCharacterRange: NSRange(location: attrCheckboxOffset, length: 1), actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return nil }

        let glyphRect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
        let lineRect = lm.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: nil, withoutAdditionalLayout: true)
        let iconRect = CGRect(
            x: glyphRect.minX + tv.textContainerInset.left,
            y: lineRect.midY - (attachment.iconSize / 2) + tv.textContainerInset.top,
            width: attachment.iconSize,
            height: attachment.iconSize
        ).insetBy(dx: -CheckboxAttachment.hitSlop, dy: -CheckboxAttachment.hitSlop)

        guard iconRect.contains(point) else { return nil }
        return (plainIndex: lineRange.location, iconRect: iconRect)
    }

    /// Returns the speaker name if the touch point lands on a speaker name line, else nil.
    /// Uses NSLayoutManager — safe to call from touchesBegan.
    func speakerNameLine(at point: CGPoint, in tv: UITextView) -> String? {
        let lm = tv.layoutManager
        let tc = tv.textContainer
        let layoutPoint = CGPoint(
            x: point.x - tv.textContainerInset.left,
            y: point.y - tv.textContainerInset.top
        )
        var fraction: CGFloat = 0
        let charIdx = lm.characterIndex(for: layoutPoint, in: tc, fractionOfDistanceBetweenInsertionPoints: &fraction)

        let nsText = parent.text as NSString
        guard nsText.length > 0 else { return nil }
        let mapper = NoteTextMapper(attributedText: tv.attributedText)
        let plainOffset = mapper.plainOffset(forAttributedOffset: charIdx)
        let safeOffset = min(plainOffset, nsText.length - 1)
        let lineRange = nsText.lineRange(for: NSRange(location: safeOffset, length: 0))
        let trimLen = lineRange.location + lineRange.length < nsText.length ? lineRange.length - 1 : lineRange.length
        guard trimLen > 0 else { return nil }
        let line = nsText.substring(with: NSRange(location: lineRange.location, length: trimLen))
        return parent.speakerColors[line] != nil ? line : nil
    }

    // MARK: - Selection Handling

    func textViewDidChangeSelection(_ tv: UITextView) {
        guard !isAnimatingAttributes else { return }

        if parent.moveCursorToEnd.wrappedValue {
            parent.moveCursorToEnd.wrappedValue = false
        }

        nudgeCursorOffCheckbox(tv)
        if !parent.speakerColors.isEmpty {
            nudgeCursorOffSpeakerLine(tv)
        }

        let mapper = NoteTextMapper(attributedText: tv.attributedText)
        parent.cursorPosition = mapper.plainOffset(forAttributedOffset: tv.selectedRange.location)
        scheduleTypingAttributesSync(for: tv)
        guard tv.isFirstResponder else { return }
        if lastTextChangeSelection == tv.selectedRange {
            lastTextChangeSelection = nil
            return
        }
        lastTextChangeSelection = nil
        scheduleScrollCursorVisible(in: tv, animated: true, delay: 0.02)
    }

    func nudgeCursorOffCheckbox(_ tv: UITextView) {
        guard tv.selectedRange.length == 0,
              let attributed = tv.attributedText else { return }
        let cursor = tv.selectedRange.location
        guard cursor < attributed.length else { return }
        let attrs = attributed.attributes(at: cursor, effectiveRange: nil)
        guard attrs[.attachment] is CheckboxAttachment else { return }
        // Cursor is on the checkbox icon — move it past the attachment to the text
        isAnimatingAttributes = true
        tv.selectedRange = NSRange(location: cursor + 1, length: 0)
        isAnimatingAttributes = false
    }

    func nudgeCursorOffSpeakerLine(_ tv: UITextView) {
        let nsText = parent.text as NSString
        guard nsText.length > 0, tv.selectedRange.length == 0 else { return }
        let mapper = NoteTextMapper(attributedText: tv.attributedText)
        let cursor = mapper.plainOffset(forAttributedOffset: tv.selectedRange.location)
        let safeOffset = min(cursor, nsText.length - 1)
        let lineRange = nsText.lineRange(for: NSRange(location: safeOffset, length: 0))
        let trimLen = lineRange.location + lineRange.length < nsText.length ? lineRange.length - 1 : lineRange.length
        guard trimLen > 0 else { return }
        let line = nsText.substring(with: NSRange(location: lineRange.location, length: trimLen))
        guard parent.speakerColors[line] != nil else { return }
        // Move cursor to start of next line (after the \n), or before this line
        let nextStart = lineRange.location + lineRange.length
        let target = nextStart <= nsText.length ? nextStart : lineRange.location
        isAnimatingAttributes = true
        ExpandingTextView.setSelectedPlainRange(NSRange(location: target, length: 0), in: tv)
        isAnimatingAttributes = false
    }

    func scheduleTypingAttributesSync(for tv: UITextView) {
        pendingTypingAttributesSync?.cancel()
        let expectedSelection = tv.selectedRange
        let workItem = DispatchWorkItem { [weak self, weak tv] in
            guard let self, let tv, !self.isAnimatingAttributes else { return }
            guard tv.selectedRange == expectedSelection else { return }
            self.syncTypingAttributesToCurrentLine(tv)
        }
        pendingTypingAttributesSync = workItem
        DispatchQueue.main.async(execute: workItem)
    }
}
