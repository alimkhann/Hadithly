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
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: timeout))

        let field = app.searchFields.firstMatch
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
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: timeout))
        // Blank query renders the quiet hint, not an error.
        XCTAssertTrue(element("reader.search.hint", in: app).exists)
        let field = app.searchFields.firstMatch
        field.tap()
        field.typeText("zzz-no-match")
        XCTAssertTrue(element("reader.search.empty", in: app).waitForExistence(timeout: timeout))
    }

    // MARK: - Bookmark placement

    func testPlacementChoiceNavigates() {
        let app = launchRound3(environment: ["R6_SCREEN": "placement"])
        XCTAssertTrue(app.buttons["Start of page"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.buttons["Start of page"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Current hadith")).firstMatch.exists)

        app.buttons["Start of page"].tap()
        let opened = element("r6.opened", in: app)
        XCTAssertTrue(opened.waitForExistence(timeout: timeout))
        XCTAssertEqual(opened.label, "Sahih al-Bukhari · Hadith 57")
    }

    // MARK: - Reader Saved shortcut

    func testSavedShortcutTabsRowsAndEdit() {
        let app = launchRound3(environment: ["R6_SCREEN": "saved"])
        XCTAssertTrue(element("reader.savedShortcut.title", in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(element("reader.savedShortcut.close", in: app).exists)

        // Bookmarks tab: reference + relative-time row.
        let bookmarks = app.buttons["reader.savedShortcut.filter.bookmarks"]
        XCTAssertTrue(bookmarks.exists)
        XCTAssertTrue(bookmarks.isHittable)
        XCTAssertGreaterThan(bookmarks.frame.minY, app.staticTexts["Sahih al-Bukhari · Hadith 57"].frame.maxY)
        XCTAssertTrue(app.staticTexts["Sahih al-Bukhari · Hadith 57"].exists)
        XCTAssertTrue(app.staticTexts["2 months ago"].exists)

        // The disclosure chevron previews in place and does not navigate.
        let preview = element("saved.preview.saved-57", in: app)
        XCTAssertTrue(preview.exists)
        preview.tap()
        XCTAssertEqual(preview.label, "Hide hadith preview")
        XCTAssertFalse(element("r6.opened", in: app).exists)

        // Tapping a row navigates to the exact hadith.
        app.staticTexts["Sahih al-Bukhari · Hadith 57"].tap()
        XCTAssertEqual(element("r6.opened", in: app).label, "Sahih al-Bukhari · Hadith 57")

        // Notes tab: the note row with its relative stamp.
        app.terminate()
        let notes = launchRound3(environment: ["R6_SCREEN": "saved"])
        XCTAssertTrue(element("reader.savedShortcut.title", in: notes).waitForExistence(timeout: timeout))
        notes.buttons["reader.savedShortcut.filter.notes"].tap()
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
        app.launchEnvironment["HADITHLY_UI_TESTING"] = "1"
        app.launch()
        XCTAssertTrue(element("reader.contents.title", in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(element("reader.contents.close", in: app).exists)
        XCTAssertTrue(element("reader.contents.title", in: app).exists)
    }

    // MARK: - Helpers

    private func launchRound3(environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-R6Round3Fixture"]
        app.launchEnvironment["HADITHLY_UI_TESTING"] = "1"
        app.launchEnvironment["R6_LOCALE"] = "en"
        for (key, value) in environment {
            app.launchEnvironment[key] = value
        }
        app.launch()
        let ready = environment["R6_SCREEN"] == "placement" ? app.buttons["Start of page"] : element("r6.screen", in: app)
        XCTAssertTrue(ready.waitForExistence(timeout: timeout))
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
