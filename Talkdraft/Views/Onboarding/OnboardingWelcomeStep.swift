import SwiftUI

struct OnboardingWelcomeStep: View {
    let onNext: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Luna mascot in brand circle
            ZStack {
                Circle()
                    .fill(Color.brand.opacity(colorScheme == .dark ? 0.20 : 0.12))
                    .frame(width: 220, height: 220)

                LunaMascotView(.notes, size: 180)
            }
            .padding(.bottom, 32)

            // Headline
            Text("Say it messy.\nRead it clean.")
                .font(.brandLargeTitle)
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)

            // Body
            Text("Capture voice notes and quick thoughts, then let Talkdraft turn them into organized notes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            // CTA
            Button {
                onNext()
            } label: {
                Text("Get Started")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.brand, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}
