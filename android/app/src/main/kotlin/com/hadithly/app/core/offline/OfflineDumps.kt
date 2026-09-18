package com.hadithly.app.core.offline

import kotlinx.serialization.Serializable
import java.security.MessageDigest

/**
 * O1 offline dump decoders. Mirrors `backend/convex/lib/offlineDumps.ts`
 * and `ios/Hadithly/Core/Offline/OfflineDump.swift`.
 * Decode + fixture validation only; O2 owns download, activation, and UI.
 */
class OfflineDumpException(val code: String, message: String) : IllegalArgumentException(message)

@Serializable
data class OfflineLicenseTerms(
    val kind: String,
    val licenseName: String? = null,
    val licenseUrl: String? = null,
    val permitsDisplay: Boolean? = null,
    val permitsRedistribution: Boolean? = null,
    val permitsOfflineDistribution: Boolean? = null,
    val verifiedAt: Double? = null,
)

@Serializable
data class OfflineLicenseRecord(
    val sourceKey: String,
    val sourceName: String,
    val sourceUrl: String,
    val terms: OfflineLicenseTerms,
) {
    val permitsOfflineUse: Boolean
        get() = terms.kind == "verified" &&
            terms.permitsDisplay == true &&
            terms.permitsOfflineDistribution == true
}

@Serializable
data class OfflineAuthenticity(
    val kind: String,
    val normalizedGrade: String? = null,
    val claimScope: String,
    val sourceLabel: String,
    val sourceName: String,
    val sourceUrl: String,
    val verificationMethod: String,
)

@Serializable
data class OfflineDumpHadith(
    val canonicalId: String,
    val provider: String,
    val collectionSlug: String,
    val providerHadithId: String,
    val volumeId: String? = null,
    val chapterId: String? = null,
    val arabicText: String,
    val englishText: String? = null,
    val narrator: String? = null,
    val narratorAr: String? = null,
    val referenceDisplay: String,
    val collectionName: String,
    val bookName: String? = null,
    val chapterName: String? = null,
    val authenticity: OfflineAuthenticity,
)

@Serializable
data class OfflineBaseDump(
    val format: String,
    val schemaVersion: Double,
    val collectionSlug: String,
    val collectionName: String,
    val contentVersion: String,
    val generatedAt: Double,
    val license: OfflineLicenseRecord,
    val hadiths: List<OfflineDumpHadith>,
)

@Serializable
data class OfflinePackEntry(
    val canonicalId: String,
    val language: String,
    val content: String,
    val source: String,
    val sourceLabel: String,
)

@Serializable
data class OfflineTranslationPack(
    val format: String,
    val schemaVersion: Double,
    val collectionSlug: String,
    val language: String,
    val baseContentVersion: String,
    val contentVersion: String,
    val generatedAt: Double,
    val license: OfflineLicenseRecord,
    val entries: List<OfflinePackEntry>,
)

@Serializable
data class OfflineManifest(
    val format: String,
    val schemaVersion: Double,
    val kind: String,
    val collectionSlug: String,
    val locale: String? = null,
    val contentVersion: String,
    val baseContentVersion: String? = null,
    val byteSize: Double,
    val sha256: String,
    val minAppVersion: String,
    val generatedAt: Double,
    val license: OfflineLicenseRecord,
    val compatiblePacks: List<String>,
    val downloadUrl: String? = null,
)

object OfflineDumps {
    const val SCHEMA_VERSION = 1.0
    const val BASE_FORMAT = "hadithly-base-dump"
    const val PACK_FORMAT = "hadithly-translation-pack"
    const val MANIFEST_FORMAT = "hadithly-offline-manifest"

    private val collectionSlug = Regex("[a-z][a-z0-9-]{1,31}")
    // Mirrors the backend dump pattern, deliberately wider than the F3 link
    // pattern: Sunnah.now serves real content (e.g. Muslim's Muqaddimah)
    // under id "0", and R1 positions already accept the same shape.
    private val providerHadithId = Regex("[0-9]{1,12}(\\.[0-9]{1,12})*")
    private val sha256Hex = Regex("[0-9a-f]{64}")
    private val contentVersion = Regex("od1:[0-9a-f]{64}")
    private val validGrades = setOf("sahih", "hasan", "daif", "mawdu", "mixed", "unknown")
    private val validProviders = setOf("sunnah_now", "sunnah_com", "local_dump")

    fun sha256Hex(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        return digest.joinToString("") { "%02x".format(it) }
    }

    fun validateBaseDump(dump: OfflineBaseDump) {
        if (dump.format != BASE_FORMAT) throw OfflineDumpException("bad_reference", "base dump format")
        if (dump.schemaVersion != SCHEMA_VERSION) throw OfflineDumpException("bad_reference", "base dump schema")
        if (!collectionSlug.matches(dump.collectionSlug)) throw OfflineDumpException("bad_reference", "slug")
        if (!contentVersion.matches(dump.contentVersion)) throw OfflineDumpException("bad_reference", "content version")
        for (hadith in dump.hadiths) {
            if (hadith.provider !in validProviders ||
                !collectionSlug.matches(hadith.collectionSlug) ||
                !providerHadithId.matches(hadith.providerHadithId) ||
                hadith.canonicalId != "${hadith.provider}:${hadith.collectionSlug}:${hadith.providerHadithId}" ||
                hadith.arabicText.isEmpty() ||
                hadith.collectionSlug != dump.collectionSlug
            ) {
                throw OfflineDumpException("bad_reference", "drifted identity for ${hadith.providerHadithId}")
            }
            val grade = if (hadith.authenticity.kind == "unverified") "unknown" else hadith.authenticity.normalizedGrade
            if (grade !in validGrades) throw OfflineDumpException("bad_reference", "unknown grade")
        }
    }

    fun validatePack(pack: OfflineTranslationPack) {
        if (pack.format != PACK_FORMAT) throw OfflineDumpException("bad_reference", "pack format")
        if (pack.schemaVersion != SCHEMA_VERSION) throw OfflineDumpException("bad_reference", "pack schema")
        if (!collectionSlug.matches(pack.collectionSlug)) throw OfflineDumpException("bad_reference", "slug")
        if (!contentVersion.matches(pack.baseContentVersion)) throw OfflineDumpException("bad_reference", "pack base version")
        if (!contentVersion.matches(pack.contentVersion)) throw OfflineDumpException("bad_reference", "pack version")
        if (pack.language.isEmpty() || pack.entries.isEmpty()) throw OfflineDumpException("bad_reference", "pack contents")
        val ids = pack.entries.map { it.canonicalId }
        if (ids.toSet().size != ids.size) throw OfflineDumpException("duplicate_provider_id", "duplicate pack entry")
        for (entry in pack.entries) {
            if (!entry.canonicalId.startsWith("sunnah_now:${pack.collectionSlug}:") || entry.content.isEmpty()) {
                throw OfflineDumpException("bad_reference", "pack entry ${entry.canonicalId}")
            }
        }
    }

    fun validateManifest(manifest: OfflineManifest) {
        if (manifest.format != MANIFEST_FORMAT) throw OfflineDumpException("bad_reference", "manifest format")
        if (manifest.kind != "base" && manifest.kind != "pack") throw OfflineDumpException("bad_reference", "manifest kind")
        if (manifest.schemaVersion != SCHEMA_VERSION) {
            throw OfflineDumpException("unsupported_schema", "schema ${manifest.schemaVersion}")
        }
        if (!collectionSlug.matches(manifest.collectionSlug)) throw OfflineDumpException("bad_reference", "slug")
        if (!contentVersion.matches(manifest.contentVersion)) throw OfflineDumpException("bad_reference", "content version")
        if (!sha256Hex.matches(manifest.sha256)) throw OfflineDumpException("bad_reference", "sha256")
        if (manifest.byteSize <= 0) throw OfflineDumpException("bad_reference", "byte size")
        if (manifest.kind == "pack" &&
            (manifest.baseContentVersion == null || !contentVersion.matches(manifest.baseContentVersion))
        ) {
            throw OfflineDumpException("incompatible_pack", "pack manifest without a base content version")
        }
    }

    /**
     * Activation gate: schema, license, checksum, then pack compatibility.
     * Throws so callers cannot ignore the reason. O2 calls this pre-activation.
     */
    fun assertValidForBytes(
        manifest: OfflineManifest,
        bytes: ByteArray,
        expectedBaseContentVersion: String? = null,
    ) {
        validateManifest(manifest)
        if (manifest.license.sourceKey.isEmpty()) {
            throw OfflineDumpException("missing_license", manifest.collectionSlug)
        }
        if (!manifest.license.permitsOfflineUse) {
            if (manifest.license.terms.kind != "verified") {
                throw OfflineDumpException("missing_license", manifest.license.sourceKey)
            }
            throw OfflineDumpException("unlicensed_source", manifest.license.sourceKey)
        }
        if (bytes.size.toLong() != manifest.byteSize.toLong()) {
            throw OfflineDumpException("checksum_mismatch", "byte size for ${manifest.collectionSlug}")
        }
        if (sha256Hex(bytes) != manifest.sha256) {
            throw OfflineDumpException("checksum_mismatch", "SHA-256 for ${manifest.collectionSlug}")
        }
        if (manifest.kind == "pack" && expectedBaseContentVersion != null &&
            manifest.baseContentVersion != expectedBaseContentVersion
        ) {
            throw OfflineDumpException(
                "incompatible_pack",
                "pack targets ${manifest.baseContentVersion}, base is $expectedBaseContentVersion",
            )
        }
    }
}
