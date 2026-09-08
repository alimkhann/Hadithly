import Foundation
import Observation

/// Persists the F2 reader preference contract and performs the one-time
/// migration from the legacy single-language settings. The stored payload is
/// a versioned JSON blob under "reader.preferences.v1"; the legacy keys
/// ("user.preferredLanguage", "reader.arabicFontSize") stay readable for the
/// migration and keep being written for backend compatibility.
@MainActor
@Observable
final class PreferencesStore {
    static let storeKey = "reader.preferences.v1"
    static let legacyLanguageKey = "user.preferredLanguage"
    static let legacyArabicFontSizeKey = "reader.arabicFontSize"

    struct MigrationResult: Equatable {
        let preferences: ReaderPreferences
        /// True when the seed came from the legacy language key.
        let seededFromLegacy: Bool
    }

    private(set) var preferences: ReaderPreferences

    /// Fired after every explicit local change (not after server adoption).
    var onPreferencesChanged: ((ReaderPreferences) -> Void)?

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let legacyLanguage = userDefaults.string(forKey: Self.legacyLanguageKey)
        let legacySize = userDefaults.object(forKey: Self.legacyArabicFontSizeKey) as? Double
        let result = Self.migrate(
            storedJSON: userDefaults.string(forKey: Self.storeKey),
            legacyLanguage: legacyLanguage,
            legacyArabicFontSize: legacySize
        )
        self.preferences = result.preferences
        userDefaults.set(
            (try? JSONEncoder().encode(result.preferences)).map { String(data: $0, encoding: .utf8) } ?? "",
            forKey: Self.storeKey
        )
    }

    /// One-time migration: an existing v1 payload wins (a later explicit
    /// choice is never reset); otherwise both locales seed from the legacy
    /// translation-language setting. With neither source, defaults to en/en.
    nonisolated static func migrate(
        storedJSON: String?,
        legacyLanguage: String?,
        legacyArabicFontSize: Double? = nil
    ) -> MigrationResult {
        if let storedJSON,
           let data = storedJSON.data(using: .utf8),
           let stored = try? JSONDecoder().decode(ReaderPreferences.self, from: data) {
            return MigrationResult(preferences: stored, seededFromLegacy: false)
        }
        if let legacyLanguage,
           let canonical = LocaleFallback.canonicalizeLocaleTag(legacyLanguage) {
            var preferences = ReaderPreferences()
            preferences.uiLocale = canonical
            preferences.translationLocale = canonical
            if let legacyArabicFontSize {
                preferences.arabicFontSize = min(
                    ReaderPreferences.maxArabicFontSize,
                    max(ReaderPreferences.minArabicFontSize, legacyArabicFontSize)
                )
            }
            return MigrationResult(preferences: preferences, seededFromLegacy: true)
        }
        return MigrationResult(preferences: ReaderPreferences(), seededFromLegacy: false)
    }

    // MARK: - Mutations

    /// Onboarding "Choose your language": writes both locales at once.
    func applyOnboardingLanguage(_ code: String) {
        guard let canonical = LocaleFallback.canonicalizeLocaleTag(code) else { return }
        update { preferences in
            preferences.uiLocale = canonical
            preferences.translationLocale = canonical
        }
        userDefaults.set(canonical, forKey: Self.legacyLanguageKey)
    }

    func setUILocale(_ code: String) {
        guard let canonical = LocaleFallback.canonicalizeLocaleTag(code) else { return }
        update { $0.uiLocale = canonical }
    }

    func setTranslationLocale(_ code: String) {
        guard let canonical = LocaleFallback.canonicalizeLocaleTag(code) else { return }
        update { $0.translationLocale = canonical }
        userDefaults.set(canonical, forKey: Self.legacyLanguageKey)
    }

    func setReadingDirection(_ direction: ReadingDirection) {
        update { $0.readingDirection = direction }
    }

    func setTheme(_ theme: ReaderTheme) {
        update { $0.theme = theme }
    }

    func setArabicFont(_ font: ArabicFont) {
        update { $0.arabicFont = font }
    }

    func setArabicFontSize(_ size: Double) {
        update {
            $0.arabicFontSize = min(
                ReaderPreferences.maxArabicFontSize,
                max(ReaderPreferences.minArabicFontSize, size)
            )
        }
    }

    /// Rejects the all-hidden state: the caller receives false instead of a
    /// preference update when both layers would be hidden.
    @discardableResult
    func setVisibility(arabic: Bool? = nil, translation: Bool? = nil) -> Bool {
        let nextArabic = arabic ?? preferences.arabicVisible
        let nextTranslation = translation ?? preferences.translationVisible
        guard nextArabic || nextTranslation else { return false }
        update {
            $0.arabicVisible = nextArabic
            $0.translationVisible = nextTranslation
        }
        return true
    }

    /// Adopts server-side preferences only when they are newer than the
    /// local state (last-write-wins by updatedAt). Does not re-emit
    /// onPreferencesChanged (no sync loop).
    func adoptServer(_ incoming: ReaderPreferences) {
        guard let validated = try? ReaderPreferencesValidator.validated(incoming) else { return }
        guard validated.updatedAt > preferences.updatedAt else { return }
        preferences = validated
        persist()
        userDefaults.set(validated.translationLocale, forKey: Self.legacyLanguageKey)
    }

    // MARK: - Internals

    private func update(_ mutate: (inout ReaderPreferences) -> Void) {
        var next = preferences
        mutate(&next)
        next.updatedAt = Date().timeIntervalSince1970 * 1000
        guard let validated = try? ReaderPreferencesValidator.validated(next) else { return }
        preferences = validated
        persist()
        onPreferencesChanged?(validated)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        userDefaults.set(String(data: data, encoding: .utf8) ?? "", forKey: Self.storeKey)
    }
}
