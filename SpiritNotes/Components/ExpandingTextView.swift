import SwiftUI
import UIKit

/// A UITextView wrapper that expands to fit content (like TextField(axis: .vertical))
/// but uses UIKit's native responder chain for correct keyboard/cursor scroll behavior.
struct ExpandingTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var font: UIFont = .preferredFont(forTextStyle: .body)
    var lineSpacing: CGFloat = 6
    var placeholder: String = ""

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
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text {
            let selected = tv.selectedRange
            applyTextAttributes(tv)
            if selected.location + selected.length <= tv.text.count {
                tv.selectedRange = selected
            }
        }

        // Placeholder visibility
        if let label = tv.viewWithTag(999) as? UILabel {
            label.isHidden = !tv.text.isEmpty
        }

        // Focus management
        if isFocused && !tv.isFirstResponder {
            DispatchQueue.main.async { tv.becomeFirstResponder() }
        } else if !isFocused && tv.isFirstResponder {
            DispatchQueue.main.async { tv.resignFirstResponder() }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(size.height, 40))
    }

    private func applyTextAttributes(_ tv: UITextView) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.label,
            .paragraphStyle: style,
        ]

        tv.typingAttributes = attributes

        if !text.isEmpty {
            let attributed = NSMutableAttributedString(string: text, attributes: attributes)
            tv.attributedText = attributed
        } else {
            tv.text = ""
        }
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: ExpandingTextView

        init(_ parent: ExpandingTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text ?? ""
            if let label = tv.viewWithTag(999) as? UILabel {
                label.isHidden = !tv.text.isEmpty
            }
        }

        func textViewDidBeginEditing(_ tv: UITextView) {
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            parent.isFocused = false
        }
    }
}
