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
}
