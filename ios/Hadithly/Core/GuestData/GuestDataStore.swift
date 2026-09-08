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

    private let container: ModelContainer
    private let context: ModelContext

    init(inMemory: Bool = false) {
        let schema = Schema([
            GuestBookmark.self,
            GuestNote.self,
            GuestFavorite.self,
            GuestReadingProgress.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        self.container = try! ModelContainer(for: schema, configurations: [configuration])
        self.context = ModelContext(container)
        context.autosaveEnabled = false
        refreshCount()
    }

    // MARK: - Bookmarks

    func addBookmark(hadithId: String, createdAt: Date = .now) {
        context.insert(GuestBookmark(hadithId: hadithId, createdAt: createdAt))
        try? context.save()
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
        try? context.save()
        refreshCount()
    }

    func removeBookmark(hadithId: String) {
        for model in fetchBookmarks().filter({ $0.hadithId == hadithId }) {
            context.delete(model)
        }
        try? context.save()
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
        try? context.save()
        refreshCount()
    }

    func removeFavorite(hadithId: String) {
        for model in fetchFavorites().filter({ $0.hadithId == hadithId }) {
            context.delete(model)
        }
        try? context.save()
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
        try? context.save()
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
        try? context.save()
        refreshCount()
    }

    func deleteNote(hadithId: String) {
        for model in fetchNotes().filter({ $0.hadithId == hadithId }) {
            context.delete(model)
        }
        try? context.save()
        refreshCount()
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
        try? context.save()
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

    // MARK: - Lifecycle

    /// Called only after the merge mutation reports success — the Convex copy
    /// is authoritative from that point on.
    func clearAll() {
        try? context.delete(model: GuestBookmark.self)
        try? context.delete(model: GuestNote.self)
        try? context.delete(model: GuestFavorite.self)
        try? context.delete(model: GuestReadingProgress.self)
        try? context.save()
        refreshCount()
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
}
