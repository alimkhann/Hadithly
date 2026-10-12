import XCTest

final class LanguageSwitchUITests: XCTestCase {
    func testHadithTranslationSwitchDoesNotMirrorEnglishInterface() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        app.buttons["settings.row.hadithTranslation"].tap()
        app.buttons["settings.language.ur"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Today"].tap()
        capture("language-english-interface-urdu-translation")
        XCTAssertLessThan(app.tabBars.buttons["Today"].frame.midX,
                          app.tabBars.buttons["Settings"].frame.midX)
        app.tabBars.buttons["Settings"].tap()
        app.buttons["settings.row.hadithTranslation"].tap()
        app.buttons["settings.language.en"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Today"].tap()
    }

    func testLiveLanguageSwitchKeepsEnglishLTRAndArabicLabels() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let settings = app.tabBars.buttons.element(boundBy: 3)
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        app.buttons["settings.row.appLanguage"].tap()
        app.buttons["settings.uiLanguage.en"].tap()
        capture("language-english-picker")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].exists)
        XCTAssertLessThan(app.tabBars.buttons["Today"].frame.midX,
                          app.tabBars.buttons["Settings"].frame.midX)
        capture("language-english-settings")
        app.buttons["settings.row.appLanguage"].tap()
        app.buttons["settings.uiLanguage.ar"].tap()
        capture("language-arabic-picker")
        let pickerTitleLocalized = app.navigationBars["لغة التطبيق"].exists
        app.navigationBars.buttons.element(boundBy: 0).tap()
        capture("language-arabic-settings")
        let localizedToday = app.tabBars.buttons["اليوم"]
        // Always restore English, even when the regression assertion fails.
        let hasArabicLabel = localizedToday.exists
        if hasArabicLabel {
            XCTAssertGreaterThan(localizedToday.frame.midX,
                                 app.tabBars.buttons["الإعدادات"].frame.midX)
        }
        app.buttons["settings.row.appLanguage"].tap()
        app.buttons["settings.uiLanguage.en"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Today"].tap()
        capture("language-english-restored")
        XCTAssertTrue(hasArabicLabel, "Arabic app language still displays English shell labels")
        XCTAssertTrue(pickerTitleLocalized, "Navigation title retained the previous language")
        XCTAssertLessThan(app.tabBars.buttons["Today"].frame.midX,
                          app.tabBars.buttons["Settings"].frame.midX)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
