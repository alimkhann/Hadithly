import Combine
import Foundation
import ConvexMobile
import ClerkConvex
import ClerkKit

/// Reads deployment configuration from Info.plist (populated via Secrets.xcconfig).
struct AppConfig {
    let convexURL: String
    let clerkPublishableKey: String

    init(infoDictionary: [String: Any]? = Bundle.main.infoDictionary) {
        let info = infoDictionary ?? [:]
        guard
            let convexURL = info["ConvexURL"] as? String,
            !convexURL.isEmpty,
            let clerkPublishableKey = info["ClerkPublishableKey"] as? String,
            !clerkPublishableKey.isEmpty
        else {
            fatalError(
                "Missing ConvexURL or ClerkPublishableKey in Info.plist. "
                    + "Copy ios/Secrets.xcconfig.example to ios/Secrets.xcconfig."
            )
        }
        self.convexURL = convexURL
        self.clerkPublishableKey = clerkPublishableKey
    }
}

struct GuestMergeResult: Decodable {
    let bookmarksMerged: Int
    let bookmarksSkipped: Int
    let notesMerged: Int
    let notesSkipped: Int
}

/// Process-wide dependency container.
/// Owns the Clerk-configured Convex client; views observe auth through `Clerk.shared`.
@MainActor
@Observable
final class AppEnvironment {
    let config: AppConfig
    let convex: ConvexClientWithAuth<String>
    let guestData: GuestDataStore

    /// Summary of the last completed sign-in sync, surfaced in Settings.
    private(set) var lastSyncSummary: String?

    private let authProvider: ClerkConvexAuthProvider

    init(config: AppConfig = AppConfig(), guestData: GuestDataStore? = nil) {
        self.config = config
        self.guestData = guestData ?? GuestDataStore()
        Clerk.configure(publishableKey: config.clerkPublishableKey)
        let provider = ClerkConvexAuthProvider()
        self.authProvider = provider
        self.convex = ConvexClientWithAuth(
            deploymentUrl: config.convexURL,
            authProvider: provider
        )
        provider.bind(client: convex)
    }

    /// Runs after a Clerk session becomes active: makes sure the user row
    /// exists, then merges whatever the guest collected on-device into
    /// Convex and clears the local store. Idempotent — safe to call again.
    func completeSignIn() async {
        guard await waitForConvexAuthentication() else {
            lastSyncSummary = "Sign-in sync failed: Convex session never activated."
            return
        }

        do {
            let preferredLanguage =
                UserDefaults.standard.string(forKey: "user.preferredLanguage") ?? "en"
            let _: String? = try await convex.mutation(
                "users:ensureCurrentUser",
                with: ["preferredLanguage": preferredLanguage]
            )
        } catch {
            lastSyncSummary = "Account sync failed: \(error.localizedDescription)"
            return
        }

        let payload = GuestMergePlanner.makePayload(
            bookmarks: guestData.bookmarkDrafts(),
            notes: guestData.noteDrafts()
        )

        guard !payload.isEmpty else {
            lastSyncSummary = "Signed in. Nothing to merge."
            return
        }

        do {
            let result: GuestMergeResult = try await convex.mutation(
                "guestMerge:mergeGuestData",
                with: [
                    "bookmarks": payload.bookmarks.map { item in
                        [
                            "hadithId": item.hadithId,
                            "createdAt": item.createdAt,
                        ] as [String: ConvexEncodable?]
                    },
                    "notes": payload.notes.map { item in
                        [
                            "hadithId": item.hadithId,
                            "content": item.content,
                            "createdAt": item.createdAt,
                            "updatedAt": item.updatedAt,
                        ] as [String: ConvexEncodable?]
                    },
                ]
            )
            guestData.clearAll()
            lastSyncSummary =
                "Signed in. Merged \(result.bookmarksMerged) bookmarks and \(result.notesMerged) notes."
                + " (\(result.bookmarksSkipped) bookmarks and \(result.notesSkipped) notes already up to date.)"
        } catch {
            // Local data is deliberately kept so a later sign-in can retry.
            lastSyncSummary = "Guest data merge failed: \(error.localizedDescription)"
        }
    }

    private func waitForConvexAuthentication(timeout: TimeInterval = 15) async -> Bool {
        for _ in 0..<Int(timeout * 4) {
            if case .authenticated = await currentAuthState() {
                return true
            }
            // Session sync normally logs Convex in via the auth provider;
            // this nudge covers races right after sign-in.
            _ = await convex.loginFromCache()
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    private func currentAuthState() async -> AuthState<String> {
        // A CurrentValueSubject replays its current value immediately, so
        // this returns without waiting for a state change.
        await convex.authState.values.first(where: { _ in true }) ?? .unauthenticated
    }
}
