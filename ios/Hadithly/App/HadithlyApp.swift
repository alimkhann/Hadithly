import SwiftUI
import ClerkKit

@main
struct HadithlyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment()

    var body: some Scene {
        let uiLocale = environment.preferences.preferences.uiLocale
        WindowGroup {
            AppPaletteRoot(theme: environment.preferences.preferences.appTheme) {
                RootView()
            }
                .environment(environment)
                .environment(environment.guestData)
                .environment(environment.library)
                .environment(environment.push)
                .environment(Clerk.shared)
                .environment(\.locale, Locale(identifier: uiLocale))
                .environment(
                    \.layoutDirection,
                    LocaleFallback.isRTL(uiLocale) ? .rightToLeft : .leftToRight
                )
        }
    }
}

/// One palette owner for all app content, presented sheets, tabs, and bars.
/// Updating the preference only invalidates this environment; it never changes
/// a view identity, so NavigationStack and Reader state remain in place.
private struct AppPaletteRoot<Content: View>: View {
    @Environment(\.colorScheme) private var systemScheme
    let theme: ReaderTheme
    let content: Content

    init(theme: ReaderTheme, @ViewBuilder content: () -> Content) {
        self.theme = theme
        self.content = content()
    }

    private var palette: ReaderPalette {
        ReaderPalette.resolved(theme, systemDark: systemScheme == .dark)
    }

    private var themedContent: Content {
        Theme.install(palette)
        return content
    }

    var body: some View {
        themedContent
            .environment(\.readerPalette, palette)
            .environment(\.readerTheme, theme)
            .tint(palette.interactive)
            .preferredColorScheme(ReaderPalette.preferredColorScheme(for: theme))
    }
}
