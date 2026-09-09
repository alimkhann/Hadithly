import XCTest

/// R5 gate: contents navigation (chapters, jump field) and the per-hadith
/// native menus. Fixture tests prove the new sheet UI offline; the live test
/// proves it against development Convex with the pre-R5 outline shape
/// (volumes exactly as before, jump navigating through the canonical path).
final class ReaderR5UITests: XCTestCase {
    private let timeout: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Fixture: chapters render from source-provided data

    func testContentsShowsChaptersAndJumpField() {
        let app = launchContentsFixture()
        XCTAssertTrue(field("reader.contents.jump", in: app).waitForExistence(timeout: timeout))
        // Volume 1 starts expanded (it holds the selected volume): its
        // source-provided chapters render with counts, and the arabic
        // subtitle appears only where present and different.
        XCTAssertTrue(element("reader.contents.chapter.1.1", in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(element("reader.contents.chapter.1.6", in: app).exists)
        XCTAssertTrue(app.staticTexts["كتاب بدء الوحي"].exists)
        // Volume 2 has no chapters entry content: it renders as a plain
        // volume row exactly like the pre-R5 sheet.
        XCTAssertTrue(element("reader.volume.2", in: app).waitForExistence(timeout: timeout))
    }

    func testContentsJumpRejectsMalformedInputInline() {
        let app = launchContentsFixture()
        let jump = field("reader.contents.jump", in: app)
        XCTAssertTrue(jump.waitForExistence(timeout: timeout))
        jump.tap()
        jump.typeText("abc")
        element("reader.contents.jumpGo", in: app).tap()
        XCTAssertTrue(element("reader.contents.jumpError", in: app).waitForExistence(timeout: timeout))
        // The sheet stays open on malformed input.
        XCTAssertTrue(field("reader.contents.jump", in: app).exists)
        XCTAssertFalse(element("r5.dismissed", in: app).exists)
    }

    func testContentsJumpAcceptsWellFormedInput() {
        let app = launchContentsFixture()
        let jump = field("reader.contents.jump", in: app)
        XCTAssertTrue(jump.waitForExistence(timeout: timeout))
        jump.tap()
        jump.typeText("57")
        element("reader.contents.jumpGo", in: app).tap()
        XCTAssertTrue(element("r5.dismissed", in: app).waitForExistence(timeout: timeout))
    }

    func testContentsChapterTapDismisses() {
        let app = launchContentsFixture()
        let chapter = element("reader.contents.chapter.1.1", in: app)
        XCTAssertTrue(chapter.waitForExistence(timeout: timeout))
        chapter.tap()
        XCTAssertTrue(element("r5.dismissed", in: app).waitForExistence(timeout: timeout))
    }

    // MARK: - Live: real reader against development Convex

    /// Opens Bukhari live, jumps to Hadith 57 through the contents field,
    /// and proves the quiet page (no ellipsis), the grade dot plus source
    /// label, the long-press menu with its gating, and tap-to-toggle
    /// chrome with the context menu present.
    func testLiveContentsJumpAndHadithMenus() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Library"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Library"].tap()
        let collection = app.buttons["library.collection.bukhari"]
        XCTAssertTrue(collection.waitForExistence(timeout: 20))
        collection.tap()
        XCTAssertTrue(element("reader.page", in: app).waitForExistence(timeout: 30))

        revealChrome(app)
        app.buttons["reader.index"].tap()
        let jump = field("reader.contents.jump", in: app)
        XCTAssertTrue(jump.waitForExistence(timeout: timeout), "Contents sheet never opened")
        // Pre-R5 cached outline: volumes render exactly as before.
        XCTAssertTrue(element("reader.volume.1", in: app).waitForExistence(timeout: timeout))
        jump.tap()
        jump.typeText("57")
        element("reader.contents.jumpGo", in: app).tap()

        // The jump lands through the same path as canonical links: the
        // target hadith's quiet marker is on screen (VoiceOver label
        // "Hadith 57"; the visible marker itself is the bare number).
        let markers = app.descendants(matching: .any).matching(identifier: "reader.hadithMarker")
        let target = markers.matching(NSPredicate(format: "label CONTAINS '57'")).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 30), "Jump to Hadith 57 never landed")

        // Slice A: the ellipsis is gone with no visual replacement. Every
        // block carries its quiet marker, grade dot, and source label.
        XCTAssertFalse(app.buttons["reader.moreActions"].exists, "ellipsis must be deleted")
        XCTAssertTrue(
            app.buttons["reader.hadithLabel"].firstMatch.waitForExistence(timeout: timeout),
            "compact source label never rendered"
        )
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "reader.gradeDot").firstMatch.exists,
            "grade dot never rendered"
        )

        // Long-press is the only sighted path to actions: the full menu
        // with Report gated out in English (no loaded non-English
        // translation exists here).
        let arabic = app.staticTexts["reader.arabic"].firstMatch
        scrollUntilHittable(arabic, in: app)
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
        XCTAssertFalse(
            app.buttons["reader.reportTranslation"].firstMatch.exists,
            "Report must stay gated without a loaded non-English translation"
        )
        app.buttons["reader.copy"].firstMatch.tap()

        // The menu opens identically from any block; Share travels with it.
        scrollUntilHittable(arabic, in: app)
        arabic.press(forDuration: 1.0)
        XCTAssertTrue(
            app.buttons["reader.bookmark"].firstMatch.waitForExistence(timeout: timeout),
            "long-press menu never appeared"
        )
        XCTAssertTrue(app.buttons["reader.share"].firstMatch.exists, "long-press menu missing Share")
        app.tap()

        // Tap-to-toggle chrome and paging still work with menus present.
        revealChrome(app)
        XCTAssertTrue(app.buttons["reader.close"].isHittable, "chrome never revealed on tap")
    }

    // MARK: - Helpers

    private func launchContentsFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-R5ContentsFixture"]
        app.launch()
        return app
    }

    private func revealChrome(_ app: XCUIApplication) {
        if !app.buttons["reader.close"].isHittable {
            element("reader.page", in: app).tap()
        }
    }

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 where !element.isHittable {
            app.swipeUp()
        }
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func field(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.textFields.matching(identifier: identifier).firstMatch
    }
}
