import Foundation
import Observation
import SwiftData

/// Owns the on-device guest store. Guests read everything through Convex but
/// their bookmarks, favorites, notes, and reading progress never touch the
/// server until sign-in, when the planner builds a payload and the store
/// clears after a confirmed merge.
@MainActor
@Observable
final class GuestDataStore {
    /// Observable so views can react to local insertions without re-fetching.
    private(set) var itemCount = 0
    private(set) var lastWriteFailed = false
    var onGuestChanged: (() -> Void)?

    private let container: ModelContainer
    private let context: ModelContext
    private let exportDirectory: URL
    private var exportCleanupDone = false
    private var savedCollectionRunning = false

    static var schema: Schema {
        Schema([
            GuestBookmark.self,
            GuestNote.self,
            GuestFavorite.self,
            GuestSavedFolder.self,
            GuestSavedMembership.self,
            GuestReadingProgress.self,
            GuestLibraryPartition.self,
            GuestAccountDeletion.self,
            GuestOutcomeScope.self,
            GuestOutcomeHeader.self,
            GuestOutcomeMember.self,
            GuestOutcomeClock.self,
            GuestOutcomeInventory.self,
            GuestOutcomeInventoryMigration.self,
            GuestLibraryExportArtifact.self,
            GuestSavedAssembly.self, GuestSavedFactRow.self, GuestSavedPageRow.self, GuestSavedProjectionRow.self,
        ])
    }

    init(inMemory: Bool = false, storeURL: URL? = nil, exportDirectory: URL? = nil) {
        let schema = Self.schema
        let configuration = storeURL.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        self.container = try! ModelContainer(for: schema, configurations: [configuration])
        self.exportDirectory = exportDirectory ?? FileManager.default.temporaryDirectory.appendingPathComponent("LibraryExports", isDirectory: true)
        self.context = ModelContext(container)
        context.autosaveEnabled = false
        refreshCount()
    }

    // MARK: - Bookmarks

    func addBookmark(hadithId: String, createdAt: Date = .now) {
        context.insert(GuestBookmark(hadithId: hadithId, createdAt: createdAt))
        saveGuestChanges()
        refreshCount()
    }

    func addBookmark(draft: GuestBookmarkDraft) {
        let model = GuestBookmark(
            hadithId: draft.hadithId,
            createdAt: draft.createdAt,
            collectionName: draft.collectionName,
            referenceDisplay: draft.referenceDisplay,
            volumeId: draft.volumeId,
            hadithNumber: draft.hadithNumber
        )
        context.insert(model)
        saveGuestChanges()
        refreshCount()
    }

    func removeBookmark(hadithId: String) {
        for model in fetchBookmarks().filter({ $0.hadithId == hadithId }) {
            context.delete(model)
        }
        removeMembershipIfUnsaved(hadithId: hadithId)
        saveGuestChanges()
        refreshCount()
    }

    func isBookmarked(hadithId: String) -> Bool {
        fetchBookmarks().contains { $0.hadithId == hadithId }
    }

    func bookmarkDrafts() -> [GuestBookmarkDraft] {
        fetchBookmarks().map {
            GuestBookmarkDraft(
                hadithId: $0.hadithId,
                createdAt: $0.createdAt,
                collectionName: $0.collectionName,
                referenceDisplay: $0.referenceDisplay,
                volumeId: $0.volumeId,
                hadithNumber: $0.hadithNumber
            )
        }
    }

    // MARK: - Favorites

    func addFavorite(draft: GuestFavoriteDraft) {
        context.insert(
            GuestFavorite(
                hadithId: draft.hadithId,
                createdAt: draft.createdAt,
                collectionName: draft.collectionName,
                referenceDisplay: draft.referenceDisplay,
                volumeId: draft.volumeId,
                hadithNumber: draft.hadithNumber
            )
        )
        saveGuestChanges()
        refreshCount()
    }

    func removeFavorite(hadithId: String) {
        for model in fetchFavorites().filter({ $0.hadithId == hadithId }) {
            context.delete(model)
        }
        removeMembershipIfUnsaved(hadithId: hadithId)
        saveGuestChanges()
        refreshCount()
    }

    func isFavorite(hadithId: String) -> Bool {
        fetchFavorites().contains { $0.hadithId == hadithId }
    }

    func favoriteDrafts() -> [GuestFavoriteDraft] {
        fetchFavorites().map {
            GuestFavoriteDraft(
                hadithId: $0.hadithId,
                createdAt: $0.createdAt,
                collectionName: $0.collectionName,
                referenceDisplay: $0.referenceDisplay,
                volumeId: $0.volumeId,
                hadithNumber: $0.hadithNumber
            )
        }
    }

    // MARK: - Notes

    func addNote(hadithId: String, content: String, createdAt: Date = .now, updatedAt: Date = .now) {
        context.insert(GuestNote(hadithId: hadithId, content: content, createdAt: createdAt, updatedAt: updatedAt))
        saveGuestChanges()
        refreshCount()
    }

    /// Creates or updates the note on a hadith, carrying display metadata.
    func saveNote(
        hadithId: String,
        content: String,
        collectionName: String?,
        referenceDisplay: String?,
        volumeId: String?,
        hadithNumber: String?
    ) {
        let now = Date.now
        if let existing = fetchNotes().first(where: { $0.hadithId == hadithId }) {
            existing.content = content
            existing.updatedAt = now
            existing.collectionName = existing.collectionName ?? collectionName
            existing.referenceDisplay = existing.referenceDisplay ?? referenceDisplay
            existing.volumeId = existing.volumeId ?? volumeId
            existing.hadithNumber = existing.hadithNumber ?? hadithNumber
        } else {
            context.insert(
                GuestNote(
                    hadithId: hadithId,
                    content: content,
                    createdAt: now,
                    updatedAt: now,
                    collectionName: collectionName,
                    referenceDisplay: referenceDisplay,
                    volumeId: volumeId,
                    hadithNumber: hadithNumber
                )
            )
        }
        saveGuestChanges()
        refreshCount()
    }

    func deleteNote(hadithId: String) {
        for model in fetchNotes().filter({ $0.hadithId == hadithId }) {
            context.delete(model)
        }
        removeMembershipIfUnsaved(hadithId: hadithId)
        saveGuestChanges()
        refreshCount()
    }

    // MARK: - Saved folders

    func createSavedFolder(name: String) -> GuestSavedFolderDraft? {
        guard Self.validFolderName(name) else { return nil }
        let folder = GuestSavedFolder(name: name.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping)
        context.insert(folder)
        saveGuestChanges()
        return GuestSavedFolderDraft(localId: folder.localId, name: folder.name, createdAt: folder.createdAt)
    }

    func assignSavedFolder(hadithId: String, folderLocalId: String?) {
        let hasFacet = isBookmarked(hadithId: hadithId) || isFavorite(hadithId: hadithId) || fetchNotes().contains { $0.hadithId == hadithId }
        guard hasFacet else { return }
        for membership in fetchMemberships().filter({ $0.hadithId == hadithId }) { context.delete(membership) }
        if let folderLocalId, fetchFolders().contains(where: { $0.localId == folderLocalId }) {
            context.insert(GuestSavedMembership(hadithId: hadithId, folderLocalId: folderLocalId))
        }
        saveGuestChanges()
    }

    func deleteSavedFolder(localId: String) -> GuestFolderDeletion? {
        guard let folder = fetchFolders().first(where: { $0.localId == localId }) else { return nil }
        let hadithIds = fetchMemberships().filter({ $0.folderLocalId == localId }).map(\.hadithId)
        for membership in fetchMemberships().filter({ $0.folderLocalId == localId }) { context.delete(membership) }
        context.delete(folder)
        saveGuestChanges()
        return GuestFolderDeletion(folder: .init(localId: folder.localId, name: folder.name, createdAt: folder.createdAt), hadithIds: hadithIds)
    }

    func restoreSavedFolder(_ deletion: GuestFolderDeletion) {
        guard !fetchFolders().contains(where: { $0.localId == deletion.folder.localId }) else { return }
        context.insert(GuestSavedFolder(localId: deletion.folder.localId, name: deletion.folder.name, createdAt: deletion.folder.createdAt))
        let savedHadithIds = Set(bookmarkDrafts().map(\.hadithId) + favoriteDrafts().map(\.hadithId) + noteDrafts().map(\.hadithId))
        for hadithId in deletion.hadithIds where savedHadithIds.contains(hadithId) && !fetchMemberships().contains(where: { $0.hadithId == hadithId }) {
            context.insert(GuestSavedMembership(hadithId: hadithId, folderLocalId: deletion.folder.localId))
        }
        saveGuestChanges()
    }

    func folderDrafts() -> [GuestSavedFolderDraft] {
        fetchFolders().map { GuestSavedFolderDraft(localId: $0.localId, name: $0.name, createdAt: $0.createdAt) }
    }

    func savedMembershipDrafts() -> [GuestSavedMembershipDraft] {
        fetchMemberships().map { GuestSavedMembershipDraft(hadithId: $0.hadithId, folderLocalId: $0.folderLocalId, updatedAt: $0.updatedAt) }
    }

    func noteDrafts() -> [GuestNoteDraft] {
        fetchNotes().map {
            GuestNoteDraft(
                hadithId: $0.hadithId,
                content: $0.content,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                collectionName: $0.collectionName,
                referenceDisplay: $0.referenceDisplay,
                volumeId: $0.volumeId,
                hadithNumber: $0.hadithNumber
            )
        }
    }

    // MARK: - Reading progress

    /// Upserts the per-collection reading position, keeping the newest entry.
    func saveProgress(draft: GuestReadingProgressDraft) {
        let existing = fetchProgress().first { $0.collectionSlug == draft.collectionSlug }
        if let existing {
            let storedPosition = existing.positionData.flatMap {
                try? JSONDecoder().decode(ReadingPosition.self, from: $0)
            }
            let existingUpdatedAt = storedPosition.map {
                Date(timeIntervalSince1970: $0.updatedAt / 1_000)
            } ?? existing.updatedAt
            guard draft.effectiveUpdatedAt > existingUpdatedAt else { return }
            existing.hadithId = draft.hadithId
            existing.volumeId = draft.volumeId
            existing.hadithNumber = draft.hadithNumber
            existing.referenceDisplay = draft.referenceDisplay
            existing.positionData = draft.position.flatMap { try? JSONEncoder().encode($0) }
            existing.updatedAt = draft.effectiveUpdatedAt
        } else {
            context.insert(
                GuestReadingProgress(
                    collectionSlug: draft.collectionSlug,
                    collectionName: draft.collectionName,
                    hadithId: draft.hadithId,
                    volumeId: draft.volumeId,
                    hadithNumber: draft.hadithNumber,
                    referenceDisplay: draft.referenceDisplay,
                    positionData: draft.position.flatMap { try? JSONEncoder().encode($0) },
                    updatedAt: draft.effectiveUpdatedAt
                )
            )
        }
        saveGuestChanges()
    }

    func progressDrafts() -> [GuestReadingProgressDraft] {
        fetchProgress().map {
            GuestReadingProgressDraft(
                collectionSlug: $0.collectionSlug,
                collectionName: $0.collectionName,
                hadithId: $0.hadithId,
                volumeId: $0.volumeId,
                hadithNumber: $0.hadithNumber,
                referenceDisplay: $0.referenceDisplay,
                updatedAt: $0.updatedAt,
                position: $0.positionData.flatMap { try? JSONDecoder().decode(ReadingPosition.self, from: $0) }
            )
        }
    }

    // MARK: - Durable account partitions

    private func partitionRow(_ owner: LibrarySyncOwner, in db: ModelContext) throws -> GuestLibraryPartition? {
        guard [owner.key, owner.subject, owner.namespace].allSatisfy({ !$0.isEmpty && $0.utf8.count <= 1_024 }),
              !owner.key.contains("|"), !owner.namespace.contains("|") else { throw LibrarySyncFailure.ownerMismatch }
        let key = owner.storageKey
        var descriptor = FetchDescriptor<GuestLibraryPartition>(predicate: #Predicate { $0.ownerKey == key })
        descriptor.fetchLimit = 2
        let rows = try db.fetch(descriptor)
        guard rows.count <= 1 else { throw LibrarySyncFailure.storeUnavailable }
        guard rows.first == nil || rows.first?.subject == owner.subject else { throw LibrarySyncFailure.ownerMismatch }
        return rows.first
    }
    private func syncPartition(_ owner: LibrarySyncOwner, in db: ModelContext) throws -> LibraryPartitionState? {
        guard let row = try partitionRow(owner, in: db) else { return nil }
        do { return try JSONDecoder().decode(LibraryPartitionState.self, from: row.stateData) }
        catch { throw LibrarySyncFailure.storeUnavailable }
    }
    func syncPartition(_ owner: LibrarySyncOwner) throws -> LibraryPartitionState? {
        try syncPartition(owner, in: outcomeContext())
    }
    private func withAccount<T>(_ owner: LibrarySyncOwner, _ body: (inout LibraryPartitionState, ModelContext) throws -> T) throws -> T {
        let db = outcomeContext()
        try assertOutcomeOwnerActive(owner, in: db)
        guard var state = try syncPartition(owner, in: db), let row = try partitionRow(owner, in: db) else { throw LibrarySyncFailure.sessionChanged }
        let before = state
        do {
            let result = try body(&state, db)
            if state != before {
                row.stateData = try JSONEncoder().encode(state)
                try bumpOutcomeClock(subject: owner.subject, namespace: owner.namespace, in: db)
            }
            if db.hasChanges { try saveOutcomeContext(db) }
            return result
        } catch { db.rollback(); throw error }
    }

    /// The claim and guest removal share one SwiftData commit, with no network await.
    func claimGuestForSync(_ owner: LibrarySyncOwner) throws {
        let db = outcomeContext()
        guard try deletionRow(subject: owner.subject, namespace: owner.namespace, in: db) == nil else { throw LibrarySyncFailure.accountDeleting }
        let bookmarks = try db.fetch(FetchDescriptor<GuestBookmark>())
        let favorites = try db.fetch(FetchDescriptor<GuestFavorite>())
        let notes = try db.fetch(FetchDescriptor<GuestNote>())
        let folders = try db.fetch(FetchDescriptor<GuestSavedFolder>())
        let memberships = try db.fetch(FetchDescriptor<GuestSavedMembership>())
        let positions = try db.fetch(FetchDescriptor<GuestReadingProgress>())
        let before = try syncPartition(owner, in: db)
        var state = before ?? LibraryPartitionState()
        for row in folders {
            let draft = GuestSavedFolderDraft(localId: row.localId, name: row.name, createdAt: row.createdAt)
            let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let command: SyncCommand? = Self.validFolderName(name)
                ? .folderCreate(.init(key: row.localId, name: row.name, purpose: .guestClaim)) : nil
            state.append(.folder(draft), command: command, at: row.createdAt.millisecondsSinceEpoch)
        }
        for row in bookmarks {
            let draft = GuestBookmarkDraft(hadithId: row.hadithId, createdAt: row.createdAt, collectionName: row.collectionName, referenceDisplay: row.referenceDisplay, volumeId: row.volumeId, hadithNumber: row.hadithNumber)
            state.append(.bookmark(draft), command: .bookmarkAdd(.init(hadithId: row.hadithId, createdAt: row.createdAt.millisecondsSinceEpoch)), at: row.createdAt.millisecondsSinceEpoch)
        }
        for row in favorites {
            let draft = GuestFavoriteDraft(hadithId: row.hadithId, createdAt: row.createdAt, collectionName: row.collectionName, referenceDisplay: row.referenceDisplay, volumeId: row.volumeId, hadithNumber: row.hadithNumber)
            state.append(.favorite(draft), command: .favoriteAdd(.init(hadithId: row.hadithId, createdAt: row.createdAt.millisecondsSinceEpoch)), at: row.createdAt.millisecondsSinceEpoch)
        }
        for row in notes {
            let draft = GuestNoteDraft(hadithId: row.hadithId, content: row.content, createdAt: row.createdAt, updatedAt: row.updatedAt, collectionName: row.collectionName, referenceDisplay: row.referenceDisplay, volumeId: row.volumeId, hadithNumber: row.hadithNumber)
            let command: SyncCommand? = !row.content.isEmpty && row.content.utf8.count <= LibrarySyncLimits.noteBytes
                ? .notePut(.init(hadithId: row.hadithId, content: row.content, createdAt: row.createdAt.millisecondsSinceEpoch, updatedAt: row.updatedAt.millisecondsSinceEpoch)) : nil
            state.append(.note(draft), command: command, at: row.updatedAt.millisecondsSinceEpoch)
        }
        for row in memberships {
            let draft = GuestSavedMembershipDraft(hadithId: row.hadithId, folderLocalId: row.folderLocalId, updatedAt: row.updatedAt)
            state.append(.membership(draft), command: .membershipPut(.init(hadithId: row.hadithId, folder: .local(.init(key: row.folderLocalId)), mode: row.updatedAt == nil ? "claim_if_unset" : nil)), at: row.updatedAt?.millisecondsSinceEpoch ?? 0)
        }
        for row in positions {
            let draft = GuestReadingProgressDraft(collectionSlug: row.collectionSlug, collectionName: row.collectionName, hadithId: row.hadithId, volumeId: row.volumeId, hadithNumber: row.hadithNumber, referenceDisplay: row.referenceDisplay, updatedAt: row.updatedAt, position: row.positionData.flatMap { try? JSONDecoder().decode(ReadingPosition.self, from: $0) })
            let command: SyncCommand = draft.readingPosition.map { .positionPut(.init(position: $0)) }
                ?? .legacyPositionPut(.init(hadithId: row.hadithId, updatedAt: row.updatedAt.millisecondsSinceEpoch))
            state.append(.position(draft), command: command, at: draft.effectiveUpdatedAt.millisecondsSinceEpoch)
        }
        let data = try JSONEncoder().encode(state)
        if let row = try partitionRow(owner, in: db) { row.stateData = data }
        else { db.insert(GuestLibraryPartition(ownerKey: owner.storageKey, subject: owner.subject, stateData: data)) }
        bookmarks.forEach { db.delete($0) }
        favorites.forEach { db.delete($0) }
        notes.forEach { db.delete($0) }
        folders.forEach { db.delete($0) }
        memberships.forEach { db.delete($0) }
        positions.forEach { db.delete($0) }
        if before != state { try bumpOutcomeClock(subject: owner.subject, namespace: owner.namespace, in: db) }
        do { try db.save() }
        catch { db.rollback(); throw LibrarySyncFailure.storeUnavailable }
        refreshCount()
    }

    func freezeSyncFrame(_ owner: LibrarySyncOwner) throws -> SyncFrame? {
        try withAccount(owner) { state, _ in try state.freeze() }
    }
    func enqueueSyncChange(_ change: LibraryLocalChange, owner: LibrarySyncOwner) throws {
        try withAccount(owner) { state, _ in state.pending.append(change) }
    }

    private func validateSyncOwner(_ owner: LibrarySyncOwner, replyOwner: String, cursor: SyncCursor? = nil) throws {
        guard replyOwner == owner.key, cursor?.outstanding?.committedValue?.reply.ownerKey == nil || cursor?.outstanding?.committedValue?.reply.ownerKey == owner.key else { throw LibrarySyncFailure.ownerMismatch }
    }

    func settleSyncExchange(_ exchange: SyncExchange, requested: SyncFrame, owner: LibrarySyncOwner, now: Double = Date.now.millisecondsSinceEpoch) throws {
        switch exchange {
        case .accepted(let value): try validateSyncOwner(owner, replyOwner: value.committed.reply.ownerKey)
        case .pending(let value): try validateSyncOwner(owner, replyOwner: value.ownerKey)
        case .reconcile(let value): try validateSyncOwner(owner, replyOwner: value.ownerKey, cursor: value.cursor)
        }
        try withAccount(owner) { state, _ in try state.settle(exchange, requested: requested, now: now) }
    }

    func settleSyncPending(_ exchange: SyncExchange, requested: SyncPending, owner: LibrarySyncOwner, now: Double = Date.now.millisecondsSinceEpoch) throws {
        switch exchange {
        case .accepted(let value): try validateSyncOwner(owner, replyOwner: value.committed.reply.ownerKey)
        case .pending(let value): try validateSyncOwner(owner, replyOwner: value.ownerKey)
        case .reconcile(let value): try validateSyncOwner(owner, replyOwner: value.ownerKey, cursor: value.cursor)
        }
        try withAccount(owner) { state, _ in try state.settlePending(exchange, requested: requested, now: now) }
    }

    func settleSyncRetirement(_ reply: SyncAckReply, requested: SyncFrame, owner: LibrarySyncOwner) throws {
        try validateSyncOwner(owner, replyOwner: reply.ownerKey, cursor: reply.cursor)
        try withAccount(owner) { state, _ in try state.settleRetirement(reply, requested: requested) }
    }

    func settleSyncAcknowledgement(_ reply: SyncAckReply, requested: SyncAcknowledgement, owner: LibrarySyncOwner, now: Double = Date.now.millisecondsSinceEpoch) throws {
        try validateSyncOwner(owner, replyOwner: reply.ownerKey, cursor: reply.cursor)
        try withAccount(owner) { state, db in
            let link = state.manifestAckLink
            try state.settleAcknowledgement(reply, requested: requested)
            if let link, reply.cursor.closedThrough >= requested.sequence {
                guard link.owner == owner, link.request.proof == requested else { throw LibrarySyncFailure.invalidReceipt }
                try acknowledgeOutcomeEvidence(link, now: now, in: db)
            }
        }
    }
    private func acknowledgeOutcomeEvidence(_ binding: LibraryOutcomeBinding, now: Double, in db: ModelContext) throws {
        guard now.isFinite, now >= 0, let scope = try outcomeScope(binding.scopeKey, in: db),
              let header = try outcomeHeader(binding.key, in: db), header.generation == scope.generation else { throw LibrarySyncFailure.storeUnavailable }
        var checkpoint = try outcomeCheckpoint(header, binding: binding)
        guard checkpoint.status == .complete, binding.expected.superseded == 0, binding.expected.missing == 0,
              checkpoint.retention?.removed == nil else { throw LibrarySyncFailure.invalidReceipt }
        if checkpoint.retention != nil { return }
        checkpoint.retention = .init(acknowledgedAt: now, removed: nil)
        header.checkpointData = try JSONEncoder().encode(checkpoint)
        try bumpOutcomeClock(subject: binding.owner.subject, namespace: binding.owner.namespace, in: db)
    }

    func pruneOutcomeSuccessStep(_ owner: LibrarySyncOwner, now: Double) throws -> Bool {
        try assertOutcomeOwnerActive(owner)
        guard now.isFinite, now >= 0 else { throw LibrarySyncFailure.invalidReceipt }
        if try !prepareOutcomeInventoryStep() { return true }
        return try withAccount(owner) { active, journal in
            let prefix = LibraryOutcomeBinding.hash([owner.namespace, owner.subject]) + ":"
            let lower = active.outcomeRetentionCursor.map { prefix + $0 + "!" } ?? prefix, upper = prefix + "~"
            var query = FetchDescriptor<GuestOutcomeInventory>(predicate: #Predicate { $0.key >= lower && $0.key < upper }, sortBy: [SortDescriptor(\.key, comparator: .lexical)])
            query.fetchLimit = LibrarySyncLimits.outcomePage
            let inventory = try journal.fetch(query)
            if inventory.isEmpty {
                active.outcomeRetentionCursor = nil
                return false
            }
            var cursor = active.outcomeRetentionCursor
            for entry in inventory {
                guard let header = try outcomeHeader(entry.headerKey, in: journal) else { throw LibrarySyncFailure.storeUnavailable }
                let binding = try JSONDecoder().decode(LibraryOutcomeBinding.self, from: header.bindingData)
                guard binding.owner.subject == owner.subject, binding.owner.namespace == owner.namespace,
                      entry.key == prefix + binding.key else { throw LibrarySyncFailure.ownerMismatch }
                var checkpoint = try outcomeCheckpoint(header, binding: binding)
                let dependencyState = try syncPartition(binding.owner, in: journal)
                let claimed = checkpoint.retention?.removed != nil
                let eligible = dependencyState?.canPruneOutcome(binding, checkpoint: checkpoint, now: now) == true
                // A missing owner partition never supplies Saved/dependency authority.
                if dependencyState != nil && (claimed || eligible) {
                    guard let scope = try outcomeScope(binding.scopeKey, in: journal), scope.generation == header.generation,
                          var retention = checkpoint.retention else { throw LibrarySyncFailure.storeUnavailable }
                    let start = retention.removed ?? 0
                    let rows = try outcomeRows(binding, start: start, limit: checkpoint.next, in: journal)
                    for row in rows {
                        let ordinal = binding.ordinalKey(Int(row.ordinal))
                        var memberQuery = FetchDescriptor<GuestOutcomeMember>(predicate: #Predicate { $0.ordinalKey == ordinal }); memberQuery.fetchLimit = 2
                        let stored = try journal.fetch(memberQuery)
                        guard stored.count == 1 else { throw LibrarySyncFailure.storeUnavailable }
                        journal.delete(stored[0])
                    }
                    retention.removed = start + rows.count
                    if retention.removed == checkpoint.next {
                        let collectionKey = binding.key
                        var remaining = FetchDescriptor<GuestOutcomeMember>(predicate: #Predicate { $0.collectionKey == collectionKey }); remaining.fetchLimit = 1
                        guard try journal.fetch(remaining).isEmpty else { throw LibrarySyncFailure.storeUnavailable }
                        journal.delete(header); journal.delete(entry); cursor = binding.key
                        let storageKey = binding.owner.storageKey, subject = binding.owner.subject, namespace = binding.owner.namespace
                        var others = FetchDescriptor<GuestOutcomeHeader>(predicate: #Predicate { $0.ownerKey == storageKey && $0.subject == subject && $0.namespace == namespace }); others.fetchLimit = 1
                        if try journal.fetch(others).isEmpty { journal.delete(scope) }
                    } else {
                        checkpoint.retention = retention
                        header.checkpointData = try JSONEncoder().encode(checkpoint)
                    }
                    try bumpOutcomeClock(subject: owner.subject, namespace: owner.namespace, in: journal)
                    active.outcomeRetentionCursor = cursor
                    return true
                }
                cursor = binding.key
            }
            active.outcomeRetentionCursor = cursor
            return true
        }
    }

    func settleCollectedOutcome(_ expected: LibraryPendingOutcome, owner: LibrarySyncOwner, now: Double) throws -> LibraryOutcomeSettlement {
        try withAccount(owner) { state, db in
            let binding = try LibraryOutcomeBinding(owner: owner, committed: expected.committed)
            guard let scope = try outcomeScope(binding.scopeKey, in: db), let header = try outcomeHeader(binding.key, in: db), header.generation == scope.generation else { throw LibrarySyncFailure.storeUnavailable }
            return try state.settleCollectedOutcome(expected, binding: binding, checkpoint: outcomeCheckpoint(header, binding: binding), now: now)
        }
    }
    func cacheSavedSnapshot(_ snapshot: SyncSavedSnapshot, owner: LibrarySyncOwner) throws {
        guard snapshot.ownerKey == owner.key else { throw LibrarySyncFailure.ownerMismatch }
        guard snapshot.version.isFinite, snapshot.version >= 0, snapshot.version.rounded(.down) == snapshot.version else { throw LibrarySyncFailure.invalidReceipt }
        try withAccount(owner) { state, _ in
            if snapshot.version >= (state.savedSnapshot?.version ?? -1) { state.savedSnapshot = snapshot; state.pruneConfirmed() }
        }
    }
    func cachePositionsSnapshot(_ snapshot: SyncPositionsSnapshot, owner: LibrarySyncOwner) throws {
        guard snapshot.ownerKey == owner.key else { throw LibrarySyncFailure.ownerMismatch }
        guard snapshot.version.isFinite, snapshot.version >= 0, snapshot.version.rounded(.down) == snapshot.version else { throw LibrarySyncFailure.invalidReceipt }
        try withAccount(owner) { state, _ in
            if snapshot.version >= (state.positionsSnapshot?.version ?? -1) { state.positionsSnapshot = snapshot; state.pruneConfirmed() }
        }
    }

    private func deletionRow(subject: String, namespace: String, in db: ModelContext) throws -> GuestAccountDeletion? {
        var query = FetchDescriptor<GuestAccountDeletion>(predicate: #Predicate { $0.subject == subject && $0.namespace == namespace }); query.fetchLimit = 2
        let rows = try db.fetch(query)
        guard rows.count <= 1 else { throw LibrarySyncFailure.storeUnavailable }
        return rows.first
    }
    private func accountRows(subject: String, namespace: String, in db: ModelContext) throws -> [GuestLibraryPartition] {
        guard !subject.isEmpty, !namespace.isEmpty, !namespace.contains("|") else { throw LibrarySyncFailure.ownerMismatch }
        let lower = namespace + "|", upper = namespace + "}"
        var query = FetchDescriptor<GuestLibraryPartition>(predicate: #Predicate { $0.subject == subject && $0.ownerKey >= lower && $0.ownerKey < upper }, sortBy: [SortDescriptor(\.ownerKey, comparator: .lexical)])
        query.fetchLimit = LibrarySyncLimits.outcomePage
        return try db.fetch(query)
    }
    private func assertAccountScopeErased(subject: String, namespace: String, in db: ModelContext) throws {
        guard try accountRows(subject: subject, namespace: namespace, in: db).isEmpty,
              try !hasSavedRows(subject: subject, namespace: namespace, in: db) else { throw LibrarySyncFailure.storeUnavailable }
        var headers = FetchDescriptor<GuestOutcomeHeader>(predicate: #Predicate { $0.subject == subject && $0.namespace == namespace }); headers.fetchLimit = 1
        var scopes = FetchDescriptor<GuestOutcomeScope>(predicate: #Predicate { $0.subject == subject && $0.namespace == namespace }); scopes.fetchLimit = 1
        var artifacts = FetchDescriptor<GuestLibraryExportArtifact>(predicate: #Predicate { $0.subject == subject && $0.namespace == namespace }); artifacts.fetchLimit = 1
        guard try db.fetch(headers).isEmpty, try db.fetch(scopes).isEmpty, try db.fetch(artifacts).isEmpty else { throw LibrarySyncFailure.storeUnavailable }
    }
    func deletionPhase(subject: String, namespace: String) throws -> LibraryDeletionPhase? {
        let db = outcomeContext()
        guard let row = try deletionRow(subject: subject, namespace: namespace, in: db) else { return nil }
        guard let phase = LibraryDeletionPhase(rawValue: row.phase) else { throw LibrarySyncFailure.storeUnavailable }
        if phase == .identityPending { try assertAccountScopeErased(subject: subject, namespace: namespace, in: db) }
        return phase
    }
    func beginDeletion(subject: String, namespace: String) throws {
        let db = outcomeContext()
        if try deletionRow(subject: subject, namespace: namespace, in: db) == nil {
            db.insert(GuestAccountDeletion(subject: subject, namespace: namespace))
            try bumpOutcomeClock(subject: subject, namespace: namespace, erasing: true, in: db)
        }
        do { try db.save() } catch { db.rollback(); throw LibrarySyncFailure.storeUnavailable }
    }
    func markDeletionBackendComplete(subject: String, namespace: String) async throws {
        guard try deletionPhase(subject: subject, namespace: namespace) != nil else { throw LibrarySyncFailure.sessionChanged }
        try beginSavedErase(subject: subject, namespace: namespace)
        while try eraseSavedStep(subject: subject, namespace: namespace) {
            await Task.yield(); try Task.checkCancellation()
            guard try deletionPhase(subject: subject, namespace: namespace) != nil else { throw LibrarySyncFailure.sessionChanged }
        }
        while true {
            let db = outcomeContext()
            guard try deletionRow(subject: subject, namespace: namespace, in: db) != nil else { throw LibrarySyncFailure.sessionChanged }
            let rows = try accountRows(subject: subject, namespace: namespace, in: db)
            if rows.isEmpty { break }
            rows.forEach { db.delete($0) }
            try bumpOutcomeClock(subject: subject, namespace: namespace, erasing: true, in: db)
            try saveOutcomeContext(db)
            await Task.yield(); try Task.checkCancellation()
        }
        try eraseOutcomeEvidence(subject: subject, namespace: namespace)
        let db = outcomeContext()
        guard let row = try deletionRow(subject: subject, namespace: namespace, in: db) else { throw LibrarySyncFailure.sessionChanged }
        try assertAccountScopeErased(subject: subject, namespace: namespace, in: db)
        row.phase = LibraryDeletionPhase.identityPending.rawValue
        try saveOutcomeContext(db)
    }
    func clearDeletion(subject: String, namespace: String) throws {
        let db = outcomeContext()
        guard let row = try deletionRow(subject: subject, namespace: namespace, in: db) else { return }
        guard row.phase == LibraryDeletionPhase.identityPending.rawValue else { throw LibrarySyncFailure.accountDeleting }
        try assertAccountScopeErased(subject: subject, namespace: namespace, in: db)
        db.delete(row)
        if let clock = try outcomeClock(subject: subject, namespace: namespace, in: db) { db.delete(clock) }
        try saveOutcomeContext(db)
    }

    // Reset fixture only. Account erasure uses the durable deletion intent above.
    func resetSyncPartitionForTesting(_ owner: LibrarySyncOwner) throws {
        let db = outcomeContext()
        try beginSavedErase(subject: owner.subject, namespace: owner.namespace, ownerKey: owner.storageKey)
        while try eraseSavedStep(subject: owner.subject, namespace: owner.namespace, ownerKey: owner.storageKey) { }
        try eraseOutcomeEvidence(subject: owner.subject, namespace: owner.namespace, ownerKey: owner.storageKey)
        if let row = try partitionRow(owner, in: db) { db.delete(row) }
        do { try db.save() }
        catch { db.rollback(); throw LibrarySyncFailure.storeUnavailable }
    }

    // Each page uses a fresh context: a long-lived identity map must not hide a
    // conflicting row saved by a reopened store. MainActor serializes local writes.
    private func outcomeClock(subject: String, namespace: String, in journal: ModelContext) throws -> GuestOutcomeClock? {
        let key = LibraryOutcomeBinding.hash([namespace, subject])
        var query = FetchDescriptor<GuestOutcomeClock>(predicate: #Predicate { $0.key == key }); query.fetchLimit = 2
        let rows = try journal.fetch(query)
        guard rows.count <= 1 else { throw LibrarySyncFailure.storeUnavailable }
        if let row = rows.first {
            guard row.subject == subject, row.namespace == namespace, !row.epoch.isEmpty,
                  row.revision >= 0, row.revision < 9_007_199_254_740_991 else { throw LibrarySyncFailure.storeUnavailable }
        }
        return rows.first
    }
    @discardableResult private func bumpOutcomeClock(subject: String, namespace: String, erasing: Bool = false, in journal: ModelContext) throws -> GuestOutcomeClock {
        if !erasing, try deletionRow(subject: subject, namespace: namespace, in: journal) != nil { throw LibrarySyncFailure.accountDeleting }
        let clock: GuestOutcomeClock
        if let stored = try outcomeClock(subject: subject, namespace: namespace, in: journal) { clock = stored }
        else { clock = GuestOutcomeClock(subject: subject, namespace: namespace); journal.insert(clock) }
        guard erasing || !clock.erasing else { throw LibrarySyncFailure.accountDeleting }
        guard clock.revision < 9_007_199_254_740_990 else { throw LibrarySyncFailure.storeUnavailable }
        clock.revision += 1
        if erasing { clock.erasing = true }
        return clock
    }
    private func insertOutcomeInventory(_ binding: LibraryOutcomeBinding, in journal: ModelContext) throws {
        let expected = GuestOutcomeInventory(binding: binding), key = expected.key
        var query = FetchDescriptor<GuestOutcomeInventory>(predicate: #Predicate { $0.key == key }); query.fetchLimit = 2
        let rows = try journal.fetch(query)
        guard rows.count <= 1 else { throw LibrarySyncFailure.storeUnavailable }
        if let stored = rows.first {
            guard stored.headerKey == binding.key else { throw LibrarySyncFailure.storeUnavailable }
        } else {
            journal.insert(expected)
            try bumpOutcomeClock(subject: binding.owner.subject, namespace: binding.owner.namespace, in: journal)
        }
        if try outcomeClock(subject: binding.owner.subject, namespace: binding.owner.namespace, in: journal) == nil {
            try bumpOutcomeClock(subject: binding.owner.subject, namespace: binding.owner.namespace, in: journal)
        }
    }
    private func prepareOutcomeInventoryStep() throws -> Bool {
        let journal = outcomeContext(), migrationKey = "outcome-inventory-v1"
        var query = FetchDescriptor<GuestOutcomeInventoryMigration>(predicate: #Predicate { $0.key == migrationKey }); query.fetchLimit = 2
        let markers = try journal.fetch(query)
        guard markers.count <= 1 else { throw LibrarySyncFailure.storeUnavailable }
        let marker: GuestOutcomeInventoryMigration
        if let stored = markers.first { marker = stored }
        else { marker = try GuestOutcomeInventoryMigration(); journal.insert(marker) }
        let progress = try JSONDecoder().decode(LibraryOutcomeInventoryProgress.self, from: marker.stateData)
        let after: String, reconciling: Bool
        switch progress {
        case .ready: return true
        case .scanning(let value): after = value; reconciling = false
        case .reconciling(let value): after = value; reconciling = true
        }
        var headersQuery = FetchDescriptor<GuestOutcomeHeader>(predicate: #Predicate { $0.key > after }, sortBy: [SortDescriptor(\.key, comparator: .lexical)])
        headersQuery.fetchLimit = LibrarySyncLimits.outcomePage
        let headers = try journal.fetch(headersQuery)
        for header in headers {
            let binding = try JSONDecoder().decode(LibraryOutcomeBinding.self, from: header.bindingData)
            _ = try outcomeCheckpoint(header, binding: binding)
            // A deleting account never regains clock/index metadata from backfill.
            if try deletionPhase(subject: binding.owner.subject, namespace: binding.owner.namespace) == nil {
                try insertOutcomeInventory(binding, in: journal)
            }
        }
        let next: LibraryOutcomeInventoryProgress
        if let last = headers.last { next = reconciling ? .reconciling(after: last.key) : .scanning(after: last.key) }
        else { next = reconciling ? .ready : .reconciling(after: "") }
        marker.stateData = try JSONEncoder().encode(next)
        try saveOutcomeContext(journal)
        if case .ready = next { return true }
        return false
    }
    func prepareOutcomeExport(_ owner: LibrarySyncOwner, isCurrent: () -> Bool) async throws -> LibraryOutcomeExportFence {
        if !exportCleanupDone { try clearAbandonedOutcomeExports() }
        while true {
            guard isCurrent() else { throw LibrarySyncFailure.sessionChanged }
            try assertOutcomeOwnerActive(owner)
            if try prepareOutcomeInventoryStep() { break }
            await Task.yield()
        }
        guard isCurrent() else { throw LibrarySyncFailure.sessionChanged }
        let journal = outcomeContext()
        if let clock = try outcomeClock(subject: owner.subject, namespace: owner.namespace, in: journal) {
            guard !clock.erasing else { throw LibrarySyncFailure.accountDeleting }
            return .init(owner: owner, version: .present(epoch: clock.epoch, revision: clock.revision))
        }
        try assertOutcomeOwnerActive(owner, in: journal)
        let clock = try bumpOutcomeClock(subject: owner.subject, namespace: owner.namespace, in: journal)
        try saveOutcomeContext(journal)
        return .init(owner: owner, version: .present(epoch: clock.epoch, revision: clock.revision))
    }
    private func validateOutcomeExport(_ fence: LibraryOutcomeExportFence, in journal: ModelContext) throws {
        try assertOutcomeOwnerActive(fence.owner, in: journal)
        let clock = try outcomeClock(subject: fence.owner.subject, namespace: fence.owner.namespace, in: journal)
        switch (fence.version, clock) {
        case (.empty, nil): guard try !hasSavedRows(subject: fence.owner.subject, namespace: fence.owner.namespace, in: journal), try accountRows(subject: fence.owner.subject, namespace: fence.owner.namespace, in: journal).isEmpty else { throw LibrarySyncFailure.storeUnavailable }
        case (.present(let epoch, let revision), .some(let clock)):
            guard !clock.erasing, clock.epoch == epoch, clock.revision == revision else { throw LibrarySyncFailure.storeUnavailable }
        default: throw LibrarySyncFailure.storeUnavailable
        }
    }
    func validateOutcomeExport(_ fence: LibraryOutcomeExportFence) throws { try validateOutcomeExport(fence, in: outcomeContext()) }
    func outcomeExportEntries(_ fence: LibraryOutcomeExportFence, after: String?) throws -> [LibraryOutcomeExportEntry] {
        let journal = outcomeContext(); try validateOutcomeExport(fence, in: journal)
        let prefix = LibraryOutcomeBinding.hash([fence.owner.namespace, fence.owner.subject]) + ":", upper = prefix + "~"
        let lower = after.map { prefix + $0 + "!" } ?? prefix
        var query = FetchDescriptor<GuestOutcomeInventory>(predicate: #Predicate { $0.key >= lower && $0.key < upper }, sortBy: [SortDescriptor(\.key, comparator: .lexical)])
        query.fetchLimit = LibrarySyncLimits.outcomePage
        let rows = try journal.fetch(query)
        return try rows.map { row in
            guard let header = try outcomeHeader(row.headerKey, in: journal) else { throw LibrarySyncFailure.storeUnavailable }
            let binding = try JSONDecoder().decode(LibraryOutcomeBinding.self, from: header.bindingData)
            guard binding.owner.subject == fence.owner.subject, binding.owner.namespace == fence.owner.namespace,
                  row.key == prefix + binding.key else { throw LibrarySyncFailure.ownerMismatch }
            return .init(binding: binding, checkpoint: try outcomeCheckpoint(header, binding: binding))
        }
    }
    func outcomeExportPage(_ fence: LibraryOutcomeExportFence, entry: LibraryOutcomeExportEntry, start: Int) throws -> LibraryOutcomeEvidencePage {
        try validateOutcomeExport(fence)
        guard entry.binding.owner.subject == fence.owner.subject, entry.binding.owner.namespace == fence.owner.namespace else { throw LibrarySyncFailure.ownerMismatch }
        let page = try outcomeEvidencePage(entry.binding.committed, owner: entry.binding.owner, start: start)
        guard page.checkpoint == entry.checkpoint else { throw LibrarySyncFailure.storeUnavailable }
        try validateOutcomeExport(fence)
        return page
    }
    private func artifactDirectory(_ id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw LibrarySyncFailure.storeUnavailable }
        return exportDirectory.appendingPathComponent(id, isDirectory: true)
    }
    func beginOutcomeExportArtifact(_ fence: LibraryOutcomeExportFence) throws -> LibraryExportArtifact {
        let journal = outcomeContext(); try validateOutcomeExport(fence, in: journal)
        let id = UUID().uuidString, directory = try artifactDirectory(id)
        journal.insert(GuestLibraryExportArtifact(id: id, owner: fence.owner))
        try saveOutcomeContext(journal)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete]) }
        catch { try? discardOutcomeExportArtifact(id); throw error }
        return .init(id: id, directory: directory)
    }
    func discardOutcomeExportArtifact(_ id: String) throws {
        let journal = outcomeContext(), directory = try artifactDirectory(id)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        var query = FetchDescriptor<GuestLibraryExportArtifact>(predicate: #Predicate { $0.id == id }); query.fetchLimit = 2
        let rows = try journal.fetch(query)
        guard rows.count <= 1 else { throw LibrarySyncFailure.storeUnavailable }
        rows.forEach { journal.delete($0) }; try saveOutcomeContext(journal)
    }
    private func eraseOutcomeExportArtifacts(subject: String, namespace: String) throws {
        while true {
            let journal = outcomeContext()
            var query = FetchDescriptor<GuestLibraryExportArtifact>(predicate: #Predicate { $0.subject == subject && $0.namespace == namespace }); query.fetchLimit = LibrarySyncLimits.outcomePage
            let rows = try journal.fetch(query)
            if rows.isEmpty { return }
            for row in rows {
                let directory = try artifactDirectory(row.id)
                if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
                journal.delete(row)
            }
            try saveOutcomeContext(journal)
        }
    }
    func clearAbandonedOutcomeExports() throws {
        while true {
            let journal = outcomeContext(); var query = FetchDescriptor<GuestLibraryExportArtifact>(); query.fetchLimit = LibrarySyncLimits.outcomePage
            let rows = try journal.fetch(query)
            if rows.isEmpty { break }
            for row in rows {
                let directory = try artifactDirectory(row.id)
                if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
                journal.delete(row)
            }
            try saveOutcomeContext(journal)
        }
        if let entries = FileManager.default.enumerator(at: exportDirectory, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants]) {
            for case let directory as URL in entries where UUID(uuidString: directory.lastPathComponent) != nil {
                try FileManager.default.removeItem(at: directory)
            }
        }
        exportCleanupDone = true
    }

    private func outcomeContext() -> ModelContext {
        let value = ModelContext(container); value.autosaveEnabled = false; return value
    }
    private func outcomeHeader(_ key: String, in journal: ModelContext) throws -> GuestOutcomeHeader? {
        var query = FetchDescriptor<GuestOutcomeHeader>(predicate: #Predicate { $0.key == key }); query.fetchLimit = 2
        let rows = try journal.fetch(query)
        guard rows.count <= 1 else { throw LibrarySyncFailure.storeUnavailable }
        return rows.first
    }
    private func outcomeScope(_ key: String, in journal: ModelContext) throws -> GuestOutcomeScope? {
        var query = FetchDescriptor<GuestOutcomeScope>(predicate: #Predicate { $0.key == key }); query.fetchLimit = 2
        let rows = try journal.fetch(query)
        guard rows.count <= 1 else { throw LibrarySyncFailure.storeUnavailable }
        return rows.first
    }
    private func outcomeCheckpoint(_ header: GuestOutcomeHeader, binding: LibraryOutcomeBinding) throws -> LibraryOutcomeCheckpoint {
        guard header.key == binding.key, header.ownerKey == binding.owner.storageKey, header.subject == binding.owner.subject,
              header.namespace == binding.owner.namespace,
              try JSONDecoder().decode(LibraryOutcomeBinding.self, from: header.bindingData) == binding else { throw LibrarySyncFailure.ownerMismatch }
        let checkpoint = try JSONDecoder().decode(LibraryOutcomeCheckpoint.self, from: header.checkpointData)
        guard checkpoint.counts.valid, checkpoint.counts.fits(binding.expected) else { throw LibrarySyncFailure.storeUnavailable }
        if checkpoint.status == .complete, checkpoint.counts != binding.expected { throw LibrarySyncFailure.storeUnavailable }
        if let retention = checkpoint.retention {
            guard retention.valid(total: checkpoint.next), checkpoint.status == .complete,
                  binding.expected.superseded == 0, binding.expected.missing == 0 else { throw LibrarySyncFailure.storeUnavailable }
        }
        if case .verifying(let counts) = checkpoint.status {
            guard counts.valid, counts.fits(checkpoint.counts), checkpoint.counts == binding.expected else { throw LibrarySyncFailure.storeUnavailable }
        }
        return checkpoint
    }
    private func outcomeRows(_ binding: LibraryOutcomeBinding, start: Int, limit: Int, in journal: ModelContext) throws -> [SyncOutcomeMember] {
        let lower = binding.ordinalKey(start), upper = binding.key + ":~"
        var query = FetchDescriptor<GuestOutcomeMember>(predicate: #Predicate { $0.ordinalKey >= lower && $0.ordinalKey < upper }, sortBy: [SortDescriptor(\.ordinalKey, comparator: .lexical)])
        query.fetchLimit = LibrarySyncLimits.outcomePage
        let stored = try journal.fetch(query)
        guard stored.count == min(LibrarySyncLimits.outcomePage, limit - start) else { throw LibrarySyncFailure.storeUnavailable }
        return try stored.enumerated().map { index, value in
            let row = try JSONDecoder().decode(SyncOutcomeMember.self, from: value.rowData)
            guard row.ordinal == Double(start + index), value.ordinal == start + index, value.ordinalKey == binding.ordinalKey(start + index),
                  value.collectionKey == binding.key, value.ownerKey == binding.owner.storageKey, value.subject == binding.owner.subject,
                  value.namespace == binding.owner.namespace, value.disposition == row.disposition.rawValue,
                  value.memberKey == binding.key + ":" + row.memberId, value.hadithKey == binding.key + ":" + row.hadithId else { throw LibrarySyncFailure.storeUnavailable }
            return row
        }
    }
    private func verifyOutcomeStep(_ header: GuestOutcomeHeader, checkpoint: LibraryOutcomeCheckpoint, binding: LibraryOutcomeBinding, in journal: ModelContext) throws -> LibraryOutcomeCheckpoint {
        guard case .verifying(var counts) = checkpoint.status else { return checkpoint }
        guard counts.valid, counts.fits(checkpoint.counts), checkpoint.counts == binding.expected else { throw LibrarySyncFailure.storeUnavailable }
        let rows = try outcomeRows(binding, start: counts.total, limit: checkpoint.next, in: journal)
        counts.add(rows)
        guard counts.fits(binding.expected) else { throw LibrarySyncFailure.storeUnavailable }
        var next = checkpoint
        if counts.total == checkpoint.next {
            guard counts == binding.expected else { throw LibrarySyncFailure.storeUnavailable }
            next.status = .complete
        } else { next.status = .verifying(counts) }
        header.checkpointData = try JSONEncoder().encode(next)
        try bumpOutcomeClock(subject: binding.owner.subject, namespace: binding.owner.namespace, in: journal)
        try saveOutcomeContext(journal)
        return next
    }
    private func saveOutcomeContext(_ journal: ModelContext) throws {
        do { try journal.save() } catch { journal.rollback(); throw LibrarySyncFailure.storeUnavailable }
    }
    private func assertOutcomeOwnerActive(_ owner: LibrarySyncOwner, in db: ModelContext) throws {
        guard try deletionRow(subject: owner.subject, namespace: owner.namespace, in: db) == nil else { throw LibrarySyncFailure.accountDeleting }
        guard try partitionRow(owner, in: db) != nil else { throw LibrarySyncFailure.sessionChanged }
    }
    private func assertOutcomeOwnerActive(_ owner: LibrarySyncOwner) throws {
        try assertOutcomeOwnerActive(owner, in: outcomeContext())
    }

    func collectOutcomeStep(_ committed: SyncCommitted, owner: LibrarySyncOwner, isCurrent: () -> Bool,
                            fetch: (SyncOutcomePageRequest) async throws -> SyncOutcomePage) async throws -> LibraryOutcomeCheckpoint {
        guard isCurrent() else { throw LibrarySyncFailure.sessionChanged }
        try assertOutcomeOwnerActive(owner)
        let binding = try LibraryOutcomeBinding(owner: owner, committed: committed), journal = outcomeContext()
        let scope: GuestOutcomeScope
        let insertedScope: Bool
        if let stored = try outcomeScope(binding.scopeKey, in: journal) { scope = stored; insertedScope = false }
        else { scope = GuestOutcomeScope(binding: binding); journal.insert(scope); insertedScope = true }
        let header: GuestOutcomeHeader
        if let stored = try outcomeHeader(binding.key, in: journal) { header = stored }
        else {
            header = try GuestOutcomeHeader(binding: binding, generation: scope.generation, checkpoint: .init()); journal.insert(header)
            try insertOutcomeInventory(binding, in: journal)
        }
        guard header.generation == scope.generation else { throw LibrarySyncFailure.sessionChanged }
        if insertedScope { try bumpOutcomeClock(subject: owner.subject, namespace: owner.namespace, in: journal) }
        let checkpoint = try outcomeCheckpoint(header, binding: binding)
        guard checkpoint.retention?.removed == nil else { throw LibrarySyncFailure.storeUnavailable }
        if case .verifying = checkpoint.status { return try verifyOutcomeStep(header, checkpoint: checkpoint, binding: binding, in: journal) }
        try saveOutcomeContext(journal)
        guard checkpoint.status == .collecting else { return checkpoint }
        let generation = scope.generation, requested = binding.pageRequest(start: checkpoint.next)
        let page = try await fetch(requested)
        guard isCurrent() else { throw LibrarySyncFailure.sessionChanged }
        return try persistOutcomePage(page, requested: requested, binding: binding, generation: generation)
    }

    private func persistOutcomePage(_ page: SyncOutcomePage, requested: SyncOutcomePageRequest, binding: LibraryOutcomeBinding, generation: String) throws -> LibraryOutcomeCheckpoint {
        try assertOutcomeOwnerActive(binding.owner)
        let rows = try binding.validate(page, requested: requested), journal = outcomeContext()
        guard let scope = try outcomeScope(binding.scopeKey, in: journal), scope.generation == generation,
              let header = try outcomeHeader(binding.key, in: journal), header.generation == generation else { throw LibrarySyncFailure.sessionChanged }
        var checkpoint = try outcomeCheckpoint(header, binding: binding)
        guard requested.start <= Double(checkpoint.next) else { throw LibrarySyncFailure.invalidReceipt }
        if case .unavailable(let reason) = checkpoint.status {
            guard case .unavailable(let value) = page, value.reason == reason, requested.start == Double(checkpoint.next) else { throw LibrarySyncFailure.invalidReceipt }
            return checkpoint
        }
        if case .unavailable = page, requested.start != Double(checkpoint.next) || checkpoint.status != .collecting { throw LibrarySyncFailure.invalidReceipt }
        let replay = requested.start < Double(checkpoint.next) || checkpoint.status != .collecting
        if replay {
            for row in rows {
                let key = binding.ordinalKey(Int(row.ordinal))
                var query = FetchDescriptor<GuestOutcomeMember>(predicate: #Predicate { $0.ordinalKey == key }); query.fetchLimit = 2
                let existing = try journal.fetch(query)
                guard existing.count == 1, let stored = existing.first,
                      try JSONDecoder().decode(SyncOutcomeMember.self, from: stored.rowData) == row else { throw LibrarySyncFailure.invalidReceipt }
            }
            if case .page(let value) = page, value.next > Double(checkpoint.next) { throw LibrarySyncFailure.invalidReceipt }
            return checkpoint
        }
        guard checkpoint.status == .collecting else { throw LibrarySyncFailure.invalidReceipt }
        for row in rows {
            let ordinalKey = binding.ordinalKey(Int(row.ordinal)), memberKey = binding.key + ":" + row.memberId, hadithKey = binding.key + ":" + row.hadithId
            let duplicate = try journal.fetchCount(FetchDescriptor<GuestOutcomeMember>(predicate: #Predicate { $0.ordinalKey == ordinalKey || $0.memberKey == memberKey || $0.hadithKey == hadithKey }))
            guard duplicate == 0 else { throw LibrarySyncFailure.invalidReceipt }
            journal.insert(try GuestOutcomeMember(binding: binding, row: row))
        }
        switch page {
        case .unavailable(let value): checkpoint.status = .unavailable(value.reason)
        case .page(let value):
            checkpoint.counts.add(rows)
            guard checkpoint.counts.fits(binding.expected) else { throw LibrarySyncFailure.invalidReceipt }
            if value.done {
                guard checkpoint.counts == binding.expected else { throw LibrarySyncFailure.invalidReceipt }
                checkpoint.status = .verifying(.init())
            }
        }
        header.checkpointData = try JSONEncoder().encode(checkpoint)
        try bumpOutcomeClock(subject: binding.owner.subject, namespace: binding.owner.namespace, in: journal)
        // Rows and continuation share one save; a failed save advances neither.
        try saveOutcomeContext(journal)
        return checkpoint
    }

    func outcomeEvidencePage(_ committed: SyncCommitted, owner: LibrarySyncOwner, start: Int) throws -> LibraryOutcomeEvidencePage {
        let binding = try LibraryOutcomeBinding(owner: owner, committed: committed), journal = outcomeContext()
        guard let header = try outcomeHeader(binding.key, in: journal) else { throw LibrarySyncFailure.storeUnavailable }
        let checkpoint = try outcomeCheckpoint(header, binding: binding)
        guard checkpoint.retention?.removed == nil else { throw LibrarySyncFailure.storeUnavailable }
        guard start >= 0, start <= checkpoint.next else { throw LibrarySyncFailure.invalidReceipt }
        let rows = try outcomeRows(binding, start: start, limit: checkpoint.next, in: journal)
        let next = start + rows.count
        return .init(binding: binding, checkpoint: checkpoint, rows: rows, next: next, endOfCollectedPrefix: next == checkpoint.next)
    }

    private func eraseOutcomeEvidence(subject: String, namespace: String, ownerKey: String? = nil) throws {
        let journal = outcomeContext()
        try bumpOutcomeClock(subject: subject, namespace: namespace, erasing: ownerKey == nil, in: journal)
        try saveOutcomeContext(journal)
        try eraseOutcomeExportArtifacts(subject: subject, namespace: namespace)
        var after = ""
        while true {
            var query = FetchDescriptor<GuestOutcomeScope>(predicate: #Predicate { $0.subject == subject && $0.namespace == namespace && $0.key > after }, sortBy: [SortDescriptor(\.key, comparator: .lexical)])
            if let ownerKey { query = FetchDescriptor(predicate: #Predicate { $0.subject == subject && $0.namespace == namespace && $0.ownerKey == ownerKey && $0.key > after }, sortBy: [SortDescriptor(\.key, comparator: .lexical)]) }
            query.fetchLimit = LibrarySyncLimits.outcomePage
            let scopes = try journal.fetch(query)
            guard let last = scopes.last else { break }
            scopes.forEach { $0.generation = UUID().uuidString }
            after = last.key
            try bumpOutcomeClock(subject: subject, namespace: namespace, erasing: ownerKey == nil, in: journal)
            try saveOutcomeContext(journal)
        }
        while true {
            var query = FetchDescriptor<GuestOutcomeMember>(predicate: #Predicate { $0.subject == subject && $0.namespace == namespace })
            if let ownerKey { query = FetchDescriptor(predicate: #Predicate { $0.subject == subject && $0.namespace == namespace && $0.ownerKey == ownerKey }) }
            query.fetchLimit = LibrarySyncLimits.outcomePage
            let rows = try journal.fetch(query)
            if rows.isEmpty { break }
            rows.forEach { journal.delete($0) }
            try bumpOutcomeClock(subject: subject, namespace: namespace, erasing: ownerKey == nil, in: journal)
            try saveOutcomeContext(journal)
        }
        while true {
            var query = FetchDescriptor<GuestOutcomeHeader>(predicate: #Predicate { $0.subject == subject && $0.namespace == namespace })
            if let ownerKey { query = FetchDescriptor(predicate: #Predicate { $0.subject == subject && $0.namespace == namespace && $0.ownerKey == ownerKey }) }
            query.fetchLimit = LibrarySyncLimits.outcomePage
            let rows = try journal.fetch(query)
            if rows.isEmpty { break }
            for row in rows {
                let key = LibraryOutcomeBinding.hash([namespace, subject]) + ":" + row.key
                var inventoryQuery = FetchDescriptor<GuestOutcomeInventory>(predicate: #Predicate { $0.key == key }); inventoryQuery.fetchLimit = 1
                for item in try journal.fetch(inventoryQuery) { journal.delete(item) }
                journal.delete(row)
            }
            try bumpOutcomeClock(subject: subject, namespace: namespace, erasing: ownerKey == nil, in: journal)
            try saveOutcomeContext(journal)
        }
        while true {
            var query = FetchDescriptor<GuestOutcomeScope>(predicate: #Predicate { $0.subject == subject && $0.namespace == namespace })
            if let ownerKey { query = FetchDescriptor(predicate: #Predicate { $0.subject == subject && $0.namespace == namespace && $0.ownerKey == ownerKey }) }
            query.fetchLimit = LibrarySyncLimits.outcomePage
            let scopes = try journal.fetch(query)
            if scopes.isEmpty { break }
            scopes.forEach { journal.delete($0) }
            try bumpOutcomeClock(subject: subject, namespace: namespace, erasing: ownerKey == nil, in: journal)
            try saveOutcomeContext(journal)
        }
        let prefix = LibraryOutcomeBinding.hash([namespace, subject]) + ":", upper = prefix + "~"
        if ownerKey == nil {
            while true {
                var query = FetchDescriptor<GuestOutcomeInventory>(predicate: #Predicate { $0.key >= prefix && $0.key < upper }); query.fetchLimit = LibrarySyncLimits.outcomePage
                let rows = try journal.fetch(query)
                if rows.isEmpty { break }
                rows.forEach { journal.delete($0) }
                try bumpOutcomeClock(subject: subject, namespace: namespace, erasing: true, in: journal)
                try saveOutcomeContext(journal)
            }
        }
        let headers = try journal.fetchCount(FetchDescriptor<GuestOutcomeHeader>(predicate: #Predicate { $0.subject == subject && $0.namespace == namespace }))
        let scopes = try journal.fetchCount(FetchDescriptor<GuestOutcomeScope>(predicate: #Predicate { $0.subject == subject && $0.namespace == namespace }))
        if headers == 0 && scopes == 0, try !hasSavedRows(subject: subject, namespace: namespace, in: journal), try accountRows(subject: subject, namespace: namespace, in: journal).isEmpty, let clock = try outcomeClock(subject: subject, namespace: namespace, in: journal) {
            journal.delete(clock); try saveOutcomeContext(journal)
        }
    }

    // MARK: - Lifecycle

    /// Called only after the merge mutation reports success — the Convex copy
    /// is authoritative from that point on.


    private func saveGuestChanges() {
        do { try context.save(); lastWriteFailed = false; onGuestChanged?() }
        catch { context.rollback(); lastWriteFailed = true }
    }

    private func refreshCount() {
        let bookmarks = (try? context.fetchCount(FetchDescriptor<GuestBookmark>())) ?? 0
        let notes = (try? context.fetchCount(FetchDescriptor<GuestNote>())) ?? 0
        let favorites = (try? context.fetchCount(FetchDescriptor<GuestFavorite>())) ?? 0
        itemCount = bookmarks + notes + favorites
    }

    private func fetchBookmarks() -> [GuestBookmark] {
        let descriptor = FetchDescriptor<GuestBookmark>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchFavorites() -> [GuestFavorite] {
        let descriptor = FetchDescriptor<GuestFavorite>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchNotes() -> [GuestNote] {
        let descriptor = FetchDescriptor<GuestNote>(sortBy: [SortDescriptor(\.updatedAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchProgress() -> [GuestReadingProgress] {
        let descriptor = FetchDescriptor<GuestReadingProgress>(sortBy: [SortDescriptor(\.updatedAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchFolders() -> [GuestSavedFolder] {
        (try? context.fetch(FetchDescriptor<GuestSavedFolder>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    private func fetchMemberships() -> [GuestSavedMembership] {
        (try? context.fetch(FetchDescriptor<GuestSavedMembership>())) ?? []
    }

    private func removeMembershipIfUnsaved(hadithId: String) {
        guard !isBookmarked(hadithId: hadithId), !isFavorite(hadithId: hadithId), !fetchNotes().contains(where: { $0.hadithId == hadithId }) else { return }
        for membership in fetchMemberships().filter({ $0.hadithId == hadithId }) { context.delete(membership) }
    }

    nonisolated static func validFolderName(_ input: String) -> Bool {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        return !name.isEmpty && name.unicodeScalars.count <= 64 && !name.unicodeScalars.contains {
            $0.value <= 0x1f || ($0.value >= 0x7f && $0.value <= 0x9f)
        }
    }
}

// One pending private generation per owner. Prepared data does not alter the joined production base.
extension GuestDataStore {
    static var savedStepLimit: Int { 8 }
    private func savedOwnerActive(_ owner: LibrarySyncOwner, in db: ModelContext) throws {
        let key = owner.storageKey, subject = owner.subject, namespace = owner.namespace
        var partition = FetchDescriptor<GuestLibraryPartition>(predicate: #Predicate { $0.ownerKey == key }); partition.fetchLimit = 2
        let partitions = try db.fetch(partition)
        guard partitions.count == 1, partitions.first?.subject == subject else { throw LibrarySyncFailure.sessionChanged }
        let deletionKey = namespace + "|" + subject
        var deletion = FetchDescriptor<GuestAccountDeletion>(predicate: #Predicate { $0.scope == deletionKey }); deletion.fetchLimit = 1
        guard try db.fetch(deletion).isEmpty, try outcomeClock(subject: subject, namespace: namespace, in: db)?.erasing != true else { throw LibrarySyncFailure.accountDeleting }
    }
    private func savedAssembly(_ key: String, in db: ModelContext) throws -> GuestSavedAssembly? {
        var query = FetchDescriptor<GuestSavedAssembly>(predicate: #Predicate { $0.key == key }); query.fetchLimit = 2
        let rows = try db.fetch(query); guard rows.count <= 1 else { throw LibrarySyncFailure.storeUnavailable }; return rows.first
    }
    private func savedHeader(_ lease: LibrarySavedLease, in db: ModelContext) throws -> (GuestSavedAssembly, LibrarySavedCheckpoint) {
        try lease.validate()
        let subject = lease.owner.subject, namespace = lease.owner.namespace
        let deletionKey = namespace + "|" + subject
        var deletion = FetchDescriptor<GuestAccountDeletion>(predicate: #Predicate { $0.scope == deletionKey }); deletion.fetchLimit = 1
        guard try db.fetch(deletion).isEmpty, try outcomeClock(subject: subject, namespace: namespace, in: db)?.erasing != true else { throw LibrarySyncFailure.accountDeleting }
        guard let row = try savedAssembly(lease.key, in: db), !row.erasing,
              row.subject == lease.owner.subject, row.namespace == lease.owner.namespace, row.ownerKey == lease.owner.storageKey,
              row.leaseData.count <= 16_384, row.checkpointData.count <= 256 * 1024,
              try JSONDecoder().decode(LibrarySavedLease.self, from: row.leaseData) == lease else { throw LibrarySyncFailure.sessionChanged }
        let value = try JSONDecoder().decode(LibrarySavedCheckpoint.self, from: row.checkpointData)
        try value.validate(owner: lease.owner); _ = try savedGenerations(row, lease: lease, checkpoint: value); return (row, value)
    }
    private func saveSaved(_ value: LibrarySavedCheckpoint, header: GuestSavedAssembly, lease: LibrarySavedLease, in db: ModelContext) throws {
        try value.validate(owner: lease.owner); header.checkpointData = try JSONEncoder().encode(value)
        guard header.checkpointData.count <= 256 * 1024 else { throw LibrarySyncFailure.storeUnavailable }
        try bumpOutcomeClock(subject: lease.owner.subject, namespace: lease.owner.namespace, in: db); try saveOutcomeContext(db)
    }
    func beginSavedAssembly(_ owner: LibrarySyncOwner) throws -> LibrarySavedLease {
        let db = outcomeContext(); try savedOwnerActive(owner, in: db)
        let candidate = LibrarySavedLease(owner: owner, epoch: UUID().uuidString, generation: UUID().uuidString)
        try candidate.validate()
        if let stored = try savedAssembly(candidate.key, in: db) {
            guard stored.leaseData.count <= 16_384 else { throw LibrarySyncFailure.storeUnavailable }
            let lease = try JSONDecoder().decode(LibrarySavedLease.self, from: stored.leaseData)
            guard lease.owner == owner else { throw LibrarySyncFailure.ownerMismatch }
            let (_, checkpoint) = try savedHeader(lease, in: db)
            let generations = try savedGenerations(stored, lease: lease, checkpoint: checkpoint)
            guard generations.active?.lease == lease else { return lease }
            guard generations.retiring == nil else { throw LibrarySyncFailure.storeUnavailable }
            let next = LibrarySavedLease(owner: owner, epoch: lease.epoch, generation: UUID().uuidString)
            stored.leaseData = try JSONEncoder().encode(next)
            try saveSaved(LibrarySavedCheckpoint(), header: stored, lease: next, in: db); return next
        }
        let lower = candidate.key + ":", upper = candidate.key + ":~"
        var facts = FetchDescriptor<GuestSavedFactRow>(predicate: #Predicate { $0.key >= lower && $0.key < upper }); facts.fetchLimit = 1
        var pages = FetchDescriptor<GuestSavedPageRow>(predicate: #Predicate { $0.key >= lower && $0.key < upper }); pages.fetchLimit = 1
        var rows = FetchDescriptor<GuestSavedProjectionRow>(predicate: #Predicate { $0.key >= lower && $0.key < upper }); rows.fetchLimit = 1
        guard try db.fetch(facts).isEmpty, try db.fetch(pages).isEmpty, try db.fetch(rows).isEmpty else { throw LibrarySyncFailure.storeUnavailable }
        let row = try GuestSavedAssembly(lease: candidate); db.insert(row)
        try bumpOutcomeClock(subject: owner.subject, namespace: owner.namespace, in: db); try saveOutcomeContext(db); return candidate
    }
    func savedCheckpoint(_ lease: LibrarySavedLease) throws -> LibrarySavedCheckpoint {
        let db = outcomeContext(); return try savedHeader(lease, in: db).1
    }
    private func savedFacts(_ lease: LibrarySavedLease, start: Int, end: Int, in db: ModelContext) throws -> [SavedFact] {
        guard start >= 0, start <= end else { throw LibrarySyncFailure.invalidReceipt }
        let lower = lease.ordinalKey(start), upper = lease.ordinalKey(end)
        var query = FetchDescriptor<GuestSavedFactRow>(predicate: #Predicate { $0.key >= lower && $0.key < upper }, sortBy: [SortDescriptor(\.key, comparator: .lexical)])
        query.fetchLimit = Self.savedStepLimit
        let rows = try db.fetch(query)
        guard rows.count == min(Self.savedStepLimit, end - start) else { throw LibrarySyncFailure.storeUnavailable }
        return try rows.enumerated().map { index, row in
            guard row.data.count <= LibrarySyncLimits.savedFactPageBytes else { throw LibrarySyncFailure.storeUnavailable }
            let fact = try JSONDecoder().decode(SavedFact.self, from: row.data)
            try LibrarySavedPolicy.validate(fact)
            guard row.key == lease.ordinalKey(start + index), row.ordinal == start + index, fact.ordinalValue == Double(start + index),
                  row.sourceKey == lease.sourceKey(fact), row.collectionKey == lease.collection, row.subject == lease.owner.subject,
                  row.namespace == lease.owner.namespace, row.ownerKey == lease.owner.storageKey, row.fingerprint == (try fact.savedFingerprint()) else { throw LibrarySyncFailure.storeUnavailable }
            return fact
        }
    }
    func savedRawPage(_ lease: LibrarySavedLease, start: Int) throws -> LibrarySavedRawPage {
        let db = outcomeContext(); let checkpoint = try savedHeader(lease, in: db).1
        let rows = try savedFacts(lease, start: start, end: checkpoint.next, in: db)
        return .init(lease: lease, checkpoint: checkpoint, facts: rows, next: start + rows.count)
    }
    private func savedReceipt(_ lease: LibrarySavedLease, input: String?, in db: ModelContext) throws -> LibrarySavedPageReceipt? {
        let key = lease.inputKey(input); var query = FetchDescriptor<GuestSavedPageRow>(predicate: #Predicate { $0.key == key }); query.fetchLimit = 2
        let rows = try db.fetch(query); guard rows.count <= 1 else { throw LibrarySyncFailure.storeUnavailable }
        guard let row = rows.first else { return nil }
        guard row.data.count <= 256 * 1024 else { throw LibrarySyncFailure.storeUnavailable }
        let receipt = try JSONDecoder().decode(LibrarySavedPageReceipt.self, from: row.data)
        _ = try LibrarySavedPolicy.integer(Double(receipt.sequence)); _ = try LibrarySavedPolicy.integer(Double(receipt.start))
        guard Double(receipt.start) <= LibrarySavedPolicy.maxInteger - Double(receipt.count) else { throw LibrarySyncFailure.storeUnavailable }
        guard receipt.input == input, receipt.sequence >= 0, row.sequenceKey == lease.sequenceKey(receipt.sequence), row.collectionKey == lease.collection,
              row.subject == lease.owner.subject, row.namespace == lease.owner.namespace, row.ownerKey == lease.owner.storageKey,
              receipt.start >= 0, receipt.count >= 0, receipt.count <= LibrarySyncLimits.savedFactRows else { throw LibrarySyncFailure.storeUnavailable }
        return receipt
    }
    private func persistSavedPage(_ lease: LibrarySavedLease, requested: String?, reply: SavedFactsReply) throws -> LibrarySavedCheckpoint {
        let db = outcomeContext()
        do {
            let (header, checkpoint) = try savedHeader(lease, in: db)
            if let receipt = try savedReceipt(lease, input: requested, in: db) {
                guard receipt.sequence < checkpoint.pages, receipt.start + receipt.count <= checkpoint.next else { throw LibrarySyncFailure.storeUnavailable }
                let facts = try savedFacts(lease, start: receipt.start, end: receipt.start + receipt.count, in: db)
                try receipt.validate(reply: reply, owner: lease.owner, facts: facts); return checkpoint
            }
            guard checkpoint.stage == .collecting else { throw LibrarySyncFailure.invalidReceipt }
            let decision = try LibrarySavedPolicy.inspect(reply, owner: lease.owner, previous: checkpoint.position, requested: requested)
            var next = checkpoint; let result: LibrarySavedReceiptResult; let count: Int
            switch decision {
            case .restart: next.stage = .restart; result = .restart; count = 0
            case .unavailable(let reason): next.stage = .unavailable(reason); result = .unavailable(reason); count = 0
            case .append(let plan):
                if case .next(let token) = plan.position.continuation, try savedReceipt(lease, input: token, in: db) != nil { throw LibrarySyncFailure.invalidReceipt }
                for fact in plan.facts {
                    let key = lease.ordinalKey(try LibrarySavedPolicy.integer(fact.ordinalValue)), source = lease.sourceKey(fact)
                    var duplicate = FetchDescriptor<GuestSavedFactRow>(predicate: #Predicate { $0.key == key || $0.sourceKey == source }); duplicate.fetchLimit = 1
                    guard try db.fetch(duplicate).isEmpty else { throw LibrarySyncFailure.invalidReceipt }
                    db.insert(try GuestSavedFactRow(lease: lease, fact: fact)); next.digest = LibraryOutcomeBinding.hash([next.digest, try fact.savedFingerprint()])
                }
                next.position = plan.position; result = .advanced(plan.position); count = plan.facts.count
                if case .complete = plan.position.continuation { next.stage = .folding(next: 0, phase: -1, digest: LibraryOutcomeBinding.hash(["saved-raw-v1"])) }
            }
            let receipt = LibrarySavedPageReceipt(sequence: checkpoint.pages, input: requested, before: checkpoint.position, start: checkpoint.next, count: count,
                fingerprint: try LibrarySemanticFingerprint.digest(reply, domain: "library-saved-page-v1:"), result: result)
            db.insert(try GuestSavedPageRow(lease: lease, receipt: receipt)); next.pages += 1
            try saveSaved(next, header: header, lease: lease, in: db); return next
        } catch { db.rollback(); throw error }
    }
    private func decodeSavedProjection(_ row: GuestSavedProjectionRow, lease: LibrarySavedLease) throws -> LibrarySavedProjection {
        guard row.data.count <= 256 * 1024 else { throw LibrarySyncFailure.storeUnavailable }
        let value = try JSONDecoder().decode(LibrarySavedProjection.self, from: row.data)
        try LibrarySavedPolicy.validateProjection(value)
        guard row.key == lease.projectionKey(value), row.collectionKey == lease.collection, row.subject == lease.owner.subject,
              row.namespace == lease.owner.namespace, row.ownerKey == lease.owner.storageKey, row.fingerprint == (try value.savedFingerprint()) else { throw LibrarySyncFailure.storeUnavailable }
        return value
    }
    private func savedProjection(_ lease: LibrarySavedLease, fact: SavedFact, in db: ModelContext) throws -> GuestSavedProjectionRow? {
        let kind = fact.sourcePhase == 0 ? "folder" : "item"
        let key = lease.collection + ":r:" + LibraryOutcomeBinding.hash([kind, fact.targetID])
        var query = FetchDescriptor<GuestSavedProjectionRow>(predicate: #Predicate { $0.key == key }); query.fetchLimit = 2
        let rows = try db.fetch(query); guard rows.count <= 1 else { throw LibrarySyncFailure.storeUnavailable }; return rows.first
    }
    private func savedProjectionRows(_ lease: LibrarySavedLease, after: String?, in db: ModelContext) throws -> [GuestSavedProjectionRow] {
        guard after == nil || after?.hasPrefix(lease.collection + ":r:") == true else { throw LibrarySyncFailure.invalidReceipt }
        let lower = after ?? (lease.collection + ":r:"), upper = lease.collection + ":r:~"
        var query = FetchDescriptor<GuestSavedProjectionRow>(predicate: #Predicate { $0.key > lower && $0.key < upper }, sortBy: [SortDescriptor(\.key, comparator: .lexical)])
        query.fetchLimit = Self.savedStepLimit; return try db.fetch(query)
    }
    private func savedPageReceipts(_ lease: LibrarySavedLease, start: Int, total: Int, in db: ModelContext) throws -> [LibrarySavedPageReceipt] {
        guard start >= 0, start <= total else { throw LibrarySyncFailure.storeUnavailable }
        let lower = lease.sequenceKey(start), upper = lease.collection + ":s:~"
        var query = FetchDescriptor<GuestSavedPageRow>(predicate: #Predicate { $0.sequenceKey >= lower && $0.sequenceKey < upper }, sortBy: [SortDescriptor(\.sequenceKey, comparator: .lexical)])
        query.fetchLimit = Self.savedStepLimit; let rows = try db.fetch(query)
        guard rows.count == min(Self.savedStepLimit, total - start) else { throw LibrarySyncFailure.storeUnavailable }
        return try rows.enumerated().map { index, row in
            guard row.data.count <= 256 * 1024 else { throw LibrarySyncFailure.storeUnavailable }
            let receipt = try JSONDecoder().decode(LibrarySavedPageReceipt.self, from: row.data)
            _ = try LibrarySavedPolicy.integer(Double(receipt.sequence)); _ = try LibrarySavedPolicy.integer(Double(receipt.start))
            guard Double(receipt.start) <= LibrarySavedPolicy.maxInteger - Double(receipt.count) else { throw LibrarySyncFailure.storeUnavailable }
            guard receipt.sequence == start + index, row.sequenceKey == lease.sequenceKey(receipt.sequence), row.key == lease.inputKey(receipt.input),
                  row.collectionKey == lease.collection, row.subject == lease.owner.subject, row.namespace == lease.owner.namespace, row.ownerKey == lease.owner.storageKey,
                  receipt.start >= 0, receipt.count >= 0, receipt.count <= LibrarySyncLimits.savedFactRows else { throw LibrarySyncFailure.storeUnavailable }
            let facts = try savedFacts(lease, start: receipt.start, end: receipt.start + receipt.count, in: db)
            try receipt.validate(reply: receipt.reply(facts: facts, owner: lease.owner), owner: lease.owner, facts: facts)
            return receipt
        }
    }
    func advanceSavedAssembly(_ lease: LibrarySavedLease) throws -> LibrarySavedCheckpoint {
        let db = outcomeContext()
        do {
            let (header, checkpoint) = try savedHeader(lease, in: db); var next = checkpoint
            switch checkpoint.stage {
            case .folding(let start, var phase, var checksum):
                let rows = try savedFacts(lease, start: start, end: checkpoint.next, in: db)
                for fact in rows {
                    guard fact.sourcePhase >= phase else { throw LibrarySyncFailure.storeUnavailable }; phase = fact.sourcePhase
                    let stored = try savedProjection(lease, fact: fact, in: db)
                    let previous = try stored.map { try decodeSavedProjection($0, lease: lease) }
                    let projection = try LibrarySavedPolicy.fold(fact, previous: previous)
                    if let stored { stored.data = try JSONEncoder().encode(projection); stored.fingerprint = try projection.savedFingerprint() }
                    else { db.insert(try GuestSavedProjectionRow(lease: lease, value: projection)); next.counts.add(projection) }
                    checksum = LibraryOutcomeBinding.hash([checksum, try fact.savedFingerprint()])
                }
                let end = start + rows.count
                if end == checkpoint.next {
                    let lower = lease.ordinalKey(checkpoint.next), upper = lease.collection + ":f:~"
                    var extras = FetchDescriptor<GuestSavedFactRow>(predicate: #Predicate { $0.key >= lower && $0.key < upper }); extras.fetchLimit = 1
                    guard try db.fetch(extras).isEmpty, checksum == checkpoint.digest else { throw LibrarySyncFailure.storeUnavailable }
                    next.stage = .checkingPages(next: 0, input: nil, position: nil)
                } else { next.stage = .folding(next: end, phase: phase, digest: checksum) }
            case .checkingPages(let start, var expectedInput, var position):
                let rows = try savedPageReceipts(lease, start: start, total: checkpoint.pages, in: db)
                for receipt in rows {
                    guard receipt.input == expectedInput, receipt.before == position, case .advanced(let advanced) = receipt.result else { throw LibrarySyncFailure.storeUnavailable }
                    expectedInput = advanced.continuation.token; position = advanced
                }
                let end = start + rows.count
                if end == checkpoint.pages {
                    guard position == checkpoint.position else { throw LibrarySyncFailure.storeUnavailable }
                    next.stage = .verifying(after: nil, seen: .init())
                } else { next.stage = .checkingPages(next: end, input: expectedInput, position: position) }
            case .verifying(let after, var seen):
                let rows = try savedProjectionRows(lease, after: after, in: db)
                for row in rows { seen.add(try decodeSavedProjection(row, lease: lease)) }
                guard seen.items <= checkpoint.counts.items, seen.folders <= checkpoint.counts.folders else { throw LibrarySyncFailure.storeUnavailable }
                if rows.count < Self.savedStepLimit {
                    guard seen == checkpoint.counts else { throw LibrarySyncFailure.storeUnavailable }; next.stage = .prepared
                } else { next.stage = .verifying(after: rows.last?.key, seen: seen) }
            default: return checkpoint
            }
            try saveSaved(next, header: header, lease: lease, in: db); return next
        } catch { db.rollback(); throw error }
    }
    func collectSavedStep(_ lease: LibrarySavedLease, isCurrent: () -> Bool, fetch: (String?) async throws -> SavedFactsReply) async throws -> LibrarySavedCheckpoint {
        guard !Task.isCancelled, isCurrent(), !savedCollectionRunning else { throw LibrarySyncFailure.sessionChanged }
        savedCollectionRunning = true; defer { savedCollectionRunning = false }
        let checkpoint = try savedCheckpoint(lease)
        guard checkpoint.stage == .collecting else { return try advanceSavedAssembly(lease) }
        let requested = checkpoint.position?.continuation.token
        let reply = try await fetch(requested)
        guard !Task.isCancelled, isCurrent() else { throw LibrarySyncFailure.sessionChanged }
        return try persistSavedPage(lease, requested: requested, reply: reply)
    }
    private func savedGeneration(_ data: Data?, scope: LibrarySavedLease, prepared: Bool) throws -> LibrarySavedGenerationRecord? {
        guard let data else { return nil }
        guard data.count <= 256 * 1024 else { throw LibrarySyncFailure.storeUnavailable }
        let value = try JSONDecoder().decode(LibrarySavedGenerationRecord.self, from: data)
        try value.validate(scope: scope, prepared: prepared); return value
    }
    private func savedGenerations(_ header: GuestSavedAssembly, lease: LibrarySavedLease, checkpoint: LibrarySavedCheckpoint) throws -> (active: LibrarySavedGenerationRecord?, retiring: LibrarySavedGenerationRecord?) {
        let active = try savedGeneration(header.activeData, scope: lease, prepared: true)
        let retiring = try savedGeneration(header.retiringData, scope: lease, prepared: false)
        if active?.lease == lease, active?.checkpoint != checkpoint { throw LibrarySyncFailure.storeUnavailable }
        if let retiring, retiring.lease == lease || retiring.lease == active?.lease { throw LibrarySyncFailure.storeUnavailable }
        return (active, retiring)
    }
    private func currentSavedScope(_ owner: LibrarySyncOwner, in db: ModelContext) throws -> (GuestSavedAssembly, LibrarySavedLease, LibrarySavedCheckpoint)? {
        let key = LibrarySavedLease(owner: owner, epoch: "lookup", generation: "lookup").key
        guard let row = try savedAssembly(key, in: db) else { return nil }
        guard row.leaseData.count <= 16_384 else { throw LibrarySyncFailure.storeUnavailable }
        let lease = try JSONDecoder().decode(LibrarySavedLease.self, from: row.leaseData)
        guard lease.owner == owner else { throw LibrarySyncFailure.ownerMismatch }
        let (_, checkpoint) = try savedHeader(lease, in: db); return (row, lease, checkpoint)
    }
    func activeSavedGeneration(_ owner: LibrarySyncOwner) throws -> LibrarySavedActiveGeneration? {
        let db = outcomeContext()
        guard let (header, lease, checkpoint) = try currentSavedScope(owner, in: db) else { return nil }
        return try savedGenerations(header, lease: lease, checkpoint: checkpoint).active.map(LibrarySavedActiveGeneration.init)
    }
    func activeSavedPage(_ handle: LibrarySavedActiveGeneration, after: String?) throws -> LibrarySavedProjectionPage {
        let db = outcomeContext()
        guard let (header, lease, checkpoint) = try currentSavedScope(handle.lease.owner, in: db),
              let active = try savedGenerations(header, lease: lease, checkpoint: checkpoint).active,
              try LibrarySavedActiveGeneration(active) == handle else { throw LibrarySyncFailure.sessionChanged }
        let rows = try savedProjectionRows(handle.lease, after: after, in: db)
        return .init(rows: try rows.map { try decodeSavedProjection($0, lease: handle.lease) }, next: rows.last?.key, done: rows.count < Self.savedStepLimit)
    }
    func activateSavedGeneration(_ lease: LibrarySavedLease, isCurrent: () -> Bool, fetch: (String) async throws -> SavedFactsReply) async throws -> LibrarySavedActivation {
        guard !Task.isCancelled, isCurrent(), !savedCollectionRunning else { throw LibrarySyncFailure.sessionChanged }
        savedCollectionRunning = true; defer { savedCollectionRunning = false }
        let captured = try savedCheckpoint(lease)
        guard captured.stage == .prepared, let position = captured.position else { throw LibrarySyncFailure.invalidReceipt }
        if let active = try activeSavedGeneration(lease.owner), active.lease == lease { return .active(active) }
        let reply = try await fetch(position.continuation.token)
        guard !Task.isCancelled, isCurrent() else { throw LibrarySyncFailure.sessionChanged }
        let db = outcomeContext()
        do {
            let (header, checkpoint) = try savedHeader(lease, in: db)
            guard checkpoint == captured else { throw LibrarySyncFailure.sessionChanged }
            let generations = try savedGenerations(header, lease: lease, checkpoint: checkpoint)
            if let active = generations.active, active.lease == lease { return .active(try .init(active)) }
            var stopped = checkpoint
            switch reply {
            case .restart(let value):
                guard value.reason == "saved_changed" else { throw LibrarySyncFailure.invalidReceipt }
                stopped.stage = .restart; try saveSaved(stopped, header: header, lease: lease, in: db); return .restart
            case .unavailable(let value):
                stopped.stage = .unavailable(value.reason); try saveSaved(stopped, header: header, lease: lease, in: db); return .unavailable(value.reason)
            default: try LibrarySavedPolicy.confirm(reply, position: position)
            }
            guard generations.retiring == nil, (generations.active?.checkpoint.position?.version ?? -1) <= position.version else { throw LibrarySyncFailure.invalidReceipt }
            let active = LibrarySavedGenerationRecord(lease: lease, checkpoint: checkpoint)
            header.retiringData = header.activeData; header.activeData = try JSONEncoder().encode(active)
            try saveSaved(checkpoint, header: header, lease: lease, in: db); return .active(try .init(active))
        } catch { db.rollback(); throw error }
    }
    func replaceSavedCandidate(_ lease: LibrarySavedLease) throws -> LibrarySavedLease {
        let db = outcomeContext()
        do {
            let (header, checkpoint) = try savedHeader(lease, in: db)
            let generations = try savedGenerations(header, lease: lease, checkpoint: checkpoint)
            guard generations.active?.lease != lease, generations.retiring == nil else { throw LibrarySyncFailure.invalidChange }
            let next = LibrarySavedLease(owner: lease.owner, epoch: lease.epoch, generation: UUID().uuidString)
            header.retiringData = try JSONEncoder().encode(LibrarySavedGenerationRecord(lease: lease, checkpoint: checkpoint))
            header.leaseData = try JSONEncoder().encode(next)
            try saveSaved(LibrarySavedCheckpoint(), header: header, lease: next, in: db); return next
        } catch { db.rollback(); throw error }
    }
    func cleanupSavedGenerationStep(_ owner: LibrarySyncOwner) throws -> Bool {
        let db = outcomeContext()
        do {
            guard let (header, lease, checkpoint) = try currentSavedScope(owner, in: db),
                  let retiring = try savedGenerations(header, lease: lease, checkpoint: checkpoint).retiring else { return false }
            let lower = retiring.lease.collection + ":", upper = lower + "~"
            var facts = FetchDescriptor<GuestSavedFactRow>(predicate: #Predicate { $0.key >= lower && $0.key < upper }); facts.fetchLimit = Self.savedStepLimit
            let raw = try db.fetch(facts)
            if !raw.isEmpty { raw.forEach { db.delete($0) } }
            else {
                var pages = FetchDescriptor<GuestSavedPageRow>(predicate: #Predicate { $0.key >= lower && $0.key < upper }); pages.fetchLimit = Self.savedStepLimit
                let receipts = try db.fetch(pages)
                if !receipts.isEmpty { receipts.forEach { db.delete($0) } }
                else {
                    var rows = FetchDescriptor<GuestSavedProjectionRow>(predicate: #Predicate { $0.key >= lower && $0.key < upper }); rows.fetchLimit = Self.savedStepLimit
                    let values = try db.fetch(rows)
                    if !values.isEmpty { values.forEach { db.delete($0) } } else { header.retiringData = nil }
                }
            }
            try saveSaved(checkpoint, header: header, lease: lease, in: db); return true
        } catch { db.rollback(); throw error }
    }
    func preparedSavedPage(_ lease: LibrarySavedLease, after: String?) throws -> LibrarySavedProjectionPage {
        let db = outcomeContext()
        guard try savedHeader(lease, in: db).1.stage == .prepared else { throw LibrarySyncFailure.storeUnavailable }
        let rows = try savedProjectionRows(lease, after: after, in: db)
        return .init(rows: try rows.map { try decodeSavedProjection($0, lease: lease) }, next: rows.last?.key, done: rows.count < Self.savedStepLimit)
    }
}

extension GuestDataStore {
    private func hasSavedRows(subject: String, namespace: String, in db: ModelContext) throws -> Bool {
        let lower = LibraryOutcomeBinding.hash([namespace, subject]) + ":", upper = lower + "~"
        var a = FetchDescriptor<GuestSavedAssembly>(predicate: #Predicate { $0.key >= lower && $0.key < upper }); a.fetchLimit = 1
        if try !db.fetch(a).isEmpty { return true }
        var f = FetchDescriptor<GuestSavedFactRow>(predicate: #Predicate { $0.key >= lower && $0.key < upper }); f.fetchLimit = 1
        if try !db.fetch(f).isEmpty { return true }
        var p = FetchDescriptor<GuestSavedPageRow>(predicate: #Predicate { $0.key >= lower && $0.key < upper }); p.fetchLimit = 1
        if try !db.fetch(p).isEmpty { return true }
        var r = FetchDescriptor<GuestSavedProjectionRow>(predicate: #Predicate { $0.key >= lower && $0.key < upper }); r.fetchLimit = 1
        return try !db.fetch(r).isEmpty
    }
    func beginSavedErase(subject: String, namespace: String, ownerKey: String? = nil) throws {
        let db = outcomeContext()
        if let ownerKey {
            let key = LibraryOutcomeBinding.hash([namespace, subject]) + ":" + LibraryOutcomeBinding.hash([ownerKey, subject])
            if let row = try savedAssembly(key, in: db) {
                guard row.subject == subject, row.namespace == namespace, row.ownerKey == ownerKey else { throw LibrarySyncFailure.ownerMismatch }
                row.erasing = true
            }
        }
        try bumpOutcomeClock(subject: subject, namespace: namespace, erasing: ownerKey == nil, in: db); try saveOutcomeContext(db)
    }
    func eraseSavedStep(subject: String, namespace: String, ownerKey: String? = nil) throws -> Bool {
        let db = outcomeContext()
        guard try ownerKey != nil || outcomeClock(subject: subject, namespace: namespace, in: db)?.erasing == true else { throw LibrarySyncFailure.accountDeleting }
        let prefix = LibraryOutcomeBinding.hash([namespace, subject]) + ":"
        let lower = ownerKey.map { prefix + LibraryOutcomeBinding.hash([$0, subject]) } ?? prefix, upper = lower + "~"
        if let ownerKey {
            let key = prefix + LibraryOutcomeBinding.hash([ownerKey, subject])
            if let header = try savedAssembly(key, in: db), !header.erasing { throw LibrarySyncFailure.invalidChange }
        }
        func owned(_ s: String, _ n: String, _ o: String) throws {
            guard s == subject, n == namespace, ownerKey == nil || o == ownerKey else { throw LibrarySyncFailure.ownerMismatch }
        }
        var f = FetchDescriptor<GuestSavedFactRow>(predicate: #Predicate { $0.key >= lower && $0.key < upper }); f.fetchLimit = Self.savedStepLimit
        let facts = try db.fetch(f)
        if !facts.isEmpty { for row in facts { try owned(row.subject, row.namespace, row.ownerKey); db.delete(row) }; try bumpOutcomeClock(subject: subject, namespace: namespace, erasing: ownerKey == nil, in: db); try saveOutcomeContext(db); return true }
        var p = FetchDescriptor<GuestSavedPageRow>(predicate: #Predicate { $0.key >= lower && $0.key < upper }); p.fetchLimit = Self.savedStepLimit
        let pages = try db.fetch(p)
        if !pages.isEmpty { for row in pages { try owned(row.subject, row.namespace, row.ownerKey); db.delete(row) }; try bumpOutcomeClock(subject: subject, namespace: namespace, erasing: ownerKey == nil, in: db); try saveOutcomeContext(db); return true }
        var r = FetchDescriptor<GuestSavedProjectionRow>(predicate: #Predicate { $0.key >= lower && $0.key < upper }); r.fetchLimit = Self.savedStepLimit
        let projection = try db.fetch(r)
        if !projection.isEmpty { for row in projection { try owned(row.subject, row.namespace, row.ownerKey); db.delete(row) }; try bumpOutcomeClock(subject: subject, namespace: namespace, erasing: ownerKey == nil, in: db); try saveOutcomeContext(db); return true }
        var a = FetchDescriptor<GuestSavedAssembly>(predicate: #Predicate { $0.key >= lower && $0.key < upper }); a.fetchLimit = Self.savedStepLimit
        let headers = try db.fetch(a)
        if !headers.isEmpty { for row in headers { try owned(row.subject, row.namespace, row.ownerKey); db.delete(row) }; try bumpOutcomeClock(subject: subject, namespace: namespace, erasing: ownerKey == nil, in: db); try saveOutcomeContext(db); return true }
        return false
    }
    func savedExportRecords(_ fence: LibraryOutcomeExportFence, section: Int, after: String?) throws -> (values: [LibraryExportValue], next: String?, done: Bool) {
        let db = outcomeContext(); try validateOutcomeExport(fence, in: db)
        let subject = fence.owner.subject, namespace = fence.owner.namespace
        let prefix = LibraryOutcomeBinding.hash([namespace, subject]) + ":", lower = after ?? prefix, upper = prefix + "~"
        func owned(_ s: String, _ n: String, _ o: String, _ collection: String) throws -> [String: LibraryExportValue] {
            let scope = LibraryOutcomeBinding.hash([namespace, subject]) + ":" + LibraryOutcomeBinding.hash([o, subject])
            guard s == subject, n == namespace, o.hasPrefix(namespace + "|"), collection.hasPrefix(scope + ":") else { throw LibrarySyncFailure.ownerMismatch }
            return ["ownerStorageKey": .string(o), "subject": .string(s), "namespace": .string(n), "collection": .string(collection), "coverage": .string("retained_local_rows")]
        }
        var values: [LibraryExportValue] = [], last: String?
        switch section {
        case 0:
            var query = FetchDescriptor<GuestSavedAssembly>(predicate: #Predicate { $0.key > lower && $0.key < upper }, sortBy: [SortDescriptor(\.key, comparator: .lexical)]); query.fetchLimit = Self.savedStepLimit
            for row in try db.fetch(query) {
                guard row.leaseData.count <= 16_384 else { throw LibrarySyncFailure.storeUnavailable }
                let lease = try JSONDecoder().decode(LibrarySavedLease.self, from: row.leaseData)
                guard lease.owner.subject == subject, lease.owner.namespace == namespace else { throw LibrarySyncFailure.ownerMismatch }
                let checkpoint = try savedHeader(lease, in: db).1
                let generations = try savedGenerations(row, lease: lease, checkpoint: checkpoint)
                var metadata = LibrarySavedGenerationRecord(lease: lease, checkpoint: checkpoint).exportMetadata(active: generations.active?.lease == lease)
                if let active = generations.active, active.lease != lease { metadata["activeGeneration"] = .object(active.exportMetadata(active: true)) }
                if let retiring = generations.retiring { metadata["retiringGeneration"] = .object(retiring.exportMetadata()) }
                metadata["kind"] = .string("assembly"); metadata["coverage"] = .string("retained_local_rows")
                values.append(.object(metadata)); last = row.key
            }
        case 1:
            var query = FetchDescriptor<GuestSavedFactRow>(predicate: #Predicate { $0.key > lower && $0.key < upper }, sortBy: [SortDescriptor(\.key, comparator: .lexical)]); query.fetchLimit = Self.savedStepLimit
            for row in try db.fetch(query) {
                var metadata = try owned(row.subject, row.namespace, row.ownerKey, row.collectionKey)
                guard row.data.count <= LibrarySyncLimits.savedFactPageBytes else { throw LibrarySyncFailure.storeUnavailable }
                let fact = try JSONDecoder().decode(SavedFact.self, from: row.data); try LibrarySavedPolicy.validate(fact)
                let ordinal = try LibrarySavedPolicy.integer(fact.ordinalValue)
                guard row.ordinal == ordinal, row.key == row.collectionKey + ":f:" + String(format: "%016llx", UInt64(ordinal)), row.sourceKey == row.collectionKey + ":i:" + LibraryOutcomeBinding.hash([String(fact.sourcePhase), fact.sourceID]), row.fingerprint == (try fact.savedFingerprint()) else { throw LibrarySyncFailure.storeUnavailable }
                metadata["record"] = try LibrarySavedExportRecord.fact(fact).exportValue(); values.append(.object(metadata)); last = row.key
            }
        case 2:
            var query = FetchDescriptor<GuestSavedPageRow>(predicate: #Predicate { $0.key > lower && $0.key < upper }, sortBy: [SortDescriptor(\.key, comparator: .lexical)]); query.fetchLimit = Self.savedStepLimit
            for row in try db.fetch(query) {
                var metadata = try owned(row.subject, row.namespace, row.ownerKey, row.collectionKey)
                guard row.data.count <= 256 * 1024 else { throw LibrarySyncFailure.storeUnavailable }
                let receipt = try JSONDecoder().decode(LibrarySavedPageReceipt.self, from: row.data)
                guard receipt.sequence >= 0, receipt.count >= 0, receipt.start >= 0,
                      row.key == row.collectionKey + ":p:" + LibraryOutcomeBinding.hash([receipt.input == nil ? "absent" : "present", receipt.input ?? ""]),
                      row.sequenceKey == row.collectionKey + ":s:" + String(format: "%016llx", UInt64(receipt.sequence)) else { throw LibrarySyncFailure.storeUnavailable }
                for position in [receipt.before, { if case .advanced(let p) = receipt.result { return p }; return nil }()].compactMap({ $0 }) {
                    guard position.owner.subject == subject, position.owner.namespace == namespace, position.owner.storageKey == row.ownerKey else { throw LibrarySyncFailure.ownerMismatch }
                }
                metadata["record"] = try LibrarySavedExportRecord.page(receipt).exportValue(); values.append(.object(metadata)); last = row.key
            }
        case 3:
            var query = FetchDescriptor<GuestSavedProjectionRow>(predicate: #Predicate { $0.key > lower && $0.key < upper }, sortBy: [SortDescriptor(\.key, comparator: .lexical)]); query.fetchLimit = Self.savedStepLimit
            for row in try db.fetch(query) {
                var metadata = try owned(row.subject, row.namespace, row.ownerKey, row.collectionKey)
                guard row.data.count <= 256 * 1024 else { throw LibrarySyncFailure.storeUnavailable }
                let value = try JSONDecoder().decode(LibrarySavedProjection.self, from: row.data); try LibrarySavedPolicy.validateProjection(value)
                guard row.key == row.collectionKey + ":r:" + LibraryOutcomeBinding.hash([value.kind, value.targetID]), row.fingerprint == (try value.savedFingerprint()) else { throw LibrarySyncFailure.storeUnavailable }
                metadata["record"] = try LibrarySavedExportRecord.projection(value).exportValue(); values.append(.object(metadata)); last = row.key
            }
        default: throw LibrarySyncFailure.invalidReceipt
        }
        try validateOutcomeExport(fence, in: db); return (values, last, values.count < Self.savedStepLimit)
    }
}

struct LibrarySavedActiveGeneration: Equatable, Sendable {
    let lease: LibrarySavedLease
    let version: Double
    fileprivate init(_ generation: LibrarySavedGenerationRecord) throws {
        guard generation.checkpoint.stage == .prepared, let position = generation.checkpoint.position else { throw LibrarySyncFailure.storeUnavailable }
        lease = generation.lease; version = position.version
    }
}
enum LibrarySavedActivation: Equatable, Sendable {
    case active(LibrarySavedActiveGeneration), restart, unavailable(SavedFactsReplyUnavailableReason)
}
