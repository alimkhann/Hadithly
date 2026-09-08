import XCTest
@testable import Hadithly

final class GuestMergePlannerTests: XCTestCase {
    private func date(_ seconds: Double) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    // MARK: - Valid hadith id filtering

    func testValidHadithIdsPass() {
        XCTAssertTrue(GuestMergePlanner.isValidHadithId("jn7fxd3z54153q9j13kmhgzkv18df2zd"))
    }

    func testEmptyAndShortIdsAreRejected() {
        XCTAssertFalse(GuestMergePlanner.isValidHadithId(""))
        XCTAssertFalse(GuestMergePlanner.isValidHadithId("short"))
    }

    func testUppercaseIdsAreRejected() {
        XCTAssertFalse(GuestMergePlanner.isValidHadithId("JN7FXD3Z54153Q9J13KMHGZKV18DF2ZD"))
    }

    func testIdsWithSymbolsAreRejected() {
        XCTAssertFalse(GuestMergePlanner.isValidHadithId("jn7fxd3z54153q9j13kmhgzkv18df2z!"))
    }

    // MARK: - Payload building

    func testPayloadIsEmptyWhenNoGuestData() {
        let payload = GuestMergePlanner.makePayload(bookmarks: [], notes: [])
        XCTAssertTrue(payload.isEmpty)
    }

    func testInvalidHadithIdsAreDropped() {
        let payload = GuestMergePlanner.makePayload(
            bookmarks: [
                GuestBookmarkDraft(hadithId: "not-a-real-id", createdAt: date(100)),
                GuestBookmarkDraft(hadithId: "jn7fxd3z54153q9j13kmhgzkv18df2zd", createdAt: date(200)),
            ],
            notes: [
                GuestNoteDraft(hadithId: "", content: "orphan", createdAt: date(1), updatedAt: date(1)),
            ]
        )
        XCTAssertEqual(payload.bookmarks.count, 1)
        XCTAssertEqual(payload.bookmarks.first?.hadithId, "jn7fxd3z54153q9j13kmhgzkv18df2zd")
        XCTAssertTrue(payload.notes.isEmpty)
    }

    func testDuplicateBookmarksKeepEarliestCreation() {
        let payload = GuestMergePlanner.makePayload(
            bookmarks: [
                GuestBookmarkDraft(hadithId: "jn7fxd3z54153q9j13kmhgzkv18df2zd", createdAt: date(500)),
                GuestBookmarkDraft(hadithId: "jn7fxd3z54153q9j13kmhgzkv18df2zd", createdAt: date(100)),
            ],
            notes: []
        )
        XCTAssertEqual(payload.bookmarks.count, 1)
        XCTAssertEqual(payload.bookmarks.first?.createdAt, 100_000)
    }

    func testDuplicateNotesKeepLatestEdit() {
        let payload = GuestMergePlanner.makePayload(
            bookmarks: [],
            notes: [
                GuestNoteDraft(hadithId: "jn7fxd3z54153q9j13kmhgzkv18df2zd", content: "old", createdAt: date(10), updatedAt: date(20)),
                GuestNoteDraft(hadithId: "jn7fxd3z54153q9j13kmhgzkv18df2zd", content: "newer", createdAt: date(10), updatedAt: date(30)),
                GuestNoteDraft(hadithId: "jn7fxd3z54153q9j13kmhgzkv18df2zd", content: "stale", createdAt: date(10), updatedAt: date(15)),
            ]
        )
        XCTAssertEqual(payload.notes.count, 1)
        XCTAssertEqual(payload.notes.first?.content, "newer")
        XCTAssertEqual(payload.notes.first?.updatedAt, 30_000)
    }

    func testTimestampsAreMillisecondsSinceEpoch() {
        let payload = GuestMergePlanner.makePayload(
            bookmarks: [GuestBookmarkDraft(hadithId: "jn7fxd3z54153q9j13kmhgzkv18df2zd", createdAt: date(1.5))],
            notes: []
        )
        XCTAssertEqual(payload.bookmarks.first?.createdAt, 1500)
    }

    func testItemsAreSortedByTimestamp() {
        let payload = GuestMergePlanner.makePayload(
            bookmarks: [
                GuestBookmarkDraft(hadithId: "baaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1", createdAt: date(300)),
                GuestBookmarkDraft(hadithId: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", createdAt: date(100)),
                GuestBookmarkDraft(hadithId: "caaaaaaaaaaaaaaaaaaaaaaaaaaaaaa2", createdAt: date(200)),
            ],
            notes: []
        )
        XCTAssertEqual(payload.bookmarks.map(\.createdAt), [100_000, 200_000, 300_000])
    }

    // MARK: - Favorites and reading progress (Phase 3)

    func testDuplicateFavoritesKeepEarliestCreation() {
        let payload = GuestMergePlanner.makePayload(
            bookmarks: [],
            notes: [],
            favorites: [
                GuestFavoriteDraft(hadithId: "jn7fxd3z54153q9j13kmhgzkv18df2zd", createdAt: date(900)),
                GuestFavoriteDraft(hadithId: "jn7fxd3z54153q9j13kmhgzkv18df2zd", createdAt: date(100)),
            ]
        )
        XCTAssertEqual(payload.favorites.count, 1)
        XCTAssertEqual(payload.favorites.first?.createdAt, 100_000)
    }

    func testProgressKeepsNewestPositionPerCollection() {
        let payload = GuestMergePlanner.makePayload(
            bookmarks: [],
            notes: [],
            progress: [
                GuestReadingProgressDraft(
                    collectionSlug: "bukhari",
                    collectionName: "Sahih al-Bukhari",
                    hadithId: "jn7fxd3z54153q9j13kmhgzkv18df2zd",
                    updatedAt: date(100)
                ),
                GuestReadingProgressDraft(
                    collectionSlug: "bukhari",
                    collectionName: "Sahih al-Bukhari",
                    hadithId: "baaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1",
                    updatedAt: date(500)
                ),
                GuestReadingProgressDraft(
                    collectionSlug: "muslim",
                    collectionName: "Sahih Muslim",
                    hadithId: "caaaaaaaaaaaaaaaaaaaaaaaaaaaaaa2",
                    updatedAt: date(300)
                ),
            ]
        )
        XCTAssertEqual(payload.readingProgress.count, 2)
        let bukhari = payload.readingProgress.first { $0.collectionSlug == "bukhari" }
        XCTAssertEqual(bukhari?.hadithId, "baaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1")
    }

    func testEmptyStateIncludesNewCollections() {
        let payload = GuestMergePlanner.makePayload(bookmarks: [], notes: [])
        XCTAssertTrue(payload.isEmpty)
        let withFavorite = GuestMergePlanner.makePayload(
            bookmarks: [],
            notes: [],
            favorites: [
                GuestFavoriteDraft(hadithId: "jn7fxd3z54153q9j13kmhgzkv18df2zd", createdAt: date(1)),
            ]
        )
        XCTAssertFalse(withFavorite.isEmpty)
    }
}
