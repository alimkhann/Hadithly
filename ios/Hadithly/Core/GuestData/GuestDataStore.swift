import Foundation
import Observation
import SwiftData

/// Owns the on-device guest store. Guests read everything through Convex but
/// their bookmarks and notes never touch the server until sign-in, when the
/// planner builds a payload and the store clears after a confirmed merge.
@MainActor
@Observable
final class GuestDataStore {
    /// Observable so views can react to local insertions without re-fetching.
    private(set) var itemCount = 0

    private let container: ModelContainer
    private let context: ModelContext

    init(inMemory: Bool = false) {
        let schema = Schema([GuestBookmark.self, GuestNote.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        self.container = try! ModelContainer(for: schema, configurations: [configuration])
        self.context = ModelContext(container)
        context.autosaveEnabled = false
        refreshCount()
    }

    func addBookmark(hadithId: String, createdAt: Date = .now) {
        context.insert(GuestBookmark(hadithId: hadithId, createdAt: createdAt))
        try? context.save()
        refreshCount()
    }

    func addNote(hadithId: String, content: String, createdAt: Date = .now, updatedAt: Date = .now) {
        context.insert(GuestNote(hadithId: hadithId, content: content, createdAt: createdAt, updatedAt: updatedAt))
        try? context.save()
        refreshCount()
    }

    func bookmarkDrafts() -> [GuestBookmarkDraft] {
        let descriptor = FetchDescriptor<GuestBookmark>(sortBy: [SortDescriptor(\.createdAt)])
        let models = (try? context.fetch(descriptor)) ?? []
        return models.map { GuestBookmarkDraft(hadithId: $0.hadithId, createdAt: $0.createdAt) }
    }

    func noteDrafts() -> [GuestNoteDraft] {
        let descriptor = FetchDescriptor<GuestNote>(sortBy: [SortDescriptor(\.updatedAt)])
        let models = (try? context.fetch(descriptor)) ?? []
        return models.map {
            GuestNoteDraft(hadithId: $0.hadithId, content: $0.content, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
        }
    }

    /// Called only after the merge mutation reports success — the Convex copy
    /// is authoritative from that point on.
    func clearAll() {
        try? context.delete(model: GuestBookmark.self)
        try? context.delete(model: GuestNote.self)
        try? context.save()
        refreshCount()
    }

    private func refreshCount() {
        let bookmarks = (try? context.fetchCount(FetchDescriptor<GuestBookmark>())) ?? 0
        let notes = (try? context.fetchCount(FetchDescriptor<GuestNote>())) ?? 0
        itemCount = bookmarks + notes
    }
}
