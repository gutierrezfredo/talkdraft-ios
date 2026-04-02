import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    @Environment(AuthStore.self) private var authStore
    @Environment(NoteStore.self) private var noteStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var step: OnboardingStep = .welcome
    @State private var navigationDirection: NavigationDirection = .forward
    @State private var selectedCategoryIndices: Set<Int> = []
    @State private var showTrialReminderSheet = false
    @State private var guestAuthError: String?

    private var backgroundColor: Color {
        colorScheme == .dark ? .darkBackground : .warmBackground
    }

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                if step != .welcome {
                    progressBar
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    backBar
                }

                ZStack(alignment: .top) {
                    if step == .welcome {
                        OnboardingWelcomeStep(onNext: advance)
                            .id(stepViewID(for: .welcome))
                            .transition(stepTransition)
                    }

                    if step == .categories {
                        OnboardingCategoriesStep(
                            selectedIndices: $selectedCategoryIndices,
                            onNext: advance,
                            onBack: goBack
                        )
                        .id(stepViewID(for: .categories))
                        .transition(stepTransition)
                    }

                    if step == .paywall {
                        OnboardingPaywallStep(
                            onPurchaseCompleted: { startedTrial in
                                createCategories()
                                #if DEBUG
                                showTrialReminderSheet = true
                                #else
                                if startedTrial {
                                    showTrialReminderSheet = true
                                } else {
                                    finishOnboarding()
                                }
                                #endif
                            },
                            onRestored: { createCategories(); finishOnboarding() },
                            onGuestContinue: { handleGuestContinue() }
                        )
                        .id(stepViewID(for: .paywall))
                        .transition(stepTransition)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: step)
        .sheet(isPresented: $showTrialReminderSheet) {
            TrialReminderSheet {
                showTrialReminderSheet = false
                finishOnboarding()
            }
            .interactiveDismissDisabled()
            .presentationDetents([.medium])
            .presentationBackground { SheetBackground() }
        }
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

    // MARK: - Back Bar

    private var backBar: some View {
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
            .opacity(step.showsBackButton ? 1 : 0)
            .allowsHitTesting(step.showsBackButton)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(height: 32)
    }

    // MARK: - Progress Bar

    private var progressSteps: [OnboardingStep] {
        [.categories, .paywall]
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

    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboarding.completed.device")
        if let userId = authStore.userId {
            UserDefaults.standard.set(true, forKey: "onboarding.completed.\(userId.uuidString)")
        }
        onComplete()
    }
}

// MARK: - Step Enum

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case categories
    case paywall

    var showsBackButton: Bool {
        switch self {
        case .welcome, .paywall: false
        case .categories: true
        }
    }

    var previous: OnboardingStep? {
        switch self {
        case .welcome: nil
        case .categories: .welcome
        case .paywall: .categories
        }
    }

    var next: OnboardingStep? {
        switch self {
        case .welcome: .categories
        case .categories: .paywall
        case .paywall: nil
        }
    }
}

private enum NavigationDirection {
    case forward
    case backward
}
