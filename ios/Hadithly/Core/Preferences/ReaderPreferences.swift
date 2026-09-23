import Foundation

/// BCP 47 fallback: exact locale, base language, then English (docs/PLAN.md).
enum LocaleFallback {
    private static let rtlBaseLanguages: Set<String> = [
        "ar", "fa", "he", "ps", "sd", "ug", "ur", "yi", "ckb", "mzn", "sdh",
    ]

    /// Canonicalizes a BCP 47 tag: "en" → "en", "EN_us" → "en-US",
    /// "pt-br" → "pt-BR", "ES-419" → "es-419", "zh-HANS" → "zh-Hans".
    /// Returns nil for empty, malformed, or oversized input.
    static func canonicalizeLocaleTag(_ tag: String) -> String? {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.count > 35 { return nil }
        let parts = trimmed.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        if parts.count > 8 { return nil }
        guard let language = parts.first, language.range(of: "^[A-Za-z]{2,3}$", options: .regularExpression) != nil else {
            return nil
        }
        var canonical = [language.lowercased()]
        for part in parts.dropFirst() {
            if part.count == 4, part.range(of: "^[A-Za-z]{4}$", options: .regularExpression) != nil {
                canonical.append(part.prefix(1).uppercased() + part.dropFirst().lowercased())
            } else if part.count == 2, part.range(of: "^[A-Za-z]{2}$", options: .regularExpression) != nil {
                canonical.append(part.uppercased())
            } else if part.range(of: "^[A-Za-z0-9]{2,8}$", options: .regularExpression) != nil {
                canonical.append(part.lowercased())
            } else {
                return nil
            }
        }
        let joined = canonical.joined(separator: "-")
        return joined.range(of: "^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$", options: .regularExpression) != nil ? joined : nil
    }

    /// Fallback chain: exact locale, base language, then English.
    static func fallbackChain(for tag: String) -> [String] {
        guard let canonical = canonicalizeLocaleTag(tag) else { return ["en"] }
        let base = String(canonical.split(separator: "-").first ?? "en")
        var chain = canonical == base ? [canonical] : [canonical, base]
        if !chain.contains("en") { chain.append("en") }
        return chain
    }

    /// First entry of the chain present in `supported`, or nil.
    static func resolve(_ tag: String, supported: Set<String>) -> String? {
        for candidate in fallbackChain(for: tag) where supported.contains(candidate) {
            return candidate
        }
        return nil
    }

    static func baseLanguage(of tag: String) -> String {
        guard let canonical = canonicalizeLocaleTag(tag) else {
            return tag.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init)?.lowercased() ?? "en"
        }
        return String(canonical.split(separator: "-").first ?? "en")
    }

    /// True for Arabic, Urdu, Persian, and other RTL-script base languages.
    /// Covers pseudolocales too: "ar-XB" is RTL, "en-XA" is not.
    static func isRTL(_ tag: String) -> Bool {
        rtlBaseLanguages.contains(baseLanguage(of: tag))
    }
}

enum ReadingDirection: String, Codable, CaseIterable {
    case auto
    case rtl
    case ltr
}

enum ReaderTheme: String, Codable, CaseIterable {
    case system
    case light
    case paper
    case dark
}

/// Licensed Arabic font identifiers (docs/FONT_LICENSES.md). Unknown ids
/// decode to `.system` so older builds keep working when newer ones add a
/// licensed face. No font binaries are bundled until R4.
enum ArabicFont: String, Codable, CaseIterable {
    case system
    case amiri
    case scheherazadeNew = "scheherazade-new"
    case notoNaskhArabic = "noto-naskh-arabic"

    init(decoding raw: String?) {
        if let raw, let decoded = ArabicFont(rawValue: raw) {
            self = decoded
        } else {
            self = .system
        }
    }

    var displayName: String {
        switch self {
        case .system: "System"
        case .amiri: "Amiri"
        case .scheherazadeNew: "Scheherazade New"
        case .notoNaskhArabic: "Noto Naskh Arabic"
        }
    }
}

enum HorizontalDirection {
    case rtl
    case ltr
}

/// Direction metadata consumed by R3 paging and R4 layout. Arabic blocks
/// always lay out RTL, including inside mixed pages.
struct DirectionMetadata: Equatable {
    let pageDirection: HorizontalDirection
    let arabicBlocksRTL: Bool
}

struct ReaderPreferences: Codable, Equatable {
    static let schemaVersion = 2
    static let minArabicFontSize: Double = 18
    static let maxArabicFontSize: Double = 40

    var schemaVersion: Int = Self.schemaVersion
    var uiLocale: String = "en"
    var translationLocale: String = "en"
    var readingDirection: ReadingDirection = .auto
    var appTheme: ReaderTheme = .system
    var readerTheme: ReaderTheme = .system
    var usesSeparateReaderTheme: Bool = false
    var arabicFont: ArabicFont = .system
    var arabicFontSize: Double = 26
    var translationFontSize: Double = 16
    var arabicVisible: Bool = true
    var translationVisible: Bool = true
    var updatedAt: Double = 0

    enum CodingKeys: String, CodingKey {
        case schemaVersion, uiLocale, translationLocale, readingDirection
        case theme, appTheme, readerTheme, usesSeparateReaderTheme, arabicFont, arabicFontSize, translationFontSize
        case arabicVisible, translationVisible, updatedAt
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = Self.schemaVersion
        uiLocale = try container.decodeIfPresent(String.self, forKey: .uiLocale) ?? "en"
        translationLocale = try container.decodeIfPresent(String.self, forKey: .translationLocale) ?? "en"
        readingDirection = try container.decodeIfPresent(ReadingDirection.self, forKey: .readingDirection) ?? .auto
        let legacyTheme = try container.decodeIfPresent(ReaderTheme.self, forKey: .theme) ?? .system
        appTheme = try container.decodeIfPresent(ReaderTheme.self, forKey: .appTheme) ?? legacyTheme
        readerTheme = try container.decodeIfPresent(ReaderTheme.self, forKey: .readerTheme) ?? legacyTheme
        usesSeparateReaderTheme = try container.decodeIfPresent(Bool.self, forKey: .usesSeparateReaderTheme) ?? false
        arabicFont = ArabicFont(decoding: try container.decodeIfPresent(String.self, forKey: .arabicFont))
        arabicFontSize = try container.decodeIfPresent(Double.self, forKey: .arabicFontSize) ?? 26
        translationFontSize = min(22, max(14, try container.decodeIfPresent(Double.self, forKey: .translationFontSize) ?? 16))
        arabicVisible = try container.decodeIfPresent(Bool.self, forKey: .arabicVisible) ?? true
        translationVisible = try container.decodeIfPresent(Bool.self, forKey: .translationVisible) ?? true
        updatedAt = try container.decodeIfPresent(Double.self, forKey: .updatedAt) ?? 0
    }

    var theme: ReaderTheme { usesSeparateReaderTheme ? readerTheme : appTheme }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(uiLocale, forKey: .uiLocale)
        try container.encode(translationLocale, forKey: .translationLocale)
        try container.encode(readingDirection, forKey: .readingDirection)
        try container.encode(appTheme, forKey: .appTheme)
        try container.encode(readerTheme, forKey: .readerTheme)
        try container.encode(usesSeparateReaderTheme, forKey: .usesSeparateReaderTheme)
        try container.encode(arabicFont, forKey: .arabicFont)
        try container.encode(arabicFontSize, forKey: .arabicFontSize)
        try container.encode(translationFontSize, forKey: .translationFontSize)
        try container.encode(arabicVisible, forKey: .arabicVisible)
        try container.encode(translationVisible, forKey: .translationVisible)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

enum ReaderPreferencesValidationError: Error, Equatable {
    case allHiddenVisibility
    case invalidLocale(String)
    case invalidArabicFont(String)
}

enum ReaderPreferencesValidator {
    /// Normalizes a preference object at the boundary. Rejects the all-hidden
    /// visibility state in shared domain logic; clamps the font size.
    static func validated(_ preferences: ReaderPreferences) throws -> ReaderPreferences {
        var result = preferences
        guard let ui = LocaleFallback.canonicalizeLocaleTag(preferences.uiLocale) else {
            throw ReaderPreferencesValidationError.invalidLocale(preferences.uiLocale)
        }
        guard let translation = LocaleFallback.canonicalizeLocaleTag(preferences.translationLocale) else {
            throw ReaderPreferencesValidationError.invalidLocale(preferences.translationLocale)
        }
        result.uiLocale = ui
        result.translationLocale = translation
        guard preferences.arabicFont == .system || ArabicFont(rawValue: preferences.arabicFont.rawValue) != nil else {
            throw ReaderPreferencesValidationError.invalidArabicFont(preferences.arabicFont.rawValue)
        }
        if !preferences.arabicVisible && !preferences.translationVisible {
            throw ReaderPreferencesValidationError.allHiddenVisibility
        }
        result.arabicFontSize = min(
            ReaderPreferences.maxArabicFontSize,
            max(ReaderPreferences.minArabicFontSize, preferences.arabicFontSize)
        )
        result.schemaVersion = ReaderPreferences.schemaVersion
        return result
    }

    /// Resolves `auto` direction: RTL for Arabic-only reading, the
    /// translation script for translation-only and mixed pages.
    static func directionMetadata(for preferences: ReaderPreferences) -> DirectionMetadata {
        switch preferences.readingDirection {
        case .rtl:
            return DirectionMetadata(pageDirection: .rtl, arabicBlocksRTL: true)
        case .ltr:
            return DirectionMetadata(pageDirection: .ltr, arabicBlocksRTL: true)
        case .auto:
            let arabicOnly = preferences.arabicVisible && !preferences.translationVisible
            if arabicOnly {
                return DirectionMetadata(pageDirection: .rtl, arabicBlocksRTL: true)
            }
            let translationRTL = LocaleFallback.isRTL(preferences.translationLocale)
            return DirectionMetadata(
                pageDirection: translationRTL ? .rtl : .ltr,
                arabicBlocksRTL: true
            )
        }
    }
}
