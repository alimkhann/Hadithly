import XCTest
@testable import Hadithly

@MainActor
final class SavedSafetyPreferencesTests: XCTestCase {
    func testConfirmationDefaultsOnAndCanBeReenabled() {
        let suite = "SavedSafetyPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = SavedSafetyPreferences(defaults: defaults)
        XCTAssertTrue(preferences.confirmsRemoval)
        preferences.confirmsRemoval = false
        XCTAssertFalse(SavedSafetyPreferences(defaults: defaults).confirmsRemoval)
        preferences.confirmsRemoval = true
        XCTAssertTrue(SavedSafetyPreferences(defaults: defaults).confirmsRemoval)
    }
}
