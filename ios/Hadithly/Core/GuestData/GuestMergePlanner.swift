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
}

struct LibraryRecentReceipt: Codable, Equatable, Sendable {
    let receipt: SyncReceipt
    let expiresAt: Double
}

struct LibraryPartitionState: Codable, Equatable, Sendable {
    var pending: [LibraryLocalChange] = []
    var frozen: LibraryFrozenBatch?
    var recovery: [LibraryRecovery] = []
    var recent: [LibraryRecentReceipt] = []
    var clientKey = UUID().uuidString
    var nextSequence = 1

    mutating func append(_ source: LibraryLocalSource, command: SyncCommand?, at: Double) {
        guard let command, at.isFinite, at >= 0 else { recovery.append(.invalid(source)); return }
        pending.append(.init(command: command, at: at, source: source))
    }
    mutating func freeze() throws -> SyncBatch? {
        if let frozen { return frozen.batch }
        guard !pending.isEmpty else { return nil }
        let id = UUID().uuidString
        var selected: [LibraryLocalChange] = []
        for change in pending.prefix(LibrarySyncLimits.operations) {
            let candidate = SyncBatch(id: id, operations: (selected + [change]).map(\.operation))
            if try JSONEncoder().encode(candidate).count > LibrarySyncLimits.bytes { break }
            selected.append(change)
        }
        guard !selected.isEmpty else { throw LibrarySyncFailure.oversizedChange }
        let batch = SyncBatch(id: id, operations: selected.map(\.operation))
        frozen = .init(batch: batch, changes: selected)
        pending.removeFirst(selected.count)
        return batch
    }
    mutating func settle(_ reply: SyncReply, now: Double) throws {
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
}

enum LibrarySyncFailure: Error {
    case storeUnavailable, ownerMismatch, invalidReceipt, oversizedChange, sessionChanged
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
    let send: (String, SyncBatch) async throws -> SyncReply
}

@MainActor
@Observable
final class LibrarySync {
    enum Status: Equatable { case idle, syncing, ready(recovered: Int), failed }
    private(set) var owner: LibrarySyncOwner?
    private(set) var status = Status.idle
    var onOwnerChange: (LibrarySyncOwner?) -> Void = { _ in }
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
        try store.enqueueSyncChange(change, owner: context.owner)
        wake()
    }

    private func check(_ session: LibrarySyncSession, epoch: UUID) throws {
        guard !Task.isCancelled, generation == epoch, currentSession() == session else { throw LibrarySyncFailure.sessionChanged }
    }

    private func run(_ session: LibrarySyncSession, epoch: UUID) async {
        do {
            try check(session, epoch: epoch)
            if binding == nil || (binding?.validUntil ?? 0) <= now() + 1_000 {
                let opened = try await transport.open()
                try check(session, epoch: epoch)
                guard opened.subject == session.subject, opened.validUntil.isFinite, opened.validUntil > now() else { throw LibrarySyncFailure.ownerMismatch }
                binding = opened
                let nextOwner = LibrarySyncOwner(key: opened.ownerKey, subject: opened.subject, namespace: transport.namespace)
                owner = nextOwner
                onOwnerChange(nextOwner)
            }
            guard let binding, let owner else { throw LibrarySyncFailure.ownerMismatch }
            for _ in 0..<4 {
                try check(session, epoch: epoch)
                try store.claimGuestForSync(owner)
                guard let batch = try store.freezeSyncBatch(owner) else {
                    status = .ready(recovered: try store.syncPartition(owner)?.recovery.count ?? 0)
                    retryDelay = 1
                    return
                }
                let reply = try await transport.send(binding.capability, batch)
                // A late A receipt can settle only A's still-existing partition.
                try store.settleSyncBatch(reply, owner: owner, now: now())
                try check(session, epoch: epoch)
            }
            schedule(session, epoch: epoch, after: 0.25)
        } catch is CancellationError { }
        catch LibrarySyncFailure.sessionChanged { }
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
