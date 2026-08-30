import SwiftUI
import ClerkKit

/// Four tabs: Today / Library / Saved / Settings.
/// There is no Community tab by design — translation contributions happen
/// contextually in the reader (Phase 4), not through social features.
struct MainTabsView: View {
    @Binding var showSignIn: Bool

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }

            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }

            SavedView()
                .tabItem { Label("Saved", systemImage: "bookmark") }

            SettingsView(showSignIn: $showSignIn)
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

// MARK: - Settings

struct SettingsView: View {
    @Binding var showSignIn: Bool

    @Environment(AppEnvironment.self) private var environment
    @Environment(Clerk.self) private var clerk

    @State private var isSigningOut = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if clerk.session != nil {
                    accountCard
                } else {
                    guestCard
                }

                #if DEBUG
                GuestDataDebugCard()
                #endif
            }
            .padding(16)
        }
        .background(Theme.background)
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Account", systemImage: "person.crop.circle")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            if let user = clerk.user {
                Text([user.firstName, user.lastName].compactMap { $0 }.joined(separator: " "))
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                if let email = user.primaryEmailAddress?.emailAddress {
                    Text(email)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if let summary = environment.lastSyncSummary {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }

            Button {
                Task { await signOut() }
            } label: {
                if isSigningOut {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else {
                    Text("Sign out")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .buttonStyle(.plain)
            .background(Theme.surfaceElevated)
            .foregroundStyle(Theme.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.top, 4)
            .accessibilityIdentifier("settings.signout")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var guestCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Reading as a guest", systemImage: "person.crop.circle.badge.questionmark")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            Text("Everything you need to read works without an account. Sign in to carry your bookmarks and notes across devices.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)

            if let summary = environment.lastSyncSummary {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }

            Button {
                showSignIn = true
            } label: {
                Text("Sign in")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityIdentifier("settings.signin")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func signOut() async {
        isSigningOut = true
        defer { isSigningOut = false }
        try? await Clerk.shared.auth.signOut()
    }
}

#if DEBUG
/// Development-only helpers to exercise guest mode and the sign-in merge
/// without a reader UI (the reader arrives in Phase 2).
private struct GuestDataDebugCard: View {
    @Environment(GuestDataStore.self) private var guestData

    /// A real hadith from the dev deployment, used to seed a mergeable item.
    private let sampleHadithId = "jn7fxd3z54153q9j13kmhgzkv18df2zd"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Debug · guest data", systemImage: "ladybug")
                .font(.headline)
                .foregroundStyle(Theme.textSecondary)

            Text("Local guest items: \(guestData.itemCount)")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 8) {
                Button("Seed bookmark") {
                    guestData.addBookmark(hadithId: sampleHadithId)
                }
                .buttonStyle(.bordered)

                Button("Seed note") {
                    guestData.addNote(hadithId: sampleHadithId, content: "Guest note written on-device.")
                }
                .buttonStyle(.bordered)
            }
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
#endif

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
    MainTabsView(showSignIn: .constant(false))
        .preferredColorScheme(.dark)
}
