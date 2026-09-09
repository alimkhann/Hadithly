package com.hadithly.app

import com.hadithly.app.core.data.CollectionOutlineResult
import com.hadithly.app.core.data.OutlineChapter
import com.hadithly.app.core.data.OutlineVolume
import com.hadithly.app.core.links.CanonicalHadithLink
import com.hadithly.app.core.links.CanonicalHadithUrl
import com.hadithly.app.features.reader.ReaderShare
import com.hadithly.app.features.reader.ReaderViewModel
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * R5: canonical URL builder, copy-text formatter, chapter outline decoding
 * with pre-R5 back-compat, and jump-to-reference validation.
 */
class ReaderR5Test {

    private val json = Json { ignoreUnknownKeys = true }

    // Canonical URL builder

    @Test
    fun `url builder produces the canonical shape`() {
        assertEquals(
            "https://hadithly.app/hadith/bukhari/57",
            CanonicalHadithUrl.build("bukhari", "57"),
        )
        assertEquals(
            "https://hadithly.app/hadith/muslim/4.5",
            CanonicalHadithUrl.build("muslim", "4.5"),
        )
    }

    @Test
    fun `url builder rejects malformed slugs and ids`() {
        org.junit.Assert.assertThrows(IllegalArgumentException::class.java) {
            CanonicalHadithUrl.build("Bukhari", "57")
        }
        org.junit.Assert.assertThrows(IllegalArgumentException::class.java) {
            CanonicalHadithUrl.build("bukhari", "0")
        }
        org.junit.Assert.assertThrows(IllegalArgumentException::class.java) {
            CanonicalHadithUrl.build("bukhari", ".5")
        }
        org.junit.Assert.assertThrows(IllegalArgumentException::class.java) {
            CanonicalHadithUrl.build("bukhari", "57abc")
        }
    }

    @Test
    fun `built urls round-trip through the inbound parser`() {
        for ((slug, id) in listOf("bukhari" to "57", "muslim" to "4.5", "abu-dawood" to "1000")) {
            val url = CanonicalHadithUrl.build(slug, id)
            val path = url.removePrefix("https://hadithly.app")
            val parsed = CanonicalHadithLink.parse("https", "hadithly.app", path)
            assertEquals(slug, parsed?.collectionSlug)
            assertEquals(id, parsed?.providerHadithId)
        }
    }

    // Copy-text formatter

    @Test
    fun `copy formatter mixes arabic, translation, and source line`() {
        val text = ReaderShare.formatCopyText(
            arabicText = "حَدَّثَنَا",
            translationText = "He said:",
            translationIsAi = false,
            collectionName = "Sahih al-Bukhari",
            providerHadithId = "57",
            sourceName = "Sunnah.com",
        )
        assertEquals(
            "حَدَّثَنَا\n\nHe said:\n\n— Sahih al-Bukhari · Hadith 57 · Sunnah.com",
            text,
        )
    }

    @Test
    fun `copy formatter supports arabic-only pages`() {
        val text = ReaderShare.formatCopyText(
            arabicText = "حَدَّثَنَا",
            translationText = null,
            translationIsAi = false,
            collectionName = "Sahih al-Bukhari",
            providerHadithId = "57",
            sourceName = "Sunnah.com",
        )
        assertEquals("حَدَّثَنَا\n\n— Sahih al-Bukhari · Hadith 57 · Sunnah.com", text)
    }

    @Test
    fun `copy formatter labels ai translations only`() {
        val ai = ReaderShare.formatCopyText(
            arabicText = null,
            translationText = "Kazakh rendering",
            translationIsAi = true,
            collectionName = "Sahih al-Bukhari",
            providerHadithId = "57",
            sourceName = "Sunnah.com",
        )
        assertTrue(ai.endsWith("· AI translation"))
        val providerEnglish = ReaderShare.formatCopyText(
            arabicText = null,
            translationText = "He said:",
            translationIsAi = false,
            collectionName = "Sahih al-Bukhari",
            providerHadithId = "57",
            sourceName = "Sunnah.com",
        )
        assertFalse(providerEnglish.contains("AI translation"))
    }

    @Test
    fun `copy formatter never includes the url`() {
        val text = ReaderShare.formatCopyText(
            arabicText = "حَدَّثَنَا",
            translationText = "He said:",
            translationIsAi = true,
            collectionName = "Sahih al-Bukhari",
            providerHadithId = "57",
            sourceName = "Sunnah.com",
        )
        assertFalse(text.contains("https://"))
        assertFalse(text.contains("hadithly.app"))
    }

    // Chapter outline decoding

    @Test
    fun `chapters decode from source-provided outlines`() {
        val payload = """
            {
              "volumes": [{
                "volumeId": "v1",
                "title": "Volume 1",
                "hadithCount": 58,
                "chapters": [
                  {"title": "Revelation", "arabicTitle": "الوحي", "hadithCount": 7, "firstProviderHadithId": "1"},
                  {"chapterId": "c2", "title": "Belief", "hadithCount": 51, "firstProviderHadithId": "8"}
                ]
              }]
            }
        """.trimIndent()
        val result = json.decodeFromString<CollectionOutlineResult>(payload)
        val volume = result.volumes.single()
        assertEquals(2, volume.chapters.size)
        assertEquals("Revelation", volume.chapters[0].title)
        assertEquals("الوحي", volume.chapters[0].arabicTitle)
        assertEquals(7.0, volume.chapters[0].hadithCount, 0.0)
        assertEquals("1", volume.chapters[0].firstProviderHadithId)
        assertNull(volume.chapters[0].chapterId)
        assertEquals("c2", volume.chapters[1].chapterId)
    }

    @Test
    fun `missing chapters decode as empty for pre-R5 caches`() {
        val payload = """
            {"volumes": [{"volumeId": "v1", "title": "Volume 1", "hadithCount": 58}]}
        """.trimIndent()
        val result = json.decodeFromString<CollectionOutlineResult>(payload)
        assertTrue(result.volumes.single().chapters.isEmpty())
    }

    // Jump-to-reference validation

    @Test
    fun `jump validation accepts plain and dotted numbers`() {
        assertTrue(CanonicalHadithLink.isValidProviderHadithId("57"))
        assertTrue(CanonicalHadithLink.isValidProviderHadithId("4.5"))
        assertTrue(CanonicalHadithLink.isValidProviderHadithId("1"))
    }

    @Test
    fun `jump validation rejects malformed input`() {
        for (bad in listOf("0", ".5", "abc", "", "57.", "57abc", " 57", "-3", "0.5")) {
            assertFalse("should reject $bad", CanonicalHadithLink.isValidProviderHadithId(bad))
        }
    }

    @Test
    fun `chapter volumes reuse the canonical volume locator`() {
        val outline = listOf(
            OutlineVolume(
                volumeId = "1",
                title = "Volume 1",
                hadithCount = 7.0,
                chapters = listOf(
                    OutlineChapter(title = "Revelation", hadithCount = 7.0, firstProviderHadithId = "1"),
                ),
            ),
            OutlineVolume(
                volumeId = "2",
                title = "Volume 2",
                hadithCount = 51.0,
                chapters = listOf(
                    OutlineChapter(title = "Belief", hadithCount = 51.0, firstProviderHadithId = "8"),
                ),
            ),
        )
        // Chapter targets resolve through the same volume locator.
        assertEquals("2", ReaderViewModel.volumeIdForHadithNumber("57", outline))
        assertEquals("1", ReaderViewModel.volumeIdForHadithNumber("1", outline))
        assertEquals("1", ReaderViewModel.volumeIdForHadithNumber(outline[0].chapters[0].firstProviderHadithId, outline))
        assertEquals("2", ReaderViewModel.volumeIdForHadithNumber(outline[1].chapters[0].firstProviderHadithId, outline))
    }
}
