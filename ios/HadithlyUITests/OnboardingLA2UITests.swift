import XCTest

final class OnboardingLA2UITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testLanguageRoundTripRestoresEnglishRowAndBackAlignment() {
        let app = XCUIApplication()
        app.launchArguments = ["-FreshInstallForUITest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HADITHLY_UI_TESTING"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.getStarted"].waitForExistence(timeout: 10))
        app.buttons["onboarding.getStarted"].tap()
        app.buttons["onboarding.language.en"].tap()
        let english = app.staticTexts["English"].firstMatch
        XCTAssertTrue(english.exists)
        let nameX = english.frame.minX
        let backX = app.buttons["onboarding.back"].frame.midX
        for code in ["ar", "ur"] {
            let choice = app.buttons["onboarding.language.\(code)"]
            if !choice.isHittable { app.swipeUp() }
            choice.tap()
            XCTAssertGreaterThan(app.buttons["onboarding.back"].frame.midX, app.frame.midX)
            let first = app.buttons["onboarding.language.en"]
            if !first.isHittable { app.swipeDown() }
            first.tap()
            XCTAssertEqual(english.frame.minX, nameX, accuracy: 1)
            XCTAssertEqual(app.buttons["onboarding.back"].frame.midX, backX, accuracy: 1)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "onboarding-\(code)-to-en"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testGuestFlowLoadsDailyHadithAndCancelledSignInRemainsUsable() {
        let app = XCUIApplication()
        app.launchArguments = ["-FreshInstallForUITest"]
        app.launchEnvironment["HADITHLY_UI_TESTING"] = "1"
        app.launch()
        let started = app.buttons["onboarding.getStarted"]
        XCTAssertTrue(started.waitForExistence(timeout: 10))
        let welcomeCTA = started.frame.minY
        XCTAssertFalse(app.buttons["settings.usageStatistics"].exists)
        started.tap()
        app.buttons["onboarding.language.en"].tap()
        let next = app.buttons["onboarding.continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertEqual(next.frame.minY, welcomeCTA, accuracy: 1)
        let languageCTA = next.frame.minY
        next.tap()
        XCTAssertTrue(waitForOnboardingDailyResult(app))
        XCTAssertEqual(next.frame.minY, languageCTA, accuracy: 1)
        let demo = XCTAttachment(screenshot: app.screenshot()); demo.name = "LA2 daily hadith"; demo.lifetime = .keepAlways; add(demo)
        next.tap()
        let signIn = app.buttons["onboarding.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 5)); signIn.tap()
        let close = app.buttons["signin.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5)); close.tap()
        let guest = app.buttons["onboarding.guest"]
        XCTAssertTrue(guest.waitForExistence(timeout: 5)); XCTAssertGreaterThanOrEqual(guest.frame.height, 44)
        let choice = XCTAttachment(screenshot: app.screenshot()); choice.name = "LA2 account choice"; choice.lifetime = .keepAlways; add(choice)
        guest.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        app.tabBars.buttons["Library"].tap()
        let collection = app.buttons["library.collection.bukhari"]
        XCTAssertTrue(collection.waitForExistence(timeout: 20)); collection.tap()
        XCTAssertTrue(app.buttons["reader.hadithLabel"].firstMatch.waitForExistence(timeout: 30))
        app.swipeUp()
        Thread.sleep(forTimeInterval: 1)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 4)
        app.launchArguments = []
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["onboarding.getStarted"].exists)
    }

    @discardableResult
    private func waitForOnboardingDailyResult(_ app: XCUIApplication) -> Bool {
        let text = app.descendants(matching: .any).matching(identifier: "onboarding.dailyText").firstMatch
        let retry = app.buttons["onboarding.dailyRetry"]
        let unavailable = app.descendants(matching: .any).matching(identifier: "onboarding.readingUnavailable").firstMatch
        let result = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in text.exists || retry.exists || unavailable.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [result], timeout: 20), .completed)
        return text.exists || retry.exists || unavailable.exists
    }
}
