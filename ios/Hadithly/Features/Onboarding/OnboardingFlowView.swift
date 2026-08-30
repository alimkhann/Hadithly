import SwiftUI

enum OnboardingStep {
    case welcome
    case language
}

/// Onboarding is intentionally short: value → language → straight in.
/// Account creation is deferred and optional (guest mode first).
struct OnboardingFlowView: View {
    let onComplete: () -> Void

    @State private var step: OnboardingStep = .welcome
    @AppStorage("user.preferredLanguage") private var preferredLanguage = "en"

    var body: some View {
        switch step {
        case .welcome:
            WelcomeView {
                step = .language
            }
        case .language:
            LanguagePickerView(selection: $preferredLanguage) {
                onComplete()
            }
        }
    }
}

#Preview {
    OnboardingFlowView(onComplete: {})
}
