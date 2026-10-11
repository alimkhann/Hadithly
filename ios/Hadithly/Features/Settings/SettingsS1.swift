import Foundation

/// S1 Settings information architecture. Every row in the Settings root maps
/// to exactly one destination or one immediate action — no dead placeholders.
/// The enum drives both the UI and the navigation unit tests so a row without
/// a finished destination fails the gate instead of shipping silently.
enum SettingsDestination: String, CaseIterable, Identifiable {
    case profile
    case appearance
    case appLanguage
    case hadithTranslation
    case readingAndType
    case offlineStorage
    case notifications
    case subscription
    case privacyAndData
    case helpAndSupport
    case aboutAndLegal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile: "Profile"
        case .appearance: "Appearance"
        case .appLanguage: "App language"
        case .hadithTranslation: "Hadith translation"
        case .readingAndType: "Reading & type"
        case .offlineStorage: "Offline storage"
        case .notifications: "Notifications"
        case .subscription: "Subscription"
        case .privacyAndData: "Privacy & data"
        case .helpAndSupport: "Help & support"
        case .aboutAndLegal: "About & legal"
        }
    }

    var subtitle: String {
        switch self {
        case .profile: "Picture, name, username"
        case .appearance: "System, Light, Paper, Dark"
        case .appLanguage: "Interface language"
        case .hadithTranslation: "Translation language"
        case .readingAndType: "Direction, visibility, Arabic type"
        case .offlineStorage: "Collections, updates, usage"
        case .notifications: "Daily hadith reminder"
        case .subscription: "Free or Pro"
        case .privacyAndData: "Export, policies, deletion"
        case .helpAndSupport: "Contact, FAQ, share"
        case .aboutAndLegal: "Version, licenses, terms"
        }
    }

    var systemImage: String {
        switch self {
        case .profile: "person.crop.circle"
        case .appearance: "circle.lefthalf.filled"
        case .appLanguage: "globe"
        case .hadithTranslation: "book.closed"
        case .readingAndType: "textformat"
        case .offlineStorage: "arrow.down.circle"
        case .notifications: "bell"
        case .subscription: "star.circle"
        case .privacyAndData: "lock.shield"
        case .helpAndSupport: "questionmark.circle"
        case .aboutAndLegal: "info.circle"
        }
    }

    var accessibilityID: String { "settings.row.\(rawValue)" }
}

/// Canonical external destinations. The site pages are live on hadithly.app
/// (docs/PLAN.md); the client never invents a policy URL.
enum SettingsLinks {
    static let privacy = URL(string: "https://hadithly.app/privacy")!
    static let terms = URL(string: "https://hadithly.app/terms")!
    static let support = URL(string: "https://hadithly.app/support")!
    static let deleteAccountInfo = URL(string: "https://hadithly.app/delete-account")!
    static let appleSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")!
    static let supportEmail = "support@hadithly.app"

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

/// Deletion keeps its own subscription warning, separate from the generic
/// data-removal copy, so a Pro reader never deletes without knowing the
/// store subscription survives.
enum SettingsDeletionCopy {
    static let title = "Delete account permanently?"
    static let message =
        "This removes your synced bookmarks, favorites, notes, reading " +
        "progress, submissions, and sign-in. It cannot be undone."
    static let subscriptionWarning =
        "Your App Store subscription is separate: deleting your Hadithly " +
        "account does not cancel it. Manage or cancel it in your Apple " +
        "Account subscriptions first if you do not want to keep paying."
}

/// Portable-export helpers. The payload comes from the identity-scoped
/// `users:exportCurrentUserData` query — callers never add device tokens,
/// other users, or audit rows.
enum SettingsExport {
    static func fileName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en-US-POSIX")
        return "hadithly-export-\(formatter.string(from: date)).json"
    }

    /// Redaction check for tests: these key fragments must never appear in
    /// an export payload.
    static let forbiddenFragments = ["pushTokens", "adminAuditLog", "revenueCatAppUserId"]
}

/// Subscription display derived from the `users:getCurrentUser` row.
enum SettingsSubscription {
    static func displayName(tier: String?) -> String {
        switch tier {
        case "pro": "Hadithly Pro"
        case "trial": "Pro trial"
        default: "Free"
        }
    }


}
