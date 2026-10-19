import Foundation
import Observation

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
            .map { ($0.hadithId, $0.folderLocalId) })
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
                .init(hadithId: item.hadithId, bookmarkCreatedAt: item.bookmarkCreatedAt, favoriteCreatedAt: item.favoriteCreatedAt, noteContent: item.noteContent, noteCreatedAt: item.noteCreatedAt, noteUpdatedAt: item.noteUpdatedAt, folderLocalId: membershipByHadith[item.hadithId], createdAt: item.createdAt, updatedAt: item.updatedAt)
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
        case .membershipPut(let value): return target(value.hadithId) && folder(value.folder)
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

struct LibraryPartitionState: Codable, Equatable, Sendable {
    var pending: [LibraryLocalChange] = []
    var frozen: LibraryFrozenBatch?
    var recovery: [LibraryRecovery] = []
    var recent: [LibraryRecentReceipt] = []
    var clientKey = UUID().uuidString
    var nextSequence = 1
    var acknowledgement: SyncAcknowledgement?
    var confirmed: [LibraryConfirmedChange] = []
    var folderMappings: [String: String] = [:]
    var savedSnapshot: SyncSavedSnapshot?
    var positionsSnapshot: SyncPositionsSnapshot?

    private enum CodingKeys: String, CodingKey { case pending, frozen, recovery, recent, clientKey, nextSequence, acknowledgement, confirmed, folderMappings, savedSnapshot, positionsSnapshot }
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
        confirmed = try values.decodeIfPresent([LibraryConfirmedChange].self, forKey: .confirmed) ?? []
        folderMappings = try values.decodeIfPresent([String: String].self, forKey: .folderMappings) ?? [:]
        savedSnapshot = try values.decodeIfPresent(SyncSavedSnapshot.self, forKey: .savedSnapshot)
        positionsSnapshot = try values.decodeIfPresent(SyncPositionsSnapshot.self, forKey: .positionsSnapshot)
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
        guard acknowledgement == nil else { throw LibrarySyncFailure.invalidReceipt }
        if let frozen { return SyncFrame(clientKey: clientKey, sequence: Double(nextSequence), batch: frozen.batch) }
        guard !pending.isEmpty else { return nil }
        let id = UUID().uuidString
        var selected: [LibraryLocalChange] = []
        var fanout = 0
        while let change = pending.first, selected.count < LibrarySyncLimits.operations {
            guard LibrarySyncAdmission.accepts(change.operation.command, at: change.operation.at) else {
                recovery.append(.rejected(change)); pending.removeFirst(); continue
            }
            let extra: Int
            switch change.operation.command { case .folderDelete, .folderRestore: extra = 1; default: extra = 0 }
            if fanout + extra > LibrarySyncLimits.fanoutOperations { break }
            let candidate = SyncBatch(id: id, operations: (selected + [change]).map(\.operation))
            if try JSONEncoder().encode(candidate).count > LibrarySyncLimits.bytes {
                if selected.isEmpty { recovery.append(.rejected(change)); pending.removeFirst(); continue }
                break
            }
            selected.append(change); pending.removeFirst(); fanout += extra
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
        if let active = cursor.active {
            guard active.clientKey == clientKey, active.sequence == cursor.closedThrough + 1,
                  !active.reply.batchId.isEmpty, !active.digest.isEmpty else { throw LibrarySyncFailure.invalidReceipt }
        }
    }

    private mutating func adopt(_ cursor: SyncCursor) throws {
        try checkCursor(cursor)
        if let frozen { recovery.append(contentsOf: frozen.changes.map(LibraryRecovery.historical)) }
        frozen = nil
        nextSequence = Int(cursor.closedThrough) + 1
        acknowledgement = cursor.active.map { .init(clientKey: clientKey, sequence: $0.sequence, batchId: $0.reply.batchId, digest: $0.digest) }
    }

    mutating func settle(_ exchange: SyncExchange, requested: SyncFrame, now: Double) throws {
        guard requested.clientKey == clientKey, requested.sequence == Double(nextSequence), frozen?.batch == requested.batch,
              acknowledgement == nil else { throw LibrarySyncFailure.invalidReceipt }
        switch exchange {
        case .accepted(let value):
            let committed = value.committed
            guard committed.clientKey == clientKey, committed.sequence == requested.sequence, !committed.digest.isEmpty else { throw LibrarySyncFailure.invalidReceipt }
            let submitted = frozen?.changes ?? []
            try settleReceipts(committed.reply, now: now)
            for change in submitted {
                guard let receipt = committed.reply.receipts.first(where: { $0.id == change.operation.id }) else { throw LibrarySyncFailure.invalidReceipt }
                switch receipt.outcome {
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
        case .reconcile(let value):
            guard value.clientKey == clientKey, value.requestedSequence == requested.sequence, value.requestedBatchId == requested.batch.id else { throw LibrarySyncFailure.invalidReceipt }
            try adopt(value.cursor)
        }
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
                if let acknowledgement = try store.syncPartition(owner)?.acknowledgement {
                    let reply = try await transport.acknowledge(binding.capability, acknowledgement)
                    try store.settleSyncAcknowledgement(reply, requested: acknowledgement, owner: owner)
                    onPartitionChange(owner)
                    try check(session, epoch: epoch)
                    continue
                }
                guard let frame = try store.freezeSyncFrame(owner) else {
                    status = .ready(recovered: try store.syncPartition(owner)?.recovery.count ?? 0)
                    retryDelay = 1
                    return
                }
                let reply = try await transport.send(binding.capability, frame)
                // A late A receipt can settle only A's still-existing partition.
                try store.settleSyncExchange(reply, requested: frame, owner: owner, now: now())
                onPartitionChange(owner)
                try check(session, epoch: epoch)
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
