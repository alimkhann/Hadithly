import XCTest
@testable import Hadithly

/// F3 gate: canonical Universal Link parsing on the iOS boundary. Mirrors
/// `backend/convex/lib/canonicalLinks.ts` and the Android parser so all
/// three surfaces accept and reject the same links.
final class CanonicalLinkTests: XCTestCase {
    func testParsesCanonicalLink() {
        let link = CanonicalHadithLink.parse(URL(string: "https://hadithly.app/hadith/bukhari/57")!)
        XCTAssertEqual(link?.collectionSlug, "bukhari")
        XCTAssertEqual(link?.providerHadithId, "57")
    }

    func testParsesDottedSubreferenceAndQueryParameters() {
        let link = CanonicalHadithLink.parse(
            URL(string: "https://hadithly.app/hadith/muslim/4.5?locale=ur&pos=v3")!
        )
        XCTAssertEqual(link?.collectionSlug, "muslim")
        XCTAssertEqual(link?.providerHadithId, "4.5")
    }

    func testToleratesTrailingSlashOnly() {
        XCTAssertNotNil(
            CanonicalHadithLink.parse(URL(string: "https://hadithly.app/hadith/nasai/1000/")!)
        )
    }

    func testCollectionNameFallsBackToSlug() {
        let known = CanonicalHadithLink.parse(
            URL(string: "https://hadithly.app/hadith/bukhari/57")!
        )
        XCTAssertEqual(known?.collectionName, "Sahih al-Bukhari")
        let unknown = CanonicalHadithLink.parse(
            URL(string: "https://hadithly.app/hadith/muwatta/7")!
        )
        XCTAssertEqual(unknown?.collectionName, "muwatta")
    }

    func testRejectsForeignHostAndScheme() {
        XCTAssertNil(CanonicalHadithLink.parse(URL(string: "http://hadithly.app/hadith/bukhari/57")!))
        XCTAssertNil(CanonicalHadithLink.parse(URL(string: "https://evil.example/hadith/bukhari/57")!))
        XCTAssertNil(
            CanonicalHadithLink.parse(
                URL(string: "https://hadithly.app.evil.example/hadith/bukhari/57")!
            )
        )
    }

    func testRejectsMalformedShapes() {
        for path in [
            "https://hadithly.app/hadith/bukhari",
            "https://hadithly.app/hadith/bukhari/57/extra",
            "https://hadithly.app/hadith//57",
            "https://hadithly.app/hadith//bukhari/57",
            "https://hadithly.app/hadith/bukhari/57//",
            "https://hadithly.app/hadith/bukhari/",
            "https://hadithly.app/hadith/Bukhari/57",
            "https://hadithly.app/hadith/bukhari/57abc",
            "https://hadithly.app/hadith/bukhari/57.",
            "https://hadithly.app/hadith/bukhari/.5",
            "https://hadithly.app/hadith/bukhari/0",
            "https://hadithly.app/hadith/bukhari/%35%37",
            "https://hadithly.app/hadith/bukhari%2F57",
            "https://hadithly.app/reader/bukhari/57",
            "https://hadithly.app/privacy/",
        ] {
            XCTAssertNil(
                CanonicalHadithLink.parse(URL(string: path)!),
                "should reject \(path)"
            )
        }
    }

    @MainActor
    func testRouterQueuesAndConsumesExactlyOnce() {
        let router = LinkRouter()
        XCTAssertEqual(router.handle(URL(string: "https://hadithly.app/hadith/bukhari/57")!), true)
        XCTAssertEqual(router.consumePending()?.providerHadithId, "57")
        XCTAssertNil(router.consumePending())
    }

    @MainActor
    func testRouterIgnoresMalformedLinks() {
        let router = LinkRouter()
        XCTAssertEqual(router.handle(URL(string: "https://hadithly.app/privacy/")!), false)
        XCTAssertNil(router.consumePending())
    }

    @MainActor
    func testRouterKeepsOnlyTheLatestLink() {
        let router = LinkRouter()
        router.handle(URL(string: "https://hadithly.app/hadith/bukhari/57")!)
        router.handle(URL(string: "https://hadithly.app/hadith/muslim/12")!)
        let consumed = router.consumePending()
        XCTAssertEqual(consumed?.collectionSlug, "muslim")
        XCTAssertEqual(consumed?.providerHadithId, "12")
    }
}

/// F3: a canonical link carries no volume, so the reader locates the volume
/// holding the hadith from the source-provided outline counts.
final class CanonicalLinkVolumeTests: XCTestCase {
    private let outline = [
        OutlineVolume(volumeId: "1", title: "Volume 1", firstChapterTitle: nil, hadithCount: 7),
        OutlineVolume(volumeId: "2", title: "Volume 2", firstChapterTitle: nil, hadithCount: 51),
        OutlineVolume(volumeId: "3", title: "Volume 3", firstChapterTitle: nil, hadithCount: 44),
    ]

    func testResolvesVolumeBoundaries() {
        XCTAssertEqual(ReaderModel.volumeId(forHadithNumber: "1", in: outline), "1")
        XCTAssertEqual(ReaderModel.volumeId(forHadithNumber: "7", in: outline), "1")
        XCTAssertEqual(ReaderModel.volumeId(forHadithNumber: "8", in: outline), "2")
        XCTAssertEqual(ReaderModel.volumeId(forHadithNumber: "57", in: outline), "2")
        XCTAssertEqual(ReaderModel.volumeId(forHadithNumber: "58", in: outline), "2")
        XCTAssertEqual(ReaderModel.volumeId(forHadithNumber: "59", in: outline), "3")
        XCTAssertEqual(ReaderModel.volumeId(forHadithNumber: "102", in: outline), "3")
    }

    func testDottedSubreferenceUsesIntegerPart() {
        XCTAssertEqual(ReaderModel.volumeId(forHadithNumber: "4.5", in: outline), "1")
    }

    func testStaleNumbersFallBackToStart() {
        XCTAssertNil(ReaderModel.volumeId(forHadithNumber: "103", in: outline))
        XCTAssertNil(ReaderModel.volumeId(forHadithNumber: "9999", in: outline))
        XCTAssertNil(ReaderModel.volumeId(forHadithNumber: "zero", in: outline))
        XCTAssertNil(ReaderModel.volumeId(forHadithNumber: "", in: outline))
        // A nil result keeps the reader on the first volume at page 1.
    }
}
