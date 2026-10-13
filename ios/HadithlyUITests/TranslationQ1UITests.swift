import XCTest

final class TranslationQ1UITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ state: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HADITHLY_UI_TESTING"] = "1"
        app.launchArguments = ["-R6AReaderFixture"]
        app.launchEnvironment["Q1_LANGUAGE"] = "ru"
        app.launchEnvironment["Q1_STATE"] = state
        app.launchEnvironment["R6A_ARABIC_VISIBLE"] = "false"
        app.launch()
        return app
    }

    func testOpeningAndPagingWaitForExplicitHadithAction() {
        let app = launch()
        let generate = app.buttons.matching(identifier: "reader.generateTranslation").firstMatch
        XCTAssertTrue(generate.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(generate.frame.height, 44)
        XCTAssertFalse(app.buttons["reader.quotaPaywall"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["reader.translationAllowance"].exists)
        app.buttons["reader.nextPage"].tap()
        XCTAssertTrue(generate.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["reader.quotaPaywall"].exists)
        generate.tap()
        XCTAssertTrue(app.staticTexts["Sign in to get AI translations in your language."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["reader.quotaPaywall"].exists)
    }

    func testQuotaShowsAllowanceRetryAndPlansOnlyForRejectedHadith() {
        let app = launch("quota")
        XCTAssertTrue(app.buttons["reader.quotaPaywall"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["reader.translationAllowance"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["reader.translationRetryAt"].exists)
    }

    func testRateFailureDoesNotOfferPaywall() {
        let app = launch("rate")
        XCTAssertTrue(app.buttons["reader.retryTranslation"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["reader.quotaPaywall"].exists)
    }

    func testCachedExactLocaleRendersForGuest() {
        let app = launch("cached")
        XCTAssertTrue(app.staticTexts["Cached exact-locale text"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["reader.quotaPaywall"].exists)
    }

    func testQ2QuotaPaywallShowsFiniteAllowanceOwnAccountAndNoWeeklyProduct() {
        let app = launch("quota")
        let plans = app.buttons["reader.quotaPaywall"]
        XCTAssertTrue(plans.waitForExistence(timeout: 10))
        plans.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "5 free or 100 Pro new translations in a rolling 7 days. Approved and cached translations stay free.")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "Use Pro on your own iOS and Android devices with the same Hadithly account. Family Sharing is off.")).firstMatch.exists)
        XCTAssertTrue(app.buttons["Restore purchases"].exists)
        XCTAssertFalse(app.buttons["Weekly"].exists)
        let restore = app.buttons["Restore purchases"]
        if !restore.isHittable { app.swipeUp() }
        restore.tap()
        XCTAssertTrue(app.staticTexts["Sign in to your original Hadithly account before restoring."].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertTrue(plans.waitForExistence(timeout: 5))
    }
}
