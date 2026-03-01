import SwiftUI
import UIKit

// MARK: - Checkbox Attachment

final class CheckboxAttachment: NSTextAttachment {
    let isChecked: Bool

    init(checked: Bool, font: UIFont, color: UIColor) {
        self.isChecked = checked
        super.init(data: nil, ofType: nil)
        let symbolName = checked ? "checkmark.circle.fill" : "circle"
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        self.image = UIImage(systemName: symbolName, withConfiguration: config)?
            .withTintColor(color, renderingMode: .alwaysOriginal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
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

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
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

    func updateUIView(_ tv: UITextView, context: Context) {
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

    static func dismantleUIView(_ tv: UITextView, coordinator: Coordinator) {
        coordinator.invalidateDisplayLink()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
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
                result += attachment.isChecked ? "☑" : "☐"
            } else {
                result += (attributed.string as NSString).substring(with: range)
            }
        }
        return result
    }

    // MARK: - Apply styled attributes (☐/☑ → SF Symbol attachments)

    private func applyTextAttributes(_ tv: UITextView) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.label,
            .paragraphStyle: style,
        ]

        tv.typingAttributes = attributes

        guard !text.isEmpty else {
            tv.text = ""
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
                    let charRange = NSRange(location: lineOffset, length: 1)
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
        for r in replacements.reversed() {
            let attachStr = NSAttributedString(attachment: r.attachment)
            attributed.replaceCharacters(in: r.range, with: attachStr)
        }

        tv.attributedText = attributed
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

        @objc private func handleCheckboxTap(_ gesture: UITapGestureRecognizer) {
            guard let tv = gesture.view as? UITextView,
                  let attributed = tv.attributedText else { return }
            let point = gesture.location(in: tv)

            // Find the nearest checkbox within a 44pt tap target
            let hitRadius: CGFloat = 22
            let attrLength = attributed.length
            var bestIdx: Int?
            var bestDist: CGFloat = .greatestFiniteMagnitude

            attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attrLength)) { value, range, stop in
                guard value is CheckboxAttachment else { return }
                guard let start = tv.position(from: tv.beginningOfDocument, offset: range.location),
                      let end = tv.position(from: start, offset: range.length),
                      let textRange = tv.textRange(from: start, to: end) else { return }
                let rect = tv.firstRect(for: textRange)
                guard !rect.isNull && !rect.isInfinite else { return }
                // Expand rect to 44x44 minimum
                let center = CGPoint(x: rect.midX, y: rect.midY)
                let dx = max(0, abs(point.x - center.x) - rect.width / 2)
                let dy = max(0, abs(point.y - center.y) - rect.height / 2)
                let dist = hypot(dx, dy)
                if dist < hitRadius && dist < bestDist {
                    bestDist = dist
                    bestIdx = range.location
                }
            }

            guard let idx = bestIdx,
                  let attachment = attributed.attribute(.attachment, at: idx, effectiveRange: nil) as? CheckboxAttachment else { return }
            var chars = Array(parent.text)
            guard idx < chars.count else { return }
            chars[idx] = attachment.isChecked ? "☐" : "☑"
            preserveScrollOnNextUpdate = true
            parent.text = String(chars)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
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
            scrollCursorVisible(in: tv)
        }

        private func scrollCursorVisible(in tv: UITextView) {
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
            let keyboardHeight = scrollView.adjustedContentInset.bottom
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
                scrollView.setContentOffset(newOffset, animated: true)
            }
        }

        func textViewDidChangeSelection(_ tv: UITextView) {
            guard !isAnimatingAttributes else { return }
            parent.cursorPosition = tv.selectedRange.location
            scrollCursorVisible(in: tv)
        }

        func textViewDidBeginEditing(_ tv: UITextView) {
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            parent.isFocused = false
        }
    }
}
