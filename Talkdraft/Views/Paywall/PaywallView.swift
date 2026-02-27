import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(SubscriptionStore.self) private var subscriptionStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlan: PlanOption = .yearly
    @State private var errorMessage: String?

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
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .background(backgroundColor.ignoresSafeArea())
            .navigationTitle("Upgrade to Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.semibold)
                    }
                }
            }
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

            Text("Unlock the full experience")
                .font(.title3)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("Longer recordings, unlimited notes, and more.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Feature Comparison

    private var featureComparison: some View {
        VStack(spacing: 0) {
            featureRow("Recording length", free: "3 min", pro: "15 min")
            Divider().padding(.leading, 16)
            featureRow("Notes", free: "50", pro: "Unlimited")
            Divider().padding(.leading, 16)
            featureRow("Categories", free: "4", pro: "Unlimited")
            Divider().padding(.leading, 16)
            featureRow("AI titles", free: "Included", pro: "Included")
        }
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func featureRow(_ feature: String, free: String, pro: String) -> some View {
        HStack {
            Text(feature)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(free)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70)

            Text(pro)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.brand)
                .frame(width: 70)
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
                    Text("Subscribe")
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
    }
}

// MARK: - Plan Option

private enum PlanOption {
    case monthly
    case yearly
}
