import XCTest
@testable import Hadithly

final class PreferencesMigrationTests: XCTestCase {
    private let suiteName = "test.preferences.migration"

    private func makeDefaults() -> UserDefaults {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        return UserDefaults(suiteName: suiteName)!
    }

    func testWithoutLegacyStateSeedsEnglishDefaults() {
        let result = PreferencesStore.migrate(storedJSON: nil, legacyLanguage: nil)
        XCTAssertFalse(result.seededFromLegacy)
        XCTAssertEqual(result.preferences.uiLocale, "en")
        XCTAssertEqual(result.preferences.translationLocale, "en")
    }

    func testLegacyTranslationSettingMigratesToBothLocalesOnce() {
        let result = PreferencesStore.migrate(storedJSON: nil, legacyLanguage: "ur")
        XCTAssertTrue(result.seededFromLegacy)
        XCTAssertEqual(result.preferences.uiLocale, "ur")
        XCTAssertEqual(result.preferences.translationLocale, "ur")
    }

    func testLegacyArabicFontSizeMigratesAndClamps() {
        let result = PreferencesStore.migrate(
            storedJSON: nil,
            legacyLanguage: "en",
            legacyArabicFontSize: 33
        )
        XCTAssertEqual(result.preferences.arabicFontSize, 33)
        let clamped = PreferencesStore.migrate(
            storedJSON: nil,
            legacyLanguage: "en",
            legacyArabicFontSize: 90
        )
        XCTAssertEqual(clamped.preferences.arabicFontSize, 40)
    }

    func testStoredV1PayloadWinsAndLegacyValueDoesNotResetExplicitChoice() throws {
        var explicit = ReaderPreferences()
        explicit.uiLocale = "en"
        explicit.translationLocale = "ar"
        explicit.theme = .paper
        explicit.updatedAt = 500
        let stored = String(data: try JSONEncoder().encode(explicit), encoding: .utf8)

        let result = PreferencesStore.migrate(
            storedJSON: stored,
            legacyLanguage: "ur"
        )
        XCTAssertFalse(result.seededFromLegacy)
        XCTAssertEqual(result.preferences.translationLocale, "ar")
        XCTAssertEqual(result.preferences.theme, .paper)
        XCTAssertEqual(result.preferences.updatedAt, 500)
    }

    func testCorruptStoredPayloadFallsBackToLegacySeed() {
        let result = PreferencesStore.migrate(
            storedJSON: "{not json",
            legacyLanguage: "ar"
        )
        XCTAssertTrue(result.seededFromLegacy)
        XCTAssertEqual(result.preferences.uiLocale, "ar")
        XCTAssertEqual(result.preferences.translationLocale, "ar")
    }

    @MainActor
    func testStorePersistsChangesAndWritesLegacyKeyForBackend() {
        let defaults = makeDefaults()
        defaults.set("ur", forKey: PreferencesStore.legacyLanguageKey)
        let store = PreferencesStore(userDefaults: defaults)

        XCTAssertEqual(store.preferences.uiLocale, "ur")
        XCTAssertEqual(store.preferences.translationLocale, "ur")

        store.setTranslationLocale("ar")
        XCTAssertEqual(store.preferences.translationLocale, "ar")
        XCTAssertEqual(store.preferences.uiLocale, "ur")
        XCTAssertEqual(
            defaults.string(forKey: PreferencesStore.legacyLanguageKey),
            "ar"
        )
        let stored = defaults.string(forKey: PreferencesStore.storeKey) ?? ""
        XCTAssertTrue(stored.contains("\"ar\""))

        // Reloading the store must not reset the explicit choice.
        let reloaded = PreferencesStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.preferences.translationLocale, "ar")
    }

    @MainActor
    func testStoreRejectsAllHiddenVisibilityAndEmitsChanges() {
        let defaults = makeDefaults()
        var emitted: ReaderPreferences?
        let store = PreferencesStore(userDefaults: defaults)
        store.onPreferencesChanged = { emitted = $0 }

        XCTAssertTrue(store.setVisibility(arabic: false, translation: true))
        XCTAssertFalse(store.preferences.arabicVisible)
        XCTAssertNotNil(emitted)

        // The last visible layer cannot be hidden.
        XCTAssertFalse(store.setVisibility(arabic: false, translation: false))
        XCTAssertFalse(store.preferences.arabicVisible)
        XCTAssertTrue(store.preferences.translationVisible)
        XCTAssertTrue(store.setVisibility(arabic: true, translation: true))
    }

    @MainActor
    func testOnboardingWritesBothLocales() {
        let defaults = makeDefaults()
        let store = PreferencesStore(userDefaults: defaults)
        store.applyOnboardingLanguage("ar")
        XCTAssertEqual(store.preferences.uiLocale, "ar")
        XCTAssertEqual(store.preferences.translationLocale, "ar")
        XCTAssertEqual(defaults.string(forKey: PreferencesStore.legacyLanguageKey), "ar")
    }

    @MainActor
    func testAdoptServerAppliesNewerServerStateWithoutEmitting() {
        let defaults = makeDefaults()
        var emitCount = 0
        let store = PreferencesStore(userDefaults: defaults)
        store.onPreferencesChanged = { _ in emitCount += 1 }

        var server = ReaderPreferences()
        server.translationLocale = "ar"
        server.theme = .paper
        server.updatedAt = Date().timeIntervalSince1970 * 1000 + 60_000

        store.adoptServer(server)
        XCTAssertEqual(store.preferences.translationLocale, "ar")
        XCTAssertEqual(store.preferences.theme, .paper)
        XCTAssertEqual(emitCount, 0)

        // An older server row never overrides a newer local choice.
        var older = ReaderPreferences()
        older.updatedAt = 1
        store.setTranslationLocale("ur")
        store.adoptServer(older)
        XCTAssertEqual(store.preferences.translationLocale, "ur")
    }
}
