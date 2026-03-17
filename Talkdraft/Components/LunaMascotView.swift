import SwiftUI

/// Displays a Luna mascot illustration.
struct LunaMascotView: View {
    let pose: LunaPose
    let size: CGFloat

    init(_ pose: LunaPose, size: CGFloat = 180) {
        self.pose = pose
        self.size = size
    }

    var body: some View {
        Image(pose.assetName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Pose Catalog

enum LunaPose: String, CaseIterable {
    case binge
    case box
    case email
    case hobby
    case paywall
    case moon
    case notes
    case read
    case search
    case snack
    case work

    var assetName: String {
        "luna-\(rawValue)"
    }
}
