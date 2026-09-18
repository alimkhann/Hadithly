package com.hadithly.app

import com.hadithly.app.core.offline.OfflineBaseDump
import com.hadithly.app.core.offline.OfflineDumpException
import com.hadithly.app.core.offline.OfflineDumps
import com.hadithly.app.core.offline.OfflineManifest
import com.hadithly.app.core.offline.OfflineModels
import com.hadithly.app.core.offline.OfflineTranslationPack
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * O1 gate: native manifest/dump decoders plus fixture validation.
 * Mirrors `backend/convex/offlineDumps.test.ts` and iOS `OfflineDumpsTests`.
 * O2 owns download UI; this proves corrupt, incompatible, and unlicensed
 * fixtures fail before anything activates.
 */
class OfflineDumpsTest {

    private val json = Json { ignoreUnknownKeys = true }

    private fun license(verified: Boolean = true): String {
        val terms = if (verified) {
            """"terms":{"kind":"verified","licenseName":"Sunnah.now early-access data grant","licenseUrl":"https://github.com/sunnah-now/database","permitsDisplay":true,"permitsRedistribution":false,"permitsOfflineDistribution":true,"verifiedAt":1700000000000}"""
        } else {
            """"terms":{"kind":"unverified"}"""
        }
        return """{"sourceKey":"sunnah_now","sourceName":"Sunnah.now","sourceUrl":"https://sunnah.now",$terms}"""
    }

    private val hadith7 = """
        {"canonicalId":"sunnah_now:bukhari:7","provider":"sunnah_now","collectionSlug":"bukhari",
        "providerHadithId":"7","volumeId":"2","chapterId":"42","arabicText":"نص الحديث",
        "englishText":"Hadith text","narrator":"Narrated Aisha",
        "referenceDisplay":"Sahih al-Bukhari · Hadith 7","collectionName":"Sahih al-Bukhari",
        "chapterName":"Chapter of faith",
        "authenticity":{"kind":"collection_scope","normalizedGrade":"sahih","claimScope":"collection",
        "sourceLabel":"Documented Sahih collection","sourceName":"Sunnah.now",
        "sourceUrl":"https://sunnah.now","verificationMethod":"manual_collection_mapping"}}
    """.trimIndent()

    private val hadith2 = """
        {"canonicalId":"sunnah_now:bukhari:2","provider":"sunnah_now","collectionSlug":"bukhari",
        "providerHadithId":"2","volumeId":"2","chapterId":"42","arabicText":"ثان",
        "referenceDisplay":"Sahih al-Bukhari · Hadith 2","collectionName":"Sahih al-Bukhari",
        "authenticity":{"kind":"unverified","claimScope":"none","sourceLabel":"Authenticity not verified",
        "sourceName":"Sunnah.now","sourceUrl":"https://sunnah.now","verificationMethod":"unavailable"}}
    """.trimIndent()

    private val baseVersion = "od1:${"a".repeat(64)}"
    private val baseDumpJson = """
        {"format":"hadithly-base-dump","schemaVersion":1,"collectionSlug":"bukhari",
        "collectionName":"Sahih al-Bukhari","contentVersion":"$baseVersion",
        "generatedAt":1700000000000,"license":${license()},"hadiths":[$hadith2,$hadith7]}
    """.trimIndent()

    private fun manifestJson(sha: String, byteSize: Int, verified: Boolean = true): String {
        return """
        {"format":"hadithly-offline-manifest","schemaVersion":1,"kind":"base","collectionSlug":"bukhari",
        "contentVersion":"$baseVersion","byteSize":$byteSize,"sha256":"$sha",
        "minAppVersion":"0.1.0","generatedAt":1700000000000,"license":${license(verified)},"compatiblePacks":[]}
        """.trimIndent()
    }

    private fun expectCode(code: String, block: () -> Unit) {
        try {
            block()
        } catch (error: OfflineDumpException) {
            assertEquals(code, error.code)
            return
        }
        fail("expected OfflineDumpException $code")
    }

    @Test
    fun `decodes golden base dump`() {
        val dump = json.decodeFromString<OfflineBaseDump>(baseDumpJson)
        OfflineDumps.validateBaseDump(dump)
        assertEquals(2, dump.hadiths.size)
        assertEquals("sunnah_now:bukhari:2", dump.hadiths[0].canonicalId)
        assertEquals("7", dump.hadiths[1].providerHadithId)
        assertTrue(dump.license.permitsOfflineUse)
    }

    @Test
    fun `accepts matching bytes and hash`() {
        val bytes = baseDumpJson.toByteArray(Charsets.UTF_8)
        val manifest = json.decodeFromString<OfflineManifest>(
            manifestJson(OfflineDumps.sha256Hex(bytes), bytes.size),
        )
        OfflineDumps.assertValidForBytes(manifest, bytes)
    }

    @Test
    fun `rejects corrupt bytes`() {
        val bytes = baseDumpJson.toByteArray(Charsets.UTF_8)
        val manifest = json.decodeFromString<OfflineManifest>(
            manifestJson(OfflineDumps.sha256Hex(bytes), bytes.size),
        )
        val corrupt = bytes.copyOf().also { it[it.size - 10] = (it[it.size - 10].toInt() xor 0xFF).toByte() }
        expectCode("checksum_mismatch") { OfflineDumps.assertValidForBytes(manifest, corrupt) }
        expectCode("checksum_mismatch") { OfflineDumps.assertValidForBytes(manifest, bytes.copyOfRange(0, 64)) }
    }

    @Test
    fun `rejects unsupported schema`() {
        val payload = manifestJson("0".repeat(64), 1).replace("\"schemaVersion\":1", "\"schemaVersion\":2")
        val manifest = json.decodeFromString<OfflineManifest>(payload)
        expectCode("unsupported_schema") {
            OfflineDumps.assertValidForBytes(manifest, ByteArray(1))
        }
    }

    @Test
    fun `rejects unlicensed manifest`() {
        val bytes = "x".toByteArray(Charsets.UTF_8)
        val manifest = json.decodeFromString<OfflineManifest>(manifestJson("0".repeat(64), 1, verified = false))
        expectCode("missing_license") { OfflineDumps.assertValidForBytes(manifest, bytes) }
    }

    @Test
    fun `rejects drifted canonical id`() {
        val drifted = baseDumpJson.replace(
            "\"canonicalId\":\"sunnah_now:bukhari:7\"",
            "\"canonicalId\":\"sunnah_now:bukhari:8\"",
        )
        val dump = json.decodeFromString<OfflineBaseDump>(drifted)
        expectCode("bad_reference") { OfflineDumps.validateBaseDump(dump) }
    }

    @Test
    fun `rejects incompatible pack`() {
        val packVersion = "od1:${"b".repeat(64)}"
        val packJson = """
            {"format":"hadithly-translation-pack","schemaVersion":1,"collectionSlug":"bukhari",
            "language":"ur","baseContentVersion":"$baseVersion",
            "contentVersion":"$packVersion","generatedAt":1700000000000,
            "license":${license()},
            "entries":[{"canonicalId":"sunnah_now:bukhari:7","language":"ur","content":"ترجمہ",
            "source":"official","sourceLabel":"Official"}]}
        """.trimIndent()
        val pack = json.decodeFromString<OfflineTranslationPack>(packJson)
        OfflineDumps.validatePack(pack)
        assertEquals(1, pack.entries.size)

        val manifestJson = """
            {"format":"hadithly-offline-manifest","schemaVersion":1,"kind":"pack",
            "collectionSlug":"bukhari","locale":"ur",
            "contentVersion":"$packVersion",
            "baseContentVersion":"$baseVersion",
            "byteSize":1,"sha256":"${OfflineDumps.sha256Hex("x".toByteArray(Charsets.UTF_8))}","minAppVersion":"0.1.0",
            "generatedAt":1700000000000,"license":${license()},"compatiblePacks":[]}
        """.trimIndent()
        val manifest = json.decodeFromString<OfflineManifest>(manifestJson)
        val probe = "x".toByteArray(Charsets.UTF_8)
        expectCode("incompatible_pack") {
            OfflineDumps.assertValidForBytes(
                manifest,
                probe,
                expectedBaseContentVersion = "od1:${"9".repeat(64)}",
            )
        }
    }

    @Test
    fun `accepts provider id zero`() {
        // Sunnah.now serves real collection content (e.g. Muslim's
        // Muqaddimah) under id "0"; the dump must carry it, ordered first.
        val zero = baseDumpJson
            .replace("\"sunnah_now:bukhari:7\"", "\"sunnah_now:bukhari:0\"")
            .replace("\"providerHadithId\":\"7\"", "\"providerHadithId\":\"0\"")
        val dump = json.decodeFromString<OfflineBaseDump>(zero)
        OfflineDumps.validateBaseDump(dump)
        assertEquals("0", dump.hadiths.first { it.providerHadithId == "0" }.providerHadithId)
        assertTrue(OfflineModels.compareProviderHadithIds("0", "1") < 0)
        assertTrue(OfflineModels.compareProviderHadithIds("1", "0") > 0)
    }

    @Test
    fun `rejects duplicate pack entries`() {
        val dup = """
            {"format":"hadithly-translation-pack","schemaVersion":1,"collectionSlug":"bukhari",
            "language":"ur","baseContentVersion":"$baseVersion",
            "contentVersion":"od1:${"b".repeat(64)}","generatedAt":1700000000000,
            "license":${license()},
            "entries":[{"canonicalId":"sunnah_now:bukhari:7","language":"ur","content":"one",
            "source":"official","sourceLabel":"Official"},
            {"canonicalId":"sunnah_now:bukhari:7","language":"ur","content":"two",
            "source":"official","sourceLabel":"Official"}]}
        """.trimIndent()
        val pack = json.decodeFromString<OfflineTranslationPack>(dup)
        expectCode("duplicate_provider_id") { OfflineDumps.validatePack(pack) }
    }
}
