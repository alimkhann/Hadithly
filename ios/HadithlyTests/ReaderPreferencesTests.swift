import XCTest
@testable import Hadithly

final class ReaderPreferencesTests: XCTestCase {
    func testDefaultsMatchTheContract() {
        let preferences = ReaderPreferences()
        XCTAssertEqual(preferences.uiLocale, "en")
        XCTAssertEqual(preferences.translationLocale, "en")
        XCTAssertEqual(preferences.readingDirection, .auto)
        XCTAssertEqual(preferences.theme, .system)
        XCTAssertEqual(preferences.arabicFont, .system)
        XCTAssertEqual(preferences.arabicFontSize, 26)
        XCTAssertTrue(preferences.arabicVisible)
        XCTAssertTrue(preferences.translationVisible)
        XCTAssertEqual(preferences.schemaVersion, 1)
    }

    func testValidatedRejectsTheAllHiddenVisibilityState() throws {
        var preferences = ReaderPreferences()
        preferences.arabicVisible = false
        preferences.translationVisible = false
        XCTAssertThrowsError(try ReaderPreferencesValidator.validated(preferences)) { error in
            XCTAssertEqual(
                error as? ReaderPreferencesValidationError,
                .allHiddenVisibility
            )
        }
        // Either single layer alone remains valid.
        preferences.arabicVisible = true
        XCTAssertNoThrow(try ReaderPreferencesValidator.validated(preferences))
        preferences.arabicVisible = false
        preferences.translationVisible = true
        XCTAssertNoThrow(try ReaderPreferencesValidator.validated(preferences))
    }

    func testValidatedClampsTheArabicFontSize() throws {
        var low = ReaderPreferences()
        low.arabicFontSize = 5
        XCTAssertEqual(try ReaderPreferencesValidator.validated(low).arabicFontSize, 18)
        var high = ReaderPreferences()
        high.arabicFontSize = 90
        XCTAssertEqual(try ReaderPreferencesValidator.validated(high).arabicFontSize, 40)
    }

    func testValidatedCanonicalizesLocalesAndRejectsMalformedOnes() throws {
        var preferences = ReaderPreferences()
        preferences.uiLocale = "UR_PK"
        preferences.translationLocale = "es-419"
        let validated = try ReaderPreferencesValidator.validated(preferences)
        XCTAssertEqual(validated.uiLocale, "ur-PK")
        XCTAssertEqual(validated.translationLocale, "es-419")

        preferences.translationLocale = "???"
        XCTAssertThrowsError(try ReaderPreferencesValidator.validated(preferences)) { error in
            XCTAssertEqual(
                error as? ReaderPreferencesValidationError,
                .invalidLocale("???")
            )
        }
    }

    func testCodableRoundTripPreservesEveryField() throws {
        var preferences = ReaderPreferences()
        preferences.uiLocale = "ur-PK"
        preferences.translationLocale = "ar"
        preferences.readingDirection = .rtl
        preferences.theme = .paper
        preferences.arabicFont = .amiri
        preferences.arabicFontSize = 32
        preferences.arabicVisible = false
        preferences.translationVisible = true
        preferences.updatedAt = 1_234

        let data = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(ReaderPreferences.self, from: data)
        XCTAssertEqual(decoded, preferences)
    }

    func testDecodingUnknownFontIdAndMissingFieldsFallsBackSafely() throws {
        // A newer build wrote a font id this build does not know.
        let json = """
        {
          "schemaVersion": 1,
          "uiLocale": "en",
          "translationLocale": "en",
          "readingDirection": "auto",
          "theme": "dark",
          "arabicFont": "some-future-naskh",
          "arabicFontSize": 30,
          "arabicVisible": true,
          "translationVisible": true,
          "updatedAt": 99
        }
        """
        let decoded = try JSONDecoder().decode(ReaderPreferences.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.arabicFont, .system)
        XCTAssertEqual(decoded.theme, .dark)
        XCTAssertEqual(decoded.updatedAt, 99)

        // A partial payload (older writer) decodes to full defaults.
        let partial = try JSONDecoder().decode(
            ReaderPreferences.self,
            from: Data(#"{"schemaVersion": 1}"#.utf8)
        )
        XCTAssertEqual(partial, ReaderPreferences())
    }

    func testDirectionMetadataMatrix() {
        var preferences = ReaderPreferences()

        // Arabic-only reading auto-resolves RTL.
        preferences.arabicVisible = true
        preferences.translationVisible = false
        XCTAssertEqual(
            ReaderPreferencesValidator.directionMetadata(for: preferences),
            DirectionMetadata(pageDirection: .rtl, arabicBlocksRTL: true)
        )

        // Translation-only follows the translation script.
        preferences.arabicVisible = false
        preferences.translationVisible = true
        preferences.translationLocale = "ur"
        XCTAssertEqual(
            ReaderPreferencesValidator.directionMetadata(for: preferences).pageDirection,
            .rtl
        )
        preferences.translationLocale = "en"
        XCTAssertEqual(
            ReaderPreferencesValidator.directionMetadata(for: preferences).pageDirection,
            .ltr
        )

        // Mixed pages follow the translation language; Arabic blocks stay RTL.
        preferences.arabicVisible = true
        preferences.translationLocale = "en"
        XCTAssertEqual(
            ReaderPreferencesValidator.directionMetadata(for: preferences).pageDirection,
            .ltr
        )
        XCTAssertEqual(
            ReaderPreferencesValidator.directionMetadata(for: preferences).arabicBlocksRTL,
            true
        )
        preferences.translationLocale = "ar"
        XCTAssertEqual(
            ReaderPreferencesValidator.directionMetadata(for: preferences).pageDirection,
            .rtl
        )

        // Explicit direction overrides auto.
        preferences.translationLocale = "ar"
        preferences.readingDirection = .ltr
        XCTAssertEqual(
            ReaderPreferencesValidator.directionMetadata(for: preferences).pageDirection,
            .ltr
        )
        preferences.readingDirection = .rtl
        XCTAssertEqual(
            ReaderPreferencesValidator.directionMetadata(for: preferences).pageDirection,
            .rtl
        )
    }
}
