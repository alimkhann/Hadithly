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

    private func edgeFixture(rtl: Bool = false, large: Bool = false, reduceMotion: Bool = false, interrupt: Bool = false, jump: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-A5ContentsNavigationFixture"]
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "PAGING_EDGES": "1",
                                 "PAGING_EDGES_RTL": rtl ? "1" : "0",
                                 "A5_LOCALE": rtl ? "ar" : "en", "A5_LARGE_TEXT": large ? "1" : "0",
                                 "PAGING_EDGES_REDUCE_MOTION": reduceMotion ? "1" : "0",
                                 "PAGING_EDGES_INTERRUPT": interrupt ? "1" : "0",
                                 "PAGING_JUMP": jump ? "1" : "0",
                                 "PAGING_JUMP_DARK": jump ? "1" : "0"]
        app.launch()
        XCTAssertTrue(app.staticTexts["paging.location"].waitForExistence(timeout: 10))
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "ready"), object: app.staticTexts["paging.ready"])], timeout: 10) == .completed)
        return app
    }

    private func edgeLocation(_ app: XCUIApplication, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let location = app.staticTexts["paging.location"]
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: location)], timeout: 8) == .completed,
                      "Expected \(expected), got \(location.label)", file: file, line: line)
    }

    private func edgeDrag(_ app: XCUIApplication, forward: Bool, rtl: Bool = false, slow: Bool = false) {
        let leftward = forward != rtl
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: leftward ? 0.83 : 0.17, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: leftward ? 0.17 : 0.83, dy: 0.5))
        start.press(forDuration: 0.08, thenDragTo: end,
                    withVelocity: slow ? .slow : XCUIGestureVelocity(rawValue: 900), thenHoldForDuration: 0)
    }

    func testJumpPageWheelWrapsWithinSelectedVolume() {
        let app = edgeFixture(jump: true)
        defer { app.terminate() }
        let open = app.buttons["reader.jump.openPage"]
        XCTAssertTrue(open.waitForExistence(timeout: 5), app.debugDescription)
        open.tap()
        XCTAssertTrue(app.buttons["reader.jump.go"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "reader-jump-sheet"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let page = app.pickerWheels.element(boundBy: 1)
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        let volume = app.pickerWheels.element(boundBy: 0)
        XCTAssertTrue(volume.exists)
        let originalVolume = volume.value as? String
        XCTAssertEqual(originalVolume, "2")
        XCTAssertEqual(page.value as? String, "2")
        let center = page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let nextRow = page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.27))
        center.press(forDuration: 0.2, thenDragTo: nextRow,
                     withVelocity: XCUIGestureVelocity(rawValue: 35), thenHoldForDuration: 1.5)
        XCTAssertEqual(volume.value as? String, originalVolume)
        page.adjust(toPickerWheelValue: "2")
        page.adjust(toPickerWheelValue: "1")
        XCTAssertEqual(page.value as? String, "1")
        XCTAssertEqual(volume.value as? String, originalVolume)
        page.adjust(toPickerWheelValue: "2")
        XCTAssertEqual(page.value as? String, "2")
        XCTAssertEqual(volume.value as? String, originalVolume)
        volume.adjust(toPickerWheelValue: "3")
        XCTAssertEqual(page.value as? String, "1")
        app.buttons["reader.jump.go"].tap()
        edgeLocation(app, "3:0")
    }

    func testPreparedEdgesBothDirectionsAndAbsoluteBoundaries() {
        let app = edgeFixture()
        defer { app.terminate() }
        edgeLocation(app, "2:1")
        edgeDrag(app, forward: true, slow: true)
        edgeLocation(app, "3:0")
        XCTAssertTrue(element("reader.volumeHeader", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["reader.arabic"].firstMatch.label.contains("301"), "The committed text must match the displayed volume")
        edgeDrag(app, forward: false)
        edgeLocation(app, "2:1")
        edgeDrag(app, forward: false, slow: true)
        edgeLocation(app, "2:0")
        edgeDrag(app, forward: false)
        edgeLocation(app, "1:1")
        edgeDrag(app, forward: false)
        edgeLocation(app, "1:0")
        edgeDrag(app, forward: false)
        edgeLocation(app, "1:0")
        for expected in ["1:1", "2:0", "2:1", "3:0", "3:1"] {
            edgeDrag(app, forward: true)
            edgeLocation(app, expected)
        }
        edgeDrag(app, forward: true)
        edgeLocation(app, "3:1")
    }

    func testPreparedEdgesCancelReverseAndRTLAtLargeText() {
        let app = edgeFixture(rtl: true, large: true, reduceMotion: true)
        defer { app.terminate() }
        edgeLocation(app, "2:1")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let short = app.coordinate(withNormalizedOffset: CGVector(dx: 0.54, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: short, withVelocity: .slow, thenHoldForDuration: 0)
        edgeLocation(app, "2:1")
        let diagonal = app.coordinate(withNormalizedOffset: CGVector(dx: 0.56, dy: 0.22))
        start.press(forDuration: 0.1, thenDragTo: diagonal, withVelocity: .slow, thenHoldForDuration: 0)
        edgeLocation(app, "2:1")
        for _ in 0..<2 {
            edgeDrag(app, forward: true, rtl: true, slow: true)
            edgeLocation(app, "3:0")
            edgeDrag(app, forward: false, rtl: true)
            edgeLocation(app, "2:1")
        }
    }

    func testFooterControlsNavigateCachedEdgesAndChromeKeepsGeometry() {
        let app = edgeFixture()
        defer { app.terminate() }
        edgeLocation(app, "2:1")
        func revealFooter(_ identifier: String) -> XCUIElement {
            let button = app.buttons[identifier]
            for _ in 0..<8 where !button.isHittable { app.swipeUp() }
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            XCTAssertTrue(button.isHittable)
            XCTAssertTrue(button.isEnabled)
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            return button
        }
        let next = revealFooter("reader.nextPage")
        XCTAssertTrue(next.label.contains("Next page"))
        XCTAssertTrue(next.label.contains("Volume 3"))
        let footerY = next.frame.minY
        let page = element("reader.page", in: app)
        let pageTop = page.frame.minY
        let pageBottom = page.frame.maxY
        let chrome = app.buttons["reader.close"]
        let wasVisible = chrome.exists && chrome.isHittable
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.36)).tap()
        if wasVisible {
            XCTAssertTrue(chrome.waitForNonExistence(timeout: 5))
        } else {
            XCTAssertTrue(chrome.waitForExistence(timeout: 5))
        }
        XCTAssertEqual(page.frame.minY, pageTop, accuracy: 1)
        XCTAssertEqual(page.frame.maxY, pageBottom, accuracy: 1)
        XCTAssertEqual(next.frame.minY, footerY, accuracy: 2, "Reader chrome must not shift footer content")
        next.tap()
        edgeLocation(app, "3:0")
        let previous = revealFooter("reader.previousPage")
        XCTAssertTrue(previous.label.contains("Previous page"))
        XCTAssertTrue(previous.label.contains("Volume 2"))
        previous.tap()
        edgeLocation(app, "2:1")
    }

    func testExplicitVolumeSelectionDuringSlowTurnWins() {
        let app = edgeFixture(interrupt: true)
        defer { app.terminate() }
        edgeLocation(app, "2:1")
        edgeDrag(app, forward: false, slow: true)
        XCTAssertTrue(app.staticTexts["a5.requests"].label.contains("interrupt-select"))
        edgeLocation(app, "3:0")
        Thread.sleep(forTimeInterval: 0.6)
        edgeLocation(app, "3:0")
        XCTAssertTrue(app.staticTexts["reader.arabic"].firstMatch.label.contains("301"))
    }

    func testVerifiedOfflineReaderTurnsForwardAndBackWithoutLiveReads() {
        let app = XCUIApplication()
        app.launchArguments = ["-A5ContentsNavigationFixture", "-forceOfflineReader"]
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "PAGING_OFFLINE": "1"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "ready"), object: app.staticTexts["paging.ready"])], timeout: 15) == .completed)
        edgeLocation(app, "2:0")
        XCTAssertTrue(app.staticTexts["reader.arabic"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["reader.arabic"].firstMatch.label.contains("1"))
        edgeDrag(app, forward: true, slow: true)
        edgeLocation(app, "2:1")
        XCTAssertTrue(app.staticTexts["reader.arabic"].firstMatch.label.contains("11"))
        XCTAssertTrue(app.buttons["reader.hadithLabel"].firstMatch.label.contains("11"))
        XCTAssertFalse(element("reader.pageLoading", in: app).exists)
        edgeDrag(app, forward: false)
        edgeLocation(app, "2:0")
        XCTAssertTrue(app.staticTexts["reader.arabic"].firstMatch.label.contains("1"))
        XCTAssertTrue(app.buttons["reader.hadithLabel"].firstMatch.label.contains("1"))
        XCTAssertFalse(app.staticTexts["a5.requests"].label.contains("live-fetch"))
    }

    func testInactiveTranslationGrowthPreservesSemanticLanding() {
        let app = XCUIApplication()
        app.launchArguments = ["-A5ContentsNavigationFixture"]
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "PAGING_RECENT": "1", "PAGING_TRANSLATION_GROWTH": "1"]
        app.launch()
        defer { app.terminate() }
        let translation = app.staticTexts["reader.translation"].firstMatch
        XCTAssertTrue(translation.waitForExistence(timeout: 10))
        XCTAssertEqual(translation.label, "Short private translation.")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
        Thread.sleep(forTimeInterval: 0.8)
        func viewport() -> (fraction: Double, height: Double) {
            let values = app.staticTexts["paging.viewport"].label.split(separator: "|").compactMap { Double($0) }
            XCTAssertEqual(values.count, 2)
            guard values.count == 2, values[1] > 0 else { return (-1, 0) }
            return (-values[0] / values[1], values[1])
        }
        let before = viewport()
        XCTAssertGreaterThan(before.fraction, 0.01)
        edgeDrag(app, forward: true)
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "1"), object: app.staticTexts["paging.page"])], timeout: 5) == .completed)
        app.buttons["paging.expandTranslation"].tap()
        edgeDrag(app, forward: false)
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "0"), object: app.staticTexts["paging.page"])], timeout: 5) == .completed)
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Expanded private translation."), object: translation)], timeout: 5) == .completed)
        Thread.sleep(forTimeInterval: 0.8)
        let after = viewport()
        XCTAssertGreaterThan(after.height, before.height)
        XCTAssertEqual(after.fraction, before.fraction, accuracy: 0.005)
    }

    func testContinueRestoresPersistedSemanticPositionForShortAndTallRows() {
        for tall in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["-A5ContentsNavigationFixture"]
            app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "PAGING_CONTINUE": "1", "PAGING_CONTINUE_TALL": tall ? "1" : "0"]
            app.launch()
            defer { app.terminate() }
            let geometry = app.staticTexts["paging.continueViewport"]
            XCTAssertTrue(geometry.waitForExistence(timeout: 10))
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: tall ? 0.25 : 0.48))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
            Thread.sleep(forTimeInterval: 0.8)
            let initialGeometry = geometry.label
            let arabicY = app.staticTexts["reader.arabic"].firstMatch.frame.minY
            let close = app.buttons["reader.close"]
            if !close.isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap() }
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            close.tap()
            let resume = app.buttons["paging.continue"]
            XCTAssertTrue(resume.waitForExistence(timeout: 5))
            resume.tap()
            print("CONTINUE_DIAG \(app.staticTexts["paging.continueDiagnostics"].firstMatch.label)")
            let persisted = app.staticTexts["paging.persisted"]
            XCTAssertTrue(persisted.waitForExistence(timeout: 10))
            XCTAssertTrue(geometry.waitForExistence(timeout: 10))
            Thread.sleep(forTimeInterval: 0.8)
            let saved = persisted.label.split(separator: "|")
            let restored = geometry.label.split(separator: "|")
            print("CONTINUE_FIXTURE tall=\(tall) before=\(initialGeometry) saved=\(persisted.label) after=\(geometry.label) arabicY=\(arabicY)->\(app.staticTexts["reader.arabic"].firstMatch.frame.minY)")
            XCTAssertGreaterThanOrEqual(saved.count, 3)
            XCTAssertEqual(restored.count, 5)
            guard saved.count >= 3, restored.count == 5,
                  let fraction = Double(saved[1]), let rowY = Double(restored[1]), let rowHeight = Double(restored[2]), rowHeight > 0 else { continue }
            XCTAssertEqual(String(restored[0]), String(saved[0]), "Continue must restore the persisted provider anchor")
            XCTAssertGreaterThan(fraction, 0.01, "The fixture must capture a partial row")
            XCTAssertEqual(max(0, -rowY / rowHeight), fraction, accuracy: 0.01, "Continue must restore the saved semantic fraction")
            app.terminate()
        }
    }

    func testUnavailableTurnKeepsOutgoingUntilReleased() {
        let app = XCUIApplication()
        app.launchArguments = ["-A5ContentsNavigationFixture"]
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "PAGING_RECENT": "1", "PAGING_PENDING": "1"]
        app.launch()
        defer { app.terminate() }
        let arabic = app.staticTexts["reader.arabic"].firstMatch
        XCTAssertTrue(arabic.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["paging.release"].waitForExistence(timeout: 5))
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "ready"), object: app.staticTexts["paging.ready"])], timeout: 5) == .completed)
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.5))
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.5))
        right.press(forDuration: 0.05, thenDragTo: left, withVelocity: XCUIGestureVelocity(rawValue: 500), thenHoldForDuration: 0)
        XCTAssertTrue(element("reader.pendingTurn", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["paging.page"].label, "0")
        XCTAssertTrue(arabic.isHittable, "The outgoing reading text must remain visible while waiting")
        let waiting = XCTAttachment(screenshot: app.screenshot()); waiting.name = "pending-outgoing-readable"; waiting.lifetime = .keepAlways; add(waiting)
        app.buttons["paging.release"].tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "1"), object: app.staticTexts["paging.page"])], timeout: 5) == .completed)
        XCTAssertFalse(element("reader.pendingTurn", in: app).exists)
        let landed = XCTAttachment(screenshot: app.screenshot()); landed.name = "pending-target-landed"; landed.lifetime = .keepAlways; add(landed)
    }

    func testReverseGestureCancelsDelayedTurnWithoutLateLanding() {
        let app = XCUIApplication()
        app.launchArguments = ["-A5ContentsNavigationFixture"]
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "PAGING_RECENT": "1", "PAGING_PENDING": "1"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["reader.arabic"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["paging.release"].waitForExistence(timeout: 5))
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "ready"), object: app.staticTexts["paging.ready"])], timeout: 5) == .completed)
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.5))
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.5))
        right.press(forDuration: 0.05, thenDragTo: left, withVelocity: XCUIGestureVelocity(rawValue: 500), thenHoldForDuration: 0)
        XCTAssertTrue(element("reader.pendingTurn", in: app).waitForExistence(timeout: 5))
        left.press(forDuration: 0.05, thenDragTo: right, withVelocity: XCUIGestureVelocity(rawValue: 500), thenHoldForDuration: 0)
        XCTAssertFalse(element("reader.pendingTurn", in: app).exists)
        app.buttons["paging.release"].tap()
        XCTAssertEqual(app.staticTexts["paging.page"].label, "0")
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(app.staticTexts["paging.page"].label, "0", "A reversed gesture must fence the delayed destination")
    }

    func testRecentPageReturnKeepsRenderedPosition() {
        let app = XCUIApplication()
        app.launchArguments = ["-A5ContentsNavigationFixture"]
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "PAGING_RECENT": "1"]
        app.launch()
        defer { app.terminate() }
        let arabic = app.staticTexts["reader.arabic"].firstMatch
        XCTAssertTrue(arabic.waitForExistence(timeout: 10))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.74))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
        Thread.sleep(forTimeInterval: 1)
        let before = arabic.frame.minY
        XCTAssertLessThan(before, 0, "The actual reading text must have moved")
        let original = XCTAttachment(screenshot: app.screenshot()); original.name = "page-A-scrolled"; original.lifetime = .keepAlways; add(original)
        app.buttons["paging.recreate"].tap()
        XCTAssertTrue(arabic.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(arabic.frame.minY, before, accuracy: 3, "A recreated active page must retain its current-reader position")
        edgeDrag(app, forward: true)
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "1"), object: app.staticTexts["paging.page"])], timeout: 5) == .completed)
        let unseen = element("reader.volumeCorner", in: app)
        XCTAssertTrue(unseen.isHittable, "An unseen page starts at its header")
        let unseenY = unseen.frame.minY
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(unseen.frame.minY, unseenY, accuracy: 1, "The incoming header cannot shift after landing")
        edgeDrag(app, forward: false)
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "0"), object: app.staticTexts["paging.page"])], timeout: 5) == .completed)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(arabic.frame.minY, before, accuracy: 3, "Final landing must retain A's rendered text position")
        let returned = XCTAttachment(screenshot: app.screenshot()); returned.name = "page-A-returned"; returned.lifetime = .keepAlways; add(returned)
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let short = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5))
        left.press(forDuration: 0.1, thenDragTo: short, withVelocity: .slow, thenHoldForDuration: 0)
        XCTAssertEqual(app.staticTexts["paging.page"].label, "0")
        XCTAssertEqual(arabic.frame.minY, before, accuracy: 3, "A canceled turn retains the active position")
    }

    func testPartialHeaderReturnAndInactiveLayoutChange() {
        let app = XCUIApplication()
        app.launchArguments = ["-A5ContentsNavigationFixture"]
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "PAGING_RECENT": "1"]
        app.launch()
        defer { app.terminate() }
        let header = element("reader.volumeHeader", in: app)
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
        Thread.sleep(forTimeInterval: 1)
        let headerY = header.frame.minY
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "partial-header-before"; capture.lifetime = .keepAlways; add(capture)
        app.swipeLeft()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "1"), object: app.staticTexts["paging.page"])], timeout: 5) == .completed)
        app.swipeRight()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "0"), object: app.staticTexts["paging.page"])], timeout: 5) == .completed)
        XCTAssertEqual(header.frame.minY, headerY, accuracy: 3)
        let returned = XCTAttachment(screenshot: app.screenshot()); returned.name = "partial-header-returned"; returned.lifetime = .keepAlways; add(returned)
        start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)), withVelocity: .slow, thenHoldForDuration: 0)
        Thread.sleep(forTimeInterval: 0.6)
        func normalizedViewport() -> Double {
            let values = app.staticTexts["paging.viewport"].label.split(separator: "|").compactMap { Double($0) }
            XCTAssertEqual(values.count, 2)
            return values.count == 2 ? -values[0] / values[1] : -1
        }
        let expectedOffset = normalizedViewport()
        let beforeHeight = Double(app.staticTexts["paging.viewport"].label.split(separator: "|").last ?? "0") ?? 0
        XCTAssertGreaterThan(expectedOffset, 0.01)
        app.swipeLeft()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "1"), object: app.staticTexts["paging.page"])], timeout: 5) == .completed)
        app.buttons["paging.grow"].tap()
        app.swipeRight()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "0"), object: app.staticTexts["paging.page"])], timeout: 5) == .completed)
        Thread.sleep(forTimeInterval: 0.6)
        let afterHeight = Double(app.staticTexts["paging.viewport"].label.split(separator: "|").last ?? "0") ?? 0
        XCTAssertGreaterThan(afterHeight, beforeHeight * 1.2, "The fixture must actually reflow to larger bilingual text")
        XCTAssertEqual(normalizedViewport(), expectedOffset, accuracy: 0.005, "Large bilingual layout changes must preserve the semantic fraction, not stale pixels")
    }

    func testGuestSavingNoteUndoAndSavedReaderReturn() {
        let app = XCUIApplication()
        app.launchArguments = ["-A5ContentsNavigationFixture", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "A5_LOCALE": "en", "A5_CONTROLS_ONLY": "1", "A5_CORE_SAVED": "1"]
        app.launch()
        defer { app.terminate() }
        let arabic = app.staticTexts["reader.arabic"].firstMatch
        XCTAssertTrue(arabic.waitForExistence(timeout: 10))
        arabic.press(forDuration: 0.8)
        app.buttons["reader.bookmark"].tap()
        XCTAssertTrue(element("reader.savedBookmark", in: app).waitForExistence(timeout: 5))
        arabic.press(forDuration: 0.8)
        app.buttons["reader.favorite"].tap()
        XCTAssertTrue(element("reader.savedFavorite", in: app).waitForExistence(timeout: 5))
        arabic.press(forDuration: 0.8)
        app.buttons["reader.note"].tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("Private %@ note اسم")
        app.buttons["note.save"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        XCTAssertTrue(element("reader.savedNote", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["a5.savedState"].label, "b:1|f:1|n:1|rows:1|note:Private %@ note اسم")
        arabic.press(forDuration: 0.8)
        app.buttons["reader.bookmark"].tap()
        if app.buttons["Remove"].waitForExistence(timeout: 1) { app.buttons["Remove"].tap() }
        let undo = app.buttons["saved.undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.tap()
        XCTAssertTrue(element("reader.savedBookmark", in: app).waitForExistence(timeout: 5))
        if !app.buttons["reader.close"].isHittable { arabic.tap() }
        app.buttons["reader.close"].tap()
        let saved = app.staticTexts["Original %@ 57"].firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        XCTAssertTrue(app.buttons["a5.releaseTarget"].waitForExistence(timeout: 5))
        app.buttons["a5.releaseTarget"].tap()
        let target = app.buttons.matching(identifier: "reader.hadithLabel").matching(NSPredicate(format: "label CONTAINS '57'")).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        XCTAssertTrue(target.isHittable)
        XCTAssertTrue(app.staticTexts["a5.savedState"].label.contains("Private %@ note اسم"))
    }

    func testProgressControlsPreserveFifteenLocaleBindings() {
        for locale in ["en","ar","ru","kk","ky","uz","tr","id","ur","fr","es-419","pt-BR","sw","hi","bn"] {
            let app = XCUIApplication()
            app.launchArguments = ["-A5ContentsNavigationFixture", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
            app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "A5_LOCALE": locale, "A5_CONTROLS_ONLY": "1"]
            app.launch()
            let progress = element("reader.unfocusedProgress", in: app)
            XCTAssertTrue(progress.waitForExistence(timeout: 10))
            let page = app.buttons["reader.jump.openPage"]
            XCTAssertTrue(page.waitForExistence(timeout: 5))
            XCTAssertTrue(page.label.contains(3.formatted(.number.locale(Locale(identifier: locale)))))
            let viewport = element("reader.page", in: app)
            XCTAssertLessThan(viewport.frame.minY, progress.frame.minY)
            let source = element("reader.volumeCorner", in: app)
            XCTAssertTrue(source.label.contains("Original %@ مصدر"))
            if source.isHittable { XCTAssertGreaterThanOrEqual(source.frame.minY, progress.frame.maxY) }
            app.terminate()
        }
    }

    func testTranslationSizeChangesActualReaderText() {
        let app = XCUIApplication()
        app.launchArguments = ["-A5ReaderTypeFixture"]
        app.launchEnvironment["HADITHLY_UI_TESTING"] = "1"
        app.launch()
        defer { app.terminate() }
        let text = app.staticTexts["reader.translation"]
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        app.buttons["a5.type.small"].tap()
        let small = text.frame.height
        let smallCapture = XCTAttachment(screenshot: app.screenshot()); smallCapture.name = "a5-type-14"; smallCapture.lifetime = .keepAlways; add(smallCapture)
        app.buttons["a5.type.large"].tap()
        XCTAssertEqual(app.staticTexts["a5.type.value"].label, "22.0")
        let largeCapture = XCTAttachment(screenshot: app.screenshot()); largeCapture.name = "a5-type-22"; largeCapture.lifetime = .keepAlways; add(largeCapture)
        let grows = NSPredicate { _, _ in text.frame.height > small + 2 }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: grows, object: nil)], timeout: 5), .completed, "Actual reader translation ignores selected type size: 14=\(small), 22=\(text.frame)")
        XCTAssertEqual(text.label, "Controlled original %@ text 57")
    }

    func testGoOwnsTargetWhilePrefetchIsInFlight() { goJourney(locale: "en", large: false) }

    func testGoAtLargeTextInRTLAndLongLocales() {
        for locale in ["ar", "ur", "ru", "bn"] { goJourney(locale: locale, large: true, controls: true) }
    }

    func testGoThenCloseReturnsWithoutRetargeting() { goJourney(locale: "en", large: false, returning: true) }

    func testTopControlsDoNotOverlapAtLargeText() { goJourney(locale: "ar", large: true, controls: true) }

    private func goJourney(locale: String, large: Bool, returning: Bool = false, controls: Bool = false) {
        let app = XCUIApplication()
        app.launchArguments = ["-A5ContentsNavigationFixture"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "A5_LOCALE": locale, "A5_LARGE_TEXT": large ? "1" : "0", "A5_RETURN": returning ? "1" : "0"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["a5.release"].waitForExistence(timeout: 10))
        app.buttons["reader.menu"].tap()
        app.buttons["reader.menu.contents"].tap()
        let jump = app.textFields["reader.contents.jump"]
        XCTAssertTrue(jump.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Original %@ مصدر"].firstMatch.exists)
        XCTAssertFalse(app.buttons["reader.contents.jumpGo"].isEnabled)
        jump.tap(); jump.typeText("abc")
        tapSettledGo(in: app)
        let invalid = element("reader.contents.jumpError", in: app).waitForExistence(timeout: 5)
        let diagnostic = XCTAttachment(screenshot: app.screenshot()); diagnostic.name = "a5-invalid-" + locale; diagnostic.lifetime = .keepAlways; add(diagnostic)
        XCTAssertTrue(invalid, "Input: \(jump.value ?? "nil"); Go: \(app.buttons["reader.contents.jumpGo"].debugDescription); Trace: " + app.staticTexts["a5.requests"].label)
        XCTAssertEqual(app.staticTexts["a5.requests"].label, "prefetch|submit:abc")
        jump.tap(); jump.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "57")
        tapSettledGo(in: app)
        XCTAssertTrue(jump.waitForNonExistence(timeout: 5), "Go did not dismiss Contents")
        XCTAssertTrue(app.buttons["a5.releaseTarget"].waitForExistence(timeout: 5))
        app.buttons["a5.release"].tap()
        XCTAssertEqual(app.staticTexts["a5.loading"].label, "loading:true")
        app.buttons["a5.releaseTarget"].tap()
        let target = app.buttons.matching(identifier: "reader.hadithLabel").matching(NSPredicate(format: "label CONTAINS '57'")).firstMatch
        let landed = target.waitForExistence(timeout: 10)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "a5-go-landing-" + locale; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertTrue(landed, "Go lost target 57. Requests: " + app.staticTexts["a5.requests"].label)
        XCTAssertTrue(target.isHittable)
        XCTAssertTrue(app.frame.contains(target.frame))
        let trace = app.staticTexts["a5.requests"].label
        XCTAssertEqual(trace.components(separatedBy: "jump:57").count - 1, 1)
        XCTAssertTrue(trace.contains("dismissed"))
        if controls {
            if !app.buttons["reader.close"].isHittable {
                app.staticTexts["reader.arabic"].firstMatch.tap()
            }
            let pills = element("reader.unfocusedProgress", in: app)
            XCTAssertTrue(pills.waitForExistence(timeout: 5))
            let corner = element("reader.volumeCorner", in: app)
            let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "a5-controls-" + locale; capture.lifetime = .keepAlways; add(capture)
            let viewport = element("reader.page", in: app)
            XCTAssertLessThan(viewport.frame.minY, pills.frame.minY, "Reader viewport must extend behind floating controls")
            if corner.isHittable {
                XCTAssertLessThanOrEqual(pills.frame.maxY, corner.frame.minY, "Visible source overlaps progress")
            }
            XCTAssertGreaterThanOrEqual(target.frame.minY + 0.5, pills.frame.maxY, "Navigation target must clear floating controls")
            XCTAssertGreaterThanOrEqual(pills.frame.height, 44, "Scaled caption must fit its progress capsule")
            let headerBefore = target.frame
            let arabic = app.staticTexts["reader.arabic"].firstMatch
            arabic.tap()
            XCTAssertTrue(app.buttons["reader.close"].waitForNonExistence(timeout: 5))
            XCTAssertTrue(target.exists)
            XCTAssertEqual(target.frame.minY, headerBefore.minY, accuracy: 1, "Focus must preserve the reading anchor")
            arabic.tap()
            XCTAssertTrue(app.buttons["reader.close"].waitForExistence(timeout: 5))
            XCTAssertEqual(target.frame.minY, headerBefore.minY, accuracy: 1, "Revealing controls must preserve the reading anchor")
        }
        if returning {
            if !app.buttons["reader.close"].isHittable {
                app.staticTexts["reader.arabic"].firstMatch.tap()
            }
            XCTAssertTrue(target.isHittable)
            app.buttons["reader.close"].tap()
            XCTAssertTrue(app.staticTexts["a5.returned"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["a5.returned"].isHittable)
        }
    }

    private func tapSettledGo(in app: XCUIApplication) {
        let go = app.buttons["reader.contents.jumpGo"]
        var previous = CGRect.null
        var stableSince = Date()
        let stable = NSPredicate { _, _ in
            let frame = go.frame
            if frame != previous { previous = frame; stableSince = Date(); return false }
            return go.isHittable && Date().timeIntervalSince(stableSince) >= 0.5
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: stable, object: nil)], timeout: 5), .completed)
        go.tap()
    }

    // MARK: - Fixture: chapters render from source-provided data

    func testContentsGuidanceAndValidationLocalizeAtRuntime() {
        for (locale, hint, error, title, volumes) in [
            ("ar", "انتقل إلى رقم حديث، مثل 57.", "أدخل رقم حديث مثل 57 أو 4.5.", "المحتويات", "المجلدات"),
            ("ru", "Перейти к номеру хадиса, например 57.", "Введите номер хадиса, например 57 или 4.5.", "Содержание", "ТОМА"),
            ("kk", "Хадис нөміріне өту, мысалы 57.", "57 немесе 4.5 сияқты хадис нөмірін енгізіңіз.", "Мазмұны", "ТОМДАР"),
            ("id", "Lompat ke nomor hadis, misalnya 57.", "Masukkan nomor hadis seperti 57 atau 4.5.", "Daftar isi", "VOLUME"),
            ("en", "Jump to a hadith number, e.g. 57.", "Enter a hadith number like 57 or 4.5.", "Contents", "Volumes"),
            ("ky", "Хадис номерине өтүңүз, мисалы 57.", "57 же 4.5 сыяктуу хадис номерин киргизиңиз.", "Мазмун", "ТОМДОР"),
            ("uz", "Hadis raqamiga o‘ting, masalan 57.", "57 yoki 4.5 kabi hadis raqamini kiriting.", "Mundarija", "JILDLAR"),
            ("tr", "Hadis numarasına git, örneğin 57.", "57 veya 4.5 gibi bir hadis numarası girin.", "İçindekiler", "CİLTLER"),
            ("ur", "حدیث نمبر پر جائیں، مثلاً 57۔", "57 یا 4.5 جیسا حدیث نمبر درج کریں۔", "فہرستِ مضامین", "جلدیں"),
            ("fr", "Aller au numéro de hadith, par exemple 57.", "Saisissez un numéro de hadith comme 57 ou 4.5.", "Sommaire", "TOMES"),
            ("es-419", "Ir al número de hadiz, por ejemplo, 57.", "Ingresa un número de hadiz como 57 o 4.5.", "Contenido", "VOLÚMENES"),
            ("pt-BR", "Ir para o número do hadith, por exemplo, 57.", "Digite um número de hadith como 57 ou 4.5.", "Conteúdo", "TOMOS"),
            ("sw", "Nenda kwenye nambari ya hadithi, kwa mfano 57.", "Weka nambari ya hadithi kama 57 au 4.5.", "Yaliyomo", "JUZUU"),
            ("hi", "हदीस संख्या पर जाएँ, जैसे 57।", "57 या 4.5 जैसा हदीस नंबर दर्ज करें।", "विषय-सूची", "खंड"),
            ("bn", "হাদিস নম্বরে যান, যেমন ৫৭।", "57 বা 4.5-এর মতো হাদিস নম্বর লিখুন।", "সূচিপত্র", "খণ্ড")
        ] {
            let app = XCUIApplication()
            app.launchArguments = ["-R5ContentsFixture"]
            app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "R5_LOCALE": locale]
            app.launch()
            XCTAssertTrue(app.staticTexts[hint].waitForExistence(timeout: timeout))
            XCTAssertEqual(element("reader.contents.title", in: app).label, title)
            XCTAssertTrue(app.staticTexts[volumes].exists)
            let jump = field("reader.contents.jump", in: app)
            jump.tap()
            jump.typeText("abc")
            element("reader.contents.jumpGo", in: app).tap()
            XCTAssertTrue(app.staticTexts[error].waitForExistence(timeout: timeout))
            XCTAssertTrue(jump.exists)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "contents-validation-" + locale
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }

    func testContentsShowsChaptersAndJumpField() {
        let app = launchContentsFixture()
        XCTAssertTrue(field("reader.contents.jump", in: app).waitForExistence(timeout: timeout))
        // Volume 1 starts expanded (it holds the selected volume): its
        // source-provided chapters render with counts, and the arabic
        // subtitle appears only where present and different.
        XCTAssertTrue(element("reader.contents.chapter.1.1", in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(element("reader.contents.chapter.1.6", in: app).exists)
        XCTAssertTrue(app.staticTexts["كتاب بدء الوحي"].exists)
        XCTAssertTrue(app.staticTexts["1. Revelation"].exists)
        XCTAssertFalse(app.buttons["Open from the start"].exists)
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

    func testContentsVolumeNameOpensWithoutExtraStartRow() {
        let app = launchContentsFixture()
        let volume = app.buttons.matching(identifier: "reader.volume.1").firstMatch
        XCTAssertTrue(volume.waitForExistence(timeout: timeout))
        volume.tap()
        XCTAssertTrue(element("r5.dismissed", in: app).waitForExistence(timeout: timeout))
    }

    func testContentsKeepsSourceNumbersAndDoesNotRepeatLocalizedGenericTitle() {
        let app = XCUIApplication()
        app.launchArguments = ["-R5ContentsFixture"]
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "R5_SPARSE_VOLUMES": "1", "R5_ARABIC_ONLY": "1"]
        app.launch()
        let source = app.buttons.matching(identifier: "reader.volume.3").firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: timeout))
        XCTAssertTrue(source.label.contains("\(3.formatted(.number.locale(Locale(identifier: "ar")))). Prayer"))
        let generic = app.buttons.matching(identifier: "reader.volume.7").firstMatch
        XCTAssertTrue(generic.exists)
        XCTAssertFalse(generic.label.contains(". "), "The localized generic title already includes its source number")
    }

    // MARK: - Live: real reader against development Convex

    func testConvexCostColdLaunchLibraryAndTenPageMoves() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed", "YES", "-reader.automaticTranslation", "NO", "-AppleLanguages", "(en)"]
        let started = Date()
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.tabBars.buttons["Library"].waitForExistence(timeout: 30))
        app.tabBars.buttons["Library"].tap()
        let collection = app.buttons["library.collection.bukhari"]
        XCTAssertTrue(collection.waitForExistence(timeout: 30))
        collection.tap()
        XCTAssertTrue(element("reader.page", in: app).waitForExistence(timeout: 30))
        func showProgress() {
            let progress = element("reader.unfocusedProgress", in: app)
            if !progress.waitForExistence(timeout: 1) {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            XCTAssertTrue(progress.waitForExistence(timeout: 10))
        }
        for step in 1...10 {
            showProgress()
            let progress = element("reader.unfocusedProgress", in: app)
            XCTAssertTrue(progress.waitForExistence(timeout: 10))
            let page = app.buttons["reader.jump.openPage"]
            let previousLabel = page.label
            app.swipeLeft()
            XCTAssertTrue(progress.waitForNonExistence(timeout: 10))
            showProgress()
            let changed = NSPredicate { _, _ in page.exists && page.label != previousLabel }
            expectation(for: changed, evaluatedWith: nil)
            waitForExpectations(timeout: 30)
            print("COST_JOURNEY_STEP \(step)")
        }
        let formatter = ISO8601DateFormatter()
        let record: [String: Any] = ["platform": "ios", "startedAtUtc": formatter.string(from: started),
            "endedAtUtc": formatter.string(from: Date()), "pageMoves": 10, "locale": "en",
            "auth": "fresh simulator guest", "automaticGeneration": false]
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        print("COST_JOURNEY_JSON " + String(decoding: data, as: UTF8.self))
    }

    func testConvexCostContentsJumpWithGenerationOff() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed", "YES", "-reader.automaticTranslation", "NO", "-AppleLanguages", "(en)"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.tabBars.buttons["Library"].waitForExistence(timeout: 30))
        app.tabBars.buttons["Library"].tap()
        let collection = app.buttons["library.collection.bukhari"]
        XCTAssertTrue(collection.waitForExistence(timeout: 30))
        collection.tap()
        XCTAssertTrue(element("reader.page", in: app).waitForExistence(timeout: 30))
        revealChrome(app)
        app.buttons["reader.menu"].tap()
        let contents = app.buttons["reader.menu.contents"]
        XCTAssertTrue(contents.waitForExistence(timeout: 10))
        contents.tap()
        let jump = field("reader.contents.jump", in: app)
        XCTAssertTrue(jump.waitForExistence(timeout: 10))
        XCTAssertTrue(element("reader.volume.1", in: app).waitForExistence(timeout: 10))
        jump.tap()
        jump.typeText("57")
        tapSettledGo(in: app)
        XCTAssertTrue(jump.waitForNonExistence(timeout: 10))
        let target = app.buttons.matching(identifier: "reader.hadithLabel")
            .matching(NSPredicate(format: "label CONTAINS '57'")).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 30), "Live contents jump did not reach Hadith 57")
    }

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
        app.buttons["reader.menu"].tap()
        let contentsCard = app.buttons["reader.menu.contents"]
        XCTAssertTrue(contentsCard.waitForExistence(timeout: timeout), "reader menu never opened")
        contentsCard.tap()
        let jump = field("reader.contents.jump", in: app)
        XCTAssertTrue(jump.waitForExistence(timeout: timeout), "Contents sheet never opened")
        // Pre-R5 cached outline: volumes render exactly as before.
        XCTAssertTrue(element("reader.volume.1", in: app).waitForExistence(timeout: timeout))
        jump.tap()
        jump.typeText("57")
        element("reader.contents.jumpGo", in: app).tap()

        // The jump lands through the same path as canonical links: the
        // target hadith's top header (`[Bukhari – 57]`, VoiceOver label
        // "Bukhari – 57, Sahih") is on screen.
        let headers = app.buttons.matching(identifier: "reader.hadithLabel")
        let target = headers.matching(NSPredicate(format: "label CONTAINS '57'")).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 30), "Jump to Hadith 57 never landed")

        // Slice A: the ellipsis is gone with no visual replacement. Every
        // block carries one top header with its grade dot and label; the
        // bottom compact label and the dim bare-number marker are gone.
        XCTAssertFalse(app.buttons["reader.moreActions"].exists, "ellipsis must be deleted")
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "reader.hadithMarker").firstMatch.exists,
            "bare-number marker must be deleted"
        )
        XCTAssertTrue(
            app.buttons["reader.hadithLabel"].firstMatch.waitForExistence(timeout: timeout),
            "top hadith header never rendered"
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
        app.launchEnvironment["HADITHLY_UI_TESTING"] = "1"
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
