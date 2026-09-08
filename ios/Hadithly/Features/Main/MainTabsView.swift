import SwiftUI
import ClerkKit

/// Four tabs: Today / Library / Saved / Settings.
/// There is no Community tab by design — translation contributions happen
/// contextually in the reader (Phase 4), not through social features.
struct MainTabsView: View {
    @Binding var showSignIn: Bool

    @Environment(AppEnvironment.self) private var environment

    @State private var linkTarget: CanonicalHadithLink?

    var body: some View {
        TabView {
            NavigationStack {
                TodayView()
            }
            .tabItem { Label("Today", systemImage: "sun.max") }

            NavigationStack {
                LibraryView()
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }

            NavigationStack {
                SavedView()
            }
            .tabItem { Label("Saved", systemImage: "bookmark") }

            NavigationStack {
                SettingsView(showSignIn: $showSignIn)
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.accent)
        .fullScreenCover(item: $linkTarget) { target in
            ReaderView(
                collectionSlug: target.collectionSlug,
                collectionName: target.collectionName,
                openHadithNumber: target.providerHadithId
            )
        }
        .task {
            environment.library.refresh()
            consumePendingLink()
        }
        .onChange(of: environment.links.pendingLink) { _, newValue in
            // consumePending clears the queue, so the nil transition must
            // not re-trigger a consume that would close the reader cover.
            guard newValue != nil else { return }
            consumePendingLink()
        }
    }

    /// A canonical link queued before (or while) the tabs appear lands in
    /// the reader exactly once; signed-out readers keep full access.
    private func consumePendingLink() {
        linkTarget = environment.links.consumePending()
    }
}

#Preview {
    MainTabsView(showSignIn: .constant(false))
        .preferredColorScheme(.dark)
}
