import XCTest

/// Monochrome review set: Today, Library, and Saved render with the neutral
/// chrome and keep their layouts. Saved is empty when signed out.
final class TabChromeUITests: XCTestCase {
    private let timeout: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTodayLibraryAndSavedChrome() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: timeout))
        takeScreenshot(named: "chrome-today")

        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: timeout))
        takeScreenshot(named: "chrome-library")

        app.tabBars.buttons["Saved"].tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: timeout))
        takeScreenshot(named: "chrome-saved")
    }

    private func takeScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
