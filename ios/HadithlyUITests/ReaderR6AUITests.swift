import XCTest

/// Slice A (R6) gate plus round-2 corrections, offline: the Sajda-quiet
/// page renders from the deterministic `-R6AReaderFixture` with no
/// network across three volumes (Volume 1: one page; Volume 2: two pages;
/// Volume 3: one page). Proves the quiet page (no dividers, no ellipsis),
/// the top header (dot + bracketed label + saved-state markers), the
/// source sheet contents, chapter/volume headers, the TWO bottom pills
/// (neighbor pages mid-volume, full neighbor-volume titles at the edges,
/// nothing at the absolute ends), tap and swipe across volume boundaries
/// both ways, the cross-volume loading state, and the narrator in all
/// three visibility modes.
final class ReaderR6AUITests: XCTestCase {
    private let timeout: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Quiet page

    func testQuietPageHasHeadersMarkersAndNoEllipsis() {
        let app = launchFixture()
        XCTAssertTrue(element("reader.volumeHeader", in: app).waitForExistence(timeout: timeout))
        // Two hadith blocks on Volume 2 page 1, each with one tappable top header.
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
        // Two bottom pills replace the old centered cluster, and the corner
        // yields to the volume header on page 1.
        XCTAssertTrue(element("reader.pagePills", in: app).exists)
        XCTAssertFalse(element("reader.pageCluster", in: app).exists, "the single centered cluster is gone")
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

    // MARK: - Narrator in all three modes

    func testNarratorShowsWithTranslationLayer() {
        let app = launchFixture()
        let narrator = element("reader.narrator", in: app)
        XCTAssertTrue(narrator.waitForExistence(timeout: timeout))
        XCTAssertTrue(narrator.label.contains("Umar"))
        // Hadith 58 has no narrator: exactly one narrator line on the page.
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "reader.narrator").count, 1)
        // Mixed mode keeps the leading-edge line below the Arabic block.
        let arabic = app.descendants(matching: .any).matching(identifier: "reader.arabic").firstMatch
        XCTAssertTrue(arabic.waitForExistence(timeout: timeout))
        XCTAssertGreaterThanOrEqual(narrator.frame.minY, arabic.frame.maxY - 2)
    }

    func testNarratorShowsAboveArabicInArabicOnlyMode() {
        let app = launchFixture(environment: ["R6A_TRANSLATION_VISIBLE": "false"])
        XCTAssertTrue(element("r6a.page", in: app).waitForExistence(timeout: timeout))
        // Arabic-only mode shows the provider Arabic narrator line, never
        // the English narrator: it hides when narratorAr is absent.
        let narrator = element("reader.narrator", in: app)
        XCTAssertTrue(narrator.waitForExistence(timeout: timeout), "narrator shows in Arabic-only mode")
        XCTAssertTrue(narrator.label.contains("عمر"))
        XCTAssertFalse(narrator.label.contains("Umar"))
        let arabic = app.descendants(matching: .any).matching(identifier: "reader.arabic").firstMatch
        XCTAssertTrue(arabic.waitForExistence(timeout: timeout))
        XCTAssertLessThanOrEqual(narrator.frame.maxY, arabic.frame.minY + 2)
        XCTAssertFalse(element("reader.translation", in: app).exists)
    }

    func testNarratorShowsInTranslationOnlyMode() {
        let app = launchFixture(environment: ["R6A_ARABIC_VISIBLE": "false"])
        XCTAssertTrue(element("r6a.page", in: app).waitForExistence(timeout: timeout))
        let narrator = element("reader.narrator", in: app)
        XCTAssertTrue(narrator.waitForExistence(timeout: timeout), "narrator shows in translation-only mode")
        XCTAssertTrue(narrator.label.contains("Umar"))
        XCTAssertFalse(element("reader.arabic", in: app).exists)
    }

    // MARK: - Source sheet

    func testSourceSheetShowsNameScopeAndURL() {
        let app = launchFixture()
        app.buttons.matching(identifier: "reader.hadithLabel").firstMatch.tap()
        XCTAssertTrue(element("reader.sourceSheet", in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(app.staticTexts["Sunnah.now"].exists)
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
        XCTAssertTrue(app.staticTexts["Sunnah.now"].exists)
        XCTAssertFalse(element("reader.sourceSheet.url", in: app).exists)
        app.buttons["Done"].tap()
    }

    // MARK: - Two bottom pills

    func testTwoPillsAtVolumeEdgeNameNeighborVolume() {
        // Volume 2 page 1: LEFT is the previous volume in full, RIGHT is
        // the neighbor page number.
        let app = launchFixture()
        XCTAssertTrue(element("reader.pagePills", in: app).waitForExistence(timeout: timeout))
        let previous = app.buttons["reader.previousPage"].firstMatch
        let next = app.buttons["reader.nextPage"].firstMatch
        XCTAssertEqual(previous.label, "Previous page, Volume 1")
        XCTAssertEqual(next.label, "Next page, Page 2")
        // LTR order: previous on the left, next on the right.
        XCTAssertLessThan(previous.frame.minX, next.frame.minX)
        // 44pt targets on both pills.
        XCTAssertGreaterThanOrEqual(previous.frame.height, 44)
        XCTAssertGreaterThanOrEqual(next.frame.height, 44)

        // Volume 2 page 2: LEFT is the neighbor page, RIGHT names Volume 3.
        next.tap()
        XCTAssertEqual(app.buttons["reader.previousPage"].firstMatch.label, "Previous page, Page 1")
        XCTAssertEqual(app.buttons["reader.nextPage"].firstMatch.label, "Next page, Volume 3")
        let corner = element("reader.volumeCorner", in: app)
        XCTAssertTrue(corner.waitForExistence(timeout: timeout))
        XCTAssertEqual(corner.label, "Volume 2: 57–59")
    }

    func testAbsoluteEndsHaveNoOutwardPill() {
        // First page of the first volume: no previous pill.
        let app = launchFixture(environment: ["R6A_START_VOLUME": "1"])
        XCTAssertTrue(element("reader.volumeHeader", in: app).waitForExistence(timeout: timeout))
        XCTAssertEqual(element("reader.volumeHeader", in: app).label, "Volume 1, 1 hadiths")
        XCTAssertFalse(app.buttons["reader.previousPage"].exists)
        XCTAssertEqual(app.buttons["reader.nextPage"].firstMatch.label, "Next page, Volume 2")

        // Last page of the last volume: no next pill.
        app.terminate()
        let last = launchFixture(environment: ["R6A_START_VOLUME": "3"])
        XCTAssertTrue(element("reader.volumeHeader", in: last).waitForExistence(timeout: timeout))
        XCTAssertEqual(element("reader.volumeHeader", in: last).label, "Volume 3, 1 hadiths")
        XCTAssertFalse(last.buttons["reader.nextPage"].exists)
        XCTAssertEqual(last.buttons["reader.previousPage"].firstMatch.label, "Previous page, Volume 2")
    }

    func testRTLPillsMirrorWithLogicalLabels() {
        let app = launchFixture(environment: ["R6A_PAGE_DIRECTION": "rtl"])
        XCTAssertTrue(element("reader.pagePills", in: app).waitForExistence(timeout: timeout))
        let previous = app.buttons["reader.previousPage"].firstMatch
        let next = app.buttons["reader.nextPage"].firstMatch
        // Labels stay logical; the previous pill sits on the right.
        XCTAssertEqual(previous.label, "Previous page, Volume 1")
        XCTAssertEqual(next.label, "Next page, Page 2")
        XCTAssertGreaterThan(previous.frame.minX, next.frame.minX)
    }

    func testCornerLabelStaysTitleOnlyUntilFullyCached() {
        let app = launchFixture(environment: ["R6A_FULL_CACHE": "false"])
        XCTAssertTrue(element("reader.pagePills", in: app).waitForExistence(timeout: timeout))
        app.buttons["reader.nextPage"].tap()
        let corner = element("reader.volumeCorner", in: app)
        XCTAssertTrue(corner.waitForExistence(timeout: timeout))
        XCTAssertEqual(corner.label, "Volume 2")
    }

    // MARK: - Crossing volume boundaries

    func testTapAcrossBoundaryForwardLandsOnNextVolumeFirstPage() {
        let app = launchFixture(environment: ["R6A_INITIAL_PAGE": "1"])
        XCTAssertTrue(element("reader.pagePills", in: app).waitForExistence(timeout: timeout))
        XCTAssertEqual(app.buttons["reader.nextPage"].firstMatch.label, "Next page, Volume 3")
        app.buttons["reader.nextPage"].tap()
        let header = element("reader.volumeHeader", in: app)
        XCTAssertTrue(header.waitForExistence(timeout: timeout))
        XCTAssertEqual(header.label, "Volume 3, 1 hadiths")
        // Absolute end: no next pill; back names Volume 2 in full.
        XCTAssertFalse(app.buttons["reader.nextPage"].exists)
        XCTAssertEqual(app.buttons["reader.previousPage"].firstMatch.label, "Previous page, Volume 2")
    }

    func testFreshVolumePageShowsItsHeaderAboveTheFirstHadith() {
        let app = launchFixture(environment: ["R6A_INITIAL_PAGE": "1"])
        app.buttons["reader.nextPage"].tap()
        let header = element("reader.volumeHeader", in: app)
        XCTAssertTrue(header.waitForExistence(timeout: timeout))
        XCTAssertTrue(header.isHittable)
    }

    func testP1VerticalLandingMatrix() {
        // A fresh Library-style open begins at the first volume header.
        let app = launchFixture()
        XCTAssertTrue(element("reader.volumeHeader", in: app).waitForExistence(timeout: timeout))

        // Turn onto the next page, scroll its content, then revisit it. The
        // manual revisit must expose the page corner again, never its old
        // vertical offset.
        app.buttons["reader.nextPage"].tap()
        let corner = element("reader.volumeCorner", in: app)
        XCTAssertTrue(corner.waitForExistence(timeout: timeout))
        app.swipeUp()
        app.buttons["reader.previousPage"].tap()
        XCTAssertTrue(element("reader.volumeHeader", in: app).waitForExistence(timeout: timeout))
        app.buttons["reader.nextPage"].tap()
        XCTAssertTrue(corner.waitForExistence(timeout: timeout))

        // The outward turn crosses into an initially unvisited volume and
        // must land at its source-provided volume header once it loads.
        app.buttons["reader.nextPage"].tap()
        let volume3 = element("reader.volumeHeader", in: app)
        XCTAssertTrue(volume3.waitForExistence(timeout: timeout))
        XCTAssertTrue(volume3.isHittable)

        // The fixture's explicit page target is the semantic-continuation
        // analogue: it remains on Hadith 59 rather than being reset to top.
        app.terminate()
        let continuation = launchFixture(environment: ["R6A_INITIAL_PAGE": "1"])
        XCTAssertTrue(continuation.buttons.matching(identifier: "reader.hadithLabel").firstMatch.waitForExistence(timeout: timeout))
        XCTAssertTrue(element("reader.volumeCorner", in: continuation).isHittable)
    }

    func testTapAcrossBoundaryBackwardLandsOnPreviousVolumeLastPage() {
        let app = launchFixture()
        XCTAssertTrue(element("reader.pagePills", in: app).waitForExistence(timeout: timeout))
        app.buttons["reader.previousPage"].tap()
        let header = element("reader.volumeHeader", in: app)
        XCTAssertTrue(header.waitForExistence(timeout: timeout))
        XCTAssertEqual(header.label, "Volume 1, 1 hadiths")
        XCTAssertFalse(app.buttons["reader.previousPage"].exists)
        // The visited volume opens instantly on the way back: no loading.
        app.buttons["reader.nextPage"].tap()
        let back = element("reader.volumeHeader", in: app)
        XCTAssertTrue(back.waitForExistence(timeout: timeout))
        XCTAssertEqual(back.label, "Belief, 3 hadiths")
        XCTAssertEqual(app.buttons["reader.previousPage"].firstMatch.label, "Previous page, Volume 1")
    }

    func testSwipeAcrossVolumesBothWays() {
        let app = launchFixture(environment: ["R6A_INITIAL_PAGE": "1"])
        XCTAssertTrue(element("reader.pagePills", in: app).waitForExistence(timeout: timeout))
        // Outward swipe past the last page advances to Volume 3's first page.
        app.swipeLeft()
        let volume3 = element("reader.volumeHeader", in: app)
        XCTAssertTrue(volume3.waitForExistence(timeout: timeout))
        XCTAssertEqual(volume3.label, "Volume 3, 1 hadiths")
        // Back across the boundary lands on Volume 2's last page.
        app.swipeRight()
        let corner = element("reader.volumeCorner", in: app)
        XCTAssertTrue(corner.waitForExistence(timeout: timeout))
        XCTAssertEqual(corner.label, "Volume 2: 57–59")
        // In-volume swipe still turns the page.
        app.swipeRight()
        let volume2 = element("reader.volumeHeader", in: app)
        XCTAssertTrue(volume2.waitForExistence(timeout: timeout))
        XCTAssertEqual(volume2.label, "Belief, 3 hadiths")
        // And back across to the previous volume's last (= only) page.
        app.swipeRight()
        let volume1 = element("reader.volumeHeader", in: app)
        XCTAssertTrue(volume1.waitForExistence(timeout: timeout))
        XCTAssertEqual(volume1.label, "Volume 1, 1 hadiths")
    }

    func testLoadingStateOnFirstVolumeVisit() {
        let app = launchFixture(environment: ["R6A_LOADING_FIXTURE": "true"])
        XCTAssertTrue(
            app.activityIndicators.firstMatch.waitForExistence(timeout: timeout),
            "a loading reader renders a native progress indicator"
        )
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

    // MARK: - Round 3: drag lock and note marker

    func testHorizontalDragTurnsPage() {
        let app = launchFixture()
        XCTAssertTrue(element("reader.volumeHeader", in: app).waitForExistence(timeout: timeout))
        app.swipeLeft()
        let corner = element("reader.volumeCorner", in: app)
        XCTAssertTrue(corner.waitForExistence(timeout: timeout))
        XCTAssertEqual(corner.label, "Volume 2: 57–59")
    }

    func testVerticalDragNeverTurnsPage() {
        let app = launchFixture()
        XCTAssertTrue(element("reader.volumeHeader", in: app).waitForExistence(timeout: timeout))
        app.swipeUp()
        app.swipeUp()
        // Still on Volume 2 page 1: the header persists, no corner label.
        XCTAssertTrue(element("reader.volumeHeader", in: app).exists)
        XCTAssertFalse(element("reader.volumeCorner", in: app).exists)
    }

    func testShortHorizontalDragCancelsBack() {
        let app = launchFixture()
        XCTAssertTrue(element("reader.volumeHeader", in: app).waitForExistence(timeout: timeout))
        // A short slow drag stays under the turn threshold: the page
        // springs back instead of turning.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: end)
        XCTAssertTrue(element("reader.volumeHeader", in: app).exists)
        XCTAssertFalse(element("reader.volumeCorner", in: app).exists)
    }

    func testGreenNoteMarkerOnNotedHadith() {
        let app = launchFixture()
        XCTAssertTrue(element("reader.volumeHeader", in: app).waitForExistence(timeout: timeout))
        // Page 1 (hadiths 57/58): no note marker.
        XCTAssertFalse(element("reader.savedNote", in: app).exists)
        // Page 2 (hadith 59, seeded note): the green inline marker renders.
        app.buttons["reader.nextPage"].tap()
        XCTAssertTrue(element("reader.savedNote", in: app).waitForExistence(timeout: timeout))
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

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
