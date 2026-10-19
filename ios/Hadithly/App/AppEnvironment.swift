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
    let librarySync: LibrarySync
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
        #if DEBUG
        if AutomationContext.allows("-FreshInstallForUITest"), let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        #endif
        #if DEBUG || DIAGNOSTICS_VERIFICATION
        if AutomationContext.allows("-LA1DisableCrashReports") { CrashReporting.shared.setConsent(false) }
        if AutomationContext.allows("-LA1SyntheticCrash") { CrashReporting.shared.setConsent(true) }
        #endif
        #if DEBUG
        if !AutomationContext.isActive || AutomationContext.allows("-LA1SyntheticCrash") {
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
        let libraryClient = self.convex
        self.librarySync = LibrarySync(store: self.guestData, transport: .init(namespace: config.convexURL, open: {
            let _: String? = try await libraryClient.mutation("users:ensureCurrentUser", with: [:])
            return try await libraryClient.mutation("librarySync:openBinding", with: [:])
        }, acknowledge: { capability, acknowledgement in
            try await libraryClient.mutation("librarySync:acknowledge", with: ["capability": capability, "acknowledgement": acknowledgement])
        }, send: { capability, frame in
            try await libraryClient.mutation("librarySync:applyBatch", with: ["capability": capability, "frame": frame])
        }, retireInvalid: { capability, frame in
            try await libraryClient.mutation("librarySync:retireInvalidFrame", with: ["capability": capability, "clientKey": frame.clientKey, "sequence": frame.sequence])
        }), currentSession: currentLibrarySession)
        self.library = UserLibraryModel(convex: convex, guestData: self.guestData, sync: self.librarySync, currentSession: currentLibrarySession)
        let privateLibrary = self.library
        self.librarySync.onOwnerChange = { [weak privateLibrary] _ in privateLibrary?.refresh() }
        self.librarySync.onPartitionChange = { [weak privateLibrary] owner in privateLibrary?.partitionChanged(owner) }
        SettingsExport.clearTemporaryFiles()
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
            if AutomationContext.allows("-NativePolishFixture") || AutomationContext.allows("-NativeFinishingFixture") { return }
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

    /// Guest data is claimed and settled by the captured account's LibrarySync.
    /// Completion never clears the guest store.
    func completeSignIn() async {
        guard let session = currentLibrarySession() else { return }
        guard await waitForConvexAuthentication(), currentLibrarySession() == session else { return }
        await librarySync.activate(session)
        guard currentLibrarySession() == session, librarySync.owner?.subject == session.subject else { return }
        do {
            let context = try librarySync.captureWriteContext()
            let capability = try librarySync.capability(for: context)
            let _: String? = try await convex.mutation("users:ensureCurrentUser", with: ["capability": capability,
                "preferredLanguage": preferences.preferences.translationLocale,
                "readerPreferences": Self.wireDict(for: preferences.preferences)])
            guard currentLibrarySession() == session else { return }
            await adoptServerPreferences(capability: capability, session: session)
            guard currentLibrarySession() == session else { return }
            await purchases.logIn(appUserID: session.subject)
            guard currentLibrarySession() == session else { return }
            lastSyncSummary = nil
            library.refresh()
            await push.uploadTokenIfNeeded()
        } catch { if currentLibrarySession() == session { lastSyncSummary = String(localized: "Saved items could not load") } }
    }

    func accountSessionChanged() {
        SettingsExport.clearTemporaryFiles()
        librarySync.deactivate()
        library.refresh()
    }

    /// Rendering is invalidated before account-specific background work stops.
    func handleSignOut() {
        SettingsExport.clearTemporaryFiles()
        librarySync.deactivate()
        analytics.clearPending()
        library.refresh()
        purchases.clearAccount()
        Task { await purchases.logOut() }
    }

    /// Durable phases allow a retry even after the backend account is gone.
    func deleteAccount(_ captured: LibrarySyncSession) async throws {
        guard currentLibrarySession() == captured, let user = Clerk.shared.session?.user,
              user.id == captured.subject else { throw LibrarySyncFailure.sessionChanged }
        let client = convex
        let flow = LibraryAccountDeletion(store: guestData, namespace: config.convexURL,
            currentSession: currentLibrarySession,
            invalidate: { [self] in
                analytics.setSharing(false); SettingsExport.clearTemporaryFiles()
                librarySync.deactivate(); library.refresh()
            }, prepare: {
                try await client.mutation("users:prepareAccountDeletion", with: [:])
            }, erase: { authorization in
                try await client.mutation("users:deleteCurrentUser", with: ["authorization": authorization])
            }, cleanup: { subject in
                EvidenceLocalDrafts.clear(for: subject)
                UserDefaults.standard.removeObject(forKey: "q1.appAttest.\(subject)")
            }, deleteIdentity: { expected in
                guard currentLibrarySession() == expected else { throw LibrarySyncFailure.sessionChanged }
                try await user.delete()
            })
        try await flow.run(captured)
        if currentLibrarySession() == nil { handleSignOut() }
    }

    private func syncPreferences(_ updated: ReaderPreferences) {
        guard let session = currentLibrarySession(), let context = try? librarySync.captureWriteContext() else { return }
        Task { [weak self] in
            guard let self, currentLibrarySession() == session, let capability = try? librarySync.capability(for: context) else { return }
            try? await self.convex.mutation(
                "users:updateReaderPreferences",
                with: ["capability": capability, "readerPreferences": Self.wireDict(for: updated)]
            )
            guard currentLibrarySession() == session else { return }
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
    private func adoptServerPreferences(capability: String, session: LibrarySyncSession) async {
        guard
            let row = try? await convex
                .subscribe(to: "users:getCurrentUserPreferences", with: ["capability": capability], yielding: CurrentPreferencesRow.self)
                .values
                .first(where: { _ in true }),
            currentLibrarySession() == session,
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


@MainActor
func currentLibrarySession() -> LibrarySyncSession? {
    guard let session = Clerk.shared.session, session.status == .active, let subject = session.user?.id else { return nil }
    return .init(id: session.id, subject: subject)
}
