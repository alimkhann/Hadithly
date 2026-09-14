import Foundation
import Observation

@MainActor
@Observable
final class SavedSafetyPreferences {
    static let removalConfirmationKey = "saved.confirmRemoval"

    private let defaults: UserDefaults
    var confirmsRemoval: Bool {
        didSet { defaults.set(confirmsRemoval, forKey: Self.removalConfirmationKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        confirmsRemoval = defaults.object(forKey: Self.removalConfirmationKey) as? Bool ?? true
    }
}
