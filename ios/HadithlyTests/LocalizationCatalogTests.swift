import XCTest
@testable import Hadithly

/// Proves the String Catalog foundations compile from source: the F2 keys
/// exist with English, Arabic, and Urdu localizations, and the plural fixture
/// carries the Arabic plural categories.
final class LocalizationCatalogTests: XCTestCase {
    func testFormattedLabelsUseBaseLocaleFallbackAndPreserveSourceArguments() {
        XCTAssertEqual(AppLocalization.format("Next page, %1$@", locale: Locale(identifier: "fr-CA"), "Source %lld %@"), "Page suivante, Source %lld %@")
        XCTAssertEqual(AppLocalization.format("Next page, %1$@", locale: Locale(identifier: "zz-ZZ"), "Source %lld %@"), "Next page, Source %lld %@")
        XCTAssertEqual(AppLocalization.string("page", locale: Locale(identifier: "id-ID")), "halaman")
    }

    func testCompiledCountCategoriesMatchScopedDraftsInEveryLocale() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("docs/a4-plural-copy.json")
        let data = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: source)) as? [String: Any])
        let repairs = try XCTUnwrap(data["ios_repairs"] as? [String: [String: Any]])
        let counts = [0, 1, 2, 3, 11, 21, 100, 102]
        for (key, repair) in repairs {
            let localizations = try XCTUnwrap(repair["plural_localizations"] as? [String: [String: String]])
            for (tag, forms) in localizations {
                let locale = Locale(identifier: tag)
                for count in counts {
                    let quantity: String
                    switch tag {
                    case "ar": quantity = count == 0 ? "zero" : count == 1 ? "one" : count == 2 ? "two" : (3...10).contains(count % 100) ? "few" : (11...99).contains(count % 100) ? "many" : "other"
                    case "ru": quantity = count % 10 == 1 && count % 100 != 11 ? "one" : (2...4).contains(count % 10) && !(12...14).contains(count % 100) ? "few" : "many"
                    case "fr", "pt-BR", "hi", "bn": quantity = count <= 1 ? "one" : "other"
                    case "id": quantity = "other"
                    default: quantity = count == 1 ? "one" : "other"
                    }
                    let template = try XCTUnwrap(forms[quantity], "\(tag):\(quantity)")
                    let expected = String(format: template, locale: locale, arguments: [count])
                    XCTAssertEqual(AppLocalization.format(key, locale: locale, count), expected, "\(key):\(tag):\(count)")
                }
            }
        }
    }

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
