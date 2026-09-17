import Combine
import ConvexMobile
import Foundation
import Observation

/// A hadith reference shared by the Saved tab, the Today tab, and the reader
/// deep-link. `arabicText` is empty for guest entries saved before the hadith
/// text was captured — callers render a fallback.
struct HadithRef: Identifiable, Equatable, Sendable {
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
    let createdAt: Date
    let updatedAt: Date
    var bookmarkCreatedAt: Date?
    var favoriteCreatedAt: Date?
    var noteContent: String?
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

struct SavedFolderDeletion: Decodable, Equatable, Sendable {
    let name: String
    let hadithIds: [String]
    let deletedAt: Double
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

/// Row shapes decoded from Convex — mirror of the `*Detailed` queries in
/// backend/convex/library.ts.
private struct HadithSummary: Decodable, Sendable {
    let _id: String
    let providerHadithId: String
    let collectionSlug: String
    let collectionName: String
    let volumeId: String?
    let arabicText: String
    let englishText: String?
    let referenceDisplay: String
}

private struct DetailedRow: Decodable, Sendable {
    let _id: String
    let createdAt: Double
    let hadith: HadithSummary?
}

private struct DetailedNoteRow: Decodable, Sendable {
    let _id: String
    let content: String
    let createdAt: Double
    let updatedAt: Double
    let hadith: HadithSummary?
}

private struct ProgressRow: Decodable, Sendable {
    let collectionSlug: String
    let hadithId: String
    let updatedAt: Double
    let position: ReadingPosition?
    let hadith: HadithSummary?
}

private struct SavedFolderRow: Decodable, Sendable {
    let _id: String
    let name: String
    let createdAt: Double
}

private struct SavedItemRow: Decodable, Sendable {
    let hadithId: String
    let createdAt: Double
    let updatedAt: Double
    let bookmarkCreatedAt: Double?
    let favoriteCreatedAt: Double?
    let noteContent: String?
    let folderId: String?
    let hadith: HadithSummary?
}

private struct SavedSnapshotRow: Decodable, Sendable {
    let folders: [SavedFolderRow]
    let items: [SavedItemRow]
}

/// Single facade over the user's personal data — bookmarks, favorites, notes,
/// reading progress — for both auth states. Signed in, everything is realtime
/// through Convex subscriptions; guests read and write the SwiftData store,
/// which syncs into Convex on sign-in through the guest merge.
@MainActor
@Observable
final class UserLibraryModel {
    private(set) var savedItems: [SavedItemEntry] = []
    private(set) var folders: [SavedFolder] = []
    private(set) var lastFolderDeletion: SavedFolderDeletion?

    /// Ends the folder-deletion undo window. Called when the undo banner's
    /// five-second deadline lapses.
    func clearFolderDeletion() {
        lastFolderDeletion = nil
    }
    private var guestFolderDeletion: GuestFolderDeletion?
    private(set) var bookmarks: [SavedEntry] = []
    private(set) var favorites: [SavedEntry] = []
    private(set) var notes: [SavedEntry] = []
    private(set) var progress: [ProgressEntry] = []

    private let convex: ConvexClientWithAuth<String>
    private let guestData: GuestDataStore
    private let isSignedIn: () -> Bool

    private var cancellables: Set<AnyCancellable> = []
    private var subscriptionsActive = false
    private var subscriptionRetriesLeft = 5

    init(
        convex: ConvexClientWithAuth<String>,
        guestData: GuestDataStore,
        isSignedIn: @escaping () -> Bool
    ) {
        self.convex = convex
        self.guestData = guestData
        self.isSignedIn = isSignedIn
    }

    // MARK: - Lifecycle

    /// Idempotent. Signed in → a Saved snapshot plus independent progress.
    /// Guest → pull local drafts. Call on auth changes — including every
    /// Convex auth-state transition, since a subscription opened before the
    /// session activated fails with Unauthenticated and must be re-opened.
    func refresh() {
        if isSignedIn() {
            guard !subscriptionsActive else { return }
            subscriptionsActive = true
            subscriptionRetriesLeft = 5
            subscribeAll()
        } else {
            unsubscribe()
            loadGuestData()
        }
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

    func toggleBookmark(_ ref: HadithRef) {
        if isSignedIn() {
            Task {
                try? await convex.mutation(
                    "library:toggleSavedBookmark",
                    with: ["hadithId": ref.hadithId as ConvexEncodable?]
                )
            }
        } else if guestData.isBookmarked(hadithId: ref.hadithId) {
            guestData.removeBookmark(hadithId: ref.hadithId)
        } else {
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
    }

    func toggleFavorite(_ ref: HadithRef) {
        if isSignedIn() {
            Task {
                try? await convex.mutation(
                    "library:toggleSavedFavorite",
                    with: ["hadithId": ref.hadithId as ConvexEncodable?]
                )
            }
        } else if guestData.isFavorite(hadithId: ref.hadithId) {
            guestData.removeFavorite(hadithId: ref.hadithId)
        } else {
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
    }

    func saveNote(_ ref: HadithRef, content: String) {
        if isSignedIn() {
            Task {
                try? await convex.mutation(
                    "library:upsertSavedNote",
                    with: [
                        "hadithId": ref.hadithId as ConvexEncodable?,
                        "content": content as ConvexEncodable?,
                    ]
                )
            }
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
    }

    func deleteNote(_ ref: HadithRef) {
        if isSignedIn() {
            Task {
                try? await convex.mutation(
                    "library:deleteSavedNote",
                    with: ["hadithId": ref.hadithId as ConvexEncodable?]
                )
            }
        } else {
            guestData.deleteNote(hadithId: ref.hadithId)
        }
        loadGuestData()
    }

    func createFolder(name: String) {
        if isSignedIn() {
            Task { try? await convex.mutation("library:createSavedFolder", with: ["name": name as ConvexEncodable?]) }
        } else {
            _ = guestData.createSavedFolder(name: name)
            loadGuestData()
        }
    }

    func assignFolder(hadithId: String, folderId: String?) {
        if isSignedIn() {
            Task {
                try? await convex.mutation(
                    "library:assignSavedFolder",
                    with: ["hadithId": hadithId as ConvexEncodable?, "folderId": folderId as ConvexEncodable?]
                )
            }
        } else {
            guestData.assignSavedFolder(hadithId: hadithId, folderLocalId: folderId)
            loadGuestData()
        }
    }

    func deleteFolder(_ folder: SavedFolder) {
        if isSignedIn() {
            Task {
                guard let deletion: SavedFolderDeletion = try? await convex.mutation("library:deleteSavedFolder", with: ["folderId": folder.id as ConvexEncodable?]) else { return }
                lastFolderDeletion = deletion
            }
        } else {
            guard let deletion = guestData.deleteSavedFolder(localId: folder.id) else { return }
            guestFolderDeletion = deletion
            lastFolderDeletion = SavedFolderDeletion(name: deletion.folder.name, hadithIds: deletion.hadithIds, deletedAt: deletion.folder.createdAt.timeIntervalSince1970 * 1_000)
            loadGuestData()
        }
    }

    func undoDeleteFolder() {
        guard let deletion = lastFolderDeletion else { return }
        if isSignedIn() {
            Task {
                let _: SavedFolderRestore? = try? await convex.mutation("library:restoreSavedFolder", with: [
                    "name": deletion.name as ConvexEncodable?,
                    "hadithIds": deletion.hadithIds.map { $0 as ConvexEncodable? } as ConvexEncodable?,
                    "deletedAt": deletion.deletedAt as ConvexEncodable?,
                ])
                lastFolderDeletion = nil
            }
        } else if let guestFolderDeletion {
            guestData.restoreSavedFolder(guestFolderDeletion)
            self.guestFolderDeletion = nil
            lastFolderDeletion = nil
            loadGuestData()
        }
    }

    func restoreBookmark(_ ref: HadithRef, createdAt: Date) {
        if isSignedIn() {
            Task { let _: Bool? = try? await convex.mutation("library:restoreSavedFacet", with: ["hadithId": ref.hadithId as ConvexEncodable?, "facet": "bookmark" as ConvexEncodable?, "createdAt": createdAt.millisecondsSinceEpoch as ConvexEncodable?]) }
        } else {
            guestData.addBookmark(draft: GuestBookmarkDraft(hadithId: ref.hadithId, createdAt: createdAt, collectionName: ref.collectionName, referenceDisplay: ref.referenceDisplay, volumeId: ref.volumeId, hadithNumber: ref.hadithNumber))
            loadGuestData()
        }
    }

    func restoreFavorite(_ ref: HadithRef, createdAt: Date) {
        if isSignedIn() {
            Task { let _: Bool? = try? await convex.mutation("library:restoreSavedFacet", with: ["hadithId": ref.hadithId as ConvexEncodable?, "facet": "favorite" as ConvexEncodable?, "createdAt": createdAt.millisecondsSinceEpoch as ConvexEncodable?]) }
        } else {
            guestData.addFavorite(draft: GuestFavoriteDraft(hadithId: ref.hadithId, createdAt: createdAt, collectionName: ref.collectionName, referenceDisplay: ref.referenceDisplay, volumeId: ref.volumeId, hadithNumber: ref.hadithNumber))
            loadGuestData()
        }
    }

    func restoreNote(_ ref: HadithRef, content: String, createdAt: Date, updatedAt: Date) {
        if isSignedIn() {
            Task { let _: Bool? = try? await convex.mutation("library:restoreSavedFacet", with: ["hadithId": ref.hadithId as ConvexEncodable?, "facet": "note" as ConvexEncodable?, "createdAt": createdAt.millisecondsSinceEpoch as ConvexEncodable?, "content": content as ConvexEncodable?, "updatedAt": updatedAt.millisecondsSinceEpoch as ConvexEncodable?]) }
        } else {
            guestData.addNote(hadithId: ref.hadithId, content: content, createdAt: createdAt, updatedAt: updatedAt)
            loadGuestData()
        }
    }

    /// Saves the reader position. Called on page turns and on leaving the
    /// reader; the per-collection upsert on the backend makes repeats cheap.
    func saveProgress(_ position: ReadingPosition, ref: HadithRef) {
        if isSignedIn() {
            Task {
                try? await convex.mutation(
                    "library:saveReadingProgress",
                    with: [
                        "position": position.convexWireValue as ConvexEncodable?,
                    ]
                )
            }
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

    // MARK: - Convex subscriptions (signed in)

    private func subscribeAll() {
        subscribe("library:listSavedSnapshot") { [weak self] (snapshot: SavedSnapshotRow) in
            self?.apply(snapshot: snapshot)
        }
        subscribe("library:listReadingProgressDetailed") { [weak self] (rows: [ProgressRow]) in
            self?.progress = rows.map {
                ProgressEntry(
                    collectionSlug: $0.collectionSlug,
                    hadith: $0.hadith.map(Self.ref(from:)),
                    position: $0.position,
                    updatedAt: Date(timeIntervalSince1970: $0.updatedAt / 1000)
                )
            }
        }
    }

    private func subscribe<T: Decodable & Sendable>(
        _ name: String,
        onUpdate: @escaping (T) -> Void
    ) {
        convex.subscribe(to: name, yielding: T.self)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.subscriptionFailed(error)
                    }
                },
                receiveValue: onUpdate
            )
            .store(in: &cancellables)
    }

    /// A subscription that raced the Convex session (opened unauthenticated)
    /// errors out without delivering data. Re-open everything, bounded.
    private func subscriptionFailed(_ error: Error) {
        subscriptionsActive = false
        guard subscriptionRetriesLeft > 0, isSignedIn() else { return }
        subscriptionRetriesLeft -= 1
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.refresh()
        }
    }

    private func unsubscribe() {
        cancellables.removeAll()
        subscriptionsActive = false
        savedItems = []
        folders = []
        bookmarks = []
        favorites = []
        notes = []
        progress = []
    }

    // MARK: - Guest data

    private func loadGuestData() {
        guard !isSignedIn() else { return }
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

    private func apply(snapshot: SavedSnapshotRow) {
        folders = snapshot.folders.map {
            SavedFolder(id: $0._id, name: $0.name, createdAt: Date(timeIntervalSince1970: $0.createdAt / 1_000))
        }
        savedItems = snapshot.items.map {
            SavedItemEntry(
                hadithId: $0.hadithId,
                createdAt: Date(timeIntervalSince1970: $0.createdAt / 1_000),
                updatedAt: Date(timeIntervalSince1970: $0.updatedAt / 1_000),
                bookmarkCreatedAt: $0.bookmarkCreatedAt.map { Date(timeIntervalSince1970: $0 / 1_000) },
                favoriteCreatedAt: $0.favoriteCreatedAt.map { Date(timeIntervalSince1970: $0 / 1_000) },
                noteContent: $0.noteContent,
                folderId: $0.folderId,
                hadith: $0.hadith.map(Self.ref(from:))
            )
        }
        bookmarks = savedItems.compactMap { item in
            guard let createdAt = item.bookmarkCreatedAt else { return nil }
            return SavedEntry(rowId: item.hadithId, createdAt: createdAt, hadith: item.hadith)
        }
        favorites = savedItems.compactMap { item in
            guard let createdAt = item.favoriteCreatedAt else { return nil }
            return SavedEntry(rowId: item.hadithId, createdAt: createdAt, hadith: item.hadith)
        }
        notes = savedItems.compactMap { item in
            guard let content = item.noteContent else { return nil }
            return SavedEntry(rowId: item.hadithId, createdAt: item.createdAt, updatedAt: item.updatedAt, noteContent: content, hadith: item.hadith)
        }
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

    private static func ref(from summary: HadithSummary) -> HadithRef {
        HadithRef(
            hadithId: summary._id,
            collectionSlug: summary.collectionSlug,
            collectionName: summary.collectionName,
            volumeId: summary.volumeId,
            hadithNumber: summary.providerHadithId,
            arabicText: summary.arabicText,
            englishText: summary.englishText,
            referenceDisplay: summary.referenceDisplay
        )
    }

    private static func ref(from draft: GuestBookmarkDraft) -> HadithRef {
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

    private static func ref(from draft: GuestFavoriteDraft) -> HadithRef {
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

    private static func ref(from draft: GuestNoteDraft) -> HadithRef {
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

    private static func progressRef(from draft: GuestReadingProgressDraft) -> HadithRef {
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
