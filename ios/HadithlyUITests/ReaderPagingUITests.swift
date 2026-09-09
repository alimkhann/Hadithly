import XCTest

final class ReaderPagingUITests: XCTestCase {
    private let timeout: TimeInterval = 8

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testBehavioralDirectionAndVisibilityMatrix() {
        let cases: [FixtureCase] = [
            .init("Arabic-only auto", locale: "en", arabic: true, translation: false, direction: "auto", leftPage: 1),
            .init("translation-only English auto", locale: "en", arabic: false, translation: true, direction: "auto", leftPage: 3),
            .init("translation-only Urdu auto", locale: "ur", arabic: false, translation: true, direction: "auto", leftPage: 1),
            .init("mixed Arabic and English auto", locale: "en", arabic: true, translation: true, direction: "auto", leftPage: 3),
            .init("mixed Arabic and Urdu auto", locale: "ur", arabic: true, translation: true, direction: "auto", leftPage: 1),
            .init("forced LTR", locale: "ur", arabic: true, translation: true, direction: "ltr", leftPage: 3),
            .init("forced RTL", locale: "en", arabic: true, translation: true, direction: "rtl", leftPage: 1),
        ]

        for fixture in cases {
            let app = launch(fixture)
            assertPage(2, in: app, fixture.name)
            XCTAssertEqual(app.staticTexts["r3.arabic"].exists, fixture.arabic, fixture.name)
            XCTAssertEqual(app.staticTexts["r3.translation"].exists, fixture.translation, fixture.name)
            app.swipeLeft()
            assertPage(fixture.leftPage, in: app, fixture.name)
            app.terminate()
        }
    }

    func testFastSwipeAndCancelledGestureContract() {
        let app = launch(
            .init("fast LTR", locale: "en", arabic: true, translation: true, direction: "ltr", leftPage: 3)
        )
        app.swipeLeft(velocity: .fast)
        assertPage(3, in: app, "fast LTR")
        // UIKit cancellation is deterministic in ReaderPagingTests. XCUITest
        // has no public API for cancelling an in-flight touch sequence.
    }

    func testVerticalScrollOnLongPageDoesNotTurnPage() {
        let app = launch(
            .init("long RTL", locale: "ur", arabic: true, translation: true, direction: "rtl", leftPage: 1),
            longContent: true
        )
        assertPage(2, in: app, "long RTL")

        for _ in 0..<6 { app.swipeUp() }

        assertPage(2, in: app, "vertical scrolling")
        XCTAssertTrue(app.staticTexts["r3.long.79"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.staticTexts["r3.long.79"].isHittable)
    }

    func testOneLineBoundariesAndAccessibleEndControls() {
        let app = launch(
            .init("first page", locale: "en", arabic: true, translation: true, direction: "ltr", leftPage: 2),
            initialPage: 0
        )
        assertPage(1, in: app, "first page")
        XCTAssertFalse(app.buttons["reader.previousPage"].exists)
        let next = app.buttons["reader.nextPage"]
        XCTAssertTrue(next.waitForExistence(timeout: timeout))
        XCTAssertEqual(next.label, "Next page")
        next.tap()
        assertPage(2, in: app, "middle page")
        app.buttons["reader.nextPage"].tap()
        assertPage(3, in: app, "last page")
        XCTAssertFalse(app.buttons["reader.nextPage"].exists)
        XCTAssertEqual(app.buttons["reader.previousPage"].label, "Previous page")
    }

    /// R4 gate: the language × theme matrix (en, ar, ur × System, Light,
    /// Paper, Dark) with the revealed chrome, plus compact progress, large
    /// content, and the accessible chapter header.
    func testR4LanguageThemeAndAccessibilityMatrix() {
        let languages: [(String, String)] = [
            ("en", "Actions are judged by intentions."),
            ("ar", "اعمال کا دار و مدار نیتوں پر ہے"),
            ("ur", "اعمال کا دار و مدار نیتوں پر ہے"),
        ]
        let themes = ["system", "light", "paper", "dark"]

        for (locale, translation) in languages {
            for theme in themes {
                let app = launch(
                    FixtureCase("matrix \(locale)-\(theme)", locale: locale, arabic: true, translation: true, direction: "auto", leftPage: 2),
                    theme: theme
                )
                // Revealed chrome: expanded progress pill and the quiet
                // name-only chapter line participate in the accessibility
                // tree.
                let pill = app.staticTexts["r4.progressPill"]
                XCTAssertTrue(pill.waitForExistence(timeout: timeout), "pill \(locale)-\(theme)")
                XCTAssertEqual(pill.label, "Page 2 of 3", "pill label \(locale)-\(theme)")
                let chapter = app.otherElements["r4.chapterHeader"]
                    .firstMatch.exists ? app.otherElements["r4.chapterHeader"] : app.staticTexts["r4.chapterHeader"]
                XCTAssertTrue(chapter.waitForExistence(timeout: timeout), "chapter \(locale)-\(theme)")
                XCTAssertEqual(chapter.label, "Kitab al-Iman", "chapter label \(locale)-\(theme)")
                XCTAssertTrue(app.staticTexts["r3.arabic"].isHittable, "arabic \(locale)-\(theme)")

                if locale == "ar" || locale == "ur" {
                    XCTAssertTrue(
                        app.staticTexts["r3.translation"].label.contains(translation),
                        "rtl translation \(locale)-\(theme)"
                    )
                } else {
                    XCTAssertEqual(app.staticTexts["r3.translation"].label, translation, "ltr translation")
                }
                app.terminate()
            }
        }

        // Hidden chrome: the compact thin bar replaces the expanded pill.
        let app = launch(
            FixtureCase("compact hidden chrome", locale: "en", arabic: true, translation: true, direction: "ltr", leftPage: 2),
            chrome: false
        )
        XCTAssertFalse(app.staticTexts["r4.progressPill"].exists, "pill must hide with chrome")
        XCTAssertTrue(app.staticTexts["r3.page"].exists, "page must remain reachable")
        app.terminate()

        // Large content: Dynamic Type accessibility sizes keep the reading
        // text hittable and the chrome navigable.
        let large = launch(
            FixtureCase("large content", locale: "en", arabic: true, translation: true, direction: "ltr", leftPage: 2),
            largeContent: true
        )
        XCTAssertTrue(large.staticTexts["r3.arabic"].isHittable, "large-content arabic")
        large.terminate()
    }

    private func launch(
        _ fixture: FixtureCase,
        longContent: Bool = false,
        initialPage: Int = 1,
        theme: String = "dark",
        chrome: Bool = true,
        largeContent: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-R3PagingFixture"]
        if largeContent {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL",
            ]
        }
        app.launchEnvironment = [
            "R3_TRANSLATION_LOCALE": fixture.locale,
            "R3_ARABIC_VISIBLE": String(fixture.arabic),
            "R3_TRANSLATION_VISIBLE": String(fixture.translation),
            "R3_READING_DIRECTION": fixture.direction,
            "R3_LONG_CONTENT": String(longContent),
            "R3_INITIAL_PAGE": String(initialPage),
            "R4_THEME": theme,
            "R4_CHROME": String(chrome),
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["r3.page"].waitForExistence(timeout: timeout), fixture.name)
        return app
    }

    private func assertPage(_ page: Int, in app: XCUIApplication, _ message: String) {
        let pageLabel = app.staticTexts["r3.page"]
        let predicate = NSPredicate(format: "label == %@", "Page \(page)")
        expectation(for: predicate, evaluatedWith: pageLabel)
        waitForExpectations(timeout: timeout)
        XCTAssertEqual(pageLabel.label, "Page \(page)", message)
    }
}

private struct FixtureCase {
    let name: String
    let locale: String
    let arabic: Bool
    let translation: Bool
    let direction: String
    let leftPage: Int

    init(
        _ name: String,
        locale: String,
        arabic: Bool,
        translation: Bool,
        direction: String,
        leftPage: Int
    ) {
        self.name = name
        self.locale = locale
        self.arabic = arabic
        self.translation = translation
        self.direction = direction
        self.leftPage = leftPage
    }
}
