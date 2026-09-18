import XCTest
@testable import Hadithly

/// O1 gate: native manifest/dump decoders plus fixture validation.
/// Mirrors `backend/convex/offlineDumps.test.ts` and the Android
/// `OfflineDumpsTest`. O2 owns download UI; this file proves corrupt,
/// incompatible, and unlicensed fixtures fail before anything activates.
final class OfflineDumpsTests: XCTestCase {
    private static let license = """
        {"sourceKey":"sunnah_now","sourceName":"Sunnah.now","sourceUrl":"https://sunnah.now", \
        "terms":{"kind":"verified","licenseName":"Sunnah.now early-access data grant", \
        "licenseUrl":"https://github.com/sunnah-now/database","permitsDisplay":true, \
        "permitsRedistribution":false,"permitsOfflineDistribution":true,"verifiedAt":1700000000000}}
        """

    private static let hadith7 = """
        {"canonicalId":"sunnah_now:bukhari:7","provider":"sunnah_now","collectionSlug":"bukhari", \
        "providerHadithId":"7","volumeId":"2","chapterId":"42","arabicText":"نص الحديث", \
        "englishText":"Hadith text","narrator":"Narrated Aisha", \
        "referenceDisplay":"Sahih al-Bukhari · Hadith 7","collectionName":"Sahih al-Bukhari", \
        "chapterName":"Chapter of faith", \
        "authenticity":{"kind":"collection_scope","normalizedGrade":"sahih","claimScope":"collection", \
        "sourceLabel":"Documented Sahih collection","sourceName":"Sunnah.now", \
        "sourceUrl":"https://sunnah.now","verificationMethod":"manual_collection_mapping"}}
        """

    private static let hadith2 = """
        {"canonicalId":"sunnah_now:bukhari:2","provider":"sunnah_now","collectionSlug":"bukhari", \
        "providerHadithId":"2","volumeId":"2","chapterId":"42","arabicText":"ثان", \
        "referenceDisplay":"Sahih al-Bukhari · Hadith 2","collectionName":"Sahih al-Bukhari", \
        "authenticity":{"kind":"unverified","claimScope":"none","sourceLabel":"Authenticity not verified", \
        "sourceName":"Sunnah.now","sourceUrl":"https://sunnah.now","verificationMethod":"unavailable"}}
        """

    private static let baseDumpJSON = """
        {"format":"hadithly-base-dump","schemaVersion":1,"collectionSlug":"bukhari", \
        "collectionName":"Sahih al-Bukhari","contentVersion":"od1:\(String(repeating: "a", count: 64))", \
        "generatedAt":1700000000000,"license":\(license),"hadiths":[\(hadith2),\(hadith7)]}
        """

    private func manifestJSON(sha: String, byteSize: Int) -> String {
        """
        {"format":"hadithly-offline-manifest","schemaVersion":1,"kind":"base","collectionSlug":"bukhari", \
        "contentVersion":"od1:\(String(repeating: "a", count: 64))","byteSize":\(byteSize),"sha256":"\(sha)", \
        "minAppVersion":"0.1.0","generatedAt":1700000000000,"license":\(Self.license),"compatiblePacks":[]}
        """
    }

    private func decodeManifest(sha: String, byteSize: Int) throws -> OfflineManifest {
        try JSONDecoder().decode(
            OfflineManifest.self, from: Data(manifestJSON(sha: sha, byteSize: byteSize).utf8))
    }

    func testDecodesGoldenBaseDump() throws {
        let dump = try JSONDecoder().decode(
            OfflineBaseDump.self, from: Data(Self.baseDumpJSON.utf8))
        XCTAssertEqual(dump.hadiths.count, 2)
        XCTAssertEqual(dump.hadiths[0].canonicalId, "sunnah_now:bukhari:2")
        XCTAssertEqual(dump.hadiths[1].providerHadithId, "7")
        XCTAssertEqual(dump.license.sourceKey, "sunnah_now")
        XCTAssertTrue(dump.license.permitsOfflineUse)
    }

    func testAcceptsMatchingBytesAndHash() throws {
        let bytes = Data(Self.baseDumpJSON.utf8)
        let manifest = try decodeManifest(
            sha: OfflineDumpValidation.sha256Hex(bytes), byteSize: bytes.count)
        XCTAssertNoThrow(try manifest.assertValid(for: bytes))
    }

    func testRejectsCorruptBytes() throws {
        var bytes = Data(Self.baseDumpJSON.utf8)
        bytes[bytes.count - 10] ^= 0xFF
        let manifest = try decodeManifest(
            sha: OfflineDumpValidation.sha256Hex(Data(Self.baseDumpJSON.utf8)),
            byteSize: Data(Self.baseDumpJSON.utf8).count)
        XCTAssertThrowsError(try manifest.assertValid(for: bytes)) { error in
            XCTAssertEqual(error as? OfflineDumpError, .checksumMismatch("SHA-256 for bukhari"))
        }
    }

    func testRejectsTruncatedBytes() throws {
        let full = Data(Self.baseDumpJSON.utf8)
        let manifest = try decodeManifest(
            sha: OfflineDumpValidation.sha256Hex(full), byteSize: full.count)
        XCTAssertThrowsError(try manifest.assertValid(for: full.prefix(64))) { error in
            guard case .checksumMismatch = error as? OfflineDumpError else {
                return XCTFail("expected checksumMismatch, got \(error)")
            }
        }
    }

    func testRejectsUnsupportedSchema() {
        let json = manifestJSON(sha: String(repeating: "0", count: 64), byteSize: 1)
            .replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2")
        XCTAssertThrowsError(
            try JSONDecoder().decode(OfflineManifest.self, from: Data(json.utf8))
        )
    }

    func testRejectsUnlicensedManifest() throws {
        let unverified = Self.license.replacingOccurrences(
            of: "\"terms\":{\"kind\":\"verified\"",
            with: "\"terms\":{\"kind\":\"unverified\"")
        let json = manifestJSON(sha: String(repeating: "0", count: 64), byteSize: 1)
            .replacingOccurrences(of: Self.license, with: unverified)
        let manifest = try JSONDecoder().decode(OfflineManifest.self, from: Data(json.utf8))
        XCTAssertThrowsError(try manifest.assertValid(for: Data("x".utf8))) { error in
            XCTAssertEqual(error as? OfflineDumpError, .missingLicense("sunnah_now"))
        }
    }

    func testRejectsDriftedCanonicalId() {
        let drifted = Self.baseDumpJSON.replacingOccurrences(
            of: "\"canonicalId\":\"sunnah_now:bukhari:7\"",
            with: "\"canonicalId\":\"sunnah_now:bukhari:8\"")
        XCTAssertThrowsError(
            try JSONDecoder().decode(OfflineBaseDump.self, from: Data(drifted.utf8))
        )
    }

    func testRejectsIncompatiblePack() throws {
        let packJSON = """
            {"format":"hadithly-translation-pack","schemaVersion":1,"collectionSlug":"bukhari", \
            "language":"ur","baseContentVersion":"od1:\(String(repeating: "a", count: 64))", \
            "contentVersion":"od1:\(String(repeating: "b", count: 64))","generatedAt":1700000000000, \
            "license":\(Self.license), \
            "entries":[{"canonicalId":"sunnah_now:bukhari:7","language":"ur","content":"ترجمہ", \
            "source":"official","sourceLabel":"Official"}]}
            """
        let pack = try JSONDecoder().decode(OfflineTranslationPack.self, from: Data(packJSON.utf8))
        XCTAssertEqual(pack.entries.count, 1)

        let probe = Data("x".utf8)
        let packManifestJSON = """
            {"format":"hadithly-offline-manifest","schemaVersion":1,"kind":"pack", \
            "collectionSlug":"bukhari","locale":"ur", \
            "contentVersion":"od1:\(String(repeating: "b", count: 64))", \
            "baseContentVersion":"od1:\(String(repeating: "a", count: 64))", \
            "byteSize":\(probe.count),"sha256":"\(OfflineDumpValidation.sha256Hex(probe))", \
            "minAppVersion":"0.1.0", \
            "generatedAt":1700000000000,"license":\(Self.license),"compatiblePacks":[]}
            """
        let manifest = try JSONDecoder().decode(
            OfflineManifest.self, from: Data(packManifestJSON.utf8))
        XCTAssertThrowsError(
            try manifest.assertValid(
                for: probe,
                expectedBaseContentVersion: "od1:\(String(repeating: "9", count: 64))")
        ) { error in
            guard case .incompatiblePack = error as? OfflineDumpError else {
                return XCTFail("expected incompatiblePack, got \(error)")
            }
        }
    }

    func testAcceptsProviderIdZero() throws {
        // Sunnah.now serves real collection content (e.g. Muslim's
        // Muqaddimah) under id "0"; the dump must carry it, ordered first.
        XCTAssertTrue(OfflineDumpValidation.validProviderHadithId("0"))
        XCTAssertTrue(OfflineDumpValidation.validProviderHadithId("0.5"))
        XCTAssertFalse(OfflineDumpValidation.validProviderHadithId(""))
        XCTAssertFalse(OfflineDumpValidation.validProviderHadithId(".5"))
        let zero = Self.hadith7
            .replacingOccurrences(of: "\"sunnah_now:bukhari:7\"", with: "\"sunnah_now:bukhari:0\"")
            .replacingOccurrences(of: "\"providerHadithId\":\"7\"", with: "\"providerHadithId\":\"0\"")
        let row = try JSONDecoder().decode(OfflineDumpHadith.self, from: Data(zero.utf8))
        XCTAssertEqual(row.providerHadithId, "0")
        XCTAssertTrue(OfflineModels.compareProviderHadithIds("0", "1"))
        XCTAssertFalse(OfflineModels.compareProviderHadithIds("1", "0"))
    }

    func testRejectsDuplicatePackEntries() {
        let dup = """
            {"format":"hadithly-translation-pack","schemaVersion":1,"collectionSlug":"bukhari", \
            "language":"ur","baseContentVersion":"od1:\(String(repeating: "a", count: 64))", \
            "contentVersion":"od1:\(String(repeating: "b", count: 64))","generatedAt":1700000000000, \
            "license":\(Self.license), \
            "entries":[{"canonicalId":"sunnah_now:bukhari:7","language":"ur","content":"one", \
            "source":"official","sourceLabel":"Official"}, \
            {"canonicalId":"sunnah_now:bukhari:7","language":"ur","content":"two", \
            "source":"official","sourceLabel":"Official"}]}
            """
        XCTAssertThrowsError(
            try JSONDecoder().decode(OfflineTranslationPack.self, from: Data(dup.utf8)))
    }
}
