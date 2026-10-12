import SwiftUI

enum AppLocalization {
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
