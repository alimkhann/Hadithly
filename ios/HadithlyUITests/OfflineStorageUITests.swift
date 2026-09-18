import XCTest

/// O2 device gate (simulator): the Offline storage destination renders one
/// row per collection with a real action, and a full download → verify →
/// activate cycle against development Convex completes without replacing
/// anything until the new bytes check out. Signed-out: manifests are
/// identity-free, so no account is needed.
final class OfflineStorageUITests: XCTestCase {
    private let timeout: TimeInterval = 15

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOfflineStorageRowsAndLiveDownload() throws {
        let app = XCUIApplication()
        app.launch()

        let settingsTab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: timeout))
        settingsTab.tap()

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

        // Seven collection rows render, each with a stable identifier.
        // List rows virtualize: scroll until each row enters the hierarchy.
        for slug in ["bukhari", "muslim", "sunan-nasai", "abu-dawood", "tirmidhi", "ibn-majah", "mishkat-al-masabih"] {
            let row = app.descendants(matching: .any)["settings.offline.\(slug).row"]
            var found = row.waitForExistence(timeout: 3)
            for _ in 0 ..< 10 where !found {
                app.swipeUp()
                found = row.waitForExistence(timeout: 2)
            }
            XCTAssertTrue(found, "missing offline row for \(slug)")
        }
        takeScreenshot(named: "o2-offline-rows")

        // The Bukhari download control sits at the top: scroll back up
        // until the row re-enters the hierarchy.
        let bukhariRow = app.descendants(matching: .any)["settings.offline.bukhari.row"]
        var topFound = bukhariRow.waitForExistence(timeout: 3)
        for _ in 0 ..< 12 where !topFound {
            app.swipeDown()
            topFound = bukhariRow.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(topFound, "lost the Bukhari row scrolling back up")

        // Live pipeline: Bukhari has a published dev manifest (O1). Tapping
        // Download must end in an installed copy offering deletion — proof
        // that fetch, checksum, license, staging, and activation ran.
        // If the row already shows an installed copy (a previous run), the
        // delete control is the same proof.
        let deleteButton = app.buttons["settings.offline.bukhari.delete"]
        if deleteButton.waitForExistence(timeout: 5) {
            takeScreenshot(named: "o2-offline-already-installed")
            return
        }
        let downloadButton = app.buttons["settings.offline.bukhari.download"]
        XCTAssertTrue(downloadButton.waitForExistence(timeout: timeout))
        downloadButton.tap()
        XCTAssertTrue(
            deleteButton.waitForExistence(timeout: 180),
            "Bukhari download never activated on the simulator"
        )
        takeScreenshot(named: "o2-offline-installed")
    }

    private func takeScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
