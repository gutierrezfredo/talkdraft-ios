import UIKit

extension ExpandingTextView.Coordinator {
    // MARK: - Keyboard Observer

    @objc func keyboardWillChangeFrame(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        lastKnownKeyboardFrame = frame
        if let window = textView?.window {
            let frameInWindow = window.convert(frame, from: nil)
            lastKnownKeyboardHeight = max(0, window.bounds.intersection(frameInWindow).height)
        } else {
            lastKnownKeyboardHeight = frame.height
        }
        guard let tv = textView, tv.isFirstResponder else { return }
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        let curveRaw = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 0
        let options = UIView.AnimationOptions(rawValue: curveRaw << 16).union([.beginFromCurrentState, .allowUserInteraction])
        scheduleScrollCursorVisible(
            in: tv,
            animated: false,
            delay: 0,
            animationDuration: duration,
            animationOptions: options
        )
    }

    @objc func keyboardWillHide(_ notification: Notification) {
        lastKnownKeyboardHeight = 0
        lastKnownKeyboardFrame = .null
    }

    // MARK: - Cursor Visibility

    func scrollCursorVisible(
        in tv: UITextView,
        animated: Bool = true,
        animationDuration: TimeInterval? = nil,
        animationOptions: UIView.AnimationOptions = []
    ) {
        tv.layoutManager.ensureLayout(for: tv.textContainer)
        guard let cursorPosition = tv.position(from: tv.beginningOfDocument, offset: tv.selectedRange.location) else {
            return
        }

        let caretRect = tv.caretRect(for: cursorPosition)
        guard !caretRect.isNull && !caretRect.isInfinite else { return }
        guard let scrollView = enclosingScrollView(for: tv), let window = tv.window else { return }

        scrollView.layoutIfNeeded()
        tv.layoutIfNeeded()

        let caretInWindow = tv.convert(caretRect, to: window)
        let scrollFrameInWindow = scrollView.convert(scrollView.bounds, to: window)
        let keyboardFrameInWindow = lastKnownKeyboardFrame.isNull
            ? CGRect(x: 0, y: window.bounds.maxY, width: 0, height: 0)
            : window.convert(lastKnownKeyboardFrame, from: nil)
        let keyboardOverlap = max(0, scrollFrameInWindow.maxY - keyboardFrameInWindow.minY)
        let editorToolbarClearance: CGFloat = tv.isFirstResponder ? 108 : 24
        let visibleBottom = scrollFrameInWindow.maxY - keyboardOverlap - editorToolbarClearance
        let visibleTop = scrollFrameInWindow.minY + 12

        let targetOffset: CGPoint?
        if caretInWindow.maxY > visibleBottom {
            let scrollAmount = caretInWindow.maxY - visibleBottom + 20
            targetOffset = CGPoint(x: scrollView.contentOffset.x, y: scrollView.contentOffset.y + scrollAmount)
        } else if caretInWindow.minY < visibleTop {
            let scrollAmount = visibleTop - caretInWindow.minY + 12
            targetOffset = CGPoint(
                x: scrollView.contentOffset.x,
                y: max(-scrollView.adjustedContentInset.top, scrollView.contentOffset.y - scrollAmount)
            )
        } else {
            targetOffset = nil
        }

        guard let newOffset = targetOffset, abs(newOffset.y - scrollView.contentOffset.y) > 0.5 else { return }

        if let animationDuration, animationDuration > 0 {
            UIView.animate(withDuration: animationDuration, delay: 0, options: animationOptions) {
                scrollView.contentOffset = newOffset
                scrollView.layoutIfNeeded()
            }
        } else {
            scrollView.setContentOffset(newOffset, animated: animated)
        }
    }

    func scheduleScrollCursorVisible(
        in tv: UITextView,
        animated: Bool,
        delay: TimeInterval,
        animationDuration: TimeInterval? = nil,
        animationOptions: UIView.AnimationOptions = []
    ) {
        pendingCursorVisibilitySync?.cancel()
        let expectedSelection = tv.selectedRange
        let workItem = DispatchWorkItem { [weak self, weak tv] in
            guard let self, let tv, !self.isAnimatingAttributes else { return }
            guard tv.selectedRange == expectedSelection else { return }
            self.scrollCursorVisible(
                in: tv,
                animated: animated,
                animationDuration: animationDuration,
                animationOptions: animationOptions
            )
        }
        pendingCursorVisibilitySync = workItem
        if delay == 0 {
            DispatchQueue.main.async(execute: workItem)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    func scheduleScrollOffsetRestore(in tv: UITextView, savedOffset: CGPoint, delays: [TimeInterval]) {
        pendingScrollOffsetRestore?.cancel()
        let expectedSelection = tv.selectedRange
        for delay in delays {
            let workItem = DispatchWorkItem { [weak self, weak tv] in
                guard let self, let tv, !self.isAnimatingAttributes else { return }
                guard tv.selectedRange == expectedSelection else { return }
                guard let scrollView = self.enclosingScrollView(for: tv) else { return }
                let currentOffset = scrollView.contentOffset
                guard currentOffset.y + 24 < savedOffset.y else { return }
                UIView.performWithoutAnimation {
                    scrollView.layer.removeAllAnimations()
                    scrollView.setContentOffset(CGPoint(x: currentOffset.x, y: savedOffset.y), animated: false)
                    scrollView.layoutIfNeeded()
                }
            }
            pendingScrollOffsetRestore = workItem
            if delay == 0 {
                DispatchQueue.main.async(execute: workItem)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
            }
        }
    }

    func captureDeletionAnchorIfNeeded(
        replacementText: String,
        plainRange: NSRange,
        plainText: String,
        in tv: UITextView
    ) {
        let nsText = plainText as NSString
        guard replacementText.isEmpty,
              plainRange.length > 0,
              tv.selectedRange.length == 0,
              NSMaxRange(plainRange) <= nsText.length,
              let caretBottom = caretBottomInWindow(for: tv)
        else {
            pendingDeletionAnchorCaretBottom = nil
            pendingAnimatedNewlineDeletionFollow = false
            return
        }

        let deletedText = nsText.substring(with: plainRange)
        guard deletedText.contains("\n") else {
            pendingDeletionAnchorCaretBottom = nil
            pendingAnimatedNewlineDeletionFollow = false
            return
        }

        pendingDeletionAnchorCaretBottom = caretBottom
        pendingAnimatedNewlineDeletionFollow = true
        suppressNextScrollOffsetRestore = true
    }

    func prepareCursorFollowForSystemEdit(
        replacementText: String,
        plainRange: NSRange,
        plainText: String,
        in tv: UITextView
    ) {
        pendingAnimatedNewlineInsertionFollow = false
        pendingEndInsertionSavedOffset = nil
        if replacementText == "\n",
           plainRange.length == 0,
           tv.selectedRange.length == 0 {
            pendingAnimatedNewlineInsertionFollow = true
            if plainRange.location == (plainText as NSString).length {
                pendingEndInsertionSavedOffset = enclosingScrollView(for: tv)?.contentOffset
            }
            suppressNextScrollOffsetRestore = true
        }
    }

    func scheduleTrailingDeletionFollowIfNeeded(
        in tv: UITextView,
        animationDuration: TimeInterval? = nil,
        animationOptions: UIView.AnimationOptions = []
    ) -> Bool {
        guard let anchorCaretBottom = pendingDeletionAnchorCaretBottom else { return false }
        pendingDeletionAnchorCaretBottom = nil
        pendingTrailingDeletionFollow?.cancel()
        let expectedSelection = tv.selectedRange
        let workItem = DispatchWorkItem { [weak self, weak tv] in
            guard let self, let tv, !self.isAnimatingAttributes else { return }
            guard tv.selectedRange == expectedSelection else { return }
            guard tv.selectedRange.length == 0,
                  let scrollView = self.enclosingScrollView(for: tv),
                  let currentCaretBottom = self.caretBottomInWindow(for: tv)
            else { return }

            let delta = currentCaretBottom - anchorCaretBottom
            guard delta < -1 else { return }

            let newOffsetY = max(
                -scrollView.adjustedContentInset.top,
                scrollView.contentOffset.y + delta
            )

            if let animationDuration, animationDuration > 0 {
                UIView.animate(withDuration: animationDuration, delay: 0, options: animationOptions) {
                    scrollView.contentOffset = CGPoint(x: scrollView.contentOffset.x, y: newOffsetY)
                    scrollView.layoutIfNeeded()
                }
            } else {
                UIView.performWithoutAnimation {
                    scrollView.layer.removeAllAnimations()
                    scrollView.setContentOffset(
                        CGPoint(x: scrollView.contentOffset.x, y: newOffsetY),
                        animated: false
                    )
                    scrollView.layoutIfNeeded()
                }
            }
        }
        pendingTrailingDeletionFollow = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: workItem)
        return true
    }

    func caretBottomInWindow(for tv: UITextView) -> CGFloat? {
        guard let cursorPosition = tv.position(from: tv.beginningOfDocument, offset: tv.selectedRange.location),
              let window = tv.window
        else { return nil }
        let caretRect = tv.caretRect(for: cursorPosition)
        guard !caretRect.isNull && !caretRect.isInfinite else { return nil }
        return tv.convert(caretRect, to: window).maxY
    }

    func enclosingScrollView(for view: UIView) -> UIScrollView? {
        var current: UIView? = view.superview
        while let candidate = current {
            if let scrollView = candidate as? UIScrollView, scrollView !== view {
                return scrollView
            }
            current = candidate.superview
        }
        return nil
    }
}
