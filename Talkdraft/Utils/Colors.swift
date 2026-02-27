import SwiftUI

extension Color {
    /// Brand violet — adaptive: darker in light mode, lighter in dark mode.
    static let brand = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x8B/255, green: 0x5C/255, blue: 0xF6/255, alpha: 1) // #8B5CF6
            : UIColor(red: 0x7C/255, green: 0x3A/255, blue: 0xED/255, alpha: 1) // #7C3AED
    })

    /// Brighter brand violet for text/chips in dark mode — pops more than .brand on dark backgrounds.
    static let brandText = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0xA7/255, green: 0x8B/255, blue: 0xFA/255, alpha: 1) // #A78BFA
            : UIColor(red: 0x7C/255, green: 0x3A/255, blue: 0xED/255, alpha: 1) // #7C3AED
    })

    /// Warm light-mode background matching Expo design.
    static let warmBackground = Color(hex: "#F8F2F0")

    /// Dark-mode background — deep navy with blue-violet undertone.
    static let darkBackground = Color(hex: "#0F1018")

    /// Elevated surface for chips, pills, and cards in dark mode.
    static let darkSurface = Color(hex: "#232538")

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

    /// Adaptive category color — brightens in dark mode so colors pop on dark backgrounds.
    static func categoryColor(hex: String) -> Color {
        Color(UIColor { traits in
            let base = UIColor(Color(hex: hex))
            guard traits.userInterfaceStyle == .dark else { return base }

            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            base.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            return UIColor(hue: h, saturation: s * 0.85, brightness: min(b * 1.25, 1.0), alpha: a)
        })
    }

    /// Blend this color with the appropriate background at a given opacity.
    /// Used for category-tinted card backgrounds.
    func blended(opacity: Double, isDark: Bool) -> Color {
        let bg: (Double, Double, Double) = isDark ? (15/255, 16/255, 24/255) : (1, 1, 1)
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
