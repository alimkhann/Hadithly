import Combine
import Foundation
import ConvexMobile
import ClerkConvex
import ClerkKit

/// Reads deployment configuration from Info.plist (populated via Secrets.xcconfig).
struct AppConfig {
    let convexURL: String
    let clerkPublishableKey: String
    let revenueCatAPIKey: String
    let privacyPolicyURL: URL?
    let termsOfUseURL: URL?

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
        self.revenueCatAPIKey = info["RevenueCatAPIKey"] as? String ?? ""
        self.privacyPolicyURL = (info["PrivacyPolicyURL"] as? String).flatMap(URL.init(string:))
        self.termsOfUseURL = (info["TermsOfUseURL"] as? String).flatMap(URL.init(string:))
    }
}

struct GuestMergeResult: Decodable {
    let bookmarksMerged: Int
    let bookmarksSkipped: Int
    let notesMerged: Int
    let notesSkipped: Int
    let favoritesMerged: Int
    let favoritesSkipped: Int
    let progressMerged: Int
    let progressSkipped: Int
}

struct CurrentPreferencesRow: Decodable {
    let readerPreferences: ReaderPreferences?
}

/// Process-wide dependency container.
/// Owns the Clerk-configured Convex client; views observe auth through `Clerk.shared`.
@MainActor
@Observable
final class AppEnvironment {
    let config: AppConfig
    let convex: ConvexClientWithAuth<String>
    let guestData: GuestDataStore
    let library: UserLibraryModel
    let push: PushNotificationManager
    let purchases: PurchaseManager
    let preferences: PreferencesStore
    let links = LinkRouter()

    /// Summary of the last completed sign-in sync, surfaced in Settings.
    private(set) var lastSyncSummary: String?
    /// Realtime, server-authorized access flag for the minimal moderation UI.
    private(set) var canModerate = false

    private let authProvider: ClerkConvexAuthProvider
    private var authStateCancellable: AnyCancellable?
    private var moderationAccessCancellable: AnyCancellable?

    init(config: AppConfig = AppConfig(), guestData: GuestDataStore? = nil) {
        self.config = config
        self.guestData = guestData ?? GuestDataStore()
        Clerk.configure(publishableKey: config.clerkPublishableKey)
        self.purchases = PurchaseManager(apiKey: config.revenueCatAPIKey)
        let store = PreferencesStore()
        self.preferences = store
        let provider = ClerkConvexAuthProvider()
        self.authProvider = provider
        self.convex = ConvexClientWithAuth(
            deploymentUrl: config.convexURL,
            authProvider: provider
        )
        provider.bind(client: convex)
        self.library = UserLibraryModel(
            convex: convex,
            guestData: self.guestData,
            isSignedIn: { Clerk.shared.session != nil }
        )
        self.push = PushNotificationManager.shared
        self.push.uploadHandler = { [weak self] token in
            guard let self, Clerk.shared.session != nil else { return }
            let tzOffsetMinutes = Double(-TimeZone.current.secondsFromGMT() / 60)
            try? await self.convex.mutation(
                "library:savePushToken",
                with: [
                    "token": token as ConvexEncodable?,
                    "platform": "ios" as ConvexEncodable?,
                    "tzOffsetMinutes": tzOffsetMinutes as ConvexEncodable?,
                ]
            )
        }

        // Explicit preference changes sync to Convex while signed in; while
        // signed out they stay device-local and merge on the next sign-in.
        store.onPreferencesChanged = { [weak self] updated in
            self?.syncPreferences(updated)
        }

        // Personal-data subscriptions must follow the Convex session: a
        // subscription opened before authentication errors and stays empty.
        authStateCancellable = convex.authState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.library.refresh()
                self?.refreshModerationAccess(for: state)
            }
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
            let _: String? = try await convex.mutation(
                "users:ensureCurrentUser",
                with: [
                    "preferredLanguage": preferences.preferences.translationLocale as ConvexEncodable?,
                    "readerPreferences": Self.wireDict(for: preferences.preferences) as ConvexEncodable?,
                ]
            )
            await adoptServerPreferences()
            if let clerkUserID = Clerk.shared.user?.id {
                await purchases.logIn(appUserID: clerkUserID)
            }
        } catch {
            lastSyncSummary = "Account sync failed: \(error.localizedDescription)"
            library.refresh()
            return
        }

        let payload = GuestMergePlanner.makePayload(
            bookmarks: guestData.bookmarkDrafts(),
            notes: guestData.noteDrafts(),
            favorites: guestData.favoriteDrafts(),
            progress: guestData.progressDrafts()
        )

        if payload.isEmpty {
            lastSyncSummary = "Signed in."
            library.refresh()
            await push.uploadTokenIfNeeded()
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
                    "favorites": payload.favorites.map { item in
                        [
                            "hadithId": item.hadithId,
                            "createdAt": item.createdAt,
                        ] as [String: ConvexEncodable?]
                    },
                    "readingProgress": payload.readingProgress.map { item in
                        [
                            "collectionSlug": item.collectionSlug,
                            "hadithId": item.hadithId,
                            "updatedAt": item.updatedAt,
                        ] as [String: ConvexEncodable?]
                    },
                ]
            )
            guestData.clearAll()
            lastSyncSummary = Self.syncSummary(for: result)
        } catch {
            // Local data is deliberately kept so a later sign-in can retry.
            lastSyncSummary = "Guest data merge failed: \(error.localizedDescription)"
        }
        library.refresh()
        await push.uploadTokenIfNeeded()
    }

    /// Called when the Clerk session ends. The SwiftData store is empty (the
    /// merge cleared it), so the library flips back to guest mode cleanly.
    func handleSignOut() {
        library.refresh()
        moderationAccessCancellable?.cancel()
        moderationAccessCancellable = nil
        canModerate = false
        Task { await purchases.logOut() }
    }

    /// Deletes synced Hadithly data first, while the Convex token is valid,
    /// then removes the Clerk identity and its sessions. Safe to retry if the
    /// second step fails because the backend mutation is idempotent.
    func deleteAccount() async throws {
        let _: Bool? = try await convex.mutation("users:deleteCurrentUser")
        guard let user = Clerk.shared.user else { return }
        try await user.delete()
        handleSignOut()
    }

    private func syncPreferences(_ updated: ReaderPreferences) {
        guard Clerk.shared.session != nil else { return }
        Task { [weak self] in
            guard let self else { return }
            try? await self.convex.mutation(
                "users:updateReaderPreferences",
                with: ["readerPreferences": Self.wireDict(for: updated) as ConvexEncodable?]
            )
        }
    }

    /// Adopts the authoritative stored preferences when the server row is
    /// newer than the device (another device made the latest explicit change).
    private func adoptServerPreferences() async {
        guard
            let row = try? await convex
                .subscribe(to: "users:getCurrentUserPreferences", yielding: CurrentPreferencesRow.self)
                .values
                .first(where: { _ in true }),
            let server = row.readerPreferences,
            server.updatedAt > preferences.preferences.updatedAt
        else { return }
        preferences.adoptServer(server)
    }

    /// Wire encoding for the platform-neutral preference payload. All numbers
    /// travel as Double because Convex `v.number()` rejects integer wrappers.
    private static func wireDict(for prefs: ReaderPreferences) -> [String: ConvexEncodable?] {
        [
            "schemaVersion": Double(prefs.schemaVersion) as ConvexEncodable?,
            "uiLocale": prefs.uiLocale as ConvexEncodable?,
            "translationLocale": prefs.translationLocale as ConvexEncodable?,
            "readingDirection": prefs.readingDirection.rawValue as ConvexEncodable?,
            "theme": prefs.theme.rawValue as ConvexEncodable?,
            "arabicFont": prefs.arabicFont.rawValue as ConvexEncodable?,
            "arabicFontSize": prefs.arabicFontSize as ConvexEncodable?,
            "arabicVisible": prefs.arabicVisible as ConvexEncodable?,
            "translationVisible": prefs.translationVisible as ConvexEncodable?,
            "updatedAt": prefs.updatedAt as ConvexEncodable?,
        ]
    }

    private func refreshModerationAccess(for state: AuthState<String>) {        moderationAccessCancellable?.cancel()
        moderationAccessCancellable = nil
        guard case .authenticated = state else {
            canModerate = false
            return
        }

        moderationAccessCancellable = convex
            .subscribe(to: "community:canModerate", yielding: Bool.self)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure = completion {
                        self?.canModerate = false
                    }
                },
                receiveValue: { [weak self] canModerate in
                    self?.canModerate = canModerate
                }
            )
    }

    private static func syncSummary(for result: GuestMergeResult) -> String {
        var summary =
            "Signed in. Merged \(result.bookmarksMerged) bookmarks, "
            + "\(result.favoritesMerged) favorites, and \(result.notesMerged) notes."
        if result.progressMerged > 0 {
            summary += " Restored \(result.progressMerged) reading positions."
        }
        return summary
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
