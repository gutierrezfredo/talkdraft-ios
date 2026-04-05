import AuthenticationServices
import StoreKit
import SwiftUI

enum PaywallPlan: String, CaseIterable {
    case lifetime
    case monthly

    static func normalized(selected: PaywallPlan, hasMonthly: Bool, hasLifetime: Bool) -> PaywallPlan {
        switch selected {
        case .lifetime where hasLifetime:
            .lifetime
        case .monthly where hasMonthly:
            .monthly
        case .lifetime where hasMonthly:
            .monthly
        case .monthly where hasLifetime:
            .lifetime
        default:
            selected
        }
    }
}

enum PaywallDismissActionKind: Equatable {
    case dismiss
    case continueAsGuest
}

struct OnboardingPaywallStep: View {
    let onPurchaseCompleted: (_ plan: PaywallPlan, _ startedTrial: Bool) -> Void
    let onRestored: () -> Void
    var onGuestContinue: (() -> Void)?
    var onDismiss: (() -> Void)?

    @Environment(AuthStore.self) private var authStore
    @Environment(SubscriptionStore.self) private var subscriptionStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    @State private var selectedPlan: PaywallPlan = .lifetime
    @State private var showEmailForm = false
    @State private var awaitingPurchaseAfterAuth = false
    @State private var errorMessage: String?

    private let fallbackMonthlyPrice = "$4.99"
    private let fallbackLifetimePrice = "$29.99"

    /// User is signed in with a real account (not guest, not unauthenticated)
    private var isAuthenticatedUser: Bool {
        authStore.isAuthenticated && !authStore.isGuest
    }

    private var monthlyPrice: String {
        subscriptionStore.monthlyProduct?.displayPrice ?? fallbackMonthlyPrice
    }

    private var lifetimePrice: String {
        subscriptionStore.lifetimeProduct?.displayPrice ?? fallbackLifetimePrice
    }

    private var isProcessing: Bool {
        subscriptionStore.isLoading
    }

    private var effectiveSelectedPlan: PaywallPlan {
        PaywallPlan.normalized(
            selected: selectedPlan,
            hasMonthly: subscriptionStore.monthlyProduct != nil,
            hasLifetime: subscriptionStore.lifetimeProduct != nil
        )
    }

    private var selectedProduct: StoreKit.Product? {
        switch effectiveSelectedPlan {
        case .monthly: subscriptionStore.monthlyProduct
        case .lifetime: subscriptionStore.lifetimeProduct
        }
    }

    private func isPlanAvailable(_ plan: PaywallPlan) -> Bool {
        if subscriptionStore.monthlyProduct == nil && subscriptionStore.lifetimeProduct == nil {
            return true
        }

        switch plan {
        case .monthly:
            return subscriptionStore.monthlyProduct != nil
        case .lifetime:
            return subscriptionStore.lifetimeProduct != nil
        }
    }

    static func dismissActionKind(
        isAuthenticated: Bool,
        hasDismissAction: Bool,
        hasGuestContinueAction: Bool
    ) -> PaywallDismissActionKind? {
        if hasDismissAction {
            return .dismiss
        }

        if hasGuestContinueAction && !isAuthenticated {
            return .continueAsGuest
        }

        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    planToggle
                        .padding(.bottom, 8)
                    planContent
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            // Action Stack + footer
            VStack(spacing: 12) {
                actionStack
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                legalFooter
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
            .background(headerBackground.ignoresSafeArea())
        }
        .fullScreenCover(isPresented: $showEmailForm, onDismiss: {
            if !authStore.isAuthenticated {
                awaitingPurchaseAfterAuth = false
            }
        }) {
            EmailSignInSheet()
        }
        .task(id: "\(authStore.isAuthenticated)-\(subscriptionStore.entitlementChecked)-\(subscriptionStore.hasProducts)") {
            guard awaitingPurchaseAfterAuth else { return }
            attemptPurchaseIfReady()
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await subscriptionStore.fetchProducts()
        }
        .overlay(alignment: .topLeading) {
            if let dismissAction = Self.dismissActionKind(
                isAuthenticated: authStore.isAuthenticated,
                hasDismissAction: onDismiss != nil,
                hasGuestContinueAction: onGuestContinue != nil
            ),
               let dismiss = dismissAction == .dismiss ? onDismiss : onGuestContinue {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .padding(.leading, 12)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Header

    private var headerBackground: Color {
        colorScheme == .dark ? Color.brand.opacity(0.16) : Color.brand.opacity(0.08)
    }

    private var header: some View {
        VStack(spacing: 4) {
            LunaMascotView(.paywall, size: 128)
                .zIndex(1)
                .padding(.top, 4)
                .padding(.bottom, -16)

            Text("Unlock Talkdraft Pro")
                .font(.brandTitle)
                .fontDesign(nil)
                .multilineTextAlignment(.center)

        }
        .background(alignment: .bottom) {
            ConcaveArchShape()
                .fill(headerBackground)
                .frame(height: 2000)
                .padding(.horizontal, -300)
                .offset(y: 1520)
        }
    }

    // MARK: - Plan Toggle

    private var planToggle: some View {
        HStack(spacing: 0) {
            ForEach(PaywallPlan.allCases, id: \.self) { plan in
                Button {
                    guard isPlanAvailable(plan) else { return }
                    withAnimation(.snappy(duration: 0.25)) {
                        selectedPlan = plan
                    }
                } label: {
                    Text(plan == .monthly ? "Monthly" : "Lifetime")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundStyle(effectiveSelectedPlan == plan ? .white : .primary)
                        .background(
                            effectiveSelectedPlan == plan
                                ? Capsule().fill(Color.brand)
                                : Capsule().fill(Color.clear)
                        )
                        .opacity(isPlanAvailable(plan) ? 1 : 0.45)
                        .contentShape(Capsule())
                        .overlay(alignment: .top) {
                            if plan == .lifetime {
                                Text("SAVE 60%")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(colorScheme == .dark ? Color(hex: "#34D399") : Color.brandText)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(colorScheme == .dark ? Color.darkBackground : Color.white, in: UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 8))
                                    .offset(y: -22)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .padding(.top, 16)
        .background(
            Capsule().fill(colorScheme == .dark ? Color.darkBackground : .white)
                .padding(.top, 16)
        )
        .sensoryFeedback(.selection, trigger: selectedPlan)
    }

    // MARK: - Plan Content

    private var planContent: some View {
        Group {
            if effectiveSelectedPlan == .monthly {
                monthlyTimeline
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                lifetimePerks
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
        .animation(.snappy(duration: 0.25), value: effectiveSelectedPlan)
    }

    // MARK: - Monthly Timeline

    private var monthlyTimeline: some View {
        VStack(spacing: 40) {
            VStack(alignment: .leading, spacing: 0) {
                timelineNode(
                    emoji: "🎁",
                    title: "Today — Free Trial Starts",
                    subtitle: "Nothing will be charged today.",
                    isLast: false
                )
                timelineNode(
                    emoji: "🔔",
                    title: "Day 6 — Trial Reminder",
                    subtitle: "We'll notify you 24h before",
                    isLast: false
                )
                timelineNode(
                    emoji: "🚀",
                    title: "Day 7 — Subscription Begins",
                    subtitle: "\(monthlyPrice)/mo · Cancel anytime",
                    isLast: true
                )
            }
            .padding(.horizontal, 8)

            VStack(spacing: 8) {
                Text("7 Days Free")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.brandText)

                Text("Then \(monthlyPrice)/mo  ·  Cancel Anytime")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
        }
    }

    // MARK: - Lifetime Perks

    private var lifetimePerks: some View {
        VStack(spacing: 40) {
            VStack(alignment: .leading, spacing: 24) {
                perkRow(
                    emoji: "🎙️",
                    title: "Capture Without Limits",
                    subtitle: "Unlimited recordings and uploads."
                )
                perkRow(
                    emoji: "🪄",
                    title: "Notes That Write Themselves",
                    subtitle: "Talk messy, read clean. Every time."
                )
                perkRow(
                    emoji: "💎",
                    title: "Pay Once, Own it Forever",
                    subtitle: "Full Pro access. No subscriptions."
                )
            }
            .padding(.horizontal, 8)

            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(lifetimePrice)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(colorScheme == .dark ? Color(hex: "#34D399") : Color.brandText)

                    Text("$59.99")
                        .font(.callout)
                        .strikethrough()
                        .foregroundStyle(.secondary)
                }

                Text("Introductory Price  ·  Lifetime Access")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
        }
    }

    private func perkRow(emoji: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.brand.opacity(colorScheme == .dark ? 0.25 : 0.12))
                    .frame(width: 48, height: 48)
                Text(emoji)
                    .font(.title3)
            }
            .frame(width: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.55))
            }
            .padding(.top, 4)

            Spacer()
        }
    }

    private func timelineNode(
        emoji: String,
        title: String,
        subtitle: String,
        isLast: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(Color.brand.opacity(colorScheme == .dark ? 0.25 : 0.12))
                        .frame(width: 48, height: 48)
                    Text(emoji)
                        .font(.title3)
                }

                if !isLast {
                    Rectangle()
                        .fill(Color.brand.opacity(0.18))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.55))
            }
            .padding(.top, 4)
            .padding(.bottom, isLast ? 0 : 24)

            Spacer()
        }
    }

    // MARK: - Action Stack

    private var actionStack: some View {
        VStack(spacing: 12) {
            if isProcessing {
                ProgressView()
                    .frame(height: 56)
            } else if isAuthenticatedUser {
                subscribeButton
            } else {
                // Not signed in or guest — show auth buttons
                SignInWithAppleButton(.continue) { request in
                    awaitingPurchaseAfterAuth = true
                    authStore.appleSignInRequest(request)
                } onCompletion: { result in
                    Task { await authStore.handleAppleSignIn(result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 56)
                .clipShape(Capsule())

                Button {
                    awaitingPurchaseAfterAuth = true
                    showEmailForm = true
                } label: {
                    Text("Continue with Email")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }

        }
    }

    // MARK: - Subscribe Button (for authenticated users)

    private var subscribeButton: some View {
        Button {
            Task {
                guard let product = selectedProduct else {
                    errorMessage = "Products not available. Please try again later."
                    return
                }
                do {
                    let startedTrial = effectiveSelectedPlan == .monthly && subscriptionStore.isTrialEligible
                    try await subscriptionStore.purchase(product)
                    if subscriptionStore.isPro {
                        onPurchaseCompleted(effectiveSelectedPlan, startedTrial)
                    }
                } catch {
                    errorMessage = "Purchase failed: \(error.localizedDescription)"
                }
            }
        } label: {
            Text(subscribeButtonTitle)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .foregroundStyle(.white)
                .background(Color.brand, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var subscribeButtonTitle: String {
        switch effectiveSelectedPlan {
        case .monthly:
            subscriptionStore.isTrialEligible ? "Try Free for 7 Days" : "Subscribe · \(monthlyPrice)/mo"
        case .lifetime:
            "Buy Lifetime · \(lifetimePrice)"
        }
    }

    // MARK: - Purchase Logic (for auth → purchase flow)

    private func attemptPurchaseIfReady() {
        guard authStore.isAuthenticated,
              subscriptionStore.hasProducts,
              subscriptionStore.entitlementChecked
        else { return }

        awaitingPurchaseAfterAuth = false
        Task {
            if subscriptionStore.isPro {
                onRestored()
                return
            }

            guard let product = selectedProduct else {
                errorMessage = "Products not available. Please try again later."
                return
            }
            do {
                let startedTrial = effectiveSelectedPlan == .monthly && subscriptionStore.isTrialEligible
                try await subscriptionStore.purchase(product)
                if subscriptionStore.isPro {
                    onPurchaseCompleted(effectiveSelectedPlan, startedTrial)
                }
            } catch {
                errorMessage = "Purchase failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Legal Footer

    private var legalFooter: some View {
        HStack(spacing: 0) {
            legalButton("Restore Purchase") {
                Task {
                    do {
                        try await subscriptionStore.restorePurchases()
                        if subscriptionStore.isPro {
                            onRestored()
                        } else {
                            errorMessage = "No active subscription found."
                        }
                    } catch {
                        errorMessage = "Restore failed: \(error.localizedDescription)"
                    }
                }
            }

            Text("·")
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)

            legalButton("Terms") { openURL(AppConfig.termsOfUseURL) }

            Text("·")
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)

            legalButton("Privacy") { openURL(AppConfig.privacyPolicyURL) }
        }
        .font(.caption)
    }

    private func legalButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}

private struct ConcaveArchShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let archRadius = rect.width * 0.45
        let archCenter = CGPoint(x: rect.midX, y: rect.minY)

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: archCenter.x - archRadius, y: rect.minY))
        path.addArc(
            center: archCenter,
            radius: archRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
