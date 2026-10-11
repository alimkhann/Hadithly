import ClerkConvex
import ConvexMobile
import XCTest
@testable import Hadithly

@MainActor
final class TranslationQ1Tests: XCTestCase {
    private func model() -> ReaderModel {
        ReaderModel(convex: ConvexClientWithAuth(deploymentUrl: "https://example.invalid", authProvider: ClerkConvexAuthProvider()),
            collectionSlug: "bukhari", collectionName: "Bukhari", language: "ru", isSignedIn: { false })
    }

    func testLanguageChangeErasesRequestedAllowanceAndQuotaState() {
        let model = model()
        model.seedQ1TranslationForUITest(id: "sunnah_now:bukhari:1", state: .failed(.quotaExceeded),
            allowance: TranslationAllowance(limit: 5, remaining: 0, retryAt: 1000))
        model.setLanguage("ur")
        XCTAssertTrue(model.translationAllowances.isEmpty)
        XCTAssertTrue(model.translations.isEmpty)
        XCTAssertFalse(model.hasQuotaFailure)
    }

    func testAccountChangeErasesPrivateAllowanceAndRejection() {
        let model = model()
        model.seedQ1TranslationForUITest(id: "sunnah_now:bukhari:1", state: .failed(.quotaExceeded),
            allowance: TranslationAllowance(limit: 5, remaining: 0, retryAt: 1000))
        model.resetTranslationRequestsForAccount()
        XCTAssertTrue(model.translationAllowances.isEmpty)
        XCTAssertFalse(model.hasQuotaFailure)
    }

    func testOnlyQuotaErrorMapsToPaywallAndRateErrorPreservesRetryTime() {
        XCTAssertEqual(TranslationFailure(message: "AI_GENERATION_QUOTA_EXCEEDED"), .quotaExceeded)
        for code in ["AI_RATE_LIMITED", "AI_GENERATION_BUSY", "AI_INTEGRITY_REJECTED", "AI_SERVICE_LIMIT", "AI_GENERATION_RETRY"] {
            let failure = TranslationFailure(message: "{\"code\":\"\(code)\",\"retryAt\":1800000000000}")
            XCTAssertNotEqual(failure, .quotaExceeded)
            XCTAssertEqual(failure.retryAt, 1_800_000_000_000)
        }
    }
}
