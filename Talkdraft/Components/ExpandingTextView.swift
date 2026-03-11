import SwiftUI
import UIKit

// MARK: - Checkbox Attachment

final class CheckboxAttachment: NSTextAttachment {
    let isChecked: Bool
    private let textFont: UIFont

    init(checked: Bool, font: UIFont, color: UIColor) {
        self.isChecked = checked
        self.textFont = font
        super.init(data: nil, ofType: nil)
        let symbolName = checked ? "checkmark.circle.fill" : "circle"
        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: checked ? .medium : .light)
        if let symbol = UIImage(systemName: symbolName, withConfiguration: config)?
            .withTintColor(color, renderingMode: .alwaysOriginal) {
            // Draw icon into a wider canvas (icon + 16pt trailing padding) so
            // the layout engine reserves the correct space on the first line too.
            // Force exactly 28×28 for the icon to ensure perfect square proportions.
            let iconSize: CGFloat = 28
            let paddedSize = CGSize(width: iconSize + 12, height: iconSize)
            let renderer = UIGraphicsImageRenderer(size: paddedSize)
            self.image = renderer.image { _ in
                symbol.draw(in: CGRect(x: 0, y: 0, width: iconSize, height: iconSize))
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: CGRect, glyphPosition position: CGPoint, characterIndex charIndex: Int) -> CGRect {
        guard image != nil else { return .zero }
        // Use a fixed size so checked/unchecked don't cause layout shifts
        let fixedSize: CGFloat = 28
        let yOffset = (textFont.capHeight - fixedSize) / 2
        return CGRect(x: 0, y: yOffset, width: fixedSize + 12, height: fixedSize)
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

// MARK: - ExpandingTextView

/// A UITextView wrapper that expands to fit content (like TextField(axis: .vertical))
/// but uses UIKit's native responder chain for correct keyboard/cursor scroll behavior.
struct ExpandingTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var cursorPosition: Int
    @Binding var highlightRange: NSRange?
    @Binding var preserveScroll: Bool
    var isEditable: Bool = true
    var font: UIFont = .preferredFont(forTextStyle: .body)
    var lineSpacing: CGFloat = 6
    var placeholder: String = ""
    var speakerColors: [String: UIColor] = [:]
    var horizontalPadding: CGFloat = 0
    var moveCursorToEnd: Binding<Bool> = .constant(false)
    var onCheckboxToggle: ((String) -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    // Placeholder markers styled differently (brand color + italic + pulse).
    static let styledPlaceholders = [
        NoteBodyState.recordingPlaceholder,
        NoteBodyState.transcribingPlaceholder,
    ]

    private static let brandColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x8B/255, green: 0x5C/255, blue: 0xF6/255, alpha: 1)
            : UIColor(red: 0x7C/255, green: 0x3A/255, blue: 0xED/255, alpha: 1)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> CheckboxTextView {
        // Force TextKit 1 via explicit NSLayoutManager stack.
        // TextKit 2 (default on iOS 17+) has a bug where tapping a UITextView places the
        // caret at a completely wrong position (often off-screen). TextKit 1 does not.
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        let tv = CheckboxTextView(frame: .zero, textContainer: textContainer)
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 0, left: horizontalPadding, bottom: 0, right: horizontalPadding)
        tv.textContainer.lineFragmentPadding = 0
        tv.keyboardAppearance = colorScheme == .dark ? .dark : .light
        tv.spellCheckingType = .no
        tv.delegate = context.coordinator
        tv.coordinator = context.coordinator

        // Checkbox tap recognizer — delegate (Coordinator) gates it via gestureRecognizerShouldBegin:
        // returns false outside the checkbox icon zone so UIKit handles those taps normally
        // (cursor placement, focus). Returns true only for taps on a checkbox attachment.
        // shouldRecognizeSimultaneously allows UITextView's own recognizers to also fire.
        let checkboxTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleCheckboxTap(_:))
        )
        checkboxTap.cancelsTouchesInView = false
        checkboxTap.delegate = context.coordinator
        tv.addGestureRecognizer(checkboxTap)

        // Placeholder label
        let label = UILabel()
        label.text = placeholder
        label.font = font
        label.textColor = .tertiaryLabel
        label.tag = 999
        label.translatesAutoresizingMaskIntoConstraints = false
        tv.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: tv.topAnchor),
            label.leadingAnchor.constraint(equalTo: tv.leadingAnchor, constant: horizontalPadding),
        ])

        applyTextAttributes(tv)
        return tv
    }

    func updateUIView(_ tv: CheckboxTextView, context: Context) {
        context.coordinator.parent = self
        // Re-apply attributes if the speaker color map changed
        let newSpeakerKeys = speakerColors.keys.sorted().joined(separator: ",")
        if newSpeakerKeys != context.coordinator.lastSpeakerColorKeys {
            context.coordinator.lastSpeakerColorKeys = newSpeakerKeys
            context.coordinator.needsAttributeRefresh = true
        }

        let needsRefresh = context.coordinator.needsAttributeRefresh
        context.coordinator.needsAttributeRefresh = false
        let currentPlain = Self.extractPlainText(from: tv)
        if currentPlain != text || needsRefresh {
            let selectedPlainRange = Self.selectedPlainRange(in: tv)
            let shouldPreserveScroll = context.coordinator.preserveScrollOnNextUpdate || preserveScroll
            context.coordinator.preserveScrollOnNextUpdate = false
            if preserveScroll {
                DispatchQueue.main.async { self.preserveScroll = false }
            }

            // Save scroll position for checkbox toggles (prevents scroll jump)
            var savedOffset: CGPoint?
            var enclosingScroll: UIScrollView?
            if shouldPreserveScroll {
                var current: UIView? = tv.superview
                while let view = current {
                    if let sv = view as? UIScrollView, sv !== tv {
                        enclosingScroll = sv
                        savedOffset = sv.contentOffset
                        break
                    }
                    current = view.superview
                }
            }

            applyTextAttributes(tv)
            Self.setSelectedPlainRange(selectedPlainRange, in: tv)
            // Re-sync typingAttributes after programmatic cursor placement — setting
            // tv.selectedRange causes UIKit to reset typingAttributes to the adjacent
            // character's attributes, which for checkbox attachments lacks .foregroundColor.
            context.coordinator.syncTypingAttributesToCurrentLine(tv)

            // Restore scroll position
            if let offset = savedOffset, let sv = enclosingScroll {
                sv.setContentOffset(offset, animated: false)
            }
        }

        // Placeholder visibility
        if let label = tv.viewWithTag(999) as? UILabel {
            label.isHidden = !text.isEmpty
        }

        // Keyboard appearance — set explicitly to avoid a flash when becoming first responder
        // before the trait collection has fully propagated the color scheme.
        let desiredAppearance: UIKeyboardAppearance = colorScheme == .dark ? .dark : .light
        if tv.keyboardAppearance != desiredAppearance {
            tv.keyboardAppearance = desiredAppearance
        }

        // Editability
        tv.isEditable = isEditable

        // Focus management — only act when the UITextView state doesn't match the binding.
        if isFocused && !tv.isFirstResponder {
            DispatchQueue.main.async {
                guard !tv.isFirstResponder else { return }
                // Read traitCollection directly at call time — more reliable than the
                // SwiftUI colorScheme captured earlier, preventing a keyboard color flash.
                tv.keyboardAppearance = tv.traitCollection.userInterfaceStyle == .dark ? .dark : .light
                _ = tv.becomeFirstResponder()
                // Do NOT set selectedRange here — let moveCursorToEnd handle it when needed,
                // and let UITextView's own touch handling place the cursor for user taps.
            }
        } else if !isFocused && tv.isFirstResponder {
            DispatchQueue.main.async { tv.resignFirstResponder() }
        }

        // Move cursor to end (e.g. tapping empty space below content while already focused)
        if moveCursorToEnd.wrappedValue {
            let coordinator = context.coordinator
            DispatchQueue.main.async {
                // Re-check: if user tapped on text in the meantime, textViewDidChangeSelection
                // will have already cancelled this (set to false). Don't override their cursor.
                guard moveCursorToEnd.wrappedValue else { return }
                moveCursorToEnd.wrappedValue = false
                guard tv.isFirstResponder else { return }
                let end = tv.attributedText?.length ?? 0
                tv.selectedRange = NSRange(location: end, length: 0)
                // Scroll cursor into view — keyboard may already be visible (no new show notification).
                coordinator.scrollCursorVisible(in: tv)
            }
        }

        // Pulse animation for placeholders
        context.coordinator.updatePulse(for: tv)

        // Highlight flash for newly inserted text (UIView overlay approach)
        if let range = highlightRange {
            context.coordinator.showHighlightOverlay(range: range, in: tv)
            DispatchQueue.main.async { self.highlightRange = nil }
        }
    }

    static func dismantleUIView(_ tv: CheckboxTextView, coordinator: Coordinator) {
        coordinator.invalidateDisplayLink()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: CheckboxTextView, context: Context) -> CGSize? {
        let fallbackWidth = uiView.window?.windowScene?.screen.bounds.width ?? uiView.bounds.width
        let width = proposal.width ?? max(fallbackWidth, 1)
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(size.height, 40))
    }

    // MARK: - Extract plain text (attachments → ☐/☑)

    static func extractPlainText(from tv: UITextView) -> String {
        guard let attributed = tv.attributedText, attributed.length > 0 else { return "" }
        var result = ""
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attrs, range, _ in
            if let attachment = attrs[.attachment] as? CheckboxAttachment {
                result += attachment.isChecked ? "☑ " : "☐ "
            } else {
                result += (attributed.string as NSString).substring(with: range)
            }
        }
        return result
    }

    fileprivate static func selectedPlainRange(in tv: UITextView) -> NSRange {
        plainRange(forAttributedRange: tv.selectedRange, in: tv.attributedText)
    }

    fileprivate static func setSelectedPlainRange(_ range: NSRange, in tv: UITextView) {
        tv.selectedRange = attributedRange(forPlainRange: range, in: tv.attributedText)
    }

    fileprivate static func plainCursorLocation(in tv: UITextView) -> Int {
        plainOffset(forAttributedOffset: tv.selectedRange.location, in: tv.attributedText)
    }

    fileprivate static func plainOffset(forAttributedOffset attributedOffset: Int, in attributed: NSAttributedString?) -> Int {
        guard let attributed else { return max(0, attributedOffset) }
        let boundedOffset = min(max(0, attributedOffset), attributed.length)
        guard boundedOffset > 0 else { return 0 }

        var plainOffset = 0
        attributed.enumerateAttributes(in: NSRange(location: 0, length: boundedOffset)) { attrs, range, _ in
            plainOffset += (attrs[.attachment] is CheckboxAttachment) ? 2 : range.length
        }
        return plainOffset
    }

    fileprivate static func plainRange(forAttributedRange range: NSRange, in attributed: NSAttributedString?) -> NSRange {
        let start = plainOffset(forAttributedOffset: range.location, in: attributed)
        let end = plainOffset(forAttributedOffset: range.location + range.length, in: attributed)
        return NSRange(location: start, length: max(0, end - start))
    }

    fileprivate static func attributedOffset(forPlainOffset plainOffset: Int, in attributed: NSAttributedString?) -> Int {
        guard let attributed else { return max(0, plainOffset) }
        let target = max(0, plainOffset)
        guard attributed.length > 0, target > 0 else { return 0 }

        var runningPlainOffset = 0
        var resolvedOffset = attributed.length
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attrs, range, stop in
            let plainLength = (attrs[.attachment] is CheckboxAttachment) ? 2 : range.length
            let nextPlainOffset = runningPlainOffset + plainLength
            guard target <= nextPlainOffset else {
                runningPlainOffset = nextPlainOffset
                return
            }

            if attrs[.attachment] is CheckboxAttachment {
                resolvedOffset = range.location + (target <= runningPlainOffset ? 0 : range.length)
            } else {
                resolvedOffset = range.location + min(range.length, target - runningPlainOffset)
            }
            stop.pointee = true
        }

        return min(max(0, resolvedOffset), attributed.length)
    }

    fileprivate static func attributedRange(forPlainRange range: NSRange, in attributed: NSAttributedString?) -> NSRange {
        let start = attributedOffset(forPlainOffset: range.location, in: attributed)
        let end = attributedOffset(forPlainOffset: range.location + range.length, in: attributed)
        return NSRange(location: start, length: max(0, end - start))
    }

    fileprivate static func checkboxParagraphStyle(lineSpacing: CGFloat) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing - 2
        style.paragraphSpacingBefore = 6
        style.firstLineHeadIndent = 0
        style.headIndent = 40
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
                    let color: UIColor = isChecked ? Self.brandColor : .secondaryLabel
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
        let checkboxParaStyle = Self.checkboxParagraphStyle(lineSpacing: lineSpacing)
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
        let cursorLoc = Self.plainCursorLocation(in: tv)
        let checkLoc = min(cursorLoc > 0 ? cursorLoc - 1 : 0, nsText.length - 1)
        let lineRange = nsText.lineRange(for: NSRange(location: checkLoc, length: 0))
        guard lineRange.location < nsText.length else { return baseAttributes }
        let lineStart = nsText.character(at: lineRange.location)
        var attrs = baseAttributes
        if lineStart == 0x2022 {
            attrs[.paragraphStyle] = bulletParaStyle
            return attrs
        }
        if lineStart == 0x2610 || lineStart == 0x2611 {
            attrs[.paragraphStyle] = checkboxParaStyle
            return attrs
        }
        return attrs
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: ExpandingTextView
        private weak var textView: UITextView?
        private var displayLink: CADisplayLink?
        private var pulseStart: CFTimeInterval = 0
        private var isAnimatingAttributes = false
        var preserveScrollOnNextUpdate = false
        var needsAttributeRefresh = false
        var lastSpeakerColorKeys: String = ""
        private static let highlightOverlayTag = 888

        init(_ parent: ExpandingTextView) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardDidShow),
                name: UIResponder.keyboardDidShowNotification,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func keyboardDidShow(_ notification: Notification) {
            guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            lastKnownKeyboardHeight = frame.height
            guard let tv = textView, tv.isFirstResponder else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let tv = self?.textView else { return }
                self?.scrollCursorVisible(in: tv)
            }
        }

        func invalidateDisplayLink() {
            displayLink?.invalidate()
            displayLink = nil
        }

        // MARK: - Pulse Animation (CADisplayLink — only modifies placeholder color)

        func updatePulse(for tv: UITextView) {
            textView = tv
            let plainText = ExpandingTextView.extractPlainText(from: tv)
            let hasPlaceholder = ExpandingTextView.styledPlaceholders.contains { plainText.contains($0) }

            if hasPlaceholder && displayLink == nil {
                pulseStart = CACurrentMediaTime()
                let link = CADisplayLink(target: self, selector: #selector(pulseTick))
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60)
                link.add(to: .main, forMode: .common)
                displayLink = link
            } else if !hasPlaceholder && displayLink != nil {
                displayLink?.invalidate()
                displayLink = nil
            }
        }

        @objc private func pulseTick() {
            guard let tv = textView else { return }
            let plainText = ExpandingTextView.extractPlainText(from: tv)
            guard plainText == parent.text else { return }
            guard let attributed = tv.attributedText.mutableCopy() as? NSMutableAttributedString else { return }

            let elapsed = CACurrentMediaTime() - pulseStart
            let pulseAlpha = CGFloat(0.675 + 0.325 * cos(elapsed * 2.5))
            let brandColor = UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0x8B/255, green: 0x5C/255, blue: 0xF6/255, alpha: pulseAlpha)
                    : UIColor(red: 0x7C/255, green: 0x3A/255, blue: 0xED/255, alpha: pulseAlpha)
            }

            var found = false
            let attrString = attributed.string as NSString
            for placeholder in ExpandingTextView.styledPlaceholders {
                var searchRange = NSRange(location: 0, length: attrString.length)
                while searchRange.location < attrString.length {
                    let range = attrString.range(of: placeholder, range: searchRange)
                    guard range.location != NSNotFound else { break }
                    attributed.addAttribute(.foregroundColor, value: brandColor, range: range)
                    found = true
                    searchRange.location = range.location + range.length
                    searchRange.length = attrString.length - searchRange.location
                }
            }

            guard found else {
                displayLink?.invalidate()
                displayLink = nil
                return
            }

            let sel = tv.selectedRange
            isAnimatingAttributes = true
            tv.attributedText = attributed
            isAnimatingAttributes = false
            let len = tv.attributedText?.length ?? 0
            if sel.location + sel.length <= len {
                tv.selectedRange = sel
            }
        }

        // MARK: - Highlight Flash (UIView overlays — no attributed string manipulation)

        func showHighlightOverlay(range: NSRange, in tv: UITextView) {
            DispatchQueue.main.async { [weak self] in
                let attributedRange = ExpandingTextView.attributedRange(forPlainRange: range, in: tv.attributedText)
                self?.addHighlightViews(range: attributedRange, in: tv)
            }
        }

        private func addHighlightViews(range: NSRange, in tv: UITextView) {
            let len = tv.attributedText?.length ?? 0
            guard range.location + range.length <= len else { return }
            guard let start = tv.position(from: tv.beginningOfDocument, offset: range.location),
                  let end = tv.position(from: start, offset: range.length),
                  let textRange = tv.textRange(from: start, to: end) else { return }

            let selectionRects = tv.selectionRects(for: textRange)
            let brandColor = UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0x8B/255, green: 0x5C/255, blue: 0xF6/255, alpha: 0.35)
                    : UIColor(red: 0x7C/255, green: 0x3A/255, blue: 0xED/255, alpha: 0.35)
            }

            for selRect in selectionRects where !selRect.rect.isEmpty && selRect.rect.width > 0 {
                let overlay = UIView(frame: selRect.rect)
                overlay.backgroundColor = brandColor
                overlay.layer.cornerRadius = 4
                overlay.isUserInteractionEnabled = false
                overlay.tag = Self.highlightOverlayTag
                tv.insertSubview(overlay, at: 0)

                UIView.animate(withDuration: 1.5, delay: 0, options: .curveEaseOut) {
                    overlay.alpha = 0
                } completion: { _ in
                    overlay.removeFromSuperview()
                }
            }
        }

        // MARK: - UITextViewDelegate

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
                  checkboxIndex(near: point, in: tv) != nil else { return false }
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
            // Allow UITextView's built-in recognizers (cursor, selection) to fire alongside ours.
            return true
        }

        /// Toggles the checkbox at the given plain-text index. Called from handleCheckboxTap.
        func toggleCheckbox(at plainIndex: Int, in tv: CheckboxTextView) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            let savedSelection = ExpandingTextView.selectedPlainRange(in: tv)
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
        /// the checkbox icon tap zone on a checkbox line, else nil.
        /// Uses NSLayoutManager exclusively — no UITextInput methods — so it is safe to call
        /// from touchesBegan without disturbing UITextInteraction's cursor placement state.
        func checkboxIndex(near point: CGPoint, in tv: UITextView) -> Int? {
            // Only trigger within the left tap zone (checkbox icon area)
            let maxTapX: CGFloat = tv.textContainerInset.left + 40
            guard point.x <= maxTapX else { return nil }

            // Convert view point → layout manager coordinate space
            let lm = tv.layoutManager
            let tc = tv.textContainer
            let layoutPoint = CGPoint(
                x: point.x - tv.textContainerInset.left,
                y: point.y - tv.textContainerInset.top
            )

            // characterIndex gives the nearest character — pure geometry, no UITextInput involved
            var fraction: CGFloat = 0
            let charIdx = lm.characterIndex(for: layoutPoint, in: tc, fractionOfDistanceBetweenInsertionPoints: &fraction)

            let plainOffset = ExpandingTextView.plainOffset(forAttributedOffset: charIdx, in: tv.attributedText)

            let nsText = parent.text as NSString
            guard nsText.length > 0 else { return nil }
            let safeOffset = min(max(plainOffset, 0), nsText.length - 1)
            let lineRange = nsText.lineRange(for: NSRange(location: safeOffset, length: 0))
            guard lineRange.length > 0 else { return nil }

            let firstChar = nsText.character(at: lineRange.location)
            guard firstChar == 0x2610 || firstChar == 0x2611 else { return nil }

            // Restrict to the first visual line of the checkbox item so tapping a wrapped
            // continuation line doesn't toggle. Get the line fragment rect via NSLayoutManager.
            let attrCheckboxOffset = ExpandingTextView.attributedOffset(forPlainOffset: lineRange.location, in: tv.attributedText)
            guard attrCheckboxOffset < (tv.attributedText?.length ?? 0) else { return nil }

            let glyphAtCheckbox = lm.glyphIndexForCharacter(at: attrCheckboxOffset)
            let lineFragRect = lm.lineFragmentRect(forGlyphAt: glyphAtCheckbox, effectiveRange: nil)
            let lineRectInView = lineFragRect.offsetBy(
                dx: tv.textContainerInset.left,
                dy: tv.textContainerInset.top
            )
            guard point.y >= lineRectInView.minY && point.y <= lineRectInView.maxY else { return nil }

            return lineRange.location
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
            let plainOffset = ExpandingTextView.plainOffset(forAttributedOffset: charIdx, in: tv.attributedText)
            let safeOffset = min(plainOffset, nsText.length - 1)
            let lineRange = nsText.lineRange(for: NSRange(location: safeOffset, length: 0))
            let trimLen = lineRange.location + lineRange.length < nsText.length ? lineRange.length - 1 : lineRange.length
            guard trimLen > 0 else { return nil }
            let line = nsText.substring(with: NSRange(location: lineRange.location, length: trimLen))
            return parent.speakerColors[line] != nil ? line : nil
        }

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard !isAnimatingAttributes else { return true }

            let plainText = ExpandingTextView.extractPlainText(from: tv)
            let plainRange = ExpandingTextView.plainRange(forAttributedRange: range, in: tv.attributedText)
            let mutation = NoteEditorRules.mutation(
                for: plainText,
                range: plainRange,
                replacementText: text,
                protectedLines: Set(parent.speakerColors.keys)
            )

            switch mutation {
            case .allowSystem:
                return true
            case .reject:
                return false
            case let .apply(updatedText, selectedPlainRange):
                applyPlainTextEdit(updatedText: updatedText, selectedPlainRange: selectedPlainRange, in: tv)
                return false
            }
        }

        private func applyPlainTextEdit(
            updatedText: String,
            selectedPlainRange: NSRange,
            in tv: UITextView,
            preserveScroll: Bool = false
        ) {
            preserveScrollOnNextUpdate = preserveScroll
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
        }

        func textViewDidChange(_ tv: UITextView) {
            guard !isAnimatingAttributes else { return }
            parent.text = ExpandingTextView.extractPlainText(from: tv)
            parent.cursorPosition = ExpandingTextView.plainCursorLocation(in: tv)
            if let label = tv.viewWithTag(999) as? UILabel {
                label.isHidden = !parent.text.isEmpty
            }
            // Sync typing attributes on text change so bullet/checkbox lines get the right
            // paragraph style for the *next* character. Moving this out of
            // textViewDidChangeSelection prevents iOS 26 from snapping the cursor to a
            // word boundary when typingAttributes is mutated during a selection change.
            syncTypingAttributesToCurrentLine(tv)
            // Defer 50 ms so SwiftUI has finished laying out the expanded text view
            // and the outer UIScrollView's contentSize is up to date before we scroll.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak tv] in
                guard let self, let tv else { return }
                self.scrollCursorVisible(in: tv, animated: false)
            }
        }

        func scrollCursorVisible(in tv: UITextView, animated: Bool = true) {
            guard let cursorPosition = tv.position(from: tv.beginningOfDocument, offset: tv.selectedRange.location),
                  let caretRange = tv.textRange(from: cursorPosition, to: cursorPosition)
            else { return }

            let caretRect = tv.firstRect(for: caretRange)
            guard !caretRect.isNull && !caretRect.isInfinite else { return }

            // Find the enclosing UIScrollView (SwiftUI's ScrollView)
            var scrollView: UIScrollView?
            var current: UIView? = tv.superview
            while let view = current {
                if let sv = view as? UIScrollView, sv !== tv {
                    scrollView = sv
                    break
                }
                current = view.superview
            }
            guard let scrollView, let window = tv.window else { return }

            // Work in window coordinates so the result is correct regardless of
            // whether SwiftUI has updated UITextView's frame height yet.
            let caretInWindow = tv.convert(caretRect, to: window)
            let screenHeight = window.bounds.height
            let keyboardHeight = max(scrollView.adjustedContentInset.bottom, lastKnownKeyboardHeight)
            let toolbarHeight: CGFloat = 88
            let visibleBottom = screenHeight - keyboardHeight - toolbarHeight

            let caretBottom = caretInWindow.maxY
            guard caretBottom > visibleBottom else { return }

            let scrollAmount = caretBottom - visibleBottom + 20 // 20 pt breathing room
            let newOffset = CGPoint(x: scrollView.contentOffset.x,
                                    y: scrollView.contentOffset.y + scrollAmount)
            scrollView.setContentOffset(newOffset, animated: animated)
        }

        func textViewDidChangeSelection(_ tv: UITextView) {
            guard !isAnimatingAttributes else { return }

            if parent.moveCursorToEnd.wrappedValue {
                parent.moveCursorToEnd.wrappedValue = false
            }
            parent.cursorPosition = ExpandingTextView.plainCursorLocation(in: tv)

            nudgeCursorOffCheckbox(tv)
            if !parent.speakerColors.isEmpty {
                nudgeCursorOffSpeakerLine(tv)
            }
        }

        private func nudgeCursorOffCheckbox(_ tv: UITextView) {
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

        private func nudgeCursorOffSpeakerLine(_ tv: UITextView) {
            let nsText = parent.text as NSString
            guard nsText.length > 0, tv.selectedRange.length == 0 else { return }
            let cursor = ExpandingTextView.plainCursorLocation(in: tv)
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

        func syncTypingAttributesToCurrentLine(_ tv: UITextView) {
            let plainText = ExpandingTextView.extractPlainText(from: tv)
            let nsText = plainText as NSString
            let baseStyle = NSMutableParagraphStyle()
            baseStyle.lineSpacing = parent.lineSpacing
            var attrs: [NSAttributedString.Key: Any] = [
                .font: parent.font,
                .foregroundColor: UIColor.label,
                .paragraphStyle: baseStyle,
            ]
            if nsText.length > 0 {
                let cursorLoc = ExpandingTextView.plainCursorLocation(in: tv)
                let checkLoc = min(cursorLoc > 0 ? cursorLoc - 1 : 0, nsText.length - 1)
                let lineRange = nsText.lineRange(for: NSRange(location: checkLoc, length: 0))
                if lineRange.location < nsText.length {
                    let lineStart = nsText.character(at: lineRange.location)
                    if lineStart == 0x2022 {
                        let bulletIndent = ("• " as NSString).size(withAttributes: [.font: parent.font]).width
                        let bulletStyle = NSMutableParagraphStyle()
                        bulletStyle.lineSpacing = parent.lineSpacing
                        bulletStyle.firstLineHeadIndent = 0
                        bulletStyle.headIndent = bulletIndent
                        attrs[.paragraphStyle] = bulletStyle
                    } else if lineStart == 0x2610 || lineStart == 0x2611 {
                        attrs[.paragraphStyle] = ExpandingTextView.checkboxParagraphStyle(lineSpacing: parent.lineSpacing)
                    }
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

        // MARK: - Keyboard Observer

        private var lastKnownKeyboardHeight: CGFloat = 0
    }
}
