import AppIntents
import XCTest
import UIKit

final class NativeFinishingUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { XCUIApplication().terminate(); XCUIApplication(bundleIdentifier: "com.apple.Preferences").terminate() }

    func testWelcomeDetectsSystemLanguageBeforeAnySelection() {
        let app = XCUIApplication()
        app.launchArguments = ["-NativeFinishingFixture", "-AppleLanguages", "(ru-RU)", "-AppleLocale", "ru_RU"]
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "FINISH_SCREEN": "fresh-install"]
        app.launch()
        let start = app.buttons["onboarding.getStarted"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertEqual(start.label, "Начать")
        capture("fresh-welcome-system-russian", app)
    }

    func testFirstInstallAndAccountRoutes() {
        let app = launch("install")
        XCTAssertTrue(app.buttons["onboarding.getStarted"].waitForExistence(timeout: 10))
        capture("01-welcome", app)
        app.buttons["onboarding.getStarted"].tap()
        XCTAssertTrue(app.buttons["onboarding.continue"].waitForExistence(timeout: 5))
        capture("02-language", app)
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(waitForOnboardingDailyResult(app))
        if app.staticTexts["hadith.text.translation"].exists { XCTAssertTrue(app.staticTexts["hadith.text.translation"].isHittable) }
        capture("03-daily-hadith", app)
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.buttons["onboarding.guest"].waitForExistence(timeout: 5))
        capture("05-account", app)
        app.buttons["onboarding.signIn"].tap()
        XCTAssertTrue(app.buttons["signin.createAccount"].waitForExistence(timeout: 5))
        capture("06-auth-methods", app)
        app.buttons["signin.createAccount"].tap()
        XCTAssertTrue(app.textFields["signup.email.field"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.navigationBars.firstMatch.buttons.count, 2, "One Back and one Close control")
        capture("07-sign-up", app)
        app.buttons["signin.close"].tap()
        app.buttons["onboarding.signIn"].tap()
        XCTAssertTrue(app.buttons["signin.email"].waitForExistence(timeout: 5))
        app.buttons["signin.email"].tap()
        XCTAssertTrue(app.textFields["signin.identifier.field"].waitForExistence(timeout: 5))
        capture("08-password", app)
        app.buttons["Forgot password?"].tap()
        capture("09-recovery", app)
        app.buttons["signin.back"].tap()
        app.buttons["Sign in with a code instead"].tap()
        XCTAssertTrue(app.textFields["signin.email.field"].waitForExistence(timeout: 5))
        capture("10-email-code-entry", app)
        app.buttons["signin.close"].tap()
        app.buttons["onboarding.guest"].tap()
        XCTAssertTrue(element("finishing.complete", app).waitForExistence(timeout: 5))
    }

    func testSettingsSignInUsesNativeNavigationAndCancelRestoresTheTab() {
        let app = launch("settings-auth", theme: "light")
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        app.buttons["settings.signin"].tap()
        XCTAssertTrue(app.buttons["signin.email"].waitForExistence(timeout: 5))
        app.buttons["signin.email"].tap()
        XCTAssertTrue(app.textFields["signin.identifier.field"].waitForExistence(timeout: 5))
        capture("settings-inline-sign-in", app)
        app.buttons["signin.close"].tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        XCTAssertTrue(settings.isSelected)
        XCTAssertTrue(app.buttons["settings.signin"].isHittable)
    }

    func testAnnualPricingPrototypeShowsMonthlyEquivalentAndNativeSelection() {
        for theme in ["light", "dark"] {
            let app = launch("paywall", theme: theme)
            let annual = app.buttons["paywall.annual"]
            XCTAssertTrue(annual.waitForExistence(timeout: 10))
            XCTAssertTrue(annual.isSelected)
            XCTAssertTrue(app.staticTexts["$2.08"].exists)
            XCTAssertFalse(app.staticTexts["$24.99"].exists)
            app.buttons["paywall.monthly"].tap()
            XCTAssertTrue(app.buttons["paywall.monthly"].isSelected)
            annual.tap()
            capture("paywall-prototype-" + theme, app)
            app.terminate()
        }
    }

    func testAuthPreviewStatesAndKeyboard() {
        for screen in ["auth-code", "auth-reset", "auth-signup"] {
            let app = launch(screen, theme: "light")
            XCTAssertTrue(app.buttons["signin.close"].waitForExistence(timeout: 10))
            capture(screen, app)
            if screen == "auth-signup" {
                app.textFields["signup.email.field"].tap()
                app.textFields["signup.email.field"].typeText("reader@example.org")
                XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
                app.swipeUp()
                XCTAssertTrue(app.buttons["signup.submit"].isHittable)
                capture("sign-up-keyboard", app)
            }
            app.terminate()
        }
    }

    func testNativeReaderSheetGalleryAndGlassControlSize() {
        for screen in ["contents", "search", "saved", "saved-main", "bookmark", "reader"] {
            let app = launch(screen, theme: "paper")
            let probe = screen == "bookmark" ? app.buttons["Start of page"] : screen == "reader" ? element("reader.volumeHeader", app) : app.navigationBars.firstMatch
            XCTAssertTrue(probe.waitForExistence(timeout: 10), screen)
            if screen == "search" {
                let field = app.searchFields.firstMatch
                XCTAssertTrue(field.waitForExistence(timeout: 5))
                if app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Speed up your typing")).firstMatch.exists { app.buttons["Continue"].tap() }
                capture("reader-search-ready", app)
                field.tap(); field.typeText("zzz-no-match")
                XCTAssertTrue(element("reader.search.empty", app).waitForExistence(timeout: 5))
            }
            if screen == "saved-main" {
                let notes = app.buttons["saved.filter.notes"]
                XCTAssertTrue(notes.isHittable)
                notes.tap()
                XCTAssertTrue(app.staticTexts["No notes yet"].waitForExistence(timeout: 5))
                let canvas = pixel(app, at: CGPoint(x: 4, y: app.frame.midY))
                XCTAssertGreaterThan(Int(canvas[0]) - Int(canvas[2]), 10, "Saved must retain the warm Paper canvas, not the system white background")
            }
            capture("reader-" + screen, app)
            if screen == "reader" {
                let control = app.buttons["reader.menu"]
                XCTAssertTrue(control.exists)
                XCTAssertEqual(control.frame.width, 52, accuracy: 1)
            }
            app.terminate()
        }
    }

    func testLargeRTLWelcomeAndAccount() {
        for screen in ["welcome", "account", "auth-signup"] {
            let app = launch(screen, theme: "light", large: true, locale: "ar")
            let probe = screen == "auth-signup" ? "signin.close" : screen == "account" ? "onboarding.guest" : "onboarding.getStarted"
            XCTAssertTrue(app.buttons[probe].waitForExistence(timeout: 10))
            for _ in 0..<4 where !app.buttons[probe].isHittable { app.swipeUp() }
            XCTAssertTrue(app.buttons[probe].isHittable)
            capture(screen + "-large-rtl", app)
            app.terminate()
        }
    }

    func testSavedFiltersAdaptToLargeText() {
        let app = launch("saved", theme: "light", large: true, locale: "ar")
        let filter = app.buttons["reader.savedShortcut.filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        XCTAssertTrue(filter.isHittable)
        filter.tap()
        capture("reader-saved-large-rtl", app)
    }

    func testReducedTransparencyKeepsReaderControlsUsable() {
        let original = setReducedTransparency(true)
        defer { _ = setReducedTransparency(original) }
        let app = launch("reader", theme: "light")
        XCTAssertTrue(app.buttons["reader.menu"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["reader.menu"].frame.width, 52, accuracy: 1)
        capture("reader-reduced-transparency", app)
        app.buttons["reader.menu"].tap()
        XCTAssertTrue(app.buttons["reader.menu.contents"].waitForExistence(timeout: 5))
        app.terminate()
    }

    private func setReducedTransparency(_ enabled: Bool) -> Bool {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let toggle = settings.switches["Reduce Transparency"]
        if !toggle.waitForExistence(timeout: 2) {
            for _ in 0..<6 {
                if settings.cells.containing(.staticText, identifier: "Accessibility").firstMatch.exists { break }
                let back = settings.navigationBars.buttons.element(boundBy: 0)
                if back.exists && back.isHittable { back.tap() } else { break }
            }
            let accessibility = settings.cells.containing(.staticText, identifier: "Accessibility").firstMatch
            for _ in 0..<8 where !accessibility.isHittable { settings.swipeUp() }
            XCTAssertTrue(accessibility.exists)
            accessibility.tap()
            settings.staticTexts["Display & Text Size"].tap()
            for _ in 0..<5 where !toggle.isHittable { settings.swipeUp() }
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let original = toggle.value as? String == "1"
        if original != enabled { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", enabled ? "1" : "0"), object: toggle)], timeout: 5), .completed)
        return original
    }

    func testReaderUndoStaysAboveBottomControlsAndRestoresBookmark() {
        let app = launch("reader-undo", theme: "dark")
        let close = app.buttons["reader.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        let controlsTop = close.frame.minY
        let arabic = app.staticTexts["reader.arabic"].firstMatch
        arabic.press(forDuration: 0.8)
        let bookmark = app.buttons["reader.bookmark"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 5))
        bookmark.tap()
        if app.buttons["Remove"].waitForExistence(timeout: 1) { app.buttons["Remove"].tap() }
        let undo = app.buttons["saved.undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2))
        XCTAssertLessThanOrEqual(undo.frame.maxY, controlsTop)
        XCTAssertTrue(undo.isHittable)
        capture("reader-undo-safe-area", app)
        undo.tap()
        XCTAssertFalse(undo.exists)
        XCTAssertTrue(element("reader.savedBookmark", app).exists)
    }

    func testReaderFocusRemovesGlassControlsAndSystemStatusBar() {
        let app = launch("reader", theme: "dark")
        let close = app.buttons["reader.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        let statusVisible = statusBarWhiteFraction(app)
        XCTAssertGreaterThan(statusVisible, 0.02)
        capture("reader-chrome-visible", app)
        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["reader.menu"].exists)
        XCTAssertLessThan(statusBarWhiteFraction(app), statusVisible * 0.3)
        capture("reader-focused", app)
        center.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.statusBarWhiteFraction(app) > statusVisible * 0.7 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 8), .completed)
        capture("reader-chrome-restored", app)
    }

    func testReaderScrollingDoesNotRebuildThePageStrip() {
        let app = XCUIApplication()
        app.launchArguments = ["-NativeFinishingFixture"]
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "FINISH_SCREEN": "reader", "FINISH_THEME": "dark", "PAGING_RENDER": "interactive", "READER_PERFORMANCE_PROBE": "1"]
        app.launch()
        let probe = app.staticTexts["reader.performance.root"]
        XCTAssertTrue(probe.waitForExistence(timeout: 10))
        let initial = Int(probe.label.split(separator: ":").first!)!
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        let finish = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.1, thenDragTo: finish)
        let final = Int(probe.label.split(separator: ":").first!)!
        let text = "Reader root evaluations during one vertical drag: \(final - initial)"
        let report = XCTAttachment(string: text); report.name = "reader-render-count"; report.lifetime = .keepAlways; add(report)
        XCTAssertLessThanOrEqual(final - initial, 5, text)
    }

    func testReaderSavedSelectionCanBeDraggedInBothDirections() {
        for locale in ["en", "ar"] {
            let app = launch("saved", theme: "dark", locale: locale)
            let all = app.buttons["reader.savedShortcut.filter.all"]
            let notes = app.buttons["reader.savedShortcut.filter.notes"]
            XCTAssertTrue(all.waitForExistence(timeout: 10))
            XCTAssertLessThanOrEqual(abs(notes.frame.midX - all.frame.midX), 260)
            all.press(forDuration: 0.1, thenDragTo: notes)
            XCTAssertTrue(notes.isSelected)
            notes.press(forDuration: 0.1, thenDragTo: all)
            XCTAssertTrue(all.isSelected)
            capture("saved-drag-\(locale)", app)
            app.terminate()
        }
    }

    func testNormalRTLReaderAndEntryGallery() {
        for locale in ["ar", "ur"] {
            for screen in ["welcome", "account", "reader", "contents", "saved"] {
                let app = launch(screen, theme: "light", locale: locale)
                let probe = screen == "welcome" ? app.buttons["onboarding.getStarted"] : screen == "account" ? app.buttons["onboarding.signIn"] : screen == "reader" ? element("reader.volumeHeader", app) : app.navigationBars.firstMatch
                XCTAssertTrue(probe.waitForExistence(timeout: 10))
                capture("normal-\(locale)-\(screen)", app)
                app.terminate()
            }
        }
    }

    private func launch(_ screen: String, theme: String = "dark", large: Bool = false, locale: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-NativeFinishingFixture"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "FINISH_SCREEN": screen, "FINISH_THEME": theme, "FINISH_LOCALE": locale, "POLISH_THEME": theme, "PAGING_RENDER": "interactive"]
        if screen == "reader-undo" { app.launchEnvironment["READER_UNDO_PROBE"] = "1" }
        app.launch()
        return app
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    @discardableResult
    private func waitForOnboardingDailyResult(_ app: XCUIApplication) -> Bool {
        let text = element("onboarding.dailyText", app)
        let retry = app.buttons["onboarding.dailyRetry"]
        let result = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in text.exists || retry.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [result], timeout: 20), .completed)
        return text.exists || retry.exists
    }
    private func statusBarWhiteFraction(_ app: XCUIApplication) -> Double {
        let original = app.screenshot().image.cgImage!
        let scale = CGFloat(original.width) / app.frame.width
        let image = original.cropping(to: CGRect(x: 45 * scale, y: 20 * scale, width: 70 * scale, height: 25 * scale))!
        var rgba = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &rgba, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let white = stride(from: 0, to: rgba.count, by: 4).filter { rgba[$0] > 180 && rgba[$0 + 1] > 180 && rgba[$0 + 2] > 180 }.count
        return Double(white) / Double(image.width * image.height)
    }

    private func pixel(_ app: XCUIApplication, at point: CGPoint) -> [UInt8] {
        let image = app.screenshot().image.cgImage!
        let scale = CGFloat(image.width) / app.frame.width
        let sample = image.cropping(to: CGRect(x: point.x * scale, y: point.y * scale, width: 1, height: 1))!
        var rgba = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return rgba
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "finishing-" + name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
