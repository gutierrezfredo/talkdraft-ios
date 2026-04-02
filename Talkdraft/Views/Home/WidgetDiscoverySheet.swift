import SwiftUI

struct WidgetDiscoverySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 20) {
            Image("luna-widget-promo")
                .resizable()
                .scaledToFit()
                .frame(height: 240)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.75),
                            .init(color: .black.opacity(0), location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .padding(.top, 24)
                .padding(.bottom, -8)

            VStack(spacing: 6) {
                Text("Record in one tap")
                    .font(.brandTitle)
                    .fontDesign(nil)

                Text("Users with widgets are 50% more likely to stay organized. 👀")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .padding(.bottom, 12)

            // How-to steps
            VStack(alignment: .leading, spacing: 16) {
                howToStep(emoji: "👆", text: "Long-press anywhere on your Home Screen")
                howToStep(emoji: "🔘", text: "Tap the (+) icon in the top corner")
                howToStep(emoji: "🔍", text: "Search for \"Talkdraft\" and add the widget")
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 4)

            Spacer()

            VStack(spacing: 8) {
                Button {
                    markDismissed()
                    dismiss()
                } label: {
                    Text("Got It")
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.brand, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    markDismissed()
                    dismiss()
                } label: {
                    Text("Maybe Later")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }

    private func howToStep(emoji: String, text: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.brand.opacity(colorScheme == .dark ? 0.25 : 0.12))
                    .frame(width: 44, height: 44)
                Text(emoji)
                    .font(.title3)
            }

            Text(text)
                .font(.subheadline)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Persistence

    static let dismissedKey = "widgetDiscovery.dismissed"

    static var wasDismissed: Bool {
        UserDefaults.standard.bool(forKey: dismissedKey)
    }

    private func markDismissed() {
        UserDefaults.standard.set(true, forKey: Self.dismissedKey)
    }
}
