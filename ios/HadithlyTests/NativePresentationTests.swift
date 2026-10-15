import XCTest
import ConvexMobile
import ClerkConvex
@testable import Hadithly

@MainActor
final class NativePresentationTests: XCTestCase {
    func testReaderExperiencePersistsManualChoiceAndOffersHintOnce() {
        let name = "reader-experience-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = ReaderExperiencePreferences(defaults: defaults)
        XCTAssertTrue(preferences.automaticallyTranslates)
        preferences.automaticallyTranslates = false
        XCTAssertFalse(ReaderExperiencePreferences(defaults: defaults).automaticallyTranslates)
        preferences.offerActionHint()
        XCTAssertTrue(preferences.showsActionHint)
        preferences.dismissActionHint()
        preferences.offerActionHint()
        XCTAssertFalse(preferences.showsActionHint)
        let relaunched = ReaderExperiencePreferences(defaults: defaults)
        relaunched.offerActionHint()
        XCTAssertFalse(relaunched.showsActionHint)
    }

    func testAutomaticRequestsArePerLocaleAndNeverReplaceAvailableOrFailedText() {
        var requests = ReaderAutomaticTranslationLedger()
        XCTAssertFalse(requests.claim(hadithId: "1", locale: "en", hasTranslation: true, hasRequestState: false))
        XCTAssertFalse(requests.claim(hadithId: "1", locale: "ru", hasTranslation: false, hasRequestState: true))
        XCTAssertTrue(requests.claim(hadithId: "1", locale: "ru", hasTranslation: false, hasRequestState: false))
        XCTAssertFalse(requests.claim(hadithId: "1", locale: "ru", hasTranslation: false, hasRequestState: false))
        XCTAssertTrue(requests.claim(hadithId: "1", locale: "kk", hasTranslation: false, hasRequestState: false))
    }

    func testAutomaticTranslationWaitsForVisibleContentAndHonorsManualChoice() async throws {
        let client = ConvexClientWithAuth(deploymentUrl: "https://example.invalid", authProvider: ClerkConvexAuthProvider())
        let model = ReaderModel(convex: client, collectionSlug: "bukhari", collectionName: "Prepared", language: "ru", isSignedIn: { true })
        var enabled = false
        model.automaticTranslationEnabled = { enabled }
        var requests: [String] = []
        model.automaticRequestForUITest = { requests.append($0.internalId) }
        let hadith = ReaderR6Round3FixtureHadith.hadith57
        let frame = [hadith.internalId: ReaderAnchorFrame(minY: 20, height: 300)]
        model.observeVisibleContent(hadiths: [hadith], frames: frame, viewport: 800)
        try await Task.sleep(for: .milliseconds(550))
        XCTAssertTrue(requests.isEmpty)
        enabled = true
        model.refreshAutomaticTranslationPreference()
        try await Task.sleep(for: .milliseconds(550))
        XCTAssertEqual(requests, [hadith.internalId])
        model.observeVisibleContent(hadiths: [hadith], frames: [:], viewport: 800)
        model.observeVisibleContent(hadiths: [hadith], frames: frame, viewport: 800)
        try await Task.sleep(for: .milliseconds(550))
        XCTAssertEqual(requests.count, 1)
        model.resetTranslationRequestsForAccount()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(requests.count, 1, "Changing account must restart the visible-content dwell")
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(requests.count, 2)
        model.stop()
    }

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
