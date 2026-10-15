import SwiftUI
import ClerkKit

@main
struct HadithlyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            LocalizedAppRoot()
                .environment(environment)
        }
    }
}

/// Reads locale and direction inside the observable view tree. Keeping these
/// environment values here makes a live RTL-to-LTR switch update the existing
/// window instead of relying on the App scene body to be reevaluated.
private struct LocalizedAppRoot: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let preferences = environment.preferences.preferences
        let uiLocale = preferences.uiLocale

        AppPaletteRoot(theme: preferences.appTheme) {
            RootView()
        }
            .environment(environment.guestData)
            .environment(environment.library)
            .environment(environment.push)
            .environment(Clerk.shared)
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { environment.analytics.flush() }
            }
            .environment(\.locale, Locale(identifier: uiLocale))
            .environment(
                \.layoutDirection,
                LocaleFallback.isRTL(uiLocale) ? .rightToLeft : .leftToRight
            )
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
