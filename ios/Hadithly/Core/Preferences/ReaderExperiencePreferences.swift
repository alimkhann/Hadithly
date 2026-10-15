import Foundation
import Observation

@MainActor
@Observable
final class ReaderExperiencePreferences {
    private let defaults: UserDefaults
    var automaticallyTranslates: Bool {
        didSet { defaults.set(automaticallyTranslates, forKey: "reader.automaticTranslation") }
    }
    private(set) var showsActionHint = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        automaticallyTranslates = defaults.object(forKey: "reader.automaticTranslation") as? Bool ?? true
    }

    func offerActionHint() {
        guard !defaults.bool(forKey: "reader.actionsHintSeen") else { return }
        defaults.set(true, forKey: "reader.actionsHintSeen")
        showsActionHint = true
    }

    func dismissActionHint() { showsActionHint = false }
#if DEBUG
    func resetHintForUITest() {
        defaults.removeObject(forKey: "reader.actionsHintSeen")
        showsActionHint = false
    }
#endif
}

struct ReaderAutomaticTranslationLedger {
    private struct Request: Hashable { let hadithId: String; let locale: String }
    private var attempted: Set<Request> = []

    mutating func claim(hadithId: String, locale: String, hasTranslation: Bool, hasRequestState: Bool) -> Bool {
        guard !hasTranslation, !hasRequestState else { return false }
        return attempted.insert(Request(hadithId: hadithId, locale: locale)).inserted
    }
}
