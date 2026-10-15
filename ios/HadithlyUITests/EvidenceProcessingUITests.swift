import XCTest

final class EvidenceProcessingUITests: XCTestCase {
    func testE4ContributorAppealAndOperatorAbsence() {
        let app = XCUIApplication()
        app.launchArguments = ["-E2ProcessingFixture"]
        app.launchEnvironment["HADITHLY_UI_TESTING"] = "1"
        app.launch()
        app.buttons["e2.fixture.rejected"].tap()
        let reason = app.textFields["submission.appealReason"]
        if !reason.isHittable { app.swipeUp() }
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        reason.tap()
        reason.typeText("Check the supplied source again.")
        let appeal = app.buttons["submission.appeal"]
        if !appeal.isHittable { app.swipeUp() }
        XCTAssertGreaterThanOrEqual(appeal.frame.height, 44)
        appeal.tap()
        XCTAssertTrue(app.staticTexts["submission.under_review"].exists)
        XCTAssertFalse(app.buttons["submission.appeal"].exists)
        XCTAssertFalse(app.debugDescription.contains("Operator"))
        XCTAssertFalse(app.debugDescription.contains("Admin review"))
    }
    func testE3PrivateStatusAndCitations() {
        let app = XCUIApplication()
        app.launchArguments = ["-E2ProcessingFixture"]
        app.launchEnvironment["HADITHLY_UI_TESTING"] = "1"
        app.launch()
        for status in ["under_review", "held", "rejected", "review_unavailable", "approved"] {
            app.buttons["e2.fixture.\(status)"].tap()
            XCTAssertTrue(app.staticTexts["submission.\(status)"].exists)
            let citation = app.descendants(matching: .any)["submission.citation.0"].firstMatch
            if !citation.isHittable { app.swipeUp() }
            XCTAssertTrue(citation.exists)
            XCTAssertGreaterThanOrEqual(citation.frame.height, 44 - 0.01)
            XCTAssertFalse(app.debugDescription.contains("confidence"))
            XCTAssertFalse(app.debugDescription.contains("reputation"))
            XCTAssertEqual(app.buttons["submission.deleteDraft"].exists, status != "approved")
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "E3 published status and source"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(app.staticTexts["reader.translation"].exists)
        app.buttons["reader.communityBadge"].tap()
        XCTAssertTrue(app.staticTexts["translation.sources.community"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["translation.sources.ai"].exists)
    }

    func testProcessingFailureInfectionAndRetryAreCoarseAccessibleStates() {
        let app = XCUIApplication()
        app.launchArguments = ["-E2ProcessingFixture"]
        app.launchEnvironment["HADITHLY_UI_TESTING"] = "1"
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["submission.processing"].waitForExistence(timeout: 10))
        app.buttons["e2.fixture.processing_failed"].tap()
        XCTAssertTrue(app.staticTexts["submission.failed"].exists)
        XCTAssertGreaterThanOrEqual(app.buttons["submission.retryProcessing"].frame.height, 44)
        app.buttons["submission.retryProcessing"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["submission.processing"].exists)
        app.buttons["e2.fixture.infected"].tap()
        XCTAssertTrue(app.staticTexts["submission.infected"].exists)
        XCTAssertFalse(app.buttons["submission.retryProcessing"].exists)
        app.buttons["e2.fixture.evidence_ready"].tap()
        XCTAssertTrue(app.staticTexts["submission.ready"].exists)
        XCTAssertFalse(app.debugDescription.contains("ClamAV"))
        XCTAssertGreaterThanOrEqual(app.buttons["submission.deleteDraft"].frame.height, 44)
    }
}
