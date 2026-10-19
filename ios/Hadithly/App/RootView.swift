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

    private var isR3PagingFixture: Bool {
        AutomationContext.allows("-R3PagingFixture")
    }

    private var isR5ContentsFixture: Bool {
        AutomationContext.allows("-R5ContentsFixture")
    }

    private var isR6AReaderFixture: Bool {
        AutomationContext.allows("-R6AReaderFixture")
    }

    private var isR6Round3Fixture: Bool {
        AutomationContext.allows("-R6Round3Fixture")
    }

    @ViewBuilder
    var body: some View {
        if AutomationContext.allows("-NativeFinishingFixture") {
#if DEBUG
            NativeFinishingFixtureView()
#endif
        } else if AutomationContext.allows("-NativePolishFixture") {
#if DEBUG
            NativePolishFixtureView()
#endif
        } else if AutomationContext.allows("-ReaderSettingsFixture") {
#if DEBUG
            ReaderSettingsFixtureView()
#endif
        } else if AutomationContext.allows("-E2ProcessingFixture") {
#if DEBUG
            EvidenceProcessingFixture()
#endif
        } else if isR3PagingFixture {
#if DEBUG
            ReaderPagingTestFixtureView()
#endif
        } else if isR6Round3Fixture {
#if DEBUG
            ReaderR6Round3FixtureView()
#endif
        } else if isR6AReaderFixture {
#if DEBUG
            ReaderR6ATestFixtureView()
#endif
        } else if isR5ContentsFixture {
#if DEBUG
            ReaderContentsTestFixtureView()
#endif
        } else {
            productionRoot
        }
    }

    private var productionRoot: some View {
        Group {
            if onboardingCompleted {
                MainTabsView(showSignIn: $showSignIn)
            } else {
                OnboardingFlowView {
                    onboardingCompleted = true
                }
            }
        }
        .task {
            await observeAuthEvents()
        }
        .onOpenURL { url in
            environment.links.handle(url)
        }
    }

    private func observeAuthEvents() async {
        // Local fixture/unit hosts do not start account writes automatically.
        // Explicit live tests call completeSignIn after their own authorization.
        if AutomationContext.isActive { return }
        // Clerk restores its client asynchronously; wait for it before
        // reading the session or a restored sign-in is missed.
        for _ in 0..<100 {
            if clerk.isLoaded { break }
            try? await Task.sleep(for: .milliseconds(100))
        }

        // A session restored from a previous launch still needs its sync.
        if clerk.session != nil, !hasSyncedLaunchSession {
            hasSyncedLaunchSession = true
            Task { await environment.completeSignIn() }
        }

        for await event in clerk.auth.events {
            switch event {
            case .sessionChanged(let old, let new):
                guard old?.id != new?.id || old?.user?.id != new?.user?.id || old?.status != new?.status else { continue }
                environment.accountSessionChanged()
                if new != nil { Task { await environment.completeSignIn() } }
                else { showSignIn = false; environment.handleSignOut() }
            case .signedOut(let ended):
                if let current = currentLibrarySession(), current.id != ended.id { continue }
                showSignIn = false
                environment.handleSignOut()
            case .accountDeleted:
                showSignIn = false
                if currentLibrarySession() != nil { environment.accountSessionChanged(); Task { await environment.completeSignIn() } }
                else { environment.handleSignOut() }
            default: break
            }
        }
    }
}
