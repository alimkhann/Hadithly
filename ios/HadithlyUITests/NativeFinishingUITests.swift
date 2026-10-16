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
        XCTAssertTrue(app.buttons["onboarding.reveal"].waitForExistence(timeout: 5))
        capture("03-example-ready", app)
        app.buttons["onboarding.reveal"].tap()
        XCTAssertTrue(element("onboarding.example", app).waitForExistence(timeout: 5))
        capture("04-example-revealed", app)
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.buttons["onboarding.guest"].waitForExistence(timeout: 5))
        capture("05-account", app)
        app.buttons["onboarding.createAccount"].tap()
        XCTAssertTrue(app.textFields["signup.email.field"].waitForExistence(timeout: 5))
        capture("06-sign-up", app)
        app.buttons["signin.close"].tap()
        app.buttons["onboarding.signIn"].tap()
        XCTAssertTrue(app.buttons["signin.email"].waitForExistence(timeout: 5))
        capture("07-auth-methods", app)
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

    private func launch(_ screen: String, theme: String = "dark", large: Bool = false, locale: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-NativeFinishingFixture"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "FINISH_SCREEN": screen, "FINISH_THEME": theme, "FINISH_LOCALE": locale, "POLISH_THEME": theme, "PAGING_RENDER": "interactive"]
        app.launch()
        return app
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
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
