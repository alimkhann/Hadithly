import SwiftUI

/// Resolved reader color palette (R4). The reader honors the F2 `ReaderTheme`
/// preference: System follows the OS appearance, Light, Paper, and Dark are
/// explicit. Accent, bookmark, favorite, and destructive stay shared tokens.
struct ReaderPalette: Equatable {
    let background: Color
    let surface: Color
    let surfaceElevated: Color
    let textPrimary: Color
    let textSecondary: Color
    let divider: Color

    static let dark = ReaderPalette(
        background: Theme.background,
        surface: Theme.surface,
        surfaceElevated: Theme.surfaceElevated,
        textPrimary: Theme.textPrimary,
        textSecondary: Theme.textSecondary,
        divider: Color(hex: "2A2A2C")
    )

    static let light = ReaderPalette(
        background: Color(hex: "FFFFFF"),
        surface: Color(hex: "F4F4F2"),
        surfaceElevated: Color(hex: "E9E9E6"),
        textPrimary: Color(hex: "1C1C1E"),
        textSecondary: Color(hex: "6B6B70"),
        divider: Color(hex: "D9D9D6")
    )

    static let paper = ReaderPalette(
        background: Color(hex: "F6EFDF"),
        surface: Color(hex: "EFE6D0"),
        surfaceElevated: Color(hex: "E5DABE"),
        textPrimary: Color(hex: "33301F"),
        textSecondary: Color(hex: "7A7357"),
        divider: Color(hex: "D6C9A4")
    )

    /// Resolves the stored preference against the current OS appearance.
    static func resolved(_ theme: ReaderTheme, systemDark: Bool) -> ReaderPalette {
        switch theme {
        case .system: systemDark ? .dark : .light
        case .light: .light
        case .paper: .paper
        case .dark: .dark
        }
    }

    /// The color scheme the reader should force for system chrome (status
    /// bar, sheets): System and Dark render dark chrome, Light and Paper
    /// render light chrome.
    static func preferredColorScheme(for theme: ReaderTheme) -> ColorScheme? {
        switch theme {
        case .system: nil
        case .light, .paper: .light
        case .dark: .dark
        }
    }
}

private struct ReaderPaletteKey: EnvironmentKey {
    static let defaultValue: ReaderPalette = .dark
}

private struct ReaderThemeKey: EnvironmentKey {
    static let defaultValue: ReaderTheme = .dark
}

extension EnvironmentValues {
    var readerPalette: ReaderPalette {
        get { self[ReaderPaletteKey.self] }
        set { self[ReaderPaletteKey.self] = newValue }
    }

    /// The stored theme preference, so reader sheets can resolve their own
    /// color scheme. Defaults to dark, matching the pre-R4 reader chrome.
    var readerTheme: ReaderTheme {
        get { self[ReaderThemeKey.self] }
        set { self[ReaderThemeKey.self] = newValue }
    }
}

/// The Arabic type size ladder behind the A−/A+ stepper. Six accessible steps
/// spanning the F2 clamp (18–40 pt).
enum ArabicTypeSize {
    static let steps: [Double] = [18, 22, 26, 30, 34, 40]

    static func nearest(_ size: Double) -> Double {
        steps.min(by: { abs($0 - size) < abs($1 - size) }) ?? ReaderPreferences.defaultArabicFontSize
    }

    static func stepUp(from size: Double) -> Double {
        steps.first(where: { $0 > size + 0.5 }) ?? ReaderPreferences.maxArabicFontSize
    }

    static func stepDown(from size: Double) -> Double {
        steps.last(where: { $0 < size - 0.5 }) ?? ReaderPreferences.minArabicFontSize
    }
}

extension ReaderPreferences {
    static let defaultArabicFontSize: Double = 26

    /// The layout-affecting projection used to recompute the layout signature
    /// and re-anchor the semantic position when reading preferences change.
    var layoutProjection: String {
        [
            translationLocale,
            arabicVisible ? "1" : "0",
            translationVisible ? "1" : "0",
            arabicFont.rawValue,
            String(Int(arabicFontSize * 1000)),
        ].joined(separator: "|")
    }
}
