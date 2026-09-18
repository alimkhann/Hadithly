import CryptoKit
import Foundation

/// O1 offline dump decoders. Mirrors `backend/convex/lib/offlineDumps.ts`.
/// Decode + fixture validation only; O2 owns download, activation, and UI.
enum OfflineDumpValidation {
    static let schemaVersion = 1.0
    static let baseFormat = "hadithly-base-dump"
    static let packFormat = "hadithly-translation-pack"
    static let manifestFormat = "hadithly-offline-manifest"

    static func validCollectionSlug(_ slug: String) -> Bool {
        slug.wholeMatch(of: /^[a-z][a-z0-9-]{1,31}$/) != nil
    }

    /// Mirrors the backend dump pattern, deliberately wider than the F3 link
    /// pattern: Sunnah.now serves real content (e.g. Muslim's Muqaddimah)
    /// under id "0", and R1 positions already accept the same shape.
    static func validProviderHadithId(_ id: String) -> Bool {
        id.wholeMatch(of: /^[0-9]{1,12}(\.[0-9]{1,12})*$/) != nil
    }

    static func validSHA256(_ hex: String) -> Bool {
        hex.wholeMatch(of: /^[0-9a-f]{64}$/) != nil
    }

    static func validContentVersion(_ version: String) -> Bool {
        version.wholeMatch(of: /^od1:[0-9a-f]{64}$/) != nil
    }

    static func sha256Hex(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

enum OfflineDumpError: Error, Equatable {
    case missingLicense(String)
    case unlicensedSource(String)
    case unsupportedSchema(Double)
    case checksumMismatch(String)
    case incompatiblePack(String)
    case badReference(String)
}

struct OfflineLicenseTerms: Codable, Equatable, Sendable {
    let kind: String
    let licenseName: String?
    let licenseUrl: String?
    let permitsDisplay: Bool?
    let permitsRedistribution: Bool?
    let permitsOfflineDistribution: Bool?
    let verifiedAt: Double?
}

struct OfflineLicenseRecord: Codable, Equatable, Sendable {
    let sourceKey: String
    let sourceName: String
    let sourceUrl: String
    let terms: OfflineLicenseTerms

    var permitsOfflineUse: Bool {
        terms.kind == "verified"
            && terms.permitsDisplay == true
            && terms.permitsOfflineDistribution == true
    }
}

struct OfflineAuthenticity: Codable, Equatable, Sendable {
    let kind: String
    let normalizedGrade: String?
    let claimScope: String
    let sourceLabel: String
    let sourceName: String
    let sourceUrl: String
    let verificationMethod: String
}

struct OfflineDumpHadith: Codable, Equatable, Sendable {
    private static let validGrades = ["sahih", "hasan", "daif", "mawdu", "mixed", "unknown"]

    let canonicalId: String
    let provider: String
    let collectionSlug: String
    let providerHadithId: String
    let volumeId: String?
    let chapterId: String?
    let arabicText: String
    let englishText: String?
    let narrator: String?
    let narratorAr: String?
    let referenceDisplay: String
    let collectionName: String
    let bookName: String?
    let chapterName: String?
    let authenticity: OfflineAuthenticity

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        canonicalId = try container.decode(String.self, forKey: .canonicalId)
        provider = try container.decode(String.self, forKey: .provider)
        collectionSlug = try container.decode(String.self, forKey: .collectionSlug)
        providerHadithId = try container.decode(String.self, forKey: .providerHadithId)
        volumeId = try container.decodeIfPresent(String.self, forKey: .volumeId)
        chapterId = try container.decodeIfPresent(String.self, forKey: .chapterId)
        arabicText = try container.decode(String.self, forKey: .arabicText)
        englishText = try container.decodeIfPresent(String.self, forKey: .englishText)
        narrator = try container.decodeIfPresent(String.self, forKey: .narrator)
        narratorAr = try container.decodeIfPresent(String.self, forKey: .narratorAr)
        referenceDisplay = try container.decode(String.self, forKey: .referenceDisplay)
        collectionName = try container.decode(String.self, forKey: .collectionName)
        bookName = try container.decodeIfPresent(String.self, forKey: .bookName)
        chapterName = try container.decodeIfPresent(String.self, forKey: .chapterName)
        authenticity = try container.decode(OfflineAuthenticity.self, forKey: .authenticity)
        guard ["sunnah_now", "sunnah_com", "local_dump"].contains(provider),
              OfflineDumpValidation.validCollectionSlug(collectionSlug),
              OfflineDumpValidation.validProviderHadithId(providerHadithId),
              canonicalId == "\(provider):\(collectionSlug):\(providerHadithId)",
              !arabicText.isEmpty
        else {
            throw OfflineDumpError.badReference("drifted identity for \(providerHadithId)")
        }
        let grade = authenticity.kind == "unverified" ? "unknown" : (authenticity.normalizedGrade ?? "")
        guard Self.validGrades.contains(grade) else {
            throw OfflineDumpError.badReference("unknown grade for \(providerHadithId)")
        }
    }
}

struct OfflineBaseDump: Codable, Equatable, Sendable {
    let format: String
    let schemaVersion: Double
    let collectionSlug: String
    let collectionName: String
    let contentVersion: String
    let generatedAt: Double
    let license: OfflineLicenseRecord
    let hadiths: [OfflineDumpHadith]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        schemaVersion = try container.decode(Double.self, forKey: .schemaVersion)
        collectionSlug = try container.decode(String.self, forKey: .collectionSlug)
        collectionName = try container.decode(String.self, forKey: .collectionName)
        contentVersion = try container.decode(String.self, forKey: .contentVersion)
        generatedAt = try container.decode(Double.self, forKey: .generatedAt)
        license = try container.decode(OfflineLicenseRecord.self, forKey: .license)
        hadiths = try container.decode([OfflineDumpHadith].self, forKey: .hadiths)
        guard format == OfflineDumpValidation.baseFormat,
              schemaVersion == OfflineDumpValidation.schemaVersion,
              OfflineDumpValidation.validCollectionSlug(collectionSlug),
              OfflineDumpValidation.validContentVersion(contentVersion),
              hadiths.allSatisfy({ $0.collectionSlug == collectionSlug })
        else {
            throw OfflineDumpError.badReference("base dump envelope for \(collectionSlug)")
        }
    }
}

struct OfflinePackEntry: Codable, Equatable, Sendable {
    let canonicalId: String
    let language: String
    let content: String
    let source: String
    let sourceLabel: String
}

struct OfflineTranslationPack: Codable, Equatable, Sendable {
    let format: String
    let schemaVersion: Double
    let collectionSlug: String
    let language: String
    let baseContentVersion: String
    let contentVersion: String
    let generatedAt: Double
    let license: OfflineLicenseRecord
    let entries: [OfflinePackEntry]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        schemaVersion = try container.decode(Double.self, forKey: .schemaVersion)
        collectionSlug = try container.decode(String.self, forKey: .collectionSlug)
        language = try container.decode(String.self, forKey: .language)
        baseContentVersion = try container.decode(String.self, forKey: .baseContentVersion)
        contentVersion = try container.decode(String.self, forKey: .contentVersion)
        generatedAt = try container.decode(Double.self, forKey: .generatedAt)
        license = try container.decode(OfflineLicenseRecord.self, forKey: .license)
        entries = try container.decode([OfflinePackEntry].self, forKey: .entries)
        let ids = entries.map(\.canonicalId)
        guard format == OfflineDumpValidation.packFormat,
              schemaVersion == OfflineDumpValidation.schemaVersion,
              OfflineDumpValidation.validCollectionSlug(collectionSlug),
              OfflineDumpValidation.validContentVersion(baseContentVersion),
              OfflineDumpValidation.validContentVersion(contentVersion),
              !language.isEmpty,
              !entries.isEmpty,
              Set(ids).count == ids.count,
              entries.allSatisfy({
                $0.canonicalId.hasPrefix("sunnah_now:\(collectionSlug):") && !$0.content.isEmpty
              })
        else {
            throw OfflineDumpError.badReference("translation pack envelope for \(collectionSlug)")
        }
    }
}

struct OfflineManifest: Codable, Equatable, Sendable {
    let format: String
    let schemaVersion: Double
    let kind: String
    let collectionSlug: String
    let locale: String?
    let contentVersion: String
    let baseContentVersion: String?
    let byteSize: Double
    let sha256: String
    let minAppVersion: String
    let generatedAt: Double
    let license: OfflineLicenseRecord
    let compatiblePacks: [String]
    let downloadUrl: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        schemaVersion = try container.decode(Double.self, forKey: .schemaVersion)
        kind = try container.decode(String.self, forKey: .kind)
        collectionSlug = try container.decode(String.self, forKey: .collectionSlug)
        locale = try container.decodeIfPresent(String.self, forKey: .locale)
        contentVersion = try container.decode(String.self, forKey: .contentVersion)
        baseContentVersion = try container.decodeIfPresent(String.self, forKey: .baseContentVersion)
        byteSize = try container.decode(Double.self, forKey: .byteSize)
        sha256 = try container.decode(String.self, forKey: .sha256)
        minAppVersion = try container.decode(String.self, forKey: .minAppVersion)
        generatedAt = try container.decode(Double.self, forKey: .generatedAt)
        license = try container.decode(OfflineLicenseRecord.self, forKey: .license)
        compatiblePacks = try container.decode([String].self, forKey: .compatiblePacks)
        downloadUrl = try container.decodeIfPresent(String.self, forKey: .downloadUrl)
        guard format == OfflineDumpValidation.manifestFormat,
              schemaVersion == OfflineDumpValidation.schemaVersion,
              kind == "base" || kind == "pack",
              OfflineDumpValidation.validCollectionSlug(collectionSlug),
              OfflineDumpValidation.validContentVersion(contentVersion),
              OfflineDumpValidation.validSHA256(sha256),
              byteSize > 0
        else {
            throw OfflineDumpError.badReference("manifest envelope for \(collectionSlug)")
        }
        if kind == "pack" {
            guard let base = baseContentVersion,
                  OfflineDumpValidation.validContentVersion(base)
            else {
                throw OfflineDumpError.incompatiblePack("pack manifest without a base content version")
            }
        }
    }

    /// Activation gate: schema, license, checksum, then pack compatibility.
    /// Throws so callers cannot ignore the reason. O2 calls this pre-activation.
    func assertValid(for bytes: Data, expectedBaseContentVersion: String? = nil) throws {
        guard schemaVersion == OfflineDumpValidation.schemaVersion else {
            throw OfflineDumpError.unsupportedSchema(schemaVersion)
        }
        guard license.sourceKey.count > 0 else {
            throw OfflineDumpError.missingLicense(collectionSlug)
        }
        guard license.permitsOfflineUse else {
            if license.terms.kind != "verified" {
                throw OfflineDumpError.missingLicense(license.sourceKey)
            }
            throw OfflineDumpError.unlicensedSource(license.sourceKey)
        }
        guard Int64(bytes.count) == Int64(byteSize) else {
            throw OfflineDumpError.checksumMismatch("byte size for \(collectionSlug)")
        }
        guard OfflineDumpValidation.sha256Hex(bytes) == sha256 else {
            throw OfflineDumpError.checksumMismatch("SHA-256 for \(collectionSlug)")
        }
        if kind == "pack", let expected = expectedBaseContentVersion {
            guard baseContentVersion == expected else {
                throw OfflineDumpError.incompatiblePack(
                    "pack targets \(baseContentVersion ?? "none"), base is \(expected)"
                )
            }
        }
    }
}
