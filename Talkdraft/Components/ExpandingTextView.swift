import SwiftUI
import UIKit

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
        checkboxTap.cancelsTouchesInView = true
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
        let mapper = NoteTextMapper(attributedText: tv.attributedText)
        let currentPlain = mapper.plainText
        if currentPlain != text || needsRefresh {
            let selectedPlainRange = mapper.plainRange(forAttributedRange: tv.selectedRange)
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
        NoteTextMapper(attributedText: tv.attributedText).plainText
    }

    fileprivate static func selectedPlainRange(in tv: UITextView) -> NSRange {
        NoteTextMapper(attributedText: tv.attributedText).plainRange(forAttributedRange: tv.selectedRange)
    }

    static func setSelectedPlainRange(_ range: NSRange, in tv: UITextView) {
        let mapper = NoteTextMapper(attributedText: tv.attributedText)
        tv.selectedRange = mapper.attributedRange(forPlainRange: range)
    }

    fileprivate static func plainCursorLocation(in tv: UITextView) -> Int {
        NoteTextMapper(attributedText: tv.attributedText).plainOffset(forAttributedOffset: tv.selectedRange.location)
    }

    fileprivate static func plainOffset(forAttributedOffset attributedOffset: Int, in attributed: NSAttributedString?) -> Int {
        NoteTextMapper(attributedText: attributed).plainOffset(forAttributedOffset: attributedOffset)
    }

    fileprivate static func plainRange(forAttributedRange range: NSRange, in attributed: NSAttributedString?) -> NSRange {
        NoteTextMapper(attributedText: attributed).plainRange(forAttributedRange: range)
    }

    fileprivate static func attributedOffset(forPlainOffset plainOffset: Int, in attributed: NSAttributedString?) -> Int {
        NoteTextMapper(attributedText: attributed).attributedOffset(forPlainOffset: plainOffset)
    }

    fileprivate static func attributedRange(forPlainRange range: NSRange, in attributed: NSAttributedString?) -> NSRange {
        NoteTextMapper(attributedText: attributed).attributedRange(forPlainRange: range)
    }

    fileprivate static func checkboxParagraphStyle(font: UIFont, lineSpacing: CGFloat) -> NSMutableParagraphStyle {
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
        let cursorLoc = Self.plainCursorLocation(in: tv)
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

    private func typingAttributes(
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

    // MARK: - Coordinator

    class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: ExpandingTextView
        weak var textView: UITextView?
        private var displayLink: CADisplayLink?
        var pendingTypingAttributesSync: DispatchWorkItem?
        var pendingCursorVisibilitySync: DispatchWorkItem?
        var pendingScrollOffsetRestore: DispatchWorkItem?
        var pendingTrailingDeletionFollow: DispatchWorkItem?
        var pendingCheckboxTapSelection: NSRange?
        var pendingDeletionAnchorCaretBottom: CGFloat?
        var pendingEndInsertionSavedOffset: CGPoint?
        var suppressNextScrollOffsetRestore = false
        var pendingAnimatedNewlineInsertionFollow = false
        var pendingAnimatedNewlineDeletionFollow = false
        var lastTextChangeSelection: NSRange?
        private var pulseStart: CFTimeInterval = 0
        var isAnimatingAttributes = false
        var preserveScrollOnNextUpdate = false
        var needsAttributeRefresh = false
        var lastSpeakerColorKeys: String = ""
        private static let highlightOverlayTag = 888

        init(_ parent: ExpandingTextView) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardWillChangeFrame),
                name: UIResponder.keyboardWillChangeFrameNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardWillHide),
                name: UIResponder.keyboardWillHideNotification,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
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
                let mapper = NoteTextMapper(attributedText: tv.attributedText)
                let attributedRange = mapper.attributedRange(forPlainRange: range)
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

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard !isAnimatingAttributes else { return true }

            let mapper = NoteTextMapper(attributedText: tv.attributedText)
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
                return false
            case let .apply(updatedText, selectedPlainRange):
                pendingDeletionAnchorCaretBottom = nil
                pendingEndInsertionSavedOffset = nil
                suppressNextScrollOffsetRestore = false
                pendingAnimatedNewlineInsertionFollow = false
                pendingAnimatedNewlineDeletionFollow = false
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
            let mapper = NoteTextMapper(attributedText: tv.attributedText)
            parent.text = mapper.plainText
            parent.cursorPosition = mapper.plainOffset(forAttributedOffset: tv.selectedRange.location)
            if let label = tv.viewWithTag(999) as? UILabel {
                label.isHidden = !parent.text.isEmpty
            }
            // Sync typing attributes on text change so bullet/checkbox lines get the right
            // paragraph style for the *next* character. Moving this out of
            // textViewDidChangeSelection prevents iOS 26 from snapping the cursor to a
            // word boundary when typingAttributes is mutated during a selection change.
            syncTypingAttributesToCurrentLine(tv)
            lastTextChangeSelection = tv.selectedRange
            if let savedOffset = enclosingScrollView(for: tv)?.contentOffset, !suppressNextScrollOffsetRestore {
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
            let mapper = NoteTextMapper(attributedText: tv.attributedText)
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
                    let lineStart = nsText.character(at: lineRange.location)
                    attrs = parent.typingAttributes(
                        forLineStart: lineStart,
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

        // MARK: - Keyboard Observer

        var lastKnownKeyboardHeight: CGFloat = 0
        var lastKnownKeyboardFrame: CGRect = .null
    }
}
