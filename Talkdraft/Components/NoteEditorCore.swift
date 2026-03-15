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
    var noteTextMapper = NoteTextMapper.empty
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

        if replacementText.isEmpty, nsText.length > 0 {
            let lineRange = currentLineRange(in: nsText, at: range.location)
            if lineRange.location < nsText.length, lineRange.length > 0 {
                let firstChar = nsText.character(at: lineRange.location)
                let checkboxPrefixRange = NSRange(location: lineRange.location, length: min(2, lineRange.length))
                let lineTextLength = max(0, lineRange.length - checkboxPrefixRange.length)
                if (firstChar == 0x2610 || firstChar == 0x2611),
                   lineTextLength > 0,
                   NSIntersectionRange(range, checkboxPrefixRange).length > 0 {
                    let updatedText = nsText.replacingCharacters(in: checkboxPrefixRange, with: "")
                    return .apply(
                        updatedText: updatedText,
                        selectedRange: NSRange(location: lineRange.location, length: 0)
                    )
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
            let lineRange = currentLineRange(in: nsText, at: range.location)
            let leadingText = nsText.substring(with: NSRange(location: lineRange.location, length: max(0, prevIdx - lineRange.location)))
            let isChecklistShortcutPosition = leadingText.trimmingCharacters(in: .whitespaces).isEmpty
            if prevIdx < nsText.length,
               nsText.character(at: prevIdx) == UInt16(Character("[").asciiValue!),
               isChecklistShortcutPosition {
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
    struct Segment {
        let attributedRange: NSRange
        let plainRange: NSRange
        let hiddenPrefixLength: Int
        let hiddenSuffixLength: Int
        let isCheckboxAttachment: Bool

        var visiblePlainStart: Int {
            plainRange.location + hiddenPrefixLength
        }

        var visiblePlainLength: Int {
            max(0, plainRange.length - hiddenPrefixLength - hiddenSuffixLength)
        }

        var visiblePlainEnd: Int {
            visiblePlainStart + visiblePlainLength
        }
    }

    private enum BoundaryKind {
        case cursor
        case selectionStart
        case selectionEnd
    }

    static let empty = NoteTextMapper(plainText: "", attributedLength: 0, segments: [])

    let plainText: String

    private let attributedLength: Int
    private let segments: [Segment]

    init(plainText: String, attributedLength: Int, segments: [Segment]) {
        self.plainText = plainText
        self.attributedLength = attributedLength
        self.segments = segments
    }

    init(attributedText: NSAttributedString?) {
        guard let attributedText, attributedText.length > 0 else {
            self = .empty
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
                    hiddenPrefixLength: 0,
                    hiddenSuffixLength: 0,
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
        plainOffset(forAttributedOffset: attributedOffset, kind: .cursor)
    }

    private func plainOffset(forAttributedOffset attributedOffset: Int, kind: BoundaryKind) -> Int {
        let boundedOffset = min(max(0, attributedOffset), attributedLength)
        guard boundedOffset > 0 else { return 0 }

        for segment in segments {
            let segmentStart = segment.attributedRange.location
            let segmentEnd = segmentStart + segment.attributedRange.length

            if boundedOffset > segmentEnd {
                continue
            }

            if boundedOffset < segmentStart {
                return segment.plainRange.location
            }

            if segment.isCheckboxAttachment {
                return segment.plainRange.location + segment.plainRange.length
            }

            if boundedOffset == segmentStart {
                switch kind {
                case .cursor:
                    return segment.visiblePlainStart
                case .selectionStart, .selectionEnd:
                    return segment.plainRange.location
                }
            }

            if boundedOffset == segmentEnd {
                return segment.plainRange.location + segment.plainRange.length
            }

            let delta = boundedOffset - segmentStart
            return segment.visiblePlainStart + min(segment.visiblePlainLength, delta)
        }

        return segments.last.map { $0.plainRange.location + $0.plainRange.length } ?? 0
    }

    func plainRange(forAttributedRange range: NSRange) -> NSRange {
        let start = plainOffset(forAttributedOffset: range.location, kind: .selectionStart)
        let end = plainOffset(forAttributedOffset: range.location + range.length, kind: .selectionEnd)
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

            if target <= segment.visiblePlainStart {
                return segment.attributedRange.location
            }

            if target >= segment.plainRange.location + segment.plainRange.length || target >= segment.visiblePlainEnd {
                return segment.attributedRange.location + segment.attributedRange.length
            }

            let delta = target - segment.visiblePlainStart
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

enum NoteTextFormatting {
    struct EditorRenderResult {
        let attributedText: NSAttributedString
        let mapper: NoteTextMapper
    }

    private struct LineInstruction {
        let plainRange: NSRange
        let kind: ParagraphKind
    }

    private enum ParagraphKind {
        case bullet
        case checkbox(checkedTextRange: NSRange?)
    }

    static func plainDisplayText(for text: String) -> String {
        let nsText = text as NSString
        guard nsText.length > 0 else { return text }

        var result: [String] = []
        var lineLocation = 0

        while lineLocation < nsText.length {
            let fullLineRange = nsText.lineRange(for: NSRange(location: lineLocation, length: 0))
            let hasNewline = lineHasTrailingNewline(in: nsText, fullLineRange: fullLineRange)
            let contentLength = hasNewline ? fullLineRange.length - 1 : fullLineRange.length
            let contentRange = NSRange(location: fullLineRange.location, length: max(0, contentLength))
            let rawLine = nsText.substring(with: contentRange)
            result.append(displayText(forLine: rawLine))
            if hasNewline {
                result.append("\n")
            }
            lineLocation = fullLineRange.location + fullLineRange.length
        }

        return result.joined()
    }

    @MainActor
    static func renderEditorText(
        text: String,
        font: UIFont,
        lineSpacing: CGFloat,
        speakerColors: [String: UIColor],
        traitCollection: UITraitCollection
    ) -> EditorRenderResult {
        let baseParagraphStyle = NSMutableParagraphStyle()
        baseParagraphStyle.lineSpacing = lineSpacing

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.label,
            .paragraphStyle: baseParagraphStyle,
        ]

        guard !text.isEmpty else {
            return EditorRenderResult(
                attributedText: NSAttributedString(string: ""),
                mapper: .empty
            )
        }

        let nsText = text as NSString
        let attributed = NSMutableAttributedString()
        var segments: [NoteTextMapper.Segment] = []
        var lineInstructions: [LineInstruction] = []
        let headingFont = headingFont(from: font)
        let headingBoldFont = boldFont(from: headingFont)
        let bodyBoldFont = boldFont(from: font)
        let resolvedBrandColor = ExpandingTextView.brandColor.resolvedColor(with: traitCollection)
        let resolvedUncheckedCheckboxColor = ExpandingTextView.uncheckedCheckboxColor.resolvedColor(with: traitCollection)

        var lineLocation = 0
        while lineLocation < nsText.length {
            let fullLineRange = nsText.lineRange(for: NSRange(location: lineLocation, length: 0))
            let hasNewline = lineHasTrailingNewline(in: nsText, fullLineRange: fullLineRange)
            let contentLength = hasNewline ? fullLineRange.length - 1 : fullLineRange.length
            let contentRange = NSRange(location: fullLineRange.location, length: max(0, contentLength))
            let rawLine = nsText.substring(with: contentRange)

            if let speakerColor = speakerColors[rawLine] {
                appendVisibleText(
                    rawLine,
                    plainLocation: contentRange.location,
                    hiddenPrefixLength: 0,
                    hiddenSuffixLength: 0,
                    attributes: [
                        .font: UIFont.systemFont(ofSize: font.pointSize, weight: .semibold),
                        .foregroundColor: speakerColor,
                        .paragraphStyle: baseParagraphStyle,
                    ],
                    attributed: attributed,
                    segments: &segments
                )
            } else if let isChecked = checkboxState(for: rawLine) {
                let prefixLength = checkboxPrefixLength(in: rawLine)
                let attachment = CheckboxAttachment(
                    checked: isChecked,
                    font: font,
                    color: isChecked ? resolvedBrandColor : resolvedUncheckedCheckboxColor
                )
                appendCheckboxAttachment(
                    attachment,
                    plainLocation: contentRange.location,
                    plainLength: prefixLength,
                    attributed: attributed,
                    segments: &segments
                )
                let remainingText = (rawLine as NSString).substring(from: prefixLength)
                appendInlineText(
                    remainingText,
                    rawContentStart: contentRange.location + prefixLength,
                    leadingHiddenPrefixLength: 0,
                    normalAttributes: isChecked
                        ? checkedTextAttributes(from: baseAttributes)
                        : baseAttributes,
                    boldAttributes: isChecked
                        ? checkedTextAttributes(from: baseAttributes, font: bodyBoldFont)
                        : [
                            .font: bodyBoldFont,
                            .foregroundColor: UIColor.label,
                            .paragraphStyle: baseParagraphStyle,
                        ],
                    attributed: attributed,
                    segments: &segments
                )
                let checkedTextRange: NSRange? = isChecked && remainingText.isEmpty == false
                    ? NSRange(location: contentRange.location + prefixLength, length: (remainingText as NSString).length)
                    : nil
                lineInstructions.append(
                    LineInstruction(
                        plainRange: fullLineRange,
                        kind: .checkbox(checkedTextRange: checkedTextRange)
                    )
                )
            } else if rawLine.hasPrefix(NoteEditorRules.bulletPrefix) {
                appendVisibleText(
                    NoteEditorRules.bulletPrefix,
                    plainLocation: contentRange.location,
                    hiddenPrefixLength: 0,
                    hiddenSuffixLength: 0,
                    attributes: baseAttributes,
                    attributed: attributed,
                    segments: &segments
                )
                let remainingText = (rawLine as NSString).substring(from: (NoteEditorRules.bulletPrefix as NSString).length)
                appendInlineText(
                    remainingText,
                    rawContentStart: contentRange.location + (NoteEditorRules.bulletPrefix as NSString).length,
                    leadingHiddenPrefixLength: 0,
                    normalAttributes: baseAttributes,
                    boldAttributes: [
                        .font: bodyBoldFont,
                        .foregroundColor: UIColor.label,
                        .paragraphStyle: baseParagraphStyle,
                    ],
                    attributed: attributed,
                    segments: &segments
                )
                lineInstructions.append(LineInstruction(plainRange: fullLineRange, kind: .bullet))
            } else {
                let headingPrefix = "# "
                let headingPrefixLength = (headingPrefix as NSString).length
                let headingContent = rawLine.hasPrefix(headingPrefix)
                    ? (rawLine as NSString).substring(from: headingPrefixLength)
                    : ""
                let shouldRenderHeading = rawLine.hasPrefix(headingPrefix)
                    && !headingContent.trimmingCharacters(in: .whitespaces).isEmpty

                appendInlineText(
                    shouldRenderHeading ? headingContent : rawLine,
                    rawContentStart: shouldRenderHeading
                        ? contentRange.location + headingPrefixLength
                        : contentRange.location,
                    leadingHiddenPrefixLength: shouldRenderHeading ? headingPrefixLength : 0,
                    normalAttributes: [
                        .font: shouldRenderHeading ? headingFont : font,
                        .foregroundColor: UIColor.label,
                        .paragraphStyle: baseParagraphStyle,
                    ],
                    boldAttributes: [
                        .font: shouldRenderHeading ? headingBoldFont : bodyBoldFont,
                        .foregroundColor: UIColor.label,
                        .paragraphStyle: baseParagraphStyle,
                    ],
                    attributed: attributed,
                    segments: &segments
                )
            }

            if hasNewline {
                appendVisibleText(
                    "\n",
                    plainLocation: fullLineRange.location + fullLineRange.length - 1,
                    hiddenPrefixLength: 0,
                    hiddenSuffixLength: 0,
                    attributes: baseAttributes,
                    attributed: attributed,
                    segments: &segments
                )
            }

            lineLocation = fullLineRange.location + fullLineRange.length
        }

        let mapper = NoteTextMapper(
            plainText: text,
            attributedLength: attributed.length,
            segments: segments
        )

        applyPlaceholderStyling(to: attributed, font: font)
        applyLegacySpeakerStyling(to: attributed, speakerColors: speakerColors, font: font)
        applyParagraphStyles(
            to: attributed,
            mapper: mapper,
            lineInstructions: lineInstructions,
            font: font,
            lineSpacing: lineSpacing
        )

        return EditorRenderResult(attributedText: attributed, mapper: mapper)
    }

    private static func appendInlineText(
        _ text: String,
        rawContentStart: Int,
        leadingHiddenPrefixLength: Int,
        normalAttributes: [NSAttributedString.Key: Any],
        boldAttributes: [NSAttributedString.Key: Any],
        attributed: NSMutableAttributedString,
        segments: inout [NoteTextMapper.Segment]
    ) {
        let nsText = text as NSString
        guard nsText.length > 0 else { return }

        var location = 0
        var pendingLeadingHiddenPrefixLength = leadingHiddenPrefixLength

        while location < nsText.length {
            let searchRange = NSRange(location: location, length: nsText.length - location)
            let openRange = nsText.range(of: "**", range: searchRange)
            guard openRange.location != NSNotFound else {
                appendVisibleText(
                    nsText.substring(with: NSRange(location: location, length: nsText.length - location)),
                    plainLocation: rawContentStart + location - pendingLeadingHiddenPrefixLength,
                    hiddenPrefixLength: pendingLeadingHiddenPrefixLength,
                    hiddenSuffixLength: 0,
                    attributes: normalAttributes,
                    attributed: attributed,
                    segments: &segments
                )
                return
            }

            if openRange.location > location {
                appendVisibleText(
                    nsText.substring(with: NSRange(location: location, length: openRange.location - location)),
                    plainLocation: rawContentStart + location - pendingLeadingHiddenPrefixLength,
                    hiddenPrefixLength: pendingLeadingHiddenPrefixLength,
                    hiddenSuffixLength: 0,
                    attributes: normalAttributes,
                    attributed: attributed,
                    segments: &segments
                )
                pendingLeadingHiddenPrefixLength = 0
            }

            let innerStart = openRange.location + 2
            guard innerStart < nsText.length else {
                appendVisibleText(
                    nsText.substring(with: NSRange(location: openRange.location, length: nsText.length - openRange.location)),
                    plainLocation: rawContentStart + openRange.location - pendingLeadingHiddenPrefixLength,
                    hiddenPrefixLength: pendingLeadingHiddenPrefixLength,
                    hiddenSuffixLength: 0,
                    attributes: normalAttributes,
                    attributed: attributed,
                    segments: &segments
                )
                return
            }

            let closeRange = nsText.range(
                of: "**",
                range: NSRange(location: innerStart, length: nsText.length - innerStart)
            )
            guard closeRange.location != NSNotFound, closeRange.location > innerStart else {
                appendVisibleText(
                    nsText.substring(with: NSRange(location: openRange.location, length: nsText.length - openRange.location)),
                    plainLocation: rawContentStart + openRange.location - pendingLeadingHiddenPrefixLength,
                    hiddenPrefixLength: pendingLeadingHiddenPrefixLength,
                    hiddenSuffixLength: 0,
                    attributes: normalAttributes,
                    attributed: attributed,
                    segments: &segments
                )
                return
            }

            let innerLength = closeRange.location - innerStart
            guard innerLength > 0 else {
                appendVisibleText(
                    "**",
                    plainLocation: rawContentStart + openRange.location - pendingLeadingHiddenPrefixLength,
                    hiddenPrefixLength: pendingLeadingHiddenPrefixLength,
                    hiddenSuffixLength: 0,
                    attributes: normalAttributes,
                    attributed: attributed,
                    segments: &segments
                )
                pendingLeadingHiddenPrefixLength = 0
                location = innerStart
                continue
            }

            appendVisibleText(
                nsText.substring(with: NSRange(location: innerStart, length: innerLength)),
                plainLocation: rawContentStart + openRange.location - pendingLeadingHiddenPrefixLength,
                hiddenPrefixLength: pendingLeadingHiddenPrefixLength + 2,
                hiddenSuffixLength: 2,
                attributes: boldAttributes,
                attributed: attributed,
                segments: &segments
            )
            pendingLeadingHiddenPrefixLength = 0
            location = closeRange.location + 2
        }
    }

    private static func appendVisibleText(
        _ text: String,
        plainLocation: Int,
        hiddenPrefixLength: Int,
        hiddenSuffixLength: Int,
        attributes: [NSAttributedString.Key: Any],
        attributed: NSMutableAttributedString,
        segments: inout [NoteTextMapper.Segment]
    ) {
        let visibleLength = (text as NSString).length
        guard visibleLength > 0 else { return }

        let attributedRange = NSRange(location: attributed.length, length: visibleLength)
        attributed.append(NSAttributedString(string: text, attributes: attributes))
        segments.append(
            NoteTextMapper.Segment(
                attributedRange: attributedRange,
                plainRange: NSRange(
                    location: plainLocation,
                    length: visibleLength + hiddenPrefixLength + hiddenSuffixLength
                ),
                hiddenPrefixLength: hiddenPrefixLength,
                hiddenSuffixLength: hiddenSuffixLength,
                isCheckboxAttachment: false
            )
        )
    }

    private static func appendCheckboxAttachment(
        _ attachment: CheckboxAttachment,
        plainLocation: Int,
        plainLength: Int,
        attributed: NSMutableAttributedString,
        segments: inout [NoteTextMapper.Segment]
    ) {
        let attributedRange = NSRange(location: attributed.length, length: 1)
        attributed.append(NSAttributedString(attachment: attachment))
        segments.append(
            NoteTextMapper.Segment(
                attributedRange: attributedRange,
                plainRange: NSRange(location: plainLocation, length: plainLength),
                hiddenPrefixLength: plainLength,
                hiddenSuffixLength: 0,
                isCheckboxAttachment: true
            )
        )
    }

    @MainActor
    private static func applyPlaceholderStyling(
        to attributed: NSMutableAttributedString,
        font: UIFont
    ) {
        let italicFont = UIFont.italicSystemFont(ofSize: font.pointSize)
        let nsText = attributed.string as NSString

        for placeholder in ExpandingTextView.styledPlaceholders {
            var searchRange = NSRange(location: 0, length: nsText.length)
            while searchRange.location < nsText.length {
                let range = nsText.range(of: placeholder, range: searchRange)
                guard range.location != NSNotFound else { break }
                attributed.addAttribute(.font, value: italicFont, range: range)
                attributed.addAttribute(.foregroundColor, value: ExpandingTextView.brandColor, range: range)
                searchRange.location = range.location + range.length
                searchRange.length = nsText.length - searchRange.location
            }
        }
    }

    private static func applyLegacySpeakerStyling(
        to attributed: NSMutableAttributedString,
        speakerColors: [String: UIColor],
        font: UIFont
    ) {
        guard !speakerColors.isEmpty else { return }
        let boldFont = UIFont.systemFont(ofSize: font.pointSize, weight: .semibold)
        let nsText = attributed.string as NSString

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

    @MainActor
    private static func applyParagraphStyles(
        to attributed: NSMutableAttributedString,
        mapper: NoteTextMapper,
        lineInstructions: [LineInstruction],
        font: UIFont,
        lineSpacing: CGFloat
    ) {
        let bulletIndent = ("• " as NSString).size(withAttributes: [.font: font]).width
        let bulletParagraphStyle = NSMutableParagraphStyle()
        bulletParagraphStyle.lineSpacing = lineSpacing
        bulletParagraphStyle.firstLineHeadIndent = 0
        bulletParagraphStyle.headIndent = bulletIndent
        let checkboxParagraphStyle = ExpandingTextView.checkboxParagraphStyle(font: font, lineSpacing: lineSpacing)

        for instruction in lineInstructions {
            let attributedRange = mapper.attributedRange(forPlainRange: instruction.plainRange)
            guard attributedRange.length > 0 else { continue }

            switch instruction.kind {
            case .bullet:
                attributed.addAttribute(.paragraphStyle, value: bulletParagraphStyle, range: attributedRange)
            case .checkbox(let checkedTextRange):
                attributed.addAttribute(.paragraphStyle, value: checkboxParagraphStyle, range: attributedRange)
                if let checkedTextRange {
                    let checkedAttributedRange = mapper.attributedRange(forPlainRange: checkedTextRange)
                    guard checkedAttributedRange.length > 0 else { continue }
                    attributed.addAttribute(
                        .strikethroughStyle,
                        value: NSUnderlineStyle.single.rawValue,
                        range: checkedAttributedRange
                    )
                    attributed.addAttribute(
                        .foregroundColor,
                        value: UIColor.tertiaryLabel,
                        range: checkedAttributedRange
                    )
                }
            }
        }
    }

    private static func checkedTextAttributes(
        from baseAttributes: [NSAttributedString.Key: Any],
        font: UIFont? = nil
    ) -> [NSAttributedString.Key: Any] {
        var attributes = baseAttributes
        if let font {
            attributes[.font] = font
        }
        attributes[.foregroundColor] = UIColor.tertiaryLabel
        attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        return attributes
    }

    private static func checkboxState(for rawLine: String) -> Bool? {
        guard let firstScalar = rawLine.unicodeScalars.first else { return nil }
        switch firstScalar.value {
        case 0x2610:
            return false
        case 0x2611:
            return true
        default:
            return nil
        }
    }

    private static func checkboxPrefixLength(in rawLine: String) -> Int {
        let nsLine = rawLine as NSString
        guard nsLine.length > 0 else { return 0 }
        return (nsLine.length > 1 && nsLine.character(at: 1) == 0x0020) ? 2 : 1
    }

    static func headingFont(from font: UIFont) -> UIFont {
        UIFont.systemFont(ofSize: font.pointSize + 8, weight: .semibold)
    }

    private static func boldFont(from font: UIFont) -> UIFont {
        UIFont.systemFont(ofSize: font.pointSize, weight: .semibold)
    }

    private static func displayText(forLine rawLine: String) -> String {
        let headingPrefix = "# "
        let headingContent = rawLine.hasPrefix(headingPrefix)
            ? String(rawLine.dropFirst((headingPrefix as NSString).length))
            : rawLine
        let line = rawLine.hasPrefix(headingPrefix) && !headingContent.trimmingCharacters(in: .whitespaces).isEmpty
            ? headingContent
            : rawLine

        return stripBoldMarkers(in: line)
    }

    private static func stripBoldMarkers(in text: String) -> String {
        let nsText = text as NSString
        guard nsText.length > 0 else { return text }

        var pieces: [String] = []
        var location = 0

        while location < nsText.length {
            let openRange = nsText.range(of: "**", range: NSRange(location: location, length: nsText.length - location))
            guard openRange.location != NSNotFound else {
                pieces.append(nsText.substring(with: NSRange(location: location, length: nsText.length - location)))
                break
            }

            if openRange.location > location {
                pieces.append(nsText.substring(with: NSRange(location: location, length: openRange.location - location)))
            }

            let innerStart = openRange.location + 2
            guard innerStart < nsText.length else {
                pieces.append(nsText.substring(with: NSRange(location: openRange.location, length: nsText.length - openRange.location)))
                break
            }

            let closeRange = nsText.range(of: "**", range: NSRange(location: innerStart, length: nsText.length - innerStart))
            guard closeRange.location != NSNotFound, closeRange.location > innerStart else {
                pieces.append(nsText.substring(with: NSRange(location: openRange.location, length: nsText.length - openRange.location)))
                break
            }

            pieces.append(nsText.substring(with: NSRange(location: innerStart, length: closeRange.location - innerStart)))
            location = closeRange.location + 2
        }

        return pieces.joined()
    }

    private static func lineHasTrailingNewline(in text: NSString, fullLineRange: NSRange) -> Bool {
        guard fullLineRange.length > 0 else { return false }
        return text.character(at: fullLineRange.location + fullLineRange.length - 1) == 0x0A
    }
}
