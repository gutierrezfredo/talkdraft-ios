import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    @Environment(AuthStore.self) private var authStore
    @Environment(NoteStore.self) private var noteStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var step: OnboardingStep = .welcome
    @State private var navigationDirection: NavigationDirection = .forward
    @State private var selectedCategoryIndices: Set<Int> = []
    @State private var guestAuthError: String?

    static func shouldShowTrialReminderAfterPurchase(
        plan: PaywallPlan,
        startedTrial: Bool,
        showsReminderForDebugPurchases: Bool
    ) -> Bool {
        guard plan != .lifetime else { return false }
        return startedTrial || showsReminderForDebugPurchases
    }

    private static var showsReminderForDebugPurchases: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? .darkBackground : .warmBackground
    }

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    if step == .welcome {
                        OnboardingWelcomeStep(onNext: advance)
                            .padding(.top, step.topContentInset)
                            .id(stepViewID(for: .welcome))
                            .transition(stepTransition)
                    }

                    if step == .categories {
                        OnboardingCategoriesStep(
                            selectedIndices: $selectedCategoryIndices,
                            onNext: advance,
                            onBack: goBack
                        )
                        .padding(.top, step.topContentInset)
                        .id(stepViewID(for: .categories))
                        .transition(stepTransition)
                    }

                    if step == .paywall {
                        OnboardingPaywallStep(
                            onPurchaseCompleted: { plan, startedTrial in
                                createCategories()
                                handlePurchaseCompletion(plan: plan, startedTrial: startedTrial)
                            },
                            onRestored: { createCategories(); finishOnboarding() },
                            onGuestContinue: authStore.isAuthenticated ? nil : { handleGuestContinue() }
                        )
                        .padding(.top, step.topContentInset)
                        .id(stepViewID(for: .paywall))
                        .transition(stepTransition)
                    }

                    if step == .trialReminder {
                        OnboardingTrialReminderStep {
                            finishOnboarding()
                        }
                        .padding(.top, step.topContentInset)
                        .id(stepViewID(for: .trialReminder))
                        .transition(stepTransition)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .overlay(alignment: .top) {
            if step.showsTopChrome {
                topChromeContainer
            }
        }
        .animation(.easeInOut(duration: 0.3), value: step)
        .alert("Unable to Continue as Guest", isPresented: .init(
            get: { guestAuthError != nil },
            set: {
                if !$0 {
                    guestAuthError = nil
                    authStore.error = nil
                }
            }
        )) {
            Button("OK") {
                guestAuthError = nil
                authStore.error = nil
            }
        } message: {
            Text(guestAuthError ?? "")
        }
    }

    // MARK: - Top Chrome

    private var topChromeContainer: some View {
        VStack(spacing: 0) {
            topChrome
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 4)
                .background(backgroundColor.opacity(0.85))

            LinearGradient(
                colors: [backgroundColor.opacity(0.85), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 20)
        }
    }

    private var topChrome: some View {
        HStack {
            Group {
                if step.showsBackButton {
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
                } else {
                    Color.clear
                }
            }
            .frame(width: 72, alignment: .leading)

            Spacer()

            progressBar

            Spacer()

            Color.clear
                .frame(width: 72, height: 44)
        }
        .frame(height: 44)
    }

    // MARK: - Progress Bar

    private var progressStepIndex: Int {
        switch step {
        case .welcome:
            0
        case .categories:
            1
        case .paywall, .trialReminder:
            2
        }
    }

    private var progressStepCount: Int {
        3
    }

    private var progressBar: some View {
        return HStack(spacing: 6) {
            ForEach(0..<progressStepCount, id: \.self) { index in
                if index == progressStepIndex {
                    Capsule()
                        .fill(Color.brand)
                        .frame(width: 24, height: 8)
                } else {
                    Circle()
                        .fill(index < progressStepIndex ? Color.brand : Color.brand.opacity(0.25))
                        .frame(width: 8, height: 8)
                }
            }
        }
        .animation(.snappy, value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Onboarding progress")
        .accessibilityValue("\(progressStepIndex + 1) of \(progressStepCount)")
    }

    // MARK: - Navigation

    private var stepTransition: AnyTransition {
        switch navigationDirection {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            )
        case .backward:
            return .asymmetric(
                insertion: .move(edge: .leading),
                removal: .identity
            )
        }
    }

    private func stepViewID(for step: OnboardingStep) -> String {
        "\(step.rawValue)-\(navigationDirection)"
    }

    private func advance() {
        guard let next = step.next else {
            finishOnboarding()
            return
        }
        navigationDirection = .forward
        step = next
    }

    private func goBack() {
        guard let prev = step.previous else { return }
        navigationDirection = .backward
        step = prev
    }

    // MARK: - Completion

    private func handleGuestContinue() {
        if authStore.isGuest {
            createCategories()
            finishOnboarding()
            return
        }

        guard !authStore.isAuthenticated else { return }

        Task {
            guestAuthError = nil
            let signedIn = await authStore.signInAnonymously()
            guard signedIn, authStore.isAuthenticated, authStore.isGuest, authStore.userId != nil else {
                guestAuthError = authStore.error ?? "Unable to continue as guest right now. Please try again."
                return
            }
            createCategories()
            finishOnboarding()
        }
    }

    private func createCategories() {
        guard let userId = authStore.userId else { return }
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

    private func handlePurchaseCompletion(plan: PaywallPlan, startedTrial: Bool) {
        if Self.shouldShowTrialReminderAfterPurchase(
            plan: plan,
            startedTrial: startedTrial,
            showsReminderForDebugPurchases: Self.showsReminderForDebugPurchases
        ) {
            navigationDirection = .forward
            step = .trialReminder
        } else {
            finishOnboarding()
        }
    }

    private func finishOnboarding() {
        onComplete()
    }
}

// MARK: - Step Enum

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case categories
    case paywall
    case trialReminder

    var showsTopChrome: Bool {
        switch self {
        case .paywall:
            false
        case .welcome, .categories, .trialReminder:
            true
        }
    }

    var showsBackButton: Bool {
        switch self {
        case .welcome, .paywall, .trialReminder: false
        case .categories: true
        }
    }

    var topContentInset: CGFloat {
        switch self {
        case .categories:
            56
        case .welcome, .paywall, .trialReminder:
            0
        }
    }

    var previous: OnboardingStep? {
        switch self {
        case .welcome: nil
        case .categories: .welcome
        case .paywall: .categories
        case .trialReminder: nil
        }
    }

    var next: OnboardingStep? {
        switch self {
        case .welcome: .categories
        case .categories: .paywall
        case .paywall, .trialReminder: nil
        }
    }
}

private enum NavigationDirection {
    case forward
    case backward
}
