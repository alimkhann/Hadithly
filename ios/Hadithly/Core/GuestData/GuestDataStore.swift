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

    private func partitionRow(_ owner: LibrarySyncOwner) throws -> GuestLibraryPartition? {
        let key = owner.storageKey
        var descriptor = FetchDescriptor<GuestLibraryPartition>(predicate: #Predicate { $0.ownerKey == key })
        descriptor.fetchLimit = 1
        let row = try context.fetch(descriptor).first
        guard row == nil || row?.subject == owner.subject else { throw LibrarySyncFailure.ownerMismatch }
        return row
    }

    func syncPartition(_ owner: LibrarySyncOwner) throws -> LibraryPartitionState? {
        guard let row = try partitionRow(owner) else { return nil }
        do { return try JSONDecoder().decode(LibraryPartitionState.self, from: row.stateData) }
        catch { throw LibrarySyncFailure.storeUnavailable }
    }

    private func saveSyncPartition(_ state: LibraryPartitionState, owner: LibrarySyncOwner) throws {
        let data = try JSONEncoder().encode(state)
        if let row = try partitionRow(owner) { row.stateData = data }
        else { context.insert(GuestLibraryPartition(ownerKey: owner.storageKey, subject: owner.subject, stateData: data)) }
        do { try context.save() }
        catch { context.rollback(); throw LibrarySyncFailure.storeUnavailable }
    }

    /// The claim and guest removal share one SwiftData commit, with no network await.
    func claimGuestForSync(_ owner: LibrarySyncOwner) throws {
        guard try deletionPhase(subject: owner.subject, namespace: owner.namespace) == nil else { throw LibrarySyncFailure.accountDeleting }
        let bookmarks = try context.fetch(FetchDescriptor<GuestBookmark>())
        let favorites = try context.fetch(FetchDescriptor<GuestFavorite>())
        let notes = try context.fetch(FetchDescriptor<GuestNote>())
        let folders = try context.fetch(FetchDescriptor<GuestSavedFolder>())
        let memberships = try context.fetch(FetchDescriptor<GuestSavedMembership>())
        let positions = try context.fetch(FetchDescriptor<GuestReadingProgress>())
        var state = try syncPartition(owner) ?? LibraryPartitionState()
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
        if let row = try partitionRow(owner) { row.stateData = data }
        else { context.insert(GuestLibraryPartition(ownerKey: owner.storageKey, subject: owner.subject, stateData: data)) }
        bookmarks.forEach { context.delete($0) }
        favorites.forEach { context.delete($0) }
        notes.forEach { context.delete($0) }
        folders.forEach { context.delete($0) }
        memberships.forEach { context.delete($0) }
        positions.forEach { context.delete($0) }
        do { try context.save() }
        catch { context.rollback(); throw LibrarySyncFailure.storeUnavailable }
        refreshCount()
    }

    func freezeSyncFrame(_ owner: LibrarySyncOwner) throws -> SyncFrame? {
        guard var state = try syncPartition(owner) else { return nil }
        let batch = try state.freeze()
        try saveSyncPartition(state, owner: owner)
        return batch
    }

    func enqueueSyncChange(_ change: LibraryLocalChange, owner: LibrarySyncOwner) throws {
        guard var state = try syncPartition(owner) else { throw LibrarySyncFailure.sessionChanged }
        state.pending.append(change)
        try saveSyncPartition(state, owner: owner)
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
        guard var state = try syncPartition(owner) else { return }
        try state.settle(exchange, requested: requested, now: now)
        try saveSyncPartition(state, owner: owner)
    }

    func settleSyncPending(_ exchange: SyncExchange, requested: SyncPending, owner: LibrarySyncOwner, now: Double = Date.now.millisecondsSinceEpoch) throws {
        switch exchange {
        case .accepted(let value): try validateSyncOwner(owner, replyOwner: value.committed.reply.ownerKey)
        case .pending(let value): try validateSyncOwner(owner, replyOwner: value.ownerKey)
        case .reconcile(let value): try validateSyncOwner(owner, replyOwner: value.ownerKey, cursor: value.cursor)
        }
        guard var state = try syncPartition(owner) else { return }
        try state.settlePending(exchange, requested: requested, now: now)
        try saveSyncPartition(state, owner: owner)
    }

    func settleSyncRetirement(_ reply: SyncAckReply, requested: SyncFrame, owner: LibrarySyncOwner) throws {
        try validateSyncOwner(owner, replyOwner: reply.ownerKey, cursor: reply.cursor)
        guard var state = try syncPartition(owner) else { return }
        try state.settleRetirement(reply, requested: requested)
        try saveSyncPartition(state, owner: owner)
    }

    func settleSyncAcknowledgement(_ reply: SyncAckReply, requested: SyncAcknowledgement, owner: LibrarySyncOwner, now: Double = Date.now.millisecondsSinceEpoch) throws {
        try validateSyncOwner(owner, replyOwner: reply.ownerKey, cursor: reply.cursor)
        guard var state = try syncPartition(owner) else { return }
        let link = state.manifestAckLink
        try state.settleAcknowledgement(reply, requested: requested)
        if let link, reply.cursor.closedThrough >= requested.sequence {
            guard link.owner == owner, link.request.proof == requested else { throw LibrarySyncFailure.invalidReceipt }
            try assertOutcomeOwnerActive(owner)
            try acknowledgeOutcomeEvidence(link, now: now)
        }
        try saveSyncPartition(state, owner: owner)
    }

    private func acknowledgeOutcomeEvidence(_ binding: LibraryOutcomeBinding, now: Double) throws {
        let journal = outcomeContext()
        guard now.isFinite, now >= 0, let scope = try outcomeScope(binding.scopeKey, in: journal),
              let header = try outcomeHeader(binding.key, in: journal), header.generation == scope.generation else { throw LibrarySyncFailure.storeUnavailable }
        var checkpoint = try outcomeCheckpoint(header, binding: binding)
        guard checkpoint.status == .complete, binding.expected.superseded == 0, binding.expected.missing == 0,
              checkpoint.retention?.removed == nil else { throw LibrarySyncFailure.invalidReceipt }
        if checkpoint.retention != nil { return }
        checkpoint.retention = .init(acknowledgedAt: now, removed: nil)
        header.checkpointData = try JSONEncoder().encode(checkpoint)
        try bumpOutcomeClock(subject: binding.owner.subject, namespace: binding.owner.namespace, in: journal)
        try saveOutcomeContext(journal)
    }

    func pruneOutcomeSuccessStep(_ owner: LibrarySyncOwner, now: Double) throws -> Bool {
        try assertOutcomeOwnerActive(owner)
        guard now.isFinite, now >= 0 else { throw LibrarySyncFailure.invalidReceipt }
        if try !prepareOutcomeInventoryStep() { return true }
        guard var active = try syncPartition(owner) else { throw LibrarySyncFailure.sessionChanged }
        let journal = outcomeContext(), prefix = LibraryOutcomeBinding.hash([owner.namespace, owner.subject]) + ":"
        let lower = active.outcomeRetentionCursor.map { prefix + $0 + "!" } ?? prefix, upper = prefix + "~"
        var query = FetchDescriptor<GuestOutcomeInventory>(predicate: #Predicate { $0.key >= lower && $0.key < upper }, sortBy: [SortDescriptor(\.key)])
        query.fetchLimit = LibrarySyncLimits.outcomePage
        let inventory = try journal.fetch(query)
        if inventory.isEmpty {
            if active.outcomeRetentionCursor != nil { active.outcomeRetentionCursor = nil; try saveSyncPartition(active, owner: owner) }
            return false
        }
        var cursor = active.outcomeRetentionCursor
        for entry in inventory {
            guard let header = try outcomeHeader(entry.headerKey, in: journal) else { throw LibrarySyncFailure.storeUnavailable }
            let binding = try JSONDecoder().decode(LibraryOutcomeBinding.self, from: header.bindingData)
            guard binding.owner.subject == owner.subject, binding.owner.namespace == owner.namespace,
                  entry.key == prefix + binding.key else { throw LibrarySyncFailure.ownerMismatch }
            var checkpoint = try outcomeCheckpoint(header, binding: binding)
            let dependencyState = try syncPartition(binding.owner)
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
                try saveOutcomeContext(journal)
                active.outcomeRetentionCursor = cursor
                try saveSyncPartition(active, owner: owner)
                return true
            }
            cursor = binding.key
        }
        active.outcomeRetentionCursor = cursor
        try saveSyncPartition(active, owner: owner)
        return true
    }

    func settleCollectedOutcome(_ expected: LibraryPendingOutcome, owner: LibrarySyncOwner, now: Double) throws -> LibraryOutcomeSettlement {
        try assertOutcomeOwnerActive(owner)
        let binding = try LibraryOutcomeBinding(owner: owner, committed: expected.committed), journal = outcomeContext()
        guard let scope = try outcomeScope(binding.scopeKey, in: journal),
              let header = try outcomeHeader(binding.key, in: journal), header.generation == scope.generation else { throw LibrarySyncFailure.storeUnavailable }
        let checkpoint = try outcomeCheckpoint(header, binding: binding)
        guard var state = try syncPartition(owner) else { throw LibrarySyncFailure.sessionChanged }
        let before = state
        let progress = try state.settleCollectedOutcome(expected, binding: binding, checkpoint: checkpoint, now: now)
        if state != before { try saveSyncPartition(state, owner: owner) }
        return progress
    }

    func cacheSavedSnapshot(_ snapshot: SyncSavedSnapshot, owner: LibrarySyncOwner) throws {
        guard snapshot.ownerKey == owner.key else { throw LibrarySyncFailure.ownerMismatch }
        guard var state = try syncPartition(owner) else { throw LibrarySyncFailure.sessionChanged }
        guard snapshot.version.isFinite, snapshot.version >= 0, snapshot.version.rounded(.down) == snapshot.version else { throw LibrarySyncFailure.invalidReceipt }
        if snapshot.version < (state.savedSnapshot?.version ?? -1) { return }
        state.savedSnapshot = snapshot
        state.pruneConfirmed()
        try saveSyncPartition(state, owner: owner)
    }

    func cachePositionsSnapshot(_ snapshot: SyncPositionsSnapshot, owner: LibrarySyncOwner) throws {
        guard snapshot.ownerKey == owner.key else { throw LibrarySyncFailure.ownerMismatch }
        guard var state = try syncPartition(owner) else { throw LibrarySyncFailure.sessionChanged }
        guard snapshot.version.isFinite, snapshot.version >= 0, snapshot.version.rounded(.down) == snapshot.version else { throw LibrarySyncFailure.invalidReceipt }
        if snapshot.version < (state.positionsSnapshot?.version ?? -1) { return }
        state.positionsSnapshot = snapshot
        state.pruneConfirmed()
        try saveSyncPartition(state, owner: owner)
    }

    private func deletionRow(subject: String, namespace: String) throws -> GuestAccountDeletion? {
        try context.fetch(FetchDescriptor<GuestAccountDeletion>()).first { $0.subject == subject && $0.namespace == namespace }
    }
    func deletionPhase(subject: String, namespace: String) throws -> LibraryDeletionPhase? {
        guard let row = try deletionRow(subject: subject, namespace: namespace) else { return nil }
        guard let phase = LibraryDeletionPhase(rawValue: row.phase) else { throw LibrarySyncFailure.storeUnavailable }
        return phase
    }
    func beginDeletion(subject: String, namespace: String) throws {
        if try deletionRow(subject: subject, namespace: namespace) == nil {
            context.insert(GuestAccountDeletion(subject: subject, namespace: namespace))
        }
        do { try context.save() } catch { context.rollback(); throw LibrarySyncFailure.storeUnavailable }
    }
    func markDeletionBackendComplete(subject: String, namespace: String) throws {
        guard let row = try deletionRow(subject: subject, namespace: namespace) else { throw LibrarySyncFailure.sessionChanged }
        try eraseOutcomeEvidence(subject: subject, namespace: namespace)
        row.phase = LibraryDeletionPhase.identityPending.rawValue
        for partition in try context.fetch(FetchDescriptor<GuestLibraryPartition>()) where partition.subject == subject && partition.ownerKey.hasPrefix(namespace + "|") {
            context.delete(partition)
        }
        do { try context.save() } catch { context.rollback(); throw LibrarySyncFailure.storeUnavailable }
    }
    func clearDeletion(subject: String, namespace: String) throws {
        if let row = try deletionRow(subject: subject, namespace: namespace) { context.delete(row) }
        do { try context.save() } catch { context.rollback(); throw LibrarySyncFailure.storeUnavailable }
    }

    // Reset fixture only. Account erasure uses the durable deletion intent above.
    func resetSyncPartitionForTesting(_ owner: LibrarySyncOwner) throws {
        try eraseOutcomeEvidence(subject: owner.subject, namespace: owner.namespace, ownerKey: owner.storageKey)
        if let row = try partitionRow(owner) { context.delete(row) }
        do { try context.save() }
        catch { context.rollback(); throw LibrarySyncFailure.storeUnavailable }
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
        var headersQuery = FetchDescriptor<GuestOutcomeHeader>(predicate: #Predicate { $0.key > after }, sortBy: [SortDescriptor(\.key)])
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
        let prefix = LibraryOutcomeBinding.hash([owner.namespace, owner.subject]) + ":", upper = prefix + "~"
        var query = FetchDescriptor<GuestOutcomeInventory>(predicate: #Predicate { $0.key >= prefix && $0.key < upper }); query.fetchLimit = 1
        guard try journal.fetch(query).isEmpty else { throw LibrarySyncFailure.storeUnavailable }
        return .init(owner: owner, version: .empty)
    }
    private func validateOutcomeExport(_ fence: LibraryOutcomeExportFence, in journal: ModelContext) throws {
        try assertOutcomeOwnerActive(fence.owner)
        let clock = try outcomeClock(subject: fence.owner.subject, namespace: fence.owner.namespace, in: journal)
        switch (fence.version, clock) {
        case (.empty, nil): break
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
        var query = FetchDescriptor<GuestOutcomeInventory>(predicate: #Predicate { $0.key >= lower && $0.key < upper }, sortBy: [SortDescriptor(\.key)])
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
        var query = FetchDescriptor<GuestOutcomeMember>(predicate: #Predicate { $0.ordinalKey >= lower && $0.ordinalKey < upper }, sortBy: [SortDescriptor(\.ordinalKey)])
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
    private func assertOutcomeOwnerActive(_ owner: LibrarySyncOwner) throws {
        guard try deletionPhase(subject: owner.subject, namespace: owner.namespace) == nil else { throw LibrarySyncFailure.accountDeleting }
        guard try partitionRow(owner) != nil else { throw LibrarySyncFailure.sessionChanged }
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
            var query = FetchDescriptor<GuestOutcomeScope>(predicate: #Predicate { $0.subject == subject && $0.namespace == namespace && $0.key > after }, sortBy: [SortDescriptor(\.key)])
            if let ownerKey { query = FetchDescriptor(predicate: #Predicate { $0.subject == subject && $0.namespace == namespace && $0.ownerKey == ownerKey && $0.key > after }, sortBy: [SortDescriptor(\.key)]) }
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
        if headers == 0 && scopes == 0, let clock = try outcomeClock(subject: subject, namespace: namespace, in: journal) {
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
