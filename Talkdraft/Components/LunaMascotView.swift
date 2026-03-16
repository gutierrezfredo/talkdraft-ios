import SwiftUI

/// Displays a Luna mascot illustration with subtle sleeping animations:
/// gentle breathing (scale pulse) and floating "z" letters above her head.
struct LunaMascotView: View {
    let pose: LunaPose
    let size: CGFloat

    init(_ pose: LunaPose, size: CGFloat = 180) {
        self.pose = pose
        self.size = size
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Floating Z's
            ZStack {
                floatingZ(delay: 0.0, xOffset: zBaseX)
                floatingZ(delay: 1.2, xOffset: zBaseX + 10)
                floatingZ(delay: 2.4, xOffset: zBaseX - 6)
            }
            .frame(width: size, height: size * 0.4)
            .offset(y: size * 0.05)

            Image(pose.assetName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }

    private var zBaseX: CGFloat {
        switch pose.zPosition {
        case .left: return -size * 0.3
        case .center: return 0
        case .right: return size * 0.3
        }
    }

    private func floatingZ(delay: Double, xOffset: CGFloat) -> some View {
        FloatingZView(delay: delay)
            .offset(x: xOffset)
    }
}

// MARK: - Floating Z

private struct FloatingZView: View {
    let delay: Double

    @State private var visible = false
    @State private var animate = false

    var body: some View {
        Text("z")
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .opacity(visible ? (animate ? 0 : 0.7) : 0)
            .offset(y: animate ? -30 : 0)
            .scaleEffect(animate ? 0.6 : 1.0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear {
                Task {
                    try? await Task.sleep(for: .seconds(delay))
                    visible = true
                    withAnimation(
                        .easeOut(duration: 2.0)
                        .repeatForever(autoreverses: false)
                    ) {
                        animate = true
                    }
                }
            }
    }
}

// MARK: - Pose Catalog

enum LunaPose: String, CaseIterable {
    case binge
    case box
    case email
    case headphone
    case hobby
    case moon
    case read
    case search
    case snack
    case work

    var assetName: String {
        "luna-\(rawValue)"
    }

    enum ZPosition {
        case left, center, right
    }

    var zPosition: ZPosition {
        switch self {
        case .read: return .left
        case .box, .snack, .moon: return .center
        default: return .right
        }
    }
}
