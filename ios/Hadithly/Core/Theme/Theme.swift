import SwiftUI
import Observation

/// Design tokens: near-black canvas, elevated dark surfaces, neutral-white
/// accent, serif Arabic. Hierarchy comes from luminance, not hue.
enum Theme {
    /// The app root resolves this from its SwiftUI environment. Existing views
    /// still consume the shared semantic names below, while no view consults
    /// UserDefaults or UIKit traits to decide its own palette.
    @Observable
    final class PaletteState {
        var palette = ReaderPalette.dark
    }

    private static let state = PaletteState()

    static func install(_ palette: ReaderPalette) {
        state.palette = palette
    }
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
    static var background: Color { state.palette.background }
    static var surface: Color { state.palette.surface }
    static var surfaceElevated: Color { state.palette.surfaceElevated }

    // Text
    static var textPrimary: Color { state.palette.textPrimary }
    static var textSecondary: Color { state.palette.textSecondary }

    // Accent: neutral white. Hierarchy comes from luminance, not hue
    // (achromatic system); emerald survives only as a semantic color for
    // the brand mark, authenticity grade dots, and success states.
    static var accent: Color { state.palette.interactive }
    static var onInteractive: Color { state.palette.onInteractive }
    static var accentSoft: Color { state.palette.interactiveSoft }

    /// Semantic-only emerald: the brand mark. Never used for chrome.
    static let brand = Color(hex: "10B981")

    // Semantic
    static let bookmark = Color(hex: "F59E0B")
    static let favorite = Color(hex: "EC4899")
    static let destructive = Color(hex: "EF4444")

    // Typography
    /// Arabic reading face. `font` is a licensed id (docs/FONT_LICENSES.md);
    /// unregistered faces degrade to the system fallback automatically.
    static func arabic(_ size: CGFloat, _ font: ArabicFont = .system) -> Font {
        switch font {
        case .system:
            .system(size: size, weight: .medium)
        case .amiri:
            .custom("Amiri-Regular", size: size)
        case .scheherazadeNew:
            .custom("ScheherazadeNew-Regular", size: size)
        case .notoNaskhArabic:
            .custom("NotoNaskhArabic-Regular", size: size)
        }
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
