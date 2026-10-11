import XCTest

final class EvidenceProcessingUITests: XCTestCase {
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
