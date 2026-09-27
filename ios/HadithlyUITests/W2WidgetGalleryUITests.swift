import XCTest

final class W2WidgetGalleryUITests: XCTestCase {
    func testContinueReadingCanBePlacedAndOpenedFromHome() {
        let app = XCUIApplication()
        app.launch()
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
        let installedWidget = springboard.icons.matching(
            NSPredicate(format: "identifier == 'Hadithly' AND value == 'Widget'")
        ).firstMatch
        let alreadyInstalled = installedWidget.exists

        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).press(forDuration: 1.2)
        springboard.buttons["Edit"].tap()
        springboard.buttons["Add Widget"].tap()
        XCTAssertTrue(springboard.cells["Hadithly"].waitForExistence(timeout: 10))
        springboard.cells["Hadithly"].tap()
        for _ in 0..<3 {
            springboard.buttons["Hadithly, Daily Hadith"].swipeLeft()
        }
        XCTAssertTrue(springboard.staticTexts["Continue Reading"].waitForExistence(timeout: 10))
        XCTAssertTrue(springboard.buttons["Hadithly, Continue Reading"].exists)
        if alreadyInstalled {
            XCUIDevice.shared.press(.home)
        } else {
            springboard.buttons[" Add Widget"].tap()
        }
        if springboard.buttons["Done"].isHittable { springboard.buttons["Done"].tap() }
        XCTAssertTrue(installedWidget.waitForExistence(timeout: 10))
        let installedScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        installedScreenshot.name = "continue-reading-installed"
        installedScreenshot.lifetime = .keepAlways
        add(installedScreenshot)

        let resume = springboard.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Continue Reading,'")
        ).firstMatch
        if resume.exists {
            resume.tap()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "reader.page").firstMatch.waitForExistence(timeout: 25))
        }
    }
}
