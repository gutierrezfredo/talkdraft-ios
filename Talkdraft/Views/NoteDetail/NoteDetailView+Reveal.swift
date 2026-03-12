import SwiftUI

extension NoteDetailView {
    func scrollToTop() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.3)) {
                scrollProxy?.scrollTo("scrollTop", anchor: .top)
            }
        }
    }

    func revealContent(_ text: String) {
        typewriterTask?.cancel()
        typewriterTask = nil
        contentOpacity = 0
        appendPlaceholder = nil
        editedContent = text
        syncBodyState(with: text)
        scrollToTop()
        withAnimation(.easeIn(duration: 0.5)) {
            contentOpacity = 1
        }
    }
}
