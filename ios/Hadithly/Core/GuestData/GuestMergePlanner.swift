import Foundation

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
