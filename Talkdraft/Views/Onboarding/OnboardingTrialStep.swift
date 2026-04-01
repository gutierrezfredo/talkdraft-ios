import SwiftUI

struct OnboardingTrialStep: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 32) {
                    // Luna
                    LunaMascotView(.moon, size: 140)
                        .padding(.top, 32)

                    // Title
                    VStack(spacing: 8) {
                        Text("How your free\ntrial works")
                            .font(.brandTitle)
                            .fontDesign(nil)
                            .multilineTextAlignment(.center)

                        Text("Nothing will be charged today")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Timeline
                    VStack(alignment: .leading, spacing: 0) {
                        trialTimelineRow(
                            icon: "gift.fill",
                            iconColor: Color.brand,
                            title: "Today — Start exploring",
                            subtitle: "7 days of full access, completely free",
                            isLast: false
                        )
                        trialTimelineRow(
                            icon: "bell.fill",
                            iconColor: .orange,
                            title: "Day 5 — Friendly reminder",
                            subtitle: "We'll notify you before your trial ends",
                            isLast: false
                        )
                        trialTimelineRow(
                            icon: "sparkles",
                            iconColor: Color.brand,
                            title: "Day 7 — Keep going",
                            subtitle: "Continue with full access or cancel anytime",
                            isLast: true
                        )
                    }
                    .padding(.horizontal, 8)
                }
                .padding(.horizontal, 24)
            }

            // Bottom CTA
            VStack(spacing: 12) {
                Button(action: onContinue) {
                    Text("Continue")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .foregroundStyle(.white)
                        .background(Color.brand, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Timeline Row

    private func trialTimelineRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        isLast: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(iconColor)
                }

                if !isLast {
                    Rectangle()
                        .fill(Color.brand.opacity(0.2))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, isLast ? 0 : 28)

            Spacer()
        }
    }
}
