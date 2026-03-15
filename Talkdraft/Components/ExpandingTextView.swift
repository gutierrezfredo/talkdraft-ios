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

    static let brandColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x8B/255, green: 0x5C/255, blue: 0xF6/255, alpha: 1)
            : UIColor(red: 0x7C/255, green: 0x3A/255, blue: 0xED/255, alpha: 1)
    }

    static let uncheckedCheckboxColor = UIColor.secondaryLabel

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
        tv.tintColor = Self.brandColor
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
        tv.tintColor = Self.brandColor

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

        // MARK: - Keyboard Observer

        var lastKnownKeyboardHeight: CGFloat = 0
        var lastKnownKeyboardFrame: CGRect = .null
    }
}
