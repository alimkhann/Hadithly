package com.hadithly.app

import com.hadithly.app.core.data.AuthenticityClaim
import com.hadithly.app.core.data.EnglishSearchResult
import com.hadithly.app.core.data.HadithRef
import com.hadithly.app.core.data.OutlineChapter
import com.hadithly.app.core.data.OutlineVolume
import com.hadithly.app.core.data.ProgressEntry
import com.hadithly.app.core.data.ReaderHadith
import com.hadithly.app.core.data.ReaderPrefetch
import com.hadithly.app.core.data.ReaderPrefetch.EntryFetch
import com.hadithly.app.features.reader.BookmarkPlacement
import com.hadithly.app.features.reader.bookmarkPlacementTargets
import com.hadithly.app.features.reader.chapterTitleForDisplay
import com.hadithly.app.features.reader.focusedProgressFraction
import com.hadithly.app.features.reader.narratorForMode
import com.hadithly.app.features.reader.pagePillFillFraction
import com.hadithly.app.features.reader.relativeTimeLabel
import com.hadithly.app.features.reader.volumeHeaderNumber
import com.hadithly.app.features.reader.volumeHeaderTitle
import com.hadithly.app.features.reader.volumePillFillFraction
import com.hadithly.app.features.reader.volumeProgressFraction
import com.hadithly.app.features.reader.volumeTitleForDisplay
import com.hadithly.app.features.reader.ReaderHapticKind
import com.hadithly.app.features.reader.ReaderHaptics
import com.hadithly.app.features.reader.ReaderShare
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * R6 round 3 unit pins: narratorAr decode/fallback, prefetch bounds,
 * bookmark placement targets, search mapping, copy-format source update,
 * relative-time rows, and the progress-bar fractions.
 */
class ReaderR6Round3Test {

    private val json = Json { ignoreUnknownKeys = true }

    private fun authenticity() = AuthenticityClaim(
        kind = "collection_scope",
        normalizedGrade = "sahih",
        claimScope = "collection",
        sourceLabel = "Documented Sahih collection",
        sourceName = "Sunnah.now",
        sourceUrl = "https://sunnah.now",
        verificationMethod = "manual_collection_mapping",
    )

    private fun hadith(
        id: String = "57",
        narrator: String? = "Narrated 'Umar:",
        narratorAr: String? = null,
    ) = ReaderHadith(
        _id = "h-$id",
        provider = "sunnah_now",
        canonicalId = "sunnah_now:bukhari:$id",
        providerHadithId = id,
        collectionSlug = "bukhari",
        arabicText = "حَدَّثَنَا",
        englishText = "He said:",
        narrator = narrator,
        narratorAr = narratorAr,
        referenceDisplay = "Sahih al-Bukhari · Hadith $id",
        collectionName = "Sahih al-Bukhari",
        authenticity = authenticity(),
    )

    private fun ref(
        volumeId: String? = "2",
        number: String? = "57",
        updatedAt: Double = 1000.0,
    ) = HadithRef(
        hadithId = "h-57",
        collectionSlug = "bukhari",
        collectionName = "Sahih al-Bukhari",
        volumeId = volumeId,
        hadithNumber = number,
        arabicText = "حَدَّثَنَا",
        englishText = "He said:",
        referenceDisplay = "Sahih al-Bukhari · Hadith 57",
    ).let { ProgressEntry("bukhari", it, null, updatedAt) }

    // narratorAr decode + fallback

    @Test
    fun `missing narratorAr decodes tolerant and stays hidden`() {
        val payload = """
            {"_id":"h1","provider":"sunnah_now","canonicalId":"sunnah_now:bukhari:1",
             "providerHadithId":"1","collectionSlug":"bukhari","arabicText":"نص",
             "referenceDisplay":"Sahih al-Bukhari · Hadith 1","collectionName":"Sahih al-Bukhari",
             "authenticity":{"kind":"collection_scope","normalizedGrade":"sahih","claimScope":"collection",
             "sourceLabel":"Documented Sahih collection","sourceName":"Sunnah.now",
             "sourceUrl":"https://sunnah.now","verificationMethod":"manual_collection_mapping"}}
        """.trimIndent()
        val decoded = json.decodeFromString<ReaderHadith>(payload)
        assertNull(decoded.narratorAr)
        assertNull(narratorForMode(decoded, arabicOnly = true))
    }

    @Test
    fun `present narratorAr decodes and leads arabic-only mode`() {
        val withAr = hadith(narratorAr = "عَنْ عُمَرَ:")
        assertEquals("عَنْ عُمَرَ:", narratorForMode(withAr, arabicOnly = true))
        assertEquals("Narrated 'Umar:", narratorForMode(withAr, arabicOnly = false))
    }

    @Test
    fun `narrator falls back to hidden when the mode line is absent`() {
        assertNull(narratorForMode(hadith(narratorAr = null), arabicOnly = true))
        assertNull(narratorForMode(hadith(narratorAr = "  "), arabicOnly = true))
        // Mixed/translation-only behavior is unchanged: English narrator.
        assertEquals("Narrated 'Umar:", narratorForMode(hadith(), arabicOnly = false))
        assertNull(narratorForMode(hadith(narrator = null), arabicOnly = false))
    }

    // Volume + chapter display titles

    @Test
    fun `arabic-only volumes use the localized name`() {
        val localized: (Int) -> String = { n -> "المجلد $n" }
        assertEquals("المجلد 2", volumeTitleForDisplay("Volume 2", true, localized))
        // Non-Volume shapes keep the source title; mixed mode is unchanged.
        assertEquals("Kitab al-Iman", volumeTitleForDisplay("Kitab al-Iman", true, localized))
        assertEquals("Volume 2", volumeTitleForDisplay("Volume 2", false, localized))
    }

    @Test
    fun `arabic-only chapters prefer the arabic title`() {
        val chapter = OutlineChapter(
            title = "Belief",
            arabicTitle = "كتاب الإيمان",
            hadithCount = 51.0,
            firstProviderHadithId = "8",
        )
        assertEquals("كتاب الإيمان", chapterTitleForDisplay(chapter, true))
        assertEquals("Belief", chapterTitleForDisplay(chapter, false))
        val noArabic = OutlineChapter(title = "Belief", hadithCount = 1.0, firstProviderHadithId = "9")
        assertEquals("Belief", chapterTitleForDisplay(noArabic, true))
        assertEquals("Belief", chapterTitleForDisplay("Belief", null, true))
    }

    // Prefetch bounds

    private fun volumes(n: Int) = (1..n).map {
        OutlineVolume(volumeId = "$it", title = "Volume $it", hadithCount = 10.0)
    }

    @Test
    fun `entry plan is bounded to seven outlines plus one page`() {
        val slugs = listOf("bukhari", "muslim", "bukhari") + (1..10).map { "extra-$it" }
        val plan = ReaderPrefetch.entryPlan(slugs, listOf(ref()))
        val outlines = plan.filterIsInstance<EntryFetch.Outline>()
        assertEquals(ReaderPrefetch.MAX_ENTRY_COLLECTIONS, outlines.size)
        assertEquals(outlines.map { it.collectionSlug }.distinct().size, outlines.size)
        val pages = plan.filterIsInstance<EntryFetch.FirstPage>()
        assertEquals(1, pages.size)
        assertEquals("bukhari", pages.single().collectionSlug)
        assertEquals("2", pages.single().volumeId)
        assertTrue(plan.size <= ReaderPrefetch.MAX_ENTRY_COLLECTIONS + 1)
    }

    @Test
    fun `entry plan without progress fetches outlines only`() {
        val plan = ReaderPrefetch.entryPlan(listOf("bukhari", "muslim"), emptyList())
        assertEquals(2, plan.size)
        assertTrue(plan.all { it is EntryFetch.Outline })
    }

    @Test
    fun `most recent progress wins the page fetch`() {
        val plan = ReaderPrefetch.entryPlan(
            listOf("bukhari", "muslim"),
            listOf(
                ref(volumeId = "1", updatedAt = 100.0),
                ref(volumeId = "3", updatedAt = 900.0).copy(collectionSlug = "muslim"),
            ),
        )
        val pages = plan.filterIsInstance<EntryFetch.FirstPage>()
        assertEquals(1, pages.size)
        assertEquals("muslim", pages.single().collectionSlug)
        assertEquals("3", pages.single().volumeId)
    }

    @Test
    fun `adjacent volumes are bounded to immediate neighbors`() {
        val all = volumes(5)
        assertEquals(listOf("1", "3"), ReaderPrefetch.adjacentVolumeIds(all, "2"))
        assertEquals(listOf("2"), ReaderPrefetch.adjacentVolumeIds(all, "1"))
        assertEquals(listOf("4"), ReaderPrefetch.adjacentVolumeIds(all, "5"))
        assertTrue(ReaderPrefetch.adjacentVolumeIds(volumes(1), "1").isEmpty())
        assertTrue(ReaderPrefetch.adjacentVolumeIds(all, null).isEmpty())
        assertTrue(ReaderPrefetch.adjacentVolumeIds(all, "9").isEmpty())
    }

    @Test
    fun `executor is silent and bounded`() = runBlocking {
        var outlines = 0
        var pages = 0
        ReaderPrefetch.executePlan(
            plan = ReaderPrefetch.entryPlan((1..20).map { "s$it" }, listOf(ref())),
            fetchOutline = { outlines += 1 },
            fetchPage = { _, _ -> pages += 1 },
        )
        assertEquals(ReaderPrefetch.MAX_ENTRY_COLLECTIONS, outlines)
        assertEquals(1, pages)

        // Failures (offline) never escape and never stop the batch.
        var calls = 0
        ReaderPrefetch.executePlan(
            plan = listOf(EntryFetch.Outline("a"), EntryFetch.FirstPage("b", "1")),
            fetchOutline = { calls += 1; throw IllegalStateException("offline") },
            fetchPage = { _, _ -> calls += 1; throw IllegalStateException("offline") },
        )
        assertEquals(2, calls)
    }

    // Bookmark placement

    @Test
    fun `placement targets page start and positioned hadith`() {
        val first = hadith("57")
        val second = hadith("58")
        val targets = bookmarkPlacementTargets(listOf(first, second), second)
        assertEquals(first, targets.pageStart)
        assertEquals(second, targets.positioned)
        val empty = bookmarkPlacementTargets(emptyList(), null)
        assertNull(empty.pageStart)
        assertNull(empty.positioned)
    }

    @Test
    fun `placement enum covers both choices`() {
        assertEquals(2, BookmarkPlacement.entries.size)
    }

    // Search mapping

    @Test
    fun `search hits decode with tolerant defaults`() {
        val payload = """
            {"hadithId":"h1","canonicalId":"sunnah_now:bukhari:57","collectionSlug":"bukhari",
             "providerHadithId":"57","referenceDisplay":"Sahih al-Bukhari · Hadith 57",
             "snippet":"…matcher…"}
        """.trimIndent()
        val hit = json.decodeFromString<EnglishSearchResult>(payload)
        assertEquals("sunnah_now:bukhari:57", hit.canonicalId)
        assertEquals("57", hit.providerHadithId)
        assertEquals("Sahih al-Bukhari · Hadith 57", hit.referenceDisplay)
        assertEquals("…matcher…", hit.snippet)
        val sparse = json.decodeFromString<EnglishSearchResult>("{}")
        assertEquals("", sparse.canonicalId)
        assertEquals("", sparse.snippet)
    }

    // Copy format source update

    @Test
    fun `copy source line renders the backend-owned source name`() {
        val text = ReaderShare.formatCopyText(
            arabicText = "حَدَّثَنَا",
            translationText = "He said:",
            translationIsAi = false,
            collectionName = "Sahih al-Bukhari",
            providerHadithId = "57",
            sourceName = "Sunnah.now",
        )
        assertEquals(
            "حَدَّثَنَا\n\nHe said:\n\n— Sahih al-Bukhari · Hadith 57 · Sunnah.now",
            text,
        )
    }

    // Relative time + progress fractions

    @Test
    fun `relative time labels cover the quiet rows`() {
        val now = 1_700_000_000_000L
        assertEquals("Just now", relativeTimeLabel(now, (now - 10_000).toDouble()))
        assertEquals("5m ago", relativeTimeLabel(now, (now - 5 * 60_000).toDouble()))
        assertEquals("3h ago", relativeTimeLabel(now, (now - 3 * 3_600_000).toDouble()))
        assertEquals("2d ago", relativeTimeLabel(now, (now - 2 * 86_400_000).toDouble()))
        assertEquals("3w ago", relativeTimeLabel(now, (now - 21 * 86_400_000).toDouble()))
        assertEquals("Just now", relativeTimeLabel(now, (now + 60_000).toDouble()))
    }

    @Test
    fun `focused page fraction fills with page scroll`() {
        assertEquals(0.0, focusedProgressFraction(0, 10, 0f)!!, 0.0)
        assertEquals(0.05, focusedProgressFraction(0, 10, 0.5f)!!, 1e-9)
        assertEquals(0.5, focusedProgressFraction(4, 10, 1f)!!, 1e-9)
        assertEquals(1.0, focusedProgressFraction(9, 10, 1f)!!, 1e-9)
        assertNull(focusedProgressFraction(0, null, 0f))
        assertNull(focusedProgressFraction(0, 0, 0f))
    }

    @Test
    fun `volume fraction is static over the outline`() {
        assertEquals(0.5, volumeProgressFraction(4, 1)!!, 1e-9)
        assertEquals(1.0, volumeProgressFraction(4, 3)!!, 1e-9)
        assertNull(volumeProgressFraction(0, 0))
        assertNull(volumeProgressFraction(4, -1))
        assertNull(volumeProgressFraction(4, 4))
    }

    // R6 fix round: actual volume names, pill fills, haptic mapping

    @Test
    fun `volume header prefers the source first chapter title`() {
        val volume = OutlineVolume(
            volumeId = "1",
            title = "Volume 1",
            firstChapterTitle = "How the Divine Revelation started being revealed",
            hadithCount = 7.0,
            chapters = listOf(
                OutlineChapter(title = "Revelation", hadithCount = 7.0, firstProviderHadithId = "1"),
            ),
        )
        assertEquals(
            "How the Divine Revelation started being revealed",
            volumeHeaderTitle(volume),
        )
        assertEquals(1, volumeHeaderNumber(volume))
    }

    @Test
    fun `volume header falls back through first chapter to outline title`() {
        val byChapter = OutlineVolume(
            volumeId = "2",
            title = "Volume 2",
            hadithCount = 51.0,
            chapters = listOf(
                OutlineChapter(title = "Belief", hadithCount = 51.0, firstProviderHadithId = "8"),
            ),
        )
        assertEquals("Belief", volumeHeaderTitle(byChapter))
        assertEquals(2, volumeHeaderNumber(byChapter))

        val byTitle = OutlineVolume(volumeId = "3", title = "Kitab al-Iman", hadithCount = 4.0)
        assertEquals("Kitab al-Iman", volumeHeaderTitle(byTitle))
        assertEquals(3, volumeHeaderNumber(byTitle))

        val unnumbered = OutlineVolume(volumeId = "intro", title = "Introduction", hadithCount = 1.0)
        assertEquals("Introduction", volumeHeaderTitle(unnumbered))
        assertNull(volumeHeaderNumber(unnumbered))
    }

    @Test
    fun `page pill fills with intra-page scroll only`() {
        assertEquals(0f, pagePillFillFraction(0f))
        assertEquals(0.5f, pagePillFillFraction(0.5f))
        assertEquals(1f, pagePillFillFraction(1f))
        assertEquals(0f, pagePillFillFraction(-0.5f))
        assertEquals(1f, pagePillFillFraction(2f))
    }

    @Test
    fun `volume pill fills with the page fraction within the volume`() {
        assertEquals(0.05, volumePillFillFraction(0, 10, 0.5f)!!, 1e-9)
        assertEquals(0.5, volumePillFillFraction(4, 10, 1f)!!, 1e-9)
        assertNull(volumePillFillFraction(0, null, 0f))
        assertNull(volumePillFillFraction(0, 0, 0f))
    }

    @Test
    fun `haptic triggers map to native constants`() {
        assertEquals(
            android.view.HapticFeedbackConstants.CLOCK_TICK,
            ReaderHaptics.constantFor(ReaderHapticKind.MENU_OPEN_CLOSE),
        )
        assertEquals(
            android.view.HapticFeedbackConstants.CONTEXT_CLICK,
            ReaderHaptics.constantFor(ReaderHapticKind.MENU_ITEM),
        )
        assertEquals(
            android.view.HapticFeedbackConstants.KEYBOARD_TAP,
            ReaderHaptics.constantFor(ReaderHapticKind.TAP_TOGGLE),
        )
        assertEquals(
            android.view.HapticFeedbackConstants.CONTEXT_CLICK,
            ReaderHaptics.constantFor(ReaderHapticKind.LONG_PRESS_MENU),
        )
        assertEquals(
            android.view.HapticFeedbackConstants.CONFIRM,
            ReaderHaptics.constantFor(ReaderHapticKind.BOOKMARK_FAVORITE_ADD),
        )
        assertEquals(
            android.view.HapticFeedbackConstants.REJECT,
            ReaderHaptics.constantFor(ReaderHapticKind.REJECT_BOTH_HIDDEN),
        )
    }
}
