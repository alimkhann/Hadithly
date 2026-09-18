import Foundation

/// O2 download-management domain. Mirrors `backend/convex/lib/offlineDumps.ts`
/// for identity rules and `chunkReaderHadiths` for offline paging. Pure and
/// testable: no URLSession, no Convex, no UI.
enum OfflineDownloadState: String, Codable, Equatable, Sendable {
    case queued
    case downloading
    case paused
    case verifying
    case failed
}

/// One in-flight or interrupted download. Persisted in the registry so a
/// crash or process death resumes (or cleanly restarts) instead of leaving
/// a half-written file the reader could mistake for data.
struct OfflineDownloadRecord: Codable, Equatable, Sendable {
    var kind: String // "base" or "pack"
    var contentVersion: String
    var locale: String?
    var state: OfflineDownloadState
    var reason: String?
    var updatedAt: Double
}

/// Per-collection registry entry. `activeBase` is the only version the
/// reader may touch. `stagedBase` holds a verified replacement until the
/// position-migration check passes and the pointer flips. The previous
/// active version stays on disk until the next successful activation, so
/// rollback is a pointer flip, never a re-download.
struct OfflineCollectionRecord: Codable, Equatable, Sendable {
    var activeBase: String?
    var activeBaseGeneratedAt: Double?
    var activePacks: [String: String] // locale -> contentVersion
    var stagedBase: String?
    var stagedPacks: [String: String]
    var download: OfflineDownloadRecord?
}

/// Device-local registry. Never synced, never exported, never merged:
/// download choices stay on the device.
struct OfflineRegistry: Codable, Equatable, Sendable {
    static let currentVersion = 1.0

    var version: Double
    var wifiOnly: Bool
    var lastManifestCheck: Double?
    var collections: [String: OfflineCollectionRecord]

    static func empty() -> OfflineRegistry {
        OfflineRegistry(version: currentVersion, wifiOnly: true, lastManifestCheck: nil, collections: [:])
    }

    func record(for slug: String) -> OfflineCollectionRecord {
        collections[slug] ?? OfflineCollectionRecord(
            activeBase: nil, activeBaseGeneratedAt: nil,
            activePacks: [:], stagedBase: nil, stagedPacks: [:], download: nil
        )
    }
}

/// User-facing status derived from registry + manifests. The UI renders
/// this; it never stores UI state back into the registry.
enum OfflineCollectionStatus: Equatable, Sendable {
    case notInstalled
    case queued(progress: Double)
    case downloading(progress: Double)
    case paused(progress: Double)
    case verifying
    case failed(reason: String)
    case active(version: String, updateAvailable: Bool, stalePack: Bool)
    case appUpdateRequired(minVersion: String)
}

enum OfflineModels {
    /// Sanitizes `od1:<hex>` for use as a directory name.
    static func directoryName(for contentVersion: String) -> String {
        contentVersion.replacingOccurrences(of: ":", with: "-")
    }

    /// Compares dotted-decimal provider hadith ids ("2" < "4.5" < "10").
    /// Mirrors `compareProviderHadithIds` on the backend.
    static func compareProviderHadithIds(_ left: String, _ right: String) -> Bool {
        let lParts = left.split(separator: ".").compactMap { Int($0) }
        let rParts = right.split(separator: ".").compactMap { Int($0) }
        for index in 0 ..< max(lParts.count, rParts.count) {
            let l = index < lParts.count ? lParts[index] : 0
            let r = index < rParts.count ? rParts[index] : 0
            if l != r { return l < r }
        }
        return false
    }

    /// Mirrors `chunkReaderHadiths`: at most 10 items or 5,200 chars per
    /// page so offline pages match the server's content-sized paging.
    static func chunkHadiths<T>(
        _ items: [T],
        arabicText: (T) -> String,
        englishText: (T) -> String?,
        narrator: (T) -> String?,
        narratorAr: (T) -> String?
    ) -> [[T]] {
        let maxItems = 10
        let maxChars = 5200
        var pages: [[T]] = []
        var current: [T] = []
        var currentChars = 0
        for item in items {
            let itemChars = arabicText(item).count + (englishText(item)?.count ?? 0)
                + (narrator(item)?.count ?? 0) + (narratorAr(item)?.count ?? 0)
            if !current.isEmpty, current.count >= maxItems || currentChars + itemChars > maxChars {
                pages.append(current)
                current = []
                currentChars = 0
            }
            current.append(item)
            currentChars += itemChars
        }
        if !current.isEmpty { pages.append(current) }
        return pages
    }

    /// Compares semantic versions ("0.2.0" > "0.1.0"). Non-numeric parts
    /// compare as 0 so a malformed string fails closed toward "older".
    static func compareAppVersions(_ left: String, _ right: String) -> ComparisonResult {
        let lParts = left.split(separator: ".").map { Int($0) ?? 0 }
        let rParts = right.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0 ..< max(lParts.count, rParts.count) {
            let l = index < lParts.count ? lParts[index] : 0
            let r = index < rParts.count ? rParts[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    /// True when the running app satisfies the manifest's minimum version.
    static func appVersion(_ current: String, satisfiesMinimum minimum: String) -> Bool {
        compareAppVersions(current, minimum) != .orderedAscending
    }

    static func format(bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }

    /// Bounds a network fetch so a hung socket cannot strand the reader on
    /// a spinner when a verified dump is on disk. The winner's value (or
    /// error) is returned; the loser is cancelled.
    static func withFetchTimeout<T: Sendable>(
        seconds: Double,
        work: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw OfflineFetchTimeout.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw OfflineFetchTimeout.timedOut
            }
            return first
        }
    }
}

enum OfflineFetchTimeout: Error {
    case timedOut
}


