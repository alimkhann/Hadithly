import SwiftUI
import ClerkKit

/// Four tabs: Today / Library / Saved / Settings.
/// There is no Community tab by design — translation contributions happen
/// contextually in the reader (Phase 4), not through social features.
struct MainTabsView: View {
    @Binding var showSignIn: Bool

    @Environment(AppEnvironment.self) private var environment

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
        .task { environment.library.refresh() }
    }
}

#Preview {
    MainTabsView(showSignIn: .constant(false))
        .preferredColorScheme(.dark)
}
