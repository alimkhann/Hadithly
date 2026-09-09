import XCTest
@testable import Hadithly

/// R4: reader themes, Arabic type ladder, source-provided chapter
/// boundaries, layout projections, and the layout-change re-anchor.
final class ReaderR4Tests: XCTestCase {
    // MARK: Themes

    func testResolvedPalettesPerTheme() {
        XCTAssertEqual(ReaderPalette.resolved(.dark, systemDark: false), .dark)
        XCTAssertEqual(ReaderPalette.resolved(.dark, systemDark: true), .dark)
        XCTAssertEqual(ReaderPalette.resolved(.light, systemDark: true), .light)
        XCTAssertEqual(ReaderPalette.resolved(.paper, systemDark: false), .paper)
        XCTAssertEqual(ReaderPalette.resolved(.system, systemDark: false), .light)
        XCTAssertEqual(ReaderPalette.resolved(.system, systemDark: true), .dark)
    }

    func testPaperAndLightPalettesHaveAccessibleContrast() {
        for palette in [ReaderPalette.light, .paper] {
            XCTAssertTrue(palette.textPrimary != palette.background)
            XCTAssertTrue(palette.textSecondary != palette.background)
        }
    }

    func testPreferredColorSchemeMapping() {
        XCTAssertNil(ReaderPalette.preferredColorScheme(for: .system))
        XCTAssertEqual(ReaderPalette.preferredColorScheme(for: .light), .light)
        XCTAssertEqual(ReaderPalette.preferredColorScheme(for: .paper), .light)
        XCTAssertEqual(ReaderPalette.preferredColorScheme(for: .dark), .dark)
    }

    // MARK: Arabic type ladder

    func testTypeSizeLadderStaysInsidePreferenceClamp() {
        XCTAssertEqual(ArabicTypeSize.steps.first, ReaderPreferences.minArabicFontSize)
        XCTAssertEqual(ArabicTypeSize.steps.last, ReaderPreferences.maxArabicFontSize)
    }

    func testTypeSizeStepping() {
        XCTAssertEqual(ArabicTypeSize.stepUp(from: 18), 22)
        XCTAssertEqual(ArabicTypeSize.stepUp(from: 40), 40)
        XCTAssertEqual(ArabicTypeSize.stepDown(from: 40), 34)
        XCTAssertEqual(ArabicTypeSize.stepDown(from: 18), 18)
        XCTAssertEqual(ArabicTypeSize.nearest(27), 26)
        XCTAssertEqual(ArabicTypeSize.nearest(36), 34)
    }

    // MARK: Layout projection

    func testLayoutProjectionTracksLayoutAffectingPreferences() {
        var preferences = ReaderPreferences()
        let baseline = preferences.layoutProjection

        preferences.arabicFontSize = 30
        XCTAssertNotEqual(preferences.layoutProjection, baseline)

        preferences.arabicFont = .amiri
        XCTAssertNotEqual(preferences.layoutProjection, baseline)

        preferences.arabicVisible = false
        XCTAssertNotEqual(preferences.layoutProjection, baseline)

        preferences.translationLocale = "ur"
        XCTAssertNotEqual(preferences.layoutProjection, baseline)
    }

    func testLayoutProjectionIgnoresThemeAndDirection() {
        var preferences = ReaderPreferences()
        let baseline = preferences.layoutProjection
        preferences.theme = .paper
        preferences.readingDirection = .rtl
        XCTAssertEqual(preferences.layoutProjection, baseline)
    }

    // MARK: Chapter boundaries

    private func hadith(json: String) throws -> ReaderHadith {
        try JSONDecoder().decode(ReaderHadith.self, from: Data(json.utf8))
    }

    private func page(with itemJSON: [String]) throws -> ReaderPageResult {
        let itemsJSON = itemJSON.joined(separator: ",")
        let json = """
        {
          "items": [\(itemsJSON)],
          "page": 1,
          "pageSize": 8,
          "totalPages": 3,
          "hasMore": true,
          "contentVersion": "abc",
          "pageKey": "pk",
          "paginationVersion": 1
        }
        """
        return try JSONDecoder().decode(ReaderPageResult.self, from: Data(json.utf8))
    }

    private func hadithJSON(id: String, number: String, chapter: String?) -> String {
        let chapterField = chapter.map { "\"chapterName\": \"\($0)\"," } ?? ""
        return """
        {
          "_id": "\(id)",
          "provider": "sunnah_now",
          "canonicalId": "sunnah_now:bukhari:\(number)",
          "providerHadithId": "\(number)",
          "collectionSlug": "bukhari",
          "volumeId": "1",
          "arabicText": "نَمَّ",
          "referenceDisplay": "Sahih al-Bukhari · Hadith \(number)",
          "collectionName": "Sahih al-Bukhari",
          \(chapterField)
          "authenticity": {
            "kind": "collection_scope",
            "normalizedGrade": "sahih",
            "claimScope": "collection",
            "sourceLabel": "Documented Sahih collection",
            "sourceName": "Sunnah.com",
            "sourceUrl": "https://sunnah.com/bukhari/about",
            "verificationMethod": "manual_collection_mapping"
          }
        }
        """
    }

    func testChapterOpeningsOnlyFromSourceNames() throws {
        let hadiths = [
            try hadith(json: hadithJSON(id: "a", number: "7", chapter: "Revelation")),
            try hadith(json: hadithJSON(id: "b", number: "8", chapter: "Revelation")),
            try hadith(json: hadithJSON(id: "c", number: "9", chapter: nil)),
            try hadith(json: hadithJSON(id: "d", number: "10", chapter: "Belief")),
        ]
        XCTAssertEqual(ReaderChapterBoundaries.openingIndices(in: hadiths), [0, 3])
    }

    func testChapterOpeningsHandleUnnamedPageStart() throws {
        let hadiths = [
            try hadith(json: hadithJSON(id: "a", number: "7", chapter: nil)),
            try hadith(json: hadithJSON(id: "b", number: "8", chapter: "Belief")),
        ]
        XCTAssertEqual(ReaderChapterBoundaries.openingIndices(in: hadiths), [1])
    }

    // MARK: Layout-change re-anchor

    func testReanchoredPositionCarriesNewSignatureAndStableOffset() throws {
        let firstJSON = hadithJSON(id: "a", number: "7", chapter: "Revelation")
        let secondJSON = hadithJSON(id: "b", number: "8", chapter: nil)
        let hadiths = [
            try hadith(json: firstJSON),
            try hadith(json: secondJSON),
        ]
        let page = try page(with: [firstJSON, secondJSON])
        var layout = ReadingLayout(
            locale: "en",
            arabicVisible: true,
            translationVisible: true,
            arabicFontId: "system",
            arabicFontSize: 26,
            widthClass: .compact,
            paginationVersion: 1
        )
        let position = ReaderModel.reanchoredPosition(
            anchor: hadiths[1],
            page: page,
            volumeId: "1",
            rawPageOffset: 120,
            normalizedOffset: 0.4,
            layout: layout
        )
        XCTAssertEqual(position.anchor.providerHadithId, "8")
        XCTAssertEqual(position.rawPageOffset, 120)
        XCTAssertEqual(position.normalizedOffset, 0.4)
        XCTAssertEqual(position.layoutSignature, layout.signature)

        layout = ReadingLayout(
            locale: "en",
            arabicVisible: true,
            translationVisible: true,
            arabicFontId: "amiri",
            arabicFontSize: 34,
            widthClass: .compact,
            paginationVersion: 1
        )
        let reanchored = ReaderModel.reanchoredPosition(
            anchor: hadiths[1],
            page: page,
            volumeId: "1",
            rawPageOffset: 120,
            normalizedOffset: 0.4,
            layout: layout
        )
        XCTAssertEqual(reanchored.layoutSignature, layout.signature)
        XCTAssertNotEqual(reanchored.layoutSignature, position.layoutSignature)
    }
}
