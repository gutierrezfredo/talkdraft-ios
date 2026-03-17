import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    @Environment(AuthStore.self) private var authStore
    @Environment(NoteStore.self) private var noteStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var step: OnboardingStep = .language
    @State private var selectedLanguage: String = "auto"
    @State private var selectedCategoryIndices: Set<Int> = []

    private var backgroundColor: Color {
        if step == .paywall {
            return Color.brand.opacity(colorScheme == .dark ? 0.20 : 0.12)
        }
        return colorScheme == .dark ? .darkBackground : .warmBackground
    }

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                progressBar
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                // Back button
                if step.showsBackButton {
                    HStack {
                        Button {
                            goBack()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.body)
                                    .fontWeight(.semibold)
                                Text("Back")
                                    .font(.body)
                            }
                            .foregroundStyle(Color.brand)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                // Step content
                Group {
                    switch step {
                    case .language:
                        OnboardingLanguageStep(
                            selectedLanguage: $selectedLanguage,
                            onNext: advance,
                            onBack: goBack
                        )

                    case .categories:
                        OnboardingCategoriesStep(
                            selectedIndices: $selectedCategoryIndices,
                            onNext: advance,
                            onBack: goBack
                        )

                    case .paywall:
                        OnboardingPaywallStep(
                            onPurchaseCompleted: { startedTrial in
                                if startedTrial {
                                    step = .notifications
                                } else {
                                    finishOnboarding()
                                }
                            },
                            onRestored: { finishOnboarding() }
                        )

                    case .notifications:
                        OnboardingNotificationsStep(onComplete: finishOnboarding)
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .id(step)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: step)
        .onAppear {
            selectedLanguage = settingsStore.language
        }
    }

    // MARK: - Progress Bar

    private var progressSteps: [OnboardingStep] {
        switch step {
        case .notifications:
            [.language, .categories, .paywall, .notifications]
        default:
            [.language, .categories, .paywall]
        }
    }

    private var progressBar: some View {
        let currentIndex = progressSteps.firstIndex(of: step) ?? 0

        return HStack(spacing: 6) {
            ForEach(Array(progressSteps.enumerated()), id: \.offset) { index, _ in
                if index == currentIndex {
                    Capsule()
                        .fill(Color.brand)
                        .frame(width: 24, height: 8)
                } else {
                    Circle()
                        .fill(index < currentIndex ? Color.brand : Color.brand.opacity(0.25))
                        .frame(width: 8, height: 8)
                }
            }
        }
        .animation(.snappy, value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Onboarding progress")
        .accessibilityValue("\(currentIndex + 1) of \(progressSteps.count)")
    }

    // MARK: - Navigation

    private func advance() {
        guard let next = step.next else {
            finishOnboarding()
            return
        }
        step = next
    }

    private func goBack() {
        guard let prev = step.previous else { return }
        step = prev
    }

    // MARK: - Completion

    private func finishOnboarding() {
        // Save language
        settingsStore.language = selectedLanguage
        settingsStore.saveLanguageToProfile()

        // Create selected categories (idempotent)
        if let userId = authStore.userId {
            let existingNames = Set(noteStore.categories.map { $0.name.lowercased() })
            for (sortIndex, catIndex) in selectedCategoryIndices.sorted().enumerated() {
                let suggestion = CategorySuggestion.all[catIndex]
                guard !existingNames.contains(suggestion.name.lowercased()) else { continue }
                let category = Category(
                    id: UUID(),
                    userId: userId,
                    name: suggestion.name,
                    color: suggestion.color,
                    icon: nil,
                    sortOrder: noteStore.categories.count + sortIndex,
                    createdAt: .now
                )
                noteStore.addCategory(category)
            }
        }

        // Mark onboarding complete
        if let userId = authStore.userId {
            UserDefaults.standard.set(true, forKey: "onboarding.completed.\(userId.uuidString)")
        }

        onComplete()
    }
}

// MARK: - Step Enum

private enum OnboardingStep: Int, CaseIterable {
    case language
    case categories
    case paywall
    case notifications

    var showsBackButton: Bool {
        switch self {
        case .language, .paywall, .notifications: false
        case .categories: true
        }
    }

    var previous: OnboardingStep? {
        switch self {
        case .language: nil
        case .categories: .language
        case .paywall: nil
        case .notifications: nil
        }
    }

    var next: OnboardingStep? {
        switch self {
        case .language: .categories
        case .categories: .paywall
        case .paywall: nil
        case .notifications: nil
        }
    }
}
