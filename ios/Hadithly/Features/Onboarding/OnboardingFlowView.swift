import SwiftUI
import ClerkKit

enum OnboardingStep: Int, CaseIterable { case welcome, language, demonstration, account }

struct OnboardingFlowView: View {
    let onComplete: () -> Void
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.readerPalette) private var palette
    @AppStorage("onboarding.la2.step") private var storedStep = 0
    @AppStorage("onboarding.la2.visited") private var visited = 0
    @State private var completedCreation: Bool?
    @State private var auth: AuthEntry?
    private enum AuthEntry: String, Identifiable { case create, signIn; var id: String { rawValue } }
    private var step: OnboardingStep { OnboardingStep(rawValue: storedStep) ?? .welcome }

    var body: some View {
        VStack(spacing: 0) {
            if step != .welcome {
                HStack {
                    Button { storedStep = max(0, storedStep - 1) } label: { Label("la2.back", systemImage: "chevron.backward").frame(minHeight: 44).contentShape(Rectangle()) }
                        .buttonStyle(.plain).accessibilityIdentifier("onboarding.back")
                    Spacer()
                    if step == .demonstration {
                        Button { environment.analytics.record(.onboardingStepDemoSkipped); storedStep = 3 } label: {
                            Text("la2.skip").frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("onboarding.skip")
                    }
                }.font(.subheadline).padding(.horizontal, 24).foregroundStyle(palette.textSecondary)
            }
            switch step {
            case .welcome:
                WelcomeView { environment.analytics.startOnboarding(); storedStep = 1 }
            case .language:
                LanguagePickerView(selection: Binding(get: { environment.preferences.preferences.uiLocale },
                    set: { environment.preferences.applyOnboardingLanguage($0) })) { storedStep = 2 }
            case .demonstration:
                OnboardingTranslationView(locale: environment.preferences.preferences.translationLocale,
                    onReveal: { environment.analytics.record(.onboardingStepDemoUsed) }, onContinue: { storedStep = 3 })
            case .account:
                ScrollView {
                    VStack(spacing: 24) {
                        Image("OnboardingBook").resizable().scaledToFill().frame(height: 260).clipped().accessibilityHidden(true)
                            .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .top, endPoint: .bottom))
                        Text("la2.account_title").font(.largeTitle.bold()).multilineTextAlignment(.center)
                        Text("la2.account_body").font(.body).foregroundStyle(palette.textSecondary).multilineTextAlignment(.center)
                        VStack(spacing: 12) {
                            OnboardingPrimaryButton("la2.create_account") { present(.create) }.accessibilityIdentifier("onboarding.createAccount")
                            Button { present(.signIn) } label: { Text("la2.sign_in").frame(maxWidth: .infinity, minHeight: 44) }
                                .buttonStyle(.bordered).accessibilityIdentifier("onboarding.signIn")
                            Button { finish(.onboardingCompletedGuest) } label: {
                                Text("la2.guest").frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .foregroundStyle(palette.textSecondary).accessibilityIdentifier("onboarding.guest")
                            Text("la2.reading_free").font(.footnote).foregroundStyle(palette.textSecondary)
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 24)
                }
            }
        }.background(palette.background.ignoresSafeArea()).foregroundStyle(palette.textPrimary)
        .onAppear { recordStep() }.onChange(of: storedStep) { _, _ in recordStep() }
        .sheet(item: $auth) { entry in
            SignInView(onAuthenticated: {
                await environment.completeSignIn(); auth = nil
                guard Clerk.shared.session != nil else { environment.analytics.record(.onboardingStepAuthFailed); return }
                finish(completedCreation == true ? .onboardingCompletedAccountNew : completedCreation == false ? .onboardingCompletedAccountExisting : .onboardingCompletedAccountUnknown)
            }, onDismiss: { environment.analytics.record(.onboardingStepAuthCancelled); auth = nil }, initialSignUp: entry == .create,
                onCreationResult: { completedCreation = $0 }, onAuthenticationFailure: { environment.analytics.record(.onboardingStepAuthFailed) })
        }
    }
    private func present(_ entry: AuthEntry) { completedCreation = nil; environment.analytics.record(.onboardingStepAuthStarted); auth = entry }
    private func recordStep() {
        let bit = 1 << step.rawValue
        guard visited & bit == 0 else { return }; visited |= bit
        environment.analytics.record([.onboardingStepWelcomeViewed, .onboardingStepLanguageViewed, .onboardingStepDemoViewed, .onboardingStepEntryViewed][step.rawValue])
        if step != .welcome { environment.analytics.startOnboarding() }
    }
    private func finish(_ metric: AnalyticsMetric) {
        environment.analytics.completeOnboarding(metric); storedStep = 0; visited = 0; onComplete()
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
        }.buttonStyle(.plain)
    }
}

struct OnboardingTranslationView: View {
    let locale: String
    let onReveal: () -> Void
    let onContinue: () -> Void
    @Environment(\.readerPalette) private var palette
    @State private var phase: TranslationPresentationPhase = .idle
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("la2.demo_title").font(.largeTitle.bold()).padding(.top, 28)
                Text("la2.source").font(.caption).foregroundStyle(palette.textSecondary)
                Text(PreparedTranslationExample.arabic).font(Theme.arabic(30, .amiri))
                    .frame(maxWidth: .infinity, alignment: .trailing).environment(\.layoutDirection, .rightToLeft)
                TranslationReveal(phase: phase) {
                    if phase == .available {
                        if locale == "ar" { Text("la2.source_details").foregroundStyle(palette.textSecondary) }
                        else if let text = PreparedTranslationExample.translations[locale] {
                            Text(text).font(.title3).lineSpacing(5).accessibilityIdentifier("onboarding.example")
                        }
                    }
                }
                if phase == .idle {
                    Button { phase = .available; onReveal()
                        UIAccessibility.post(notification: .announcement, argument: PreparedTranslationExample.translations[locale])
                    } label: { Text("la2.see_example").frame(minHeight: 44).contentShape(Rectangle()) }
                        .buttonStyle(.plain).accessibilityIdentifier("onboarding.reveal")
                }
                Text("la2.sample_label").font(.caption).foregroundStyle(palette.textSecondary)
                Text("la2.sample_notice").font(.footnote).foregroundStyle(palette.textSecondary)
            }.padding(.horizontal, 28).padding(.bottom, 24)
        }
        OnboardingPrimaryButton("la2.continue", action: onContinue).padding(24).accessibilityIdentifier("onboarding.continue")
    }
}
