import XCTest

final class Phase4TranslationFlowTests: XCTestCase {
    private let timeout: TimeInterval = 20

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testEvidenceSuggestionRequiresSignInAndAdminQueueStaysHidden() throws {
        let app = XCUIApplication()
        app.launch()

        openBukhariReader(app)
        settleReaderOnAnyHadith(app)
        openMoreActions(app)

        app.buttons["reader.suggestTranslation"].firstMatch.tap()
        XCTAssertTrue(
            element("submission.signInRequired", in: app).waitForExistence(timeout: timeout),
            "Guest evidence contribution must require sign-in"
        )
        takeScreenshot(named: "01-evidence-sign-in")
        app.buttons["Done"].tap()
        XCTAssertFalse(
            app.textViews["submission.editor"].waitForExistence(timeout: 3),
            "Submission sheet did not dismiss"
        )

        if !app.buttons["reader.close"].isHittable {
            element("reader.page", in: app).tap()
        }
        app.buttons["reader.close"].tap()
        app.tabBars.buttons["Settings"].tap()

        // S1 moved the admin queue out of the consumer app (E4 owns the
        // secured exception tool): Settings must not expose a review entry.
        XCTAssertFalse(
            app.buttons["settings.translationReview"].waitForExistence(timeout: 3),
            "Admin review must not ship in consumer Settings"
        )
        // E1 quarantine is tested through its authenticated upload flow;
        // publication remains unavailable until the later evidence sessions.
    }

    func testReportRemainsPrivateWhenStoredTranslationIsAvailable() throws {
        let app = XCUIApplication()
        app.launch()
        openBukhariReader(app)
        chooseRussian(app)
        guard openMoreActionsWaitingForReport(app) else {
            throw XCTSkip("No stored Russian translation loaded in the development reader")
        }
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
    }

    private func openBukhariReader(_ app: XCUIApplication) {
        if !app.tabBars.buttons["Library"].waitForExistence(timeout: 3) {
            let continueButton = app.buttons["Continue"]
            XCTAssertTrue(continueButton.waitForExistence(timeout: timeout))
            continueButton.tap()
            XCTAssertTrue(continueButton.waitForExistence(timeout: timeout))
            continueButton.tap()
        }
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
        let translationSettings = app.buttons["reader.settings.translation"]
        XCTAssertTrue(translationSettings.waitForExistence(timeout: timeout))
        translationSettings.tap()
        let russian = app.buttons["reader.language.ru"]
        XCTAssertTrue(russian.waitForExistence(timeout: timeout))
        russian.tap()
        // The Sajda-styled settings sheet closes with its X circle.
        app.buttons["reader.settings.close"].tap()
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
    private func openMoreActionsWaitingForReport(_ app: XCUIApplication) -> Bool {
        settleReaderOnAnyHadith(app)
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            openMoreActions(app)
            if app.buttons["reader.reportTranslation"].firstMatch.waitForExistence(timeout: 3) {
                return true
            }
            // The menu is still open but lacks Report: tap outside to
            // dismiss it, then poll again once the translation may have
            // arrived.
            dismissMoreActions(app)
            if Date() >= deadline { return false }
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
