import Foundation
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
    func intentDigest() throws -> String {
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
        let value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(self))
        return SHA256.hash(data: Data(("library-intent-v1:" + (try encode(value))).utf8)).map { String(format: "%02x", $0) }.joined()
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
struct LibraryOutcomeCheckpoint: Codable, Equatable, Sendable {
    var counts = LibraryOutcomeCounts()
    var status = LibraryOutcomeStatus.collecting
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
    var confirmed: [LibraryConfirmedChange] = []
    var folderMappings: [String: String] = [:]
    var savedSnapshot: SyncSavedSnapshot?
    var positionsSnapshot: SyncPositionsSnapshot?

    private enum CodingKeys: String, CodingKey { case pending, frozen, recovery, recent, clientKey, nextSequence, acknowledgement, waiting, collectingOutcome, confirmed, folderMappings, savedSnapshot, positionsSnapshot }
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
        confirmed = try values.decodeIfPresent([LibraryConfirmedChange].self, forKey: .confirmed) ?? []
        folderMappings = try values.decodeIfPresent([String: String].self, forKey: .folderMappings) ?? [:]
        savedSnapshot = try values.decodeIfPresent(SyncSavedSnapshot.self, forKey: .savedSnapshot)
        positionsSnapshot = try values.decodeIfPresent(SyncPositionsSnapshot.self, forKey: .positionsSnapshot)
    }

    var projectedFrozenChanges: [LibraryLocalChange] {
        guard let collectingOutcome else { return frozen?.changes ?? [] }
        return (frozen?.changes ?? []).filter { change in
            if case .folderDelete = change.operation.command { return (savedSnapshot?.version ?? -1) < collectingOutcome.committed.revision.saved }
            return false
        }
    }

    mutating func pruneConfirmed() {
        confirmed.removeAll { value in
            let observed = value.change.operation.command.isPositionChange ? positionsSnapshot?.version : savedSnapshot?.version
            return (observed ?? -1) >= value.version
        }
    }

    mutating func append(_ source: LibraryLocalSource, command: SyncCommand?, at: Double) {
        guard let command, LibrarySyncAdmission.accepts(command, at: at) else { recovery.append(.invalid(source)); return }
        pending.append(.init(command: command, at: at, source: source))
    }
    mutating func freeze() throws -> SyncFrame? {
        guard acknowledgement == nil, waiting == nil, collectingOutcome == nil else { throw LibrarySyncFailure.invalidReceipt }
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
            case .folderDeletedManifest, .folderRestoredManifest: throw LibrarySyncFailure.invalidReceipt
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
            self.waiting = nil; acknowledgement = nil
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

    mutating func settle(_ exchange: SyncExchange, requested: SyncFrame, now: Double) throws {
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
            let submitted = frozen?.changes ?? []
            try settleReceipts(committed.reply, now: now)
            for change in submitted {
                guard let receipt = committed.reply.receipts.first(where: { $0.id == change.operation.id }) else { throw LibrarySyncFailure.invalidReceipt }
                switch receipt.outcome {
                case .folderDeletedManifest, .folderRestoredManifest: throw LibrarySyncFailure.invalidReceipt
                case .preserved, .folder, .folderDeleted, .folderRestored, .resolvedPosition:
                    let version = change.operation.command.isPositionChange ? committed.revision.position : committed.revision.saved
                    confirmed.append(.init(change: change, outcome: receipt.outcome, version: version))
                case .superseded, .unresolved: break
                }
                if case .folderCreate(let created) = change.operation.command, case .folder(let value) = receipt.outcome { folderMappings[created.key] = value.folderId }
                if case .folderRestore(let restored) = change.operation.command, case .folderRestored(let value) = receipt.outcome { folderMappings["restore:" + restored.deletionId] = value.folderId }
            }
            pruneConfirmed()
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

    mutating func settlePending(_ exchange: SyncExchange, requested: SyncPending, now: Double) throws {
        guard waiting == requested, acknowledgement == nil else { throw LibrarySyncFailure.invalidReceipt }
        switch exchange {
        case .pending(let value):
            guard requested.matches(value.pending) else { throw LibrarySyncFailure.invalidReceipt }
            try adopt(.init(closedThrough: requested.sequence - 1, outstanding: .pending(.init(pending: value.pending))))
        case .accepted(let value):
            let proof = value.committed
            guard proof.clientKey == requested.clientKey, proof.sequence == requested.sequence, proof.reply.batchId == requested.batchId, proof.digest == requested.digest else { throw LibrarySyncFailure.invalidReceipt }
            if let frozen, frozen.batch.id == requested.batchId, (try? frozen.batch.intentDigest()) == requested.intentDigest {
                try settle(exchange, requested: .init(clientKey: clientKey, sequence: requested.sequence, batch: frozen.batch), now: now)
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
}

@MainActor
@Observable
final class LibrarySync {
    enum Status: Equatable { case idle, syncing, ready(recovered: Int), failed }
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
        if let worker { await worker.value; return }
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

    func portableState(for context: LibraryWriteContext) throws -> LibraryExportValue {
        _ = try capability(for: context)
        guard let state = try store.syncPartition(context.owner) else { throw LibrarySyncFailure.sessionChanged }
        let encoded = try JSONEncoder().encode(state)
        return try JSONDecoder().decode(LibraryExportValue.self, from: encoded).withoutProviderPassages
    }

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
                        // Collection alone does not authorize settlement or ACK.
                        status = .failed
                        return
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
                    try store.settleSyncAcknowledgement(reply, requested: acknowledgement, owner: owner)
                    onPartitionChange(owner)
                    try check(session, epoch: epoch)
                    continue
                }
                guard let frame = try store.freezeSyncFrame(owner) else {
                    let state = try store.syncPartition(owner)
                    onPartitionChange(owner)
                    if state?.pending.isEmpty == false { continue }
                    status = .ready(recovered: state?.recovery.count ?? 0)
                    retryDelay = 1
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
            try store.markDeletionBackendComplete(subject: captured.subject, namespace: namespace)
        }
        cleanup(captured.subject)
        guard currentSession() == captured else { throw LibrarySyncFailure.sessionChanged }
        try await deleteIdentity(captured)
        try store.clearDeletion(subject: captured.subject, namespace: namespace)
    }
}
