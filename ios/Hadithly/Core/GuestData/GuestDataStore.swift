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

    init(inMemory: Bool = false, storeURL: URL? = nil) {
        let schema = Schema([
            GuestBookmark.self,
            GuestNote.self,
            GuestFavorite.self,
            GuestSavedFolder.self,
            GuestSavedMembership.self,
            GuestReadingProgress.self,
            GuestLibraryPartition.self,
            GuestAccountDeletion.self,
        ])
        let configuration = storeURL.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        self.container = try! ModelContainer(for: schema, configurations: [configuration])
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

    func settleSyncAcknowledgement(_ reply: SyncAckReply, requested: SyncAcknowledgement, owner: LibrarySyncOwner) throws {
        try validateSyncOwner(owner, replyOwner: reply.ownerKey, cursor: reply.cursor)
        guard var state = try syncPartition(owner) else { return }
        try state.settleAcknowledgement(reply, requested: requested)
        try saveSyncPartition(state, owner: owner)
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

    func eraseSyncPartition(_ owner: LibrarySyncOwner) throws {
        if let row = try partitionRow(owner) { context.delete(row) }
        do { try context.save() }
        catch { context.rollback(); throw LibrarySyncFailure.storeUnavailable }
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
