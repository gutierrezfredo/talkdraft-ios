import AuthenticationServices
import StoreKit
import SwiftUI

struct OnboardingPaywallStep: View {
    let onPurchaseCompleted: (_ startedTrial: Bool) -> Void
    let onRestored: () -> Void
    var onGuestContinue: (() -> Void)?
    var onDismiss: (() -> Void)?

    @Environment(AuthStore.self) private var authStore
    @Environment(SubscriptionStore.self) private var subscriptionStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    @State private var showEmailForm = false
    @State private var awaitingPurchaseAfterAuth = false
    @State private var errorMessage: String?

    private let fallbackYearlyPrice = "$59.99"

    /// User is signed in with a real account (not guest, not unauthenticated)
    private var isAuthenticatedUser: Bool {
        authStore.isAuthenticated && !authStore.isGuest
    }

    private var yearlyPrice: String {
        subscriptionStore.yearlyProduct?.displayPrice ?? fallbackYearlyPrice
    }

    private var monthlyEquivalent: String {
        if let price = subscriptionStore.yearlyProduct?.price {
            let monthly = NSDecimalNumber(decimal: price).doubleValue / 12
            let floored = floor(monthly * 100) / 100
            return String(format: "$%.2f", floored)
        }
        return "$4.99"
    }

    private var isProcessing: Bool {
        subscriptionStore.isLoading
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar (only when dismiss is available)
            if let onDismiss {
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 12)
            }

            ScrollView {
                VStack(spacing: 32) {
                    header
                    trustTimeline
                        .padding(.horizontal, 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            // Action Stack + footer
            VStack(spacing: 12) {
                actionStack
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                if let onGuestContinue {
                    Button(action: onGuestContinue) {
                        Text("Continue as Guest")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

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
    }

    // MARK: - Header

    private var headerBackground: Color {
        colorScheme == .dark ? Color.brand.opacity(0.12) : Color.brand.opacity(0.06)
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

            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.brand)
                Text("Unlimited AI transcription")
            }
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.brand.opacity(colorScheme == .dark ? 0.15 : 0.08), in: Capsule())
            .padding(.top, 4)
            .padding(.bottom, 2)
        }
        .background(alignment: .bottom) {
            ConcaveArchShape()
                .fill(headerBackground)
                .frame(height: 2000)
                .padding(.horizontal, -300)
                .offset(y: 1480)
        }
    }

    // MARK: - Trust Timeline

    private var trustTimeline: some View {
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
                emoji: "🪄",
                title: "Day 7 — Subscription Begins",
                subtitle: "\(yearlyPrice)/yr · Cancel anytime",
                isLast: true
            )
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
                // Already signed in — show direct subscribe button
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
                    HStack(spacing: 10) {
                        Image(systemName: "envelope.fill")
                            .font(.body)
                        Text("Continue with Email")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.darkSurface : .white)
                    )
                }
                .buttonStyle(.plain)
            }

            Text("Start your 7-day free trial. Then \(yearlyPrice)/year (\(monthlyEquivalent)/mo).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Subscribe Button (for authenticated users)

    private var subscribeButton: some View {
        Button {
            Task {
                guard let product = subscriptionStore.yearlyProduct else {
                    errorMessage = "Products not available. Please try again later."
                    return
                }
                do {
                    let startedTrial = subscriptionStore.isTrialEligible
                    try await subscriptionStore.purchase(product)
                    if subscriptionStore.isPro {
                        onPurchaseCompleted(startedTrial)
                    }
                } catch {
                    errorMessage = "Purchase failed: \(error.localizedDescription)"
                }
            }
        } label: {
            Text(subscriptionStore.isTrialEligible ? "Try Free for 7 Days" : "Continue")
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .foregroundStyle(.white)
                .background(Color.brand, in: Capsule())
        }
        .buttonStyle(.plain)
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

            guard let product = subscriptionStore.yearlyProduct else {
                errorMessage = "Products not available. Please try again later."
                return
            }
            do {
                let startedTrial = subscriptionStore.isTrialEligible
                try await subscriptionStore.purchase(product)
                if subscriptionStore.isPro {
                    onPurchaseCompleted(startedTrial)
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
