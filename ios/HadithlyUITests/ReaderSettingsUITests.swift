import XCTest
import UIKit

final class ReaderSettingsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testBothEntryPointsKeepSettingsAndNativeNavigation() {
        for context in ["reader", "global"] {
            let app = launch(context: context)
            let prefix = context == "reader" ? "reader" : "settings"
            if context == "global" {
                app.buttons["settings.row.readingAndType"].tap()
            }
            let arabic = app.switches["\(prefix).visibility.arabic"]
            XCTAssertTrue(arabic.waitForExistence(timeout: 10))
            arabic.tap()
            let translation = app.switches["\(prefix).visibility.translation"]
            translation.tap()
            XCTAssertEqual(translation.value as? String, "1", "The last layer must stay visible")
            arabic.tap()
            screenshot("\(context)-root")

            let typeRow = app.buttons["\(prefix).settings.arabic"]
            XCTAssertLessThanOrEqual(typeRow.frame.height, 64)
            typeRow.tap()
            XCTAssertTrue(app.steppers["\(prefix).arabicSize"].waitForExistence(timeout: 5))
            let stepper = app.steppers["\(prefix).arabicSize"]
            stepper.buttons["\(prefix).arabicSize-Increment"].tap()
            XCTAssertTrue(app.staticTexts["30 pt"].exists)
            app.buttons["\(prefix).font.amiri"].tap()
            screenshot("\(context)-arabic")
            app.navigationBars["Arabic type"].buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.staticTexts["Amiri · 30 pt"].exists)

            app.buttons["\(prefix).settings.translation"].tap()
            app.steppers["\(prefix).translationSize"].buttons["\(prefix).translationSize-Increment"].tap()
            XCTAssertTrue(app.staticTexts["18 pt"].exists)
            app.buttons["\(prefix).language.ru"].tap()
            screenshot("\(context)-translation")
            app.navigationBars["Translation"].buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.staticTexts["RU · 18 pt"].exists)

            app.buttons["\(prefix).settings.appearance"].tap()
            app.buttons["\(prefix).theme.paper"].tap()
            screenshot("\(context)-appearance")
            app.navigationBars["Appearance"].buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.staticTexts["Paper"].exists)
            if context == "reader" {
                app.buttons["reader.settings.close"].tap()
                XCTAssertFalse(app.switches["reader.visibility.arabic"].exists)
            }
            app.terminate()
        }
    }

    func testMainAppearanceKeepsAppToggleAndReaderInSeparateGroups() {
        let app = launch(context: "global", theme: "light")
        app.buttons["settings.row.appearance"].tap()
        let toggle = app.switches["settings.appearance.separateReader"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let appDark = app.descendants(matching: .any).matching(identifier: "settings.appearance.dark").firstMatch
        XCTAssertTrue(appDark.exists)
        XCTAssertGreaterThan(toggle.frame.minY - appDark.frame.maxY, 16)
        let reader = app.descendants(matching: .any).matching(identifier: "settings.readerAppearance.system").firstMatch
        XCTAssertFalse(reader.exists)
        screenshot("appearance-two-groups")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertTrue(reader.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(reader.frame.minY - toggle.frame.maxY, 16)
        screenshot("appearance-three-groups")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertFalse(reader.exists)
    }

    func testSelectingPaperChangesRenderedSheetBackground() {
        let app = launch(context: "reader")
        app.buttons["reader.settings.appearance"].tap()
        app.buttons["reader.theme.paper"].tap()
        assertPaperBackground(app)
        screenshot("reader-paper-selected")
    }

    func testThemeCycleDoesNotRetainPaperDividers() {
        let app = launch(context: "reader", theme: "paper")
        app.buttons["reader.settings.appearance"].tap()
        for theme in ["light", "dark"] {
            app.buttons["reader.theme.\(theme)"].tap()
            let row = app.buttons["reader.theme.system"]
            XCTAssertTrue(row.exists)
            screenshot("theme-cycle-\(theme)-before-reentry")
            XCTAssertLessThan(warmPixelsNearDivider(app, row: row), 0.02,
                              "Paper's tan separator must not survive a theme change")
            app.navigationBars["Appearance"].buttons.element(boundBy: 0).tap()
            app.buttons["reader.settings.appearance"].tap()
            screenshot("theme-cycle-\(theme)-after-reentry")
            XCTAssertLessThan(warmPixelsNearDivider(app, row: app.buttons["reader.theme.system"]), 0.02)
        }
    }

    private func warmPixelsNearDivider(_ app: XCUIApplication, row: XCUIElement) -> Double {
        let image = app.screenshot().image.cgImage!
        let scale = CGFloat(image.width) / app.frame.width
        let rect = CGRect(x: row.frame.midX, y: row.frame.maxY - 2, width: row.frame.width * 0.2, height: 5)
        let crop = image.cropping(to: CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale))!
        let width = crop.width, height = crop.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &rgba, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
        let warm = stride(from: 0, to: rgba.count, by: 4).filter { Int(rgba[$0]) - Int(rgba[$0 + 2]) > 20 && Int(rgba[$0 + 1]) - Int(rgba[$0 + 2]) > 10 }.count
        return Double(warm) / Double(width * height)
    }

    private func assertPaperBackground(_ app: XCUIApplication) {
        let image = app.screenshot().image.cgImage!
        let sample = image.cropping(to: CGRect(x: 20, y: image.height / 2, width: 1, height: 1))!
        var rgba = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &rgba, width: 1, height: 1, bitsPerComponent: 8,
                                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertGreaterThan(rgba[0], 220, "Paper must render a light background, not merely a selected checkmark")
        XCTAssertGreaterThan(rgba[1], 210)
        XCTAssertGreaterThan(rgba[2], 190)
        XCTAssertGreaterThan(Int(rgba[0]) - Int(rgba[2]), 10, "Paper must retain its warm tint")
    }

    func testThemesAndLargeTextRemainScrollable() {
        for locale in ["en", "ar", "ur"] {
            for theme in ["system", "light", "paper", "dark"] {
                let app = launch(context: "reader", theme: theme, locale: locale)
                screenshot("reader-\(locale)-\(theme)")
                app.terminate()
            }
        }
        let app = launch(context: "global", largeText: true)
        app.buttons["settings.row.readingAndType"].tap()
        let saved = app.switches["settings.confirmSavedRemoval"]
        for _ in 0..<8 where !saved.exists { app.swipeUp() }
        XCTAssertTrue(saved.exists)
        screenshot("global-accessibility")
    }

    private func launch(context: String, theme: String = "dark", locale: String = "en", largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ReaderSettingsFixture"]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "READER_SETTINGS_CONTEXT": context, "READER_SETTINGS_THEME": theme, "READER_SETTINGS_LOCALE": locale]
        app.launch()
        let probe = context == "global" ? "settings.row.readingAndType" : "reader.settings.arabic"
        if context == "global" {
            for _ in 0..<5 where !app.buttons[probe].exists { app.swipeUp() }
        }
        XCTAssertTrue(app.buttons[probe].waitForExistence(timeout: 10))
        return app
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
