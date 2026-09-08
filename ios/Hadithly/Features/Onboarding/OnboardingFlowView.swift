import SwiftUI

enum OnboardingStep {
    case welcome
    case language
}

/// Onboarding is intentionally short: value → language → straight in.
/// Account creation is deferred and optional (guest mode first).
/// The single language answer initializes both uiLocale and translationLocale.
struct OnboardingFlowView: View {
    let onComplete: () -> Void

    @Environment(AppEnvironment.self) private var environment

    @State private var step: OnboardingStep = .welcome

    var body: some View {
        switch step {
        case .welcome:
            WelcomeView {
                step = .language
            }
        case .language:
            LanguagePickerView(
                selection: Binding(
                    get: { environment.preferences.preferences.uiLocale },
                    set: { environment.preferences.applyOnboardingLanguage($0) }
                )
            ) {
                onComplete()
            }
        }
    }
}

#Preview {
    OnboardingFlowView(onComplete: {})
}
