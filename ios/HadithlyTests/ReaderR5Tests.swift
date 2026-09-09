import XCTest
@testable import Hadithly

/// R5: canonical-URL builder, copy formatter, chapter-outline decoding, and
/// jump-to-reference validation. The builder round-trips through
/// `CanonicalHadithLink.parse` so share output and inbound routing can never
/// disagree.
final class ReaderR5Tests: XCTestCase {
    // MARK: - Canonical URL builder

    func testCanonicalURLBuilderProducesCleanURL() {
        let url = ReaderShare.canonicalURL(collectionSlug: "bukhari", providerHadithId: "57")
        XCTAssertEqual(url?.absoluteString, "https://hadithly.app/hadith/bukhari/57")
    }

    func testCanonicalURLBuilderRoundTripsThroughParser() {
        for (slug, number) in [("bukhari", "57"), ("muslim", "4.5"), ("sunan-nasai", "1000")] {
            let url = ReaderShare.canonicalURL(collectionSlug: slug, providerHadithId: number)
            XCTAssertNotNil(url, "\(slug)/\(number)")
            let parsed = url.flatMap { CanonicalHadithLink.parse($0) }
            XCTAssertEqual(parsed?.collectionSlug, slug)
            XCTAssertEqual(parsed?.providerHadithId, number)
        }
    }

    func testCanonicalURLBuilderRejectsMalformedInput() {
        XCTAssertNil(ReaderShare.canonicalURL(collectionSlug: "Bukhari", providerHadithId: "57"))
        XCTAssertNil(ReaderShare.canonicalURL(collectionSlug: "", providerHadithId: "57"))
        XCTAssertNil(ReaderShare.canonicalURL(collectionSlug: "bukhari", providerHadithId: "0"))
        XCTAssertNil(ReaderShare.canonicalURL(collectionSlug: "bukhari", providerHadithId: ".5"))
        XCTAssertNil(ReaderShare.canonicalURL(collectionSlug: "bukhari", providerHadithId: "57."))
        XCTAssertNil(ReaderShare.canonicalURL(collectionSlug: "bukhari", providerHadithId: "abc"))
        XCTAssertNil(ReaderShare.canonicalURL(collectionSlug: "bukhari", providerHadithId: ""))
    }

    // MARK: - Copy formatter

    private func hadith() -> ReaderHadith {
        ReaderHadith(
            _id: "abc123",
            provider: "sunnah_now",
            canonicalId: "sunnah_now:bukhari:57",
            providerHadithId: "57",
            collectionSlug: "bukhari",
            volumeId: "2",
            chapterId: nil,
            arabicText: "نَصّ الحديث",
            englishText: "Deeds are by intentions.",
            narrator: nil,
            referenceDisplay: "Sahih al-Bukhari · Hadith 57",
            collectionName: "Sahih al-Bukhari",
            chapterName: nil,
            authenticity: ReaderAuthenticity(
                kind: "collection_scope",
                normalizedGrade: "sahih",
                claimScope: "collection",
                sourceLabel: "Documented Sahih collection",
                sourceName: "Sunnah.com",
                sourceUrl: "https://sunnah.com/bukhari/about",
                verificationMethod: "manual_collection_mapping"
            )
        )
    }

    func testCopyArabicOnly() {
        let text = ReaderShare.copyText(
            for: hadith(),
            arabicVisible: true,
            translationVisible: false,
            translationText: nil,
            translationIsAI: false
        )
        XCTAssertEqual(text, "نَصّ الحديث\n\n— Sahih al-Bukhari · Hadith 57 · Sunnah.com")
    }

    func testCopyMixedArabicAndProviderEnglish() {
        let text = ReaderShare.copyText(
            for: hadith(),
            arabicVisible: true,
            translationVisible: true,
            translationText: "Deeds are by intentions.",
            translationIsAI: false
        )
        XCTAssertEqual(
            text,
            "نَصّ الحديث\n\nDeeds are by intentions.\n\n— Sahih al-Bukhari · Hadith 57 · Sunnah.com"
        )
    }

    func testCopyAddsAILabelOnlyForAITranslations() {
        let ai = ReaderShare.copyText(
            for: hadith(),
            arabicVisible: true,
            translationVisible: true,
            translationText: "Taten richten sich nach Absichten.",
            translationIsAI: true
        )
        XCTAssertTrue(ai.hasSuffix("· AI translation"), ai)

        let provider = ReaderShare.copyText(
            for: hadith(),
            arabicVisible: true,
            translationVisible: true,
            translationText: "Deeds are by intentions.",
            translationIsAI: false
        )
        XCTAssertFalse(provider.contains("AI translation"), provider)
    }

    func testCopyNeverIncludesURL() {
        let text = ReaderShare.copyText(
            for: hadith(),
            arabicVisible: true,
            translationVisible: true,
            translationText: "Deeds are by intentions.",
            translationIsAI: false
        )
        XCTAssertFalse(text.contains("hadithly.app"))
        XCTAssertFalse(text.contains("https://"))
    }

    func testCopyTranslationOnlyOmitsArabic() {
        let text = ReaderShare.copyText(
            for: hadith(),
            arabicVisible: false,
            translationVisible: true,
            translationText: "Deeds are by intentions.",
            translationIsAI: false
        )
        XCTAssertEqual(text, "Deeds are by intentions.\n\n— Sahih al-Bukhari · Hadith 57 · Sunnah.com")
    }

    // MARK: - Chapter decoding

    func testChapterDecodeWithDoubleCounts() throws {
        let json = """
        {
          "volumes": [
            {
              "volumeId": "1",
              "title": "Volume 1",
              "firstChapterTitle": "Revelation",
              "hadithCount": 7.0,
              "chapters": [
                {
                  "chapterId": "1",
                  "title": "Revelation",
                  "arabicTitle": "كتاب بدء الوحي",
                  "hadithCount": 7.0,
                  "firstProviderHadithId": "1"
                }
              ]
            }
          ]
        }
        """
        let outline = try JSONDecoder().decode(CollectionOutlineResult.self, from: Data(json.utf8))
        XCTAssertEqual(outline.volumes.count, 1)
        XCTAssertEqual(outline.volumes[0].hadithCount, 7)
        let chapters = try XCTUnwrap(outline.volumes[0].chapters)
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters[0].chapterId, "1")
        XCTAssertEqual(chapters[0].title, "Revelation")
        XCTAssertEqual(chapters[0].arabicTitle, "كتاب بدء الوحي")
        XCTAssertEqual(chapters[0].hadithCount, 7)
        XCTAssertEqual(chapters[0].firstProviderHadithId, "1")
    }

    func testChapterMissingKeepsPreR5BackCompat() throws {
        let json = """
        {
          "volumes": [
            { "volumeId": "1", "title": "Volume 1", "firstChapterTitle": "Revelation", "hadithCount": 100 }
          ]
        }
        """
        let outline = try JSONDecoder().decode(CollectionOutlineResult.self, from: Data(json.utf8))
        XCTAssertEqual(outline.volumes.count, 1)
        XCTAssertNil(outline.volumes[0].chapters)
    }

    func testChapterWithoutIdDecodes() throws {
        let json = """
        {
          "volumes": [
            {
              "volumeId": "2",
              "title": "Volume 2",
              "hadithCount": 51,
              "chapters": [
                { "title": "Belief", "hadithCount": 51, "firstProviderHadithId": "8" }
              ]
            }
          ]
        }
        """
        let outline = try JSONDecoder().decode(CollectionOutlineResult.self, from: Data(json.utf8))
        let chapters = try XCTUnwrap(outline.volumes[0].chapters)
        XCTAssertNil(chapters[0].chapterId)
        XCTAssertNil(chapters[0].arabicTitle)
        XCTAssertEqual(chapters[0].firstProviderHadithId, "8")
    }

    // MARK: - Jump validation

    func testJumpValidationAcceptsWellFormedNumbers() {
        XCTAssertTrue(ReaderShare.isValidReferenceNumber("57"))
        XCTAssertTrue(ReaderShare.isValidReferenceNumber("1"))
        XCTAssertTrue(ReaderShare.isValidReferenceNumber("4.5"))
    }

    func testJumpValidationRejectsMalformedNumbers() {
        for bad in ["0", ".5", "57.", "abc", "", "0.5", "57abc", " 57"] {
            XCTAssertFalse(ReaderShare.isValidReferenceNumber(bad), "should reject \(bad)")
        }
    }
}
