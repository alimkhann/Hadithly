import ConvexMobile
import XCTest
@testable import Hadithly

final class ReaderModelsTests: XCTestCase {
    func testReaderHadithInternalIdShape() throws {
        let json = """
        {
          "_id": "abc123",
          "providerHadithId": "7",
          "collectionSlug": "bukhari",
          "volumeId": "1",
          "arabicText": "نَمَّ",
          "englishText": "Deeds are by intentions.",
          "narrator": "Umar ibn al-Khattab",
          "referenceDisplay": "Sahih al-Bukhari · Hadith 7",
          "collectionName": "Sahih al-Bukhari",
          "chapterName": "Revelation"
        }
        """
        let hadith = try JSONDecoder().decode(ReaderHadith.self, from: Data(json.utf8))
        XCTAssertEqual(hadith.internalId, "sunnah_now:bukhari:7")
        XCTAssertEqual(hadith.volumeId, "1")
    }

    func testReaderPageDecodes() throws {
        let json = """
        {
          "items": [{
            "_id": "abc123",
            "providerHadithId": "7",
            "collectionSlug": "bukhari",
            "arabicText": "نَمَّ",
            "referenceDisplay": "Sahih al-Bukhari · Hadith 7",
            "collectionName": "Sahih al-Bukhari"
          }],
          "page": 2,
          "pageSize": 8,
          "totalPages": 9,
          "hasMore": true
        }
        """
        let page = try JSONDecoder().decode(ReaderPageResult.self, from: Data(json.utf8))
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.page, 2)
        XCTAssertEqual(page.totalPages, 9)
        XCTAssertTrue(page.hasMore)
    }

    func testOutlineDecodes() throws {
        let json = """
        {
          "volumes": [
            { "volumeId": "1", "title": "Volume 1", "firstChapterTitle": "Revelation", "hadithCount": 100 }
          ]
        }
        """
        let outline = try JSONDecoder().decode(CollectionOutlineResult.self, from: Data(json.utf8))
        XCTAssertEqual(outline.volumes.count, 1)
        XCTAssertEqual(outline.volumes[0].volumeId, "1")
    }

    func testTranslationDecodes() throws {
        let json = """
        {
          "translationId": "tx1",
          "translation": "Die Taten richten sich nach den Absichten.",
          "confidence": 0.9,
          "riskFlags": [],
          "glossaryNotes": ["niyya = Absicht"],
          "source": "gemini_ai",
          "sourceLabel": "AI",
          "aiModel": "gemini-2.5-flash-lite",
          "groundingUsed": true,
          "citations": [{ "url": "https://sunnah.com/bukhari:1", "title": "Sunnah.com", "domain": "sunnah.com" }],
          "sourceReferenceUrl": "https://sunnah.com/bukhari:1",
          "cached": false
        }
        """
        let translation = try JSONDecoder().decode(ReaderTranslation.self, from: Data(json.utf8))
        XCTAssertEqual(translation.translationId, "tx1")
        XCTAssertEqual(translation.citations.count, 1)
        XCTAssertEqual(translation.citations[0].domain, "sunnah.com")
        XCTAssertEqual(translation.sourceLabel, "AI")
    }

    func testSubmissionVerdictDecodesAndCollectsReviewNotes() throws {
        let json = """
        {
          "submissionId": "submission1",
          "status": "needs_admin",
          "aiReview": {
            "model": "gemini-2.5-flash-lite",
            "score": 0.72,
            "riskFlags": ["ambiguous pronoun"],
            "missingMeaning": ["chain attribution"],
            "addedMeaning": [],
            "glossaryIssues": ["use an established rendering"],
            "recommendation": "admin_review"
          }
        }
        """
        let result = try JSONDecoder().decode(
            TranslationSubmissionResult.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(result.status, "needs_admin")
        XCTAssertEqual(result.aiReview.recommendation, "admin_review")
        XCTAssertEqual(
            result.aiReview.reviewNotes,
            [
                "ambiguous pronoun",
                "Missing meaning: chain attribution",
                "Terminology: use an established rendering",
            ]
        )
    }

    func testTranslationFailureClassification() {
        XCTAssertEqual(
            TranslationFailure(message: "AI_GENERATION_QUOTA_EXCEEDED"),
            .quotaExceeded
        )
        XCTAssertEqual(
            TranslationFailure(message: "Unauthenticated: this function requires a signed-in user"),
            .requiresSignIn
        )
        XCTAssertEqual(
            TranslationFailure(message: "Gemini returned an empty translation"),
            .failed("Gemini returned an empty translation")
        )
    }

    func testServerErrorMessageExtraction() {
        let error = ClientError.ServerError(msg: "AI_GENERATION_QUOTA_EXCEEDED")
        XCTAssertEqual(ReaderModels.errorMessage(of: error), "AI_GENERATION_QUOTA_EXCEEDED")
    }

    func testCollectionListMatchesBackendOrder() {
        XCTAssertEqual(
            ReaderModels.collections.map(\.slug),
            ["bukhari", "muslim", "sunan-nasai", "abu-dawood", "tirmidhi", "ibn-majah", "mishkat-al-masabih"]
        )
    }
}
