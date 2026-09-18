import Foundation
import Observation

/// Wire shape of `offlineDumps:getOfflineManifests`. Decoded from the first
/// subscription emission (the SDK has no one-shot query call).
struct OfflineManifestsResponse: Decodable, Sendable {
    let bases: [OfflineManifest]
    let packs: [OfflineManifest]
}

enum OfflineEnqueueResult: Equatable, Sendable {
    case started
    case alreadyActive
    case blocked(reason: String)
}

/// O2 download manager. Owns the on-disk layout, the device-local registry,
/// and the verify → stage → migrate-check → activate pipeline:
///
///     <root>/<slug>/base/<od1-hex>/dump.json (+ manifest.json)
///     <root>/<slug>/pack-<locale>/<od1-hex>/pack.json (+ manifest.json)
///     <root>/registry.json
///
/// The reader only ever touches the registry's `activeBase` pointer. Every
/// mutation is idempotent: re-running boot, refresh, download, activation,
/// or deletion converges to the same end state, and a crash at any point
/// leaves the previous version usable.
@MainActor
@Observable
final class OfflineStore {
    typealias ManifestProvider = (String?) async throws -> OfflineManifestsResponse

    private(set) var registry: OfflineRegistry
    private(set) var bases: [String: OfflineManifest] = [:]
    private(set) var packs: [String: OfflineManifest] = [:] // "slug#locale" -> manifest
    private(set) var progress: [String: Double] = [:]
    private(set) var lastError: String?

    private let rootURL: URL
    private let transport: OfflineDownloadTransport
    private let manifestProvider: ManifestProvider?
    private let appVersion: String
    /// Base URL for the pool-independent reachability probe (see
    /// OfflineProbe). When set, manifest fetches check it first so a
    /// stalled network fails the run visibly instead of queueing forever.
    private let probeBaseURL: URL?
    private let fileManager = FileManager.default
    /// One live run per collection: starting a second collection must never
    /// cancel the first. A single shared task meant only one collection
    /// could download at a time.
    private var runTasks: [String: Task<Void, Never>] = [:]
    private var dumpCache: [String: OfflineBaseDump] = [:]
    private var packCache: [String: OfflineTranslationPack] = [:]

    init(
        rootURL: URL? = nil,
        transport: OfflineDownloadTransport = URLSessionOfflineTransport(),
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
        manifestProvider: ManifestProvider? = nil,
        probeBaseURL: URL? = nil
    ) {
        let base = rootURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("offline", isDirectory: true)
        self.rootURL = base
        self.transport = transport
        self.appVersion = appVersion
        self.manifestProvider = manifestProvider
        self.probeBaseURL = probeBaseURL
        self.registry = OfflineRegistry.empty()
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        loadRegistry()
        reconcile()
    }

    // MARK: - Registry persistence (atomic)

    private var registryURL: URL { rootURL.appendingPathComponent("registry.json") }

    private func loadRegistry() {
        guard let data = try? Data(contentsOf: registryURL),
              let decoded = try? JSONDecoder().decode(OfflineRegistry.self, from: data),
              decoded.version == OfflineRegistry.currentVersion
        else {
            if fileManager.fileExists(atPath: registryURL.path) {
                let aside = rootURL.appendingPathComponent("registry.corrupt-\(Int(Date.now.timeIntervalSince1970))")
                try? fileManager.moveItem(at: registryURL, to: aside)
            }
            registry = OfflineRegistry.empty()
            rebuildRegistryByScanning()
            return
        }
        registry = decoded
    }

    private func saveRegistry() {
        guard let data = try? JSONEncoder().encode(registry) else { return }
        let tmp = registryURL.appendingPathExtension("tmp")
        do {
            try data.write(to: tmp, options: .atomic)
            _ = try? fileManager.removeItem(at: registryURL)
            try fileManager.moveItem(at: tmp, to: registryURL)
        } catch {
            try? fileManager.removeItem(at: tmp)
        }
    }

    private func setRecord(_ slug: String, _ update: (inout OfflineCollectionRecord) -> Void) {
        var record = registry.record(for: slug)
        update(&record)
        registry.collections[slug] = record
        saveRegistry()
    }

    /// A corrupt or missing registry never loses data: scan version dirs,
    /// adopt the newest decodable dump per slug as active. Staged work is
    /// dropped because its manifest pairing cannot be proven.
    private func rebuildRegistryByScanning() {
        guard let slugs = try? fileManager.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: nil
        ) else { return }
        for slugURL in slugs where slugURL.hasDirectoryPath {
            let slug = slugURL.lastPathComponent
            guard OfflineDumpValidation.validCollectionSlug(slug) else { continue }
            let baseRoot = slugURL.appendingPathComponent("base", isDirectory: true)
            guard let versions = try? fileManager.contentsOfDirectory(at: baseRoot, includingPropertiesForKeys: nil) else { continue }
            var newest: (version: String, generatedAt: Double)?
            for versionURL in versions where versionURL.hasDirectoryPath {
                let dumpURL = versionURL.appendingPathComponent("dump.json")
                guard let data = try? Data(contentsOf: dumpURL),
                      let dump = try? JSONDecoder().decode(OfflineBaseDump.self, from: data)
                else { continue }
                if newest == nil || dump.generatedAt > newest!.generatedAt {
                    newest = (dump.contentVersion, dump.generatedAt)
                }
            }
            if let newest {
                setRecord(slug) {
                    $0.activeBase = newest.version
                    $0.activeBaseGeneratedAt = newest.generatedAt
                }
            }
        }
    }

    // MARK: - Boot reconciliation (idempotent)

    /// Convergent startup: orphan `.tmp` files without a download record are
    /// removed; interrupted downloads become `paused` (partial bytes kept
    /// for resume); staged entries without their manifest pairing are
    /// re-verified or dropped. The active pointer is never touched here.
    func reconcile() {
        guard let slugs = try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil) else { return }
        for slugURL in slugs where slugURL.hasDirectoryPath {
            let slug = slugURL.lastPathComponent
            guard OfflineDumpValidation.validCollectionSlug(slug) else { continue }
            var record = registry.record(for: slug)
            if let download = record.download {
                switch download.state {
                case .downloading, .verifying, .queued:
                    record.download?.state = .paused
                    record.download?.reason = nil
                case .paused, .failed:
                    break
                }
            } else {
                removeOrphanTmpFiles(under: slugURL)
            }
            if let staged = record.stagedBase, stagedManifest(for: slug, kind: "base", version: staged) == nil {
                record.stagedBase = nil
            }
            for (locale, version) in record.stagedPacks where stagedManifest(for: slug, kind: "pack", version: version, locale: locale) == nil {
                record.stagedPacks.removeValue(forKey: locale)
            }
            registry.collections[slug] = record
        }
        saveRegistry()
    }

    private func removeOrphanTmpFiles(under slugURL: URL) {
        guard let enumerator = fileManager.enumerator(at: slugURL, includingPropertiesForKeys: nil) else { return }
        for case let url as URL in enumerator where url.pathExtension == "tmp" {
            try? fileManager.removeItem(at: url)
        }
    }

    // MARK: - Manifests

    /// Manifest fetches share the reader's bounded-wait discipline: a hung
    /// subscription must surface "could not reach the server", never a
    /// permanently queued download.
    private static let manifestTimeoutSeconds = 15.0

    private func backendUnreachable() async -> Bool {
        guard let probeBaseURL else { return false }
        return await OfflineProbe.shared.isReachable(probeBaseURL) == false
    }

    func refresh(translationLocale: String?) async {
        guard let manifestProvider else { return }
        if await backendUnreachable() {
            lastError = "You're offline. Showing your downloaded content."
            return
        }
        do {
            let response = try await OfflineModels.withFetchTimeout(seconds: Self.manifestTimeoutSeconds) {
                try await manifestProvider(translationLocale)
            }
            bases = Dictionary(uniqueKeysWithValues: response.bases.map { ($0.collectionSlug, $0) })
            var nextPacks: [String: OfflineManifest] = [:]
            for pack in response.packs {
                nextPacks[Self.packKey(slug: pack.collectionSlug, locale: pack.locale ?? translationLocale ?? "")] = pack
            }
            packs = nextPacks
            registry.lastManifestCheck = Date.now.timeIntervalSince1970
            saveRegistry()
            lastError = nil
        } catch {
            lastError = "Could not check for updates. Your downloads keep working offline."
        }
    }

    static func packKey(slug: String, locale: String) -> String { "\(slug)#\(locale)" }

    /// Test and preview support: swaps the cached manifests (as if the
    /// server published a new generation) without a network round trip.
    func noteManifests(bases: [OfflineManifest], packs: [OfflineManifest] = []) {
        for manifest in bases { self.bases[manifest.collectionSlug] = manifest }
        for manifest in packs {
            self.packs[Self.packKey(slug: manifest.collectionSlug, locale: manifest.locale ?? "")] = manifest
        }
    }

    func setWifiOnly(_ value: Bool) {
        registry.wifiOnly = value
        saveRegistry()
    }

    func baseManifest(for slug: String) -> OfflineManifest? { bases[slug] }

    func packManifest(for slug: String, locale: String) -> OfflineManifest? {
        packs[Self.packKey(slug: slug, locale: locale)]
    }

    // MARK: - Status derivation

    func status(for slug: String, translationLocale: String?) -> OfflineCollectionStatus {
        let record = registry.record(for: slug)
        if let download = record.download {
            let key = Self.progressKey(slug: slug, kind: download.kind, locale: download.locale)
            let fraction = progress[key] ?? 0
            switch download.state {
            case .queued: return .queued(progress: fraction)
            case .downloading: return .downloading(progress: fraction)
            case .paused: return .paused(progress: fraction)
            case .verifying: return .verifying
            case .failed: return .failed(reason: download.reason ?? "Download failed.")
            }
        }
        if let manifest = bases[slug],
           !OfflineModels.appVersion(appVersion, satisfiesMinimum: manifest.minAppVersion)
        {
            return .appUpdateRequired(minVersion: manifest.minAppVersion)
        }
        guard let active = record.activeBase else { return .notInstalled }
        guard let manifest = bases[slug] else {
            return .active(version: active, updateAvailable: false, stalePack: false)
        }
        let updateAvailable = manifest.contentVersion != active
        var stalePack = false
        if let locale = translationLocale,
           let activePack = record.activePacks[locale],
           let packManifest = packManifest(for: slug, locale: locale)
        {
            stalePack = packManifest.contentVersion != activePack
                || packManifest.baseContentVersion != active
        } else if translationLocale != nil, packManifest(for: slug, locale: translationLocale!) != nil,
                  record.activePacks[translationLocale!] == nil, record.activeBase != nil
        {
            stalePack = true
        }
        return .active(version: active, updateAvailable: updateAvailable, stalePack: stalePack)
    }

    // MARK: - Storage accounting

    func offlineBytes() -> Int64 {
        var total: Int64 = 0
        guard let enumerator = fileManager.enumerator(
            at: rootURL, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        for case let url as URL in enumerator {
            if url.pathExtension == "tmp" || url.lastPathComponent == "registry.json" { continue }
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    func freeBytes() -> Int64? {
        (try? rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))
            .flatMap { $0.volumeAvailableCapacityForImportantUsage.map { Int64($0) } }
    }

    /// Refuses a download the device cannot hold: the manifest bytes twice
    /// (partial `.tmp` plus verified final) plus an 8 MB headroom.
    func storageError(for manifest: OfflineManifest) -> String? {
        let need = Int64(manifest.byteSize) * 2 + 8 * 1024 * 1024
        guard let free = freeBytes() else { return nil }
        if free < need {
            return "Not enough storage: need \(OfflineModels.format(bytes: need)), \(OfflineModels.format(bytes: free)) free."
        }
        return nil
    }

    // MARK: - Download lifecycle

    static func progressKey(slug: String, kind: String, locale: String?) -> String {
        "\(slug)#\(kind)#\(locale ?? "-")"
    }

    @discardableResult
    func enqueue(slug: String, kind: String, locale: String?) -> OfflineEnqueueResult {
        let record = registry.record(for: slug)
        guard record.download == nil else { return .started }
        let manifest: OfflineManifest?
        if kind == "pack" {
            guard let locale else { return .blocked(reason: "Pick a translation language first.") }
            manifest = packManifest(for: slug, locale: locale)
            if record.activePacks[locale] == manifest?.contentVersion, manifest != nil { return .alreadyActive }
        } else {
            manifest = bases[slug]
            if record.activeBase == manifest?.contentVersion, manifest != nil { return .alreadyActive }
        }
        guard let manifest else { return .blocked(reason: "No offline file is published for this collection yet.") }
        if !OfflineModels.appVersion(appVersion, satisfiesMinimum: manifest.minAppVersion) {
            return .blocked(reason: "Update Hadithly to download this collection.")
        }
        if let active = record.activeBase, kind == "base",
           manifest.contentVersion != active,
           let activeAt = record.activeBaseGeneratedAt,
           manifest.generatedAt < activeAt
        {
            return .blocked(reason: "The server offers an older file than your installed copy. Your copy stays active.")
        }
        if let storageReason = storageError(for: manifest) {
            return .blocked(reason: storageReason)
        }
        if registry.wifiOnly {
            // The caller checks reachability before starting; the flag is
            // honored at start time, not enqueue time.
        }
        setRecord(slug) {
            $0.download = OfflineDownloadRecord(
                kind: kind, contentVersion: manifest.contentVersion,
                locale: locale, state: .queued, reason: nil,
                updatedAt: Date.now.timeIntervalSince1970
            )
        }
        startRun(slug: slug)
        return .started
    }

    func pause(slug: String) {
        guard registry.record(for: slug).download != nil else { return }
        invalidateRun(slug: slug)
        setRecord(slug) {
            if $0.download?.state == .downloading || $0.download?.state == .queued {
                $0.download?.state = .paused
            }
        }
    }

    func cancel(slug: String) {
        invalidateRun(slug: slug)
        let record = registry.record(for: slug)
        if let download = record.download {
            progress[Self.progressKey(slug: slug, kind: download.kind, locale: download.locale)] = nil
        }
        if let tmp = tmpURL(for: slug, record: record) {
            try? fileManager.removeItem(at: tmp)
        }
        setRecord(slug) { $0.download = nil }
    }

    func retry(slug: String) {
        guard var download = registry.record(for: slug).download else { return }
        download.state = .queued
        download.reason = nil
        download.updatedAt = Date.now.timeIntervalSince1970
        setRecord(slug) { $0.download = download }
        startRun(slug: slug)
    }

    /// Deletes downloaded files only. Saved items, folders, notes, reading
    /// positions, and preferences live in other stores and are untouched.
    func delete(slug: String) {
        invalidateRun(slug: slug)
        let slugURL = rootURL.appendingPathComponent(slug, isDirectory: true)
        try? fileManager.removeItem(at: slugURL)
        registry.collections.removeValue(forKey: slug)
        dumpCache.removeValue(forKey: slug)
        for key in packCache.keys where key.hasPrefix("\(slug)#") {
            packCache.removeValue(forKey: key)
        }
        saveRegistry()
    }

    /// Queues a base update and remembers the translation locale so the
    /// runner chains the matching pack update once the base is staged.
    func update(slug: String, translationLocale: String?) {
        guard registry.record(for: slug).download == nil else { return }
        enqueue(slug: slug, kind: "base", locale: translationLocale)
    }

    // MARK: - Download runner (idempotent)

    /// A cancelled run must never clobber a newer run's state (the stale
    /// catch resumes after `retry` re-queued). Every run carries the
    /// generation captured at start; stale runs exit without mutating.
    private var runGenerations: [String: Int] = [:]

    private func invalidateRun(slug: String) {
        runGenerations[slug, default: 0] += 1
        runTasks[slug]?.cancel()
        runTasks[slug] = nil
    }

    private func startRun(slug: String) {
        invalidateRun(slug: slug)
        let generation = runGenerations[slug, default: 0]
        runTasks[slug] = Task { [weak self] in
            await self?.runLoop(slug: slug, generation: generation)
            await self?.finishRun(slug: slug, generation: generation)
        }
    }

    private func finishRun(slug: String, generation: Int) {
        // Only the current run clears its own handle; a newer run's task
        // for the same slug must survive.
        if isCurrentRun(slug: slug, generation: generation) {
            runTasks[slug] = nil
        }
    }

    private func isCurrentRun(slug: String, generation: Int) -> Bool {
        runGenerations[slug, default: 0] == generation
    }

    private func runLoop(slug: String, generation: Int) async {
        guard let manifestProvider else { return }
        while let download = registry.record(for: slug).download,
              download.state == .queued,
              isCurrentRun(slug: slug, generation: generation)
        {
            if await backendUnreachable() {
                if isCurrentRun(slug: slug, generation: generation) {
                    setRecord(slug) {
                        $0.download?.state = .failed
                        $0.download?.reason = "You're offline. Reconnect and retry — your installed copy still works."
                    }
                }
                return
            }
            // Fresh signed URL: the cached manifest URL may have expired.
            // getOfflineManifests returns every base plus the packs for one
            // locale, so a single call serves both kinds. Bounded: a hung
            // subscription fails the run instead of queueing forever.
            do {
                let response = try await OfflineModels.withFetchTimeout(seconds: Self.manifestTimeoutSeconds) {
                    try await manifestProvider(download.locale)
                }
                if download.kind == "base" {
                    for manifest in response.bases { bases[manifest.collectionSlug] = manifest }
                } else {
                    for manifest in response.packs {
                        packs[Self.packKey(slug: manifest.collectionSlug, locale: manifest.locale ?? "")] = manifest
                    }
                }
            } catch {
                if isCurrentRun(slug: slug, generation: generation) {
                    setRecord(slug) {
                        $0.download?.state = .failed
                        $0.download?.reason = "Could not reach the server. Try again when you are online."
                    }
                }
                return
            }
            guard let manifest = currentManifest(for: slug, download: registry.record(for: slug).download!) else {
                if isCurrentRun(slug: slug, generation: generation) {
                    setRecord(slug) {
                        $0.download?.state = .failed
                        $0.download?.reason = "No offline file is published for this collection yet."
                    }
                }
                return
            }
            if manifest.contentVersion != download.contentVersion {
                // Server moved on mid-queue: adopt the newest manifest instead
                // of downloading a stale file.
                setRecord(slug) { $0.download?.contentVersion = manifest.contentVersion }
                continue
            }
            await downloadBytes(slug: slug, download: download, manifest: manifest, generation: generation)
            // After a base run, chain a pending pack update for the same slug
            // when its manifest targets the just-staged base.
            if download.kind == "base", let locale = download.locale ?? packLocaleHint(for: slug) {
                chainPackIfNeeded(slug: slug, locale: locale)
                if registry.record(for: slug).download != nil { continue }
            }
        }
    }

    private func packLocaleHint(for slug: String) -> String? {
        packs.keys.first { $0.hasPrefix("\(slug)#") }.map { String($0.dropFirst(slug.count + 1)) }
    }

    private func chainPackIfNeeded(slug: String, locale: String) {
        let record = registry.record(for: slug)
        guard record.download == nil,
              let pack = packManifest(for: slug, locale: locale),
              record.activePacks[locale] != pack.contentVersion,
              pack.baseContentVersion == (record.stagedBase ?? record.activeBase)
        else { return }
        setRecord(slug) {
            $0.download = OfflineDownloadRecord(
                kind: "pack", contentVersion: pack.contentVersion, locale: locale,
                state: .queued, reason: nil, updatedAt: Date.now.timeIntervalSince1970
            )
        }
    }

    private func currentManifest(for slug: String, download: OfflineDownloadRecord) -> OfflineManifest? {
        if download.kind == "pack", let locale = download.locale {
            return packManifest(for: slug, locale: locale)
        }
        return bases[slug]
    }

    private func versionDir(for slug: String, kind: String, version: String, locale: String?) -> URL {
        let leaf = kind == "pack" ? "pack-\(locale ?? "unknown")" : "base"
        return rootURL.appendingPathComponent(slug, isDirectory: true)
            .appendingPathComponent(leaf, isDirectory: true)
            .appendingPathComponent(OfflineModels.directoryName(for: version), isDirectory: true)
    }

    private func tmpURL(for slug: String, record: OfflineCollectionRecord) -> URL? {
        guard let download = record.download else { return nil }
        return versionDir(for: slug, kind: download.kind, version: download.contentVersion, locale: download.locale)
            .appendingPathComponent("download.tmp")
    }

    private func downloadBytes(slug: String, download: OfflineDownloadRecord, manifest: OfflineManifest, generation: Int) async {
        guard isCurrentRun(slug: slug, generation: generation) else { return }
        setRecord(slug) { $0.download?.state = .downloading }
        let key = Self.progressKey(slug: slug, kind: download.kind, locale: download.locale)
        let dir = versionDir(for: slug, kind: download.kind, version: download.contentVersion, locale: download.locale)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent("download.tmp")
        let offset = Int64((try? fileManager.attributesOfItem(atPath: tmp.path)[.size] as? Int) ?? 0)
        guard let url = URL(string: manifest.downloadUrl ?? "") else {
            if isCurrentRun(slug: slug, generation: generation) {
                setRecord(slug) {
                    $0.download?.state = .failed
                    $0.download?.reason = "The download link is invalid. Try again."
                }
            }
            return
        }
        do {
            let data = try await transport.download(
                from: url, resumingFrom: offset,
                progress: { [weak self] fraction in
                    Task { @MainActor in self?.progress[key] = fraction }
                }
            )
            progress[key] = 1
            let status = await transport.lastStatusCode()
            try appendOrReplace(data, at: tmp, resumingFrom: offset, statusCode: status)
            guard isCurrentRun(slug: slug, generation: generation) else { return }
            setRecord(slug) { $0.download?.state = .verifying }
            await verifyAndStage(slug: slug, download: download, manifest: manifest, tmp: tmp)
        } catch is CancellationError {
            if isCurrentRun(slug: slug, generation: generation) {
                setRecord(slug) { $0.download?.state = .paused }
            }
        } catch OfflineDownloadError.cancelled {
            if isCurrentRun(slug: slug, generation: generation) {
                setRecord(slug) { $0.download?.state = .paused }
            }
        } catch {
            if isCurrentRun(slug: slug, generation: generation) {
                setRecord(slug) {
                    $0.download?.state = .failed
                    $0.download?.reason = "The download was interrupted. Your installed copy still works."
                }
            }
        }
    }

    private func appendOrReplace(_ data: Data, at tmp: URL, resumingFrom offset: Int64, statusCode: Int) throws {
        if offset > 0, statusCode == 206, fileManager.fileExists(atPath: tmp.path) {
            let handle = try FileHandle(forWritingTo: tmp)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            // Fresh 200 (or first run): the server ignored Range, so any
            // partial file is stale and the bytes restart from zero.
            try data.write(to: tmp, options: .atomic)
        }
    }

    // MARK: - Verify, stage, activate, rollback

    private func stagedManifestURL(for slug: String, kind: String, version: String, locale: String?) -> URL {
        versionDir(for: slug, kind: kind, version: version, locale: locale)
            .appendingPathComponent("manifest.json")
    }

    private func stagedManifest(for slug: String, kind: String, version: String, locale: String? = nil) -> OfflineManifest? {
        guard let data = try? Data(contentsOf: stagedManifestURL(for: slug, kind: kind, version: version, locale: locale)) else { return nil }
        return try? JSONDecoder().decode(OfflineManifest.self, from: data)
    }

    private func verifyAndStage(slug: String, download: OfflineDownloadRecord, manifest: OfflineManifest, tmp: URL) async {
        let record = registry.record(for: slug)
        let expectedBase = download.kind == "pack"
            ? (record.stagedBase ?? record.activeBase)
            : nil
        do {
            let bytes = try Data(contentsOf: tmp)
            try manifest.assertValid(for: bytes, expectedBaseContentVersion: expectedBase)
            if download.kind == "base" {
                _ = try JSONDecoder().decode(OfflineBaseDump.self, from: bytes)
            } else {
                let pack = try JSONDecoder().decode(OfflineTranslationPack.self, from: bytes)
                let baseVersion = record.stagedBase ?? record.activeBase
                guard pack.baseContentVersion == baseVersion else {
                    throw OfflineDumpError.incompatiblePack("pack targets \(pack.baseContentVersion)")
                }
            }
            let dir = versionDir(for: slug, kind: download.kind, version: download.contentVersion, locale: download.locale)
            let finalName = download.kind == "base" ? "dump.json" : "pack.json"
            let final = dir.appendingPathComponent(finalName)
            _ = try? fileManager.removeItem(at: final)
            try fileManager.moveItem(at: tmp, to: final)
            let manifestData = try JSONEncoder().encode(manifest)
            try manifestData.write(
                to: stagedManifestURL(for: slug, kind: download.kind, version: download.contentVersion, locale: download.locale),
                options: .atomic
            )
            // Caller-supplied anchors (Saved + R1 positions) must all exist
            // in the replacement before the pointer flips. The previous
            // version stays active until this check passes.
            let anchors = pendingAnchors(for: slug)
            if download.kind == "base", !anchors.isEmpty {
                let stagedDump = try JSONDecoder().decode(OfflineBaseDump.self, from: Data(contentsOf: final))
                let ids = Set(stagedDump.hadiths.map(\.canonicalId))
                let missing = anchors.filter { !ids.contains($0) }
                if !missing.isEmpty {
                    setRecord(slug) {
                        $0.download?.state = .failed
                        $0.download?.reason = "The new file is missing \(missing.count) of your saved hadiths. Your copy stays active."
                        $0.stagedBase = nil
                    }
                    try? fileManager.removeItem(at: dir)
                    return
                }
            }
            setRecord(slug) {
                if download.kind == "base" {
                    $0.stagedBase = download.contentVersion
                } else if let locale = download.locale {
                    $0.stagedPacks[locale] = download.contentVersion
                }
                $0.download = nil
            }
            activateStaged(slug: slug)
        } catch let error as OfflineDumpError {
            setRecord(slug) {
                $0.download?.state = .failed
                switch error {
                case .checksumMismatch: $0.download?.reason = "The file failed its checksum. Your installed copy still works."
                case .unsupportedSchema: $0.download?.reason = "This file needs a newer Hadithly. Update the app and try again."
                case .incompatiblePack: $0.download?.reason = "This translation does not match the installed Arabic file."
                case .missingLicense, .unlicensedSource: $0.download?.reason = "This file's license could not be verified."
                case .badReference: $0.download?.reason = "This file failed validation. Your installed copy still works."
                }
            }
            try? fileManager.removeItem(at: tmp)
        } catch {
            setRecord(slug) {
                $0.download?.state = .failed
                $0.download?.reason = "This file failed validation. Your installed copy still works."
            }
            try? fileManager.removeItem(at: tmp)
        }
    }

    /// Anchors the UI supplies for the migration check (Saved canonical ids
    /// + R1 position anchors). Empty means "no user data to protect".
    private var anchorProviders: [String: () -> Set<String>] = [:]

    func setAnchorProvider(for slug: String, provider: @escaping () -> Set<String>) {
        anchorProviders[slug] = provider
    }

    private func pendingAnchors(for slug: String) -> Set<String> {
        anchorProviders[slug]?() ?? []
    }

    /// Flips the active pointer to the staged version. The previous version
    /// stays on disk for rollback; older generations are pruned.
    func activateStaged(slug: String) {
        var record = registry.record(for: slug)
        let previousBase = record.activeBase
        if let staged = record.stagedBase {
            record.activeBase = staged
            if let manifest = bases[slug], manifest.contentVersion == staged {
                record.activeBaseGeneratedAt = manifest.generatedAt
            } else if let manifest = stagedManifest(for: slug, kind: "base", version: staged) {
                record.activeBaseGeneratedAt = manifest.generatedAt
            }
            record.stagedBase = nil
            dumpCache.removeValue(forKey: slug)
        }
        for (locale, version) in record.stagedPacks {
            record.activePacks[locale] = version
            packCache.removeValue(forKey: "\(slug)#\(locale)")
        }
        record.stagedPacks = [:]
        registry.collections[slug] = record
        saveRegistry()
        // Keep the previous version on disk for rollback; only generations
        // older than both are pruned.
        var keep = [record.activeBase].compactMap { $0 }
        if let previous = previousBase, previous != record.activeBase {
            keep.append(previous)
        }
        prune(slug: slug, keeping: keep)
    }

    /// Rollback is a pointer flip back to the retained previous version.
    /// Used when post-activation reads prove the new bytes unreadable.
    @discardableResult
    func rollback(slug: String, to version: String) -> Bool {
        let dir = versionDir(for: slug, kind: "base", version: version, locale: nil)
        guard (try? Data(contentsOf: dir.appendingPathComponent("dump.json"))) != nil else { return false }
        setRecord(slug) {
            $0.activeBase = version
            $0.stagedBase = nil
        }
        dumpCache.removeValue(forKey: slug)
        return true
    }

    private func prune(slug: String, keeping: [String]) {
        let baseRoot = rootURL.appendingPathComponent(slug, isDirectory: true).appendingPathComponent("base", isDirectory: true)
        guard let versions = try? fileManager.contentsOfDirectory(at: baseRoot, includingPropertiesForKeys: nil) else { return }
        let keepDirs = Set(keeping.map(OfflineModels.directoryName(for:)))
        for versionURL in versions where versionURL.hasDirectoryPath {
            if !keepDirs.contains(versionURL.lastPathComponent) {
                try? fileManager.removeItem(at: versionURL)
            }
        }
    }

    // MARK: - Reader fallback (offline-tolerant, read-first)

    func loadActiveDump(slug: String) -> OfflineBaseDump? {
        if let cached = dumpCache[slug] { return cached }
        guard let version = registry.record(for: slug).activeBase else { return nil }
        let url = versionDir(for: slug, kind: "base", version: version, locale: nil).appendingPathComponent("dump.json")
        guard let data = try? Data(contentsOf: url),
              let dump = try? JSONDecoder().decode(OfflineBaseDump.self, from: data)
        else {
            // Post-activation corruption: retry the previous retained
            // version instead of serving half-usable data.
            return nil
        }
        dumpCache[slug] = dump
        return dump
    }

    func loadActivePack(slug: String, locale: String) -> OfflineTranslationPack? {
        let key = "\(slug)#\(locale)"
        if let cached = packCache[key] { return cached }
        guard let version = registry.record(for: slug).activePacks[locale] else { return nil }
        let url = versionDir(for: slug, kind: "pack", version: version, locale: locale).appendingPathComponent("pack.json")
        guard let data = try? Data(contentsOf: url),
              let pack = try? JSONDecoder().decode(OfflineTranslationPack.self, from: data)
        else { return nil }
        packCache[key] = pack
        return pack
    }

    func translation(for canonicalId: String, slug: String, locale: String) -> String? {
        loadActivePack(slug: slug, locale: locale)?.entries.first { $0.canonicalId == canonicalId }?.content
    }

    func offlineHadith(canonicalId: String, slug: String, locale: String?) -> ReaderHadith? {
        guard let dump = loadActiveDump(slug: slug),
              let row = dump.hadiths.first(where: { $0.canonicalId == canonicalId })
        else { return nil }
        return readerHadith(from: row, packContent: locale.flatMap { translation(for: canonicalId, slug: slug, locale: $0) })
    }

    func readerHadith(from row: OfflineDumpHadith, packContent: String?) -> ReaderHadith {
        ReaderHadith(
            _id: row.canonicalId,
            provider: row.provider,
            canonicalId: row.canonicalId,
            providerHadithId: row.providerHadithId,
            collectionSlug: row.collectionSlug,
            volumeId: row.volumeId,
            chapterId: row.chapterId,
            arabicText: row.arabicText,
            englishText: packContent ?? row.englishText,
            narrator: row.narrator,
            narratorAr: row.narratorAr,
            referenceDisplay: row.referenceDisplay,
            collectionName: row.collectionName,
            chapterName: row.chapterName,
            authenticity: ReaderAuthenticity(
                kind: row.authenticity.kind,
                normalizedGrade: row.authenticity.normalizedGrade,
                claimScope: row.authenticity.claimScope,
                sourceLabel: row.authenticity.sourceLabel,
                sourceName: row.authenticity.sourceName,
                sourceUrl: row.authenticity.sourceUrl,
                verificationMethod: row.authenticity.verificationMethod
            )
        )
    }

    /// Offline page with the same content-sized chunking as the server, over
    /// dotted-id-ordered volume hadiths. R1 positions restore by semantic
    /// anchor, so approximate page numbers never strand the reader.
    func offlinePage(slug: String, volumeId: String?, page: Int, locale: String?) -> ReaderPageResult? {
        guard let dump = loadActiveDump(slug: slug) else { return nil }
        let rows = dump.hadiths
            .filter { volumeId == nil || $0.volumeId == volumeId }
            .sorted { OfflineModels.compareProviderHadithIds($0.providerHadithId, $1.providerHadithId) }
        guard !rows.isEmpty else { return nil }
        let chunks = OfflineModels.chunkHadiths(
            rows,
            arabicText: \.arabicText,
            englishText: { $0.englishText },
            narrator: { $0.narrator },
            narratorAr: { $0.narratorAr }
        )
        let index = max(0, min(page, chunks.count - 1))
        let items = chunks[index].map { row in
            readerHadith(
                from: row,
                packContent: locale.flatMap { l in translation(for: row.canonicalId, slug: slug, locale: l) }
            )
        }
        // contentVersion/pageKey stay nil so R1 positions record "legacy":
        // offline chunking is approximate (not the server's cv1 versions),
        // and restoration resolves semantically through the exact
        // canonical anchor. Claiming the dump's od1: version here crashed
        // position saves against the R1 wire contract on device.
        return ReaderPageResult(
            items: items, page: index + 1, pageSize: items.count,
            totalPages: chunks.count, hasMore: index + 1 < chunks.count,
            contentVersion: nil, paginationVersion: 1, pageKey: nil
        )
    }

    /// Outline synthesized from the dump's own volume ids and counts. Titles
    /// fall back to the volume id: Hadithly never invents chapter names, and
    /// offline volume titles are no exception.
    func offlineOutline(slug: String) -> CollectionOutlineResult? {
        guard let dump = loadActiveDump(slug: slug) else { return nil }
        var counts: [String: Int] = [:]
        var order: [String] = []
        for row in dump.hadiths {
            let volume = row.volumeId ?? "1"
            if counts[volume] == nil { order.append(volume) }
            counts[volume, default: 0] += 1
        }
        let volumes = order.map { volume in
            OutlineVolume(
                volumeId: volume, title: volume,
                firstChapterTitle: nil, hadithCount: counts[volume] ?? 0, chapters: []
            )
        }
        return CollectionOutlineResult(volumes: volumes)
    }

    func isCollectionActive(_ slug: String) -> Bool {
        registry.record(for: slug).activeBase != nil
    }
}
