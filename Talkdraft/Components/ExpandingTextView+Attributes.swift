import UIKit

extension ExpandingTextView {
    // MARK: - Extract plain text (attachments → ☐/☑)

    static func extractPlainText(from tv: UITextView) -> String {
        NoteTextMapper(attributedText: tv.attributedText).plainText
    }


    static func setSelectedPlainRange(_ range: NSRange, in tv: UITextView) {
        let mapper = NoteTextMapper(attributedText: tv.attributedText)
        tv.selectedRange = mapper.attributedRange(forPlainRange: range)
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

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.label,
            .paragraphStyle: style,
        ]

        guard !text.isEmpty else {
            tv.text = ""
            tv.typingAttributes = attributes
            return
        }

        let attributed = NSMutableAttributedString(string: text, attributes: attributes)
        let nsText = text as NSString

        // Style recording/transcribing placeholders
        let italicFont = UIFont.italicSystemFont(ofSize: font.pointSize)
        for placeholder in Self.styledPlaceholders {
            var searchRange = NSRange(location: 0, length: nsText.length)
            while searchRange.location < nsText.length {
                let range = nsText.range(of: placeholder, range: searchRange)
                guard range.location != NSNotFound else { break }
                attributed.addAttribute(.font, value: italicFont, range: range)
                attributed.addAttribute(.foregroundColor, value: Self.brandColor, range: range)
                searchRange.location = range.location + range.length
                searchRange.length = nsText.length - searchRange.location
            }
        }

        // Color speaker name lines (new format: standalone line per speaker)
        if !speakerColors.isEmpty {
            let boldFont = UIFont.systemFont(ofSize: font.pointSize, weight: .semibold)
            let speakerLines = nsText.components(separatedBy: .newlines)
            let linesWithOffsets = speakerLines.reduce(into: [(line: String, offset: Int)]()) { result, line in
                let offset = result.last.map { $0.offset + ($0.line as NSString).length + 1 } ?? 0
                result.append((line, offset))
            }
            for (line, offset) in linesWithOffsets {
                guard let color = speakerColors[line] else { continue }
                let range = NSRange(location: offset, length: (line as NSString).length)
                guard range.location + range.length <= attributed.length else { continue }
                attributed.addAttribute(.foregroundColor, value: color, range: range)
                attributed.addAttribute(.font, value: boldFont, range: range)
            }
            // Also handle legacy [Speaker N]: inline format
            for (key, color) in speakerColors {
                let label = "[\(key)]:"
                var searchRange = NSRange(location: 0, length: nsText.length)
                while searchRange.location < nsText.length {
                    let range = nsText.range(of: label, range: searchRange)
                    guard range.location != NSNotFound else { break }
                    attributed.addAttribute(.foregroundColor, value: color, range: range)
                    attributed.addAttribute(.font, value: boldFont, range: range)
                    searchRange.location = range.location + range.length
                    searchRange.length = nsText.length - searchRange.location
                }
            }
        }

        let resolvedBrandColor = Self.brandColor.resolvedColor(with: tv.traitCollection)
        let resolvedUncheckedCheckboxColor = Self.uncheckedCheckboxColor.resolvedColor(with: tv.traitCollection)

        // Replace ☐/☑ with SF Symbol attachments + style checked lines
        let lines = nsText.components(separatedBy: .newlines)
        var lineOffset = 0
        // Process in reverse so replacements don't shift later offsets
        var replacements: [(range: NSRange, attachment: CheckboxAttachment, lineTextRange: NSRange?)] = []
        for line in lines {
            let lineNS = line as NSString
            let lineLen = lineNS.length
            if lineLen > 0 {
                let firstScalar = lineNS.character(at: 0)
                let isUnchecked = firstScalar == 0x2610 // ☐
                let isChecked = firstScalar == 0x2611   // ☑
                if isUnchecked || isChecked {
                    let color: UIColor = isChecked ? resolvedBrandColor : resolvedUncheckedCheckboxColor
                    let attachment = CheckboxAttachment(checked: isChecked, font: font, color: color)
                    // Replace checkbox + space (2 chars) so no stray space precedes the text on line 1
                    let replaceLen = (lineLen > 1 && lineNS.character(at: 1) == 0x0020) ? 2 : 1
                    let charRange = NSRange(location: lineOffset, length: replaceLen)
                    let textRange: NSRange? = (isChecked && lineLen > 2)
                        ? NSRange(location: lineOffset + 2, length: lineLen - 2) : nil
                    replacements.append((charRange, attachment, textRange))
                }
            }
            lineOffset += lineLen + 1
        }

        // Apply strikethrough + dim for checked lines first (before offsets shift)
        for r in replacements {
            if r.attachment.isChecked, let textRange = r.lineTextRange {
                attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
                attributed.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: textRange)
            }
        }

        // Replace checkbox chars with attachments (reverse order to preserve offsets)
        let checkboxParaStyle = Self.checkboxParagraphStyle(font: font, lineSpacing: lineSpacing)
        for r in replacements.reversed() {
            let attachStr = NSMutableAttributedString(attachment: r.attachment)
            attachStr.addAttribute(.paragraphStyle, value: checkboxParaStyle, range: NSRange(location: 0, length: attachStr.length))
            attributed.replaceCharacters(in: r.range, with: attachStr)
        }

        // Apply hanging indent to bullet lines so wrapped text aligns under the text, not the bullet
        let bulletIndent = ("• " as NSString).size(withAttributes: [.font: font]).width
        let bulletParaStyle = NSMutableParagraphStyle()
        bulletParaStyle.lineSpacing = lineSpacing
        bulletParaStyle.firstLineHeadIndent = 0
        bulletParaStyle.headIndent = bulletIndent
        var bulletOffset = 0
        for line in lines {
            let lineNS = line as NSString
            let lineLen = lineNS.length
            if lineLen >= 2 && lineNS.character(at: 0) == 0x2022 && lineNS.character(at: 1) == 0x0020 { // • + space
                // Include the trailing \n so UIKit applies the paragraph style to the full paragraph
                let rangeLen = min(lineLen + 1, attributed.length - bulletOffset)
                if rangeLen > 0 {
                    attributed.addAttribute(.paragraphStyle, value: bulletParaStyle, range: NSRange(location: bulletOffset, length: rangeLen))
                }
            }
            bulletOffset += lineLen + 1
        }

        tv.attributedText = attributed
        // Reset typingAttributes after setting attributedText — UIKit resets them to the
        // attributes at the cursor position, which for checkbox attachments lacks .foregroundColor.
        // Use cursor-aware attributes so bullet lines keep their headIndent while typing.
        tv.typingAttributes = typingAttributesForCurrentLine(
            in: tv,
            baseAttributes: attributes,
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
        let cursorLoc = NoteTextMapper(attributedText: tv.attributedText).plainOffset(forAttributedOffset: tv.selectedRange.location)
        let checkLoc = min(cursorLoc > 0 ? cursorLoc - 1 : 0, nsText.length - 1)
        let lineRange = nsText.lineRange(for: NSRange(location: checkLoc, length: 0))
        guard lineRange.location < nsText.length else { return baseAttributes }
        let lineStart = nsText.character(at: lineRange.location)
        return typingAttributes(
            forLineStart: lineStart,
            baseAttributes: baseAttributes,
            bulletParaStyle: bulletParaStyle,
            checkboxParaStyle: checkboxParaStyle
        )
    }

    func typingAttributes(
        forLineStart lineStart: unichar,
        baseAttributes: [NSAttributedString.Key: Any],
        bulletParaStyle: NSParagraphStyle,
        checkboxParaStyle: NSParagraphStyle
    ) -> [NSAttributedString.Key: Any] {
        var attrs = baseAttributes
        if lineStart == 0x2022 {
            attrs[.paragraphStyle] = bulletParaStyle
            return attrs
        }
        if lineStart == 0x2610 {
            attrs[.paragraphStyle] = checkboxParaStyle
            return attrs
        }
        if lineStart == 0x2611 {
            attrs[.paragraphStyle] = checkboxParaStyle
            attrs[.foregroundColor] = UIColor.tertiaryLabel
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            return attrs
        }
        return attrs
    }

}
