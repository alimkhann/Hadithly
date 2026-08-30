import Foundation
import SwiftData

/// A hadith the reader wants to find again, saved while reading as a guest.
/// Stored only on-device until the user signs in, at which point it merges
/// into Convex and is cleared locally.
@Model
final class GuestBookmark {
    var hadithId: String
    var createdAt: Date
    // Display metadata captured at save time so the Saved tab renders
    // without a server round trip. Optional so older local stores migrate.
    var collectionName: String?
    var referenceDisplay: String?
    var volumeId: String?
    var hadithNumber: String?

    init(
        hadithId: String,
        createdAt: Date = .now,
        collectionName: String? = nil,
        referenceDisplay: String? = nil,
        volumeId: String? = nil,
        hadithNumber: String? = nil
    ) {
        self.hadithId = hadithId
        self.createdAt = createdAt
        self.collectionName = collectionName
        self.referenceDisplay = referenceDisplay
        self.volumeId = volumeId
        self.hadithNumber = hadithNumber
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
    var collectionName: String?
    var referenceDisplay: String?
    var volumeId: String?
    var hadithNumber: String?

    init(
        hadithId: String,
        content: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        collectionName: String? = nil,
        referenceDisplay: String? = nil,
        volumeId: String? = nil,
        hadithNumber: String? = nil
    ) {
        self.hadithId = hadithId
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.collectionName = collectionName
        self.referenceDisplay = referenceDisplay
        self.volumeId = volumeId
        self.hadithNumber = hadithNumber
    }
}

/// A hadith marked as a favorite while reading as a guest.
@Model
final class GuestFavorite {
    var hadithId: String
    var createdAt: Date
    var collectionName: String?
    var referenceDisplay: String?
    var volumeId: String?
    var hadithNumber: String?

    init(
        hadithId: String,
        createdAt: Date = .now,
        collectionName: String? = nil,
        referenceDisplay: String? = nil,
        volumeId: String? = nil,
        hadithNumber: String? = nil
    ) {
        self.hadithId = hadithId
        self.createdAt = createdAt
        self.collectionName = collectionName
        self.referenceDisplay = referenceDisplay
        self.volumeId = volumeId
        self.hadithNumber = hadithNumber
    }
}

/// Private per-collection reading position. Progress is never shared or
/// ranked; it exists only so the reader can offer "continue reading".
@Model
final class GuestReadingProgress {
    var collectionSlug: String
    var collectionName: String
    var hadithId: String
    var volumeId: String?
    var hadithNumber: String?
    var referenceDisplay: String?
    var updatedAt: Date

    init(
        collectionSlug: String,
        collectionName: String,
        hadithId: String,
        volumeId: String? = nil,
        hadithNumber: String? = nil,
        referenceDisplay: String? = nil,
        updatedAt: Date = .now
    ) {
        self.collectionSlug = collectionSlug
        self.collectionName = collectionName
        self.hadithId = hadithId
        self.volumeId = volumeId
        self.hadithNumber = hadithNumber
        self.referenceDisplay = referenceDisplay
        self.updatedAt = updatedAt
    }
}

/// Plain-value snapshots of the guest items. SwiftData models stay inside the
/// store; everything downstream (merge planning, tests, Saved tab) works on
/// these.
struct GuestBookmarkDraft: Equatable, Sendable {
    let hadithId: String
    let createdAt: Date
    var collectionName: String?
    var referenceDisplay: String?
    var volumeId: String?
    var hadithNumber: String?

    init(
        hadithId: String,
        createdAt: Date,
        collectionName: String? = nil,
        referenceDisplay: String? = nil,
        volumeId: String? = nil,
        hadithNumber: String? = nil
    ) {
        self.hadithId = hadithId
        self.createdAt = createdAt
        self.collectionName = collectionName
        self.referenceDisplay = referenceDisplay
        self.volumeId = volumeId
        self.hadithNumber = hadithNumber
    }
}

struct GuestNoteDraft: Equatable, Sendable {
    let hadithId: String
    let content: String
    let createdAt: Date
    let updatedAt: Date
    var collectionName: String?
    var referenceDisplay: String?
    var volumeId: String?
    var hadithNumber: String?

    init(
        hadithId: String,
        content: String,
        createdAt: Date,
        updatedAt: Date,
        collectionName: String? = nil,
        referenceDisplay: String? = nil,
        volumeId: String? = nil,
        hadithNumber: String? = nil
    ) {
        self.hadithId = hadithId
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.collectionName = collectionName
        self.referenceDisplay = referenceDisplay
        self.volumeId = volumeId
        self.hadithNumber = hadithNumber
    }
}

struct GuestFavoriteDraft: Equatable, Sendable {
    let hadithId: String
    let createdAt: Date
    var collectionName: String?
    var referenceDisplay: String?
    var volumeId: String?
    var hadithNumber: String?

    init(
        hadithId: String,
        createdAt: Date,
        collectionName: String? = nil,
        referenceDisplay: String? = nil,
        volumeId: String? = nil,
        hadithNumber: String? = nil
    ) {
        self.hadithId = hadithId
        self.createdAt = createdAt
        self.collectionName = collectionName
        self.referenceDisplay = referenceDisplay
        self.volumeId = volumeId
        self.hadithNumber = hadithNumber
    }
}

struct GuestReadingProgressDraft: Equatable, Sendable {
    let collectionSlug: String
    let collectionName: String
    let hadithId: String
    var volumeId: String?
    var hadithNumber: String?
    var referenceDisplay: String?
    let updatedAt: Date
}
