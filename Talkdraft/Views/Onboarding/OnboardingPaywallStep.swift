import StoreKit
import SwiftUI

struct OnboardingPaywallStep: View {
    let onPurchaseCompleted: (_ startedTrial: Bool) -> Void
    let onRestored: () -> Void

    @Environment(SubscriptionStore.self) private var subscriptionStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var selectedPlan: PlanOption = .yearly
    @State private var errorMessage: String?
    private let fallbackMonthlyPrice = "$7.99"
    private let fallbackYearlyPrice = "$59.99"

    private var cardColor: Color {
        colorScheme == .dark ? .darkSurface : .white
    }

    private var showsTrialMessaging: Bool {
        subscriptionStore.isTrialEligible
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                featureList
                planSelection
                subscribeButton
                subscriptionDetails

                Button {
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
                } label: {
                    Text("Restore Purchases")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
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
            ZStack(alignment: .top) {
                LunaMascotView(.paywall, size: 125)
                    .zIndex(1)
            }
            .padding(.top, 20)
            .background(alignment: .bottom) {
                ConcaveArchShape()
                    .fill(headerBackground)
                    .frame(height: 2000)
                    .padding(.horizontal, -300)
                    .offset(y: 1615)
            }

            Text("Unlock the full\nTalkdraft experience")
                .font(.brandTitle)
                .fontDesign(nil)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Feature List

    private var featureList: some View {
        VStack(spacing: 0) {
            featureRow("Unlimited notes and categories", systemImage: "note.text")
            Divider().padding(.leading, 52)
            featureRow("AI rewrites for summaries, action items, and more", systemImage: "wand.and.stars")
            Divider().padding(.leading, 52)
            featureRow("Multi-speaker transcription", systemImage: "person.2.fill")
        }
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func featureRow(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.brand.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: systemImage)
                    .font(.callout)
                    .foregroundStyle(Color.brand)
            }
            .frame(width: 36)

            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Trial Timeline

    private var trialTimeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("How your free trial works")
                .font(.headline)
                .padding(.bottom, 16)

            timelineRow(
                icon: "gift.fill",
                title: "Today",
                subtitle: "Full access starts",
                isLast: false
            )
            timelineRow(
                icon: "bell.fill",
                title: "Before renewal",
                subtitle: "Cancel anytime in Apple ID Settings",
                isLast: false
            )
            timelineRow(
                icon: "creditcard.fill",
                title: "After 7 days",
                subtitle: "Your subscription begins unless canceled",
                isLast: true
            )
        }
        .padding(16)
    }

    private func timelineRow(icon: String, title: String, subtitle: String, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(Color.brand.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.callout)
                        .foregroundStyle(Color.brand)
                }

                if !isLast {
                    Rectangle()
                        .fill(Color.brand.opacity(0.2))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, isLast ? 0 : 20)

            Spacer()
        }
    }

    // MARK: - Plan Selection

    private var planSelection: some View {
        VStack(spacing: 12) {
            planCard(
                option: .yearly,
                title: "Yearly",
                price: subscriptionStore.yearlyProduct?.displayPrice ?? fallbackYearlyPrice,
                detail: "per year",
                badge: yearlyBadgeText
            )

            planCard(
                option: .monthly,
                title: "Monthly",
                price: subscriptionStore.monthlyProduct?.displayPrice ?? fallbackMonthlyPrice,
                detail: "per month",
                badge: nil
            )
        }
    }

    private func planCard(option: PlanOption, title: String, price: String, detail: String, badge: String?) -> some View {
        Button {
            withAnimation(.snappy) { selectedPlan = option }
        } label: {
            HStack(spacing: 14) {
                Circle()
                    .strokeBorder(selectedPlan == option ? Color.brand : .secondary.opacity(0.3), lineWidth: 2)
                    .frame(width: 24, height: 24)
                    .overlay {
                        if selectedPlan == option {
                            Circle()
                                .fill(Color.brand)
                                .frame(width: 14, height: 14)
                        }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        if let badge {
                            Text(badge)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.brand)
                                .clipShape(Capsule())
                        }
                    }

                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(price)
                    .font(.body)
                    .fontWeight(.bold)
                    .foregroundStyle(selectedPlan == option ? Color.brand : .primary)
            }
            .padding(16)
            .background(cardColor)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selectedPlan == option ? Color.brand : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selectedPlan)
    }

    // MARK: - Subscribe Button

    private var subscribeButton: some View {
        VStack(spacing: 8) {
            Button {
                Task {
                    let startedTrial = showsTrialMessaging
                    let product: StoreKit.Product? = switch selectedPlan {
                    case .monthly: subscriptionStore.monthlyProduct
                    case .yearly: subscriptionStore.yearlyProduct
                    }
                    guard let product else {
                        errorMessage = "Products not available. Please try again later."
                        return
                    }
                    do {
                        try await subscriptionStore.purchase(product)
                        if subscriptionStore.isPro {
                            onPurchaseCompleted(startedTrial)
                        }
                    } catch {
                        errorMessage = "Purchase failed: \(error.localizedDescription)"
                    }
                }
            } label: {
                Group {
                    if subscriptionStore.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(showsTrialMessaging ? "Start Free Trial" : "Subscribe Now")
                            .fontWeight(.bold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .foregroundStyle(.white)
                .background(Color.brand, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(subscriptionStore.isLoading)

            Text(subscriptionFooterText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var subscriptionDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subscription details")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                subscriptionDetailRow(
                    title: "Plan",
                    detail: "Talkdraft Pro \(selectedPlanTitle) • \(selectedPlanPrice)/\(selectedPlanPeriod)"
                )
                subscriptionDetailRow(
                    title: "Billing",
                    detail: billingDescription
                )
                subscriptionDetailRow(
                    title: "Cancellation",
                    detail: "Manage or cancel anytime in Apple ID Settings."
                )
            }

            HStack(spacing: 12) {
                legalLinkButton("Terms of Use", url: AppConfig.termsOfUseURL)
                legalLinkButton("Privacy Policy", url: AppConfig.privacyPolicyURL)
                legalLinkButton("Manage", url: AppConfig.manageSubscriptionsURL)
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(16)
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func subscriptionDetailRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    private func legalLinkButton(_ title: String, url: URL) -> some View {
        Button(title) {
            openURL(url)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.brand)
    }

    private var selectedPlanPrice: String {
        switch selectedPlan {
        case .monthly: subscriptionStore.monthlyProduct?.displayPrice ?? fallbackMonthlyPrice
        case .yearly: subscriptionStore.yearlyProduct?.displayPrice ?? fallbackYearlyPrice
        }
    }

    private var selectedPlanTitle: String {
        switch selectedPlan {
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        }
    }

    private var yearlyBadgeText: String? {
        guard let monthlyPrice = subscriptionStore.monthlyProduct?.price,
              let yearlyPrice = subscriptionStore.yearlyProduct?.price
        else {
            return "Save 37%"
        }

        let monthly = NSDecimalNumber(decimal: monthlyPrice).doubleValue
        let yearly = NSDecimalNumber(decimal: yearlyPrice).doubleValue
        let annualizedMonthly = monthly * 12
        guard annualizedMonthly > yearly, annualizedMonthly > 0 else { return nil }

        let savings = Int(round((1 - yearly / annualizedMonthly) * 100))
        return savings > 0 ? "Save \(savings)%" : nil
    }

    private var selectedPlanPeriod: String {
        switch selectedPlan {
        case .monthly: "month"
        case .yearly: "year"
        }
    }

    private var billingDescription: String {
        if showsTrialMessaging {
            return "7-day free trial for eligible accounts, then \(selectedPlanPrice)/\(selectedPlanPeriod). Auto-renews unless canceled at least 24 hours before the current period ends."
        }

        return "Auto-renews at \(selectedPlanPrice)/\(selectedPlanPeriod) unless canceled at least 24 hours before the current period ends."
    }

    private var subscriptionFooterText: String {
        if showsTrialMessaging {
            return "7-day free trial, then \(selectedPlanPrice)/\(selectedPlanPeriod). Auto-renews unless canceled at least 24 hours before the current period ends."
        }

        return "Auto-renews at \(selectedPlanPrice)/\(selectedPlanPeriod) unless canceled at least 24 hours before the current period ends."
    }
}

// MARK: - Plan Option

private enum PlanOption {
    case monthly
    case yearly
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
