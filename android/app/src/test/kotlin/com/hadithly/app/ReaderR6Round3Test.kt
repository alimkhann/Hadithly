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
import com.hadithly.app.features.reader.CONFIRMED_TAP_TIMEOUT_MILLIS
import com.hadithly.app.features.reader.ReaderHapticKind
import com.hadithly.app.features.reader.ReaderHaptics
import com.hadithly.app.features.reader.ReaderScrollOffsetCache
import com.hadithly.app.features.reader.readerPageLandingItemIndex
import com.hadithly.app.features.reader.ReaderShare
import com.hadithly.app.features.reader.bookmarkDialogRows
import com.hadithly.app.features.reader.bookmarkPlacementTargets
import com.hadithly.app.features.reader.pagePillsForPage
import com.hadithly.app.features.reader.chapterTitleForDisplay
import com.hadithly.app.features.reader.focusedProgressFraction
import com.hadithly.app.features.reader.isConfirmedTap
import com.hadithly.app.features.reader.narratorForMode
import com.hadithly.app.features.reader.nextPreviewRestoreTicks
import com.hadithly.app.features.reader.pagePillFillFraction
import com.hadithly.app.features.reader.relativeTimeLabel
import com.hadithly.app.features.reader.volumeHeaderNumber
import com.hadithly.app.features.reader.volumeHeaderTitle
import com.hadithly.app.features.reader.volumePillFillFraction
import com.hadithly.app.features.reader.volumeProgressFraction
import com.hadithly.app.features.reader.volumeTitleForDisplay
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

    @Test
    fun `dialog rows always render start positioned and cancel`() {
        val first = hadith("57")
        val second = hadith("58")
        val rows = bookmarkDialogRows(bookmarkPlacementTargets(listOf(first, second), second)) { false }
        assertEquals(3, rows.size)
        assertEquals("reader.bookmarkSheet.pageStart", rows[0].testTag)
        assertEquals(first, rows[0].target)
        assertTrue(rows[0].enabled)
        assertEquals("reader.bookmarkSheet.positioned", rows[1].testTag)
        assertEquals(second, rows[1].target)
        assertTrue(rows[1].enabled)
        assertEquals("reader.bookmarkSheet.cancel", rows[2].testTag)
        assertTrue(rows[2].enabled)
        assertNull(rows[2].target)

        // Empty page: both options stay visible but disabled — the card can
        // never collapse to a Cancel-only row.
        val empty = bookmarkDialogRows(bookmarkPlacementTargets(emptyList(), null)) { false }
        assertEquals(3, empty.size)
        assertEquals("reader.bookmarkSheet.pageStart", empty[0].testTag)
        assertEquals("reader.bookmarkSheet.positioned", empty[1].testTag)
        assertEquals("reader.bookmarkSheet.cancel", empty[2].testTag)
        assertTrue(!empty[0].enabled && !empty[1].enabled && empty[2].enabled)
    }

    @Test
    fun `per-page pills match settled pills and never depend on settle`() {
        val volumes = listOf(
            OutlineVolume(volumeId = "1", title = "Volume 1", hadithCount = 2.0),
            OutlineVolume(volumeId = "2", title = "Volume 2", hadithCount = 2.0),
        )
        val pages = listOf(
            com.hadithly.app.core.data.ReaderPageResult(items = emptyList(), page = 1.0, hasMore = true),
            com.hadithly.app.core.data.ReaderPageResult(items = emptyList(), page = 2.0),
        )
        // Each slot resolves its own labels from cached sources.
        val first = pagePillsForPage(0, pages, volumes, "1")
        assertEquals("Page 2", first.next?.label)
        val second = pagePillsForPage(1, pages, volumes, "1")
        assertEquals("Page 1", second.previous?.label)
        assertEquals("Volume 2", second.next?.label)
        // The settled slot matches the settled-index pill state exactly.
        val settled = com.hadithly.app.features.reader.ReaderPagePills.state(
            pageIndex = 1, hasPreviousPage = true, hasNextPage = false,
            atLoadedPage = true, volumes = volumes, selectedVolumeId = "1",
        )
        assertEquals(settled, second)
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
        // Round 6: exactly one light feedback on the tap toggling
        // focused/unfocused chrome; scroll/drag/swipe/settle stay silent.
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

    // Round 5: 2-entry per-page scroll offset cache

    @Test
    fun `scroll cache restores the exact stored offset`() {
        val cache = ReaderScrollOffsetCache()
        assertNull(cache.restore(0))
        cache.save(0, 5, 120)
        assertEquals(5 to 120, cache.restore(0))
        assertEquals(1, cache.size())
    }

    @Test
    fun `fresh page lands on the header while a target accounts for it`() {
        assertEquals(0, readerPageLandingItemIndex(targetHadithIndex = null, hasCachedOffset = false))
        assertEquals(1, readerPageLandingItemIndex(targetHadithIndex = 0, hasCachedOffset = false))
        assertEquals(3, readerPageLandingItemIndex(targetHadithIndex = 2, hasCachedOffset = false))
        assertNull(readerPageLandingItemIndex(targetHadithIndex = null, hasCachedOffset = true))
    }

    @Test
    fun `initial landing preserves top cached offsets and explicit targets`() {
        assertEquals(0 to 0, com.hadithly.app.features.reader.readerInitialOffset(null, null))
        assertEquals(0 to 0, com.hadithly.app.features.reader.readerInitialOffset(null, 0 to 0))
        assertEquals(2 to 148, com.hadithly.app.features.reader.readerInitialOffset(null, 2 to 148))
        assertEquals(1 to 0, com.hadithly.app.features.reader.readerInitialOffset(0, 2 to 148))
        assertEquals(4 to 0, com.hadithly.app.features.reader.readerInitialOffset(3, null))
    }

    @Test
    fun `captured header and footer are never hadith anchors`() {
        assertNull(com.hadithly.app.features.reader.readerHadithIndex(0, 3))
        assertEquals(0, com.hadithly.app.features.reader.readerHadithIndex(1, 3))
        assertEquals(2, com.hadithly.app.features.reader.readerHadithIndex(3, 3))
        assertNull(com.hadithly.app.features.reader.readerHadithIndex(4, 3))
    }

    @Test
    fun `scroll cache keeps only the last two pages`() {
        val cache = ReaderScrollOffsetCache()
        cache.save(0, 5, 120)
        cache.save(1, 0, 0)
        cache.save(2, 3, 40)
        assertEquals(2, cache.size())
        assertNull(cache.restore(0))
        assertEquals(0 to 0, cache.restore(1))
        assertEquals(3 to 40, cache.restore(2))
    }

    @Test
    fun `scroll cache re-save refreshes eviction order`() {
        val cache = ReaderScrollOffsetCache()
        cache.save(0, 1, 10)
        cache.save(1, 2, 20)
        cache.save(0, 1, 10)
        cache.save(2, 3, 30)
        assertNull(cache.restore(1))
        assertEquals(1 to 10, cache.restore(0))
        assertEquals(3 to 30, cache.restore(2))
    }

    // Round 6: preview-at-offset ticks

    @Test
    fun `preview tick bumps the targeted page only`() {
        val ticks = nextPreviewRestoreTicks(emptyMap(), 3)
        assertEquals(mapOf(3 to 1), ticks)
        val again = nextPreviewRestoreTicks(ticks, 3)
        assertEquals(mapOf(3 to 2), again)
        val other = nextPreviewRestoreTicks(again, 4)
        assertEquals(mapOf(3 to 2, 4 to 1), other)
    }

    @Test
    fun `preview tick ignores negative pages`() {
        val ticks = mapOf(0 to 1)
        assertEquals(ticks, nextPreviewRestoreTicks(ticks, -1))
    }

    // Round 7: tap-vs-drag disambiguation for the chrome toggle

    @Test
    fun `confirmed tap needs minimal movement and short duration`() {
        // A still, quick tap confirms.
        assertTrue(isConfirmedTap(100f, 200f, 102f, 201f, 120L, slopPx = 24f))
        // Exactly on the slop boundary still confirms.
        assertTrue(isConfirmedTap(0f, 0f, 24f, 0f, 100L, slopPx = 24f))
        // Exactly on the timeout still confirms.
        assertTrue(
            isConfirmedTap(0f, 0f, 0f, 0f, CONFIRMED_TAP_TIMEOUT_MILLIS, slopPx = 24f),
        )
    }

    @Test
    fun `swipe drag never confirms a tap`() {
        // A swipe's release is far beyond slop.
        assertEquals(false, isConfirmedTap(100f, 200f, 400f, 200f, 150L, slopPx = 24f))
        // A vertical scroll's release is far beyond slop.
        assertEquals(false, isConfirmedTap(100f, 200f, 100f, 600f, 300L, slopPx = 24f))
        // Just past the slop boundary rejects.
        assertEquals(false, isConfirmedTap(0f, 0f, 24.1f, 0f, 100L, slopPx = 24f))
    }

    @Test
    fun `long hold release never confirms a tap`() {
        assertEquals(false, isConfirmedTap(100f, 200f, 100f, 200f, CONFIRMED_TAP_TIMEOUT_MILLIS + 1, slopPx = 24f))
        assertEquals(false, isConfirmedTap(100f, 200f, 100f, 200f, -1L, slopPx = 24f))
    }
}
