import ConvexMobile
import Foundation

/// Wire types for the reader, decoded straight from Convex action results.

struct ReaderAuthenticity: Decodable, Equatable {
    let kind: String
    let normalizedGrade: String?
    let claimScope: String
    let sourceLabel: String
    let sourceName: String
    let sourceUrl: String
    let verificationMethod: String

    var displayLabel: String {
        switch (claimScope, normalizedGrade) {
        case ("hadith", let grade?):
            return "\(grade.capitalized) hadith · \(sourceName)"
        case ("collection", let grade?):
            return "\(grade.capitalized) collection scope · \(sourceName)"
        default:
            return "Authenticity not verified · \(sourceName)"
        }
    }
}

struct ReaderHadith: Decodable, Identifiable, Equatable {
    let _id: String
    let provider: String
    let canonicalId: String
    let providerHadithId: String
    let collectionSlug: String
    let volumeId: String?
    let chapterId: String?
    let arabicText: String
    let englishText: String?
    let narrator: String?
    let referenceDisplay: String
    let collectionName: String
    let chapterName: String?
    let authenticity: ReaderAuthenticity

    var id: String { _id }

    /// Internal id used by actions/ai:translateHadith.
    var internalId: String {
        canonicalId
    }
}

struct ReaderPageResult: Decodable {
    let items: [ReaderHadith]
    let page: Int
    let pageSize: Int
    let totalPages: Int
    let hasMore: Bool
    let contentVersion: String?
    let paginationVersion: Double?
    let pageKey: String?

    /// Skipped-by-jump pages start as page == 0 sentinels and load on demand.
    var isPlaceholder: Bool { page == 0 }
}

struct OutlineChapter: Decodable, Identifiable, Equatable {
    let chapterId: String?
    let title: String
    let arabicTitle: String?
    let hadithCount: Int
    let firstProviderHadithId: String

    var id: String { chapterId ?? "\(title)|\(firstProviderHadithId)" }

    init(
        chapterId: String? = nil,
        title: String,
        arabicTitle: String? = nil,
        hadithCount: Int,
        firstProviderHadithId: String
    ) {
        self.chapterId = chapterId
        self.title = title
        self.arabicTitle = arabicTitle
        self.hadithCount = hadithCount
        self.firstProviderHadithId = firstProviderHadithId
    }

    private enum CodingKeys: String, CodingKey {
        case chapterId, title, arabicTitle, hadithCount, firstProviderHadithId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        chapterId = try container.decodeIfPresent(String.self, forKey: .chapterId)
        title = try container.decode(String.self, forKey: .title)
        arabicTitle = try container.decodeIfPresent(String.self, forKey: .arabicTitle)
        hadithCount = try Self.decodeCount(container, key: .hadithCount)
        firstProviderHadithId = try container.decode(String.self, forKey: .firstProviderHadithId)
    }

    /// Convex numbers arrive as Double; pre-R5 fixtures may carry Int.
    private static func decodeCount(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> Int {
        if let int = try? container.decode(Int.self, forKey: key) { return int }
        let double = try container.decode(Double.self, forKey: key)
        return Int(double)
    }
}

struct OutlineVolume: Decodable, Identifiable, Equatable {
    let volumeId: String
    let title: String
    let firstChapterTitle: String?
    let hadithCount: Int
    /// Source-provided chapters (R5). Nil for outlines cached before R5;
    /// those volumes keep rendering exactly as before.
    let chapters: [OutlineChapter]?

    var id: String { volumeId }

    init(
        volumeId: String,
        title: String,
        firstChapterTitle: String? = nil,
        hadithCount: Int,
        chapters: [OutlineChapter]? = nil
    ) {
        self.volumeId = volumeId
        self.title = title
        self.firstChapterTitle = firstChapterTitle
        self.hadithCount = hadithCount
        self.chapters = chapters
    }

    private enum CodingKeys: String, CodingKey {
        case volumeId, title, firstChapterTitle, hadithCount, chapters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        volumeId = try container.decode(String.self, forKey: .volumeId)
        title = try container.decode(String.self, forKey: .title)
        firstChapterTitle = try container.decodeIfPresent(String.self, forKey: .firstChapterTitle)
        if let int = try? container.decode(Int.self, forKey: .hadithCount) {
            hadithCount = int
        } else {
            hadithCount = Int(try container.decode(Double.self, forKey: .hadithCount))
        }
        chapters = try container.decodeIfPresent([OutlineChapter].self, forKey: .chapters)
    }
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
    /// Convex `translations` row id, used by the report action.
    let translationId: String
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

struct TranslationAIReview: Decodable, Equatable, Sendable {
    let model: String
    let score: Double
    let riskFlags: [String]
    let missingMeaning: [String]?
    let addedMeaning: [String]?
    let glossaryIssues: [String]?
    let recommendation: String

    var reviewNotes: [String] {
        riskFlags
            + (missingMeaning ?? []).map { "Missing meaning: \($0)" }
            + (addedMeaning ?? []).map { "Added meaning: \($0)" }
            + (glossaryIssues ?? []).map { "Terminology: \($0)" }
    }
}

struct TranslationSubmissionResult: Decodable, Equatable, Sendable {
    let submissionId: String
    let aiReview: TranslationAIReview
    let status: String
}

struct TranslationReportResult: Decodable, Equatable, Sendable {
    let ok: Bool
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

/// R5 share/copy helpers. The canonical URL contract is
/// `https://hadithly.app/hadith/{collectionSlug}/{providerHadithId}` (F3);
/// validation reuses `CanonicalHadithLink.parse` so the builder and the
/// inbound parser can never disagree.
enum ReaderShare {
    /// Builds the shareable canonical URL, or nil when the slug or hadith
    /// id is malformed. Share sheets use only this URL — never a deep link
    /// with private position data.
    static func canonicalURL(collectionSlug: String, providerHadithId: String) -> URL? {
        guard CanonicalHadithLink.parse(
            collectionSlug: collectionSlug,
            providerHadithId: providerHadithId
        ) != nil else { return nil }
        return URL(string: "https://hadithly.app/hadith/\(collectionSlug)/\(providerHadithId)")
    }

    static func canonicalURL(for hadith: ReaderHadith) -> URL? {
        canonicalURL(
            collectionSlug: hadith.collectionSlug,
            providerHadithId: hadith.providerHadithId
        )
    }

    /// Validates a jump-to-reference / hadith-number field against the same
    /// provider-hadith-id pattern the canonical links enforce.
    static func isValidReferenceNumber(_ number: String) -> Bool {
        CanonicalHadithLink.parse(collectionSlug: "bukhari", providerHadithId: number) != nil
    }

    /// Formats copied text: the visible Arabic when shown, the visible
    /// translation when shown, then a source line. The URL is never part of
    /// copied text; the AI suffix appears only when the copied translation
    /// itself is AI-generated.
    static func copyText(
        for hadith: ReaderHadith,
        arabicVisible: Bool,
        translationVisible: Bool,
        translationText: String?,
        translationIsAI: Bool
    ) -> String {
        var parts: [String] = []
        if arabicVisible {
            parts.append(hadith.arabicText)
        }
        if translationVisible,
           let translation = translationText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !translation.isEmpty {
            parts.append(translation)
        }
        var sourceLine = "— \(hadith.collectionName) · Hadith \(hadith.providerHadithId) · \(hadith.authenticity.sourceName)"
        let translationIncluded = translationVisible
            && !(translationText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        if translationIncluded && translationIsAI {
            sourceLine += " · AI translation"
        }
        if parts.isEmpty { return sourceLine }
        return parts.joined(separator: "\n\n") + "\n\n" + sourceLine
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
