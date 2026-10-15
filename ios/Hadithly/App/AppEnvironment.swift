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
    #if DEBUG
    static weak var activeForStoreVerification: AppEnvironment?
    #endif
    let config: AppConfig
    let convex: ConvexClientWithAuth<String>
    let guestData: GuestDataStore
    let library: UserLibraryModel
    let push: PushNotificationManager
    let purchases: PurchaseManager
    let preferences: PreferencesStore
    let analytics: UsageStatistics
    let readerExperience = ReaderExperiencePreferences()
    let savedSafety: SavedSafetyPreferences
    let offline: OfflineStore
    let widgetProgress = LibraryModel()
    let links = LinkRouter()

    /// Summary of the last completed sign-in sync, surfaced in Settings.
    private(set) var lastSyncSummary: String?

    private let authProvider: ClerkConvexAuthProvider
    private var authStateCancellable: AnyCancellable?

    init(config: AppConfig = AppConfig(), guestData: GuestDataStore? = nil) {
        #if DEBUG || DIAGNOSTICS_VERIFICATION
        if AutomationContext.allows("-LA1DisableCrashReports") { CrashReporting.shared.setConsent(false) }
        if AutomationContext.allows("-LA1SyntheticCrash") { CrashReporting.shared.setConsent(true) }
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            CrashReporting.shared.startIfConsented()
        }
        #else
        CrashReporting.shared.startIfConsented()
        #endif
        #if DEBUG || DIAGNOSTICS_VERIFICATION
        if AutomationContext.allows("-LA1SyntheticCrash") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { fatalError("LA1SyntheticFailure") }
        }
        #endif
        let evidenceDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "EvidenceDrafts", directoryHint: .isDirectory)
        if let files = try? FileManager.default.contentsOfDirectory(at: evidenceDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for file in files {
                if let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   Date().timeIntervalSince(modified) > 7 * 24 * 60 * 60 {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
        self.config = config
        self.analytics = UsageStatistics(cloudURL: config.convexURL)
        self.guestData = guestData ?? GuestDataStore()
        Clerk.configure(publishableKey: config.clerkPublishableKey)
        self.purchases = PurchaseManager(apiKey: config.revenueCatAPIKey)
        self.purchases.analytics = self.analytics
        let store = PreferencesStore()
        self.preferences = store
        WidgetSnapshotStore.saveUILocale(store.preferences.uiLocale)
        self.savedSafety = SavedSafetyPreferences()
        let provider = ClerkConvexAuthProvider()
        self.authProvider = provider
        self.convex = ConvexClientWithAuth(
            deploymentUrl: config.convexURL,
            authProvider: provider
        )
        provider.bind(client: convex)
        let purchaseClient = self.convex
        purchases.verifyBackendAccess = { try await purchaseClient.action("actions/subscriptions:refresh", with: [:]) }
        self.library = UserLibraryModel(
            convex: convex,
            guestData: self.guestData,
            isSignedIn: { Clerk.shared.session != nil }
        )
        let client = convex
        let probeURL = URL(string: config.convexURL)
        self.offline = OfflineStore(manifestProvider: { locale in
            var args: [String: ConvexEncodable?] = [:]
            if let locale {
                args["translationLocale"] = locale as ConvexEncodable?
            }
            for try await response in client.subscribe(
                to: "offlineDumps:getOfflineManifests",
                with: args,
                yielding: OfflineManifestsResponse.self
            ).values {
                return response
            }
            throw OfflineDownloadError.noData
        }, probeBaseURL: probeURL)
        let library = self.library
        let offline = self.offline
        offline.analytics = analytics
        for slug in ReaderModels.collections.map(\.slug) {
            offline.setAnchorProvider(for: slug) { [weak library] in
                Self.offlineAnchors(for: slug, library: library)
            }
        }
        self.push = PushNotificationManager.shared
        self.widgetProgress.start(convex: convex)
        self.push.uploadHandler = { [weak self] token in
            guard let self, Clerk.shared.session != nil else { return }
            let prefs = self.preferences.preferences
            let tzOffsetMinutes = Double(-TimeZone.current.secondsFromGMT() / 60)
            try? await self.convex.mutation(
                "library:savePushToken",
                with: [
                    "token": token as ConvexEncodable?,
                    "platform": "ios" as ConvexEncodable?,
                    "timezone": TimeZone.current.identifier as ConvexEncodable?,
                    "uiLocale": prefs.uiLocale as ConvexEncodable?,
                    "translationLocale": prefs.translationLocale as ConvexEncodable?,
                    "tzOffsetMinutes": tzOffsetMinutes as ConvexEncodable?,
                ]
            )
        }
        self.push.openHandler = { [weak self] payload in
            self?.links.handleNotification(payload)
        }

        // Explicit preference changes sync to Convex while signed in; while
        // signed out they stay device-local and merge on the next sign-in.
        store.onPreferencesChanged = { [weak self] updated in
            guard let self else { return }
            WidgetSnapshotStore.saveUILocale(updated.uiLocale)
#if DEBUG
            if AutomationContext.allows("-NativePolishFixture") { return }
#endif
            self.syncPreferences(updated)
            Task { await self.refreshDailyWidget(updated) }
        }

        // Personal-data subscriptions must follow the Convex session: a
        // subscription opened before authentication errors and stays empty.
        authStateCancellable = convex.authState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.library.refresh()
            }
        #if DEBUG
        Self.activeForStoreVerification = self
        #endif
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
            progress: guestData.progressDrafts(),
            folders: guestData.folderDrafts(),
            memberships: guestData.savedMembershipDrafts()
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
                        switch item {
                        case .current(let position):
                            return [
                                "position": position.convexWireValue,
                            ] as [String: ConvexEncodable?]
                        case .legacy(let collectionSlug, let hadithId, let updatedAt):
                            return [
                                "collectionSlug": collectionSlug,
                                "hadithId": hadithId,
                                "updatedAt": updatedAt,
                            ] as [String: ConvexEncodable?]
                        }
                    },
                    "savedFolders": payload.savedFolders.map { item in
                        [
                            "localId": item.localId,
                            "name": item.name,
                            "createdAt": item.createdAt,
                        ] as [String: ConvexEncodable?]
                    },
                    "savedItems": payload.savedItems.map { item in
                        // Convex optional validators require an absent key,
                        // not a JSON null. Sending the latter was the guest
                        // merge failure shown in Settings.
                        var wire: [String: ConvexEncodable?] = [
                            "hadithId": item.hadithId,
                            "createdAt": item.createdAt,
                            "updatedAt": item.updatedAt,
                        ]
                        if let value = item.bookmarkCreatedAt { wire["bookmarkCreatedAt"] = value }
                        if let value = item.favoriteCreatedAt { wire["favoriteCreatedAt"] = value }
                        if let value = item.noteContent { wire["noteContent"] = value }
                        if let value = item.noteCreatedAt { wire["noteCreatedAt"] = value }
                        if let value = item.noteUpdatedAt { wire["noteUpdatedAt"] = value }
                        if let value = item.folderLocalId { wire["folderLocalId"] = value }
                        return wire
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
        analytics.clearPending()
        library.refresh()
        purchases.clearAccount()
        Task { await purchases.logOut() }
    }

    /// Deletes synced Hadithly data first, while the Convex token is valid,
    /// then removes the Clerk identity and its sessions. Safe to retry if the
    /// second step fails because the backend mutation is idempotent.
    func deleteAccount() async throws {
        analytics.setSharing(false)
        let accountId = Clerk.shared.user?.id
        let _: Bool? = try await convex.mutation("users:deleteCurrentUser")
        if let accountId {
            EvidenceLocalDrafts.clear(for: accountId)
            UserDefaults.standard.removeObject(forKey: "q1.appAttest.\(accountId)")
        }
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
            // N1: a locale change must also reach this device's push row so
            // the next notification is materialized in the new translation.
            // No-ops when no APNs token is registered yet.
            await self.push.uploadTokenIfNeeded()
        }
    }

    private func refreshDailyWidget(_ prefs: ReaderPreferences) async {
        let payload: DailyWidgetPayload? = try? await convex.action(
            "actions/daily:getDailyWidgetPayload",
            with: [
                "timezone": TimeZone.current.identifier,
                "translationLocale": prefs.translationLocale,
                "arabicVisible": prefs.arabicVisible,
                "translationVisible": prefs.translationVisible,
            ]
        )
        WidgetSnapshotStore.saveDaily(payload?.snapshot())
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
        WidgetSnapshotStore.saveUILocale(server.uiLocale)
    }

    /// Wire encoding for the platform-neutral preference payload. All numbers
    /// travel as Double because Convex `v.number()` rejects integer wrappers.
    private static func wireDict(for prefs: ReaderPreferences) -> [String: ConvexEncodable?] {
        [
            "schemaVersion": Double(prefs.schemaVersion) as ConvexEncodable?,
            "uiLocale": prefs.uiLocale as ConvexEncodable?,
            "translationLocale": prefs.translationLocale as ConvexEncodable?,
            "readingDirection": prefs.readingDirection.rawValue as ConvexEncodable?,
            "appTheme": prefs.appTheme.rawValue as ConvexEncodable?,
            "readerTheme": prefs.readerTheme.rawValue as ConvexEncodable?,
            "usesSeparateReaderTheme": prefs.usesSeparateReaderTheme as ConvexEncodable?,
            "arabicFont": prefs.arabicFont.rawValue as ConvexEncodable?,
            "arabicFontSize": prefs.arabicFontSize as ConvexEncodable?,
            "translationFontSize": prefs.translationFontSize as ConvexEncodable?,
            "arabicVisible": prefs.arabicVisible as ConvexEncodable?,
            "translationVisible": prefs.translationVisible as ConvexEncodable?,
            "updatedAt": prefs.updatedAt as ConvexEncodable?,
        ]
    }

    /// Canonical ids the O2 activation gate must find in a replacement
    /// dump before the pointer flips: every Saved hadith (`sunnah_now` is
    /// the only provider writing Saved rows today) plus every stored R1
    /// position anchor for the collection.
    private static func offlineAnchors(for slug: String, library: UserLibraryModel?) -> Set<String> {
        guard let library else { return [] }
        var anchors = Set<String>()
        func canonicalId(collectionSlug: String, hadithNumber: String?) -> String? {
            guard collectionSlug == slug, let hadithNumber, !hadithNumber.isEmpty else { return nil }
            return "sunnah_now:\(slug):\(hadithNumber)"
        }
        for item in library.savedItems {
            if let id = canonicalId(collectionSlug: item.hadith?.collectionSlug ?? "", hadithNumber: item.hadith?.hadithNumber) {
                anchors.insert(id)
            }
        }
        for entry in [library.bookmarks, library.favorites, library.notes].joined() {
            if let id = canonicalId(collectionSlug: entry.hadith?.collectionSlug ?? "", hadithNumber: entry.hadith?.hadithNumber) {
                anchors.insert(id)
            }
        }
        for entry in library.progress where entry.collectionSlug == slug {
            if let position = entry.position {
                anchors.insert("\(position.anchor.provider):\(slug):\(position.anchor.providerHadithId)")
            } else if let hadith = entry.hadith,
                      let id = canonicalId(collectionSlug: slug, hadithNumber: hadith.hadithNumber)
            {
                anchors.insert(id)
            }
        }
        return anchors
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
