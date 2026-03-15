import UIKit

extension ExpandingTextView.Coordinator {
        // MARK: - UITextViewDelegate

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard !isAnimatingAttributes else { return true }

            let mapper = ExpandingTextView.mapper(for: tv)
            let plainText = mapper.plainText
            let plainRange = mapper.plainRange(forAttributedRange: range)
            let mutation = NoteEditorRules.mutation(
                for: plainText,
                range: plainRange,
                replacementText: text,
                protectedLines: Set(parent.speakerColors.keys)
            )

            switch mutation {
            case .allowSystem:
                let updatedText = (plainText as NSString).replacingCharacters(in: plainRange, with: text)
                pendingSystemEdit = (
                    updatedText: updatedText,
                    selectedPlainRange: NSRange(location: plainRange.location + (text as NSString).length, length: 0)
                )
                pendingAnimatedNewlineDeletionFollow = false
                prepareCursorFollowForSystemEdit(
                    replacementText: text,
                    plainRange: plainRange,
                    plainText: plainText,
                    in: tv
                )
                captureDeletionAnchorIfNeeded(
                    replacementText: text,
                    plainRange: plainRange,
                    plainText: plainText,
                    in: tv
                )
                return true
            case .reject:
                pendingDeletionAnchorCaretBottom = nil
                pendingEndInsertionSavedOffset = nil
                suppressNextScrollOffsetRestore = false
                pendingAnimatedNewlineInsertionFollow = false
                pendingAnimatedNewlineDeletionFollow = false
                pendingSystemEdit = nil
                return false
            case let .apply(updatedText, selectedPlainRange):
                pendingDeletionAnchorCaretBottom = nil
                pendingEndInsertionSavedOffset = nil
                suppressNextScrollOffsetRestore = false
                pendingAnimatedNewlineInsertionFollow = false
                pendingAnimatedNewlineDeletionFollow = false
                pendingSystemEdit = nil
                applyPlainTextEdit(
                    updatedText: updatedText,
                    selectedPlainRange: selectedPlainRange,
                    in: tv,
                    ensureCursorVisible: text == "\n"
                )
                return false
            }
        }

        func applyPlainTextEdit(
            updatedText: String,
            selectedPlainRange: NSRange,
            in tv: UITextView,
            preserveScroll: Bool = false,
            ensureCursorVisible: Bool = false
        ) {
            preserveScrollOnNextUpdate = preserveScroll
            pendingSystemEdit = nil
            isAnimatingAttributes = true
            parent.text = updatedText
            parent.applyTextAttributes(tv)
            ExpandingTextView.setSelectedPlainRange(selectedPlainRange, in: tv)
            parent.cursorPosition = selectedPlainRange.location
            if let label = tv.viewWithTag(999) as? UILabel {
                label.isHidden = !updatedText.isEmpty
            }
            isAnimatingAttributes = false
            syncTypingAttributesToCurrentLine(tv)
            if ensureCursorVisible, tv.isFirstResponder {
                lastTextChangeSelection = tv.selectedRange
                scheduleScrollCursorVisible(
                    in: tv,
                    animated: false,
                    delay: 0.02,
                    animationDuration: 0.18,
                    animationOptions: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
                )
            }
        }

        func textViewDidChange(_ tv: UITextView) {
            guard !isAnimatingAttributes else { return }
            let savedOffset = enclosingScrollView(for: tv)?.contentOffset
            if let pendingSystemEdit {
                self.pendingSystemEdit = nil
                isAnimatingAttributes = true
                parent.text = pendingSystemEdit.updatedText
                parent.applyTextAttributes(tv)
                ExpandingTextView.setSelectedPlainRange(pendingSystemEdit.selectedPlainRange, in: tv)
                parent.cursorPosition = pendingSystemEdit.selectedPlainRange.location
                isAnimatingAttributes = false
            } else {
                let mapper = ExpandingTextView.mapper(for: tv)
                parent.text = mapper.plainText
                parent.cursorPosition = mapper.plainOffset(forAttributedOffset: tv.selectedRange.location)
            }
            if let label = tv.viewWithTag(999) as? UILabel {
                label.isHidden = !parent.text.isEmpty
            }
            // Sync typing attributes on text change so bullet/checkbox lines get the right
            // paragraph style for the *next* character. Moving this out of
            // textViewDidChangeSelection prevents iOS 26 from snapping the cursor to a
            // word boundary when typingAttributes is mutated during a selection change.
            syncTypingAttributesToCurrentLine(tv)
            lastTextChangeSelection = tv.selectedRange
            if let savedOffset, !suppressNextScrollOffsetRestore {
                scheduleScrollOffsetRestore(in: tv, savedOffset: savedOffset, delays: [0, 0.02])
            }
            suppressNextScrollOffsetRestore = false
            let animateInsertionFollow = pendingAnimatedNewlineInsertionFollow
            let animateDeletionFollow = pendingAnimatedNewlineDeletionFollow
            let savedEndInsertionOffset = pendingEndInsertionSavedOffset
            pendingAnimatedNewlineInsertionFollow = false
            pendingAnimatedNewlineDeletionFollow = false
            pendingEndInsertionSavedOffset = nil

            let scheduledDeletionFollow = scheduleTrailingDeletionFollowIfNeeded(
                in: tv,
                animationDuration: animateDeletionFollow ? 0.14 : nil,
                animationOptions: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
            )

            if !scheduledDeletionFollow {
                if animateInsertionFollow {
                    if let savedEndInsertionOffset {
                        scheduleScrollOffsetRestore(in: tv, savedOffset: savedEndInsertionOffset, delays: [0, 0.02, 0.05, 0.09])
                    }
                    scheduleScrollCursorVisible(
                        in: tv,
                        animated: false,
                        delay: savedEndInsertionOffset == nil ? 0.02 : 0.06,
                        animationDuration: 0.14,
                        animationOptions: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
                    )
                } else {
                    scheduleScrollCursorVisible(
                        in: tv,
                        animated: false,
                        delay: 0.02,
                        animationDuration: 0.12,
                        animationOptions: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
                    )
                }
            }
        }

        func syncTypingAttributesToCurrentLine(_ tv: UITextView) {
            let mapper = ExpandingTextView.mapper(for: tv)
            let nsText = mapper.plainText as NSString
            let baseStyle = NSMutableParagraphStyle()
            baseStyle.lineSpacing = parent.lineSpacing
            var attrs: [NSAttributedString.Key: Any] = [
                .font: parent.font,
                .foregroundColor: UIColor.label,
                .paragraphStyle: baseStyle,
            ]
            if nsText.length > 0 {
                let cursorLoc = mapper.plainOffset(forAttributedOffset: tv.selectedRange.location)
                let checkLoc = min(cursorLoc > 0 ? cursorLoc - 1 : 0, nsText.length - 1)
                let lineRange = nsText.lineRange(for: NSRange(location: checkLoc, length: 0))
                if lineRange.location < nsText.length {
                    let bulletIndent = ("• " as NSString).size(withAttributes: [.font: parent.font]).width
                    let bulletStyle = NSMutableParagraphStyle()
                    bulletStyle.lineSpacing = parent.lineSpacing
                    bulletStyle.firstLineHeadIndent = 0
                    bulletStyle.headIndent = bulletIndent
                    let checkboxStyle = ExpandingTextView.checkboxParagraphStyle(font: parent.font, lineSpacing: parent.lineSpacing)
                    let lineLength = max(0, lineRange.length - (lineRange.location + lineRange.length < nsText.length ? 1 : 0))
                    let lineText = nsText.substring(with: NSRange(location: lineRange.location, length: lineLength))
                    attrs = parent.typingAttributes(
                        forLineText: lineText,
                        baseAttributes: attrs,
                        bulletParaStyle: bulletStyle,
                        checkboxParaStyle: checkboxStyle
                    )
                }
            }
            tv.typingAttributes = attrs
        }

        func textViewDidBeginEditing(_ tv: UITextView) {
            parent.isFocused = true
            textView = tv
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            parent.isFocused = false
        }

}
