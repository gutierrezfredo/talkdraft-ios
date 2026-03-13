import SwiftUI

// MARK: - Sheet Background

struct SheetBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            (colorScheme == .dark ? Color.darkBackground : Color.warmBackground)
                .opacity(colorScheme == .dark ? 0.85 : 0.55)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Rename Speaker Alert

extension View {
    func renameSpeakerAlert(
        renamingSpeaker: Binding<String?>,
        renameText: Binding<String>,
        onConfirm: @escaping (String, String) -> Void
    ) -> some View {
        alert("Rename Speaker", isPresented: Binding(
            get: { renamingSpeaker.wrappedValue != nil },
            set: { if !$0 { renamingSpeaker.wrappedValue = nil } }
        )) {
            TextField("New name", text: renameText)
            Button("Rename") {
                if let key = renamingSpeaker.wrappedValue {
                    let trimmed = renameText.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    onConfirm(key, trimmed)
                }
                renamingSpeaker.wrappedValue = nil
            }
            Button("Cancel", role: .cancel) {
                renamingSpeaker.wrappedValue = nil
            }
        } message: {
            Text("This will update all instances in the transcript")
        }
    }
}
