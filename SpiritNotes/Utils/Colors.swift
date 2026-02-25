import SwiftUI

extension Color {
    /// Brand violet used for accents and primary actions.
    static let brand = Color(hex: "#7C3AED")

    /// Warm light-mode background matching Expo design.
    static let warmBackground = Color(hex: "#F8F2F0")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)

        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double((rgbValue & 0x0000FF)) / 255.0

        self.init(red: r, green: g, blue: b)
    }

    /// Blend this color with the appropriate background at a given opacity.
    /// Used for category-tinted card backgrounds.
    func blended(opacity: Double, isDark: Bool) -> Color {
        let bg: (Double, Double, Double) = isDark ? (10/255, 10/255, 10/255) : (1, 1, 1)
        // Resolve hex-based RGB from the color's components
        let resolved = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)

        let oR = Double(r) * opacity + bg.0 * (1 - opacity)
        let oG = Double(g) * opacity + bg.1 * (1 - opacity)
        let oB = Double(b) * opacity + bg.2 * (1 - opacity)

        return Color(red: oR, green: oG, blue: oB)
    }
}
