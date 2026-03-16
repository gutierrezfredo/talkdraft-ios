import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    @Environment(AuthStore.self) private var authStore
    @Environment(NoteStore.self) private var noteStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptionStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var step: OnboardingStep = .welcome
    @State private var selectedLanguage: String = "auto"
    @State private var selectedCategoryIndices: Set<Int> = []
    @State private var trialJustStarted = false

    private var backgroundColor: Color {
        colorScheme == .dark ? .darkBackground : .warmBackground
    }

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
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
                    case .welcome:
                        OnboardingWelcomeStep(onNext: advance)

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
                            onTrialStarted: {
                                trialJustStarted = true
                                advance()
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
    }

    // MARK: - Navigation

    private func advance() {
        guard let next = step.next(trialStarted: trialJustStarted) else {
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
    case welcome
    case language
    case categories
    case paywall
    case notifications

    var showsBackButton: Bool {
        switch self {
        case .welcome, .paywall, .notifications: false
        case .language, .categories: true
        }
    }

    var previous: OnboardingStep? {
        switch self {
        case .welcome: nil
        case .language: .welcome
        case .categories: .language
        case .paywall: nil
        case .notifications: nil
        }
    }

    func next(trialStarted: Bool) -> OnboardingStep? {
        switch self {
        case .welcome: .language
        case .language: .categories
        case .categories: .paywall
        case .paywall: trialStarted ? .notifications : nil
        case .notifications: nil
        }
    }
}
