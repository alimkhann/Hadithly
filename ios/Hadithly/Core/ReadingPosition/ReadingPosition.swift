import CryptoKit
import Foundation

struct ReadingPositionAnchor: Codable, Equatable, Sendable {
    let provider: String
    let collectionSlug: String
    let providerHadithId: String
}

struct ReadingPosition: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1.0

    let schemaVersion: Double
    let anchor: ReadingPositionAnchor
    let contentVersion: String
    let volumeId: String
    let chapterId: String?
    let pageKey: String
    let displayPageIndex: Double
    let rawPageOffset: Double
    let normalizedOffset: Double
    let layoutSignature: String
    let updatedAt: Double

    init(
        anchor: ReadingPositionAnchor,
        contentVersion: String,
        volumeId: String,
        chapterId: String? = nil,
        pageKey: String,
        displayPageIndex: Double,
        rawPageOffset: Double,
        normalizedOffset: Double,
        layoutSignature: String,
        updatedAt: Double
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.anchor = anchor
        self.contentVersion = contentVersion
        self.volumeId = volumeId
        self.chapterId = chapterId
        self.pageKey = pageKey
        self.displayPageIndex = displayPageIndex
        self.rawPageOffset = rawPageOffset
        self.normalizedOffset = normalizedOffset
        self.layoutSignature = layoutSignature
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Double.self, forKey: .schemaVersion)
        anchor = try container.decode(ReadingPositionAnchor.self, forKey: .anchor)
        contentVersion = try container.decode(String.self, forKey: .contentVersion)
        volumeId = try container.decode(String.self, forKey: .volumeId)
        chapterId = try container.decodeIfPresent(String.self, forKey: .chapterId)
        pageKey = try container.decode(String.self, forKey: .pageKey)
        displayPageIndex = try container.decode(Double.self, forKey: .displayPageIndex)
        rawPageOffset = try container.decode(Double.self, forKey: .rawPageOffset)
        normalizedOffset = try container.decode(Double.self, forKey: .normalizedOffset)
        layoutSignature = try container.decode(String.self, forKey: .layoutSignature)
        updatedAt = try container.decode(Double.self, forKey: .updatedAt)
        guard schemaVersion == Self.currentSchemaVersion,
              ["sunnah_now", "sunnah_com", "local_dump"].contains(anchor.provider),
              ReadingPositionValidation.validCollectionSlug(anchor.collectionSlug),
              ReadingPositionValidation.validProviderHadithId(anchor.providerHadithId),
              ReadingPositionValidation.validContentVersion(contentVersion),
              ReadingPositionValidation.validContextId(volumeId),
              chapterId.map(ReadingPositionValidation.validContextId) ?? true,
              ReadingPositionValidation.validPageKey(pageKey),
              displayPageIndex.isFinite,
              displayPageIndex >= 1,
              displayPageIndex.rounded() == displayPageIndex,
              rawPageOffset.isFinite,
              rawPageOffset >= 0,
              normalizedOffset.isFinite,
              (0...1).contains(normalizedOffset),
              ReadingPositionValidation.validLayoutSignature(layoutSignature),
              updatedAt.isFinite,
              updatedAt >= 0 else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid ReadingPosition V1")
            )
        }
    }

    static func legacy(
        provider: String = "sunnah_now",
        collectionSlug: String,
        providerHadithId: String,
        volumeId: String,
        chapterId: String? = nil,
        updatedAt: Double
    ) -> ReadingPosition? {
        guard ReadingPositionValidation.validCollectionSlug(collectionSlug),
              ReadingPositionValidation.validProviderHadithId(providerHadithId),
              !volumeId.isEmpty else { return nil }
        return ReadingPosition(
            anchor: .init(
                provider: provider,
                collectionSlug: collectionSlug,
                providerHadithId: providerHadithId
            ),
            contentVersion: "legacy",
            volumeId: volumeId,
            chapterId: chapterId,
            pageKey: "legacy",
            displayPageIndex: 1,
            rawPageOffset: 0,
            normalizedOffset: 0,
            layoutSignature: "legacy",
            updatedAt: updatedAt
        )
    }
}

private enum ReadingPositionValidation {
    static func validCollectionSlug(_ value: String) -> Bool {
        value.range(of: "^[a-z][a-z0-9-]{1,31}$", options: .regularExpression) != nil
    }

    static func validProviderHadithId(_ value: String) -> Bool {
        value.range(of: "^[0-9]{1,12}(\\.[0-9]{1,12})*$", options: .regularExpression) != nil
    }

    static func validContentVersion(_ value: String) -> Bool {
        value.range(of: "^(cv1:[A-Za-z0-9._:-]{1,128}|legacy)$", options: .regularExpression) != nil
    }

    static func validPageKey(_ value: String) -> Bool {
        value.range(of: "^(pg1:[A-Za-z0-9._:-]{1,160}|legacy)$", options: .regularExpression) != nil
    }

    static func validLayoutSignature(_ value: String) -> Bool {
        value.range(of: "^(ls1:[A-Za-z0-9._:-]{1,160}|legacy)$", options: .regularExpression) != nil
    }

    static func validContextId(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9._:-]{1,128}$", options: .regularExpression) != nil
    }
}

enum ReadingWidthClass: String, Codable, Sendable {
    case compact
    case regular
}

struct ReadingLayout: Equatable, Sendable {
    let locale: String
    let arabicVisible: Bool
    let translationVisible: Bool
    let arabicFontId: String
    let arabicFontSize: Double
    let widthClass: ReadingWidthClass
    let paginationVersion: Double

    var signature: String {
        let sizeMilliPoints = Int((arabicFontSize * 1_000).rounded())
        let pagination = Int(paginationVersion)
        let canonical = [
            "v1",
            "locale=\(locale)",
            "arabic=\(arabicVisible ? 1 : 0)",
            "translation=\(translationVisible ? 1 : 0)",
            "font=\(arabicFontId)",
            "size=\(sizeMilliPoints)",
            "width=\(widthClass.rawValue)",
            "pagination=\(pagination)",
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return "ls1:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    func withPaginationVersion(_ version: Double) -> ReadingLayout {
        ReadingLayout(
            locale: locale,
            arabicVisible: arabicVisible,
            translationVisible: translationVisible,
            arabicFontId: arabicFontId,
            arabicFontSize: arabicFontSize,
            widthClass: widthClass,
            paginationVersion: version
        )
    }
}

struct ReadingPositionAnchorLocation: Equatable, Sendable {
    let anchor: ReadingPositionAnchor
    let volumeId: String
    let chapterId: String?
}

struct ReadingPositionPage: Equatable, Sendable {
    let pageKey: String
    let displayPageIndex: Double
    let anchors: [ReadingPositionAnchorLocation]
}

struct ReadingPositionTopology: Equatable, Sendable {
    let contentVersion: String
    let layoutSignature: String
    let pages: [ReadingPositionPage]
}

struct ResolvedReadingPosition: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case raw
        case semantic
        case nearest
        case unavailable
    }

    let kind: Kind
    let anchor: ReadingPositionAnchor?
    let volumeId: String?
    let chapterId: String?
    let pageKey: String?
    let displayPageIndex: Double
    let rawPageOffset: Double
    let normalizedOffset: Double
}

enum ReadingPositionResolver {
    private struct LocatedAnchor {
        let location: ReadingPositionAnchorLocation
        let pageKey: String
        let displayPageIndex: Double
        let itemIndex: Int
    }

    static func resolve(
        _ position: ReadingPosition,
        topology: ReadingPositionTopology
    ) -> ResolvedReadingPosition {
        let all = topology.pages.flatMap { page in
            page.anchors.enumerated().map { itemIndex, anchor in
                LocatedAnchor(
                    location: anchor,
                    pageKey: page.pageKey,
                    displayPageIndex: page.displayPageIndex,
                    itemIndex: itemIndex
                )
            }
        }
        let candidates = all.filter {
            $0.location.anchor.provider == position.anchor.provider
                && $0.location.anchor.collectionSlug == position.anchor.collectionSlug
        }
        if let exact = candidates.first(where: { $0.location.anchor == position.anchor }) {
            let rawMatches = topology.contentVersion == position.contentVersion
                && topology.layoutSignature == position.layoutSignature
                && exact.pageKey == position.pageKey
                && exact.displayPageIndex == position.displayPageIndex
            return result(
                kind: rawMatches ? .raw : .semantic,
                location: exact,
                rawPageOffset: rawMatches ? position.rawPageOffset : 0,
                normalizedOffset: position.normalizedOffset
            )
        }
        guard !candidates.isEmpty else {
            return ResolvedReadingPosition(
                kind: .unavailable,
                anchor: nil,
                volumeId: nil,
                chapterId: nil,
                pageKey: nil,
                displayPageIndex: 1,
                rawPageOffset: 0,
                normalizedOffset: 0
            )
        }
        var preferred = candidates
        let sameVolume = preferred.filter { $0.location.volumeId == position.volumeId }
        if !sameVolume.isEmpty { preferred = sameVolume }
        if let chapterId = position.chapterId {
            let sameChapter = preferred.filter { $0.location.chapterId == chapterId }
            if !sameChapter.isEmpty { preferred = sameChapter }
        }
        guard let nearest = preferred.sorted(by: {
            compareDistance(target: position.anchor.providerHadithId, left: $0, right: $1) < 0
        }).first else {
            return ResolvedReadingPosition(
                kind: .unavailable,
                anchor: nil,
                volumeId: nil,
                chapterId: nil,
                pageKey: nil,
                displayPageIndex: 1,
                rawPageOffset: 0,
                normalizedOffset: 0
            )
        }
        return result(kind: .nearest, location: nearest, rawPageOffset: 0, normalizedOffset: 0)
    }

    private static func result(
        kind: ResolvedReadingPosition.Kind,
        location: LocatedAnchor,
        rawPageOffset: Double,
        normalizedOffset: Double
    ) -> ResolvedReadingPosition {
        ResolvedReadingPosition(
            kind: kind,
            anchor: location.location.anchor,
            volumeId: location.location.volumeId,
            chapterId: location.location.chapterId,
            pageKey: location.pageKey,
            displayPageIndex: location.displayPageIndex,
            rawPageOffset: rawPageOffset,
            normalizedOffset: normalizedOffset
        )
    }

    private static func compareDistance(
        target: String,
        left: LocatedAnchor,
        right: LocatedAnchor
    ) -> Int {
        guard let targetSegments = segments(target) else {
            return compareLocated(left, right)
        }
        let leftSegments = segments(left.location.anchor.providerHadithId)
        let rightSegments = segments(right.location.anchor.providerHadithId)
        if leftSegments == nil || rightSegments == nil {
            if leftSegments != nil { return -1 }
            if rightSegments != nil { return 1 }
            return compareLocated(left, right)
        }
        guard let leftSegments, let rightSegments else {
            return compareLocated(left, right)
        }
        let width = max(targetSegments.count, max(leftSegments.count, rightSegments.count))
        for index in 0..<width {
            let targetPart = index < targetSegments.count ? targetSegments[index] : 0
            let leftPart = index < leftSegments.count ? leftSegments[index] : 0
            let rightPart = index < rightSegments.count ? rightSegments[index] : 0
            let leftDistance = abs(leftPart - targetPart)
            let rightDistance = abs(rightPart - targetPart)
            if leftDistance != rightDistance { return leftDistance < rightDistance ? -1 : 1 }
        }
        let providerOrder = compareSegments(leftSegments, rightSegments)
        if providerOrder != 0 { return providerOrder }
        return compareLocated(left, right)
    }

    private static func compareLocated(_ left: LocatedAnchor, _ right: LocatedAnchor) -> Int {
        let leftId = left.location.anchor.providerHadithId
        let rightId = right.location.anchor.providerHadithId
        if leftId != rightId { return leftId < rightId ? -1 : 1 }
        if left.displayPageIndex != right.displayPageIndex {
            return left.displayPageIndex < right.displayPageIndex ? -1 : 1
        }
        return left.itemIndex - right.itemIndex
    }

    private static func segments(_ value: String) -> [Int64]? {
        let result = value.split(separator: ".").map { Int64($0) }
        guard result.allSatisfy({ $0 != nil }) else { return nil }
        return result.compactMap { $0 }
    }

    private static func compareSegments(_ left: [Int64], _ right: [Int64]) -> Int {
        let width = max(left.count, right.count)
        for index in 0..<width {
            let difference = (index < left.count ? left[index] : 0) - (index < right.count ? right[index] : 0)
            if difference != 0 { return difference < 0 ? -1 : 1 }
        }
        return left.count - right.count
    }
}
