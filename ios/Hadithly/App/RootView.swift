import SwiftUI
import ClerkKit

/// Top-level routing: onboarding (welcome → language → straight in) or main tabs.
/// Guest mode is a first-class state — reading works without an account.
/// This view owns the sign-in sheet and the post-sign-in sync so every
/// auth method (Apple, Google, email) converges on the same completion path.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(Clerk.self) private var clerk
    @AppStorage("onboarding.completed") private var onboardingCompleted = false

    @State private var showSignIn = false
    @State private var hasSyncedLaunchSession = false

    var body: some View {
        Group {
            if onboardingCompleted {
                MainTabsView(showSignIn: $showSignIn)
            } else {
                OnboardingFlowView {
                    onboardingCompleted = true
                }
            }
        }
        .sheet(isPresented: $showSignIn) {
            SignInView(
                onAuthenticated: {
                    await environment.completeSignIn()
                    showSignIn = false
                },
                onDismiss: { showSignIn = false }
            )
            .presentationDetents([.large])
        }
        .task {
            await observeAuthEvents()
        }
        .onOpenURL { url in
            environment.links.handle(url)
        }
    }

    private func observeAuthEvents() async {
        // Clerk restores its client asynchronously; wait for it before
        // reading the session or a restored sign-in is missed.
        for _ in 0..<100 {
            if clerk.isLoaded { break }
            try? await Task.sleep(for: .milliseconds(100))
        }

        // A session restored from a previous launch still needs its sync.
        if clerk.session != nil, !hasSyncedLaunchSession {
            hasSyncedLaunchSession = true
            await environment.completeSignIn()
        }

        // Custom flows report completion directly to onAuthenticated; this
        // loop only reacts to sign-out, which has no in-flow hook.
        for await event in clerk.auth.events {
            if case .signedOut = event {
                showSignIn = false
                environment.handleSignOut()
            }
        }
    }
}
