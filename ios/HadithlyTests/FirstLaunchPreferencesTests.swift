import XCTest
@testable import Hadithly

@MainActor
final class FirstLaunchPreferencesTests: XCTestCase {
    func testEveryOfferedLanguageCanBeDetectedBeforeWelcome() {
        let cases = [("en-US", "en"), ("ar-SA", "ar"), ("ru-RU", "ru"), ("kk-KZ", "kk"), ("ky-KG", "ky"), ("uz-Latn-UZ", "uz"), ("tr-TR", "tr"), ("id-ID", "id"), ("ur-PK", "ur"), ("fr-FR", "fr"), ("es-MX", "es-419"), ("pt-PT", "pt-BR"), ("sw-KE", "sw"), ("hi-IN", "hi"), ("bn-BD", "bn")]
        for (device, expected) in cases { XCTAssertEqual(PreferencesStore.suggestedLanguage([device]), expected, device) }
        XCTAssertEqual(PreferencesStore.suggestedLanguage(["de-DE", "fr-CA", "en-US"]), "fr")
    }

    func testFreshStoreFollowsSystemAndPreservesLaterChoice() {
        let suite = "first-launch-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = PreferencesStore(userDefaults: defaults, preferredLanguages: ["ru-RU"])
        XCTAssertEqual(first.preferences.appTheme, .system)
        XCTAssertEqual(first.preferences.uiLocale, "ru")
        XCTAssertEqual(first.preferences.translationLocale, "ru")
        first.setTheme(.paper)
        first.setUILocale("kk")
        let reopened = PreferencesStore(userDefaults: defaults, preferredLanguages: ["fr-FR"])
        XCTAssertEqual(reopened.preferences.appTheme, .paper)
        XCTAssertEqual(reopened.preferences.uiLocale, "kk")
    }
}
