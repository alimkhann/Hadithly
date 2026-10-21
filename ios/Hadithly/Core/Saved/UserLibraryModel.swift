import Combine
import ConvexMobile
import Foundation
import Observation

/// A hadith reference shared by the Saved tab, the Today tab, and the reader
/// deep-link. `arabicText` is empty for guest entries saved before the hadith
/// text was captured — callers render a fallback.
struct HadithRef: Codable, Identifiable, Equatable, Sendable {
    let hadithId: String
    let collectionSlug: String
    let collectionName: String
    let volumeId: String?
    let hadithNumber: String?
    let arabicText: String
    let englishText: String?
    let referenceDisplay: String

    var id: String { hadithId }
}

/// One row of the Saved tab: the item's server (or local) id, timestamps,
/// note content when it is a note, and the hadith it points at.
struct SavedEntry: Identifiable, Equatable, Sendable {
    let rowId: String
    let createdAt: Date
    var updatedAt: Date?
    var noteContent: String?
    var hadith: HadithRef?

    var id: String { rowId }

    var sortDate: Date { updatedAt ?? createdAt }
}

/// A unique private Saved target. Its facets stay independent: a note never
/// implies a bookmark or favorite, even though the list renders one row.
struct SavedItemEntry: Identifiable, Equatable, Sendable {
    let hadithId: String
    var createdAt: Date
    var updatedAt: Date
    var bookmarkCreatedAt: Date?
    var favoriteCreatedAt: Date?
    var noteContent: String?
    var noteCreatedAt: Date? = nil
    var noteUpdatedAt: Date? = nil
    var folderId: String?
    var hadith: HadithRef?

    var id: String { hadithId }
    var sortDate: Date { updatedAt }
}

struct SavedFolder: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let createdAt: Date
}

enum SavedUndoDeadline {
    static let duration: TimeInterval = 5
}

struct SavedFolderDeletion: Decodable, Equatable, Sendable {
    let name: String
    let deletedAt: Double
    let undoID = UUID()
    let undoDeadline = Date.now.addingTimeInterval(SavedUndoDeadline.duration)
    private enum CodingKeys: String, CodingKey { case name, deletedAt }
}

private struct SavedFolderRestore: Decodable, Sendable {
    let folderId: String
    let restoredHadithIds: [String]
}

/// Private per-collection reading position (never shared, never ranked).
struct ProgressEntry: Identifiable, Equatable, Sendable {
    let collectionSlug: String
    var hadith: HadithRef?
    var position: ReadingPosition? = nil
    let updatedAt: Date

    var id: String { collectionSlug }
}

@MainActor
struct LibraryReadTransport {
    let saved: () -> AnyPublisher<SyncSavedSnapshot, Error>
    let positions: () -> AnyPublisher<SyncPositionsSnapshot, Error>
}

/// Single facade over the user's personal data — bookmarks, favorites, notes,
/// reading progress — for both auth states. Signed in, everything is realtime
/// through Convex subscriptions; guests read and write the SwiftData store,
/// which syncs into Convex on sign-in through the guest merge.
@MainActor
@Observable
final class UserLibraryModel {
    enum LoadState { case loading, ready, failed }
    private(set) var loadState: LoadState = .loading
    private(set) var savedItems: [SavedItemEntry] = []
    private(set) var folders: [SavedFolder] = []
    private(set) var lastFolderDeletion: SavedFolderDeletion?

    /// Ends the folder-deletion undo window. Called when the undo banner's
    /// five-second deadline lapses.
    func clearFolderDeletion() {
        lastFolderDeletion = nil; folderUndo = nil; guestFolderDeletion = nil
    }
    private var guestFolderDeletion: GuestFolderDeletion?
    private(set) var bookmarks: [SavedEntry] = []
    private(set) var favorites: [SavedEntry] = []
    private(set) var notes: [SavedEntry] = []
    private(set) var progress: [ProgressEntry] = []

    private let reads: LibraryReadTransport?
    private let sync: LibrarySync?
    private let guestData: GuestDataStore
    private let currentSession: () -> LibrarySyncSession?
    private var scopedOwner: LibrarySyncOwner?
    private var scopedSession: LibrarySyncSession?
    private var epoch = UUID()
    private var cancellables: Set<AnyCancellable> = []
    private var subscriptionsActive = false
    private var subscriptionRetriesLeft = 5
    private var retryTask: Task<Void, Never>?
    private var lastIntentAt = 0.0
    private(set) var lastWriteFailed = false
    private enum UndoScope { case guest(UUID), account(LibraryWriteContext) }
    private struct UndoAction { let deletionID: String; let scope: UndoScope; let expiresAt: Double }
    private var undoActions: [String: UndoAction] = [:]
    private var folderUndo: UndoAction?

    init(guestData: GuestDataStore) {
        self.guestData = guestData; self.reads = nil; self.sync = nil; self.currentSession = { nil }
    }

    init(reads: LibraryReadTransport, guestData: GuestDataStore, sync: LibrarySync, currentSession: @escaping () -> LibrarySyncSession?) {
        self.reads = reads; self.guestData = guestData; self.sync = sync; self.currentSession = currentSession
    }

    convenience init(convex: ConvexClientWithAuth<String>, guestData: GuestDataStore, sync: LibrarySync, currentSession: @escaping () -> LibrarySyncSession?) {
        self.init(reads: .init(saved: { convex.subscribe(to: "librarySync:savedSnapshot", yielding: SyncSavedSnapshot.self).mapError { value -> Error in value }.eraseToAnyPublisher() },
                               positions: { convex.subscribe(to: "librarySync:positionsSnapshot", yielding: SyncPositionsSnapshot.self).mapError { value -> Error in value }.eraseToAnyPublisher() }),
                  guestData: guestData, sync: sync, currentSession: currentSession)
    }

    var actionScope: UUID { epoch }
    func isActionCurrent(_ captured: UUID?) -> Bool {
        guard let captured, captured == epoch, currentSession() == scopedSession else { return false }
        return scopedOwner == sync?.owner || (scopedOwner == nil && currentSession() == nil)
    }

    private func isSignedIn() -> Bool { currentSession() != nil }

    func refresh() {
        let session = currentSession()
        let owner = sync?.owner.flatMap { $0.subject == session?.subject ? $0 : nil }
        if session != scopedSession || owner != scopedOwner {
            unsubscribe()
            scopedSession = session; scopedOwner = owner
            subscriptionRetriesLeft = 5
        }
        guard let session else { loadGuestData(); return }
        guard let owner else { loadState = .loading; return }
        reloadAccount(owner)
        guard !subscriptionsActive, reads != nil else { return }
        subscriptionsActive = true
        subscribeAll(owner: owner, session: session, epoch: epoch)
    }

    func partitionChanged(_ owner: LibrarySyncOwner) {
        guard scopedOwner == owner, currentSession() == scopedSession else { return }
        reloadAccount(owner)
    }

    private func reloadAccount(_ owner: LibrarySyncOwner) {
        guard currentSession() == scopedSession, scopedOwner == owner else { return }
        do {
            guard let state = try guestData.syncPartition(owner) else { loadState = .loading; return }
            let value = LibraryProjection(state)
            savedItems = value.items; folders = value.folders; progress = value.progress
            bookmarks = value.items.compactMap { item in item.bookmarkCreatedAt.map { .init(rowId: item.hadithId, createdAt: $0, hadith: item.hadith) } }
            favorites = value.items.compactMap { item in item.favoriteCreatedAt.map { .init(rowId: item.hadithId, createdAt: $0, hadith: item.hadith) } }
            notes = value.items.compactMap { item in item.noteContent.map { .init(rowId: item.hadithId, createdAt: item.noteCreatedAt ?? item.createdAt, updatedAt: item.noteUpdatedAt ?? item.updatedAt, noteContent: $0, hadith: item.hadith) } }
            loadState = state.savedSnapshot != nil || !value.items.isEmpty ? .ready : .loading
        } catch { loadState = .failed }
    }

    private func folderReference(_ id: String?) -> SyncFolderReference {
        guard let id else { return .none }
        return id.hasPrefix("local:") ? .local(.init(key: String(id.dropFirst(6)))) : .server(.init(id: id))
    }

    @discardableResult private func submit(_ make: (Double) -> SyncCommand, ref: HadithRef? = nil, removalKey: String? = nil, context captured: LibraryWriteContext? = nil) -> (LibraryLocalChange, LibraryWriteContext)? {
        guard let sync else { return nil }
        do {
            let context = try captured ?? sync.captureWriteContext()
            lastIntentAt = max(Date.now.millisecondsSinceEpoch, lastIntentAt + 1)
            let change = LibraryLocalChange(command: make(lastIntentAt), at: lastIntentAt, source: .account(ref))
            try sync.enqueue(change, context: context)
            if let removalKey { undoActions[removalKey] = .init(deletionID: change.operation.id, scope: .account(context), expiresAt: Date.now.millisecondsSinceEpoch + SavedUndoDeadline.duration * 1_000) }
            if let owner = sync.owner { reloadAccount(owner) }
            lastWriteFailed = false
            return (change, context)
        } catch { lastWriteFailed = true; loadState = .failed; return nil }
    }

    private func restore(_ ref: HadithRef, key: String, value: SyncCommandFacetRestoreValue) {
        guard let undo = undoActions.removeValue(forKey: key), undo.expiresAt > Date.now.millisecondsSinceEpoch else { return }
        guard case .account(let context) = undo.scope else { return }
        submit({ _ in .facetRestore(.init(hadithId: ref.hadithId, deletionId: undo.deletionID, value: value)) }, ref: ref, context: context)
    }

    private func recordGuestUndo(_ key: String) {
        undoActions[key] = .init(deletionID: "guest", scope: .guest(epoch), expiresAt: Date.now.millisecondsSinceEpoch + SavedUndoDeadline.duration * 1_000)
    }
    private func guestUndoAllowed(_ key: String) -> Bool {
        guard let undo = undoActions.removeValue(forKey: key), undo.expiresAt > Date.now.millisecondsSinceEpoch,
              case .guest(let capturedEpoch) = undo.scope else { return false }
        return currentSession() == nil && epoch == capturedEpoch
    }

    // MARK: - Reads

    var continueReading: ProgressEntry? {
        progress
            .filter { $0.hadith != nil }
            .max { $0.updatedAt < $1.updatedAt }
    }

    func progress(for collectionSlug: String) -> ProgressEntry? {
        progress.first { $0.collectionSlug == collectionSlug }
    }

    func isBookmarked(hadithId: String) -> Bool {
        bookmarks.contains { $0.hadith?.hadithId == hadithId }
    }

    func isFavorite(hadithId: String) -> Bool {
        favorites.contains { $0.hadith?.hadithId == hadithId }
    }

    // MARK: - Mutations

    @discardableResult func toggleBookmark(_ ref: HadithRef) -> Bool {
        if isSignedIn() {
            if isBookmarked(hadithId: ref.hadithId) { return submit({ _ in .bookmarkRemove(.init(hadithId: ref.hadithId)) }, ref: ref, removalKey: "bookmark:" + ref.hadithId) != nil }
            else { return submit({ at in .bookmarkAdd(.init(hadithId: ref.hadithId, createdAt: at)) }, ref: ref) != nil }
        } else if guestData.isBookmarked(hadithId: ref.hadithId) {
            guestData.removeBookmark(hadithId: ref.hadithId)
            recordGuestUndo("bookmark:" + ref.hadithId)
        } else {
            undoActions.removeValue(forKey: "bookmark:" + ref.hadithId)
            guestData.addBookmark(
                draft: GuestBookmarkDraft(
                    hadithId: ref.hadithId,
                    createdAt: .now,
                    collectionName: ref.collectionName,
                    referenceDisplay: ref.referenceDisplay,
                    volumeId: ref.volumeId,
                    hadithNumber: ref.hadithNumber
                )
            )
        }
        loadGuestData()
        return !guestData.lastWriteFailed
    }

    @discardableResult func toggleFavorite(_ ref: HadithRef) -> Bool {
        if isSignedIn() {
            if isFavorite(hadithId: ref.hadithId) { return submit({ _ in .favoriteRemove(.init(hadithId: ref.hadithId)) }, ref: ref, removalKey: "favorite:" + ref.hadithId) != nil }
            else { return submit({ at in .favoriteAdd(.init(hadithId: ref.hadithId, createdAt: at)) }, ref: ref) != nil }
        } else if guestData.isFavorite(hadithId: ref.hadithId) {
            guestData.removeFavorite(hadithId: ref.hadithId)
            recordGuestUndo("favorite:" + ref.hadithId)
        } else {
            undoActions.removeValue(forKey: "favorite:" + ref.hadithId)
            guestData.addFavorite(
                draft: GuestFavoriteDraft(
                    hadithId: ref.hadithId,
                    createdAt: .now,
                    collectionName: ref.collectionName,
                    referenceDisplay: ref.referenceDisplay,
                    volumeId: ref.volumeId,
                    hadithNumber: ref.hadithNumber
                )
            )
        }
        loadGuestData()
        return !guestData.lastWriteFailed
    }

    @discardableResult func removeBookmark(_ ref: HadithRef, scope: UUID) -> Bool {
        guard isActionCurrent(scope), isBookmarked(hadithId: ref.hadithId) else { return false }
        if isSignedIn() { return submit({ _ in .bookmarkRemove(.init(hadithId: ref.hadithId)) }, ref: ref, removalKey: "bookmark:" + ref.hadithId) != nil }
        guestData.removeBookmark(hadithId: ref.hadithId); recordGuestUndo("bookmark:" + ref.hadithId); loadGuestData()
        return !guestData.lastWriteFailed
    }
    @discardableResult func removeFavorite(_ ref: HadithRef, scope: UUID) -> Bool {
        guard isActionCurrent(scope), isFavorite(hadithId: ref.hadithId) else { return false }
        if isSignedIn() { return submit({ _ in .favoriteRemove(.init(hadithId: ref.hadithId)) }, ref: ref, removalKey: "favorite:" + ref.hadithId) != nil }
        guestData.removeFavorite(hadithId: ref.hadithId); recordGuestUndo("favorite:" + ref.hadithId); loadGuestData()
        return !guestData.lastWriteFailed
    }

    @discardableResult func saveNote(_ ref: HadithRef, content: String) -> Bool {
        if isSignedIn() {
            let created = notes.first { $0.hadith?.hadithId == ref.hadithId }?.createdAt.millisecondsSinceEpoch
            return submit({ at in .notePut(.init(hadithId: ref.hadithId, content: content, createdAt: created ?? at, updatedAt: at)) }, ref: ref) != nil
        } else {
            guestData.saveNote(
                hadithId: ref.hadithId,
                content: content,
                collectionName: ref.collectionName,
                referenceDisplay: ref.referenceDisplay,
                volumeId: ref.volumeId,
                hadithNumber: ref.hadithNumber
            )
        }
        loadGuestData()
        return !guestData.lastWriteFailed
    }

    @discardableResult func deleteNote(_ ref: HadithRef, scope: UUID) -> Bool {
        guard isActionCurrent(scope), notes.contains(where: { $0.hadith?.hadithId == ref.hadithId }) else { return false }
        if isSignedIn() {
            return submit({ _ in .noteRemove(.init(hadithId: ref.hadithId)) }, ref: ref, removalKey: "note:" + ref.hadithId) != nil
        } else {
            guestData.deleteNote(hadithId: ref.hadithId)
            recordGuestUndo("note:" + ref.hadithId)
        }
        loadGuestData()
        return !guestData.lastWriteFailed
    }

    func createFolder(name: String, scope: UUID) {
        guard isActionCurrent(scope) else { return }
        if isSignedIn() {
            guard GuestDataStore.validFolderName(name) else { lastWriteFailed = true; return }
            let key = UUID().uuidString
            submit({ _ in .folderCreate(.init(key: key, name: name.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping, purpose: .create)) })
        } else {
            _ = guestData.createSavedFolder(name: name)
            loadGuestData()
        }
    }

    func assignFolder(hadithId: String, folderId: String?, scope: UUID) {
        guard isActionCurrent(scope) else { return }
        if isSignedIn() {
            let ref = savedItems.first { $0.hadithId == hadithId }?.hadith
            submit({ _ in .membershipPut(.init(hadithId: hadithId, folder: folderReference(folderId), mode: nil)) }, ref: ref)
        } else {
            guestData.assignSavedFolder(hadithId: hadithId, folderLocalId: folderId)
            loadGuestData()
        }
    }

    func deleteFolder(_ folder: SavedFolder, scope: UUID) {
        guard isActionCurrent(scope) else { return }
        if isSignedIn() {
            guard let (change, context) = submit({ _ in .folderDelete(.init(folder: folderReference(folder.id))) }) else { return }
            folderUndo = .init(deletionID: change.operation.id, scope: .account(context), expiresAt: Date.now.millisecondsSinceEpoch + SavedUndoDeadline.duration * 1_000)
            lastFolderDeletion = .init(name: folder.name, deletedAt: change.operation.at)
        } else {
            guard let deletion = guestData.deleteSavedFolder(localId: folder.id) else { return }
            guestFolderDeletion = deletion
            folderUndo = .init(deletionID: "guest", scope: .guest(epoch), expiresAt: Date.now.millisecondsSinceEpoch + SavedUndoDeadline.duration * 1_000)
            lastFolderDeletion = SavedFolderDeletion(name: deletion.folder.name, deletedAt: deletion.folder.createdAt.timeIntervalSince1970 * 1_000)
            loadGuestData()
        }
    }

    func undoDeleteFolder() {
        guard let deletion = lastFolderDeletion else { return }
        if isSignedIn() {
            guard let undo = folderUndo, undo.expiresAt > Date.now.millisecondsSinceEpoch else { clearFolderDeletion(); return }
            guard case .account(let context) = undo.scope else { return }
            submit({ _ in .folderRestore(.init(deletionId: undo.deletionID, name: deletion.name, hadithIds: [])) }, context: context)
            folderUndo = nil; lastFolderDeletion = nil
        } else if let guestFolderDeletion {
            guard let undo = folderUndo, undo.expiresAt > Date.now.millisecondsSinceEpoch,
                  case .guest(let capturedEpoch) = undo.scope, capturedEpoch == epoch else { clearFolderDeletion(); return }
            guestData.restoreSavedFolder(guestFolderDeletion)
            self.guestFolderDeletion = nil
            lastFolderDeletion = nil
            loadGuestData()
        }
    }

    func restoreBookmark(_ ref: HadithRef, createdAt: Date) {
        if isSignedIn() {
            restore(ref, key: "bookmark:" + ref.hadithId, value: .bookmark(.init(createdAt: createdAt.millisecondsSinceEpoch)))
        } else {
            guard guestUndoAllowed("bookmark:" + ref.hadithId) else { return }
            guestData.addBookmark(draft: GuestBookmarkDraft(hadithId: ref.hadithId, createdAt: createdAt, collectionName: ref.collectionName, referenceDisplay: ref.referenceDisplay, volumeId: ref.volumeId, hadithNumber: ref.hadithNumber))
            loadGuestData()
        }
    }

    func restoreFavorite(_ ref: HadithRef, createdAt: Date) {
        if isSignedIn() {
            restore(ref, key: "favorite:" + ref.hadithId, value: .favorite(.init(createdAt: createdAt.millisecondsSinceEpoch)))
        } else {
            guard guestUndoAllowed("favorite:" + ref.hadithId) else { return }
            guestData.addFavorite(draft: GuestFavoriteDraft(hadithId: ref.hadithId, createdAt: createdAt, collectionName: ref.collectionName, referenceDisplay: ref.referenceDisplay, volumeId: ref.volumeId, hadithNumber: ref.hadithNumber))
            loadGuestData()
        }
    }

    func restoreNote(_ ref: HadithRef, content: String, createdAt: Date, updatedAt: Date) {
        if isSignedIn() {
            restore(ref, key: "note:" + ref.hadithId, value: .note(.init(content: content, createdAt: createdAt.millisecondsSinceEpoch, updatedAt: updatedAt.millisecondsSinceEpoch)))
        } else {
            guard guestUndoAllowed("note:" + ref.hadithId) else { return }
            guestData.addNote(hadithId: ref.hadithId, content: content, createdAt: createdAt, updatedAt: updatedAt)
            loadGuestData()
        }
    }

    /// Saves the reader position. Called on page turns and on leaving the
    /// reader; the per-collection upsert on the backend makes repeats cheap.
    func saveProgress(_ position: ReadingPosition, ref: HadithRef) {
        if isSignedIn() {
            submit({ _ in .positionPut(.init(position: position)) }, ref: ref)
        } else {
            guestData.saveProgress(
                draft: GuestReadingProgressDraft(
                    collectionSlug: ref.collectionSlug,
                    collectionName: ref.collectionName,
                    hadithId: ref.hadithId,
                    volumeId: ref.volumeId,
                    hadithNumber: ref.hadithNumber,
                    referenceDisplay: ref.referenceDisplay,
                    updatedAt: .init(timeIntervalSince1970: position.updatedAt / 1000),
                    position: position
                )
            )
        }
        loadGuestData()
    }

    // MARK: - Owned subscriptions

    private func matches(_ owner: LibrarySyncOwner, session: LibrarySyncSession, epoch: UUID) -> Bool {
        self.epoch == epoch && scopedOwner == owner && scopedSession == session && currentSession() == session && sync?.owner == owner
    }

    private func subscribeAll(owner: LibrarySyncOwner, session: LibrarySyncSession, epoch: UUID) {
        guard let reads else { return }
        reads.saved().receive(on: DispatchQueue.main).sink(receiveCompletion: { [weak self] completion in
            if case .failure = completion { self?.subscriptionFailed(owner: owner, session: session, epoch: epoch) }
        }, receiveValue: { [weak self] snapshot in
            guard let self, matches(owner, session: session, epoch: epoch), snapshot.ownerKey == owner.key else { return }
            do { try guestData.cacheSavedSnapshot(snapshot, owner: owner); reloadAccount(owner); sync?.wake() }
            catch { loadState = .failed }
        }).store(in: &cancellables)
        reads.positions().receive(on: DispatchQueue.main).sink(receiveCompletion: { [weak self] completion in
            if case .failure = completion { self?.subscriptionFailed(owner: owner, session: session, epoch: epoch) }
        }, receiveValue: { [weak self] snapshot in
            guard let self, matches(owner, session: session, epoch: epoch), snapshot.ownerKey == owner.key else { return }
            do { try guestData.cachePositionsSnapshot(snapshot, owner: owner); reloadAccount(owner) }
            catch { loadState = .failed }
        }).store(in: &cancellables)
    }

    private func subscriptionFailed(owner: LibrarySyncOwner, session: LibrarySyncSession, epoch: UUID) {
        guard matches(owner, session: session, epoch: epoch) else { return }
        if savedItems.isEmpty { loadState = .failed }
        cancellables.removeAll(); subscriptionsActive = false
        guard subscriptionRetriesLeft > 0 else { return }
        subscriptionRetriesLeft -= 1
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
            guard let self, matches(owner, session: session, epoch: epoch) else { return }
            refresh()
        }
    }

    private func unsubscribe() {
        epoch = UUID(); retryTask?.cancel(); retryTask = nil
        cancellables.removeAll(); subscriptionsActive = false
        savedItems = []; folders = []; bookmarks = []; favorites = []; notes = []; progress = []
        undoActions = [:]; folderUndo = nil; guestFolderDeletion = nil; lastFolderDeletion = nil
    }

    // MARK: - Guest data

    private func loadGuestData() {
        guard !isSignedIn() else { return }
        defer { lastWriteFailed = guestData.lastWriteFailed; loadState = guestData.lastWriteFailed ? .failed : .ready }
        bookmarks = guestData.bookmarkDrafts().map { draft in
            SavedEntry(
                rowId: "guest-bookmark-\(draft.hadithId)",
                createdAt: draft.createdAt,
                hadith: Self.ref(from: draft)
            )
        }
        favorites = guestData.favoriteDrafts().map { draft in
            SavedEntry(
                rowId: "guest-favorite-\(draft.hadithId)",
                createdAt: draft.createdAt,
                hadith: Self.ref(from: draft)
            )
        }
        notes = guestData.noteDrafts().map { draft in
            SavedEntry(
                rowId: "guest-note-\(draft.hadithId)",
                createdAt: draft.createdAt,
                updatedAt: draft.updatedAt,
                noteContent: draft.content,
                hadith: Self.ref(from: draft)
            )
        }
        progress = guestData.progressDrafts().map { draft in
            ProgressEntry(
                collectionSlug: draft.collectionSlug,
                hadith: Self.progressRef(from: draft),
                position: draft.readingPosition,
                updatedAt: draft.updatedAt
            )
        }
        folders = guestData.folderDrafts().map { SavedFolder(id: $0.localId, name: $0.name, createdAt: $0.createdAt) }
        rebuildGuestSavedItems(memberships: guestData.savedMembershipDrafts())
    }

    private func rebuildGuestSavedItems(memberships: [GuestSavedMembershipDraft] = []) {
        let folderByHadith = Dictionary(uniqueKeysWithValues: memberships.map { ($0.hadithId, $0.folderLocalId) })
        var byHadith: [String: SavedItemEntry] = [:]
        for entry in bookmarks where entry.hadith != nil {
            let ref = entry.hadith!
            byHadith[ref.hadithId] = SavedItemEntry(hadithId: ref.hadithId, createdAt: entry.createdAt, updatedAt: entry.sortDate, bookmarkCreatedAt: entry.createdAt, favoriteCreatedAt: nil, noteContent: nil, folderId: folderByHadith[ref.hadithId], hadith: ref)
        }
        for entry in favorites where entry.hadith != nil {
            let ref = entry.hadith!
            let prior = byHadith[ref.hadithId]
            byHadith[ref.hadithId] = SavedItemEntry(hadithId: ref.hadithId, createdAt: min(prior?.createdAt ?? entry.createdAt, entry.createdAt), updatedAt: max(prior?.updatedAt ?? entry.sortDate, entry.sortDate), bookmarkCreatedAt: prior?.bookmarkCreatedAt, favoriteCreatedAt: entry.createdAt, noteContent: prior?.noteContent, folderId: folderByHadith[ref.hadithId], hadith: ref)
        }
        for entry in notes where entry.hadith != nil {
            let ref = entry.hadith!
            let prior = byHadith[ref.hadithId]
            byHadith[ref.hadithId] = SavedItemEntry(hadithId: ref.hadithId, createdAt: min(prior?.createdAt ?? entry.createdAt, entry.createdAt), updatedAt: max(prior?.updatedAt ?? entry.sortDate, entry.sortDate), bookmarkCreatedAt: prior?.bookmarkCreatedAt, favoriteCreatedAt: prior?.favoriteCreatedAt, noteContent: entry.noteContent, folderId: folderByHadith[ref.hadithId], hadith: ref)
        }
        savedItems = byHadith.values.sorted { $0.sortDate > $1.sortDate }
    }

    // MARK: - Mappers

    fileprivate static func ref(from draft: GuestBookmarkDraft) -> HadithRef {
        HadithRef(
            hadithId: draft.hadithId,
            collectionSlug: ReaderModels.collectionSlug(forName: draft.collectionName),
            collectionName: draft.collectionName ?? "Saved hadith",
            volumeId: draft.volumeId,
            hadithNumber: draft.hadithNumber,
            arabicText: "",
            englishText: nil,
            referenceDisplay: draft.referenceDisplay ?? ""
        )
    }

    fileprivate static func ref(from draft: GuestFavoriteDraft) -> HadithRef {
        HadithRef(
            hadithId: draft.hadithId,
            collectionSlug: ReaderModels.collectionSlug(forName: draft.collectionName),
            collectionName: draft.collectionName ?? "Saved hadith",
            volumeId: draft.volumeId,
            hadithNumber: draft.hadithNumber,
            arabicText: "",
            englishText: nil,
            referenceDisplay: draft.referenceDisplay ?? ""
        )
    }

    fileprivate static func ref(from draft: GuestNoteDraft) -> HadithRef {
        HadithRef(
            hadithId: draft.hadithId,
            collectionSlug: ReaderModels.collectionSlug(forName: draft.collectionName),
            collectionName: draft.collectionName ?? "Saved hadith",
            volumeId: draft.volumeId,
            hadithNumber: draft.hadithNumber,
            arabicText: "",
            englishText: nil,
            referenceDisplay: draft.referenceDisplay ?? ""
        )
    }

    fileprivate static func progressRef(from draft: GuestReadingProgressDraft) -> HadithRef {
        HadithRef(
            hadithId: draft.hadithId,
            collectionSlug: draft.collectionSlug,
            collectionName: draft.collectionName,
            volumeId: draft.volumeId,
            hadithNumber: draft.hadithNumber,
            arabicText: "",
            englishText: nil,
            referenceDisplay: draft.referenceDisplay ?? ""
        )
    }

}


@MainActor
extension LibraryLocalSource {
    var reference: HadithRef? {
        switch self {
        case .account(let value): value
        case .bookmark(let value): UserLibraryModel.ref(from: value)
        case .favorite(let value): UserLibraryModel.ref(from: value)
        case .note(let value): UserLibraryModel.ref(from: value)
        case .position(let value): UserLibraryModel.progressRef(from: value)
        case .folder, .membership: nil
        }
    }
}

@MainActor
struct LibraryProjection {
    let items: [SavedItemEntry]
    let folders: [SavedFolder]
    let progress: [ProgressEntry]

    init(_ state: LibraryPartitionState) {
        func date(_ value: Double) -> Date { Date(timeIntervalSince1970: value / 1_000) }
        func reference(_ value: SyncHadithSummary) -> HadithRef {
            .init(hadithId: value._id, collectionSlug: value.collectionSlug, collectionName: value.collectionName, volumeId: value.volumeId,
                  hadithNumber: value.providerHadithId, arabicText: value.arabicText, englishText: value.englishText, referenceDisplay: value.referenceDisplay)
        }
        var byID = Dictionary(uniqueKeysWithValues: (state.savedSnapshot?.items ?? []).map { value in
            (value.hadithId, SavedItemEntry(hadithId: value.hadithId, createdAt: date(value.createdAt), updatedAt: date(value.updatedAt),
                bookmarkCreatedAt: value.bookmarkCreatedAt.map(date), favoriteCreatedAt: value.favoriteCreatedAt.map(date), noteContent: value.noteContent,
                noteCreatedAt: value.noteCreatedAt.map(date), noteUpdatedAt: value.noteUpdatedAt.map(date), folderId: value.folderId, hadith: reference(value.hadith)))
        })
        var byFolder = Dictionary(uniqueKeysWithValues: (state.savedSnapshot?.folders ?? []).map { ($0._id, SavedFolder(id: $0._id, name: $0.name, createdAt: date($0.createdAt))) })
        var byCollection = Dictionary(uniqueKeysWithValues: (state.positionsSnapshot?.rows ?? []).map { ($0.collectionSlug, ProgressEntry(collectionSlug: $0.collectionSlug, hadith: reference($0.hadith), position: $0.position, updatedAt: date($0.updatedAt))) })
        func folderID(_ value: SyncFolderReference) -> String? {
            switch value { case .none: nil; case .server(let value): value.id; case .local(let value): state.folderMappings[value.key] ?? "local:" + value.key }
        }
        func initial(_ id: String, _ change: LibraryLocalChange) -> SavedItemEntry {
            byID[id] ?? .init(hadithId: id, createdAt: date(change.operation.at), updatedAt: date(change.operation.at), hadith: change.source.reference)
        }
        var removedBy: [String: String] = [:]
        func hasSavedFacet(_ item: SavedItemEntry) -> Bool { item.bookmarkCreatedAt != nil || item.favoriteCreatedAt != nil || item.noteContent != nil }
        let changes: [(LibraryLocalChange, SyncOutcome?)] = state.confirmed.map { ($0.change, $0.outcome) }
            + state.projectedFrozenChanges.map { ($0, nil) } + state.pending.map { ($0, nil) }
        for (change, outcome) in changes {
            let at = date(change.operation.at)
            switch change.operation.command {
            case .bookmarkAdd(let value):
                var item = initial(value.hadithId, change); item.bookmarkCreatedAt = min(item.bookmarkCreatedAt ?? date(value.createdAt), date(value.createdAt)); item.updatedAt = max(item.updatedAt, at); byID[value.hadithId] = item
            case .bookmarkRemove(let value):
                if var item = byID[value.hadithId] { item.bookmarkCreatedAt = nil; item.updatedAt = max(item.updatedAt, at); byID[value.hadithId] = item; if !hasSavedFacet(item) { removedBy.removeValue(forKey: value.hadithId) } }
            case .favoriteAdd(let value):
                var item = initial(value.hadithId, change); item.favoriteCreatedAt = min(item.favoriteCreatedAt ?? date(value.createdAt), date(value.createdAt)); item.updatedAt = max(item.updatedAt, at); byID[value.hadithId] = item
            case .favoriteRemove(let value):
                if var item = byID[value.hadithId] { item.favoriteCreatedAt = nil; item.updatedAt = max(item.updatedAt, at); byID[value.hadithId] = item; if !hasSavedFacet(item) { removedBy.removeValue(forKey: value.hadithId) } }
            case .notePut(let value):
                var item = initial(value.hadithId, change); item.noteContent = value.content; item.noteCreatedAt = item.noteCreatedAt ?? date(value.createdAt); item.noteUpdatedAt = date(value.updatedAt); item.updatedAt = max(item.updatedAt, date(value.updatedAt)); byID[value.hadithId] = item
            case .noteRemove(let value):
                if var item = byID[value.hadithId] { item.noteContent = nil; item.noteCreatedAt = nil; item.noteUpdatedAt = nil; item.updatedAt = max(item.updatedAt, at); byID[value.hadithId] = item; if !hasSavedFacet(item) { removedBy.removeValue(forKey: value.hadithId) } }
            case .membershipPut(let value):
                if value.mode == "claim_if_unset" && outcome == nil { break }
                if var item = byID[value.hadithId] { item.folderId = folderID(value.folder); item.updatedAt = max(item.updatedAt, at); byID[value.hadithId] = item }
                removedBy.removeValue(forKey: value.hadithId)
            case .folderCreate(let value):
                let id = state.folderMappings[value.key] ?? "local:" + value.key
                byFolder[id] = byFolder[id] ?? .init(id: id, name: value.name, createdAt: at)
            case .folderDelete(let value):
                if let id = folderID(value.folder) {
                    byFolder.removeValue(forKey: id)
                    for (key, var item) in byID where item.folderId == id { removedBy[key] = change.operation.id; item.folderId = nil; item.updatedAt = max(item.updatedAt, at); byID[key] = item }
                }
            case .folderRestore(let value):
                let id: String; let restored: [String]
                if case .folderRestored(let result) = outcome { id = result.folderId; restored = result.restored }
                else { id = byFolder.values.first { $0.name.precomposedStringWithCanonicalMapping.lowercased() == value.name.precomposedStringWithCanonicalMapping.lowercased() }?.id ?? state.folderMappings["restore:" + value.deletionId] ?? "local:restore:" + value.deletionId; restored = value.hadithIds }
                byFolder[id] = byFolder[id] ?? .init(id: id, name: value.name, createdAt: at)
                if outcome == nil && value.hadithIds.isEmpty {
                    for (key, var item) in byID where removedBy[key] == value.deletionId && item.folderId == nil && hasSavedFacet(item) {
                        item.folderId = id; item.updatedAt = max(item.updatedAt, at); byID[key] = item; removedBy.removeValue(forKey: key)
                    }
                } else {
                    for key in restored { if var item = byID[key] { item.folderId = id; item.updatedAt = max(item.updatedAt, at); byID[key] = item; removedBy.removeValue(forKey: key) } }
                }
            case .facetRestore(let value):
                var item = initial(value.hadithId, change)
                switch value.value {
                case .bookmark(let value): item.bookmarkCreatedAt = item.bookmarkCreatedAt ?? date(value.createdAt)
                case .favorite(let value): item.favoriteCreatedAt = item.favoriteCreatedAt ?? date(value.createdAt)
                case .note(let value): item.noteContent = value.content; item.noteCreatedAt = date(value.createdAt); item.noteUpdatedAt = at
                }
                item.updatedAt = max(item.updatedAt, at); byID[value.hadithId] = item
            case .positionPut(let value):
                byCollection[value.position.anchor.collectionSlug] = .init(collectionSlug: value.position.anchor.collectionSlug, hadith: change.source.reference, position: value.position, updatedAt: date(value.position.updatedAt))
            case .legacyPositionPut(let value):
                let position: ReadingPosition?
                if case .resolvedPosition(let result) = outcome { position = result.position }
                else if case .position(let draft) = change.source { position = draft.readingPosition }
                else { position = nil }
                if let source = change.source.reference { byCollection[source.collectionSlug] = .init(collectionSlug: source.collectionSlug, hadith: source, position: position, updatedAt: date(value.updatedAt)) }
            }
        }
        items = byID.values.filter { $0.bookmarkCreatedAt != nil || $0.favoriteCreatedAt != nil || $0.noteContent != nil }.sorted { $0.sortDate > $1.sortDate }
        folders = byFolder.values.sorted { $0.createdAt < $1.createdAt }
        progress = byCollection.values.sorted { $0.updatedAt > $1.updatedAt }
    }
}
