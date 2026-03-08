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
        guard let image else { return .zero }
        // Use a fixed size so checked/unchecked don't cause layout shifts
        let fixedSize: CGFloat = 28
        let yOffset = (textFont.capHeight - fixedSize) / 2
        return CGRect(x: 0, y: yOffset, width: fixedSize + 12, height: fixedSize)
    }
}

// MARK: - CheckboxTextView

/// UITextView subclass that can temporarily block becoming first responder
/// during checkbox toggles, preventing cursor/keyboard flash.
final class CheckboxTextView: UITextView {
    var blockFirstResponder = false

    override var canBecomeFirstResponder: Bool {
        blockFirstResponder ? false : super.canBecomeFirstResponder
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

    // Placeholder markers styled differently (brand color + italic + pulse).
    static let styledPlaceholders = ["Recording…", "Transcribing…"]

    private static let brandColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x8B/255, green: 0x5C/255, blue: 0xF6/255, alpha: 1)
            : UIColor(red: 0x7C/255, green: 0x3A/255, blue: 0xED/255, alpha: 1)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> CheckboxTextView {
        let tv = CheckboxTextView()
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.delegate = context.coordinator

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
            label.leadingAnchor.constraint(equalTo: tv.leadingAnchor),
        ])

        applyTextAttributes(tv)
        context.coordinator.setupCheckboxTap(for: tv)
        return tv
    }

    func updateUIView(_ tv: CheckboxTextView, context: Context) {
        let needsRefresh = context.coordinator.needsAttributeRefresh
        context.coordinator.needsAttributeRefresh = false
        let currentPlain = Self.extractPlainText(from: tv)
        if currentPlain != text || needsRefresh {
            let selected = tv.selectedRange
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
            let len = tv.attributedText?.length ?? 0
            if selected.location + selected.length <= len {
                tv.selectedRange = selected
            }

            // Restore scroll position
            if let offset = savedOffset, let sv = enclosingScroll {
                sv.setContentOffset(offset, animated: false)
            }
        }

        // Placeholder visibility
        if let label = tv.viewWithTag(999) as? UILabel {
            label.isHidden = !text.isEmpty
        }

        // Editability
        tv.isEditable = isEditable

        // Focus management — only act when the UITextView state doesn't match the binding.
        if isFocused && !tv.isFirstResponder {
            DispatchQueue.main.async {
                guard !tv.isFirstResponder else { return }
                tv.becomeFirstResponder()
                let end = tv.attributedText?.length ?? 0
                tv.selectedRange = NSRange(location: end, length: 0)
            }
        } else if !isFocused && tv.isFirstResponder {
            DispatchQueue.main.async { tv.resignFirstResponder() }
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
        let width = proposal.width ?? UIScreen.main.bounds.width
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
        let checkboxParaStyle = NSMutableParagraphStyle()
        checkboxParaStyle.lineSpacing = lineSpacing - 2
        checkboxParaStyle.paragraphSpacingBefore = 6
        checkboxParaStyle.firstLineHeadIndent = 0
        checkboxParaStyle.headIndent = 40
        for r in replacements.reversed() {
            let attachStr = NSMutableAttributedString(attachment: r.attachment)
            attachStr.addAttribute(.paragraphStyle, value: checkboxParaStyle, range: NSRange(location: 0, length: attachStr.length))
            attributed.replaceCharacters(in: r.range, with: attachStr)
        }

        tv.attributedText = attributed
        // Reset typingAttributes after setting attributedText — UIKit resets them to the
        // attributes at the cursor position, which for checkbox attachments lacks .foregroundColor.
        tv.typingAttributes = attributes
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

        @objc private func keyboardDidShow() {
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
                self?.addHighlightViews(range: range, in: tv)
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

        private static let bulletPrefix = "• "
        private static let uncheckedPrefix = "☐ "

        // MARK: - Checkbox Tap-to-Toggle

        func setupCheckboxTap(for tv: UITextView) {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleCheckboxTap(_:)))
            tap.delegate = self
            tv.addGestureRecognizer(tap)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard parent.text.contains("☐") || parent.text.contains("☑") else { return false }

            // Block first responder BEFORE any tap action fires
            if let tv = gestureRecognizer.view as? CheckboxTextView {
                let point = gestureRecognizer.location(in: tv)
                if checkboxIndex(near: point, in: tv) != nil {
                    tv.blockFirstResponder = true
                }
            }
            return true
        }

        @objc private func handleCheckboxTap(_ gesture: UITapGestureRecognizer) {
            guard let tv = gesture.view as? CheckboxTextView else { return }
            let point = gesture.location(in: tv)

            // Always unblock first responder
            defer {
                DispatchQueue.main.async { tv.blockFirstResponder = false }
            }

            guard let idx = checkboxIndex(near: point, in: tv) else { return }

            UIImpactFeedbackGenerator(style: .light).impactOccurred()

            var chars = Array(parent.text)
            guard idx < chars.count else { return }
            chars[idx] = (chars[idx] == "☑") ? "☐" : "☑"
            preserveScrollOnNextUpdate = true

            let savedSelection = tv.selectedRange
            isAnimatingAttributes = true
            parent.text = String(chars)
            parent.applyTextAttributes(tv)
            let len = tv.attributedText?.length ?? 0
            if savedSelection.location + savedSelection.length <= len {
                tv.selectedRange = savedSelection
            }
            isAnimatingAttributes = false
        }

        private func checkboxIndex(near point: CGPoint, in tv: UITextView) -> Int? {
            guard let tapPosition = tv.closestPosition(to: point) else { return nil }
            let tapOffset = tv.offset(from: tv.beginningOfDocument, to: tapPosition)

            // tapOffset is in attributed text coordinates. Each CheckboxAttachment occupies
            // 1 char in attributed text but 2 chars in parent.text (☐/☑ + space), so
            // translate by counting attachments before the tap point.
            var checkboxCount = 0
            if let attributed = tv.attributedText {
                let scanRange = NSRange(location: 0, length: min(tapOffset, attributed.length))
                attributed.enumerateAttributes(in: scanRange) { attrs, _, _ in
                    if attrs[.attachment] is CheckboxAttachment { checkboxCount += 1 }
                }
            }
            let plainOffset = tapOffset + checkboxCount

            let nsText = parent.text as NSString
            guard nsText.length > 0 else { return nil }

            let safeOffset = min(max(plainOffset, 0), nsText.length - 1)
            let lineRange = nsText.lineRange(for: NSRange(location: safeOffset, length: 0))
            guard lineRange.length > 0 else { return nil }

            let firstChar = nsText.character(at: lineRange.location)
            guard firstChar == 0x2610 || firstChar == 0x2611 else { return nil }

            let maxTapX: CGFloat = 28
            guard point.x <= maxTapX else { return nil }

            return lineRange.location
        }

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard !isAnimatingAttributes else { return true }

            // Work with plain text representation for line analysis
            let plainText = ExpandingTextView.extractPlainText(from: tv)
            let nsText = plainText as NSString

            // Auto-convert "[]" to "☐ " — triggered when user types "]"
            if text == "]" && range.location > 0 && range.location <= nsText.length {
                let prevIdx = range.location - 1
                if prevIdx < nsText.length {
                    let prevChar = nsText.character(at: prevIdx)
                    if prevChar == UInt16(Character("[").asciiValue!) {
                        let bracketRange = NSRange(location: prevIdx, length: 1)
                        tv.selectedRange = bracketRange
                        tv.insertText(Self.uncheckedPrefix)
                        needsAttributeRefresh = true
                        return false
                    }
                }
            }

            // Normalize "- " to "• " at line start
            if text == " " && range.location <= nsText.length {
                let lineStart = nsText.lineRange(for: NSRange(location: min(range.location, nsText.length - 1), length: 0)).location
                if range.location > lineStart {
                    let typed = nsText.substring(with: NSRange(location: lineStart, length: range.location - lineStart))
                    if typed == "-" {
                        let replaceRange = NSRange(location: lineStart, length: range.location - lineStart)
                        tv.selectedRange = replaceRange
                        tv.insertText(Self.bulletPrefix)
                        return false
                    }
                }
            }

            // Handle return key for bullet/checkbox continuation
            guard text == "\n" else { return true }

            guard range.location <= nsText.length else { return true }
            let safeLocation = min(range.location, max(nsText.length - 1, 0))
            let lineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
            let currentLine = nsText.substring(with: lineRange).trimmingCharacters(in: .newlines)

            // Checkbox continuation
            if currentLine.hasPrefix("☐ ") || currentLine.hasPrefix("☑ ") {
                let trimmed = currentLine.trimmingCharacters(in: .whitespaces)
                if trimmed == "☐" || trimmed == "☑" {
                    let deleteRange = NSRange(
                        location: lineRange.location,
                        length: min(lineRange.length, nsText.length - lineRange.location)
                    )
                    tv.selectedRange = deleteRange
                    tv.insertText("")
                    return false
                }
                tv.insertText("\n" + Self.uncheckedPrefix)
                needsAttributeRefresh = true
                return false
            }

            // Bullet continuation
            guard currentLine.hasPrefix(Self.bulletPrefix) else { return true }

            if currentLine == Self.bulletPrefix.trimmingCharacters(in: .whitespaces) || currentLine == Self.bulletPrefix {
                let deleteRange = NSRange(
                    location: lineRange.location,
                    length: min(lineRange.length, nsText.length - lineRange.location)
                )
                tv.selectedRange = deleteRange
                tv.insertText("")
                return false
            }

            tv.insertText("\n" + Self.bulletPrefix)
            return false
        }

        func textViewDidChange(_ tv: UITextView) {
            guard !isAnimatingAttributes else { return }
            parent.text = ExpandingTextView.extractPlainText(from: tv)
            parent.cursorPosition = tv.selectedRange.location
            if let label = tv.viewWithTag(999) as? UILabel {
                label.isHidden = !parent.text.isEmpty
            }
            scrollCursorVisible(in: tv, animated: false)
        }

        private func scrollCursorVisible(in tv: UITextView, animated: Bool = true) {
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
            guard let scrollView else { return }

            // Get caret position in screen coordinates
            guard let window = tv.window else { return }
            let caretInWindow = tv.convert(caretRect, to: window)

            // Calculate the bottom edge of visible area:
            // screen height - keyboard height - toolbar height (~88pt)
            let screenHeight = window.bounds.height
            let keyboardHeight = max(scrollView.adjustedContentInset.bottom, lastKnownKeyboardHeight)
            let toolbarHeight: CGFloat = 88
            let visibleBottom = screenHeight - keyboardHeight - toolbarHeight

            // If caret is below the visible area, scroll up
            let caretBottom = caretInWindow.maxY
            if caretBottom > visibleBottom {
                let scrollAmount = caretBottom - visibleBottom + 20 // 20pt extra breathing room
                let newOffset = CGPoint(
                    x: scrollView.contentOffset.x,
                    y: scrollView.contentOffset.y + scrollAmount
                )
                scrollView.setContentOffset(newOffset, animated: animated)
            }
        }

        func textViewDidChangeSelection(_ tv: UITextView) {
            guard !isAnimatingAttributes else { return }
            parent.cursorPosition = tv.selectedRange.location
        }

        func textViewDidBeginEditing(_ tv: UITextView) {
            parent.isFocused = true
            startKeyboardObserver(for: tv)
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            parent.isFocused = false
            stopKeyboardObserver()
        }

        // MARK: - Keyboard Observer

        private var keyboardObserver: NSObjectProtocol?
        private var lastKnownKeyboardHeight: CGFloat = 0

        private func startKeyboardObserver(for tv: UITextView) {
            stopKeyboardObserver()
            keyboardObserver = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardDidShowNotification,
                object: nil,
                queue: .main
            ) { [weak tv] notification in
                guard let tv, let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                self.lastKnownKeyboardHeight = frame.height
                self.scrollCursorVisible(in: tv)
            }
        }

        private func stopKeyboardObserver() {
            if let observer = keyboardObserver {
                NotificationCenter.default.removeObserver(observer)
                keyboardObserver = nil
            }
        }
    }
}
