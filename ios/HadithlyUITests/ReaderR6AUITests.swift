import XCTest

/// Slice A (R6) gate, offline: the Sajda-quiet page renders from the
/// deterministic `-R6AReaderFixture` with no network. Proves the quiet
/// page (no dividers, no ellipsis), the top header (dot + bracketed label
/// + saved-state markers), the source sheet contents, chapter/volume
/// headers, the snug chevron cluster, the volume-range rule, the
/// Arabic-only narrator rule, and the intact long-press menu.
final class ReaderR6AUITests: XCTestCase {
    private let timeout: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Quiet page

    func testQuietPageHasHeadersMarkersAndNoEllipsis() {
        let app = launchFixture()
        XCTAssertTrue(element("reader.volumeHeader", in: app).waitForExistence(timeout: timeout))
        // Two hadith blocks on page 1, each with one tappable top header.
        XCTAssertGreaterThanOrEqual(app.buttons.matching(identifier: "reader.hadithLabel").count, 2)
        // The bottom compact label and the dim bare-number marker are gone:
        // both were replaced by the header.
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "reader.hadithMarker").firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "reader.gradeDot").firstMatch.exists)
        // The R5 ellipsis is gone with no visual replacement.
        XCTAssertFalse(app.buttons["reader.moreActions"].exists)
        // The header opens the source sheet (Hadith 57 carries a URL).
        app.buttons.matching(identifier: "reader.hadithLabel").firstMatch.tap()
        XCTAssertTrue(element("reader.sourceSheet", in: app).waitForExistence(timeout: timeout))
        app.buttons["Done"].tap()
        // No inter-hadith dividers: the page holds the new cluster instead
        // of corners, and the corner yields to the volume header on page 1.
        XCTAssertTrue(element("reader.pageCluster", in: app).exists)
        XCTAssertFalse(element("reader.volumeCorner", in: app).exists, "corner yields to the volume header on page 1")
    }

    func testSavedStateMiniMarkers() {
        let app = launchFixture()
        XCTAssertTrue(element("reader.volumeHeader", in: app).waitForExistence(timeout: timeout))
        // Hadith 57 is bookmarked: the amber mini marker renders inline
        // after its header. Hadith 58 is neither: no heart on page 1.
        XCTAssertTrue(element("reader.savedBookmark", in: app).exists)
        XCTAssertFalse(element("reader.savedFavorite", in: app).exists)
        // Hadith 59 is favorited: turning to page 2 shows the pink heart
        // and no bookmark.
        app.buttons["reader.nextPage"].tap()
        XCTAssertTrue(element("reader.savedFavorite", in: app).waitForExistence(timeout: timeout))
        XCTAssertFalse(element("reader.savedBookmark", in: app).exists)
    }

    func testChapterLineIsNameOnlyWithArabicSubtitle() {
        let app = launchFixture()
        let chapter = element("reader.chapterHeader", in: app)
        XCTAssertTrue(chapter.waitForExistence(timeout: timeout))
        XCTAssertEqual(chapter.label, "Belief, كتاب الإيمان")
        XCTAssertFalse(chapter.label.contains("Chapter"))
    }

    // MARK: - Narrator (translation metadata)

    func testNarratorShowsWithTranslationLayer() {
        let app = launchFixture()
        let narrator = element("reader.narrator", in: app)
        XCTAssertTrue(narrator.waitForExistence(timeout: timeout))
        XCTAssertTrue(narrator.label.contains("Umar"))
    }

    func testNarratorHiddenInArabicOnlyMode() {
        let app = launchFixture(environment: ["R6A_TRANSLATION_VISIBLE": "false"])
        XCTAssertTrue(element("r6a.page", in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(element("reader.arabic", in: app).waitForExistence(timeout: timeout))
        XCTAssertFalse(element("reader.narrator", in: app).exists, "narrator hides with the translation layer")
        XCTAssertFalse(element("reader.translation", in: app).exists)
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

        // Snug: the next chevron sits a few points from the label, not at
        // an outer corner.
        XCTAssertLessThan(
            gapBetweenLabelAndChevron(in: app, chevron: "reader.nextPage"),
            16,
            "chevron must sit snug against the page label"
        )

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

    func testCornerLabelStaysTitleOnlyUntilFullyCached() {
        let app = launchFixture(environment: ["R6A_FULL_CACHE": "false"])
        XCTAssertTrue(element("reader.pageCluster", in: app).waitForExistence(timeout: timeout))
        app.buttons["reader.nextPage"].tap()
        let corner = element("reader.volumeCorner", in: app)
        XCTAssertTrue(corner.waitForExistence(timeout: timeout))
        XCTAssertEqual(corner.label, "Volume 2")
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

    private func launchFixture(environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-R6AReaderFixture"]
        for (key, value) in environment {
            app.launchEnvironment[key] = value
        }
        app.launch()
        XCTAssertTrue(element("r6a.page", in: app).waitForExistence(timeout: timeout))
        return app
    }

    /// Horizontal gap between the page-pill label and a chevron button.
    /// Returns a large value when either element is missing so the
    /// caller's assertion fails loudly instead of passing vacuously.
    private func gapBetweenLabelAndChevron(in app: XCUIApplication, chevron: String) -> CGFloat {
        let label = element("reader.pagePill", in: app)
        let button = app.buttons[chevron].firstMatch
        guard label.exists, button.exists else { return 10_000 }
        let labelFrame = label.frame
        let buttonFrame = button.frame
        if buttonFrame.minX >= labelFrame.maxX {
            return buttonFrame.minX - labelFrame.maxX
        }
        return labelFrame.minX - buttonFrame.maxX
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
