import XCTest

final class W2WidgetGalleryUITests: XCTestCase {
    func testContinueReadingCanBePlacedAndOpenedFromHome() {
        let app = XCUIApplication()
        app.launch()
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
        let resumeWidget = springboard.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Continue Reading,'")
        ).firstMatch
        let emptyWidget = springboard.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Read a hadith to continue here.' OR label CONTAINS 'اقرأ حديثًا للمتابعة هنا.' OR label CONTAINS 'یہاں سے جاری رکھنے کے لیے حدیث پڑھیں۔'")
        ).firstMatch
        let alreadyInstalled = resumeWidget.exists || emptyWidget.exists

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
        XCTAssertTrue(resumeWidget.exists || emptyWidget.waitForExistence(timeout: 10))
        let installedScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        installedScreenshot.name = "continue-reading-installed"
        installedScreenshot.lifetime = .keepAlways
        add(installedScreenshot)

        if resumeWidget.exists {
            resumeWidget.tap()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "reader.page").firstMatch.waitForExistence(timeout: 25))
        }
    }
}
