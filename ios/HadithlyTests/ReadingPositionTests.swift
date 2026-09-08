import XCTest
@testable import Hadithly

final class ReadingPositionTests: XCTestCase {
    private func position(
        contentVersion: String = "cv1:content-a",
        layoutSignature: String = "ls1:layout-a",
        volumeId: String = "1",
        updatedAt: Double = 2_000
    ) -> ReadingPosition {
        ReadingPosition(
            anchor: .init(provider: "sunnah_now", collectionSlug: "bukhari", providerHadithId: "50"),
            contentVersion: contentVersion,
            volumeId: volumeId,
            chapterId: "10",
            pageKey: "pg1:page-a",
            displayPageIndex: 2,
            rawPageOffset: 144.5,
            normalizedOffset: 0.375,
            layoutSignature: layoutSignature,
            updatedAt: updatedAt
        )
    }

    func testWireRoundTripUsesDoubleNumbers() throws {
        let data = try JSONEncoder().encode(position())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Double, 1)
        XCTAssertEqual(object["displayPageIndex"] as? Double, 2)
        XCTAssertEqual(object["rawPageOffset"] as? Double, 144.5)
        XCTAssertEqual(try JSONDecoder().decode(ReadingPosition.self, from: data), position())
        XCTAssertEqual(position().convexWireValue["schemaVersion"] as? Double, 1)
        XCTAssertEqual(position().convexWireValue["displayPageIndex"] as? Double, 2)
    }

    func testDecoderRejectsAnUnsupportedVersion() throws {
        let data = try JSONEncoder().encode(position())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["schemaVersion"] = 2.0
        let unsupported = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(ReadingPosition.self, from: unsupported))
    }

    func testLayoutSignatureGoldenVectorAndPaginationChange() {
        let base = ReadingLayout(
            locale: "ur-PK",
            arabicVisible: true,
            translationVisible: true,
            arabicFontId: "noto-naskh-arabic",
            arabicFontSize: 26,
            widthClass: .compact,
            paginationVersion: 1
        )
        XCTAssertEqual(base.signature, "ls1:7bfbec6f3b66f12f662f28de140565cff6e4b521c0cd3f1c6deac9fb49b31b0d")
        XCTAssertNotEqual(base.signature, base.withPaginationVersion(2).signature)
    }

    func testContentAndLayoutChangesUseSemanticAnchor() {
        let page = ReadingPositionPage(
            pageKey: "pg1:page-a",
            displayPageIndex: 4,
            anchors: [.init(anchor: position().anchor, volumeId: "1", chapterId: "10")]
        )
        let changedContent = ReadingPositionResolver.resolve(
            position(),
            topology: .init(contentVersion: "cv1:content-b", layoutSignature: "ls1:layout-a", pages: [page])
        )
        let changedLayout = ReadingPositionResolver.resolve(
            position(),
            topology: .init(contentVersion: "cv1:content-a", layoutSignature: "ls1:layout-b", pages: [page])
        )
        XCTAssertEqual(changedContent.kind, .semantic)
        XCTAssertEqual(changedContent.displayPageIndex, 4)
        XCTAssertEqual(changedContent.normalizedOffset, 0.375)
        XCTAssertEqual(changedLayout.kind, .semantic)
    }

    func testMissingAnchorChoosesNearestAndResetsOffset() {
        let anchors = ["1", "49", "80"].map {
            ReadingPositionAnchorLocation(
                anchor: .init(provider: "sunnah_now", collectionSlug: "bukhari", providerHadithId: $0),
                volumeId: $0 == "1" ? "1" : "2",
                chapterId: nil
            )
        }
        let resolved = ReadingPositionResolver.resolve(
            position(volumeId: "2"),
            topology: .init(
                contentVersion: "changed",
                layoutSignature: "changed",
                pages: [.init(pageKey: "pg1:new", displayPageIndex: 3, anchors: anchors)]
            )
        )
        XCTAssertEqual(resolved.kind, .nearest)
        XCTAssertEqual(resolved.anchor?.providerHadithId, "49")
        XCTAssertEqual(resolved.normalizedOffset, 0)
    }

    func testLegacyGuestProgressMigratesAtOffsetZero() {
        let legacy = GuestReadingProgressDraft(
            collectionSlug: "bukhari",
            collectionName: "Bukhari",
            hadithId: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            volumeId: "2",
            hadithNumber: "57",
            updatedAt: Date(timeIntervalSince1970: 5)
        )
        let migrated = legacy.readingPosition
        XCTAssertEqual(migrated?.anchor.providerHadithId, "57")
        XCTAssertEqual(migrated?.volumeId, "2")
        XCTAssertEqual(migrated?.rawPageOffset, 0)
        XCTAssertEqual(migrated?.updatedAt, 5_000)
        XCTAssertNotNil(ReadingPosition.legacy(
            collectionSlug: "muslim",
            providerHadithId: "0",
            volumeId: "1",
            updatedAt: 5_000
        ))
    }

    func testGuestMergeCarriesTheCompleteNewestV1Position() {
        let older = position(updatedAt: 1_000)
        let newer = position(contentVersion: "cv1:content-b", updatedAt: 2_000)
        let payload = GuestMergePlanner.makePayload(
            bookmarks: [],
            notes: [],
            progress: [
                GuestReadingProgressDraft(
                    collectionSlug: "bukhari",
                    collectionName: "Bukhari",
                    hadithId: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                    updatedAt: Date(timeIntervalSince1970: 1),
                    position: older
                ),
                GuestReadingProgressDraft(
                    collectionSlug: "bukhari",
                    collectionName: "Bukhari",
                    hadithId: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                    updatedAt: Date(timeIntervalSince1970: 2),
                    position: newer
                ),
            ]
        )
        XCTAssertEqual(payload.readingProgress, [.current(newer)])
    }
}
