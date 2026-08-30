import Foundation
import SwiftData

/// A bookmark saved while reading as a guest. Stored only on-device until the
/// user signs in, at which point it merges into Convex and is cleared locally.
@Model
final class GuestBookmark {
    var hadithId: String
    var createdAt: Date

    init(hadithId: String, createdAt: Date = .now) {
        self.hadithId = hadithId
        self.createdAt = createdAt
    }
}

/// A note written on a hadith while reading as a guest. Same lifecycle as
/// GuestBookmark: local-only until sign-in, then merged and cleared.
@Model
final class GuestNote {
    var hadithId: String
    var content: String
    var createdAt: Date
    var updatedAt: Date

    init(hadithId: String, content: String, createdAt: Date = .now, updatedAt: Date = .now) {
        self.hadithId = hadithId
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Plain-value snapshots of the guest items. SwiftData models stay inside the
/// store; everything downstream (merge planning, tests) works on these.
struct GuestBookmarkDraft: Equatable, Sendable {
    let hadithId: String
    let createdAt: Date
}

struct GuestNoteDraft: Equatable, Sendable {
    let hadithId: String
    let content: String
    let createdAt: Date
    let updatedAt: Date
}
