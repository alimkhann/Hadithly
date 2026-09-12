import XCTest
@testable import Hadithly

final class TodayTests: XCTestCase {
    func testShortDailyReadingDoesNotCollapse() {
        XCTAssertFalse(TodayContentPolicy.needsCollapsedPreview(
            arabic: "نص قصير",
            translation: "A short translation."
        ))
    }

    func testExtremeDailyReadingUsesBoundedExpansion() {
        XCTAssertTrue(TodayContentPolicy.needsCollapsedPreview(
            arabic: String(repeating: "نص ", count: 300),
            translation: String(repeating: "translation ", count: 300)
        ))
        XCTAssertEqual(TodayContentPolicy.expandedScrollHeight, 420)
    }

    func testDailyPayloadKeepsAITranslationLabelSeparateFromProviderEnglish() throws {
        let json = """
        {
          "_id":"h1", "provider":"sunnah_now", "canonicalId":"sunnah_now:bukhari:1",
          "providerHadithId":"1", "collectionSlug":"bukhari", "collectionName":"Sahih al-Bukhari",
          "volumeId":"1", "arabicText":"نص", "englishText":"Provider English",
          "translation":{"text":"اردو", "language":"ur", "source":"gemini_ai", "sourceLabel":"AI translation", "isAI":true},
          "referenceDisplay":"Sahih al-Bukhari · Hadith 1",
          "authenticity":{"kind":"collection_scope", "normalizedGrade":"sahih", "claimScope":"collection", "sourceLabel":"Documented Sahih collection", "sourceName":"Sunnah.com", "sourceUrl":"https://sunnah.com/bukhari/about", "verificationMethod":"manual_collection_mapping"}
        }
        """
        let hadith = try JSONDecoder().decode(DailyHadith.self, from: Data(json.utf8))
        XCTAssertEqual(hadith.translation?.language, "ur")
        XCTAssertEqual(hadith.translation?.sourceLabel, "AI translation")
        XCTAssertTrue(hadith.translation?.isAI == true)
    }
}
