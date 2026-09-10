import XCTest

/// R6 fixes round 3 gate, offline: the restyled menu order (Contents,
/// Bookmarks & Notes, Settings, Bookmark + Search; no location card;
/// chevron-left back), the filled bookmark state, the functional English
/// search sheet, the placement choice, the reader Saved shortcut, and the
/// Sajda sheet aesthetic ids. All from the deterministic
/// `-R6Round3Fixture` with no network.
final class ReaderR6Round3UITests: XCTestCase {
    private let timeout: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Menu order and cards

    func testMenuOrderContentsSavedSettingsThenBookmarkSearch() {
        let app = launchRound3()
        let stack = element("reader.menuStack", in: app)
        XCTAssertTrue(stack.waitForExistence(timeout: timeout))

        for identifier in [
            "reader.menu.contents", "reader.menu.saved", "reader.menu.settings",
            "reader.menu.bookmark", "reader.menu.search",
        ] {
            XCTAssertTrue(element(identifier, in: app).exists, "missing \(identifier)")
        }
        // No location card, no playback, no note card.
        XCTAssertFalse(app.staticTexts["Current location"].exists)
        XCTAssertFalse(app.staticTexts["Current hadith"].exists)

        // Sajda order: Contents above Bookmarks & Notes above Settings.
        let contents = element("reader.menu.contents", in: app)
        let saved = element("reader.menu.saved", in: app)
        let settings = element("reader.menu.settings", in: app)
        XCTAssertLessThan(contents.frame.minY, saved.frame.minY)
        XCTAssertLessThan(saved.frame.minY, settings.frame.minY)

        // Bottom row: Bookmark and Search share a row below Settings.
        let bookmark = element("reader.menu.bookmark", in: app)
        let search = element("reader.menu.search", in: app)
        XCTAssertGreaterThan(bookmark.frame.minY, settings.frame.maxY)
        XCTAssertGreaterThan(search.frame.minY, settings.frame.maxY)
        XCTAssertLessThan(abs(bookmark.frame.midY - search.frame.midY), 60)
        XCTAssertLessThan(bookmark.frame.minX, search.frame.minX)

        // Bottom circles: chevron-left back plus the menu circle.
        XCTAssertTrue(app.buttons["reader.close"].exists)
        XCTAssertEqual(app.buttons["reader.close"].label, "Close reader")
        XCTAssertTrue(app.buttons["reader.menu"].exists)
    }

    func testMenuBookmarkFilledWhenPositionedHadithBookmarked() {
        // Default: not bookmarked — the quiet bookmark card.
        let app = launchRound3()
        XCTAssertTrue(element("reader.menu.bookmark", in: app).waitForExistence(timeout: timeout))
        XCTAssertEqual(element("reader.menu.bookmark", in: app).label, "Bookmark positioned hadith")

        // Seeded bookmarked: the card renders filled with a remove action.
        app.terminate()
        let filled = launchRound3(environment: ["R6_MENU_BOOKMARKED": "true"])
        let card = element("reader.menu.bookmark", in: filled)
        XCTAssertTrue(card.waitForExistence(timeout: timeout))
        XCTAssertEqual(card.label, "Remove bookmark for positioned hadith")
    }

    // MARK: - Search sheet flow

    func testSearchResultsNavigateExact() {
        let app = launchRound3(environment: ["R6_SCREEN": "search", "R6_SEARCH_STUB": "results"])
        XCTAssertTrue(element("reader.search.title", in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(element("reader.search.grabber", in: app).exists)
        XCTAssertTrue(element("reader.search.close", in: app).exists)

        let field = app.textFields["reader.search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        field.tap()
        field.typeText("mercy")

        let first = element("reader.search.result.0", in: app)
        XCTAssertTrue(first.waitForExistence(timeout: timeout))
        XCTAssertTrue(element("reader.search.section", in: app).exists)
        // Results are labeled as Sunnah.now English text.
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Sunnah.now English'")
        ).firstMatch.exists)
        XCTAssertEqual(first.label, "Sahih al-Bukhari · Hadith 57, Sunnah.now English text")

        first.tap()
        let opened = element("r6.opened", in: app)
        XCTAssertTrue(opened.waitForExistence(timeout: timeout))
        XCTAssertEqual(opened.label, "Sahih al-Bukhari · Hadith 57")
    }

    func testSearchEmptyStateWithoutStub() {
        let app = launchRound3(environment: ["R6_SCREEN": "search"])
        XCTAssertTrue(element("reader.search.title", in: app).waitForExistence(timeout: timeout))
        // Blank query renders the quiet hint, not an error.
        XCTAssertTrue(element("reader.search.hint", in: app).exists)
        let field = app.textFields["reader.search.field"]
        field.tap()
        field.typeText("zzz-no-match")
        XCTAssertTrue(element("reader.search.empty", in: app).waitForExistence(timeout: timeout))
    }

    // MARK: - Bookmark placement

    func testPlacementChoiceNavigates() {
        let app = launchRound3(environment: ["R6_SCREEN": "placement"])
        XCTAssertTrue(element("reader.bookmarkPlacement.title", in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(element("reader.bookmarkPlacement.grabber", in: app).exists)
        XCTAssertTrue(element("reader.bookmarkPlacement.pageStart", in: app).exists)
        XCTAssertTrue(element("reader.bookmarkPlacement.currentHadith", in: app).exists)
        XCTAssertTrue(element("reader.bookmarkPlacement.cancel", in: app).exists)

        element("reader.bookmarkPlacement.pageStart", in: app).tap()
        let opened = element("r6.opened", in: app)
        XCTAssertTrue(opened.waitForExistence(timeout: timeout))
        XCTAssertEqual(opened.label, "Sahih al-Bukhari · Hadith 57")
    }

    // MARK: - Reader Saved shortcut

    func testSavedShortcutTabsRowsAndEdit() {
        let app = launchRound3(environment: ["R6_SCREEN": "saved"])
        XCTAssertTrue(element("reader.savedShortcut.title", in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(element("reader.savedShortcut.grabber", in: app).exists)
        XCTAssertTrue(element("reader.savedShortcut.close", in: app).exists)

        // Bookmarks tab: reference + relative-time row.
        XCTAssertTrue(element("reader.savedShortcut.tab.bookmarks", in: app).exists)
        XCTAssertTrue(element("reader.savedShortcut.tab.favorites", in: app).exists)
        XCTAssertTrue(element("reader.savedShortcut.tab.notes", in: app).exists)
        XCTAssertTrue(app.staticTexts["Sahih al-Bukhari · Hadith 57"].exists)
        XCTAssertTrue(app.staticTexts["2 months ago"].exists)

        // Tapping a row navigates to the exact hadith.
        app.staticTexts["Sahih al-Bukhari · Hadith 57"].tap()
        XCTAssertEqual(element("r6.opened", in: app).label, "Sahih al-Bukhari · Hadith 57")

        // Notes tab: the note row with its relative stamp.
        app.terminate()
        let notes = launchRound3(environment: ["R6_SCREEN": "saved"])
        XCTAssertTrue(element("reader.savedShortcut.title", in: notes).waitForExistence(timeout: timeout))
        element("reader.savedShortcut.tab.notes", in: notes).tap()
        XCTAssertTrue(notes.staticTexts["Fixture note"].exists)
        XCTAssertTrue(notes.staticTexts["just now"].exists)

        // EDIT opens the Saved tab destination.
        element("reader.savedShortcut.edit", in: notes).tap()
        XCTAssertEqual(element("r6.opened", in: notes).label, "EDIT_SAVED")
    }

    // MARK: - Sheets aesthetic ids (all four sheets)

    func testContentsSheetAesthetic() {
        let app = XCUIApplication()
        app.launchArguments = ["-R5ContentsFixture"]
        app.launch()
        XCTAssertTrue(element("r5.sheetOpen", in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(element("reader.contents.grabber", in: app).exists)
        XCTAssertTrue(element("reader.contents.close", in: app).exists)
        XCTAssertTrue(element("reader.contents.title", in: app).exists)
    }

    // MARK: - Helpers

    private func launchRound3(environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-R6Round3Fixture"]
        for (key, value) in environment {
            app.launchEnvironment[key] = value
        }
        app.launch()
        XCTAssertTrue(element("r6.screen", in: app).waitForExistence(timeout: timeout))
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
