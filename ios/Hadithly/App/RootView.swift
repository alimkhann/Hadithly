import SwiftUI
import ClerkKit

/// Top-level routing: onboarding (welcome → language → sign-in later) or main tabs.
/// Guest mode is a first-class state — reading works without an account.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(Clerk.self) private var clerk
    @AppStorage("onboarding.completed") private var onboardingCompleted = false

    var body: some View {
        if onboardingCompleted {
            MainTabsView()
        } else {
            OnboardingFlowView {
                onboardingCompleted = true
            }
        }
    }
}
