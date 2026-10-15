import XCTest
import UIKit

final class VisualPolishUITests: XCTestCase {
    func testPageHandoffKeepsIncomingTextGeometry() {
        var positions: [CGFloat] = []
        for renderer in ["neighbor", "active"] {
            let app = XCUIApplication()
            app.launchArguments = ["-NativePolishFixture"]
            app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "POLISH_SCREEN": "reader", "POLISH_THEME": "light", "PAGING_RENDER": renderer]
            app.launch()
            let text = app.staticTexts["reader.arabic"].firstMatch
            XCTAssertTrue(text.waitForExistence(timeout: 10))
            positions.append(text.frame.minY)
            capture("page-handoff-\(renderer)", app)
            app.terminate()
        }
        XCTAssertEqual(positions[0], positions[1], accuracy: 1, "Incoming text must not jump when its page becomes active")
    }
    func testReaderSourcesOpenFromHadithHeader() {
        let app = XCUIApplication()
        app.launchArguments = ["-NativePolishFixture"]
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "POLISH_SCREEN": "reader", "POLISH_THEME": "paper", "Q1_STATE": "sources"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Prepared sourced translation"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["reader.aiBadge"].exists)
        app.buttons.matching(identifier: "reader.hadithLabel").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Prepared reference"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["reader.sourceSheet.name"].exists)
        XCTAssertTrue(element("translation.sources.ai", app).exists)
        capture("combined-reader-sources", app)
    }

    func testProductionReaderSwipesAndHintDoesNotRepeat() {
        let app = XCUIApplication()
        app.launchArguments = ["-NativePolishFixture"]
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "POLISH_SCREEN": "reader", "POLISH_THEME": "light", "PAGING_RENDER": "interactive", "POLISH_RESET_HINT": "1"]
        app.launch()
        XCTAssertTrue(element("reader.volumeHeader", app).waitForExistence(timeout: 10))
        XCTAssertTrue(element("reader.actionHint", app).waitForExistence(timeout: 5))
        app.buttons["Dismiss hint"].tap()
        app.swipeLeft()
        XCTAssertTrue(element("reader.volumeCorner", app).waitForExistence(timeout: 5))
        app.swipeRight()
        XCTAssertTrue(element("reader.volumeHeader", app).waitForExistence(timeout: 5))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)))
        XCTAssertTrue(element("reader.volumeHeader", app).exists)
        app.terminate()
        app.launchEnvironment["POLISH_RESET_HINT"] = "0"
        app.launch()
        XCTAssertTrue(element("reader.volumeHeader", app).waitForExistence(timeout: 10))
        XCTAssertFalse(element("reader.actionHint", app).exists)
        capture("reader-final", app)
    }

    func testProductionReaderRTLSwipes() {
        let app = XCUIApplication()
        app.launchArguments = ["-NativePolishFixture"]
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "POLISH_SCREEN": "reader", "POLISH_THEME": "paper", "PAGING_RENDER": "interactive", "POLISH_DIRECTION": "rtl"]
        app.launch()
        XCTAssertTrue(element("reader.volumeHeader", app).waitForExistence(timeout: 10))
        app.swipeRight()
        XCTAssertTrue(element("reader.volumeCorner", app).waitForExistence(timeout: 5))
        app.swipeLeft()
        XCTAssertTrue(element("reader.volumeHeader", app).waitForExistence(timeout: 5))
        capture("reader-rtl-final", app)
    }

    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        let app = XCUIApplication()
        if app.state == .runningForeground { capture("final-" + name, app) }
        app.terminate()
        XCUIApplication(bundleIdentifier: "com.apple.Preferences").terminate()
    }

    func testLightSettingsHasDistinctSurfaces() {
        let app = XCUIApplication()
        app.launchArguments = ["-ReaderSettingsFixture"]
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "READER_SETTINGS_CONTEXT": "global", "READER_SETTINGS_THEME": "light"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        let title = app.navigationBars["Settings"].staticTexts["Settings"]
        XCTAssertTrue(title.exists)
        XCTAssertGreaterThan(inkFraction(in: app, rect: title.frame), 0.02, "The Settings title must contain visible dark text, not only an accessibility label")
        let row = app.buttons["settings.row.appearance"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let canvas = pixel(in: app, at: CGPoint(x: 4, y: row.frame.midY))
        let surface = pixel(in: app, at: CGPoint(x: row.frame.minX + row.frame.width * 0.7, y: row.frame.midY))
        XCTAssertGreaterThan(Int(canvas[0]) - Int(surface[0]), 10, "Light settings cells must not disappear into the white canvas")
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "light-settings-surfaces"
        capture.lifetime = .keepAlways
        add(capture)
    }

    func testLoadingSurfacesAndCollectionTitlesAcrossThemes() {
        for theme in ["light", "dark", "paper"] {
            for screen in ["today-loading", "library-ready", "saved-loading", "reader-loading"] {
                let app = launchPolish(screen, theme: theme)
                let probe = screen == "library-ready" ? "library.collection.bukhari" : screen == "reader-loading" ? "reader.pageLoading" : screen == "today-loading" ? "today.dailyLoading" : "loading.skeleton"
                XCTAssertTrue(element(probe, app).waitForExistence(timeout: 10), "Missing \(screen) in \(theme)")
                capture("\(screen)-\(theme)", app)
                app.terminate()
            }
        }
    }

    func testTodayRefreshAndOnboardingPreparedReveal() {
        let today = launchPolish("today-loading", theme: "light")
        XCTAssertTrue(element("today.dailyLoading", today).waitForExistence(timeout: 10))
        let scroll = today.scrollViews.firstMatch
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            .press(forDuration: 0.1, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        XCTAssertTrue(element("today.dailyCard", today).waitForExistence(timeout: 10))
        let expand = today.buttons["today.expand"]
        for _ in 0..<4 where !expand.isHittable { today.swipeUp() }
        expand.tap()
        XCTAssertTrue(today.buttons["Show less"].exists)
        capture("today-loaded-expanded", today)
        today.terminate()

        let demo = launchPolish("demo", theme: "paper")
        XCTAssertTrue(element("onboarding.preparedPlaceholder", demo).waitForExistence(timeout: 10))
        demo.buttons["onboarding.reveal"].tap()
        XCTAssertTrue(element("onboarding.example", demo).waitForExistence(timeout: 5))
        XCTAssertFalse(element("onboarding.preparedPlaceholder", demo).exists)
        capture("onboarding-prepared-revealed", demo)
        demo.terminate()

        for screen in ["today-failure", "saved-failure"] {
            let failed = launchPolish(screen)
            let title = screen == "saved-failure" ? "Saved items could not load" : "Today's hadith could not load"
            XCTAssertTrue(failed.staticTexts[title].waitForExistence(timeout: 10))
            XCTAssertFalse(element(screen == "today-failure" ? "today.dailyLoading" : "loading.skeleton", failed).exists)
            capture(screen, failed)
            failed.terminate()
        }
    }

    func testAIWaitingMotionAndReducedMotionThenCompletion() {
        let original = setReducedMotion(false)
        defer { _ = setReducedMotion(original) }
        for reduced in [false, true] {
            _ = setReducedMotion(reduced)
            let app = launchPolish("reader", theme: "light", reduced: reduced)
            let waiting = element("reader.translationLoading", app)
            XCTAssertTrue(waiting.waitForExistence(timeout: 10))
            let rect = waiting.frame
            let before = cropped(app, rect)
            Thread.sleep(forTimeInterval: 0.31)
            let after = cropped(app, rect)
            if reduced { XCTAssertEqual(before, after, "Reduce Motion must leave the waiting indicator static") }
            else { XCTAssertNotEqual(before, after, "An active AI request must show motion") }
            capture(reduced ? "ai-waiting-reduced" : "ai-waiting", app)
            waiting.doubleTap()
            XCTAssertTrue(app.staticTexts["Prepared translation preview."].waitForExistence(timeout: 10))
            XCTAssertFalse(waiting.exists)
            capture(reduced ? "ai-result-reduced" : "ai-result", app)
            app.terminate()
        }
    }

    func testLargeRTLAndOnboardingStepNavigation() {
        let app = launchPolish("library-ready", theme: "light", locale: "ar", large: true)
        XCTAssertTrue(app.buttons["library.collection.bukhari"].waitForExistence(timeout: 10))
        capture("library-large-rtl", app)
        app.buttons["library.layoutToggle"].tap()
        XCTAssertTrue(app.buttons["library.collection.bukhari"].exists)
        capture("library-list-large-rtl", app)
        app.terminate()

        let original = setReducedMotion(true)
        defer { _ = setReducedMotion(original) }
        let demo = launchPolish("demo", theme: "dark", reduced: true, large: true)
        XCTAssertTrue(demo.buttons["onboarding.reveal"].waitForExistence(timeout: 10))
        demo.buttons["onboarding.reveal"].tap()
        XCTAssertTrue(element("onboarding.example", demo).waitForExistence(timeout: 5))
        capture("onboarding-large-reduced", demo)
    }

    func testOnboardingStepNavigationRemainsImmediatelyUsable() {
        let app = launchPolish("onboarding", theme: "light")
        XCTAssertTrue(app.buttons["onboarding.getStarted"].waitForExistence(timeout: 10))
        app.buttons["onboarding.getStarted"].tap()
        XCTAssertTrue(app.buttons["onboarding.continue"].waitForExistence(timeout: 5))
        capture("onboarding-language-step", app)
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.buttons["onboarding.reveal"].waitForExistence(timeout: 5))
        app.buttons["onboarding.reveal"].tap()
        XCTAssertTrue(element("onboarding.example", app).waitForExistence(timeout: 5))
        capture("onboarding-demo-step", app)
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.buttons["onboarding.guest"].waitForExistence(timeout: 5))
        app.buttons["onboarding.back"].tap()
        XCTAssertTrue(app.buttons["onboarding.reveal"].waitForExistence(timeout: 5))
        app.buttons["onboarding.skip"].tap()
        app.buttons["onboarding.guest"].tap()
        XCTAssertTrue(element("polish.onboardingDone", app).waitForExistence(timeout: 5))
    }

    @discardableResult
    private func setReducedMotion(_ enabled: Bool) -> Bool {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let toggle = settings.switches["Reduce Motion"]
        if !toggle.waitForExistence(timeout: 2) {
            for _ in 0..<5 {
                if settings.cells.containing(.staticText, identifier: "Accessibility").firstMatch.exists { break }
                let back = settings.navigationBars.buttons.element(boundBy: 0)
                if back.exists && back.isHittable { back.tap() } else { break }
            }
            let accessibility = settings.cells.containing(.staticText, identifier: "Accessibility").firstMatch
            for _ in 0..<8 where !accessibility.isHittable { settings.swipeUp() }
            XCTAssertTrue(accessibility.exists)
            accessibility.tap()
            settings.staticTexts["Motion"].tap()
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let original = toggle.value as? String == "1"
        if original != enabled { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", enabled ? "1" : "0"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed)
        return original
    }

    private func launchPolish(_ screen: String, theme: String = "light", reduced: Bool = false, locale: String = "en", large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-NativePolishFixture"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "POLISH_SCREEN": screen, "POLISH_THEME": theme,
            "POLISH_LOCALE": locale, "POLISH_REDUCE_MOTION": reduced ? "1" : "0", "Q1_STATE": "loading", "Q1_LANGUAGE": "ru",
            "POLISH_INTERACTIVE": "1", "R6A_LOADING_FIXTURE": screen == "reader-loading" ? "true" : "false"]
        app.launch()
        return app
    }

    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func cropped(_ app: XCUIApplication, _ rect: CGRect) -> Data? {
        let image = app.screenshot().image.cgImage!
        let scale = CGFloat(image.width) / app.frame.width
        let box = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        guard let crop = image.cropping(to: box) else { return nil }
        return UIImage(cgImage: crop).pngData()
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("polish-\(name).png")
        try? app.screenshot().pngRepresentation.write(to: file)
    }

    private func inkFraction(in app: XCUIApplication, rect: CGRect) -> Double {
        guard rect.width > 0, rect.height > 0 else { return 0 }
        let image = app.screenshot().image.cgImage!
        let scale = CGFloat(image.width) / app.frame.width
        guard let crop = image.cropping(to: CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)) else { return 0 }
        var rgba = [UInt8](repeating: 255, count: 64 * 24 * 4)
        let context = CGContext(data: &rgba, width: 64, height: 24, bitsPerComponent: 8, bytesPerRow: 64 * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(crop, in: CGRect(x: 0, y: 0, width: 64, height: 24))
        return Double(stride(from: 0, to: rgba.count, by: 4).filter { Int(rgba[$0]) + Int(rgba[$0 + 1]) + Int(rgba[$0 + 2]) < 450 }.count) / (64 * 24)
    }

    private func pixel(in app: XCUIApplication, at point: CGPoint) -> [UInt8] {
        let image = app.screenshot().image.cgImage!
        let scale = CGFloat(image.width) / app.frame.width
        let sample = image.cropping(to: CGRect(x: point.x * scale, y: point.y * scale, width: 1, height: 1))!
        var rgba = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &rgba, width: 1, height: 1, bitsPerComponent: 8,
                                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return rgba
    }
}
