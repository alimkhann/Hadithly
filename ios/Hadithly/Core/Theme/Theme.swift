import SwiftUI

/// Design tokens adapted from the Sajda-style reader reference:
/// near-black canvas, elevated dark surfaces, emerald accent, serif Arabic.
enum Theme {
    /// The app's vertical rhythm. Auth screens and onboarding standardize on
    /// these steps so pages share one consistent spacing scale.
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // Canvas & surfaces
    static let background = Color(hex: "0D0D0D")
    static let surface = Color(hex: "1A1A1A")
    static let surfaceElevated = Color(hex: "2A2A2C")

    // Text
    static let textPrimary = Color(hex: "F2F2F2")
    static let textSecondary = Color(hex: "98989E")

    // Accent
    static let accent = Color(hex: "10B981")
    static let accentSoft = Color(hex: "10B981").opacity(0.18)

    // Semantic
    static let bookmark = Color(hex: "F59E0B")
    static let favorite = Color(hex: "EC4899")
    static let destructive = Color(hex: "EF4444")

    // Typography
    static func arabic(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium)
    }
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        var hex = hex
        if hex.hasPrefix("#") { hex.removeFirst() }
        Scanner(string: hex).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}
