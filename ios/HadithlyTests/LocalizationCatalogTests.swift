import XCTest
@testable import Hadithly

/// Proves the String Catalog foundations compile from source: the F2 keys
/// exist with English, Arabic, and Urdu localizations, and the plural fixture
/// carries the Arabic plural categories.
final class LocalizationCatalogTests: XCTestCase {
    func testFirstReadingDecodesTheActualBackendFixtures() throws {
        for name in ["starter-en", "starter-ru", "daily-ru", "original-ar"] {
            let outcome = try JSONDecoder().decode(FirstReadingResult.self, from: firstReadingFixture(name))
            guard case .ready(let ready) = outcome else { return XCTFail("Expected ready fixture") }
            XCTAssertEqual(ready.locale, ready.reading.text.language)
            XCTAssertFalse(ready.reading.text.text.isEmpty)
            XCTAssertEqual(ready.reading.canonicalId, "\(ready.reading.provider):\(ready.reading.collectionSlug):\(ready.reading.providerHadithId)")
        }
        XCTAssertEqual(try JSONDecoder().decode(FirstReadingResult.self, from: firstReadingFixture("unavailable-ru")), .unavailable)
    }

    func testFirstReadingRejectsWrongLanguageAndFalseDailyIdentity() throws {
        let data = try firstReadingFixture("starter-ru")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["locale"] = "fr"
        XCTAssertThrowsError(try JSONDecoder().decode(FirstReadingResult.self, from: JSONSerialization.data(withJSONObject: object)))
        object["locale"] = "ru"
        object["origin"] = "daily"
        XCTAssertThrowsError(try JSONDecoder().decode(FirstReadingResult.self, from: JSONSerialization.data(withJSONObject: object)))
    }

    func testFirstReadingRejectsAnUnsupportedReaderProvider() throws {
        let source = try String(decoding: firstReadingFixture("starter-en"), as: UTF8.self)
        XCTAssertThrowsError(try JSONDecoder().decode(FirstReadingResult.self, from: Data(source.replacingOccurrences(of: "sunnah_now", with: "sunnah_com").utf8)))
    }

    private func firstReadingFixture(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("testdata/first-reading/\(name).json"))
    }

    func testSelectedLocaleResolvesShellAndDynamicNavigationTitles() {
        XCTAssertEqual(AppLocalization.string("Today", locale: Locale(identifier: "ar")), "اليوم")
        XCTAssertEqual(AppLocalization.string("Settings", locale: Locale(identifier: "ur")), "ترتیبات")
        XCTAssertEqual(AppLocalization.string("App language", locale: Locale(identifier: "ar")), "لغة التطبيق")
        XCTAssertEqual(AppLocalization.string("Today", locale: Locale(identifier: "en")), "Today")
        XCTAssertEqual(AppLocalization.string("Today", locale: Locale(identifier: "fr")), "Aujourd’hui")
    }

    private func catalogJSON() throws -> [String: Any] {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Hadithly/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func localizations(for key: String, in catalog: [String: Any]) throws -> [String: Any] {
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let entry = try XCTUnwrap(strings[key] as? [String: Any], "missing key \(key)")
        return try XCTUnwrap(entry["localizations"] as? [String: Any])
    }

    func testCatalogParsesWithEnglishSource() throws {
        let catalog = try catalogJSON()
        XCTAssertEqual(try XCTUnwrap(catalog["sourceLanguage"] as? String), "en")
    }

    func testEveryWaveOneLocaleHasEveryCatalogKey() throws {
        let catalog = try catalogJSON()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let locales = ["en", "ar", "ru", "kk", "ky", "uz", "tr", "id", "ur", "fr", "es-419", "pt-BR", "sw", "hi", "bn"]
        for (key, rawEntry) in strings {
            let entry = try XCTUnwrap(rawEntry as? [String: Any])
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], "missing localizations for \(key)")
            for locale in locales {
                XCTAssertNotNil(localizations[locale], "\(key) lacks \(locale)")
            }
        }
    }

    func testF2KeysHaveArabicAndUrduUnitTranslations() throws {
        let catalog = try catalogJSON()
        let keys = [
            "Choose your language",
            "You can change this any time in Settings.",
            "Continue",
            "Reading",
            "Arabic type size",
            "App language",
            "Hadith translation",
            "Reading direction",
            "Arabic text",
            "Translation",
            "Automatic",
            "Right to left",
            "Left to right",
        ]
        for key in keys {
            let localizations = try localizations(for: key, in: catalog)
            XCTAssertNotNil(localizations["ar"], "\(key) lacks Arabic")
            XCTAssertNotNil(localizations["ur"], "\(key) lacks Urdu")
        }
    }

    func testPluralFixtureCoversArabicAndUrduCategories() throws {
        let catalog = try catalogJSON()
        let localizations = try localizations(
            for: "%lld languages available",
            in: catalog
        )
        for (locale, expected) in [
            ("ar", ["zero", "one", "two", "few", "many", "other"]),
            ("en", ["one", "other"]),
            ("ur", ["one", "other"]),
        ] {
            let entry = try XCTUnwrap(localizations[locale] as? [String: Any])
            let variations = try XCTUnwrap(entry["variations"] as? [String: Any])
            let plural = try XCTUnwrap(variations["plural"] as? [String: Any])
            for quantity in expected {
                XCTAssertNotNil(plural[quantity], "\(locale) plural misses \(quantity)")
            }
        }
    }

    func testCompiledAppBundleResolvesArabicAndUrduStrings() throws {
        // The test host is the app bundle, so its generated .lproj folders
        // prove the catalog compiled into real localizations.
        for (code, key, expectedPrefix) in [
            ("ar", "Choose your language", "اختر"),
            ("ur", "Choose your language", "اپنی"),
        ] {
            let path = try XCTUnwrap(
                Bundle.main.path(forResource: code, ofType: "lproj"),
                "missing \(code).lproj in app bundle"
            )
            let bundle = try XCTUnwrap(Bundle(path: path))
            let value = bundle.localizedString(forKey: key, value: key, table: nil)
            XCTAssertTrue(
                value.hasPrefix(expectedPrefix),
                "\(code) resolved '\(value)' for '\(key)'"
            )
        }
    }
}
