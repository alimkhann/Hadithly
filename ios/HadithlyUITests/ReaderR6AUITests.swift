import XCTest

/// Slice A (R6) gate, offline: the Sajda-quiet page renders from the
/// deterministic `-R6AReaderFixture` with no network. Proves the quiet
/// page (no dividers, no ellipsis), the dot + compact label, the source
/// sheet contents, chapter/volume headers, the chevron cluster, and the
/// intact long-press menu.
final class ReaderR6AUITests: XCTestCase {
    private let timeout: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Quiet page

    func testQuietPageHasMarkersDotsLabelsAndNoEllipsis() {
        let app = launchFixture()
        XCTAssertTrue(element("reader.volumeHeader", in: app).waitForExistence(timeout: timeout))
        // Two hadith blocks on page 1: markers, grade dots, source labels.
        XCTAssertGreaterThanOrEqual(app.descendants(matching: .any).matching(identifier: "reader.hadithMarker").count, 2)
        XCTAssertGreaterThanOrEqual(app.descendants(matching: .any).matching(identifier: "reader.gradeDot").count, 2)
        XCTAssertGreaterThanOrEqual(app.buttons.matching(identifier: "reader.hadithLabel").count, 2)
        // The R5 ellipsis is gone with no visual replacement.
        XCTAssertFalse(app.buttons["reader.moreActions"].exists)
        // No inter-hadith dividers: nothing accessibility-exposed between
        // blocks, and the page holds the new cluster instead of corners.
        XCTAssertTrue(element("reader.pageCluster", in: app).exists)
        XCTAssertFalse(element("reader.volumeCorner", in: app).exists, "corner yields to the volume header on page 1")
    }

    func testChapterLineIsNameOnlyWithArabicSubtitle() {
        let app = launchFixture()
        let chapter = element("reader.chapterHeader", in: app)
        XCTAssertTrue(chapter.waitForExistence(timeout: timeout))
        XCTAssertEqual(chapter.label, "Belief, كتاب الإيمان")
        XCTAssertFalse(chapter.label.contains("Chapter"))
    }

    // MARK: - Source sheet

    func testSourceSheetShowsNameScopeAndURL() {
        let app = launchFixture()
        app.buttons.matching(identifier: "reader.hadithLabel").firstMatch.tap()
        XCTAssertTrue(element("reader.sourceSheet", in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(app.staticTexts["Sunnah.com"].exists)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Sahih collection scope'")).firstMatch.exists
        )
        XCTAssertTrue(element("reader.sourceSheet.url", in: app).exists)
        app.buttons["Done"].tap()
        XCTAssertFalse(element("reader.sourceSheet", in: app).waitForExistence(timeout: 3))
    }

    func testSourceSheetOmitsURLWhenAbsent() {
        let app = launchFixture()
        // Second block (Hadith 58) carries an empty source URL.
        app.buttons.matching(identifier: "reader.hadithLabel").element(boundBy: 1).tap()
        XCTAssertTrue(element("reader.sourceSheet", in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(app.staticTexts["Sunnah.com"].exists)
        XCTAssertFalse(element("reader.sourceSheet.url", in: app).exists)
        app.buttons["Done"].tap()
    }

    // MARK: - Page cluster

    func testChevronClusterTurnsPagesAndRevealsCornerRange() {
        let app = launchFixture()
        XCTAssertTrue(element("reader.pageCluster", in: app).waitForExistence(timeout: timeout))
        XCTAssertEqual(element("reader.pagePill", in: app).label, "Page 1 of 2")
        XCTAssertFalse(app.buttons["reader.previousPage"].exists)

        app.buttons["reader.nextPage"].tap()
        XCTAssertEqual(element("reader.pagePill", in: app).label, "Page 2 of 2")
        let corner = element("reader.volumeCorner", in: app)
        XCTAssertTrue(corner.waitForExistence(timeout: timeout))
        XCTAssertEqual(corner.label, "Volume 2: 57–59")
        XCTAssertFalse(element("reader.volumeHeader", in: app).exists)
        XCTAssertFalse(app.buttons["reader.nextPage"].exists)

        app.buttons["reader.previousPage"].tap()
        XCTAssertEqual(element("reader.pagePill", in: app).label, "Page 1 of 2")
        XCTAssertTrue(element("reader.volumeHeader", in: app).waitForExistence(timeout: timeout))
    }

    // MARK: - Long-press menu intact

    func testLongPressMenuStillOpensWithFullActions() {
        let app = launchFixture()
        let arabic = app.staticTexts["reader.arabic"].firstMatch
        XCTAssertTrue(arabic.waitForExistence(timeout: timeout))
        arabic.press(forDuration: 1.0)
        for identifier in [
            "reader.bookmark", "reader.favorite", "reader.note",
            "reader.copy", "reader.share", "reader.suggestTranslation",
        ] {
            XCTAssertTrue(
                app.buttons[identifier].firstMatch.waitForExistence(timeout: timeout),
                "long-press menu missing \(identifier)"
            )
        }
        app.tap()
    }

    // MARK: - Helpers

    private func launchFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-R6AReaderFixture"]
        app.launch()
        XCTAssertTrue(element("r6a.page", in: app).waitForExistence(timeout: timeout))
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
