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

        // Slice A: Suggest/Report live only in the per-hadith long-press
        // menu (the R5 ellipsis is deleted). Report appears only once the
        // stored translation has loaded, so poll the menu until it does.
        openMoreActionsWaitingForReport(app)

        app.buttons["reader.suggestTranslation"].firstMatch.tap()
        XCTAssertTrue(app.textViews["submission.editor"].waitForExistence(timeout: timeout))
        app.buttons["submission.submit"].tap()
        XCTAssertTrue(
            element("submission.verdict", in: app).waitForExistence(timeout: 90),
            "Gemini review verdict did not arrive"
        )
        takeScreenshot(named: "01-submission-verdict")
        app.buttons["Done"].tap()
        // The verdict sheet must be gone before touching the reader:
        // otherwise its editor still exists behind the reader page.
        XCTAssertFalse(
            app.textViews["submission.editor"].waitForExistence(timeout: 3),
            "Submission sheet did not dismiss"
        )

        openMoreActions(app)
        let report = app.buttons["reader.reportTranslation"].firstMatch
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
        if !app.buttons["reader.menu"].isHittable {
            element("reader.page", in: app).tap()
        }
        XCTAssertTrue(app.buttons["reader.menu"].waitForExistence(timeout: timeout))
        app.buttons["reader.menu"].tap()
        let settingsCard = app.buttons["reader.menu.settings"]
        XCTAssertTrue(settingsCard.waitForExistence(timeout: timeout), "reader menu never opened")
        settingsCard.tap()
        let russian = app.buttons["reader.language.ru"]
        XCTAssertTrue(russian.waitForExistence(timeout: timeout))
        russian.tap()
        app.buttons["Done"].tap()
    }

    /// The reader restores the last saved position, so the first block in
    /// the hierarchy may be far off-screen. This flow is hadith-agnostic:
    /// any on-screen hadith works, so settle on whichever block is
    /// reachable instead of assuming Hadith 1. Slice A deleted the R5
    /// ellipsis, so reachability means hittable Arabic text to long-press.
    private func hittableHadithText(_ app: XCUIApplication) -> XCUIElement? {
        let query = app.staticTexts.matching(identifier: "reader.arabic")
        for index in 0..<query.count {
            let text = query.element(boundBy: index)
            if text.isHittable {
                return text
            }
        }
        return nil
    }

    /// Brings some hadith block on screen without opening any menu, so the
    /// polling loop below never scrolls while a menu is involved.
    private func settleReaderOnAnyHadith(_ app: XCUIApplication) {
        if hittableHadithText(app) != nil {
            return
        }
        for _ in 0..<15 {
            app.swipeDown()
            if hittableHadithText(app) != nil {
                return
            }
        }
        for _ in 0..<15 {
            app.swipeUp()
            if hittableHadithText(app) != nil {
                return
            }
        }
        XCTFail("No hadith text reachable")
    }

    private func openMoreActions(_ app: XCUIApplication) {
        guard let text = hittableHadithText(app) else {
            takeScreenshot(named: "99-hadith-text-unhittable")
            XCTFail("Hadith text never became hittable")
            return
        }
        text.press(forDuration: 1.0)
    }

    /// Toggles an open context menu closed with a tap outside it.
    private func dismissMoreActions(_ app: XCUIApplication) {
        app.tap()
    }

    /// Opens the long-press menu and waits for the stored translation to
    /// load, signaled by the Report item. Retries because an open menu
    /// does not reliably gain items that arrive later: a menu opened
    /// before the translation arrives may have no Report row. Never
    /// scrolls while polling, so every attempt targets the same settled
    /// block.
    private func openMoreActionsWaitingForReport(_ app: XCUIApplication) {
        settleReaderOnAnyHadith(app)
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            openMoreActions(app)
            if app.buttons["reader.reportTranslation"].firstMatch.waitForExistence(timeout: 3) {
                return
            }
            // The menu is still open but lacks Report: tap outside to
            // dismiss it, then poll again once the translation may have
            // arrived.
            dismissMoreActions(app)
            XCTAssertLessThan(Date(), deadline, "Stored translation never loaded")
            Thread.sleep(forTimeInterval: 2)
        }
    }

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 where !element.isHittable {
            app.swipeUp()
        }
        // The target may sit above the settled position; come back down.
        for _ in 0..<24 where !element.isHittable {
            app.swipeDown()
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
