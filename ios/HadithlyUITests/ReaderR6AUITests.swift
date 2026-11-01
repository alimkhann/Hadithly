import XCTest
import os

/// Slice A (R6) gate plus round-2 corrections, offline: the Sajda-quiet
/// page renders from the deterministic `-R6AReaderFixture` with no
/// network across three volumes (Volume 1: one page; Volume 2: two pages;
/// Volume 3: one page). Proves the quiet page (no dividers, no ellipsis),
/// the top header (dot + bracketed label + saved-state markers), the
/// source sheet contents, chapter/volume headers, the TWO bottom pills
/// (neighbor pages mid-volume, full neighbor-volume titles at the edges,
/// nothing at the absolute ends), tap and swipe across volume boundaries
/// both ways, the cross-volume loading state, and the narrator in all
/// three visibility modes. The physical performance method separately requires
/// an explicit test-host opt-in and never launches a fixture or resets app data.
final class ReaderR6AUITests: XCTestCase {
    private let timeout: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPhysicalLoadedReaderScrollingPerformance() throws {
        guard ProcessInfo.processInfo.environment["HADITHLY_PHYSICAL_SCROLL"] == "1" else {
            throw XCTSkip("Requires explicit physical scrolling opt-in and an already-running reader")
        }
        guard #available(iOS 26, *) else { throw XCTSkip("Physical hitch metrics require iOS 26") }
        let app = XCUIApplication()
        XCTAssertNotEqual(app.state, .notRunning)
        guard app.state != .notRunning else { return }
        app.activate()
        XCTAssertTrue(app.descendants(matching: .any)["reader.page"].firstMatch.waitForExistence(timeout: 10))
        let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
        let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let velocity: XCUIGestureVelocity = ProcessInfo.processInfo.environment["HADITHLY_SCROLL_GESTURE"] == "fast" ? .fast : .slow
        let seconds = Double(ProcessInfo.processInfo.environment["HADITHLY_SCROLL_SECONDS"] ?? "0") ?? 0
        XCTAssertTrue(seconds == 0 || (30...60).contains(seconds))
        let metadata = app.staticTexts["reader.profile.metadata"]
        var motionAnchor: XCUIElement?
        var initialMetadata = ""
        if seconds > 0 {
            XCTAssertTrue(metadata.waitForExistence(timeout: 10), "Long-form measurements require pinned profile metadata")
            let data = try XCTUnwrap(metadata.label.data(using: .utf8))
            var workload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(workload["automaticGenerationEnabled"] as? Bool, false, "Performance runs require automatic generation off")
            workload["thermalState"] = ProcessInfo.processInfo.thermalState.rawValue
            workload["lowPowerMode"] = ProcessInfo.processInfo.isLowPowerModeEnabled
            if var preferences = workload["preferences"] as? [String: Any] {
                preferences.removeValue(forKey: "updatedAt")
                workload["preferences"] = preferences
            }
            let pinned = try JSONSerialization.data(withJSONObject: workload, options: [.sortedKeys])
            print("READER_WORKLOAD_METADATA=\(String(decoding: pinned, as: UTF8.self))")
            let attachment = XCTAttachment(data: pinned, uniformTypeIdentifier: "public.json")
            attachment.name = "reader-workload-metadata"; attachment.lifetime = .keepAlways; add(attachment)
            let candidates = app.staticTexts.matching(identifier: "reader.arabic").allElementsBoundByIndex
                + app.buttons.matching(identifier: "reader.hadithLabel").allElementsBoundByIndex
            let anchor = try XCTUnwrap(candidates.first { $0.frame.intersects(app.frame.insetBy(dx: 0, dy: 100)) })
            motionAnchor = anchor
            initialMetadata = metadata.label
            let before = anchor.frame.minY
            lower.press(forDuration: 0.02, thenDragTo: upper, withVelocity: .slow, thenHoldForDuration: 0)
            let movement = abs(anchor.frame.minY - before)
            XCTAssertGreaterThan(movement, 20, "The workload must move reader content")
            upper.press(forDuration: 0.02, thenDragTo: lower, withVelocity: .slow, thenHoldForDuration: 0)
            print("READER_SCROLL_MOVEMENT_POINTS=\(movement)")
        }
        if ProcessInfo.processInfo.environment["HADITHLY_SCROLL_TRACE"] == "1" {
            XCTAssertEqual(seconds, 30)
            let repetitions = Int(ProcessInfo.processInfo.environment["HADITHLY_SCROLL_REPETITIONS"] ?? "3") ?? 0
            XCTAssertTrue(repetitions == 1 || repetitions == 3)
            guard repetitions == 1 || repetitions == 3 else { return }
            let log = OSLog(subsystem: "com.hadithly.reader.driver", category: .pointsOfInterest)
            let thermalState = ProcessInfo.processInfo.thermalState
            for iteration in 0..<repetitions {
                XCTAssertFalse(ProcessInfo.processInfo.isLowPowerModeEnabled)
                XCTAssertEqual(ProcessInfo.processInfo.thermalState, thermalState)
                let id = OSSignpostID(log: log)
                os_signpost(.begin, log: log, name: "ReaderMeasuredRun", signpostID: id, "iteration=%d", iteration)
                let started = ProcessInfo.processInfo.systemUptime
                var verifiedMovement = false
                repeat {
                    let before = verifiedMovement ? 0 : motionAnchor?.frame.minY ?? 0
                    lower.press(forDuration: 0.02, thenDragTo: upper, withVelocity: velocity, thenHoldForDuration: 0)
                    let afterUp = verifiedMovement ? 0 : motionAnchor?.frame.minY ?? 0
                    upper.press(forDuration: 0.02, thenDragTo: lower, withVelocity: velocity, thenHoldForDuration: 0)
                    if !verifiedMovement {
                        let afterDown = motionAnchor?.frame.minY ?? 0
                        XCTAssertGreaterThan(max(abs(afterUp - before), abs(afterDown - afterUp)), 20)
                        verifiedMovement = true
                    }
                } while ProcessInfo.processInfo.systemUptime - started < seconds
                os_signpost(.end, log: log, name: "ReaderMeasuredRun", signpostID: id)
                XCTAssertFalse(ProcessInfo.processInfo.isLowPowerModeEnabled)
                XCTAssertEqual(ProcessInfo.processInfo.thermalState, thermalState)
                XCTAssertEqual(metadata.label, initialMetadata, "The page content or display settings changed during the run")
                print("READER_TRACE_ITERATION=\(iteration) THERMAL=\(thermalState.rawValue)")
            }
            return
        }
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        let thermalState = ProcessInfo.processInfo.thermalState
        measure(metrics: [XCTHitchMetric(application: app), XCTCPUMetric(application: app), XCTMemoryMetric(application: app), XCTClockMetric(),
                          XCTOSSignpostMetric.scrollingAndDecelerationMetric,
                          XCTOSSignpostMetric(subsystem: "com.hadithly.app.reader", category: "PointsOfInterest", name: "ReaderActiveScroll")], options: options) {
            if seconds > 0 {
                XCTAssertFalse(ProcessInfo.processInfo.isLowPowerModeEnabled)
                XCTAssertEqual(ProcessInfo.processInfo.thermalState, thermalState, "Thermal conditions changed within the workload")
                print("READER_SCROLL_THERMAL_STATE=\(thermalState.rawValue)")
            }
            startMeasuring()
            let started = ProcessInfo.processInfo.systemUptime
            var pairs = 0
            repeat {
                lower.press(forDuration: 0.02, thenDragTo: upper, withVelocity: velocity, thenHoldForDuration: 0)
                upper.press(forDuration: 0.02, thenDragTo: lower, withVelocity: velocity, thenHoldForDuration: 0)
                pairs += 1
            } while seconds > 0 ? ProcessInfo.processInfo.systemUptime - started < seconds : pairs < 3
            stopMeasuring()
        }
    }

    // MARK: - Quiet page

    func testLoadedReaderScrollsBehindFloatingControls() {
        let app = scrollingApplication()
        app.launch()
        defer { app.terminate() }
        let viewport = app.descendants(matching: .any)["reader.page"].firstMatch
        let pills = app.descendants(matching: .any)["reader.unfocusedProgress"].firstMatch
        XCTAssertTrue(viewport.waitForExistence(timeout: 10))
        XCTAssertTrue(pills.waitForExistence(timeout: 10))
        XCTAssertLessThan(viewport.frame.minY, pills.frame.minY, "The scrolling viewport must extend behind the floating controls")
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "reader-full-bleed-initial"; before.lifetime = .keepAlways; add(before)
        app.swipeUp()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        XCTAssertTrue(pills.waitForExistence(timeout: 5))
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "reader-full-bleed-scrolled-controls"; after.lifetime = .keepAlways; add(after)
        XCTAssertLessThanOrEqual(viewport.frame.minY, 1, "Text must be able to scroll into the top safe area")
    }

    func testLoadedReaderSemanticReanchorPreservesScrolledPosition() {
        let app = scrollingApplication()
        app.launchEnvironment["READER_SCROLL_REANCHOR"] = "1"
        app.launch()
        defer { app.terminate() }
        let probe = app.staticTexts["reader.performance.root"]
        XCTAssertTrue(probe.waitForExistence(timeout: 10))
        app.swipeUp()
        app.swipeUp()
        let before = Double(probe.label.split(separator: ":").last ?? "0") ?? 0
        XCTAssertGreaterThan(before, 0.1)
        app.buttons["reader.test.reanchor"].tap()
        Thread.sleep(forTimeInterval: 1)
        let after = Double(probe.label.split(separator: ":").last ?? "0") ?? 0
        XCTAssertEqual(after, before, accuracy: 0.01, "Semantic restoration must use the same reading-area coordinates as scroll capture")
    }

    private func scrollingApplication() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-R6AReaderFixture", "-FreshInstallForUITest", "-AppleLanguages", "(en)", "-AppleInterfaceStyle", "Dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "PAGING_RENDER": "interactive", "READER_PERFORMANCE_PROBE": "1", "Q1_UI_LOCALE": "en"]
        return app
    }

    func testQuietPageHasHeadersMarkersAndNoEllipsis() {
        let app = launchFixture()
        XCTAssertTrue(element("reader.volumeHeader", in: app).waitForExistence(timeout: timeout))
        // Two hadith blocks on Volume 2 page 1, each with one tappable top header.
        XCTAssertGreaterThanOrEqual(app.buttons.matching(identifier: "reader.hadithLabel").count, 2)
        // The bottom compact label and the dim bare-number marker are gone:
        // both were replaced by the header.
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "reader.hadithMarker").firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "reader.gradeDot").firstMatch.exists)
        // The R5 ellipsis is gone with no visual replacement.
        XCTAssertFalse(app.buttons["reader.moreActions"].exists)
        // The header opens the source sheet (Hadith 57 carries a URL).
        app.buttons.matching(identifier: "reader.hadithLabel").firstMatch.tap()
        XCTAssertTrue(element("reader.sourceSheet", in: app).waitForExistence(timeout: timeout))
        app.buttons["Done"].tap()
        // Two bottom pills replace the old centered cluster, and the corner
        // yields to the volume header on page 1.
        XCTAssertTrue(element("reader.pagePills", in: app).exists)
        XCTAssertFalse(element("reader.pageCluster", in: app).exists, "the single centered cluster is gone")
        XCTAssertFalse(element("reader.volumeCorner", in: app).exists, "corner yields to the volume header on page 1")
    }

    func testSavedStateMiniMarkers() {
        let app = launchFixture()
        XCTAssertTrue(element("reader.volumeHeader", in: app).waitForExistence(timeout: timeout))
        // Hadith 57 is bookmarked: the amber mini marker renders inline
        // after its header. Hadith 58 is neither: no heart on page 1.
        XCTAssertTrue(element("reader.savedBookmark", in: app).exists)
        XCTAssertFalse(element("reader.savedFavorite", in: app).exists)
        // Hadith 59 is favorited: turning to page 2 shows the pink heart
        // and no bookmark.
        app.buttons["reader.nextPage"].tap()
        XCTAssertTrue(element("reader.savedFavorite", in: app).waitForExistence(timeout: timeout))
        XCTAssertFalse(element("reader.savedBookmark", in: app).exists)
    }

    func testChapterLineIsNameOnlyWithArabicSubtitle() {
        let app = launchFixture()
        let chapter = element("reader.chapterHeader", in: app)
        XCTAssertTrue(chapter.waitForExistence(timeout: timeout))
        XCTAssertEqual(chapter.label, "Belief, كتاب الإيمان")
        XCTAssertFalse(chapter.label.contains("Chapter"))
    }

    // MARK: - Narrator in all three modes

    func testNarratorShowsWithTranslationLayer() {
        let app = launchFixture()
        let narrator = element("reader.narrator", in: app)
        XCTAssertTrue(narrator.waitForExistence(timeout: timeout))
        XCTAssertTrue(narrator.label.contains("Umar"))
        // Hadith 58 has no narrator: exactly one narrator line on the page.
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "reader.narrator").count, 1)
        // Mixed mode keeps the leading-edge line below the Arabic block.
        let arabic = app.descendants(matching: .any).matching(identifier: "reader.arabic").firstMatch
        XCTAssertTrue(arabic.waitForExistence(timeout: timeout))
        XCTAssertGreaterThanOrEqual(narrator.frame.minY, arabic.frame.maxY - 2)
    }

    func testNarratorShowsAboveArabicInArabicOnlyMode() {
        let app = launchFixture(environment: ["R6A_TRANSLATION_VISIBLE": "false"])
        XCTAssertTrue(element("r6a.page", in: app).waitForExistence(timeout: timeout))
        // Arabic-only mode shows the provider Arabic narrator line, never
        // the English narrator: it hides when narratorAr is absent.
        let narrator = element("reader.narrator", in: app)
        XCTAssertTrue(narrator.waitForExistence(timeout: timeout), "narrator shows in Arabic-only mode")
        XCTAssertTrue(narrator.label.contains("عمر"))
        XCTAssertFalse(narrator.label.contains("Umar"))
        let arabic = app.descendants(matching: .any).matching(identifier: "reader.arabic").firstMatch
        XCTAssertTrue(arabic.waitForExistence(timeout: timeout))
        XCTAssertLessThanOrEqual(narrator.frame.maxY, arabic.frame.minY + 2)
        XCTAssertFalse(element("reader.translation", in: app).exists)
    }

    func testNarratorShowsInTranslationOnlyMode() {
        let app = launchFixture(environment: ["R6A_ARABIC_VISIBLE": "false"])
        XCTAssertTrue(element("r6a.page", in: app).waitForExistence(timeout: timeout))
        let narrator = element("reader.narrator", in: app)
        XCTAssertTrue(narrator.waitForExistence(timeout: timeout), "narrator shows in translation-only mode")
        XCTAssertTrue(narrator.label.contains("Umar"))
        XCTAssertFalse(element("reader.arabic", in: app).exists)
    }

    // MARK: - Source sheet

    func testSourceSheetShowsNameScopeAndURL() {
        let app = launchFixture()
        app.buttons.matching(identifier: "reader.hadithLabel").firstMatch.tap()
        XCTAssertTrue(element("reader.sourceSheet", in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(app.staticTexts["Sunnah.now"].exists)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Sahih collection scope'")).firstMatch.exists
        )
        XCTAssertTrue(element("reader.sourceSheet.url", in: app).exists)
        app.buttons["Done"].tap()
        XCTAssertFalse(element("reader.sourceSheet", in: app).waitForExistence(timeout: 3))
    }

    func testSourceSheetOmitsURLWhenAbsent() {
        let app = launchFixture()
        // Second block (Hadith 58) carries an empty source URL.
        app.buttons.matching(identifier: "reader.hadithLabel").element(boundBy: 1).tap()
        XCTAssertTrue(element("reader.sourceSheet", in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(app.staticTexts["Sunnah.now"].exists)
        XCTAssertFalse(element("reader.sourceSheet.url", in: app).exists)
        app.buttons["Done"].tap()
    }

    // MARK: - Two bottom pills

    func testTwoPillsAtVolumeEdgeNameNeighborVolume() {
        // Volume 2 page 1: LEFT is the previous volume in full, RIGHT is
        // the neighbor page number.
        let app = launchFixture()
        XCTAssertTrue(element("reader.pagePills", in: app).waitForExistence(timeout: timeout))
        let previous = app.buttons["reader.previousPage"].firstMatch
        let next = app.buttons["reader.nextPage"].firstMatch
        XCTAssertEqual(previous.label, "Previous page, Volume 1")
        XCTAssertEqual(next.label, "Next page, Page 2")
        // LTR order: previous on the left, next on the right.
        XCTAssertLessThan(previous.frame.minX, next.frame.minX)
        // 44pt targets on both pills.
        XCTAssertGreaterThanOrEqual(previous.frame.height, 44)
        XCTAssertGreaterThanOrEqual(next.frame.height, 44)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "native-page-controls"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Volume 2 page 2: LEFT is the neighbor page, RIGHT names Volume 3.
        next.tap()
        XCTAssertEqual(app.buttons["reader.previousPage"].firstMatch.label, "Previous page, Page 1")
        XCTAssertEqual(app.buttons["reader.nextPage"].firstMatch.label, "Next page, Volume 3")
        let corner = element("reader.volumeCorner", in: app)
        XCTAssertTrue(corner.waitForExistence(timeout: timeout))
        XCTAssertEqual(corner.label, "Volume 2: 57–59")
    }

    func testAbsoluteEndsHaveNoOutwardPill() {
        // First page of the first volume: no previous pill.
        let app = launchFixture(environment: ["R6A_START_VOLUME": "1"])
        XCTAssertTrue(element("reader.volumeHeader", in: app).waitForExistence(timeout: timeout))
        XCTAssertEqual(element("reader.volumeHeader", in: app).label, "Volume 1, 1 hadith")
        XCTAssertFalse(app.buttons["reader.previousPage"].exists)
        XCTAssertEqual(app.buttons["reader.nextPage"].firstMatch.label, "Next page, Volume 2")

        // Last page of the last volume: no next pill.
        app.terminate()
        let last = launchFixture(environment: ["R6A_START_VOLUME": "3"])
        XCTAssertTrue(element("reader.volumeHeader", in: last).waitForExistence(timeout: timeout))
        XCTAssertEqual(element("reader.volumeHeader", in: last).label, "Volume 3, 1 hadith")
        XCTAssertFalse(last.buttons["reader.nextPage"].exists)
        XCTAssertEqual(last.buttons["reader.previousPage"].firstMatch.label, "Previous page, Volume 2")
    }

    func testRTLPillsMirrorWithLogicalLabels() {
        let app = launchFixture(environment: ["R6A_PAGE_DIRECTION": "rtl"])
        XCTAssertTrue(element("reader.pagePills", in: app).waitForExistence(timeout: timeout))
        let previous = app.buttons["reader.previousPage"].firstMatch
        let next = app.buttons["reader.nextPage"].firstMatch
        // Labels stay logical; the previous pill sits on the right.
        XCTAssertEqual(previous.label, "Previous page, Volume 1")
        XCTAssertEqual(next.label, "Next page, Page 2")
        XCTAssertGreaterThan(previous.frame.minX, next.frame.minX)
    }

    func testCornerLabelStaysTitleOnlyUntilFullyCached() {
        let app = launchFixture(environment: ["R6A_FULL_CACHE": "false"])
        XCTAssertTrue(element("reader.pagePills", in: app).waitForExistence(timeout: timeout))
        app.buttons["reader.nextPage"].tap()
        let corner = element("reader.volumeCorner", in: app)
        XCTAssertTrue(corner.waitForExistence(timeout: timeout))
        XCTAssertEqual(corner.label, "Volume 2")
    }

    // MARK: - Crossing volume boundaries

    func testTapAcrossBoundaryForwardLandsOnNextVolumeFirstPage() {
        let app = launchFixture(environment: ["R6A_INITIAL_PAGE": "1"])
        XCTAssertTrue(element("reader.pagePills", in: app).waitForExistence(timeout: timeout))
        XCTAssertEqual(app.buttons["reader.nextPage"].firstMatch.label, "Next page, Volume 3")
        app.buttons["reader.nextPage"].tap()
        let header = element("reader.volumeHeader", in: app)
        XCTAssertTrue(header.waitForExistence(timeout: timeout))
        XCTAssertEqual(header.label, "Volume 3, 1 hadith")
        // Absolute end: no next pill; back names Volume 2 in full.
        XCTAssertFalse(app.buttons["reader.nextPage"].exists)
        XCTAssertEqual(app.buttons["reader.previousPage"].firstMatch.label, "Previous page, Volume 2")
    }

    func testFreshVolumePageShowsItsHeaderAboveTheFirstHadith() {
        let app = launchFixture(environment: ["R6A_INITIAL_PAGE": "1"])
        app.buttons["reader.nextPage"].tap()
        let header = element("reader.volumeHeader", in: app)
        XCTAssertTrue(header.waitForExistence(timeout: timeout))
        XCTAssertTrue(header.isHittable)
    }

    func testP1VerticalLandingMatrix() {
        // A fresh Library-style open begins at the first volume header.
        let app = launchFixture()
        XCTAssertTrue(element("reader.volumeHeader", in: app).waitForExistence(timeout: timeout))

        // Turn onto the next page, scroll its content, then revisit it. The
        // manual revisit must expose the page corner again, never its old
        // vertical offset.
        app.buttons["reader.nextPage"].tap()
        let corner = element("reader.volumeCorner", in: app)
        XCTAssertTrue(corner.waitForExistence(timeout: timeout))
        app.swipeUp()
        app.buttons["reader.previousPage"].tap()
        XCTAssertTrue(element("reader.volumeHeader", in: app).waitForExistence(timeout: timeout))
        app.buttons["reader.nextPage"].tap()
        XCTAssertTrue(corner.waitForExistence(timeout: timeout))

        // The outward turn crosses into an initially unvisited volume and
        // must land at its source-provided volume header once it loads.
        app.buttons["reader.nextPage"].tap()
        let volume3 = element("reader.volumeHeader", in: app)
        XCTAssertTrue(volume3.waitForExistence(timeout: timeout))
        XCTAssertTrue(volume3.isHittable)

        // The fixture's explicit page target is the semantic-continuation
        // analogue: it remains on Hadith 59 rather than being reset to top.
        app.terminate()
        let continuation = launchFixture(environment: ["R6A_INITIAL_PAGE": "1"])
        XCTAssertTrue(continuation.buttons.matching(identifier: "reader.hadithLabel").firstMatch.waitForExistence(timeout: timeout))
        XCTAssertTrue(element("reader.volumeCorner", in: continuation).isHittable)
    }

    func testTapAcrossBoundaryBackwardLandsOnPreviousVolumeLastPage() {
        let app = launchFixture()
        XCTAssertTrue(element("reader.pagePills", in: app).waitForExistence(timeout: timeout))
        app.buttons["reader.previousPage"].tap()
        let header = element("reader.volumeHeader", in: app)
        XCTAssertTrue(header.waitForExistence(timeout: timeout))
        XCTAssertEqual(header.label, "Volume 1, 1 hadith")
        XCTAssertFalse(app.buttons["reader.previousPage"].exists)
        // The visited volume opens instantly on the way back: no loading.
        app.buttons["reader.nextPage"].tap()
        let back = element("reader.volumeHeader", in: app)
        XCTAssertTrue(back.waitForExistence(timeout: timeout))
        XCTAssertEqual(back.label, "Belief, 3 hadiths")
        XCTAssertEqual(app.buttons["reader.previousPage"].firstMatch.label, "Previous page, Volume 1")
    }

    func testSwipeAcrossVolumesBothWays() {
        let app = launchFixture(environment: ["R6A_INITIAL_PAGE": "1"])
        XCTAssertTrue(element("reader.pagePills", in: app).waitForExistence(timeout: timeout))
        // Outward swipe past the last page advances to Volume 3's first page.
        app.swipeLeft()
        let volume3 = element("reader.volumeHeader", in: app)
        XCTAssertTrue(volume3.waitForExistence(timeout: timeout))
        XCTAssertEqual(volume3.label, "Volume 3, 1 hadith")
        // Back across the boundary lands on Volume 2's last page.
        app.swipeRight()
        let corner = element("reader.volumeCorner", in: app)
        XCTAssertTrue(corner.waitForExistence(timeout: timeout))
        XCTAssertEqual(corner.label, "Volume 2: 57–59")
        // In-volume swipe still turns the page.
        app.swipeRight()
        let volume2 = element("reader.volumeHeader", in: app)
        XCTAssertTrue(volume2.waitForExistence(timeout: timeout))
        XCTAssertEqual(volume2.label, "Belief, 3 hadiths")
        // And back across to the previous volume's last (= only) page.
        app.swipeRight()
        let volume1 = element("reader.volumeHeader", in: app)
        XCTAssertTrue(volume1.waitForExistence(timeout: timeout))
        XCTAssertEqual(volume1.label, "Volume 1, 1 hadith")
    }

    func testLoadingStateOnFirstVolumeVisit() {
        let app = launchFixture(environment: ["R6A_LOADING_FIXTURE": "true"])
        XCTAssertTrue(
            element("reader.pageLoading", in: app).waitForExistence(timeout: timeout),
            "a loading reader renders the shared article loading presentation"
        )
        XCTAssertFalse(app.buttons["reader.hadithLabel"].exists)
    }

    // MARK: - Long-press menu intact

    func testLongPressMenuStillOpensWithFullActions() {
        let app = launchFixture()
        let arabic = app.staticTexts["reader.arabic"].firstMatch
        XCTAssertTrue(arabic.waitForExistence(timeout: timeout))
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
        app.tap()
    }

    // MARK: - Round 3: drag lock and note marker

    func testHorizontalDragTurnsPage() {
        let app = launchFixture()
        XCTAssertTrue(element("reader.volumeHeader", in: app).waitForExistence(timeout: timeout))
        app.swipeLeft()
        let corner = element("reader.volumeCorner", in: app)
        XCTAssertTrue(corner.waitForExistence(timeout: timeout))
        XCTAssertEqual(corner.label, "Volume 2: 57–59")
    }

    func testVerticalDragNeverTurnsPage() {
        let app = launchFixture()
        XCTAssertTrue(element("reader.volumeHeader", in: app).waitForExistence(timeout: timeout))
        app.swipeUp()
        app.swipeUp()
        // Still on Volume 2 page 1: the header persists, no corner label.
        XCTAssertTrue(element("reader.volumeHeader", in: app).exists)
        XCTAssertFalse(element("reader.volumeCorner", in: app).exists)
    }

    func testShortHorizontalDragCancelsBack() {
        let app = launchFixture()
        XCTAssertTrue(element("reader.volumeHeader", in: app).waitForExistence(timeout: timeout))
        // A short slow drag stays under the turn threshold: the page
        // springs back instead of turning.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: end)
        XCTAssertTrue(element("reader.volumeHeader", in: app).exists)
        XCTAssertFalse(element("reader.volumeCorner", in: app).exists)
    }

    func testGreenNoteMarkerOnNotedHadith() {
        let app = launchFixture()
        XCTAssertTrue(element("reader.volumeHeader", in: app).waitForExistence(timeout: timeout))
        // Page 1 (hadiths 57/58): no note marker.
        XCTAssertFalse(element("reader.savedNote", in: app).exists)
        // Page 2 (hadith 59, seeded note): the green inline marker renders.
        app.buttons["reader.nextPage"].tap()
        XCTAssertTrue(element("reader.savedNote", in: app).waitForExistence(timeout: timeout))
    }

    // MARK: - Helpers

    private func launchFixture(environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-R6AReaderFixture"]
        app.launchEnvironment["HADITHLY_UI_TESTING"] = "1"
        app.launchEnvironment["Q1_UI_LOCALE"] = "en"
        for (key, value) in environment {
            app.launchEnvironment[key] = value
        }
        app.launch()
        XCTAssertTrue(element("r6a.page", in: app).waitForExistence(timeout: timeout))
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
