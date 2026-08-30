import XCTest

final class Phase4TranslationFlowTests: XCTestCase {
    private let timeout: TimeInterval = 20

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSubmitReportApproveAndPublish() throws {
        let app = XCUIApplication()
        app.launch()

        openBukhariReader(app)
        chooseRussian(app)
        scrollToContributionActions(app)

        let report = app.buttons["reader.reportTranslation"].firstMatch
        XCTAssertTrue(report.waitForExistence(timeout: timeout), "Stored translation never loaded")

        app.buttons["reader.suggestTranslation"].firstMatch.tap()
        XCTAssertTrue(app.textViews["submission.editor"].waitForExistence(timeout: timeout))
        app.buttons["submission.submit"].tap()
        XCTAssertTrue(
            element("submission.verdict", in: app).waitForExistence(timeout: 90),
            "Gemini review verdict did not arrive"
        )
        takeScreenshot(named: "01-submission-verdict")
        app.buttons["Done"].tap()

        XCTAssertTrue(report.waitForExistence(timeout: timeout))
        report.tap()
        let reportEditor = app.textViews["report.editor"]
        XCTAssertTrue(reportEditor.waitForExistence(timeout: timeout))
        reportEditor.tap()
        reportEditor.typeText("Phase 4 simulator verification report; safe to dismiss.")
        app.buttons["report.submit"].tap()
        XCTAssertTrue(element("report.confirmation", in: app).waitForExistence(timeout: timeout))
        takeScreenshot(named: "02-report-confirmation")
        app.buttons["Done"].tap()

        if !app.buttons["reader.close"].isHittable {
            element("reader.page", in: app).tap()
        }
        app.buttons["reader.close"].tap()
        app.tabBars.buttons["Settings"].tap()

        let review = app.buttons["settings.translationReview"]
        XCTAssertTrue(review.waitForExistence(timeout: timeout), "Admin review entry did not appear")
        review.tap()

        let approve = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'admin.approve.'")
        ).firstMatch
        XCTAssertTrue(approve.waitForExistence(timeout: timeout), "Submission did not enter the admin queue")
        approve.tap()
        XCTAssertTrue(element("admin.empty", in: app).waitForExistence(timeout: timeout))
        takeScreenshot(named: "03-admin-approved")
        app.buttons["Done"].tap()

        app.tabBars.buttons["Library"].tap()
        app.buttons["library.collection.bukhari"].tap()
        XCTAssertTrue(element("reader.page", in: app).waitForExistence(timeout: timeout))
        chooseRussian(app)
        let communityBadge = element("reader.communityBadge", in: app)
        scrollUntilHittable(communityBadge, in: app)
        XCTAssertTrue(
            communityBadge.waitForExistence(timeout: timeout),
            "Approved community translation did not become the reader default"
        )
        takeScreenshot(named: "04-community-default")
    }

    private func openBukhariReader(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["Library"].waitForExistence(timeout: timeout))
        app.tabBars.buttons["Library"].tap()
        let collection = app.buttons["library.collection.bukhari"]
        XCTAssertTrue(collection.waitForExistence(timeout: timeout))
        collection.tap()
        XCTAssertTrue(element("reader.page", in: app).waitForExistence(timeout: timeout))
    }

    private func chooseRussian(_ app: XCUIApplication) {
        if !app.buttons["reader.settings"].isHittable {
            element("reader.page", in: app).tap()
        }
        XCTAssertTrue(app.buttons["reader.settings"].waitForExistence(timeout: timeout))
        app.buttons["reader.settings"].tap()
        let russian = app.buttons["reader.language.ru"]
        XCTAssertTrue(russian.waitForExistence(timeout: timeout))
        russian.tap()
        app.buttons["Done"].tap()
    }

    private func scrollToContributionActions(_ app: XCUIApplication) {
        scrollUntilHittable(app.buttons["reader.suggestTranslation"].firstMatch, in: app)
        XCTAssertTrue(app.buttons["reader.suggestTranslation"].firstMatch.isHittable)
    }

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 where !element.isHittable {
            app.swipeUp()
        }
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func takeScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
