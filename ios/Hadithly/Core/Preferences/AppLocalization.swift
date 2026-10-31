import SwiftUI

enum AppLocalization {
    static func format(_ key: String, locale: Locale, _ arguments: CVarArg...) -> String {
        for code in LocaleFallback.fallbackChain(for: locale.identifier) {
            guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { continue }
            let template = bundle.localizedString(forKey: key, value: nil, table: nil)
            if template != key {
                return String(format: template, locale: locale, arguments: arguments)
            }
        }
        return String(format: key, locale: locale, arguments: arguments)
    }

    static func authenticity(scope: String, grade: String?, sourceName: String, locale: Locale) -> String {
        guard (scope == "hadith" || scope == "collection"), let grade else {
            return format("Authenticity not verified · %@", locale: locale, sourceName)
        }
        let label = ["sahih", "hasan", "daif"].contains(grade) ? string(grade.capitalized, locale: locale) : grade.capitalized
        return format(scope == "hadith" ? "%1$@ hadith · %2$@" : "%1$@ collection scope · %2$@", locale: locale, label, sourceName)
    }

    static func string(_ key: String, locale: Locale) -> String {
        for code in LocaleFallback.fallbackChain(for: locale.identifier) {
            guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { continue }
            let value = bundle.localizedString(forKey: key, value: nil, table: nil)
            if value != key { return value }
        }
        return key
    }
}

private struct AppNavigationTitle: ViewModifier {
    @Environment(\.locale) private var locale
    let key: String

    func body(content: Content) -> some View {
        content.navigationTitle(AppLocalization.string(key, locale: locale))
    }
}

extension View {
    func appNavigationTitle(_ key: String) -> some View {
        modifier(AppNavigationTitle(key: key))
    }
}

enum RuntimeCopy {
    static let keys: [String] = [
        "Could not read that photo.",
        "Profile photo updated.",
        "Could not update your photo. Please try again.",
        "Export is unavailable right now.",
        "Export cancelled: device check did not pass.",
        "Export failed. Please try again.",
        "Export saved. Saved items: %lld. Reading positions: %lld.",
        "Use your original Hadithly account to finish or restore this purchase.",
        "Sign in to your Hadithly account before purchasing or restoring.",
        "Plans could not be loaded. Try again.",
        "No subscription plans are available right now.",
        "Purchase could not be completed. Try again.",
        "Restore failed. Use the original Hadithly account and store account, then try again.",
        "No active Pro purchase was found for this Hadithly account. Use the account that purchased Pro.",
        "Your subscription could not be checked. Try Restore purchases again shortly.",
        "Purchase state could not be read. Contact support; reading remains available.",
        "Subscriptions are not configured for this build.",
        "Notifications are not allowed in system settings.",
        "Registering this device…",
        "This device is registered.",
        "Could not save notification settings.",
        "Could not register this device. Check your connection and try again.",
        "Choose no more than three evidence items.",
        "Each file must be 10 MB or smaller.",
        "Choose a JPEG, PNG, WebP, or PDF.",
        "Select this file again to retry the upload.",
        "Evidence could not be submitted. Please retry.",
        "Upload paused. Retry when you are ready.",
        "Enter an HTTPS source link without a username or password.",
        "This draft could not be loaded. Retry after the connection returns.",
        "Evidence status is unavailable. Try again when connected.",
        "Evidence could not be retried right now.",
        "Could not withdraw this suggestion.",
        "Could not delete this draft.",
        "Sign in again to upload evidence.",
        "Upload endpoint is unavailable.",
        "Could not add this file.",
        "Delete download",
        "Preparing…",
        "Restoring…",
        "Deleting…",
        "Sending…",
        "Export my data",
        "Submit with evidence",
        "Retry evidence upload",
        "Send private report",
        "View profile, picture, and name",
        "On",
        "Off",
        "Show less",
        "Read more",
        "Free",
        "Pro trial",
        "Account",
        "Confirm it is you before exporting your data.",
        "Notifications are not configured for this build."
    ]
    static let bindingKeys: [String] = ["This action could not be completed. Please try again.", "Check your connection and try again.", "Done", "Cancel", "Show Library list", "Show Library grid", "Remove bookmark", "Remove favorite", "Add to favorites", "Add note", "Edit note"]
    static let aliases: [String: String] = [
        "A store operation is pending for another Hadithly account. Sign in to the account that started it, then restore.": "Use your original Hadithly account to finish or restore this purchase.",
        "Sign in to your original Hadithly account to use this purchase.": "Use your original Hadithly account to finish or restore this purchase.",
        "Finish or restore the pending purchase with your original Hadithly account first.": "Use your original Hadithly account to finish or restore this purchase.",
        "Sign in to your original Hadithly account before restoring.": "Use your original Hadithly account to finish or restore this purchase.",
        "Could not save notification settings. Please try again.": "Could not save notification settings.",
        "Enter an HTTPS source link without credentials.": "Enter an HTTPS source link without a username or password.",
        "Draft status is unavailable. Retry when connected.": "This draft could not be loaded. Retry after the connection returns.",
        "Draft status is unavailable": "This draft could not be loaded. Retry after the connection returns.",
        "Select this file again to retry.": "Select this file again to retry the upload.",
        "Could not open the selected file.": "Could not add this file.",
        "Sign-in is reconnecting. Retry in a moment.": "Sign in again to upload evidence.",
        "Add Firebase configuration to enable FCM in this build.": "Notifications are not configured for this build.",
        "Restore purchases": "la2.restore"
    ]
    static func text(_ source: String, locale: Locale, fallback: String = "This action could not be completed. Please try again.") -> String {
        if source == "e4.appeal_error" { return AppLocalization.string(source, locale: locale) }
        if let alias = aliases[source] { return AppLocalization.string(alias, locale: locale) }
        if keys.contains(source), !source.contains("%lld") { return AppLocalization.string(source, locale: locale) }
        let pattern = #"^Export saved: ([0-9]+) saved items, ([0-9]+) reading positions\.$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
           let first = Range(match.range(at: 1), in: source), let second = Range(match.range(at: 2), in: source),
           let saved = Int(source[first]), let positions = Int(source[second]) {
            return AppLocalization.format("Export saved. Saved items: %lld. Reading positions: %lld.", locale: locale, saved, positions)
        }
        return AppLocalization.string(fallback, locale: locale)
    }
}

struct RuntimeStatusNotice: View {
    @Environment(\.locale) private var locale
    let source: String
    var fallback = "This action could not be completed. Please try again."
    var body: some View { Text(RuntimeCopy.text(source, locale: locale, fallback: fallback)).accessibilityIdentifier("runtimeAudit.notice") }
}

#if DEBUG
struct RuntimeNoticeCopyAuditFixture: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var index = 0
    @State private var callbacks = 0
    private let opaque = "Original %lld %@ اسم"
    private var sources: [String] { RuntimeCopy.keys + RuntimeCopy.bindingKeys + ["Synthetic private diagnostic %@"] }
    private var step: Int { textSize.isAccessibilitySize ? 1 : 3 }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(opaque).accessibilityIdentifier("runtimeAudit.opaque")
                ForEach(index..<min(index + step, sources.count), id: \.self) { item in
                    Group {
                        if item < RuntimeCopy.keys.count || item == sources.count - 1 {
                            RuntimeStatusNotice(source: item == 6 ? "Export saved: 2 saved items, 3 reading positions." : sources[item])
                        } else {
                            Text(LocalizedStringKey(sources[item]))
                        }
                    }.accessibilityIdentifier("runtimeAudit.notice." + String(item))
                }
                Button("Next fixture notice") { index = (index + step) % sources.count }.accessibilityIdentifier("runtimeAudit.next")
                Button("Local callback") { callbacks += 1 }.accessibilityIdentifier("runtimeAudit.callback")
                Text(String(callbacks)).accessibilityIdentifier("runtimeAudit.callbacks")
            }.padding(24)
        }
    }
}
#endif

#if DEBUG
struct EdgeCopyAuditFixture: View {
    @Environment(\.locale) private var locale
    @State private var index = 0
    @State private var callbacks = 0
    let opaque = "Original %lld %@ اسم"
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            Text(opaque).accessibilityIdentifier("edgeAudit.opaque")
            Group {
                switch index {
                case 0: Text("Enter the code we sent to \("name%lld+%@person@example.test").")
                case 1: Text(savedFolderFilterTitle(nil, locale: locale))
                case 2: Text(CopyAttribution.line(collection: opaque, id: "57", source: "Source %@ %lld", isAI: true, locale: locale))
                default: Text(LocalizedStringKey(["Add bookmark", "Remove bookmark", "Add to favorites", "Remove favorite", "Add note", "Edit note", "Copy", "Share", "Suggest a translation", "Report translation", "Open in reader"][index - 3]))
                }
            }.accessibilityIdentifier("edgeAudit.notice")
            Button("Next fixture notice") { index = (index + 1) % 14 }.accessibilityIdentifier("edgeAudit.next")
            Button("Local callback") { callbacks += 1 }.accessibilityIdentifier("edgeAudit.callback")
            Text(String(callbacks)).accessibilityIdentifier("edgeAudit.callbacks")
        }.padding(24) }
    }
}
#endif

#if DEBUG
struct FinalWrapperCopyAuditFixture: View {
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var index = 0
    private let keys: [String] = ["Not bookmarked", "Bookmark %@", "Bookmark current hadith", "Bookmark positioned hadith", "Remove bookmark for positioned hadith", "Expand chapters in %@", "Collapse chapters in %@", "Volumes and chapters", "Your private saved reading", "Type, appearance, and text", "This page", "Positioned hadith", "Close reader", "Close reader menu", "Open reader menu", "Sahih", "Hasan", "Daif", "Reading", "Library", "Support", "Account", "Saved items could not load", "Free", "Pro trial", "Off", "Contents", "Bookmarks & Notes", "Settings", "Search", "Back", "Show Library list", "Show Library grid", "Bookmarked", "Favorited", "Has note", "Unverified"]
    private var step: Int { textSize.isAccessibilitySize ? 1 : 3 }
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            ForEach(index..<min(index + step, keys.count), id: \.self) { item in
                Text(keys[item].contains("%@") ? AppLocalization.format(keys[item], locale: locale, "Original %lld %@ اسم") : AppLocalization.string(keys[item], locale: locale))
                    .accessibilityIdentifier("finalAudit.notice." + String(item))
            }
            Button("Next fixture notice") { index = (index + step) % keys.count }.accessibilityIdentifier("finalAudit.next")
        }.padding(24) }
    }
}
#endif

#if DEBUG
struct AuthenticityCopyAuditFixture: View {
    @Environment(\.locale) private var locale
    @State private var index = 0
    private let grades: [String?] = ["sahih", "hasan", nil, "custom", "sahih", nil]
    private let scopes = ["hadith", "collection", "unknown", "hadith", "unknown", "hadith"]
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 20) {
            Text(AppLocalization.authenticity(scope: scopes[index], grade: grades[index], sourceName: "Original %lld %@ اسم", locale: locale))
                .accessibilityIdentifier("authenticityAudit.notice")
            Button("Next fixture notice") { index = (index + 1) % scopes.count }.accessibilityIdentifier("authenticityAudit.next")
        }.padding(24) }
    }
}
#endif
