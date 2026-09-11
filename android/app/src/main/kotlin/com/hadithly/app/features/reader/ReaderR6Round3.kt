package com.hadithly.app.features.reader

import com.hadithly.app.core.data.OutlineChapter
import com.hadithly.app.core.data.OutlineVolume
import com.hadithly.app.core.data.ReaderHadith

/**
 * R6 round 3 pure display rules. Every function is unit-pinned; the
 * composables resolve locale resources at the composition boundary and call
 * in here for the decision.
 */

/**
 * The narration line for the visible layers. Arabic-only reading shows the
 * provider's Arabic narrator (`narratorAr`); every other mode keeps the
 * English narrator. Null (missing stays hidden) when the mode's line is
 * absent — callers fall back to hiding the narrator.
 */
fun narratorForMode(hadith: ReaderHadith, arabicOnly: Boolean): String? =
    if (arabicOnly) hadith.narratorAr?.takeIf { it.isNotBlank() }
    else hadith.narrator?.takeIf { it.isNotBlank() }

/**
 * Volume title for the visible layers. Arabic-only reading shows the
 * localized volume name (`localizedVolume` resolves e.g. values-ar
 * `reader_volume_title`) for `Volume N` outline titles; any other title
 * shape, any other mode, or a missing number keeps the source title as-is.
 */
fun volumeTitleForDisplay(
    title: String,
    arabicOnly: Boolean,
    localizedVolume: (Int) -> String,
): String {
    if (!arabicOnly) return title
    val number = ReaderViewModel.volumeTitleNumber(title) ?: return title
    return localizedVolume(number)
}

/**
 * Chapter title for the visible layers. Arabic-only reading uses the
 * provider's `arabicTitle` when present, else the title. Mixed and
 * translation-only modes keep the title (the Arabic second line stays
 * governed by [visibleArabicChapterTitle]).
 */
fun chapterTitleForDisplay(chapter: OutlineChapter, arabicOnly: Boolean): String {
    if (!arabicOnly) return chapter.title
    return chapter.arabicTitle?.takeIf { it.isNotBlank() } ?: chapter.title
}

/** Display title variant for header call sites that already resolved the Arabic subtitle. */
fun chapterTitleForDisplay(title: String, arabicTitle: String?, arabicOnly: Boolean): String {
    if (!arabicOnly) return title
    return arabicTitle?.takeIf { it.isNotBlank() } ?: title
}

/**
 * Focused thin page bar fraction: the page index plus the intra-page scroll
 * fraction, over the backend-reported total. Fills and defills with page
 * scroll; null until the backend reports a total (the bar stays hidden).
 */
fun focusedProgressFraction(pageIndex: Int, totalPages: Int?, intraPageFraction: Float): Double? {
    if (totalPages == null || totalPages <= 0) return null
    val intra = intraPageFraction.coerceIn(0f, 1f).toDouble()
    return ((pageIndex.coerceAtLeast(0) + intra) / totalPages).coerceIn(0.0, 1.0)
}

/** Static volume bar fraction for the unfocused chrome; null when unknown. */
fun volumeProgressFraction(volumeCount: Int, selectedIndex: Int): Double? {
    if (volumeCount <= 0 || selectedIndex < 0 || selectedIndex >= volumeCount) return null
    return ((selectedIndex + 1).toDouble() / volumeCount).coerceIn(0.0, 1.0)
}

/**
 * Quiet relative-time label for reader Saved rows. `nowMs`/`thenMs` are
 * epoch milliseconds (Convex and guest stores both persist millis).
 */
fun relativeTimeLabel(nowMs: Long, thenMs: Double): String {
    val deltaSec = ((nowMs - thenMs.toLong()) / 1000).coerceAtLeast(0)
    return when {
        deltaSec < 60 -> "Just now"
        deltaSec < 3600 -> "${deltaSec / 60}m ago"
        deltaSec < 86400 -> "${deltaSec / 3600}h ago"
        deltaSec < 7 * 86400 -> "${deltaSec / 86400}d ago"
        else -> "${deltaSec / (7 * 86400)}w ago"
    }
}

/** Where the reader menu bookmark can land. */
enum class BookmarkPlacement { PAGE_START, POSITIONED }

/**
 * Bookmark placement targets for the menu choice sheet: the first hadith on
 * the current page and the positioned (R2 anchor) hadith. Null slots mean
 * the choice is unavailable (empty page / no position yet).
 */
data class BookmarkPlacementTargets(
    val pageStart: ReaderHadith?,
    val positioned: ReaderHadith?,
)

fun bookmarkPlacementTargets(
    pageHadiths: List<ReaderHadith>,
    positioned: ReaderHadith?,
): BookmarkPlacementTargets = BookmarkPlacementTargets(
    pageStart = pageHadiths.firstOrNull(),
    positioned = positioned,
)

/**
 * R6 reader fix round: the big centered volume header shows the ACTUAL
 * volume name — the outline's `firstChapterTitle`, falling back to the
 * first chapter title, then the outline title. Never synthesized beyond
 * those source-provided values.
 */
fun volumeHeaderTitle(volume: OutlineVolume): String {
    volume.firstChapterTitle?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
    volume.chapters.firstOrNull()?.title?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
    return volume.title
}

/**
 * R6 reader fix round: the volume number behind the quiet "Volume N"
 * eyebrow (localized via `reader_volume_title` at the call site), the
 * corner label, and the volume-edge pills. Parsed from a `Volume N`
 * outline title first, then the volume id; null when neither carries a
 * number — the eyebrow then hides instead of guessing.
 */
fun volumeHeaderNumber(volume: OutlineVolume): Int? =
    ReaderViewModel.volumeTitleNumber(volume.title) ?: volume.volumeId.toIntOrNull()

/**
 * R6 reader fix round: the unfocused Page pill (`Page N`) fills with the
 * intra-page scroll fraction only — position within the current page.
 */
fun pagePillFillFraction(intraPageFraction: Float): Float =
    intraPageFraction.coerceIn(0f, 1f)

/**
 * R6 reader fix round 5: per-page vertical scroll offsets. Leaving a page
 * stores its LazyColumn position; navigating back to one of the last
 * [maxEntries] pages restores the exact offset instead of the top. Backed
 * by an access-ordered map so the least-recently-visited page evicts first.
 * One instance per volume (page indices reset on volume switches and jumps).
 */
class ReaderScrollOffsetCache(maxEntries: Int = 2) {
    private val limit = maxEntries.coerceAtLeast(1)
    private val map = object : LinkedHashMap<Int, Pair<Int, Int>>(limit + 1, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<Int, Pair<Int, Int>>): Boolean =
            size > limit
    }

    /** Stores the LazyColumn position for [pageIndex]. */
    fun save(pageIndex: Int, firstVisibleItem: Int, firstVisibleItemOffset: Int) {
        map[pageIndex] = firstVisibleItem to firstVisibleItemOffset
    }

    /** The stored position for [pageIndex], or null when evicted/never saved. */
    fun restore(pageIndex: Int): Pair<Int, Int>? = map[pageIndex]

    /** How many pages are currently cached (never more than the limit). */
    fun size(): Int = map.size
}

/**
 * R6 reader fix round: the unfocused Volume pill (`Volume N`) fills with
 * the current page fraction within the volume (page index plus intra-page
 * scroll over the backend-reported total). Null until the total is known.
 */
fun volumePillFillFraction(pageIndex: Int, totalPages: Int?, intraPageFraction: Float): Double? =
    focusedProgressFraction(pageIndex, totalPages, intraPageFraction)
