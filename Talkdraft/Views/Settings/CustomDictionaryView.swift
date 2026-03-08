import SwiftUI

struct CustomDictionaryView: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var newWord = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Add word field
                HStack(spacing: 12) {
                    TextField("Add a word…", text: $newWord)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($isFieldFocused)
                        .onAppear { isFieldFocused = true }
                        .onSubmit(addWord)

                    Button("Save", action: addWord)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(newWord.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : Color.brand)
                        .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(16)
                .background(colorScheme == .dark ? Color.darkSurface : .white)
                .clipShape(RoundedRectangle(cornerRadius: 24))

                if settingsStore.customDictionary.isEmpty {
                    // Empty state
                    VStack(spacing: 8) {
                        Text("No custom words yet")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        Text("Add words that transcription often misspells — names, brands, or jargon.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 32)
                } else {
                    // Word list
                    VStack(spacing: 0) {
                        ForEach(Array(settingsStore.customDictionary.enumerated()), id: \.offset) { index, word in
                            HStack {
                                Text(word)
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                Spacer()

                                Button {
                                    withAnimation { removeWord(at: index) }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 48)

                            if index < settingsStore.customDictionary.count - 1 {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .background(colorScheme == .dark ? Color.darkSurface : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(
            (colorScheme == .dark ? Color.darkBackground : .warmBackground)
                .ignoresSafeArea()
        )
        .navigationTitle("Custom Dictionary")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        withAnimation {
            settingsStore.addWord(trimmed)
        }
        newWord = ""
    }

    private func removeWord(at index: Int) {
        settingsStore.removeWord(at: index)
    }
}
