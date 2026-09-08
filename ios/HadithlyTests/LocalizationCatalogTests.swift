import XCTest
@testable import Hadithly

/// Proves the String Catalog foundations compile from source: the F2 keys
/// exist with English, Arabic, and Urdu localizations, and the plural fixture
/// carries the Arabic plural categories.
final class LocalizationCatalogTests: XCTestCase {
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
