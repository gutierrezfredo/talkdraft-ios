import StoreKit
import SwiftUI

struct PaywallView: View {
    var mandatory: Bool = false

    @Environment(SubscriptionStore.self) private var subscriptionStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlan: PlanOption = .yearly
    @State private var errorMessage: String?
    private let fallbackMonthlyPrice = "$5.99"
    private let fallbackYearlyPrice = "$59.99"

    private var backgroundColor: Color {
        colorScheme == .dark ? .darkBackground : .warmBackground
    }

    private var cardColor: Color {
        colorScheme == .dark ? .darkSurface : .white
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    featureComparison
                    planSelection
                    subscribeButton

                    Button {
                        Task {
                            do {
                                try await subscriptionStore.restorePurchases()
                                if subscriptionStore.isPro {
                                    dismiss()
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
                .padding(.top, 8)
            }
            .background(backgroundColor.ignoresSafeArea())
            .navigationTitle(subscriptionStore.isTrialEligible ? "Start my free week" : "Go Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !mandatory {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .interactiveDismissDisabled(mandatory)
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .task {
            await subscriptionStore.fetchProducts()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(Color.brand)
                .padding(.top, 16)

            Text("Unlock Full Access")
                .font(.brandTitle2)
                .multilineTextAlignment(.center)

            Text(subscriptionStore.isTrialEligible
                 ? "Start your free trial to create notes, record, and use AI features."
                 : "Subscribe to create notes, record, and use AI features.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Feature Comparison

    private var featureComparison: some View {
        VStack(spacing: 0) {
            featureRow("60-minute recordings", systemImage: "mic.fill")
            Divider().padding(.leading, 52)
            featureRow("Unlimited notes", systemImage: "note.text")
            Divider().padding(.leading, 52)
            featureRow("Unlimited categories", systemImage: "folder.fill")
            Divider().padding(.leading, 52)
            featureRow("AI titles & rewriting", systemImage: "wand.and.stars")
        }
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func featureRow(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(Color.brand)
                .frame(width: 24)
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "checkmark")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.brand)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
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
                            dismiss()
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
                        Text(subscriptionStore.isTrialEligible ? "Start my free week" : "Subscribe now")
                            .fontWeight(.bold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .foregroundStyle(.white)
                .background(Color.brand)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(subscriptionStore.isLoading)

            if subscriptionStore.isTrialEligible {
                Text("7-day free trial, then \(selectedPlanPrice)/\(selectedPlanPeriod). Cancel anytime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var selectedPlanPrice: String {
        switch selectedPlan {
        case .monthly: subscriptionStore.monthlyProduct?.displayPrice ?? fallbackMonthlyPrice
        case .yearly: subscriptionStore.yearlyProduct?.displayPrice ?? fallbackYearlyPrice
        }
    }

    private var yearlyBadgeText: String? {
        guard let monthlyPrice = subscriptionStore.monthlyProduct?.price,
              let yearlyPrice = subscriptionStore.yearlyProduct?.price
        else {
            return "Save 17%"
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
}

// MARK: - Plan Option

private enum PlanOption {
    case monthly
    case yearly
}
