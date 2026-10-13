import XCTest

final class OnboardingLA2UITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testGuestFlowDemoAndCancelledSignupRemainUsable() {
        let app = XCUIApplication()
        app.launchEnvironment["HADITHLY_UI_TESTING"] = "1"
        app.launch()
        let started = app.buttons["onboarding.getStarted"]
        XCTAssertTrue(started.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["settings.usageStatistics"].exists)
        started.tap()
        let next = app.buttons["onboarding.continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 5)); next.tap()
        let reveal = app.buttons["onboarding.reveal"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 5)); reveal.tap()
        XCTAssertTrue(app.staticTexts["onboarding.example"].waitForExistence(timeout: 5))
        let demo = XCTAttachment(screenshot: app.screenshot()); demo.name = "LA2 card-free example"; demo.lifetime = .keepAlways; add(demo)
        next.tap()
        let create = app.buttons["onboarding.createAccount"]
        XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap()
        let close = app.buttons["Close"]
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
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["onboarding.getStarted"].exists)
    }
}
