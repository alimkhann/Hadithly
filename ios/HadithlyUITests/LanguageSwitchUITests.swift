import XCTest
import UIKit

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
        app.launchEnvironment["HADITHLY_UI_TESTING"] = "1"
        app.launchArguments = ["-onboarding.completed", "YES"]
        app.launch()
        let settings = app.tabBars.buttons.element(boundBy: 3)
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.buttons["settings.signin"].waitForExistence(timeout: 5), "This regression must run as a guest")
        app.buttons["settings.row.appLanguage"].tap()
        app.buttons["settings.uiLanguage.en"].tap()
        capture("language-english-picker")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].exists)
        XCTAssertLessThan(app.tabBars.buttons["Today"].frame.midX,
                          app.tabBars.buttons["Settings"].frame.midX)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Settings"].tap()
        capture("language-english-settings")
        let englishRow = app.buttons["settings.row.appLanguage"].screenshot().image
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
        capture("language-english-picker-restored")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Today"].tap()
        capture("language-english-restored")
        XCTAssertTrue(hasArabicLabel, "Arabic app language still displays English shell labels")
        XCTAssertTrue(pickerTitleLocalized, "Navigation title retained the previous language")
        XCTAssertLessThan(app.tabBars.buttons["Today"].frame.midX,
                          app.tabBars.buttons["Settings"].frame.midX)
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["settings.row.appLanguage"].waitForExistence(timeout: 5))
        capture("language-english-settings-return")
        assertEnglishRowOrientation(app.buttons["settings.row.appLanguage"].screenshot().image, baseline: englishRow)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["settings.row.appLanguage"].waitForExistence(timeout: 5))
        XCTAssertLessThan(app.tabBars.buttons["Today"].frame.midX,
                          app.tabBars.buttons["Settings"].frame.midX)
        capture("language-english-settings-relaunch")
        assertEnglishRowOrientation(app.buttons["settings.row.appLanguage"].screenshot().image, baseline: englishRow)
    }

    private func assertEnglishRowOrientation(_ returned: UIImage, baseline: UIImage) {
        let width = 256, height = 64
        func pixels(_ image: UIImage) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image.cgImage!, in: CGRect(x: 0, y: 0, width: width, height: height))
            return bytes
        }
        let expected = pixels(baseline), actual = pixels(returned)
        var direct = 0, mirrored = 0
        for y in 0..<height {
            for x in 0..<width {
                for channel in 0..<3 {
                    let index = (y * width + x) * 4 + channel
                    let flipped = (y * width + width - 1 - x) * 4 + channel
                    direct += abs(Int(expected[index]) - Int(actual[index]))
                    mirrored += abs(Int(expected[index]) - Int(actual[flipped]))
                }
            }
        }
        XCTAssertLessThan(direct, mirrored, "English Settings ink is mirrored after returning: direct=\(direct), flipped=\(mirrored)")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
