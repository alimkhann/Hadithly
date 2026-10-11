import XCTest
@testable import Hadithly

/// S1 gate: every Settings row resolves to a finished destination, deletion
/// keeps its separate subscription warning, and export filenames stay stable.
final class SettingsS1Tests: XCTestCase {
    func testEveryDestinationHasTitleSubtitleIconAndAccessibilityID() {
        for destination in SettingsDestination.allCases {
            XCTAssertFalse(destination.title.isEmpty, destination.rawValue)
            XCTAssertFalse(destination.subtitle.isEmpty, destination.rawValue)
            XCTAssertFalse(destination.systemImage.isEmpty, destination.rawValue)
            XCTAssertEqual(destination.accessibilityID, "settings.row.\(destination.rawValue)")
        }
    }

    func testRequiredS1DestinationsExist() {
        let ids = Set(SettingsDestination.allCases.map(\.rawValue))
        for required in [
            "profile", "appearance", "appLanguage", "hadithTranslation",
            "offlineStorage", "notifications", "subscription",
            "privacyAndData", "helpAndSupport", "aboutAndLegal",
            "readingAndType",
        ] {
            XCTAssertTrue(ids.contains(required), "missing destination \(required)")
        }
    }

    func testDeletionKeepsSeparateSubscriptionWarning() {
        XCTAssertTrue(
            SettingsDeletionCopy.subscriptionWarning.localizedCaseInsensitiveContains("subscription")
        )
        XCTAssertTrue(
            SettingsDeletionCopy.message.localizedCaseInsensitiveContains("cannot be undone")
        )
        // The generic message must not absorb the store warning: they are
        // shown as two separate blocks in PrivacyDataView.
        XCTAssertFalse(SettingsDeletionCopy.message.contains("App Store"))
    }

    func testExportFileNameIsStableAndDated() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 17))!
        XCTAssertEqual(SettingsExport.fileName(date: date), "hadithly-export-2026-09-17.json")
    }

    func testExportForbiddenFragmentsCoverDeviceAndForeignData() {
        XCTAssertTrue(SettingsExport.forbiddenFragments.contains("pushTokens"))
        XCTAssertTrue(SettingsExport.forbiddenFragments.contains("adminAuditLog"))
    }

    func testExternalLinksStayOnHadithlyApp() {
        for url in [SettingsLinks.privacy, SettingsLinks.terms, SettingsLinks.support, SettingsLinks.deleteAccountInfo] {
            XCTAssertEqual(url.host, "hadithly.app")
            XCTAssertEqual(url.scheme, "https")
        }
    }

    func testSubscriptionDisplayNames() {
        XCTAssertEqual(SettingsSubscription.displayName(tier: "pro"), "Hadithly Pro")
        XCTAssertEqual(SettingsSubscription.displayName(tier: "trial"), "Pro trial")
        XCTAssertEqual(SettingsSubscription.displayName(tier: "free"), "Free")
        XCTAssertEqual(SettingsSubscription.displayName(tier: nil), "Free")
    }


}
