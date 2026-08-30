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

    struct Progress: Equatable, Sendable {
        let collectionSlug: String
        let hadithId: String
        let updatedAt: Double
    }

    let bookmarks: [Bookmark]
    let notes: [Note]
    var favorites: [Favorite]
    var readingProgress: [Progress]

    init(
        bookmarks: [Bookmark],
        notes: [Note],
        favorites: [Favorite] = [],
        readingProgress: [Progress] = []
    ) {
        self.bookmarks = bookmarks
        self.notes = notes
        self.favorites = favorites
        self.readingProgress = readingProgress
    }

    var isEmpty: Bool {
        bookmarks.isEmpty && notes.isEmpty && favorites.isEmpty && readingProgress.isEmpty
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
        progress: [GuestReadingProgressDraft] = []
    ) -> GuestMergePayload {
        let validBookmarks = dedupeBookmarks(bookmarks.filter { isValidHadithId($0.hadithId) })
        let validNotes = dedupeNotes(notes.filter { isValidHadithId($0.hadithId) })
        let validFavorites = dedupeFavorites(favorites.filter { isValidHadithId($0.hadithId) })
        let validProgress = dedupeProgress(progress.filter { isValidHadithId($0.hadithId) })

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
                .sorted { $0.updatedAt < $1.updatedAt }
                .map {
                    .init(
                        collectionSlug: $0.collectionSlug,
                        hadithId: $0.hadithId,
                        updatedAt: $0.updatedAt.millisecondsSinceEpoch
                    )
                }
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
            if existing == nil || entry.updatedAt > existing!.updatedAt {
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
