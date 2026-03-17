import StoreKit
import SwiftUI

struct OnboardingPaywallStep: View {
    let onPurchaseCompleted: (_ startedTrial: Bool) -> Void
    let onRestored: () -> Void

    @Environment(SubscriptionStore.self) private var subscriptionStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedPlan: PlanOption = .yearly
    @State private var errorMessage: String?

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
                if showsTrialMessaging {
                    trialTimeline
                }
                planSelection
                subscribeButton

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
                }
                .buttonStyle(.plain)
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

    private var bodyBackground: Color {
        colorScheme == .dark ? .darkBackground : .warmBackground
    }

    private var header: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .top) {
                Image("luna-paywall")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                    .accessibilityHidden(true)
                    .zIndex(1)
            }
            .padding(.top, 20)
            .background(alignment: .bottom) {
                ConcaveArchShape()
                    .fill(bodyBackground)
                    .frame(height: 2000)
                    .padding(.horizontal, -300)
                    .offset(y: 1600)
            }

            Text("Unlock the full\nTalkdraft experience")
                .font(.brandTitle)
                .multilineTextAlignment(.center)

            Text(showsTrialMessaging
                 ? "Record longer, organize everything, and start with a free trial."
                 : "Record longer, organize everything, and turn rough notes into something useful.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Feature List

    private var featureList: some View {
        VStack(spacing: 0) {
            featureRow("60-minute recordings", systemImage: "mic.fill")
            Divider().padding(.leading, 52)
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
                title: "Before your trial ends",
                subtitle: "We send a reminder",
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
        .background(Color.secondary.opacity(colorScheme == .dark ? 0.15 : 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func timelineRow(icon: String, title: String, subtitle: String, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon + connecting line
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(cardColor)
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.callout)
                        .foregroundStyle(Color.brand)
                }

                if !isLast {
                    Rectangle()
                        .fill(cardColor)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 36)

            // Text
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
                price: subscriptionStore.yearlyProduct?.displayPrice ?? "$59.99",
                detail: "per year",
                badge: "Save 17%"
            )

            planCard(
                option: .monthly,
                title: "Monthly",
                price: subscriptionStore.monthlyProduct?.displayPrice ?? "$5.99",
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
                    let startedTrial = subscriptionStore.isTrialEligible
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
                .background(Color.brand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(subscriptionStore.isLoading)

            if showsTrialMessaging {
                Text("7-day free trial, then \(selectedPlanPrice)/\(selectedPlanPeriod). Cancel anytime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var selectedPlanPrice: String {
        switch selectedPlan {
        case .monthly: subscriptionStore.monthlyProduct?.displayPrice ?? "$5.99"
        case .yearly: subscriptionStore.yearlyProduct?.displayPrice ?? "$59.99"
        }
    }

    private var selectedPlanPeriod: String {
        switch selectedPlan {
        case .monthly: "month"
        case .yearly: "year"
        }
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
