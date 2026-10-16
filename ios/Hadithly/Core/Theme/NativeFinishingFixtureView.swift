#if DEBUG
import SwiftUI

struct NativeFinishingFixtureView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var configured = false
    @State private var finished = false
    private let values = ProcessInfo.processInfo.environment
    private var screen: String { values["FINISH_SCREEN"] ?? "install" }
    @Environment(\.colorScheme) private var colorScheme
    private var locale: String { screen == "fresh-install" ? PreferencesStore.suggestedLanguage(Locale.preferredLanguages) : values["FINISH_LOCALE"] ?? "en" }
    private var theme: ReaderTheme { screen == "fresh-install" ? .system : ReaderTheme(rawValue: values["FINISH_THEME"] ?? "dark") ?? .dark }
    private var palette: ReaderPalette { ReaderPalette.resolved(theme, systemDark: colorScheme == .dark) }

    var body: some View {
        Group {
            if configured {
                if screen.hasPrefix("auth-") {
                    SignInView.preview(String(screen.dropFirst(5)))
                } else {
                    switch screen {
                    case "fresh-install", "install", "welcome", "language", "demo", "account":
                        if finished { Text("Reading is ready").accessibilityIdentifier("finishing.complete") }
                        else { OnboardingFlowView { finished = true } }
                    case "contents":
                        FinishingSheet { ReaderContentsTestFixtureView() }
                    case "search", "saved":
                        FinishingSheet { ReaderR6Round3FixtureView(screen: screen) }
                    case "saved-main": FinishingSavedTabs()
                    case "bookmark": ReaderR6Round3FixtureView(screen: "placement")
                    default: ReaderR6ATestFixtureView()
                    }
                }
            } else { palette.background }
        }
        .environment(\.readerPalette, palette)
        .environment(\.readerTheme, theme)
        .environment(\.locale, Locale(identifier: locale))
        .environment(\.layoutDirection, LocaleFallback.isRTL(locale) ? .rightToLeft : .leftToRight)
        .preferredColorScheme(ReaderPalette.preferredColorScheme(for: theme))
        .task {
            environment.preferences.setTheme(theme)
            environment.preferences.setSeparateReaderTheme(false)
            environment.preferences.setUILocale(locale)
            environment.preferences.setTranslationLocale("en")
            environment.preferences.setReadingDirection(.ltr)
            UserDefaults.standard.set(["language": 1, "demo": 2, "account": 3][screen] ?? 0, forKey: "onboarding.la2.step")
            configured = true
        }
    }
}

private struct FinishingSheet<Content: View>: View {
    @State private var presented = false
    @ViewBuilder var content: () -> Content
    @Environment(\.readerPalette) private var palette
    @Environment(\.readerTheme) private var theme
    var body: some View {
        ReaderR6ATestFixtureView()
            .sheet(isPresented: $presented) {
                content().environment(\.readerPalette, palette).environment(\.readerTheme, theme)
                    .preferredColorScheme(ReaderPalette.preferredColorScheme(for: theme))
                    .presentationDetents([.large]).presentationBackground(palette.background)
            }
            .task { presented = true }
    }
}
#endif

#if DEBUG
private struct FinishingSavedTabs: View {
    @Environment(\.readerPalette) private var palette
    var body: some View {
        TabView(selection: .constant(2)) {
            Color.clear.tabItem { Label("Today", systemImage: "sun.max") }.tag(0)
            Color.clear.tabItem { Label("Library", systemImage: "books.vertical") }.tag(1)
            NavigationStack { SavedView(previewState: .ready) }.tabItem { Label("Saved", systemImage: "bookmark") }.tag(2)
            Color.clear.tabItem { Label("Settings", systemImage: "gearshape") }.tag(3)
        }.tint(palette.interactive).toolbarBackground(palette.surface, for: .tabBar).toolbarBackground(.visible, for: .tabBar)
    }
}
#endif
