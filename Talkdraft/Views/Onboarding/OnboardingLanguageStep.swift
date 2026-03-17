import SwiftUI

struct OnboardingLanguageStep: View {
    @Binding var selectedLanguage: String
    let onNext: () -> Void
    let onBack: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""

    private var cardColor: Color {
        colorScheme == .dark ? .darkSurface : .white
    }

    private var allLanguages: [(code: String, name: String)] {
        [("auto", "Auto-detect")] + SettingsStore.supportedLanguages
    }

    private var filteredLanguages: [(code: String, name: String)] {
        if searchText.isEmpty { return allLanguages }
        let query = searchText.lowercased()
        return allLanguages.filter { $0.name.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 12) {
                Text("What language should we use for transcriptions?")
                    .font(.brandTitle)
                    .fixedSize(horizontal: false, vertical: true)

                Text("We'll use this to improve accuracy when you record. You can change it anytime in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.body)
                    .foregroundStyle(.secondary)
                TextField("Search languages", text: $searchText)
                    .font(.body)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(cardColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            // Language list
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(filteredLanguages.enumerated()), id: \.element.code) { index, lang in
                        Button {
                            selectedLanguage = lang.code
                        } label: {
                            HStack {
                                Text(lang.name)
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(
                                        selectedLanguage == lang.code ? Color.brand : .primary
                                    )
                                Spacer()
                                if selectedLanguage == lang.code {
                                    Image(systemName: "checkmark")
                                        .font(.body)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.brand)
                                }
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < filteredLanguages.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(cardColor)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal, 20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        .clear,
                        (colorScheme == .dark ? Color.darkBackground : .warmBackground).opacity(0.85),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 20)

                Button {
                    onNext()
                } label: {
                    Text("Continue")
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.brand, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .background(colorScheme == .dark ? Color.darkBackground : .warmBackground)
            }
        }
        .sensoryFeedback(.selection, trigger: selectedLanguage)
    }
}
