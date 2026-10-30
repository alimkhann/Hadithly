import XCTest
@testable import Hadithly

/// S1 gate: every Settings row resolves to a finished destination, deletion
/// keeps its separate subscription warning, and export filenames stay stable.
final class SettingsS1Tests: XCTestCase {
    func testOfflineNoticeBoundaryKeepsArgumentsAndBoundsDiagnostics() {
        let locale = Locale(identifier: "en")
        let opaque = "Original %lld %@ اسم"
        XCTAssertTrue(OfflineCopy.removed(opaque, locale: locale).contains(opaque))
        XCTAssertEqual(OfflineCopy.message("Not enough storage: need 12 MB, 8 MB free.", locale: locale), "Not enough storage: need 12 MB, 8 MB free.")
        XCTAssertEqual(OfflineCopy.message("The new file is missing 2 of your saved hadiths. Your copy stays active.", locale: locale), "The new file is missing 2 of your saved hadiths. Your copy stays active.")
        XCTAssertEqual(OfflineCopy.message("Could not check for updates (Private diagnostic %@). Your downloads keep working offline.", locale: locale), OfflineCopy.keys[13])
        for source in ["Private diagnostic %@", "Not enough storage: need private, name free.", "The new file is missing 99999999999999999999999 of your saved hadiths. Your copy stays active."] {
            XCTAssertEqual(OfflineCopy.message(source, locale: locale), "Download failed.")
        }
    }

    func testProfileUsernameFailuresUseCodesAndBoundUnknownDetails() {
        XCTAssertEqual(ProfileNotice.usernameFailure(code: "form_username_in_use"), .unavailable)
        XCTAssertEqual(ProfileNotice.usernameFailure(code: "form_identifier_exists"), .unavailable)
        for code in [nil, "unknown_provider_code", "Private diagnostic %@"] {
            XCTAssertEqual(ProfileNotice.usernameFailure(code: code), .retry)
        }
    }

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

    func testExportCleanupRemovesOnlyManagedTemporaryFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let managed = directory.appendingPathComponent("hadithly-export-2026-10-19.json")
        let unrelated = directory.appendingPathComponent("personal-notes.json")
        let almost = directory.appendingPathComponent("hadithly-export-2026-10-19.json.backup")
        for url in [managed, unrelated, almost] { try Data("Private fixture".utf8).write(to: url) }
        SettingsExport.clearTemporaryFiles(in: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: managed.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: almost.path))
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
