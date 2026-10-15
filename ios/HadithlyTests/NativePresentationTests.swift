import XCTest
import ConvexMobile
import ClerkConvex
@testable import Hadithly

@MainActor
final class NativePresentationTests: XCTestCase {
    func testGuestSavedLoadingEndsWithTheActualLocalSnapshot() {
        let guest = GuestDataStore(inMemory: true)
        let client = ConvexClientWithAuth(deploymentUrl: "https://example.invalid", authProvider: ClerkConvexAuthProvider())
        let model = UserLibraryModel(convex: client, guestData: guest, isSignedIn: { false })
        XCTAssertEqual(model.loadState, .loading)
        model.refresh()
        XCTAssertEqual(model.loadState, .ready)
        XCTAssertTrue(model.savedItems.isEmpty)
        guest.addBookmark(draft: GuestBookmarkDraft(hadithId: "local-preview", createdAt: .now,
            collectionName: "Prepared interface preview", referenceDisplay: "Prepared interface preview",
            volumeId: nil, hadithNumber: "1"))
        model.refresh()
        XCTAssertEqual(model.loadState, .ready)
        XCTAssertEqual(model.savedItems.count, 1)
        model.refresh()
        XCTAssertEqual(model.loadState, .ready)
        XCTAssertEqual(model.savedItems.count, 1)
    }
}
