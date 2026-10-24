import Foundation
import Combine
import Observation
import CryptoKit
import CoreFoundation

/// The merge request sent to `guestMerge:mergeGuestData`. Timestamps are
/// milliseconds since the Unix epoch, which is what Convex stores.
struct GuestMergePayload: Equatable, Sendable {
    struct Bookmark: Equatable, Sendable {
        let hadithId: String
        let createdAt: Double
    }

    struct Note: Equatable, Sendable {
        let hadithId: String
        let content: String
        let createdAt: Double
        let updatedAt: Double
    }

    struct Favorite: Equatable, Sendable {
        let hadithId: String
        let createdAt: Double
    }

    struct SavedFolder: Equatable, Sendable {
        let localId: String
        let name: String
        let createdAt: Double
    }

    struct SavedItem: Equatable, Sendable {
        let hadithId: String
        let bookmarkCreatedAt: Double?
        let favoriteCreatedAt: Double?
        let noteContent: String?
        let noteCreatedAt: Double?
        let noteUpdatedAt: Double?
        let folderLocalId: String?
        let createdAt: Double
        let updatedAt: Double
        var folderUpdatedAt: Double? = nil
    }

    enum Progress: Equatable, Sendable {
        case current(ReadingPosition)
        case legacy(collectionSlug: String, hadithId: String, updatedAt: Double)

        var collectionSlug: String {
            switch self {
            case .current(let position): position.anchor.collectionSlug
            case .legacy(let collectionSlug, _, _): collectionSlug
            }
        }

        var hadithId: String? {
            if case .legacy(_, let hadithId, _) = self { return hadithId }
            return nil
        }

        var position: ReadingPosition? {
            if case .current(let position) = self { return position }
            return nil
        }

        var updatedAt: Double {
            switch self {
            case .current(let position): position.updatedAt
            case .legacy(_, _, let updatedAt): updatedAt
            }
        }
    }

    let bookmarks: [Bookmark]
    let notes: [Note]
    var favorites: [Favorite]
    var readingProgress: [Progress]
    var savedFolders: [SavedFolder]
    var savedItems: [SavedItem]

    init(
        bookmarks: [Bookmark],
        notes: [Note],
        favorites: [Favorite] = [],
        readingProgress: [Progress] = [],
        savedFolders: [SavedFolder] = [],
        savedItems: [SavedItem] = []
    ) {
        self.bookmarks = bookmarks
        self.notes = notes
        self.favorites = favorites
        self.readingProgress = readingProgress
        self.savedFolders = savedFolders
        self.savedItems = savedItems
    }

    var isEmpty: Bool {
        bookmarks.isEmpty && notes.isEmpty && favorites.isEmpty && readingProgress.isEmpty && savedFolders.isEmpty && savedItems.isEmpty
    }
}

/// Builds the merge payload from local guest data. Pure and deterministic so
/// the rules (dedupe, invalid-id filtering, ordering) are unit-testable
/// without SwiftData or networking.
enum GuestMergePlanner {
    /// Convex document ids are fixed-length lowercase alphanumeric strings.
    /// Anything else cannot reference a hadith and would make the whole
    /// mutation fail Convex's validator, so those items are dropped here.
    static func isValidHadithId(_ id: String) -> Bool {
        !id.isEmpty
            && id.count == 32
            && id.allSatisfy { $0.isLowercase || $0.isNumber }
    }

    static func makePayload(
        bookmarks: [GuestBookmarkDraft],
        notes: [GuestNoteDraft],
        favorites: [GuestFavoriteDraft] = [],
        progress: [GuestReadingProgressDraft] = [],
        folders: [GuestSavedFolderDraft] = [],
        memberships: [GuestSavedMembershipDraft] = []
    ) -> GuestMergePayload {
        let validBookmarks = dedupeBookmarks(bookmarks.filter { isValidHadithId($0.hadithId) })
        let validNotes = dedupeNotes(notes.filter { isValidHadithId($0.hadithId) })
        let validFavorites = dedupeFavorites(favorites.filter { isValidHadithId($0.hadithId) })
        let validProgress = dedupeProgress(progress.filter {
            $0.readingPosition != nil || isValidHadithId($0.hadithId)
        })
        let validFolders = folders.filter { GuestDataStore.validFolderName($0.name) }
        let folderIds = Set(validFolders.map(\.localId))
        let membershipByHadith = Dictionary(uniqueKeysWithValues: memberships
            .filter { isValidHadithId($0.hadithId) && folderIds.contains($0.folderLocalId) }
            .map { ($0.hadithId, $0) })
        var savedByHadith: [String: GuestMergePayload.SavedItem] = [:]
        for bookmark in validBookmarks {
            savedByHadith[bookmark.hadithId] = .init(hadithId: bookmark.hadithId, bookmarkCreatedAt: bookmark.createdAt.millisecondsSinceEpoch, favoriteCreatedAt: nil, noteContent: nil, noteCreatedAt: nil, noteUpdatedAt: nil, folderLocalId: nil, createdAt: bookmark.createdAt.millisecondsSinceEpoch, updatedAt: bookmark.createdAt.millisecondsSinceEpoch)
        }
        for favorite in validFavorites {
            let stamp = favorite.createdAt.millisecondsSinceEpoch
            let previous = savedByHadith[favorite.hadithId]
            savedByHadith[favorite.hadithId] = .init(hadithId: favorite.hadithId, bookmarkCreatedAt: previous?.bookmarkCreatedAt, favoriteCreatedAt: stamp, noteContent: previous?.noteContent, noteCreatedAt: previous?.noteCreatedAt, noteUpdatedAt: previous?.noteUpdatedAt, folderLocalId: nil, createdAt: min(previous?.createdAt ?? stamp, stamp), updatedAt: max(previous?.updatedAt ?? stamp, stamp))
        }
        for note in validNotes {
            let createdAt = note.createdAt.millisecondsSinceEpoch
            let updatedAt = note.updatedAt.millisecondsSinceEpoch
            let previous = savedByHadith[note.hadithId]
            savedByHadith[note.hadithId] = .init(hadithId: note.hadithId, bookmarkCreatedAt: previous?.bookmarkCreatedAt, favoriteCreatedAt: previous?.favoriteCreatedAt, noteContent: note.content, noteCreatedAt: createdAt, noteUpdatedAt: updatedAt, folderLocalId: nil, createdAt: min(previous?.createdAt ?? createdAt, createdAt), updatedAt: max(previous?.updatedAt ?? updatedAt, updatedAt))
        }

        return GuestMergePayload(
            bookmarks: validBookmarks
                .sorted { $0.createdAt < $1.createdAt }
                .map { .init(hadithId: $0.hadithId, createdAt: $0.createdAt.millisecondsSinceEpoch) },
            notes: validNotes
                .sorted { $0.updatedAt < $1.updatedAt }
                .map {
                    .init(
                        hadithId: $0.hadithId,
                        content: $0.content,
                        createdAt: $0.createdAt.millisecondsSinceEpoch,
                        updatedAt: $0.updatedAt.millisecondsSinceEpoch
                    )
                },
            favorites: validFavorites
                .sorted { $0.createdAt < $1.createdAt }
                .map { .init(hadithId: $0.hadithId, createdAt: $0.createdAt.millisecondsSinceEpoch) },
            readingProgress: validProgress
                .sorted { $0.effectiveUpdatedAt < $1.effectiveUpdatedAt }
                .map { draft in
                    if let position = draft.readingPosition {
                        return .current(position)
                    }
                    return .legacy(
                        collectionSlug: draft.collectionSlug,
                        hadithId: draft.hadithId,
                        updatedAt: draft.updatedAt.millisecondsSinceEpoch
                    )
                }
            ,
            savedFolders: validFolders.sorted { $0.localId < $1.localId }.map { .init(localId: $0.localId, name: $0.name, createdAt: $0.createdAt.millisecondsSinceEpoch) },
            savedItems: savedByHadith.values.map { item in
                .init(hadithId: item.hadithId, bookmarkCreatedAt: item.bookmarkCreatedAt, favoriteCreatedAt: item.favoriteCreatedAt, noteContent: item.noteContent, noteCreatedAt: item.noteCreatedAt, noteUpdatedAt: item.noteUpdatedAt, folderLocalId: membershipByHadith[item.hadithId]?.folderLocalId, createdAt: item.createdAt, updatedAt: item.updatedAt, folderUpdatedAt: membershipByHadith[item.hadithId]?.updatedAt?.millisecondsSinceEpoch)
            }.sorted { $0.hadithId < $1.hadithId }
        )
    }

    /// The same hadith bookmarked twice keeps its earliest record.
    private static func dedupeBookmarks(_ bookmarks: [GuestBookmarkDraft]) -> [GuestBookmarkDraft] {
        var earliestByHadith: [String: GuestBookmarkDraft] = [:]
        for bookmark in bookmarks {
            let existing = earliestByHadith[bookmark.hadithId]
            if existing == nil || bookmark.createdAt < existing!.createdAt {
                earliestByHadith[bookmark.hadithId] = bookmark
            }
        }
        return Array(earliestByHadith.values)
    }

    /// The same hadith noted twice keeps the most recently edited version.
    private static func dedupeNotes(_ notes: [GuestNoteDraft]) -> [GuestNoteDraft] {
        var latestByHadith: [String: GuestNoteDraft] = [:]
        for note in notes {
            let existing = latestByHadith[note.hadithId]
            if existing == nil || note.updatedAt > existing!.updatedAt {
                latestByHadith[note.hadithId] = note
            }
        }
        return Array(latestByHadith.values)
    }

    /// The same hadith favorited twice keeps its earliest record.
    private static func dedupeFavorites(_ favorites: [GuestFavoriteDraft]) -> [GuestFavoriteDraft] {
        var earliestByHadith: [String: GuestFavoriteDraft] = [:]
        for favorite in favorites {
            let existing = earliestByHadith[favorite.hadithId]
            if existing == nil || favorite.createdAt < existing!.createdAt {
                earliestByHadith[favorite.hadithId] = favorite
            }
        }
        return Array(earliestByHadith.values)
    }

    /// One entry per collection, keeping the newest position.
    private static func dedupeProgress(
        _ progress: [GuestReadingProgressDraft]
    ) -> [GuestReadingProgressDraft] {
        var latestByCollection: [String: GuestReadingProgressDraft] = [:]
        for entry in progress {
            let existing = latestByCollection[entry.collectionSlug]
            if existing == nil || entry.effectiveUpdatedAt > existing!.effectiveUpdatedAt {
                latestByCollection[entry.collectionSlug] = entry
            }
        }
        return Array(latestByCollection.values)
    }
}

extension Date {
    var millisecondsSinceEpoch: Double {
        timeIntervalSince1970 * 1000
    }
}

struct LibrarySyncOwner: Codable, Equatable, Sendable {
    let key: String
    let subject: String
    var namespace: String = "fixture"
    var storageKey: String { namespace + "|" + key }
}

enum LibraryLocalSource: Codable, Equatable, Sendable {
    case bookmark(GuestBookmarkDraft)
    case favorite(GuestFavoriteDraft)
    case note(GuestNoteDraft)
    case folder(GuestSavedFolderDraft)
    case membership(GuestSavedMembershipDraft)
    case position(GuestReadingProgressDraft)
    case account(HadithRef?)
}

struct LibraryLocalChange: Codable, Equatable, Sendable {
    let operation: SyncOperation
    let source: LibraryLocalSource
    init(operation: SyncOperation, source: LibraryLocalSource) { self.operation = operation; self.source = source }
    init(command: SyncCommand, at: Double, source: LibraryLocalSource) {
        operation = SyncOperation(id: UUID().uuidString, revision: UUID().uuidString, at: at, command: command)
        self.source = source
    }
}

struct LibraryFrozenBatch: Codable, Equatable, Sendable {
    let batch: SyncBatch
    let changes: [LibraryLocalChange]
}

enum LibraryRecovery: Codable, Equatable, Sendable {
    case invalid(LibraryLocalSource)
    case server(LibraryLocalChange, SyncOutcome)
    case historical(LibraryLocalChange)
    case rejected(LibraryLocalChange)
    case outcome(authority: LibraryOutcomeBinding, checkpoint: LibraryOutcomeCheckpoint, original: LibraryLocalChange?)
}

struct LibraryRecentReceipt: Codable, Equatable, Sendable {
    let receipt: SyncReceipt
    let expiresAt: Double
}

enum LibrarySyncAdmission {
    static func accepts(_ frozen: LibraryFrozenBatch, now: Double = Date.now.millisecondsSinceEpoch) -> Bool {
        guard accepts(frozen.batch, now: now), frozen.changes.map(\.operation) == frozen.batch.operations else { return false }
        return frozen.changes.allSatisfy { change in
            if case .membership(let draft) = change.source, draft.updatedAt == nil,
               case .membershipPut(let command) = change.operation.command {
                return command.mode == "claim_if_unset"
            }
            return true
        }
    }

    static func accepts(_ batch: SyncBatch, now: Double = Date.now.millisecondsSinceEpoch) -> Bool {
        func identifier(_ value: String) -> Bool { value.range(of: "^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$", options: .regularExpression) != nil }
        guard identifier(batch.id), !batch.operations.isEmpty, batch.operations.count <= LibrarySyncLimits.operations,
              Set(batch.operations.map(\.id)).count == batch.operations.count,
              let data = try? JSONEncoder().encode(batch), data.count <= LibrarySyncLimits.bytes else { return false }
        var fanout = 0
        for operation in batch.operations {
            guard identifier(operation.id), identifier(operation.revision), accepts(operation.command, at: operation.at, now: now) else { return false }
            switch operation.command { case .folderDelete, .folderRestore: fanout += 1; default: break }
        }
        return fanout <= LibrarySyncLimits.fanoutOperations
    }

    static func accepts(_ command: SyncCommand, at: Double, now: Double = Date.now.millisecondsSinceEpoch) -> Bool {
        func time(_ value: Double) -> Bool { value.isFinite && value >= 0 && value <= now + 300_000 }
        func target(_ value: String) -> Bool { !value.isEmpty && value.utf16.count <= 128 }
        func key(_ value: String) -> Bool { value.range(of: "^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$", options: .regularExpression) != nil }
        func note(_ value: String) -> Bool { !value.isEmpty && value.utf8.count <= LibrarySyncLimits.noteBytes }
        func folder(_ value: SyncFolderReference) -> Bool {
            switch value { case .none: true; case .server(let value): target(value.id); case .local(let value): key(value.key) }
        }
        guard time(at) else { return false }
        switch command {
        case .bookmarkAdd(let value): return target(value.hadithId) && time(value.createdAt)
        case .favoriteAdd(let value): return target(value.hadithId) && time(value.createdAt)
        case .bookmarkRemove(let value): return target(value.hadithId)
        case .favoriteRemove(let value): return target(value.hadithId)
        case .notePut(let value): return target(value.hadithId) && note(value.content) && time(value.createdAt) && time(value.updatedAt)
        case .noteRemove(let value): return target(value.hadithId)
        case .folderCreate(let value): return key(value.key) && GuestDataStore.validFolderName(value.name)
        case .folderDelete(let value): if case .none = value.folder { return false }; return folder(value.folder)
        case .membershipPut(let value):
            guard target(value.hadithId), folder(value.folder), value.mode == nil || value.mode == "claim_if_unset" else { return false }
            if value.mode != nil, case .none = value.folder { return false }
            return true
        case .positionPut(let value):
            guard time(value.position.updatedAt), let data = try? JSONEncoder().encode(value.position), (try? JSONDecoder().decode(ReadingPosition.self, from: data)) != nil else { return false }
            return true
        case .legacyPositionPut(let value): return target(value.hadithId) && time(value.updatedAt)
        case .facetRestore(let value):
            guard target(value.hadithId), key(value.deletionId) else { return false }
            switch value.value { case .bookmark(let value): return time(value.createdAt); case .favorite(let value): return time(value.createdAt); case .note(let value): return note(value.content) && time(value.createdAt) && time(value.updatedAt) }
        case .folderRestore(let value): return key(value.deletionId) && GuestDataStore.validFolderName(value.name) && value.hadithIds.count <= 500 && Set(value.hadithIds).count == value.hadithIds.count && value.hadithIds.allSatisfy(target)
        }
    }
}

struct LibraryConfirmedChange: Codable, Equatable, Sendable {
    let change: LibraryLocalChange
    let outcome: SyncOutcome
    let version: Double
}

extension SyncCommand {
    var isPositionChange: Bool {
        switch self { case .positionPut, .legacyPositionPut: true; default: false }
    }
}

extension SyncOutstanding {
    var committedValue: SyncCommitted? { if case .committed(let value) = self { value.committed } else { nil } }
    var pendingValue: SyncPending? { if case .pending(let value) = self { value.pending } else { nil } }
}

extension SyncPending {
    func matches(_ other: SyncPending) -> Bool {
        clientKey == other.clientKey && sequence == other.sequence && batchId == other.batchId && digest == other.digest && intentDigest == other.intentDigest && manifestId == other.manifestId && generation == other.generation
    }
}

extension SyncBatch {
    func intentDigest() throws -> String { try LibrarySemanticFingerprint.digest(self, domain: "library-intent-v1:") }
}

enum LibrarySemanticFingerprint {
    static func digest<T: Encodable>(_ input: T, domain: String) throws -> String {
        func encode(_ value: Any) throws -> String {
            if value is NSNull { return "z" }
            if let text = value as? String { return "s\(text.utf8.count):" + text }
            if let number = value as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "t" : "f" }
                let number = number.doubleValue
                guard number.isFinite else { throw LibrarySyncFailure.invalidReceipt }
                return "n" + String(format: "%016llx", number == 0 ? UInt64(0) : number.bitPattern)
            }
            if let array = value as? [Any] { return "a\(array.count):" + (try array.map(encode).joined()) }
            if let object = value as? [String: Any] {
                return "o\(object.count):" + (try object.sorted { $0.key < $1.key }.map { key, child in try encode(key) + encode(child) }.joined())
            }
            throw LibrarySyncFailure.invalidReceipt
        }
        let value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(input))
        return SHA256.hash(data: Data((domain + (try encode(value))).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct LibraryOutcomeCounts: Codable, Equatable, Sendable {
    var deleted = 0, restored = 0, superseded = 0, missing = 0
    var valid: Bool { [deleted, restored, superseded, missing].allSatisfy { $0 >= 0 && $0 < 9_007_199_254_740_991 } }
    var total: Int { deleted + restored + superseded + missing }
    mutating func add(_ rows: [SyncOutcomeMember]) {
        for row in rows {
            switch row.disposition {
            case .deleted: deleted += 1
            case .restored: restored += 1
            case .superseded: superseded += 1
            case .missing: missing += 1
            }
        }
    }
    func fits(_ expected: Self) -> Bool {
        deleted <= expected.deleted && restored <= expected.restored && superseded <= expected.superseded && missing <= expected.missing
    }
}

enum LibraryOutcomeStatus: Codable, Equatable, Sendable {
    case collecting, verifying(LibraryOutcomeCounts), complete, unavailable(SyncOutcomePageUnavailableReason)
}
struct LibraryOutcomeRetention: Codable, Equatable, Sendable {
    static let duration: Double = 30 * 24 * 60 * 60 * 1_000
    let acknowledgedAt: Double
    var removed: Int?
    func valid(total: Int) -> Bool { acknowledgedAt.isFinite && acknowledgedAt >= 0 && (removed.map { $0 >= 0 && $0 <= total } ?? true) }
}
struct LibraryOutcomeCheckpoint: Codable, Equatable, Sendable {
    var counts = LibraryOutcomeCounts()
    var status = LibraryOutcomeStatus.collecting
    var retention: LibraryOutcomeRetention?
    var next: Int { counts.total }
}

extension SyncCommitted {
    var needsOutcomeCollection: Bool {
        reply.receipts.contains { receipt in
            switch receipt.outcome { case .folderDeletedManifest, .folderRestoredManifest: true; default: false }
        }
    }
}

struct LibraryManifestProof {
    let request: SyncOutcomePageRequest
    let expected: LibraryOutcomeCounts
    let receipt: SyncReceipt
    init(_ committed: SyncCommitted) throws {
        func identifier(_ value: String) -> Bool { !value.isEmpty && value.utf8.count <= 128 }
        func count(_ value: Double) throws -> Int {
            guard value.isFinite, value >= 0, value.rounded(.down) == value, value < 9_007_199_254_740_991 else { throw LibrarySyncFailure.invalidReceipt }
            return Int(value)
        }
        guard [committed.clientKey, committed.digest, committed.reply.batchId].allSatisfy(identifier),
              committed.sequence >= 1, try count(committed.sequence) > 0,
              try count(committed.revision.saved) >= 0,
              committed.reply.receipts.count == 1, let receipt = committed.reply.receipts.first,
              [receipt.id, receipt.revision].allSatisfy(identifier) else { throw LibrarySyncFailure.invalidReceipt }
        let manifest: String, generation: String, phase: SyncOutcomePageRequestPhase, expected: LibraryOutcomeCounts
        switch receipt.outcome {
        case .folderDeletedManifest(let value):
            guard value.deletedAt.isFinite, value.deletedAt >= 0 else { throw LibrarySyncFailure.invalidReceipt }
            manifest = value.manifestId; generation = value.generation; phase = .delete
            expected = .init(deleted: try count(value.count))
        case .folderRestoredManifest(let value):
            guard identifier(value.folderId) else { throw LibrarySyncFailure.invalidReceipt }
            manifest = value.manifestId; generation = value.generation; phase = .restore
            expected = .init(restored: try count(value.restored), superseded: try count(value.superseded), missing: try count(value.missing))
        default: throw LibrarySyncFailure.invalidReceipt
        }
        guard identifier(manifest), identifier(generation), expected.total < 9_007_199_254_740_991 else { throw LibrarySyncFailure.invalidReceipt }
        self.expected = expected; self.receipt = receipt
        request = .init(proof: .init(clientKey: committed.clientKey, sequence: committed.sequence, batchId: committed.reply.batchId, digest: committed.digest),
            receiptId: receipt.id, manifestId: manifest, generation: generation, phase: phase, start: 0)
    }
}

enum LibraryOutcomeOrigin: Codable, Equatable, Sendable { case matched(intentDigest: String), historical }
struct LibraryPendingOutcome: Codable, Equatable, Sendable {
    let committed: SyncCommitted
    let origin: LibraryOutcomeOrigin
}

struct LibraryOutcomeBinding: Codable, Equatable, Sendable {
    let owner: LibrarySyncOwner
    let committed: SyncCommitted
    let request: SyncOutcomePageRequest
    let expected: LibraryOutcomeCounts
    let key: String
    var scopeKey: String { Self.hash([owner.namespace, owner.subject, owner.key]) }

    init(owner: LibrarySyncOwner, committed: SyncCommitted) throws {
        guard committed.reply.ownerKey == owner.key else { throw LibrarySyncFailure.ownerMismatch }
        guard [owner.key, owner.subject, owner.namespace].allSatisfy({ !$0.isEmpty }) else { throw LibrarySyncFailure.invalidReceipt }
        let proof = try LibraryManifestProof(committed)
        self.owner = owner; self.committed = committed; expected = proof.expected; request = proof.request
        key = Self.hash([owner.namespace, owner.subject, owner.key, committed.clientKey, String(Int(committed.sequence)), committed.reply.batchId,
            committed.digest, proof.receipt.id, proof.receipt.revision, request.manifestId, request.generation, request.phase.rawValue])
    }
    private enum CodingKeys: String, CodingKey { case owner, committed }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(owner: values.decode(LibrarySyncOwner.self, forKey: .owner), committed: values.decode(SyncCommitted.self, forKey: .committed))
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(owner, forKey: .owner); try values.encode(committed, forKey: .committed)
    }
    static func hash(_ values: [String]) -> String {
        let input = values.map { "\($0.utf8.count):\($0)" }.joined()
        return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func pageRequest(start: Int) -> SyncOutcomePageRequest {
        .init(proof: request.proof, receiptId: request.receiptId, manifestId: request.manifestId, generation: request.generation, phase: request.phase, start: Double(start))
    }
    func ordinalKey(_ ordinal: Int) -> String {
        let digits = String(ordinal)
        return key + ":" + String(repeating: "0", count: 16 - digits.count) + digits
    }
    func validate(_ page: SyncOutcomePage, requested: SyncOutcomePageRequest) throws -> [SyncOutcomeMember] {
        guard requested.start.isFinite, requested.start >= 0, requested.start.rounded(.down) == requested.start, requested.start <= Double(expected.total),
              requested == pageRequest(start: Int(requested.start)),
              try JSONEncoder().encode(page).count <= LibrarySyncLimits.outcomeBytes else { throw LibrarySyncFailure.invalidReceipt }
        switch page {
        case .unavailable(let value):
            guard value.ownerKey == owner.key, value.request == requested else { throw LibrarySyncFailure.invalidReceipt }
            return []
        case .page(let value):
            guard value.ownerKey == owner.key, value.request == requested,
                  value.rows.count == min(LibrarySyncLimits.outcomePage, expected.total - Int(requested.start)),
                  value.next == requested.start + Double(value.rows.count), value.done == (value.next == Double(expected.total)),
                  Set(value.rows.map(\.memberId)).count == value.rows.count,
                  Set(value.rows.map(\.hadithId)).count == value.rows.count else { throw LibrarySyncFailure.invalidReceipt }
            for (index, row) in value.rows.enumerated() {
                guard row.ordinal == requested.start + Double(index), !row.memberId.isEmpty, row.memberId.utf8.count <= 128,
                      !row.hadithId.isEmpty, row.hadithId.utf8.count <= 128,
                      (request.phase == .delete) == (row.disposition == .deleted) else { throw LibrarySyncFailure.invalidReceipt }
            }
            return value.rows
        }
    }
}

struct LibraryOutcomeEvidencePage: Codable, Equatable, Sendable {
    let binding: LibraryOutcomeBinding
    let checkpoint: LibraryOutcomeCheckpoint
    let rows: [SyncOutcomeMember]
    let next: Int
    let endOfCollectedPrefix: Bool
}

enum LibraryOutcomeInventoryProgress: Codable { case scanning(after: String), reconciling(after: String), ready }
enum LibraryOutcomeExportVersion: Equatable, Sendable { case empty, present(epoch: String, revision: Int) }
struct LibraryOutcomeExportFence: Equatable, Sendable {
    let owner: LibrarySyncOwner
    let version: LibraryOutcomeExportVersion
}
struct LibraryOutcomeExportEntry: Equatable, Sendable {
    let binding: LibraryOutcomeBinding
    let checkpoint: LibraryOutcomeCheckpoint
}
struct LibraryExportArtifact: Sendable {
    let id: String
    let directory: URL
}

enum LibraryOutcomeSettlement: Equatable, Sendable {
    case collecting, awaitingSaved, proofUnavailable, settled
}

struct LibraryPartitionState: Codable, Equatable, Sendable {
    var pending: [LibraryLocalChange] = []
    var frozen: LibraryFrozenBatch?
    var recovery: [LibraryRecovery] = []
    var recent: [LibraryRecentReceipt] = []
    var clientKey = UUID().uuidString
    var nextSequence = 1
    var acknowledgement: SyncAcknowledgement?
    var waiting: SyncPending?
    var collectingOutcome: LibraryPendingOutcome?
    var manifestAckLink: LibraryOutcomeBinding?
    var outcomeRetentionCursor: String?
    var confirmed: [LibraryConfirmedChange] = []
    var folderMappings: [String: String] = [:]
    var savedSnapshot: SyncSavedSnapshot?
    var positionsSnapshot: SyncPositionsSnapshot?

    private enum CodingKeys: String, CodingKey { case pending, frozen, recovery, recent, clientKey, nextSequence, acknowledgement, waiting, collectingOutcome, manifestAckLink, outcomeRetentionCursor, confirmed, folderMappings, savedSnapshot, positionsSnapshot }
    init() { }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        pending = try values.decodeIfPresent([LibraryLocalChange].self, forKey: .pending) ?? []
        frozen = try values.decodeIfPresent(LibraryFrozenBatch.self, forKey: .frozen)
        recovery = try values.decodeIfPresent([LibraryRecovery].self, forKey: .recovery) ?? []
        recent = try values.decodeIfPresent([LibraryRecentReceipt].self, forKey: .recent) ?? []
        clientKey = try values.decodeIfPresent(String.self, forKey: .clientKey) ?? UUID().uuidString
        nextSequence = try values.decodeIfPresent(Int.self, forKey: .nextSequence) ?? 1
        acknowledgement = try values.decodeIfPresent(SyncAcknowledgement.self, forKey: .acknowledgement)
        waiting = try values.decodeIfPresent(SyncPending.self, forKey: .waiting)
        collectingOutcome = try values.decodeIfPresent(LibraryPendingOutcome.self, forKey: .collectingOutcome)
        manifestAckLink = try values.decodeIfPresent(LibraryOutcomeBinding.self, forKey: .manifestAckLink)
        outcomeRetentionCursor = try values.decodeIfPresent(String.self, forKey: .outcomeRetentionCursor)
        confirmed = try values.decodeIfPresent([LibraryConfirmedChange].self, forKey: .confirmed) ?? []
        folderMappings = try values.decodeIfPresent([String: String].self, forKey: .folderMappings) ?? [:]
        savedSnapshot = try values.decodeIfPresent(SyncSavedSnapshot.self, forKey: .savedSnapshot)
        positionsSnapshot = try values.decodeIfPresent(SyncPositionsSnapshot.self, forKey: .positionsSnapshot)
    }

    func projectedFrozenChanges(owner: LibrarySyncOwner, observed: LibrarySavedObservation) throws -> [LibraryLocalChange] {
        let version = try observed.version(for: owner)
        guard let collectingOutcome else { return frozen?.changes ?? [] }
        return (frozen?.changes ?? []).filter { change in
            if case .folderDelete = change.operation.command { return (version ?? -1) < collectingOutcome.committed.revision.saved }
            return false
        }
    }
    mutating func pruneConfirmed(owner: LibrarySyncOwner, observed: LibrarySavedObservation) throws {
        let savedVersion = try observed.version(for: owner)
        confirmed.removeAll { value in
            let version = value.change.operation.command.isPositionChange ? positionsSnapshot?.version : savedVersion
            return (version ?? -1) >= value.version
        }
    }

    mutating func append(_ source: LibraryLocalSource, command: SyncCommand?, at: Double) {
        guard let command, LibrarySyncAdmission.accepts(command, at: at) else { recovery.append(.invalid(source)); return }
        pending.append(.init(command: command, at: at, source: source))
    }
    mutating func freeze() throws -> SyncFrame? {
        guard acknowledgement == nil, waiting == nil, collectingOutcome == nil, manifestAckLink == nil else { throw LibrarySyncFailure.invalidReceipt }
        if let frozen {
            guard frozen.changes.map(\.operation) == frozen.batch.operations else { throw LibrarySyncFailure.invalidReceipt }
            return SyncFrame(clientKey: clientKey, sequence: Double(nextSequence), batch: frozen.batch)
        }
        guard !pending.isEmpty else { return nil }
        let id = UUID().uuidString
        var selected: [LibraryLocalChange] = []
        var inspected = 0
        while let change = pending.first, inspected < LibrarySyncLimits.operations {
            inspected += 1
            guard LibrarySyncAdmission.accepts(change.operation.command, at: change.operation.at) else {
                recovery.append(.rejected(change)); pending.removeFirst(); continue
            }
            let extra: Int
            switch change.operation.command { case .folderDelete, .folderRestore: extra = 1; default: extra = 0 }
            if extra > 0 && !selected.isEmpty { break }
            let candidate = SyncBatch(id: id, operations: (selected + [change]).map(\.operation))
            if try JSONEncoder().encode(candidate).count > LibrarySyncLimits.bytes {
                if selected.isEmpty { recovery.append(.rejected(change)); pending.removeFirst(); continue }
                break
            }
            selected.append(change); pending.removeFirst()
            if extra > 0 { break }
        }
        if selected.isEmpty { return nil }
        let batch = SyncBatch(id: id, operations: selected.map(\.operation))
        frozen = .init(batch: batch, changes: selected)
        return SyncFrame(clientKey: clientKey, sequence: Double(nextSequence), batch: batch)
    }
    private mutating func settleReceipts(_ reply: SyncReply, now: Double) throws {
        guard let frozen, frozen.batch.id == reply.batchId, reply.receipts.count == frozen.changes.count else { throw LibrarySyncFailure.invalidReceipt }
        var byID = Dictionary(uniqueKeysWithValues: frozen.changes.map { ($0.operation.id, $0) })
        var stagedRecovery: [LibraryRecovery] = []
        var stagedRecent: [LibraryRecentReceipt] = []
        for receipt in reply.receipts {
            guard let change = byID.removeValue(forKey: receipt.id), change.operation.revision == receipt.revision else { throw LibrarySyncFailure.invalidReceipt }
            switch receipt.outcome {
            case .batchRequiresSplit, .folderDeletedManifest, .folderRestoredManifest: throw LibrarySyncFailure.invalidReceipt
            case .preserved, .folder, .folderDeleted: break
            case .folderRestored(let value):
                if !value.superseded.isEmpty || !value.missing.isEmpty { stagedRecovery.append(.server(change, receipt.outcome)) }
            case .superseded, .unresolved, .resolvedPosition: stagedRecovery.append(.server(change, receipt.outcome))
            }
            switch change.operation.command {
            case .bookmarkRemove, .favoriteRemove, .noteRemove, .folderDelete:
                let expiry = change.operation.at + SavedUndoDeadline.duration * 1_000
                if expiry > now { stagedRecent.append(.init(receipt: receipt, expiresAt: expiry)) }
            default: break
            }
        }
        guard byID.isEmpty else { throw LibrarySyncFailure.invalidReceipt }
        recovery.append(contentsOf: stagedRecovery)
        recent = recent.filter { $0.expiresAt > now } + stagedRecent
        self.frozen = nil
        nextSequence += 1
    }

    mutating func settleCollectedOutcome(_ expected: LibraryPendingOutcome, binding: LibraryOutcomeBinding,
                                         checkpoint: LibraryOutcomeCheckpoint, observed: LibrarySavedObservation, now: Double) throws -> LibraryOutcomeSettlement {
        let committed = expected.committed, proof = try LibraryManifestProof(committed)
        let ack = SyncAcknowledgement(clientKey: committed.clientKey, sequence: committed.sequence, batchId: committed.reply.batchId, digest: committed.digest)
        guard binding.committed == committed, binding.owner.key == committed.reply.ownerKey,
              clientKey == committed.clientKey else { throw LibrarySyncFailure.invalidReceipt }
        if collectingOutcome == nil, acknowledgement == ack, Double(nextSequence) == committed.sequence + 1 { return .settled }
        guard collectingOutcome == expected, acknowledgement == nil, waiting == nil,
              Double(nextSequence) == committed.sequence, checkpoint.counts.valid,
              checkpoint.counts.fits(binding.expected) else { throw LibrarySyncFailure.invalidReceipt }
        let original: LibraryLocalChange?
        switch expected.origin {
        case .matched(let digest):
            try validateMatchedOutcome(committed)
            guard let frozen, try frozen.batch.intentDigest() == digest else { throw LibrarySyncFailure.invalidReceipt }
            original = frozen.changes[0]
        case .historical:
            guard frozen == nil else { throw LibrarySyncFailure.invalidReceipt }
            original = nil
        }
        let unavailable: Bool
        switch checkpoint.status {
        case .collecting, .verifying: return .collecting
        case .unavailable(.proofUnavailable): return .proofUnavailable
        case .unavailable(.detailUnavailable): unavailable = true
        case .complete:
            guard checkpoint.counts == binding.expected else { throw LibrarySyncFailure.invalidReceipt }
            unavailable = false
        }
        guard let version = try observed.version(for: binding.owner), version >= committed.revision.saved else { return .awaitingSaved }
        var mapping: (String, String)?
        if let original, case .folderRestore(let command) = original.operation.command,
           case .folderRestoredManifest(let result) = proof.receipt.outcome {
            let key = "restore:" + command.deletionId
            guard folderMappings[key] == nil || folderMappings[key] == result.folderId else { throw LibrarySyncFailure.invalidReceipt }
            mapping = (key, result.folderId)
        }
        let recoveryEntry = LibraryRecovery.outcome(authority: binding, checkpoint: checkpoint, original: original)
        let needsRecovery = original == nil || unavailable || binding.expected.superseded > 0 || binding.expected.missing > 0
        if needsRecovery {
            let existing = recovery.filter { if case .outcome(let authority, _, _) = $0 { return authority.key == binding.key }; return false }
            guard existing.isEmpty || existing == [recoveryEntry] else { throw LibrarySyncFailure.invalidReceipt }
            if existing.isEmpty { recovery.append(recoveryEntry) }
        }
        if let (key, value) = mapping { folderMappings[key] = value }
        recent = recent.filter { $0.expiresAt > now }
        if let original, case .folderDelete = original.operation.command {
            let deadline = original.operation.at + SavedUndoDeadline.duration * 1_000
            if deadline > now { recent.append(.init(receipt: proof.receipt, expiresAt: deadline)) }
        }
        manifestAckLink = !needsRecovery && checkpoint.status == .complete ? binding : nil
        frozen = nil; collectingOutcome = nil
        nextSequence += 1; acknowledgement = ack
        return .settled
    }

    func retainsOutcome(_ binding: LibraryOutcomeBinding, now: Double) -> Bool {
        let target = binding.request.receiptId
        func folderReferences(_ folder: SyncFolderReference) -> Bool {
            guard case .local(let value) = folder else { return false }
            if binding.request.phase == .delete { return value.key == "restore:" + target }
            if case .folderRestoredManifest(let result) = binding.committed.reply.receipts.first?.outcome { return folderMappings[value.key] == result.folderId }
            return false
        }
        func changeReferences(_ change: LibraryLocalChange) -> Bool {
            if change.operation.id == target { return true }
            switch change.operation.command {
            case .folderRestore(let value): return value.deletionId == target
            case .membershipPut(let value): return folderReferences(value.folder)
            case .folderDelete(let value): return folderReferences(value.folder)
            case .bookmarkAdd, .bookmarkRemove, .favoriteAdd, .favoriteRemove, .notePut, .noteRemove,
                 .folderCreate, .positionPut, .legacyPositionPut, .facetRestore: return false
            }
        }
        if manifestAckLink?.key == binding.key { return true }
        if let collectingOutcome, (try? LibraryOutcomeBinding(owner: binding.owner, committed: collectingOutcome.committed).key) == binding.key { return true }
        if waiting?.manifestId == binding.request.manifestId && waiting?.generation == binding.request.generation { return true }
        if recent.contains(where: { $0.receipt.id == target && $0.expiresAt > now }) { return true }
        if (pending + (frozen?.changes ?? []) + confirmed.map(\.change)).contains(where: changeReferences) { return true }
        return recovery.contains { value in
            switch value {
            case .invalid: return false
            case .server(let change, _), .historical(let change), .rejected(let change): return changeReferences(change)
            case .outcome(let authority, _, let original): return authority.key == binding.key || original.map(changeReferences) == true
            }
        }
    }
    func canPruneOutcome(_ binding: LibraryOutcomeBinding, checkpoint: LibraryOutcomeCheckpoint, observed: LibrarySavedObservation, now: Double) throws -> Bool {
        guard checkpoint.status == .complete, checkpoint.counts == binding.expected,
              binding.expected.superseded == 0, binding.expected.missing == 0,
              let retention = checkpoint.retention, retention.valid(total: checkpoint.next),
              now.isFinite, now >= retention.acknowledgedAt + LibraryOutcomeRetention.duration,
              let version = try observed.version(for: binding.owner), version >= binding.committed.revision.saved else { return false }
        return !retainsOutcome(binding, now: now)
    }

    private func checkCursor(_ cursor: SyncCursor) throws {
        guard cursor.closedThrough.isFinite, cursor.closedThrough >= 0,
              cursor.closedThrough.rounded(.down) == cursor.closedThrough,
              cursor.closedThrough < 9_007_199_254_740_991 else { throw LibrarySyncFailure.invalidReceipt }
        if let active = cursor.outstanding?.committedValue {
            guard active.clientKey == clientKey, active.sequence == cursor.closedThrough + 1,
                  !active.reply.batchId.isEmpty, !active.digest.isEmpty else { throw LibrarySyncFailure.invalidReceipt }
            if active.needsOutcomeCollection { _ = try LibraryManifestProof(active) }
        }
        if let pending = cursor.outstanding?.pendingValue {
            guard pending.clientKey == clientKey, pending.sequence == cursor.closedThrough + 1,
                  !pending.batchId.isEmpty, pending.batchId.utf8.count <= 128, !pending.digest.isEmpty, pending.digest.utf8.count <= 128,
                  pending.intentDigest.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                  !pending.manifestId.isEmpty, pending.manifestId.utf8.count <= 128, !pending.generation.isEmpty, pending.generation.utf8.count <= 128,
                  pending.retryAfterMs.isFinite, pending.retryAfterMs >= 250, pending.retryAfterMs <= 30_000 else { throw LibrarySyncFailure.invalidReceipt }
        }
    }

    private mutating func adopt(_ cursor: SyncCursor) throws {
        try checkCursor(cursor)
        guard collectingOutcome == nil else { throw LibrarySyncFailure.invalidReceipt }
        if let committed = cursor.outstanding?.committedValue, committed.needsOutcomeCollection {
            var origin = LibraryOutcomeOrigin.historical
            if let waiting, waiting.clientKey == committed.clientKey, waiting.sequence == committed.sequence,
               waiting.batchId == committed.reply.batchId, waiting.digest == committed.digest,
               let frozen, (try? frozen.batch.intentDigest()) == waiting.intentDigest {
                try validateMatchedOutcome(committed)
                origin = .matched(intentDigest: waiting.intentDigest)
            } else {
                if let frozen { recovery.append(contentsOf: frozen.changes.map(LibraryRecovery.historical)) }
                frozen = nil
            }
            collectingOutcome = .init(committed: committed, origin: origin)
            nextSequence = Int(cursor.closedThrough) + 1
            self.waiting = nil; acknowledgement = nil; manifestAckLink = nil
            return
        }
        let pending = cursor.outstanding?.pendingValue
        let keepOriginal = pending.map { $0.sequence == Double(nextSequence) && $0.batchId == frozen?.batch.id && $0.intentDigest == (try? frozen?.batch.intentDigest()) } ?? false
        if !keepOriginal {
            if let frozen { recovery.append(contentsOf: frozen.changes.map(LibraryRecovery.historical)) }
            frozen = nil
        }
        nextSequence = Int(cursor.closedThrough) + 1
        waiting = pending
        manifestAckLink = nil
        acknowledgement = cursor.outstanding?.committedValue.map { .init(clientKey: clientKey, sequence: $0.sequence, batchId: $0.reply.batchId, digest: $0.digest) }
    }

    private func validateMatchedOutcome(_ committed: SyncCommitted) throws {
        let proof = try LibraryManifestProof(committed)
        guard let frozen, frozen.batch.id == committed.reply.batchId, frozen.changes.map(\.operation) == frozen.batch.operations,
              frozen.changes.count == 1, let operation = frozen.batch.operations.first,
              operation.id == proof.receipt.id, operation.revision == proof.receipt.revision else { throw LibrarySyncFailure.invalidReceipt }
        switch (operation.command, proof.receipt.outcome) {
        case (.folderDelete, .folderDeletedManifest), (.folderRestore, .folderRestoredManifest): break
        default: throw LibrarySyncFailure.invalidReceipt
        }
    }

    mutating func settle(_ exchange: SyncExchange, requested: SyncFrame, owner: LibrarySyncOwner, observed: LibrarySavedObservation, now: Double) throws {
        _ = try observed.version(for: owner)
        guard requested.clientKey == clientKey, requested.sequence == Double(nextSequence), frozen?.batch == requested.batch,
              acknowledgement == nil, collectingOutcome == nil else { throw LibrarySyncFailure.invalidReceipt }
        switch exchange {
        case .accepted(let value):
            let committed = value.committed
            guard committed.clientKey == clientKey, committed.sequence == requested.sequence, !committed.digest.isEmpty else { throw LibrarySyncFailure.invalidReceipt }
            if committed.needsOutcomeCollection {
                try validateMatchedOutcome(committed)
                guard let frozen else { throw LibrarySyncFailure.invalidReceipt }
                collectingOutcome = .init(committed: committed, origin: .matched(intentDigest: try frozen.batch.intentDigest()))
                waiting = nil
                return
            }
            if committed.reply.receipts.contains(where: { $0.outcome == .batchRequiresSplit }) {
                guard let frozen, frozen.batch.id == committed.reply.batchId,
                      frozen.changes.map(\.operation) == frozen.batch.operations,
                      frozen.changes.count > 1, Set(frozen.changes.map { $0.operation.id }).count == frozen.changes.count,
                      frozen.changes.filter({ if case .folderDelete = $0.operation.command { return true }; if case .folderRestore = $0.operation.command { return true }; return false }).count == 1,
                      committed.reply.receipts.count == frozen.changes.count,
                      Set(committed.reply.receipts.map(\.id)).count == committed.reply.receipts.count else { throw LibrarySyncFailure.invalidReceipt }
                let receipts = Dictionary(uniqueKeysWithValues: committed.reply.receipts.map { ($0.id, $0) })
                guard receipts.count == frozen.changes.count, frozen.changes.allSatisfy({ change in
                    receipts[change.operation.id]?.revision == change.operation.revision && receipts[change.operation.id]?.outcome == .batchRequiresSplit
                }) else { throw LibrarySyncFailure.invalidReceipt }
                pending = frozen.changes + pending
                self.frozen = nil; nextSequence += 1; waiting = nil
                acknowledgement = .init(clientKey: clientKey, sequence: committed.sequence, batchId: committed.reply.batchId, digest: committed.digest)
                return
            }
            let submitted = frozen?.changes ?? []
            try settleReceipts(committed.reply, now: now)
            for change in submitted {
                guard let receipt = committed.reply.receipts.first(where: { $0.id == change.operation.id }) else { throw LibrarySyncFailure.invalidReceipt }
                switch receipt.outcome {
                case .batchRequiresSplit, .folderDeletedManifest, .folderRestoredManifest: throw LibrarySyncFailure.invalidReceipt
                case .preserved, .folder, .folderDeleted, .folderRestored, .resolvedPosition:
                    let version = change.operation.command.isPositionChange ? committed.revision.position : committed.revision.saved
                    confirmed.append(.init(change: change, outcome: receipt.outcome, version: version))
                case .superseded, .unresolved: break
                }
                if case .folderCreate(let created) = change.operation.command, case .folder(let value) = receipt.outcome { folderMappings[created.key] = value.folderId }
                if case .folderRestore(let restored) = change.operation.command, case .folderRestored(let value) = receipt.outcome { folderMappings["restore:" + restored.deletionId] = value.folderId }
            }
            try pruneConfirmed(owner: owner, observed: observed)
            acknowledgement = .init(clientKey: clientKey, sequence: committed.sequence, batchId: committed.reply.batchId, digest: committed.digest)
            waiting = nil
        case .pending(let value):
            guard value.pending.clientKey == clientKey, value.pending.sequence == requested.sequence, value.pending.batchId == requested.batch.id else { throw LibrarySyncFailure.invalidReceipt }
            guard waiting == nil || waiting?.matches(value.pending) == true else { throw LibrarySyncFailure.invalidReceipt }
            try adopt(.init(closedThrough: requested.sequence - 1, outstanding: .pending(.init(pending: value.pending))))
        case .reconcile(let value):
            guard value.clientKey == clientKey, value.requestedSequence == requested.sequence, value.requestedBatchId == requested.batch.id else { throw LibrarySyncFailure.invalidReceipt }
            try adopt(value.cursor)
        }
    }

    mutating func settlePending(_ exchange: SyncExchange, requested: SyncPending, owner: LibrarySyncOwner, observed: LibrarySavedObservation, now: Double) throws {
        _ = try observed.version(for: owner)
        guard waiting == requested, acknowledgement == nil else { throw LibrarySyncFailure.invalidReceipt }
        switch exchange {
        case .pending(let value):
            guard requested.matches(value.pending) else { throw LibrarySyncFailure.invalidReceipt }
            try adopt(.init(closedThrough: requested.sequence - 1, outstanding: .pending(.init(pending: value.pending))))
        case .accepted(let value):
            let proof = value.committed
            guard proof.clientKey == requested.clientKey, proof.sequence == requested.sequence, proof.reply.batchId == requested.batchId, proof.digest == requested.digest else { throw LibrarySyncFailure.invalidReceipt }
            if let frozen, frozen.batch.id == requested.batchId, (try? frozen.batch.intentDigest()) == requested.intentDigest {
                try settle(exchange, requested: .init(clientKey: clientKey, sequence: requested.sequence, batch: frozen.batch), owner: owner, observed: observed, now: now)
            } else {
                try adopt(.init(closedThrough: requested.sequence - 1, outstanding: .committed(.init(committed: proof))))
            }
        case .reconcile(let value):
            guard value.clientKey == requested.clientKey, value.requestedSequence == requested.sequence, value.requestedBatchId == requested.batchId else { throw LibrarySyncFailure.invalidReceipt }
            try adopt(value.cursor)
        }
    }

    func pollRequest() throws -> SyncPending? {
        guard let waiting else { return nil }
        guard acknowledgement == nil, waiting.sequence == Double(nextSequence) else { throw LibrarySyncFailure.invalidReceipt }
        try checkCursor(.init(closedThrough: Double(nextSequence - 1), outstanding: .pending(.init(pending: waiting))))
        return waiting
    }

    mutating func settleRetirement(_ reply: SyncAckReply, requested: SyncFrame) throws {
        guard reply.clientKey == clientKey, requested.clientKey == clientKey,
              requested.sequence == Double(nextSequence), frozen?.batch == requested.batch,
              acknowledgement == nil else { throw LibrarySyncFailure.invalidReceipt }
        try adopt(reply.cursor)
    }

    mutating func settleAcknowledgement(_ reply: SyncAckReply, requested: SyncAcknowledgement) throws {
        guard acknowledgement == requested, reply.clientKey == clientKey else { throw LibrarySyncFailure.invalidReceipt }
        try adopt(reply.cursor)
    }

}

enum LibrarySyncFailure: Error {
    case storeUnavailable, ownerMismatch, invalidReceipt, oversizedChange, invalidChange, sessionChanged, accountDeleting
}

struct LibrarySyncSession: Equatable, Sendable {
    let id: String
    let subject: String
}

enum LibraryExportPolicy {
    static let deniedKeys: Set<String> = ["pushTokens", "adminAuditLog", "revenueCatAppUserId", "capability"]
}
struct LibraryPreparedExport: Sendable {
    let url: URL
    fileprivate let artifactID: String
    fileprivate let context: LibraryWriteContext
}
extension LibraryOutcomeExportEntry {
    func exportMetadata() throws -> [String: LibraryExportValue] {
        func counts(_ value: LibraryOutcomeCounts) -> LibraryExportValue {
            .object(["deleted": .number(Double(value.deleted)), "restored": .number(Double(value.restored)), "superseded": .number(Double(value.superseded)), "missing": .number(Double(value.missing))])
        }
        var result: [String: LibraryExportValue] = [
            "authority": try JSONDecoder().decode(LibraryExportValue.self, from: JSONEncoder().encode(binding)),
            "expected": counts(binding.expected), "collected": counts(checkpoint.counts), "collectedPrefixCount": .number(Double(checkpoint.next)),
            "detailComplete": .bool(checkpoint.status == .complete),
        ]
        switch checkpoint.status {
        case .collecting: result["status"] = .string("collecting")
        case .complete: result["status"] = .string("complete")
        case .verifying(let verified): result["status"] = .string("verifying"); result["verified"] = counts(verified)
        case .unavailable(let reason): result["status"] = .string("unavailable"); result["unavailableReason"] = .string(reason.rawValue)
        }
        if let retention = checkpoint.retention { result["retention"] = try JSONDecoder().decode(LibraryExportValue.self, from: JSONEncoder().encode(retention)) }
        return result
    }
}

struct LibraryWriteContext: Sendable {
    fileprivate let session: LibrarySyncSession
    fileprivate let owner: LibrarySyncOwner
    fileprivate let generation: UUID
}

@MainActor
struct LibrarySyncTransport {
    let namespace: String
    let open: () async throws -> SyncBinding
    let acknowledge: (String, SyncAcknowledgement) async throws -> SyncAckReply
    let send: (String, SyncFrame) async throws -> SyncExchange
    var retireInvalid: (String, SyncFrame) async throws -> SyncAckReply = { _, _ in throw LibrarySyncFailure.invalidChange }
    var poll: (String, SyncPending) async throws -> SyncExchange = { _, _ in throw LibrarySyncFailure.invalidChange }
    var outcomePage: (String, SyncOutcomePageRequest) async throws -> SyncOutcomePage = { _, _ in throw LibrarySyncFailure.invalidChange }
    var savedHeads: (String) -> AnyPublisher<SavedReadHead, Error> = { _ in Fail(error: LibrarySyncFailure.invalidChange).eraseToAnyPublisher() }
    var savedFacts: (String, String?) async throws -> SavedFactsReply = { _, _ in throw LibrarySyncFailure.invalidChange }
    var savedReference: (String, String) async throws -> SavedReferenceReply = { _, _ in throw LibrarySyncFailure.invalidChange }
    var savedText: (String, String) async throws -> SavedTextReply = { _, _ in throw LibrarySyncFailure.invalidChange }
}

@MainActor
@Observable
final class LibrarySync {
    enum Status: Equatable { case idle, syncing, waitingForSaved, ready(recovered: Int), failed }
    private(set) var owner: LibrarySyncOwner?
    private(set) var status = Status.idle
    var onOwnerChange: (LibrarySyncOwner?) -> Void = { _ in }
    var onPartitionChange: (LibrarySyncOwner) -> Void = { _ in }
    private let store: GuestDataStore
    private let transport: LibrarySyncTransport
    private let currentSession: () -> LibrarySyncSession?
    private let now: () -> Double
    private var session: LibrarySyncSession?
    private var binding: SyncBinding?
    private var generation = UUID()
    private var worker: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var retryDelay: Double = 1
    private var requested = false

    init(store: GuestDataStore, transport: LibrarySyncTransport,
         currentSession: @escaping () -> LibrarySyncSession?, now: @escaping () -> Double = { Date.now.millisecondsSinceEpoch }) {
        self.store = store
        self.transport = transport
        self.currentSession = currentSession
        self.now = now
        store.onGuestChanged = { [weak self] in self?.wake() }
    }

    func activate(_ next: LibrarySyncSession) async {
        guard currentSession() == next else { return }
        if session != next { deactivate(); session = next }
        if let worker { requested = true; await worker.value; return }
        retryTask?.cancel()
        retryTask = nil
        let epoch = generation
        status = .syncing
        requested = false
        let task = Task { await run(next, epoch: epoch) }
        worker = task
        await task.value
        if generation == epoch {
            worker = nil
            if requested { wake() }
        }
    }

    func deactivate() {
        generation = UUID()
        worker?.cancel()
        retryTask?.cancel()
        worker = nil
        retryTask = nil
        session = nil
        binding = nil
        owner = nil
        status = .idle
        onOwnerChange(nil)
    }

    func wake() {
        guard let session, currentSession() == session else { return }
        requested = true
        guard worker == nil else { return }
        let epoch = generation
        Task {
            guard generation == epoch, self.session == session else { return }
            await activate(session)
        }
    }

    func captureWriteContext() throws -> LibraryWriteContext {
        guard let session, currentSession() == session, let owner else { throw LibrarySyncFailure.sessionChanged }
        return LibraryWriteContext(session: session, owner: owner, generation: generation)
    }

    func enqueue(_ change: LibraryLocalChange, context: LibraryWriteContext) throws {
        guard generation == context.generation, session == context.session,
              currentSession() == context.session, owner == context.owner else { throw LibrarySyncFailure.sessionChanged }
        guard LibrarySyncAdmission.accepts(change.operation.command, at: change.operation.at),
              try JSONEncoder().encode(SyncBatch(id: "admission", operations: [change.operation])).count <= LibrarySyncLimits.bytes else { throw LibrarySyncFailure.invalidChange }
        try store.enqueueSyncChange(change, owner: context.owner)
        onPartitionChange(context.owner)
        wake()
    }

    func capability(for context: LibraryWriteContext) throws -> String {
        guard generation == context.generation, session == context.session, currentSession() == context.session,
              owner == context.owner, let binding, binding.validUntil > now() else { throw LibrarySyncFailure.sessionChanged }
        return binding.capability
    }

    func captureSavedReadContext() throws -> LibrarySavedReadContext {
        let write = try captureWriteContext(), capability = try capability(for: write)
        guard let binding else { throw LibrarySyncFailure.sessionChanged }
        return .init(write: write, capability: capability, validUntil: binding.validUntil)
    }
    private func savedCapability(_ context: LibrarySavedReadContext) throws -> String {
        let value = try capability(for: context.write)
        guard value == context.capability, now() < context.validUntil else { throw LibrarySyncFailure.sessionChanged }
        return value
    }
    func savedInvalidations(_ context: LibrarySavedReadContext) throws -> AnyPublisher<LibrarySavedInvalidation, Error> {
        _ = try savedCapability(context)
        return Deferred { [weak self] () -> AnyPublisher<LibrarySavedInvalidation, Error> in
            do {
                guard let self else { throw LibrarySyncFailure.sessionChanged }
                let capability = try savedCapability(context)
                let expiry = Just(()).delay(for: .seconds(max(0, (context.validUntil - now()) / 1_000)), scheduler: DispatchQueue.main)
                return transport.savedHeads(capability).prefix(untilOutputFrom: expiry)
                    .append(Fail<SavedReadHead, Error>(error: LibrarySyncFailure.sessionChanged)).receive(on: DispatchQueue.main)
                    .tryMap { [weak self] value in
                        guard let self else { throw LibrarySyncFailure.sessionChanged }
                        _ = try savedCapability(context)
                        return try LibrarySavedReadPolicy.invalidation(value, owner: context.owner)
                    }.eraseToAnyPublisher()
            } catch { return Fail(error: error).eraseToAnyPublisher() }
        }.subscribe(on: DispatchQueue.main).eraseToAnyPublisher()
    }
    func savedFacts(continuation: String?, context: LibrarySavedReadContext) async throws -> SavedFactsReply {
        let reply = try await transport.savedFacts(savedCapability(context), continuation)
        try Task.checkCancellation(); _ = try savedCapability(context)
        return reply // The durable collector validates source position, identity and completion.
    }
    func savedReference(hadithID: String, context: LibrarySavedReadContext) async throws -> LibrarySavedReferenceState {
        try LibrarySavedReadPolicy.target(hadithID)
        let reply = try await transport.savedReference(savedCapability(context), hadithID)
        try Task.checkCancellation(); _ = try savedCapability(context)
        return try LibrarySavedReadPolicy.reference(reply, owner: context.owner, target: hadithID)
    }
    func savedText(hadithID: String, context: LibrarySavedReadContext) async throws -> LibrarySavedTextState {
        try LibrarySavedReadPolicy.target(hadithID)
        let reply = try await transport.savedText(savedCapability(context), hadithID)
        try Task.checkCancellation(); _ = try savedCapability(context)
        return try LibrarySavedReadPolicy.text(reply, owner: context.owner, target: hadithID)
    }

    func portableState(for context: LibraryWriteContext) throws -> LibraryExportValue {
        _ = try capability(for: context)
        guard let state = try store.syncPartition(context.owner) else { throw LibrarySyncFailure.sessionChanged }
        let encoded = try JSONEncoder().encode(state)
        return try JSONDecoder().decode(LibraryExportValue.self, from: encoded).withoutProviderPassages
    }

    func preparePortableExport(server: LibraryExportValue, context captured: LibraryWriteContext, fileName: String) async throws -> LibraryPreparedExport {
        for attempt in 0..<3 {
            do { return try await preparePortableExportAttempt(server: server, context: captured, fileName: fileName) }
            catch LibrarySyncFailure.storeUnavailable {
                guard attempt < 2 else { throw LibrarySyncFailure.storeUnavailable }
                try Task.checkCancellation()
                _ = try capability(for: captured)
                await Task.yield()
            }
        }
        throw LibrarySyncFailure.storeUnavailable
    }
    private func preparePortableExportAttempt(server: LibraryExportValue, context captured: LibraryWriteContext, fileName: String) async throws -> LibraryPreparedExport {

        _ = try capability(for: captured)
        guard !fileName.isEmpty, fileName != ".", fileName != "..", URL(fileURLWithPath: fileName).lastPathComponent == fileName else { throw LibrarySyncFailure.invalidChange }
        let fence = try await store.prepareOutcomeExport(captured.owner, isCurrent: { (try? self.capability(for: captured)) != nil })
        _ = try capability(for: captured)
        let document = try server.includingLocalLibrary(portableState(for: captured))
        guard case .object(let fields) = document, fields["localOutcomeEvidence"] == nil, fields["localSavedEvidence"] == nil,
              !document.containsAnyKey(LibraryExportPolicy.deniedKeys) else { throw LibrarySyncFailure.invalidReceipt }
        let artifact = try store.beginOutcomeExportArtifact(fence)
        let partial = artifact.directory.appendingPathComponent("document.partial"), destination = artifact.directory.appendingPathComponent(fileName)
        var keep = false
        defer { if !keep { try? store.discardOutcomeExportArtifact(artifact.id) } }
        guard FileManager.default.createFile(atPath: partial.path, contents: nil, attributes: [.protectionKey: FileProtectionType.complete]) else { throw LibrarySyncFailure.storeUnavailable }
        let file = try FileHandle(forWritingTo: partial)
        defer { try? file.close() }
        let encoder = JSONEncoder()
        func raw(_ text: String) throws { try file.write(contentsOf: Data(text.utf8)) }
        func encoded<T: Encodable>(_ value: T) throws { try file.write(contentsOf: encoder.encode(value)) }
        try raw("{")
        var first = true
        for key in fields.keys.sorted() {
            if !first { try raw(",") }; first = false
            try encoded(key); try raw(":"); try encoded(fields[key])
        }
        if !first { try raw(",") }
        try raw("\"localOutcomeEvidence\":[")
        var after: String?, firstEntry = true
        while true {
            try Task.checkCancellation(); _ = try capability(for: captured)
            let entries = try store.outcomeExportEntries(fence, after: after)
            if entries.isEmpty { break }
            for entry in entries {
                guard entry.checkpoint.retention?.removed == nil else { throw LibrarySyncFailure.storeUnavailable }
                if !firstEntry { try raw(",") }; firstEntry = false
                let metadata = try entry.exportMetadata()
                try raw("{")
                for key in metadata.keys.sorted() {
                    try encoded(key); try raw(":"); try encoded(metadata[key]); try raw(",")
                }
                try raw("\"rows\":[")
                var start = 0, firstRow = true
                while true {
                    try Task.checkCancellation(); _ = try capability(for: captured)
                    let page = try store.outcomeExportPage(fence, entry: entry, start: start)
                    for row in page.rows {
                        if !firstRow { try raw(",") }; firstRow = false
                        try encoded(row)
                    }
                    start = page.next
                    if page.endOfCollectedPrefix { break }
                    await Task.yield()
                }
                try raw("]}")
                after = entry.binding.key
                await Task.yield()
            }
        }
        try raw("],\"localSavedEvidence\":[")
        var firstSaved = true
        for section in 0..<6 {
            var cursor: String?
            while true {
                try Task.checkCancellation(); _ = try capability(for: captured)
                let page = try store.savedExportRecords(fence, section: section, after: cursor)
                for value in page.values { if !firstSaved { try raw(",") }; firstSaved = false; try encoded(value) }
                cursor = page.next
                if page.done { break }
                await Task.yield()
            }
        }
        try raw("]}")
        try file.synchronize(); try file.close()
        try Task.checkCancellation(); _ = try capability(for: captured)
        try store.validateOutcomeExport(fence)
        try FileManager.default.moveItem(at: partial, to: destination)
        keep = true
        return .init(url: destination, artifactID: artifact.id, context: captured)
    }
    func discardPreparedExport(_ export: LibraryPreparedExport) throws { try store.discardOutcomeExportArtifact(export.artifactID) }

    private func check(_ session: LibrarySyncSession, epoch: UUID) throws {
        guard !Task.isCancelled, generation == epoch, currentSession() == session else { throw LibrarySyncFailure.sessionChanged }
    }

    private func run(_ session: LibrarySyncSession, epoch: UUID) async {
        do {
            try check(session, epoch: epoch)
            guard try store.deletionPhase(subject: session.subject, namespace: transport.namespace) == nil else { throw LibrarySyncFailure.accountDeleting }
            if binding == nil || (binding?.validUntil ?? 0) <= now() + 1_000 {
                let opened = try await transport.open()
                try check(session, epoch: epoch)
                guard opened.subject == session.subject, opened.validUntil.isFinite, opened.validUntil > now() else { throw LibrarySyncFailure.ownerMismatch }
                binding = opened
                let nextOwner = LibrarySyncOwner(key: opened.ownerKey, subject: opened.subject, namespace: transport.namespace)
                try store.claimGuestForSync(nextOwner)
                try check(session, epoch: epoch)
                owner = nextOwner
                onOwnerChange(nextOwner)
            }
            guard let binding, let owner else { throw LibrarySyncFailure.ownerMismatch }
            for _ in 0..<8 {
                try check(session, epoch: epoch)
                try store.claimGuestForSync(owner)
                onPartitionChange(owner)
                if let collection = try store.syncPartition(owner)?.collectingOutcome {
                    let checkpoint = try await store.collectOutcomeStep(collection.committed, owner: owner, isCurrent: {
                        (try? self.check(session, epoch: epoch)) != nil
                    }, fetch: { request in try await self.transport.outcomePage(binding.capability, request) })
                    try check(session, epoch: epoch)
                    switch checkpoint.status {
                    case .collecting, .verifying: continue
                    case .complete, .unavailable:
                        let progress = try store.settleCollectedOutcome(collection, owner: owner, now: now())
                        switch progress {
                        case .settled: onPartitionChange(owner); continue
                        case .awaitingSaved: status = .waitingForSaved; return
                        case .proofUnavailable: status = .failed; return
                        case .collecting: continue
                        }
                    }
                }
                if let waiting = try store.syncPartition(owner)?.pollRequest() {
                    let reply = try await transport.poll(binding.capability, waiting)
                    try store.settleSyncPending(reply, requested: waiting, owner: owner, now: now())
                    onPartitionChange(owner)
                    try check(session, epoch: epoch)
                    if let pending = try store.syncPartition(owner)?.waiting {
                        schedule(session, epoch: epoch, after: pending.retryAfterMs / 1_000)
                        return
                    }
                    continue
                }
                if let acknowledgement = try store.syncPartition(owner)?.acknowledgement {
                    let reply = try await transport.acknowledge(binding.capability, acknowledgement)
                    try store.settleSyncAcknowledgement(reply, requested: acknowledgement, owner: owner, now: now())
                    onPartitionChange(owner)
                    try check(session, epoch: epoch)
                    continue
                }
                guard let frame = try store.freezeSyncFrame(owner) else {
                    let state = try store.syncPartition(owner)
                    onPartitionChange(owner)
                    if state?.pending.isEmpty == false { continue }
                    var moreCleanup = false
                    for _ in 0..<4 {
                        try check(session, epoch: epoch)
                        moreCleanup = try store.pruneOutcomeSuccessStep(owner, now: now())
                        if !moreCleanup { break }
                        await Task.yield()
                    }
                    try check(session, epoch: epoch)
                    status = .ready(recovered: state?.recovery.count ?? 0)
                    retryDelay = 1
                    if moreCleanup { schedule(session, epoch: epoch, after: 0.25) }
                    return
                }
                guard let frozen = try store.syncPartition(owner)?.frozen else { throw LibrarySyncFailure.sessionChanged }
                if !LibrarySyncAdmission.accepts(frozen, now: now()) {
                    let reply = try await transport.retireInvalid(binding.capability, frame)
                    try store.settleSyncRetirement(reply, requested: frame, owner: owner)
                    onPartitionChange(owner)
                    try check(session, epoch: epoch)
                    continue
                }
                let reply = try await transport.send(binding.capability, frame)
                // A late A receipt can settle only A's still-existing partition.
                try store.settleSyncExchange(reply, requested: frame, owner: owner, now: now())
                onPartitionChange(owner)
                try check(session, epoch: epoch)
                if let pending = try store.syncPartition(owner)?.waiting {
                    schedule(session, epoch: epoch, after: pending.retryAfterMs / 1_000)
                    return
                }
            }
            schedule(session, epoch: epoch, after: 0.25)
        } catch is CancellationError { }
        catch LibrarySyncFailure.sessionChanged { }
        catch LibrarySyncFailure.accountDeleting { status = .failed }
        catch LibrarySyncFailure.ownerMismatch {
            guard generation == epoch else { return }
            binding = nil
            owner = nil
            status = .failed
            onOwnerChange(nil)
        } catch {
            guard generation == epoch, currentSession() == session else { return }
            status = .failed
            schedule(session, epoch: epoch, after: retryDelay)
            retryDelay = min(30, retryDelay * 2)
        }
    }

    private func schedule(_ session: LibrarySyncSession, epoch: UUID, after seconds: Double) {
        retryTask?.cancel()
        retryTask = Task {
            do { try await Task.sleep(for: .seconds(seconds)) }
            catch { return }
            guard !Task.isCancelled, generation == epoch, currentSession() == session else { return }
            retryTask = nil
            await activate(session)
        }
    }
}


/// The same durable deletion state machine drives production and controlled tests.
@MainActor
struct LibraryAccountDeletion {
    let store: GuestDataStore
    let namespace: String
    let currentSession: () -> LibrarySyncSession?
    let invalidate: () -> Void
    let prepare: () async throws -> SyncDeletionAuthorization
    let erase: (String) async throws -> SyncDeletionResult
    let cleanup: (String) -> Void
    let deleteIdentity: (LibrarySyncSession) async throws -> Void

    func run(_ captured: LibrarySyncSession) async throws {
        guard currentSession() == captured else { throw LibrarySyncFailure.sessionChanged }
        invalidate()
        try store.beginDeletion(subject: captured.subject, namespace: namespace)
        if try store.deletionPhase(subject: captured.subject, namespace: namespace) == .serverPending {
            guard currentSession() == captured else { throw LibrarySyncFailure.sessionChanged }
            let grant = try await prepare()
            guard currentSession() == captured, grant.subject == captured.subject,
                  grant.validUntil.isFinite, grant.validUntil > Date.now.millisecondsSinceEpoch else { throw LibrarySyncFailure.ownerMismatch }
            let result = try await erase(grant.authorization)
            guard result.subject == captured.subject else { throw LibrarySyncFailure.ownerMismatch }
            try await store.markDeletionBackendComplete(subject: captured.subject, namespace: namespace)
        }
        cleanup(captured.subject)
        guard currentSession() == captured else { throw LibrarySyncFailure.sessionChanged }
        try await deleteIdentity(captured)
        try store.clearDeletion(subject: captured.subject, namespace: namespace)
    }
}

// Private Saved page policy. Collection/preparation never grants the production Saved barrier.
enum LibrarySavedContinuation: Codable, Equatable, Sendable {
    case next(String), complete(String)
    var token: String { switch self { case .next(let value), .complete(let value): value } }
}
struct LibrarySavedReadPosition: Codable, Equatable, Sendable {
    let owner: LibrarySyncOwner
    let version: Double
    let assemblyID: String
    let nextOrdinal: Int
    let phase: Int
    let continuation: LibrarySavedContinuation
}
struct LibrarySavedPagePlan: Equatable, Sendable {
    let position: LibrarySavedReadPosition
    let facts: [SavedFact]
    let input: String?
    let start: Int
    let fingerprint: String
}
enum LibrarySavedPageDecision: Equatable, Sendable {
    case append(LibrarySavedPagePlan), restart, unavailable(SavedFactsReplyUnavailableReason)
}
enum LibrarySavedProjection: Codable, Equatable, Sendable {
    case item(SavedPrivateItem, firstOrdinal: Int), folder(SyncFolderRow, firstOrdinal: Int)
    var firstOrdinal: Int { switch self { case .item(_, let value), .folder(_, let value): value } }
}
extension SavedFact {
    var ordinalValue: Double { switch self { case .folder(let v): v.ordinal; case .item(let v): v.ordinal; case .bookmark(let v): v.ordinal; case .favorite(let v): v.ordinal; case .note(let v): v.ordinal } }
    var sourceID: String { switch self { case .folder(let v): v.sourceId; case .item(let v): v.sourceId; case .bookmark(let v): v.sourceId; case .favorite(let v): v.sourceId; case .note(let v): v.sourceId } }
    var sourcePhase: Int { switch self { case .folder: 0; case .item: 1; case .bookmark: 2; case .favorite: 3; case .note: 4 } }
    var targetID: String { switch self { case .folder(let v): v.value._id; case .item(let v): v.value.hadithId; case .bookmark(let v): v.hadithId; case .favorite(let v): v.hadithId; case .note(let v): v.hadithId } }
    func savedFingerprint() throws -> String { try LibrarySemanticFingerprint.digest(self, domain: "library-saved-fact-v1:") }
}
enum LibrarySavedPolicy {
    static let maxInteger = 9_007_199_254_740_991.0
    static func integer(_ value: Double) throws -> Int {
        guard value.isFinite, value >= 0, value <= maxInteger, value.rounded(.down) == value else { throw LibrarySyncFailure.invalidReceipt }
        return Int(value)
    }
    private static func text(_ value: String, limit: Int, empty: Bool = false) throws {
        guard (empty || !value.isEmpty), value.utf8.count <= limit else { throw LibrarySyncFailure.invalidReceipt }
    }
    private static func time(_ value: Double) throws {
        guard value.isFinite, value >= 0 else { throw LibrarySyncFailure.invalidReceipt }
    }
    private static func encodedSize<T: Encodable>(_ value: T) throws -> Int {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes]
        return try encoder.encode(value).count
    }
    static func validate(_ item: SavedPrivateItem) throws {
        try text(item.hadithId, limit: 128); try time(item.createdAt); try time(item.updatedAt)
        for stamp in [item.bookmarkCreatedAt, item.favoriteCreatedAt, item.noteCreatedAt, item.noteUpdatedAt, item.folderUpdatedAt].compactMap({ $0 }) { try time(stamp) }
        if let id = item.folderId { try text(id, limit: 128) }
        guard try encodedSize(item) <= 128 * 1024 else { throw LibrarySyncFailure.invalidReceipt }
    }
    static func validate(_ fact: SavedFact) throws {
        _ = try integer(fact.ordinalValue); try text(fact.sourceID, limit: 128); try text(fact.targetID, limit: 128)
        guard try encodedSize(fact) <= LibrarySyncLimits.savedFactSourceBytes else { throw LibrarySyncFailure.invalidReceipt }
        switch fact {
        case .folder(let v): try text(v.value.name, limit: LibrarySyncLimits.savedFactSourceBytes, empty: true); try time(v.value.createdAt)
        case .item(let v): try validate(v.value)
        case .bookmark(let v): try time(v.createdAt)
        case .favorite(let v): try time(v.createdAt)
        case .note(let v): try time(v.createdAt); try time(v.updatedAt)
        }
    }
    static func inspect(_ reply: SavedFactsReply, owner: LibrarySyncOwner, previous: LibrarySavedReadPosition?, requested: String?) throws -> LibrarySavedPageDecision {
        guard try encodedSize(reply) <= LibrarySyncLimits.savedFactPageBytes else { throw LibrarySyncFailure.invalidReceipt }
        if let requested { try text(requested, limit: LibrarySyncLimits.savedFactCursorBytes) }
        if let previous {
            guard previous.owner == owner, previous.nextOrdinal >= 0, previous.phase >= -1, previous.phase <= 4,
                  case .next(let expected) = previous.continuation, expected == requested else { throw LibrarySyncFailure.invalidReceipt }
            _ = try integer(previous.version)
        } else if requested != nil { throw LibrarySyncFailure.invalidReceipt }
        let key: String, version: Double, root: String, input: String?, start: Double, facts: [SavedFact], continuation: LibrarySavedContinuation
        switch reply {
        case .restart(let value):
            guard value.reason == "saved_changed" else { throw LibrarySyncFailure.invalidReceipt }; return .restart
        case .unavailable(let v): return .unavailable(v.reason)
        case .page(let v): key = v.ownerKey; version = v.version; root = v.assemblyId; input = v.input; start = v.start; facts = v.facts; continuation = .next(v.next)
        case .complete(let v):
            key = v.ownerKey; version = v.version; root = v.assemblyId; input = v.input; start = v.start; facts = v.facts; continuation = .complete(v.completion)
            guard try integer(v.total) == integer(v.start) + facts.count else { throw LibrarySyncFailure.invalidReceipt }
        }
        _ = try integer(version); let ordinal = try integer(start)
        try text(root, limit: LibrarySyncLimits.savedFactCursorBytes); try text(continuation.token, limit: LibrarySyncLimits.savedFactCursorBytes)
        guard key == owner.key, input == requested, ordinal == (previous?.nextOrdinal ?? 0), facts.count <= LibrarySyncLimits.savedFactRows,
              Double(ordinal + facts.count) <= maxInteger else { throw LibrarySyncFailure.invalidReceipt }
        if let previous { guard version == previous.version, root == previous.assemblyID else { throw LibrarySyncFailure.invalidReceipt } }
        if case .next(let next) = continuation, next == requested { throw LibrarySyncFailure.invalidReceipt }
        var phase = previous?.phase ?? -1
        for (offset, fact) in facts.enumerated() {
            try validate(fact)
            guard try integer(fact.ordinalValue) == ordinal + offset, fact.sourcePhase >= phase else { throw LibrarySyncFailure.invalidReceipt }
            phase = fact.sourcePhase
        }
        return .append(.init(position: .init(owner: owner, version: version, assemblyID: root, nextOrdinal: ordinal + facts.count, phase: phase, continuation: continuation), facts: facts, input: input, start: ordinal,
            fingerprint: try LibrarySemanticFingerprint.digest(reply, domain: "library-saved-page-v1:")))
    }
    static func confirm(_ reply: SavedFactsReply, position: LibrarySavedReadPosition) throws {
        guard case .complete(let token) = position.continuation, case .complete(let value) = reply,
              try encodedSize(reply) <= LibrarySyncLimits.savedFactPageBytes,
              value.ownerKey == position.owner.key, value.version == position.version, value.assemblyId == position.assemblyID,
              value.input == token, value.completion == token, value.start == Double(position.nextOrdinal), value.total == value.start, value.facts.isEmpty else { throw LibrarySyncFailure.invalidReceipt }
        _ = try integer(value.version); _ = try integer(value.start)
        try text(token, limit: LibrarySyncLimits.savedFactCursorBytes); try text(value.assemblyId, limit: LibrarySyncLimits.savedFactCursorBytes)
    }
    static func validateProjection(_ value: LibrarySavedProjection) throws {
        _ = try integer(Double(value.firstOrdinal))
        switch value {
        case .item(let row, _): try validate(row)
        case .folder(let row, _): try text(row._id, limit: 128); try text(row.name, limit: LibrarySyncLimits.savedFactSourceBytes, empty: true); try time(row.createdAt)
        }
    }
    static func fold(_ fact: SavedFact, previous: LibrarySavedProjection?) throws -> LibrarySavedProjection {
        try validate(fact); let ordinal = try integer(fact.ordinalValue), first = previous?.firstOrdinal ?? ordinal
        guard first >= 0, first <= ordinal else { throw LibrarySyncFailure.invalidReceipt }
        if case .folder(let value) = fact {
            if let previous { guard case .folder(let row, _) = previous, row._id == value.value._id else { throw LibrarySyncFailure.invalidReceipt } }
            return .folder(value.value, firstOrdinal: first)
        }
        let prior: SavedPrivateItem?
        if let previous { guard case .item(let value, _) = previous, value.hadithId == fact.targetID else { throw LibrarySyncFailure.invalidReceipt }; try validate(value); prior = value }
        else { prior = nil }
        if case .item(let value) = fact { return .item(value.value, firstOrdinal: first) }
        let stamp: Double
        switch fact { case .bookmark(let v): stamp = v.createdAt; case .favorite(let v): stamp = v.createdAt; case .note(let v): stamp = v.updatedAt; default: throw LibrarySyncFailure.invalidReceipt }
        var bookmark = prior?.bookmarkCreatedAt, favorite = prior?.favoriteCreatedAt, content = prior?.noteContent, noteCreated = prior?.noteCreatedAt, noteUpdated = prior?.noteUpdatedAt
        let created: Double, updated: Double
        switch fact {
        case .bookmark(let v): bookmark = min(bookmark ?? v.createdAt, v.createdAt); created = min(prior?.createdAt ?? v.createdAt, v.createdAt); updated = prior?.updatedAt ?? v.createdAt
        case .favorite(let v): favorite = min(favorite ?? v.createdAt, v.createdAt); created = min(prior?.createdAt ?? v.createdAt, v.createdAt); updated = prior?.updatedAt ?? v.createdAt
        case .note(let v):
            if (noteUpdated ?? -.infinity) < v.updatedAt { content = v.content; noteCreated = v.createdAt; noteUpdated = v.updatedAt }
            created = min(prior?.createdAt ?? v.createdAt, v.createdAt); updated = max(prior?.updatedAt ?? stamp, stamp)
        default: throw LibrarySyncFailure.invalidReceipt
        }
        let row = SavedPrivateItem(hadithId: fact.targetID, createdAt: created, updatedAt: updated, bookmarkCreatedAt: bookmark, favoriteCreatedAt: favorite, noteContent: content, noteCreatedAt: noteCreated, noteUpdatedAt: noteUpdated, folderId: prior?.folderId, folderUpdatedAt: prior?.folderUpdatedAt)
        try validate(row); return .item(row, firstOrdinal: first)
    }
}

struct LibrarySavedLease: Codable, Equatable, Sendable {
    let owner: LibrarySyncOwner
    let epoch: String
    let generation: String
    func validate() throws {
        guard [owner.key, owner.subject, owner.namespace].allSatisfy({ !$0.isEmpty && $0.utf8.count <= 1024 }),
              [epoch, generation].allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 }) else { throw LibrarySyncFailure.storeUnavailable }
    }
    var key: String { LibraryOutcomeBinding.hash([owner.namespace, owner.subject]) + ":" + LibraryOutcomeBinding.hash([owner.storageKey, owner.subject]) }
    var collection: String { key + ":" + LibraryOutcomeBinding.hash([epoch, generation]) }
    func ordinalKey(_ ordinal: Int) -> String { collection + ":f:" + String(format: "%016llx", UInt64(ordinal)) }
    func inputKey(_ input: String?) -> String { collection + ":p:" + LibraryOutcomeBinding.hash([input == nil ? "absent" : "present", input ?? ""]) }
    func sequenceKey(_ sequence: Int) -> String { collection + ":s:" + String(format: "%016llx", UInt64(sequence)) }
    func sourceKey(_ fact: SavedFact) -> String { collection + ":i:" + LibraryOutcomeBinding.hash([String(fact.sourcePhase), fact.sourceID]) }
    func projectionKey(_ value: LibrarySavedProjection) -> String { collection + ":r:" + LibraryOutcomeBinding.hash([value.kind, value.targetID]) }
}
struct LibrarySavedCounts: Codable, Equatable, Sendable {
    var items = 0, folders = 0
    var total: Int { items + folders }
    mutating func add(_ value: LibrarySavedProjection) { if value.kind == "item" { items += 1 } else { folders += 1 } }
}
enum LibrarySavedStage: Codable, Equatable, Sendable {
    case collecting
    case folding(next: Int, phase: Int, digest: String)
    case checkingPages(next: Int, input: String?, position: LibrarySavedReadPosition?)
    case verifying(after: String?, seen: LibrarySavedCounts)
    case prepared
    case restart
    case unavailable(SavedFactsReplyUnavailableReason)
}
struct LibrarySavedCheckpoint: Codable, Equatable, Sendable {
    var position: LibrarySavedReadPosition?
    var pages = 0
    var digest = LibraryOutcomeBinding.hash(["saved-raw-v1"])
    var counts = LibrarySavedCounts()
    var stage = LibrarySavedStage.collecting
    var next: Int { position?.nextOrdinal ?? 0 }
    func validate(owner: LibrarySyncOwner) throws {
        guard pages >= 0, Double(pages) <= LibrarySavedPolicy.maxInteger, counts.items >= 0, counts.folders >= 0, Double(counts.items) <= LibrarySavedPolicy.maxInteger, Double(counts.folders) <= LibrarySavedPolicy.maxInteger,
              counts.total <= next, digest.count == 64 else { throw LibrarySyncFailure.storeUnavailable }
        if let position {
            guard position.owner == owner, position.nextOrdinal >= 0, Double(position.nextOrdinal) <= LibrarySavedPolicy.maxInteger,
                  (-1...4).contains(position.phase), !position.assemblyID.isEmpty, position.assemblyID.utf8.count <= LibrarySyncLimits.savedFactCursorBytes,
                  !position.continuation.token.isEmpty, position.continuation.token.utf8.count <= LibrarySyncLimits.savedFactCursorBytes else { throw LibrarySyncFailure.storeUnavailable }
            _ = try LibrarySavedPolicy.integer(position.version)
        }
        switch stage {
        case .collecting: if let position { guard case .next = position.continuation else { throw LibrarySyncFailure.storeUnavailable } }
        case .folding(let at, let phase, let checksum):
            guard let position, case .complete = position.continuation, at >= 0, at <= next, (-1...4).contains(phase), checksum.count == 64 else { throw LibrarySyncFailure.storeUnavailable }
        case .checkingPages(let sequence, _, _):
            guard let position, case .complete = position.continuation, sequence >= 0, sequence <= pages else { throw LibrarySyncFailure.storeUnavailable }
        case .verifying(_, let seen):
            guard let position, case .complete = position.continuation, seen.items >= 0, seen.folders >= 0, seen.items <= counts.items, seen.folders <= counts.folders else { throw LibrarySyncFailure.storeUnavailable }
        case .prepared: guard let position, case .complete = position.continuation else { throw LibrarySyncFailure.storeUnavailable }
        case .restart, .unavailable: break
        }
    }
}
enum LibrarySavedReceiptResult: Codable, Equatable, Sendable {
    case advanced(LibrarySavedReadPosition), restart, unavailable(SavedFactsReplyUnavailableReason)
}
struct LibrarySavedPageReceipt: Codable, Equatable, Sendable {
    let sequence: Int
    let input: String?
    let before: LibrarySavedReadPosition?
    let start: Int
    let count: Int
    let fingerprint: String
    let result: LibrarySavedReceiptResult
    func validate(reply: SavedFactsReply, owner: LibrarySyncOwner, facts: [SavedFact]) throws {
        let decision = try LibrarySavedPolicy.inspect(reply, owner: owner, previous: before, requested: input)
        guard fingerprint == (try LibrarySemanticFingerprint.digest(reply, domain: "library-saved-page-v1:")) else { throw LibrarySyncFailure.invalidReceipt }
        switch (decision, result) {
        case (.append(let plan), .advanced(let position)):
            guard plan.position == position, plan.start == start, plan.facts == facts, facts.count == count else { throw LibrarySyncFailure.invalidReceipt }
        case (.restart, .restart): guard facts.isEmpty, count == 0 else { throw LibrarySyncFailure.invalidReceipt }
        case (.unavailable(let a), .unavailable(let b)): guard a == b, facts.isEmpty, count == 0 else { throw LibrarySyncFailure.invalidReceipt }
        default: throw LibrarySyncFailure.invalidReceipt
        }
    }
}
struct LibrarySavedGenerationRecord: Codable, Equatable, Sendable {
    let lease: LibrarySavedLease
    let checkpoint: LibrarySavedCheckpoint
    func validate(scope: LibrarySavedLease, prepared: Bool) throws {
        try lease.validate(); try checkpoint.validate(owner: lease.owner)
        guard lease.owner == scope.owner, lease.epoch == scope.epoch,
              !prepared || checkpoint.stage == .prepared else { throw LibrarySyncFailure.storeUnavailable }
    }
}
enum LibrarySavedExportRecord: Codable, Equatable, Sendable {
    case fact(SavedFact), page(LibrarySavedPageReceipt), projection(LibrarySavedProjection)
}
struct LibrarySavedRawPage: Sendable { let lease: LibrarySavedLease; let checkpoint: LibrarySavedCheckpoint; let facts: [SavedFact]; let next: Int }
struct LibrarySavedProjectionPage: Sendable { let rows: [LibrarySavedProjection]; let next: String?; let done: Bool }
extension LibrarySavedProjection {
    var kind: String { switch self { case .item: "item"; case .folder: "folder" } }
    var targetID: String { switch self { case .item(let v, _): v.hadithId; case .folder(let v, _): v._id } }
    func savedFingerprint() throws -> String {
        let value: String
        switch self {
        case .item(let row, _): value = try LibrarySemanticFingerprint.digest(row, domain: "saved-private-value-v1:")
        case .folder(let row, _): value = try LibrarySemanticFingerprint.digest(row, domain: "saved-private-value-v1:")
        }
        return LibraryOutcomeBinding.hash([kind, String(firstOrdinal), value])
    }
}

struct LibrarySavedExportPage: Sendable { let records: [LibrarySavedExportRecord]; let next: Int; let done: Bool }
extension LibrarySavedPageReceipt {
    func reply(facts: [SavedFact], owner: LibrarySyncOwner) -> SavedFactsReply {
        switch result {
        case .advanced(let position):
            switch position.continuation {
            case .next(let token): return .page(.init(ownerKey: owner.key, version: position.version, assemblyId: position.assemblyID, input: input, start: Double(start), facts: facts, next: token))
            case .complete(let token): return .complete(.init(ownerKey: owner.key, version: position.version, assemblyId: position.assemblyID, input: input, start: Double(start), facts: facts, total: Double(position.nextOrdinal), completion: token))
            }
        case .restart: return .restart(.init(reason: "saved_changed"))
        case .unavailable(let reason): return .unavailable(.init(reason: reason))
        }
    }
}
extension LibrarySavedGenerationRecord {
    func exportMetadata(active: Bool = false) -> [String: LibraryExportValue] {
        let phase: String
        switch checkpoint.stage { case .collecting: phase = "collecting"; case .folding: phase = "folding"; case .checkingPages: phase = "checking_pages"; case .verifying: phase = "verifying"; case .prepared: phase = "prepared"; case .restart: phase = "restart"; case .unavailable: phase = "unavailable" }
        return ["formatVersion": .number(1), "ownerKey": .string(lease.owner.key), "subject": .string(lease.owner.subject), "namespace": .string(lease.owner.namespace),
            "generation": .string(lease.generation), "status": .string(phase), "active": .bool(active), "collectedFacts": .number(Double(checkpoint.next)), "pageCount": .number(Double(checkpoint.pages)),
            "projectedItems": .number(Double(checkpoint.counts.items)), "projectedFolders": .number(Double(checkpoint.counts.folders)), "privateVersion": checkpoint.position.map { .number($0.version) } ?? .null]
    }
}
extension LibrarySavedExportRecord {
    func exportValue() throws -> LibraryExportValue {
        func encoded<T: Encodable>(_ value: T) throws -> LibraryExportValue { try JSONDecoder().decode(LibraryExportValue.self, from: JSONEncoder().encode(value)) }
        switch self {
        case .fact(let fact): return .object(["kind": .string("fact"), "value": try encoded(fact)])
        case .projection(let value):
            let row: LibraryExportValue
            switch value { case .item(let v, _): row = try encoded(v); case .folder(let v, _): row = try encoded(v) }
            return .object(["kind": .string(value.kind), "firstOrdinal": .number(Double(value.firstOrdinal)), "value": row])
        case .page(let receipt):
            let status: String, output: LibraryExportValue
            switch receipt.result { case .advanced(let p): status = "advanced"; output = .string(LibraryOutcomeBinding.hash([p.continuation.token])); case .restart: status = "restart"; output = .null; case .unavailable(let reason): status = reason.rawValue; output = .null }
            return .object(["kind": .string("page"), "sequence": .number(Double(receipt.sequence)), "start": .number(Double(receipt.start)), "count": .number(Double(receipt.count)),
                "fingerprint": .string(receipt.fingerprint), "inputFingerprint": .string(LibraryOutcomeBinding.hash([receipt.input == nil ? "absent" : "present", receipt.input ?? ""])), "status": .string(status), "outputFingerprint": output])
        }
    }
}

struct LibrarySavedReadContext {
    fileprivate let write: LibraryWriteContext
    fileprivate let capability: String
    let validUntil: Double
    var owner: LibrarySyncOwner { write.owner }
}
struct LibrarySavedInvalidation: Equatable, Sendable { let version: Double }
struct LibrarySavedReferenceValue: Equatable, Sendable {
    let hadithID: String
    let providerHadithID: String
    let collectionSlug: String
    let collectionName: String
    let volumeID: String?
    let referenceDisplay: String
}
struct LibrarySavedCompleteText: Equatable, Sendable {
    let reference: HadithRef
    fileprivate init(_ reference: HadithRef) { self.reference = reference }
}
enum LibrarySavedReferenceState: Equatable, Sendable { case available(LibrarySavedReferenceValue), missing, unavailable }
enum LibrarySavedTextState: Equatable, Sendable { case available(LibrarySavedCompleteText), missing, unavailable }
enum LibrarySavedReadPolicy {
    static func target(_ value: String) throws {
        guard !value.isEmpty, value.utf8.count <= 128 else { throw LibrarySyncFailure.invalidReceipt }
    }
    private static func size<T: Encodable>(_ value: T, limit: Int) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes]
        guard try encoder.encode(value).count <= limit else { throw LibrarySyncFailure.invalidReceipt }
    }
    static func invalidation(_ value: SavedReadHead, owner: LibrarySyncOwner) throws -> LibrarySavedInvalidation {
        guard value.ownerKey == owner.key else { throw LibrarySyncFailure.ownerMismatch }
        _ = try LibrarySavedPolicy.integer(value.version)
        return .init(version: value.version)
    }
    private static func identity(_ ownerKey: String, _ hadithID: String, owner: LibrarySyncOwner, target: String) throws {
        try self.target(target)
        guard ownerKey == owner.key else { throw LibrarySyncFailure.ownerMismatch }
        guard hadithID == target else { throw LibrarySyncFailure.invalidReceipt }
    }
    private static func referenceValue(_ value: SavedHadithReference, target: String) throws -> LibrarySavedReferenceValue {
        guard value._id == target, !value.collectionSlug.isEmpty, !value.providerHadithId.isEmpty else { throw LibrarySyncFailure.invalidReceipt }
        return .init(hadithID: target, providerHadithID: value.providerHadithId, collectionSlug: value.collectionSlug, collectionName: value.collectionName, volumeID: value.volumeId, referenceDisplay: value.referenceDisplay)
    }
    static func reference(_ reply: SavedReferenceReply, owner: LibrarySyncOwner, target: String) throws -> LibrarySavedReferenceState {
        try size(reply, limit: LibrarySyncLimits.savedReferenceBytes)
        switch reply {
        case .available(let value):
            try identity(value.ownerKey, value.hadithId, owner: owner, target: target)
            return .available(try referenceValue(value.reference, target: target))
        case .missing(let value): try identity(value.ownerKey, value.hadithId, owner: owner, target: target); return .missing
        case .unavailable(let value):
            try identity(value.ownerKey, value.hadithId, owner: owner, target: target)
            guard value.reason == "reference_too_large" else { throw LibrarySyncFailure.invalidReceipt }; return .unavailable
        }
    }
    static func text(_ reply: SavedTextReply, owner: LibrarySyncOwner, target: String) throws -> LibrarySavedTextState {
        try size(reply, limit: LibrarySyncLimits.savedTextBytes)
        switch reply {
        case .available(let value):
            try identity(value.ownerKey, value.hadithId, owner: owner, target: target)
            let row = value.hadith
            let metadata = try referenceValue(.init(_id: row._id, providerHadithId: row.providerHadithId, collectionSlug: row.collectionSlug, collectionName: row.collectionName, volumeId: row.volumeId, referenceDisplay: row.referenceDisplay), target: target)
            return .available(.init(.init(hadithId: metadata.hadithID, collectionSlug: metadata.collectionSlug, collectionName: metadata.collectionName, volumeId: metadata.volumeID, hadithNumber: metadata.providerHadithID, arabicText: row.arabicText, englishText: row.englishText, referenceDisplay: metadata.referenceDisplay)))
        case .missing(let value): try identity(value.ownerKey, value.hadithId, owner: owner, target: target); return .missing
        case .unavailable(let value):
            try identity(value.ownerKey, value.hadithId, owner: owner, target: target)
            guard value.reason == "text_too_large" else { throw LibrarySyncFailure.invalidReceipt }; return .unavailable
        }
    }
}

struct LibrarySavedViewItem: Codable, Equatable, Sendable {
    var value: SavedPrivateItem
    var collectionSlug: String?
    var removedBy: String?
    var mask: Int { (value.bookmarkCreatedAt == nil ? 0 : 1) | (value.favoriteCreatedAt == nil ? 0 : 2) | (value.noteContent == nil ? 0 : 4) }
    init(value: SavedPrivateItem, collectionSlug: String? = nil, removedBy: String? = nil) { self.value = value; self.collectionSlug = collectionSlug; self.removedBy = removedBy }
    func validate() throws {
        try LibrarySavedPolicy.validate(value)
        for text in [collectionSlug, removedBy].compactMap({ $0 }) { guard !text.isEmpty, text.utf8.count <= 128 else { throw LibrarySyncFailure.invalidReceipt } }
    }
}
enum LibrarySavedViewFacet: String, Codable, CaseIterable, Sendable { case all = "All", bookmarks = "Bookmarks", favorites = "Favorites", notes = "Notes" }
enum LibrarySavedViewFolderSelection: Codable, Equatable, Sendable { case all, unfiled, folder(String) }
struct LibrarySavedViewSelection: Codable, Equatable, Sendable {
    var facet: LibrarySavedViewFacet = .all
    var folder: LibrarySavedViewFolderSelection = .all
    var collection: String?
    func validate() throws {
        var values = collection.map { [$0] } ?? []
        if case .folder(let id) = folder { values.append(id) }
        for value in values { guard !value.isEmpty, value.utf8.count <= 128 else { throw LibrarySyncFailure.invalidChange } }
    }
}
struct LibrarySavedViewIdentity: Codable, Equatable, Sendable {
    let owner: LibrarySyncOwner
    let epoch: String
    let generation: String
    let scope: String
    let key: String
    private enum CodingKeys: String, CodingKey { case owner, epoch, generation }
    init(owner: LibrarySyncOwner, epoch: String, generation: String) {
        self.owner = owner; self.epoch = epoch; self.generation = generation
        let lease = LibrarySavedLease(owner: owner, epoch: epoch, generation: generation); scope = lease.key; key = lease.collection + ":view"
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(owner: try values.decode(LibrarySyncOwner.self, forKey: .owner), epoch: try values.decode(String.self, forKey: .epoch), generation: try values.decode(String.self, forKey: .generation))
    }
    func itemKey(_ id: String) -> String { key + ":i:" + LibraryOutcomeBinding.hash([id]) }
    func folderKey(_ id: String) -> String { key + ":f:" + LibraryOutcomeBinding.hash([id]) }
    func queryPrefix(_ selection: LibrarySavedViewSelection, unresolved: Bool = false) -> String {
        let folder: [String]
        switch selection.folder { case .all: folder = ["all"]; case .unfiled: folder = ["unfiled"]; case .folder(let id): folder = ["folder", id] }
        let collection = unresolved ? ["unresolved"] : selection.collection.map { ["collection", $0] } ?? ["all"]
        return key + ":q:" + LibraryOutcomeBinding.hash([selection.facet.rawValue] + folder + collection) + ":"
    }
    var folderPrefix: String { key + ":d:" }
    func namePrefix(_ name: String) -> String { key + ":n:" + LibraryOutcomeBinding.hash([LibrarySavedViewPolicy.nameKey(name)]) + ":" }
}
struct LibrarySavedViewStamp: Codable, Equatable, Sendable { let identity: LibrarySavedViewIdentity; let serial: Int }
struct LibrarySavedViewTicket: Sendable { let stamp: LibrarySavedViewStamp; let selection: LibrarySavedViewSelection; let after: String }
struct LibrarySavedViewPage: Sendable { let stamp: LibrarySavedViewStamp; let items: [LibrarySavedViewItem]; let next: LibrarySavedViewTicket?; let unresolvedCoverage: Bool }

enum LibrarySavedViewPolicy {
    private static let nameTrim = CharacterSet(charactersIn: "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")
    static func nameKey(_ name: String) -> String { name.trimmingCharacters(in: nameTrim).precomposedStringWithCanonicalMapping.lowercased(with: Locale(identifier: "en_US_POSIX")) }
    private static func bytesKey(_ value: String) -> String { value.utf8.map { String(format: "%02x", $0) }.joined() }
    private static func timeKey(_ value: Double, descending: Bool) throws -> String {
        guard value.isFinite, value >= 0 else { throw LibrarySyncFailure.invalidReceipt }
        let bits = (value == 0 ? 0.0 : value).bitPattern
        return String(format: "%016llx", descending ? ~bits : bits)
    }
    static func rank(_ item: SavedPrivateItem) throws -> String { try timeKey(item.updatedAt, descending: true) + ":" + bytesKey(item.hadithId) }
    static func folderRank(_ folder: SyncFolderRow) throws -> String { try timeKey(folder.createdAt, descending: false) + ":" + bytesKey(folder._id) }
    static func indexKeys(_ identity: LibrarySavedViewIdentity, item: LibrarySavedViewItem) throws -> Set<String> {
        try item.validate(); guard item.mask != 0 else { return [] }
        let facets: [LibrarySavedViewFacet] = [.all] + [item.mask & 1 == 0 ? nil : .bookmarks, item.mask & 2 == 0 ? nil : .favorites, item.mask & 4 == 0 ? nil : .notes].compactMap { $0 }
        let folders: [LibrarySavedViewFolderSelection] = [.all, item.value.folderId.map(LibrarySavedViewFolderSelection.folder) ?? .unfiled]
        let rank = try rank(item.value)
        return Set(facets.flatMap { facet in folders.flatMap { folder in
            let global = LibrarySavedViewSelection(facet: facet, folder: folder)
            return [identity.queryPrefix(global) + rank, identity.queryPrefix(.init(facet: facet, folder: folder, collection: item.collectionSlug), unresolved: item.collectionSlug == nil) + rank]
        } })
    }
    static func matches(_ item: LibrarySavedViewItem, selection: LibrarySavedViewSelection) throws -> Bool {
        try item.validate()
        let facet: Bool
        switch selection.facet { case .all: facet = item.mask != 0; case .bookmarks: facet = item.mask & 1 != 0; case .favorites: facet = item.mask & 2 != 0; case .notes: facet = item.mask & 4 != 0 }
        let folder: Bool
        switch selection.folder { case .all: folder = true; case .unfiled: folder = item.value.folderId == nil; case .folder(let id): folder = item.value.folderId == id }
        return facet && folder && (selection.collection == nil || item.collectionSlug == selection.collection)
    }
    static func target(_ command: SyncCommand) -> String? {
        switch command {
        case .bookmarkAdd(let v): v.hadithId; case .bookmarkRemove(let v): v.hadithId
        case .favoriteAdd(let v): v.hadithId; case .favoriteRemove(let v): v.hadithId
        case .notePut(let v): v.hadithId; case .noteRemove(let v): v.hadithId
        case .membershipPut(let v): v.hadithId; case .facetRestore(let v): v.hadithId
        case .folderCreate, .folderDelete, .folderRestore, .positionPut, .legacyPositionPut: nil
        }
    }
    static func point(_ current: LibrarySavedViewItem?, change: LibraryLocalChange, outcome: SyncOutcome?, mappings: [String: String], route: String?) throws -> LibrarySavedViewItem? {
        let command = change.operation.command, at = change.operation.at
        guard let target = target(command) else { throw LibrarySyncFailure.invalidChange }
        guard current == nil || current?.value.hadithId == target else { throw LibrarySyncFailure.ownerMismatch }
        var item = current ?? .init(value: .init(hadithId: target, createdAt: at, updatedAt: at, bookmarkCreatedAt: nil, favoriteCreatedAt: nil, noteContent: nil, noteCreatedAt: nil, noteUpdatedAt: nil, folderId: nil, folderUpdatedAt: nil), collectionSlug: route)
        var bookmark = item.value.bookmarkCreatedAt, favorite = item.value.favoriteCreatedAt
        var content = item.value.noteContent, noteCreated = item.value.noteCreatedAt, noteUpdated = item.value.noteUpdatedAt
        var folderID = item.value.folderId, folderUpdated = item.value.folderUpdatedAt, updated = item.value.updatedAt
        func folder(_ reference: SyncFolderReference) -> String? { switch reference { case .none: nil; case .server(let value): value.id; case .local(let value): mappings[value.key] ?? "local:" + value.key } }
        switch command {
        case .bookmarkAdd(let value): bookmark = min(bookmark ?? value.createdAt, value.createdAt); updated = max(updated, at)
        case .favoriteAdd(let value): favorite = min(favorite ?? value.createdAt, value.createdAt); updated = max(updated, at)
        case .notePut(let value): content = value.content; noteCreated = noteCreated ?? value.createdAt; noteUpdated = value.updatedAt; updated = max(updated, value.updatedAt)
        case .bookmarkRemove: guard current != nil else { return nil }; bookmark = nil; updated = max(updated, at)
        case .favoriteRemove: guard current != nil else { return nil }; favorite = nil; updated = max(updated, at)
        case .noteRemove: guard current != nil else { return nil }; content = nil; noteCreated = nil; noteUpdated = nil; updated = max(updated, at)
        case .membershipPut(let value):
            guard current != nil, value.mode != "claim_if_unset" || outcome != nil else { return current }
            folderID = folder(value.folder); folderUpdated = max(folderUpdated ?? 0, at); updated = max(updated, at); item.removedBy = nil
        case .facetRestore(let value):
            switch value.value {
            case .bookmark(let v): bookmark = bookmark ?? v.createdAt
            case .favorite(let v): favorite = favorite ?? v.createdAt
            case .note(let v): content = v.content; noteCreated = v.createdAt; noteUpdated = at
            }
            updated = max(updated, at)
        default: throw LibrarySyncFailure.invalidChange
        }
        item.value = .init(hadithId: target, createdAt: item.value.createdAt, updatedAt: updated, bookmarkCreatedAt: bookmark, favoriteCreatedAt: favorite, noteContent: content, noteCreatedAt: noteCreated, noteUpdatedAt: noteUpdated, folderId: folderID, folderUpdatedAt: folderUpdated)
        if item.mask == 0 { item.removedBy = nil }
        try item.validate(); return item
    }
    private static func placing(_ item: LibrarySavedViewItem, folder: String?, removedBy: String?, at: Double) -> LibrarySavedViewItem {
        let value = item.value
        return .init(value: .init(hadithId: value.hadithId, createdAt: value.createdAt, updatedAt: max(value.updatedAt, at), bookmarkCreatedAt: value.bookmarkCreatedAt, favoriteCreatedAt: value.favoriteCreatedAt, noteContent: value.noteContent, noteCreatedAt: value.noteCreatedAt, noteUpdatedAt: value.noteUpdatedAt, folderId: folder, folderUpdatedAt: max(value.folderUpdatedAt ?? 0, at)), collectionSlug: item.collectionSlug, removedBy: removedBy)
    }
    static func deleted(_ item: LibrarySavedViewItem, operation: String, at: Double) -> LibrarySavedViewItem { placing(item, folder: nil, removedBy: operation, at: at) }
    static func restored(_ item: LibrarySavedViewItem, folder: String, at: Double) -> LibrarySavedViewItem { placing(item, folder: folder, removedBy: nil, at: at) }
}

struct LibrarySavedViewSnapshot: Codable, Equatable, Sendable { let items: [LibrarySavedViewItem]; let folders: [SyncFolderRow] }
extension LibrarySavedViewPolicy {
    @MainActor static func captureLegacy(_ state: LibraryPartitionState, owner: LibrarySyncOwner, observed: LibrarySavedObservation) throws -> LibrarySavedViewSnapshot {
        guard state.savedSnapshot == nil || state.savedSnapshot?.ownerKey == owner.key else { throw LibrarySyncFailure.ownerMismatch }
        var items: [String: LibrarySavedViewItem] = [:], folders: [String: SyncFolderRow] = [:]
        for row in state.savedSnapshot?.items ?? [] {
            let value = SavedPrivateItem(hadithId: row.hadithId, createdAt: row.createdAt, updatedAt: row.updatedAt, bookmarkCreatedAt: row.bookmarkCreatedAt, favoriteCreatedAt: row.favoriteCreatedAt, noteContent: row.noteContent, noteCreatedAt: row.noteCreatedAt, noteUpdatedAt: row.noteUpdatedAt, folderId: row.folderId, folderUpdatedAt: nil)
            let item = LibrarySavedViewItem(value: value, collectionSlug: row.hadith._id == row.hadithId && !row.hadith.collectionSlug.isEmpty ? row.hadith.collectionSlug : nil)
            try item.validate(); guard items.updateValue(item, forKey: row.hadithId) == nil else { throw LibrarySyncFailure.storeUnavailable }
        }
        for row in state.savedSnapshot?.folders ?? [] {
            try LibrarySavedPolicy.validate(.folder(.init(sourceId: row._id, ordinal: 0, value: row)))
            guard folders.updateValue(row, forKey: row._id) == nil else { throw LibrarySyncFailure.storeUnavailable }
        }
        func folder(_ reference: SyncFolderReference) -> String? { switch reference { case .none: nil; case .server(let value): value.id; case .local(let value): state.folderMappings[value.key] ?? "local:" + value.key } }
        let changes: [(LibraryLocalChange, SyncOutcome?)] = state.confirmed.map { ($0.change, $0.outcome) } + (try state.projectedFrozenChanges(owner: owner, observed: observed)).map { ($0, nil) } + state.pending.map { ($0, nil) }
        for (change, outcome) in changes {
            let at = change.operation.at
            if let target = target(change.operation.command) {
                let reference = change.source.reference
                let route = reference?.hadithId == target ? reference?.collectionSlug : nil
                if let item = try point(items[target], change: change, outcome: outcome, mappings: state.folderMappings, route: route) { items[target] = item }
                continue
            }
            switch change.operation.command {
            case .folderCreate(let value):
                let id = state.folderMappings[value.key] ?? "local:" + value.key
                folders[id] = folders[id] ?? .init(_id: id, name: value.name, createdAt: at)
            case .folderDelete(let value):
                if let id = folder(value.folder) {
                    folders.removeValue(forKey: id)
                    for (target, item) in items where item.value.folderId == id { items[target] = deleted(item, operation: change.operation.id, at: at) }
                }
            case .folderRestore(let value):
                let id: String, targets: [String]
                if case .folderRestored(let result) = outcome { id = result.folderId; targets = result.restored }
                else {
                    let match = try folders.values.filter { nameKey($0.name) == nameKey(value.name) }.sorted { try folderRank($0) < folderRank($1) }.first
                    id = match?._id ?? state.folderMappings["restore:" + value.deletionId] ?? "local:restore:" + value.deletionId; targets = value.hadithIds
                }
                folders[id] = folders[id] ?? .init(_id: id, name: value.name, createdAt: at)
                if outcome == nil && value.hadithIds.isEmpty {
                    for (target, item) in items where item.removedBy == value.deletionId && item.value.folderId == nil && item.mask != 0 { items[target] = restored(item, folder: id, at: at) }
                } else { for target in targets { if let item = items[target] { items[target] = restored(item, folder: id, at: at) } } }
            case .positionPut, .legacyPositionPut: break
            default: throw LibrarySyncFailure.invalidChange
            }
        }
        let result = try LibrarySavedViewSnapshot(items: items.values.filter { $0.mask != 0 }.sorted { try rank($0.value) < rank($1.value) }, folders: folders.values.sorted { try folderRank($0) < folderRank($1) })
        for item in result.items { try item.validate() }; for folder in result.folders { try LibrarySavedPolicy.validate(.folder(.init(sourceId: folder._id, ordinal: 0, value: folder))) }; return result
    }
}

enum LibrarySavedViewChanged: Error { case stale }
struct LibrarySavedViewFolderTicket: Sendable { let stamp: LibrarySavedViewStamp; let name: String?; let after: String }
struct LibrarySavedViewFolderPage: Sendable { let stamp: LibrarySavedViewStamp; let folders: [SyncFolderRow]; let next: LibrarySavedViewFolderTicket? }


// Integrity of a compiled snapshot is distinct from current server/queue coverage.
struct LibrarySavedViewManifest: Codable, Equatable, Sendable {
    let items: Int
    let folders: Int
    let indexes: Int
    let digest: String
    var bindings: Int? = nil
    static var initialDigest: String { LibraryOutcomeBinding.hash(["saved-view-manifest-v1"]) }
    func validate() throws {
        guard [items, folders, indexes].allSatisfy({ (0...9_007_199_254_740_990).contains($0) }),
              digest.count == 64, digest.allSatisfy({ "0123456789abcdef".contains($0) }), (0...indexes).contains(bindings ?? 0), indexes <= items * 16 + folders * 2 + (bindings ?? 0) else { throw LibrarySyncFailure.invalidReceipt }
    }
    static func make(_ identity: LibrarySavedViewIdentity, source: LibrarySavedViewSnapshot) throws -> Self {
        var rows: [String: String] = [:], indexes = 0
        func insert<T: Encodable>(_ key: String, value: T) throws {
            guard rows[key] == nil else { throw LibrarySyncFailure.invalidChange }
            rows[key] = try LibrarySemanticFingerprint.digest(JSONDecoder().decode(LibraryExportValue.self, from: JSONEncoder().encode(value)), domain: "saved-view-row-v1:")
        }
        for item in source.items {
            try item.validate(); guard item.mask != 0 else { throw LibrarySyncFailure.invalidChange }
            try insert(identity.itemKey(item.value.hadithId), value: item)
            indexes += try LibrarySavedViewPolicy.indexKeys(identity, item: item).count
        }
        for folder in source.folders {
            try LibrarySavedPolicy.validate(.folder(.init(sourceId: folder._id, ordinal: 0, value: folder)))
            try insert(identity.folderKey(folder._id), value: folder); indexes += 2
        }
        var digest = initialDigest
        for (key, fingerprint) in rows.sorted(by: { $0.key < $1.key }) { digest = LibraryOutcomeBinding.hash([digest, key, fingerprint]) }
        let value = Self(items: source.items.count, folders: source.folders.count, indexes: indexes, digest: digest); try value.validate(); return value
    }
}
enum LibrarySavedViewAuditPhase: String, Codable, Sendable { case rows, indexes, verified }
struct LibrarySavedViewAudit: Codable, Equatable, Sendable {
    let serial: Int
    let manifest: LibrarySavedViewManifest
    var phase: LibrarySavedViewAuditPhase = .rows
    var after: String?
    var items: Int = 0
    var folders: Int = 0
    var indexes: Int = 0
    var digest: String = LibrarySavedViewManifest.initialDigest
    func validate(_ stamp: LibrarySavedViewStamp) throws {
        try manifest.validate()
        guard serial == stamp.serial, (0...manifest.items).contains(items), (0...manifest.folders).contains(folders), (0...manifest.indexes).contains(indexes), digest.count == 64, digest.allSatisfy({ "0123456789abcdef".contains($0) }),
              after.map({ $0.utf8.count <= 1024 && $0.hasPrefix(stamp.identity.key + ":") }) ?? true else { throw LibrarySyncFailure.invalidReceipt }
        if phase != .rows { guard items == manifest.items, folders == manifest.folders, digest == manifest.digest else { throw LibrarySyncFailure.invalidReceipt } }
        if phase == .verified { guard indexes == manifest.indexes, after == nil else { throw LibrarySyncFailure.invalidReceipt } }
    }
}


struct LibrarySavedReplayEntry: Codable, Equatable, Sendable { let operation: SyncOperation; let outcome: SyncOutcome?; let route: String? }
struct LibrarySavedReplayCut: Sendable {
    let entries: [LibrarySavedReplayEntry]
    let mappings: [String: String]
    let routes: [String: String]
    let prefixes: [String]
    @MainActor init(_ state: LibraryPartitionState, source: LibrarySavedGenerationRecord) throws {
        try source.validate(scope: source.lease, prepared: true)
        guard let version = source.checkpoint.position?.version else { throw LibrarySyncFailure.invalidReceipt }
        guard state.savedSnapshot == nil || state.savedSnapshot?.ownerKey == source.lease.owner.key else { throw LibrarySyncFailure.ownerMismatch }
        let collecting = state.collectingOutcome
        let frozen = (state.frozen?.changes ?? []).filter { change in
            guard !change.operation.command.isPositionChange else { return false }
            guard let collecting else { return true }
            if case .folderDelete = change.operation.command { return version < collecting.committed.revision.saved }; return false
        }
        let changes: [(LibraryLocalChange, SyncOutcome?)] = state.confirmed.filter { !$0.change.operation.command.isPositionChange && $0.version > version }.map { ($0.change, $0.outcome) } + frozen.map { ($0, nil) } + state.pending.filter { !$0.operation.command.isPositionChange }.map { ($0, nil) }
        entries = try changes.map { change, outcome in
            guard LibrarySyncAdmission.accepts(change.operation.command, at: change.operation.at) else { throw LibrarySyncFailure.invalidChange }
            let target = LibrarySavedViewPolicy.target(change.operation.command), reference = change.source.reference
            return .init(operation: change.operation, outcome: outcome, route: reference?.hadithId == target ? reference?.collectionSlug : nil)
        }
        guard Set(entries.map { $0.operation.id }).count == entries.count else { throw LibrarySyncFailure.invalidReceipt }
        mappings = state.folderMappings
        var routes: [String: String] = [:]
        for row in state.savedSnapshot?.items ?? [] where row.hadith._id == row.hadithId && !row.hadith.collectionSlug.isEmpty { routes[row.hadithId] = row.hadith.collectionSlug }
        self.routes = routes
        let mappingsDigest = try LibrarySemanticFingerprint.digest(mappings, domain: "saved-build-mappings-v1:"), routesDigest = try LibrarySemanticFingerprint.digest(routes, domain: "saved-build-routes-v1:")
        var prefixes = [LibraryOutcomeBinding.hash(["saved-build-cut-v1", mappingsDigest, routesDigest])]
        for entry in entries { prefixes.append(LibraryOutcomeBinding.hash([prefixes[prefixes.count - 1], try LibrarySemanticFingerprint.digest(entry, domain: "saved-build-entry-v1:")])) }
        self.prefixes = prefixes
    }
    @MainActor func item(_ base: SavedPrivateItem?, target: String, bindings: [Int: String]) throws -> LibrarySavedViewItem? {
        var value = base.map { LibrarySavedViewItem(value: $0, collectionSlug: routes[target]) }
        for (index, entry) in entries.enumerated() {
            let command = entry.operation.command, at = entry.operation.at
            if LibrarySavedViewPolicy.target(command) == target {
                value = try LibrarySavedViewPolicy.point(value, change: .init(operation: entry.operation, source: .account(nil)), outcome: entry.outcome, mappings: mappings, route: entry.route)
            } else {
                switch command {
                case .folderDelete:
                    guard let folder = bindings[index] else { throw LibrarySyncFailure.invalidReceipt }
                    if let item = value, !folder.isEmpty, item.value.folderId == folder { value = LibrarySavedViewPolicy.deleted(item, operation: entry.operation.id, at: at) }
                case .folderRestore(let command):
                    guard let folder = bindings[index] else { throw LibrarySyncFailure.invalidReceipt }
                    if let item = value {
                        let matches: Bool
                        if case .folderRestored(let result) = entry.outcome { matches = result.restored.contains(target) }
                        else if command.hadithIds.isEmpty { matches = item.removedBy == command.deletionId && item.value.folderId == nil && item.mask != 0 }
                        else { matches = command.hadithIds.contains(target) }
                        if matches { value = LibrarySavedViewPolicy.restored(item, folder: folder, at: at) }
                    }
                default: break
                }
            }
        }
        return value
    }
}
enum LibrarySavedBuildPhase: String, Codable, Sendable { case folders, folderCommands, items, pointTargets, manifest, audit, prepared }
struct LibrarySavedBuildRecord: Codable, Equatable, Sendable {
    let source: LibrarySavedGenerationRecord
    var accountRevision: Int
    var commandCount: Int
    var cutDigest: String
    var phase: LibrarySavedBuildPhase = .folders
    var after: String?
    var commandNext: Int = 0
    var seen = LibrarySavedCounts()
    var expected = LibrarySavedCounts()
    var bindings: Int = 0
    var manifest: LibrarySavedViewManifest?
    func validate(_ identity: LibrarySavedViewIdentity) throws {
        try source.validate(scope: source.lease, prepared: true)
        guard source.lease.owner == identity.owner, source.lease.epoch == identity.epoch, (0...9_007_199_254_740_990).contains(accountRevision), commandCount >= 0, (0...commandCount).contains(commandNext), cutDigest.count == 64,
              (0...source.checkpoint.counts.items).contains(seen.items), (0...source.checkpoint.counts.folders).contains(seen.folders), (0...9_007_199_254_740_990).contains(expected.items), (0...9_007_199_254_740_990).contains(expected.folders), (0...commandCount).contains(bindings) else { throw LibrarySyncFailure.invalidReceipt }
        try manifest?.validate()
    }
}
@MainActor final class LibrarySavedBuildSession {
    let identity: LibrarySavedViewIdentity
    let revision: Int
    let cut: LibrarySavedReplayCut
    var bindings: [Int: String]
    init(identity: LibrarySavedViewIdentity, revision: Int, cut: LibrarySavedReplayCut, bindings: [Int: String]) { self.identity = identity; self.revision = revision; self.cut = cut; self.bindings = bindings }
}
enum LibrarySavedBuildChanged: Error { case sourceChanged }

struct LibrarySavedBuildBinding: Codable, Sendable {
    let folder: String
    let digest: String
    init(identity: LibrarySavedViewIdentity, index: Int, cut: LibrarySavedReplayCut, folder: String) {
        self.folder = folder; digest = LibraryOutcomeBinding.hash([identity.key, String(index), cut.prefixes[index + 1], folder])
    }
    func validate(_ identity: LibrarySavedViewIdentity, index: Int, cut: LibrarySavedReplayCut) throws {
        guard folder.utf8.count <= 128, digest == LibraryOutcomeBinding.hash([identity.key, String(index), cut.prefixes[index + 1], folder]) else { throw LibrarySyncFailure.invalidReceipt }
    }
}
