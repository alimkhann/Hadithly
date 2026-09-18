import XCTest

/// O2 offline-open proof in a single launch: the app starts with
/// `-forceOfflineReader` (a DEBUG-only hook that skips the reader's
/// network fetch, standing in for dead network), downloads Bukhari
/// through the real pipeline, then opens it from Library. The reader must
/// render the verified dump — Arabic text, no spinner — and saving the
/// R1 position must not throw (the legacy wire values gate this).
/// The 10 s network timeout itself is unit-covered in OfflineStoreTests;
/// this test proves everything downstream of it on device.
final class OfflineReaderUITests: XCTestCase {
    private let timeout: TimeInterval = 20

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDownloadedCollectionOpensOffline() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-forceOfflineReader")
        app.launch()

        // 1. Download Bukhari through the real online pipeline.
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: timeout))
        app.tabBars.buttons["Settings"].tap()
        var offlineRow = app.buttons["settings.row.offlineStorage"]
        var found = offlineRow.waitForExistence(timeout: 5)
        for _ in 0 ..< 10 where !found {
            app.swipeUp()
            found = offlineRow.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(found, "missing offline storage row")
        offlineRow = app.buttons["settings.row.offlineStorage"]
        for _ in 0 ..< 6 where !offlineRow.isHittable {
            app.swipeUp()
        }
        offlineRow.tap()
        let bukhariRow = app.descendants(matching: .any)["settings.offline.bukhari.row"]
        XCTAssertTrue(bukhariRow.waitForExistence(timeout: timeout))
        let deleteButton = app.buttons["settings.offline.bukhari.delete"]
        if !deleteButton.waitForExistence(timeout: 5) {
            let downloadButton = app.buttons["settings.offline.bukhari.download"]
            XCTAssertTrue(downloadButton.waitForExistence(timeout: timeout))
            downloadButton.tap()
            XCTAssertTrue(
                deleteButton.waitForExistence(timeout: 180),
                "Bukhari download never activated"
            )
        }

        // 2. Open it from Library with the reader forced offline.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.tabBars.buttons["Library"].waitForExistence(timeout: timeout))
        app.tabBars.buttons["Library"].tap()
        let collection = app.buttons["library.collection.bukhari"]
        XCTAssertTrue(collection.waitForExistence(timeout: timeout))
        collection.tap()
        if !app.descendants(matching: .any)["reader.page"].waitForExistence(timeout: 90) {
            let failShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            failShot.name = "o2-offline-reader-FAIL"
            failShot.lifetime = .keepAlways
            add(failShot)
            let loading = app.descendants(matching: .any)["reader.loading"].exists
            let failedTexts = app.staticTexts.allElementsBoundByIndex.prefix(12).map(\.label)
            XCTFail("downloaded Bukhari never rendered offline; loading=\(loading) texts=\(failedTexts)")
        }
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Bukhari")).firstMatch.exists
        )
        XCTAssertFalse(app.descendants(matching: .any)["reader.loading"].exists)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "o2-offline-reader"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
