import SwiftUI
import ClerkKit

enum OnboardingStep: Int, CaseIterable { case welcome, language, demonstration, account }

struct OnboardingFlowView: View {
    let onComplete: () -> Void
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.readerPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @AppStorage("onboarding.la2.step") private var storedStep = 0
    @AppStorage("onboarding.la2.visited") private var visited = 0
    @State private var completedCreation: Bool?
    @State private var showingSignIn = false
    private var step: OnboardingStep { OnboardingStep(rawValue: storedStep) ?? .welcome }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if step != .welcome {
                    HStack {
                        Button { storedStep = max(0, storedStep - 1) } label: {
                            Label("la2.back", systemImage: "chevron.backward").frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("onboarding.back")
                        Spacer()
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 24)
                    .foregroundStyle(palette.textSecondary)
                }

                Group {
                    switch step {
                    case .welcome:
                        WelcomeView(showsBackground: false)
                    case .language:
                        LanguagePickerView(selection: Binding(
                            get: { environment.preferences.preferences.uiLocale },
                            set: { environment.preferences.applyOnboardingLanguage($0) }
                        ))
                    case .demonstration:
                        OnboardingTranslationView(locale: environment.preferences.preferences.translationLocale)
                    case .account:
                        VStack(spacing: 16) {
                            Spacer(minLength: 24)
                            Text("la2.account_title")
                                .font(.largeTitle.bold())
                                .multilineTextAlignment(.center)
                            Text("la2.account_body")
                                .font(.body)
                                .foregroundStyle(palette.textSecondary)
                                .multilineTextAlignment(.center)
                            Spacer(minLength: 24)
                        }
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(step)
                .transition(.opacity.combined(with: .offset(x: reducedMotion ? 0 : (layoutDirection == .rightToLeft ? -InterfaceMotion.travel : InterfaceMotion.travel))))

                footer
            }
            .animation(reducedMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: InterfaceMotion.step), value: storedStep)
            .background {
                if step == .welcome || step == .account { EntryArtworkBackdrop() }
                else { palette.background.ignoresSafeArea() }
            }
            .foregroundStyle(palette.textPrimary)
            .onAppear { recordStep() }
            .onChange(of: storedStep) { _, _ in recordStep() }
            .navigationDestination(isPresented: $showingSignIn) {
                SignInView(onAuthenticated: {
                    await environment.completeSignIn()
                    showingSignIn = false
                    guard Clerk.shared.session != nil else {
                        environment.analytics.record(.onboardingStepAuthFailed)
                        return
                    }
                    finish(completedCreation == true ? .onboardingCompletedAccountNew : completedCreation == false ? .onboardingCompletedAccountExisting : .onboardingCompletedAccountUnknown)
                }, onDismiss: {
                    environment.analytics.record(.onboardingStepAuthCancelled)
                    showingSignIn = false
                }, onCreationResult: { completedCreation = $0 }, onAuthenticationFailure: {
                    environment.analytics.record(.onboardingStepAuthFailed)
                }, embeddedInNavigation: true)
            }
        }
    }

    @ViewBuilder private var footer: some View {
        if step == .account {
            VStack(spacing: 12) {
                OnboardingPrimaryButton("la2.sign_in") {
                    completedCreation = nil
                    environment.analytics.record(.onboardingStepAuthStarted)
                    showingSignIn = true
                }
                .accessibilityIdentifier("onboarding.signIn")
                Button { finish(.onboardingCompletedGuest) } label: {
                    Text("la2.guest").frame(maxWidth: .infinity, minHeight: 52).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.textSecondary)
                .accessibilityIdentifier("onboarding.guest")
            }
            .padding(24)
        } else {
            let title: LocalizedStringKey = step == .welcome ? "la2.get_started" : "la2.continue"
            OnboardingPrimaryButton(title) {
                if step == .welcome { environment.analytics.startOnboarding() }
                storedStep += 1
            }
                .padding(24)
                .accessibilityIdentifier(step == .welcome ? "onboarding.getStarted" : "onboarding.continue")
        }
    }

    private func recordStep() {
        let bit = 1 << step.rawValue
        guard visited & bit == 0 else { return }
        visited |= bit
        environment.analytics.record([.onboardingStepWelcomeViewed, .onboardingStepLanguageViewed, .onboardingStepDemoViewed, .onboardingStepEntryViewed][step.rawValue])
        if step != .welcome { environment.analytics.startOnboarding() }
    }

    private func finish(_ metric: AnalyticsMetric) {
        environment.analytics.completeOnboarding(metric)
        storedStep = 0
        visited = 0
        onComplete()
    }
}

struct OnboardingPrimaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void
    @Environment(\.readerPalette) private var palette
    init(_ title: LocalizedStringKey, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity, minHeight: 52).background(palette.interactive)
                .foregroundStyle(palette.onInteractive).clipShape(RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(QuietPressStyle())
    }
}

struct OnboardingTranslationView: View {
    let locale: String
    @Environment(\.readerPalette) private var palette
    @Environment(AppEnvironment.self) private var environment
    @State private var hadith: DailyHadith?
    @State private var loading = true
    @State private var retry = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("la2.demo_title").font(.largeTitle.bold()).padding(.top, 28)
                if loading {
                    ContentSkeleton(kind: .daily, label: "Bringing today's hadith…")
                        .accessibilityIdentifier("onboarding.dailyLoading")
                } else if let hadith {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(hadith.referenceDisplay).font(.caption.weight(.semibold))
                        Text(hadith.authenticity.displayLabel).font(.caption)
                    }.foregroundStyle(palette.textSecondary)
                    HadithReadingText(arabicText: hadith.arabicText,
                                      translation: hadith.translation?.text,
                                      translationLanguage: hadith.translation?.language,
                                      translationLineLimit: 3,
                                      textColor: palette.textPrimary)
                        .accessibilityIdentifier("onboarding.dailyText")
                    if let translation = hadith.translation {
                        HStack(spacing: 6) {
                            Text(translation.sourceLabel)
                            if translation.isAI && !translation.sourceLabel.localizedCaseInsensitiveContains("AI") { Text("AI") }
                        }
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .accessibilityIdentifier("onboarding.translationSource")
                    } else {
                        Button("Retry") { retry += 1 }
                            .accessibilityIdentifier("onboarding.dailyRetry")
                    }
                } else {
                    Text("Today's reading is not available yet.")
                        .font(.body)
                        .foregroundStyle(palette.textSecondary)
                    Button("Retry") { retry += 1 }
                        .accessibilityIdentifier("onboarding.dailyRetry")
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .task(id: retry) { await loadDailyHadith() }
    }

    @MainActor private func loadDailyHadith() async {
        loading = true
        defer { loading = false }
        do {
            let daily: DailyHadith? = try await environment.convex.action("actions/daily:getDailyHadith", with: [
                "timezone": TimeZone.current.identifier,
                "translationLocale": locale,
            ])
            hadith = daily
        } catch {
            hadith = nil
        }
    }
}
