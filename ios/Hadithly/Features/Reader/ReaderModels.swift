import ConvexMobile
import Foundation

/// Wire types for the reader, decoded straight from Convex action results.

struct ReaderHadith: Decodable, Identifiable, Equatable {
    let _id: String
    let providerHadithId: String
    let collectionSlug: String
    let volumeId: String?
    let arabicText: String
    let englishText: String?
    let narrator: String?
    let referenceDisplay: String
    let collectionName: String
    let chapterName: String?

    var id: String { _id }

    /// Internal id used by actions/ai:translateHadith.
    var internalId: String {
        "sunnah_now:\(collectionSlug):\(providerHadithId)"
    }
}

struct ReaderPageResult: Decodable {
    let items: [ReaderHadith]
    let page: Int
    let pageSize: Int
    let totalPages: Int
    let hasMore: Bool

    /// Skipped-by-jump pages start as page == 0 sentinels and load on demand.
    var isPlaceholder: Bool { page == 0 }
}

struct OutlineVolume: Decodable, Identifiable, Equatable {
    let volumeId: String
    let title: String
    let firstChapterTitle: String?
    let hadithCount: Int

    var id: String { volumeId }
}

struct CollectionOutlineResult: Decodable {
    let volumes: [OutlineVolume]
}

struct ReaderCitation: Decodable, Hashable {
    let url: String
    let title: String?
    let domain: String?
}

struct ReaderTranslation: Decodable {
    let hadithId: String
    let translation: String
    let confidence: Double
    let riskFlags: [String]
    let glossaryNotes: [String]
    let source: String
    let sourceLabel: String
    let aiModel: String?
    let groundingUsed: Bool
    let citations: [ReaderCitation]
    let sourceReferenceUrl: String?
    let cached: Bool
}

/// Maps Convex action failures to reader-facing states. The backend reports
/// the quota wall with the literal message "AI_GENERATION_QUOTA_EXCEEDED"
/// (convex/quotas.ts) and guests fail requireIdentity with "Unauthenticated".
enum TranslationFailure: Equatable {
    case quotaExceeded
    case requiresSignIn
    case failed(String)

    init(error: Error) {
        self.init(message: ReaderModels.errorMessage(of: error))
    }

    init(message: String) {
        if message.contains("AI_GENERATION_QUOTA_EXCEEDED") {
            self = .quotaExceeded
        } else if message.lowercased().contains("unauthenticated") {
            self = .requiresSignIn
        } else {
            self = .failed(message)
        }
    }
}

enum ReaderModels {
    /// The seven collections, in reading order. Mirrors
    /// DEFAULT_COLLECTION_ORDER in backend/convex/lib/sunnahNow.ts.
    static let collections: [(slug: String, name: String)] = [
        ("bukhari", "Sahih al-Bukhari"),
        ("muslim", "Sahih Muslim"),
        ("sunan-nasai", "Sunan an-Nasa'i"),
        ("abu-dawood", "Abu Dawood"),
        ("tirmidhi", "Jami` at-Tirmidhi"),
        ("ibn-majah", "Ibn Majah"),
        ("mishkat-al-masabih", "Mishkat al-Masabih"),
    ]

    static func errorMessage(of error: Error) -> String {
        if case let ClientError.ServerError(msg) = error {
            return msg
        }
        if case let ClientError.ConvexError(data) = error {
            return data
        }
        return error.localizedDescription
    }

    /// Reverse lookup used by guest-side saved items, which only store the
    /// collection's display name.
    static func collectionSlug(forName name: String?) -> String {
        guard let name else { return "bukhari" }
        return collections.first {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }?.slug ?? "bukhari"
    }
}
