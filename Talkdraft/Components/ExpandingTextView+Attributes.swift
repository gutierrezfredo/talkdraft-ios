import UIKit

extension ExpandingTextView {
    // MARK: - Extract plain text (attachments → ☐/☑)

    static func extractPlainText(from tv: UITextView) -> String {
        mapper(for: tv).plainText
    }

    static func setSelectedPlainRange(_ range: NSRange, in tv: UITextView) {
        tv.selectedRange = mapper(for: tv).attributedRange(forPlainRange: range)
    }

    static func mapper(for tv: UITextView) -> NoteTextMapper {
        (tv as? CheckboxTextView)?.noteTextMapper ?? NoteTextMapper(attributedText: tv.attributedText)
    }

    static func checkboxParagraphStyle(font: UIFont, lineSpacing: CGFloat) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing - 2
        style.paragraphSpacingBefore = 6
        style.firstLineHeadIndent = 0
        style.headIndent = CheckboxAttachment.iconSize(for: font) + CheckboxAttachment.trailingPadding
        return style
    }

    // MARK: - Apply styled attributes (☐/☑ → SF Symbol attachments)

    func applyTextAttributes(_ tv: UITextView) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.label,
            .paragraphStyle: style,
        ]

        guard !text.isEmpty else {
            tv.text = ""
            (tv as? CheckboxTextView)?.noteTextMapper = .empty
            tv.typingAttributes = baseAttributes
            return
        }

        let renderResult = NoteTextFormatting.renderEditorText(
            text: text,
            font: font,
            lineSpacing: lineSpacing,
            speakerColors: speakerColors,
            selectedSpeaker: selectedSpeaker,
            traitCollection: tv.traitCollection
        )

        tv.attributedText = renderResult.attributedText
        (tv as? CheckboxTextView)?.noteTextMapper = renderResult.mapper

        let bulletIndent = ("• " as NSString).size(withAttributes: [.font: font]).width
        let bulletParaStyle = NSMutableParagraphStyle()
        bulletParaStyle.lineSpacing = lineSpacing
        bulletParaStyle.firstLineHeadIndent = 0
        bulletParaStyle.headIndent = bulletIndent
        let checkboxParaStyle = Self.checkboxParagraphStyle(font: font, lineSpacing: lineSpacing)
        // Reset typingAttributes after setting attributedText — UIKit resets them to the
        // attributes at the cursor position, which for checkbox attachments lacks .foregroundColor.
        // Use cursor-aware attributes so bullet lines keep their headIndent while typing.
        tv.typingAttributes = typingAttributesForCurrentLine(
            in: tv,
            baseAttributes: baseAttributes,
            bulletParaStyle: bulletParaStyle,
            checkboxParaStyle: checkboxParaStyle
        )
    }

    /// Returns the correct typingAttributes for the line the cursor is currently on.
    func typingAttributesForCurrentLine(
        in tv: UITextView,
        baseAttributes: [NSAttributedString.Key: Any],
        bulletParaStyle: NSParagraphStyle,
        checkboxParaStyle: NSParagraphStyle
    ) -> [NSAttributedString.Key: Any] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return baseAttributes }
        let cursorLoc = Self.mapper(for: tv).plainOffset(forAttributedOffset: tv.selectedRange.location)
        let checkLoc = min(cursorLoc > 0 ? cursorLoc - 1 : 0, nsText.length - 1)
        let lineRange = nsText.lineRange(for: NSRange(location: checkLoc, length: 0))
        guard lineRange.location < nsText.length else { return baseAttributes }
        let lineLength = max(0, lineRange.length - (lineRange.location + lineRange.length < nsText.length ? 1 : 0))
        let lineText = nsText.substring(with: NSRange(location: lineRange.location, length: lineLength))
        return typingAttributes(
            forLineText: lineText,
            baseAttributes: baseAttributes,
            bulletParaStyle: bulletParaStyle,
            checkboxParaStyle: checkboxParaStyle
        )
    }

    func typingAttributes(
        forLineText lineText: String,
        baseAttributes: [NSAttributedString.Key: Any],
        bulletParaStyle: NSParagraphStyle,
        checkboxParaStyle: NSParagraphStyle
    ) -> [NSAttributedString.Key: Any] {
        var attrs = baseAttributes
        if lineText.hasPrefix(NoteEditorRules.bulletPrefix) {
            attrs[.paragraphStyle] = bulletParaStyle
            return attrs
        }
        if lineText.hasPrefix(NoteEditorRules.uncheckedPrefix) {
            attrs[.paragraphStyle] = checkboxParaStyle
            return attrs
        }
        if lineText.hasPrefix(NoteEditorRules.checkedPrefix) {
            attrs[.paragraphStyle] = checkboxParaStyle
            attrs[.foregroundColor] = UIColor.tertiaryLabel
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            return attrs
        }
        if lineText.hasPrefix("# ") {
            attrs[.font] = NoteTextFormatting.headingFont(from: font)
        }
        return attrs
    }

}
