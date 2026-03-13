import UIKit

// MARK: - Checkbox Attachment

final class CheckboxAttachment: NSTextAttachment {
    static let trailingPadding: CGFloat = 8
    static let hitSlop: CGFloat = 6

    static func iconSize(for font: UIFont) -> CGFloat {
        min(26, max(20, ceil(font.lineHeight - 2)))
    }

    static func attachmentHeight(for font: UIFont) -> CGFloat {
        ceil(font.lineHeight)
    }

    let isChecked: Bool
    let iconSize: CGFloat
    let attachmentHeight: CGFloat
    private let textFont: UIFont

    init(checked: Bool, font: UIFont, color: UIColor) {
        self.isChecked = checked
        self.textFont = font
        self.iconSize = Self.iconSize(for: font)
        self.attachmentHeight = Self.attachmentHeight(for: font)
        super.init(data: nil, ofType: nil)
        let paddedSize = CGSize(width: iconSize + Self.trailingPadding, height: attachmentHeight)
        let renderer = UIGraphicsImageRenderer(size: paddedSize)
        self.image = renderer.image { _ in
            let iconRect = CGRect(
                x: 0,
                y: floor((attachmentHeight - iconSize) / 2),
                width: iconSize,
                height: iconSize
            )
            let symbolName = checked ? "checkmark.circle.fill" : "circle"
            let config = UIImage.SymbolConfiguration(pointSize: iconSize, weight: checked ? .medium : .light)
            let symbol = UIImage(systemName: symbolName, withConfiguration: config)?
                .withTintColor(color, renderingMode: .alwaysOriginal)
            symbol?.draw(in: iconRect)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: CGRect, glyphPosition position: CGPoint, characterIndex charIndex: Int) -> CGRect {
        guard image != nil else { return .zero }
        let yOffset = floor((textFont.capHeight - attachmentHeight) / 2)
        return CGRect(x: 0, y: yOffset, width: iconSize + Self.trailingPadding, height: attachmentHeight)
    }
}

// MARK: - CheckboxTextView

/// UITextView subclass for the note body. Handles checkbox tap detection and toggling.
final class CheckboxTextView: UITextView {
    weak var coordinator: ExpandingTextView.Coordinator?
    /// Set to true during a checkbox tap to prevent UITextView's tap recognizer from
    /// making this view first responder (which would show the keyboard).
    var suppressBecomeFirstResponder = false

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configureTraitObservation()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureTraitObservation()
    }

    override func becomeFirstResponder() -> Bool {
        guard !suppressBecomeFirstResponder else { return false }
        return super.becomeFirstResponder()
    }

    private func configureTraitObservation() {
        updateKeyboardAppearance()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.updateKeyboardAppearance()
        }
    }

    private func updateKeyboardAppearance() {
        keyboardAppearance = traitCollection.userInterfaceStyle == .dark ? .dark : .light
        if isFirstResponder { reloadInputViews() }
    }
}

enum NoteEditorMutation: Equatable {
    case allowSystem
    case reject
    case apply(updatedText: String, selectedRange: NSRange)
}

struct NoteEditorRules {
    static let uncheckedPrefix = "☐ "
    static let checkedPrefix = "☑ "
    static let bulletPrefix = "• "

    static func toggleCheckbox(in text: String, at plainIndex: Int) -> String? {
        let nsText = text as NSString
        guard plainIndex < nsText.length else { return nil }
        let currentChar = nsText.character(at: plainIndex)
        guard currentChar == 0x2610 || currentChar == 0x2611 else { return nil }
        let replacement = currentChar == 0x2611 ? "☐" : "☑"
        return nsText.replacingCharacters(in: NSRange(location: plainIndex, length: 1), with: replacement)
    }

    static func mutation(
        for text: String,
        range: NSRange,
        replacementText: String,
        protectedLines: Set<String> = []
    ) -> NoteEditorMutation {
        let nsText = text as NSString

        if !replacementText.isEmpty, nsText.length > 0 {
            let lineRange = currentLineRange(in: nsText, at: range.location)
            if lineRange.location < nsText.length, lineRange.length > 0 {
                let firstChar = nsText.character(at: lineRange.location)
                if (firstChar == 0x2610 || firstChar == 0x2611) && range.location <= lineRange.location + 1 {
                    return .reject
                }
            }
        }

        if !protectedLines.isEmpty, nsText.length > 0 {
            let lineRange = currentLineRange(in: nsText, at: range.location)
            let currentLine = trimmedLine(in: nsText, lineRange: lineRange)
            if protectedLines.contains(currentLine) {
                return .reject
            }
        }

        if replacementText == "]", range.location > 0, range.location <= nsText.length {
            let prevIdx = range.location - 1
            if prevIdx < nsText.length, nsText.character(at: prevIdx) == UInt16(Character("[").asciiValue!) {
                let updatedText = nsText.replacingCharacters(in: NSRange(location: prevIdx, length: 1), with: uncheckedPrefix)
                return .apply(
                    updatedText: updatedText,
                    selectedRange: NSRange(location: prevIdx + (uncheckedPrefix as NSString).length, length: 0)
                )
            }
        }

        if replacementText == " ", range.location <= nsText.length, nsText.length > 0 {
            let lineStart = currentLineRange(in: nsText, at: range.location).location
            if range.location > lineStart {
                let typed = nsText.substring(with: NSRange(location: lineStart, length: range.location - lineStart))
                if typed == "-" {
                    let updatedText = nsText.replacingCharacters(
                        in: NSRange(location: lineStart, length: range.location - lineStart),
                        with: bulletPrefix
                    )
                    return .apply(
                        updatedText: updatedText,
                        selectedRange: NSRange(location: lineStart + (bulletPrefix as NSString).length, length: 0)
                    )
                }
            }
        }

        guard replacementText == "\n", nsText.length > 0, range.location <= nsText.length else {
            return .allowSystem
        }

        let lineRange = currentLineRange(in: nsText, at: range.location)
        let currentLine = nsText.substring(with: lineRange).trimmingCharacters(in: .newlines)

        if currentLine.hasPrefix(uncheckedPrefix) || currentLine.hasPrefix(checkedPrefix) {
            let trimmed = currentLine.trimmingCharacters(in: .whitespaces)
            if trimmed == "☐" || trimmed == "☑" {
                let updatedText = nsText.replacingCharacters(
                    in: NSRange(location: lineRange.location, length: (uncheckedPrefix as NSString).length),
                    with: ""
                )
                return .apply(
                    updatedText: updatedText,
                    selectedRange: NSRange(location: lineRange.location, length: 0)
                )
            }

            let insertedText = "\n" + uncheckedPrefix
            let updatedText = nsText.replacingCharacters(in: range, with: insertedText)
            return .apply(
                updatedText: updatedText,
                selectedRange: NSRange(location: range.location + (insertedText as NSString).length, length: 0)
            )
        }

        guard currentLine.hasPrefix(bulletPrefix) else { return .allowSystem }

        if currentLine == bulletPrefix.trimmingCharacters(in: .whitespaces) || currentLine == bulletPrefix {
            let updatedText = nsText.replacingCharacters(
                in: NSRange(location: lineRange.location, length: (bulletPrefix as NSString).length),
                with: ""
            )
            return .apply(
                updatedText: updatedText,
                selectedRange: NSRange(location: lineRange.location, length: 0)
            )
        }

        let insertedText = "\n" + bulletPrefix
        let updatedText = nsText.replacingCharacters(in: range, with: insertedText)
        return .apply(
            updatedText: updatedText,
            selectedRange: NSRange(location: range.location + (insertedText as NSString).length, length: 0)
        )
    }

    private static func trimmedLine(in text: NSString, lineRange: NSRange) -> String {
        text.substring(with: NSRange(
            location: lineRange.location,
            length: max(0, lineRange.length - (text.length > lineRange.location + lineRange.length ? 1 : 0))
        ))
    }

    private static func currentLineRange(in text: NSString, at location: Int) -> NSRange {
        let boundedLocation = min(max(0, location), text.length)
        var start = boundedLocation
        while start > 0, text.character(at: start - 1) != 0x0A {
            start -= 1
        }

        var end = boundedLocation
        while end < text.length, text.character(at: end) != 0x0A {
            end += 1
        }
        if end < text.length, text.character(at: end) == 0x0A {
            end += 1
        }

        return NSRange(location: start, length: end - start)
    }
}

struct NoteTextMapper {
    private struct Segment {
        let attributedRange: NSRange
        let plainRange: NSRange
        let isCheckboxAttachment: Bool
    }

    let plainText: String

    private let attributedLength: Int
    private let segments: [Segment]

    init(attributedText: NSAttributedString?) {
        guard let attributedText, attributedText.length > 0 else {
            self.plainText = ""
            self.attributedLength = 0
            self.segments = []
            return
        }

        let fullRange = NSRange(location: 0, length: attributedText.length)
        let nsString = attributedText.string as NSString
        var plainText = ""
        var plainLocation = 0
        var segments: [Segment] = []

        attributedText.enumerateAttributes(in: fullRange) { attrs, range, _ in
            let plainFragment: String
            let isCheckboxAttachment: Bool

            if let attachment = attrs[.attachment] as? CheckboxAttachment {
                plainFragment = attachment.isChecked ? NoteEditorRules.checkedPrefix : NoteEditorRules.uncheckedPrefix
                isCheckboxAttachment = true
            } else {
                plainFragment = nsString.substring(with: range)
                isCheckboxAttachment = false
            }

            let plainLength = (plainFragment as NSString).length
            segments.append(
                Segment(
                    attributedRange: range,
                    plainRange: NSRange(location: plainLocation, length: plainLength),
                    isCheckboxAttachment: isCheckboxAttachment
                )
            )
            plainText += plainFragment
            plainLocation += plainLength
        }

        self.plainText = plainText
        self.attributedLength = attributedText.length
        self.segments = segments
    }

    func plainOffset(forAttributedOffset attributedOffset: Int) -> Int {
        let boundedOffset = min(max(0, attributedOffset), attributedLength)
        guard boundedOffset > 0 else { return 0 }

        for segment in segments {
            let segmentStart = segment.attributedRange.location
            let segmentEnd = segmentStart + segment.attributedRange.length

            if boundedOffset >= segmentEnd {
                continue
            }

            if boundedOffset <= segmentStart {
                return segment.plainRange.location
            }

            if segment.isCheckboxAttachment {
                return segment.plainRange.location + segment.plainRange.length
            }

            let delta = boundedOffset - segmentStart
            return segment.plainRange.location + min(segment.plainRange.length, delta)
        }

        return segments.last.map { $0.plainRange.location + $0.plainRange.length } ?? 0
    }

    func plainRange(forAttributedRange range: NSRange) -> NSRange {
        let start = plainOffset(forAttributedOffset: range.location)
        let end = plainOffset(forAttributedOffset: range.location + range.length)
        return NSRange(location: start, length: max(0, end - start))
    }

    func attributedOffset(forPlainOffset plainOffset: Int) -> Int {
        let target = max(0, plainOffset)
        guard attributedLength > 0, target > 0 else { return 0 }

        for segment in segments {
            let segmentStart = segment.plainRange.location
            let segmentEnd = segmentStart + segment.plainRange.length

            guard target <= segmentEnd else { continue }

            if target <= segmentStart {
                return segment.attributedRange.location
            }

            if segment.isCheckboxAttachment {
                return segment.attributedRange.location + segment.attributedRange.length
            }

            let delta = target - segmentStart
            return segment.attributedRange.location + min(segment.attributedRange.length, delta)
        }

        return attributedLength
    }

    func attributedRange(forPlainRange range: NSRange) -> NSRange {
        let start = attributedOffset(forPlainOffset: range.location)
        let end = attributedOffset(forPlainOffset: range.location + range.length)
        return NSRange(location: start, length: max(0, end - start))
    }
}
