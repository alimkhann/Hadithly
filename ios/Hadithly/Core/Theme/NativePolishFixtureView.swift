#if DEBUG
import SwiftUI

struct NativePolishFixtureView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var configured = false
    @State private var onboardingDone = false
    private let values = ProcessInfo.processInfo.environment
    private var screen: String { values["POLISH_SCREEN"] ?? "today-loading" }
    private var theme: ReaderTheme { ReaderTheme(rawValue: values["POLISH_THEME"] ?? "light") ?? .light }
    private var palette: ReaderPalette { ReaderPalette.resolved(theme, systemDark: true) }

    var body: some View {
        Group {
            if configured {
                NavigationStack {
                    switch screen {
                    case "today-loading": TodayView(previewState: "loading")
                    case "today-ready": TodayView(previewState: "ready")
                    case "today-failure": TodayView(previewState: "failure")
                    case "library-loading": LibraryView(previewLoading: true)
                    case "library-ready": LibraryView(previewLoading: false)
                    case "saved-loading": SavedView(previewState: .loading)
                    case "saved-failure": SavedView(previewState: .failed)
                    case "onboarding":
                        if onboardingDone { Text("Reading is ready").accessibilityIdentifier("polish.onboardingDone") }
                        else { OnboardingFlowView { onboardingDone = true } }
                    case "reader", "reader-loading": ReaderR6ATestFixtureView()
                    default: OnboardingTranslationView(locale: "en", onReveal: {}, onContinue: {})
                    }
                }
            } else { Color.clear }
        }
        .background(palette.background.ignoresSafeArea())
        .environment(\.readerPalette, palette)
        .environment(\.readerTheme, theme)
        .environment(\.locale, Locale(identifier: values["POLISH_LOCALE"] ?? "en"))
        .environment(\.layoutDirection, LocaleFallback.isRTL(values["POLISH_LOCALE"] ?? "en") ? .rightToLeft : .leftToRight)
        .preferredColorScheme(ReaderPalette.preferredColorScheme(for: theme))
        .task {
            environment.preferences.setTheme(theme)
            environment.preferences.setSeparateReaderTheme(false)
            environment.preferences.setUILocale(values["POLISH_LOCALE"] ?? "en")
            environment.preferences.setTranslationLocale("en")
            UserDefaults.standard.set(0, forKey: "onboarding.la2.step")
            UserDefaults.standard.set(0, forKey: "onboarding.la2.visited")
            configured = true
        }
    }

    static var dailyExample: DailyHadith {
        DailyHadith(_id: "visual-preview", provider: "fixture", canonicalId: "fixture:preview:1", providerHadithId: "1",
            collectionSlug: "fixture", collectionName: "Prepared interface preview", volumeId: nil,
            arabicText: PreparedTranslationExample.arabic, englishText: nil,
            translation: DailyTranslation(text: Array(repeating: PreparedTranslationExample.translations["en"]!, count: 12).joined(separator: " "), language: "en", source: "fixture", sourceLabel: "Prepared example", isAI: false),
            referenceDisplay: "Prepared interface preview", authenticity: ReaderAuthenticity(kind: "unknown", normalizedGrade: nil, claimScope: "unknown", sourceLabel: "Prepared example", sourceName: "Interface preview", sourceUrl: "", verificationMethod: "unverified"))
    }
}
#endif
