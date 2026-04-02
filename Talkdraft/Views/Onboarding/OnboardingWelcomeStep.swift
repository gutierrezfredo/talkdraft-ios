import SwiftUI

struct OnboardingWelcomeStep: View {
    let onNext: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var lunaVisible = false
    @State private var textVisible = false
    @State private var buttonVisible = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Luna hero with soft glow
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.brand.opacity(colorScheme == .dark ? 0.18 : 0.10),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 40,
                            endRadius: 160
                        )
                    )
                    .frame(width: 300, height: 300)

                LunaMascotView(.notes, size: 200)
            }
            .opacity(lunaVisible ? 1 : 0)
            .offset(y: lunaVisible ? 0 : 20)
            .padding(.bottom, 8)

            // Headline + body
            VStack(spacing: 12) {
                Text("Say it messy.\nRead it clean.")
                    .font(.brandLargeTitle)
                    .fontDesign(nil)
                    .multilineTextAlignment(.center)

                Text("Turn your messy voice notes into\nperfectly organized text.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(textVisible ? 1 : 0)
            .offset(y: textVisible ? 0 : 12)

            Spacer()
            Spacer()

            // CTA
            Button(action: onNext) {
                Text("Get Started")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.brand, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .opacity(buttonVisible ? 1 : 0)
            .offset(y: buttonVisible ? 0 : 10)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                lunaVisible = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.25)) {
                textVisible = true
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.5)) {
                buttonVisible = true
            }
        }
    }
}
