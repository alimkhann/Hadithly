#if DEBUG
import SwiftUI

struct NativeFinishingFixtureView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var configured = false
    @State private var finished = false
    @State private var showingSignIn = false
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
                } else if screen.hasPrefix("first-reading-") {
                    FirstReadingFixtureView(name: String(screen.dropFirst("first-reading-".count)))
                } else {
                    switch screen {
                    case "fresh-install", "install", "welcome", "language", "demo", "account":
                        if finished { Text("Reading is ready").accessibilityIdentifier("finishing.complete") }
                        else { OnboardingFlowView { finished = true } }
                    case "paywall": FinishingPaywallOptions()
                    case "settings-auth": MainTabsView(showSignIn: $showingSignIn)
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
            environment.preferences.setTranslationLocale(ProcessInfo.processInfo.environment["FINISH_TRANSLATION_LOCALE"] ?? "en")
            if ProcessInfo.processInfo.environment["FIRST_READING_NO_GENERATION"] == "1" { environment.readerExperience.automaticallyTranslates = false }
            environment.preferences.setReadingDirection(.ltr)
            UserDefaults.standard.set(["language": 1, "demo": 2, "account": 3][screen] ?? 0, forKey: "onboarding.la2.step")
            configured = true
        }
    }
}

private struct FirstReadingFixtureView: View {
    let name: String
    @State private var feed = FirstReadingFixtureFeed()
    @State private var observedLocale = "ru"
    @State private var phase: FirstReadingPhase
    @State private var chosenLanguage = false
    @State private var openedTarget: String?
    init(name: String) {
        self.name = name
        _phase = State(initialValue: name == "failed" ? .failed : Self.load(name))
    }
    fileprivate static func load(_ name: String) -> FirstReadingPhase {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        do {
            let data = try Data(contentsOf: root.appendingPathComponent("testdata/first-reading/\(name).json"))
            return .result(try JSONDecoder().decode(FirstReadingResult.self, from: data))
        } catch { return .failed }
    }
    var body: some View {
        if name.hasPrefix("stream-") {
            VStack {
                OnboardingTranslationView(locale: observedLocale, source: { feed.stream($0, expiring: name == "stream-expiry") })
                Button("Withdraw fixture") { feed.withdraw("ru") }.accessibilityIdentifier("firstReading.fixture.withdraw")
                Button("Change fixture language") { observedLocale = "en" }.accessibilityIdentifier("firstReading.fixture.switch")
                Text(feed.stopped ?? "active").accessibilityIdentifier("firstReading.fixture.stopped")
            }
        }
        else if chosenLanguage { Text("Choose language").accessibilityIdentifier("firstReading.fixture.language") }
        else if let openedTarget { Text(openedTarget).accessibilityIdentifier("firstReading.fixture.target") }
        else {
            FirstReadingContent(phase: phase, onRetry: { phase = Self.load("starter-ru") },
                onChooseLanguage: { chosenLanguage = true }, onOpen: { openedTarget = $0.canonicalId })
        }
    }
}

@MainActor @Observable private final class FirstReadingFixtureFeed {
    var stopped: String?
    private var continuations: [String: AsyncThrowingStream<FirstReadingResult, Error>.Continuation] = [:]
    func stream(_ locale: String, expiring: Bool) -> AsyncThrowingStream<FirstReadingResult, Error> {
        AsyncThrowingStream { continuation in
            continuations[locale] = continuation
            continuation.onTermination = { [weak self] _ in Task { @MainActor in self?.stopped = locale } }
            if expiring {
                let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                do {
                    let data = try Data(contentsOf: root.appendingPathComponent("testdata/first-reading/starter-ru.json"))
                    var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                    object["validUntil"] = Date().timeIntervalSince1970 * 1000 + 5_000
                    continuation.yield(try JSONDecoder().decode(FirstReadingResult.self, from: JSONSerialization.data(withJSONObject: object)))
                } catch { continuation.finish(throwing: error) }
            } else if case .result(let result) = FirstReadingFixtureView.load(locale == "en" ? "starter-en" : "starter-ru") {
                continuation.yield(result)
            }
        }
    }
    func withdraw(_ locale: String) { continuations[locale]?.yield(.unavailable) }
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
private struct FinishingPaywallOptions: View {
    @State private var annual = true
    @Environment(\.readerPalette) private var palette
    var body: some View {
        VStack(spacing: 20) {
            Text("la2.more_translations").font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text("la2.allowance").font(.subheadline).foregroundStyle(palette.textSecondary).multilineTextAlignment(.center)
            PaywallPlanOption(annual: true, isSelected: annual, price: "$2.08", savingsPercent: 30) { annual = true }
            PaywallPlanOption(annual: false, isSelected: !annual, price: "$2.99", savingsPercent: nil) { annual = false }
            OnboardingPrimaryButton(annual ? "la2.subscribe_annual" : "la2.subscribe_monthly") {}.disabled(true)
            Text("la2.renewal").font(.footnote).foregroundStyle(palette.textSecondary).multilineTextAlignment(.center)
        }.padding(24).foregroundStyle(palette.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(palette.background.ignoresSafeArea())
    }
}

#endif
