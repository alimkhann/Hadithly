import SwiftUI
import ClerkKit

/// Four tabs: Today / Library / Saved / Settings.
/// There is no Community tab by design — translation contributions happen
/// contextually in the reader (Phase 4), not through social features.
struct MainTabsView: View {
    @Binding var showSignIn: Bool

    @Environment(AppEnvironment.self) private var environment

    @State private var linkTarget: CanonicalHadithLink?
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                TodayView()
            }
            .tabItem { Label("Today", systemImage: "sun.max") }
            .tag(0)

            NavigationStack {
                LibraryView()
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }
            .tag(1)

            NavigationStack {
                SavedView()
            }
            .tabItem { Label("Saved", systemImage: "bookmark") }
            .tag(2)

            NavigationStack {
                SettingsView(showSignIn: $showSignIn)
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(3)
        }
        .tint(Theme.accent)
        .fullScreenCover(item: $linkTarget) { target in
            ReaderView(
                collectionSlug: target.collectionSlug,
                collectionName: target.collectionName,
                openHadithNumber: target.providerHadithId,
                targetSource: .canonicalLink
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
        // The reader shortcut sheet's EDIT affordance dismisses the reader
        // and lands here on the Saved tab.
        .onReceive(NotificationCenter.default.publisher(for: .hadithlyOpenSavedTab)) { _ in
            selection = 2
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
