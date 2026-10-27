import XCTest

final class TranslationQ1UITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ state: String? = nil, theme: String = "dark", locale: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HADITHLY_UI_TESTING"] = "1"
        app.launchArguments = ["-R6AReaderFixture"]
        app.launchEnvironment["Q1_LANGUAGE"] = "ru"
        app.launchEnvironment["Q1_STATE"] = state
        app.launchEnvironment["Q1_UI_LOCALE"] = locale
        app.launchEnvironment["POLISH_THEME"] = theme
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
        XCTAssertTrue(app.staticTexts["Sign in from Settings to translate this hadith."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["reader.quotaPaywall"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["reader.translationAllowance"].exists)
    }

    func testCooldownHasOneDateAndDisablesPrematureRetry() {
        let app = launch("cooldown")
        let retry = app.buttons["reader.retryTranslation"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertFalse(retry.isEnabled)
        XCTAssertEqual(app.staticTexts.matching(identifier: "reader.translationRetryAt").count, 1)
        XCTAssertTrue(app.staticTexts["Translation temporarily unavailable"].exists)
        XCTAssertFalse(app.buttons["reader.quotaPaywall"].exists)
        capture("cooldown", app)
    }

    func testProLimitHasAvailabilityWithoutAnotherUpgradeOffer() {
        let app = launch("paid-quota")
        XCTAssertTrue(app.staticTexts["Translation allowance used"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["reader.translationRetryAt"].exists)
        XCTAssertFalse(app.buttons["reader.quotaPaywall"].exists)
        capture("pro-limit", app)
    }

    func testElapsedQuotaAvailabilityOffersRetry() {
        let app = launch("quota-ready")
        let retry = app.buttons["reader.retryTranslation"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertTrue(retry.isEnabled)
        XCTAssertFalse(app.buttons["reader.quotaPaywall"].exists)
        XCTAssertFalse(app.staticTexts["reader.translationRetryAt"].exists)
    }

    func testReaderStatusGalleryAcrossThemesAndArabic() {
        for (state, theme, locale) in [("", "light", "en"), ("loading", "paper", "en"), ("rate", "dark", "en"), ("quota", "light", "en"), ("quota", "paper", "ar")] {
            let app = launch(state, theme: theme, locale: locale)
            XCTAssertTrue(app.descendants(matching: .any)["reader.translationStatus"].firstMatch.waitForExistence(timeout: 10))
            if locale == "ar" {
                XCTAssertTrue(app.staticTexts["reader.translationAllowance"].label.contains("ترجمة"))
                XCTAssertTrue(app.staticTexts["reader.translationRetryAt"].label.contains("المحاولة"))
            }
            capture("\(state.isEmpty ? "missing" : state)-\(theme)-\(locale)", app)
            app.terminate()
        }
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "reader-status-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testQuotaShowsAllowanceRetryAndPlansOnlyForRejectedHadith() {
        let app = launch("quota")
        XCTAssertTrue(app.buttons["reader.quotaPaywall"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["reader.translationAllowance"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["reader.translationRetryAt"].exists)
    }

    func testQuotaWithUnavailableAllowanceStillOffersAnExplicitPlanAction() {
        let app = launch("quota-unknown")
        XCTAssertTrue(app.buttons["reader.quotaPaywall"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["reader.translationAllowance"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["paywall.quota"].exists)
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
        XCTAssertFalse(app.staticTexts["reader.translationAllowance"].exists)
    }

    func testQ2QuotaPaywallShowsFiniteAllowanceOwnAccountAndNoWeeklyProduct() {
        let app = launch("quota")
        let plans = app.buttons["reader.quotaPaywall"]
        XCTAssertTrue(plans.waitForExistence(timeout: 10))
        plans.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "5 free or 100 Pro new translations in a rolling 7 days. Approved and cached translations stay free.")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "Use Pro on your own iOS and Android devices with the same Hadithly account. Family Sharing is off.")).firstMatch.exists)
        app.buttons["paywall.more"].tap()
        XCTAssertTrue(app.buttons["paywall.restore"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Weekly"].exists)
        let restore = app.buttons["paywall.restore"]
        if !restore.isHittable { app.swipeUp() }
        restore.tap()
        XCTAssertTrue(app.staticTexts["Sign in to your original Hadithly account before restoring."].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertTrue(plans.waitForExistence(timeout: 5))
    }
}
