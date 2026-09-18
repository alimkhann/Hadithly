import XCTest

/// S1 gate: signed-out Settings shows every row, each row opens a finished
/// destination (no dead placeholders), and the admin queue stays out of the
/// consumer app. One pass walks all ten signed-out destinations.
final class SettingsS1UITests: XCTestCase {
    private let timeout: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSignedOutSettingsNavigatesEveryDestination() throws {
        let app = XCUIApplication()
        app.launch()

        let tabs = app.tabBars.buttons["Settings"]
        XCTAssertTrue(tabs.waitForExistence(timeout: timeout))
        takeScreenshot(named: "s1-today-after")
        tabs.tap()

        // Guest card offers sign-in; profile stays a signed-in destination.
        XCTAssertTrue(app.buttons["settings.signin"].waitForExistence(timeout: timeout))
        XCTAssertFalse(app.buttons["settings.row.profile"].exists)

        let rows: [(row: String, probe: String)] = [
            ("settings.row.appearance", "settings.appearance.system"),
            ("settings.row.appLanguage", "settings.uiLanguage.en"),
            ("settings.row.hadithTranslation", "settings.language.en"),
            ("settings.row.readingAndType", "settings.arabicSize"),
            ("settings.row.offlineStorage", "settings.offline.learnMore"),
            ("settings.row.notifications", "settings.notifications.signedOut"),
            ("settings.row.subscription", "settings.subscription.signedOut"),
            ("settings.row.privacyAndData", "settings.deletionInfo"),
            ("settings.row.helpAndSupport", "settings.help.contact"),
            ("settings.row.aboutAndLegal", "settings.about.licenses"),
        ]

        for (row, probe) in rows {
            // List rows virtualize: scroll until the row enters the hierarchy.
            var rowButton = app.buttons[row]
            var found = rowButton.waitForExistence(timeout: 2)
            for _ in 0..<10 where !found {
                app.swipeUp()
                found = rowButton.waitForExistence(timeout: 2)
            }
            XCTAssertTrue(found, "missing row \(row)")
            rowButton = app.buttons[row]
            scrollUntilHittable(rowButton, in: app)
            rowButton.tap()
            XCTAssertTrue(
                app.descendants(matching: .any)[probe].waitForExistence(timeout: timeout),
                "row \(row) opened no finished content (\(probe))"
            )
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(
                app.buttons[row].waitForExistence(timeout: timeout),
                "back from \(row) did not return to Settings"
            )
        }

        // The admin queue must not ship in consumer Settings.
        XCTAssertFalse(app.buttons["settings.translationReview"].exists)
        takeScreenshot(named: "s1-settings-after")
    }

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.isHittable { return }
            app.swipeUp()
        }
    }

    private func takeScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
