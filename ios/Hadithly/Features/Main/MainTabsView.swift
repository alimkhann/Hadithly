import SwiftUI

/// Four tabs: Today / Library / Saved / Settings.
/// There is no Community tab by design — translation contributions happen
/// contextually in the reader (Phase 4), not through social features.
struct MainTabsView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }

            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }

            SavedView()
                .tabItem { Label("Saved", systemImage: "bookmark") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.accent)
    }
}

// Phase 0 placeholders — each is replaced in its own phase.

struct TodayView: View {
    var body: some View {
        PlaceholderScreen(
            title: "Today",
            subtitle: "Daily hadith and continue reading land here in Phase 3."
        )
    }
}

struct LibraryView: View {
    var body: some View {
        PlaceholderScreen(
            title: "Library",
            subtitle: "The seven collections open here in Phase 2."
        )
    }
}

struct SavedView: View {
    var body: some View {
        PlaceholderScreen(
            title: "Saved",
            subtitle: "Bookmarks, favorites, and notes land here in Phase 3."
        )
    }
}

struct SettingsView: View {
    var body: some View {
        PlaceholderScreen(
            title: "Settings",
            subtitle: "Reading preferences and account land here in Phase 3."
        )
    }
}

private struct PlaceholderScreen: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

#Preview {
    MainTabsView()
        .preferredColorScheme(.dark)
}
