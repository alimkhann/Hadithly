package com.hadithly.app

import com.hadithly.app.core.data.Collections
import com.hadithly.app.core.data.DailyHadith
import com.hadithly.app.core.data.ReaderPageResult
import com.hadithly.app.core.data.ReaderTranslation
import com.hadithly.app.core.data.TranslationSubmissionResult
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Wire decoding checks against representative Convex JSON. The real client
 * uses the same kotlinx.serialization with ignoreUnknownKeys enabled.
 */
class WireModelsTest {

    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun `collections match the backend order`() {
        assertEquals("bukhari", Collections.all.first().first)
        assertEquals(7, Collections.all.size)
        assertEquals("bukhari", Collections.slugForName("Sahih al-Bukhari"))
        assertEquals("bukhari", Collections.slugForName(null))
    }

    @Test
    fun `reader page decodes with unknown keys ignored`() {
        val payload = """
            {
              "items": [{
                "_id": "jd7c0xxxxxxxxxxxxxxxxxxxxxxx0",
                "providerHadithId": "1",
                "collectionSlug": "bukhari",
                "volumeId": "volume-1",
                "arabicText": "حَدَّثَنَا",
                "englishText": "He said:",
                "narrator": "Umar ibn al-Khattab",
                "referenceDisplay": "Sahih al-Bukhari 1",
                "collectionName": "Sahih al-Bukhari",
                "chapterName": "Revelation",
                "sortOrder": 5
              }],
              "page": 1, "pageSize": 10, "totalPages": 42, "hasMore": true,
              "someFutureField": true
            }
        """.trimIndent()
        val result = json.decodeFromString<ReaderPageResult>(payload)
        assertEquals(1, result.items.size)
        assertEquals("sunnah_now:bukhari:1", result.items.first().internalId)
        assertTrue(result.hasMore)
        assertFalse(result.isPlaceholder)
    }

    @Test
    fun `placeholder pages are zero-page sentinels`() {
        val result = json.decodeFromString<ReaderPageResult>(
            """{"items": [], "page": 0, "pageSize": 0, "totalPages": 0, "hasMore": false}""",
        )
        assertTrue(result.isPlaceholder)
    }

    @Test
    fun `translation decodes with optional fields defaulted`() {
        val payload = """
            {
              "translationId": "t1",
              "translation": "Перевод",
              "confidence": 0.94,
              "riskFlags": [],
              "glossaryNotes": ["note"],
              "source": "gemini_ai",
              "sourceLabel": "Gemini",
              "groundingUsed": true,
              "citations": [{"url": "https://sunnah.com", "title": "Sunnah", "domain": "sunnah.com"}],
              "cached": false,
              "extraKey": 123
            }
        """.trimIndent()
        val translation = json.decodeFromString<ReaderTranslation>(payload)
        assertEquals("gemini_ai", translation.source)
        assertEquals("note", translation.glossaryNotes.first())
        assertEquals(null, translation.sourceReferenceUrl)
        assertEquals(1, translation.citations.size)
    }

    @Test
    fun `daily hadith decodes with an optional volume`() {
        val daily = json.decodeFromString<DailyHadith>(
            """{"_id":"h1","providerHadithId":"25","collectionSlug":"tirmidhi","collectionName":"Jami` at-Tirmidhi","volumeId":"1","arabicText":"نص","englishText":"Text","referenceDisplay":"Jami` at-Tirmidhi · Hadith 25"}""",
        )
        assertEquals("tirmidhi", daily.collectionSlug)
        assertEquals("1", daily.volumeId)
        assertEquals("25", daily.providerHadithId)
    }

    @Test
    fun `submission verdict keeps private AI review detail`() {
        val result = json.decodeFromString<TranslationSubmissionResult>(
            """{"submissionId":"s1","status":"needs_admin","aiReview":{"model":"gemini-2.5-flash-lite","score":0.72,"riskFlags":["ambiguous_wording"],"missingMeaning":["condition"],"recommendation":"admin_review"}}""",
        )
        assertEquals("needs_admin", result.status)
        assertEquals(2, result.aiReview.reviewNotes.size)
        assertTrue(result.aiReview.reviewNotes.last().contains("condition"))
    }
}
