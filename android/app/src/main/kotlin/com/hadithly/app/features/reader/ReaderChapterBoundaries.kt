package com.hadithly.app.features.reader

import com.hadithly.app.core.data.ReaderHadith

/**
 * Source-provided chapter boundaries (R4). A strong typographic header is
 * rendered only when the provider data carries a chapter name; Hadithly
 * never invents one. Mirrors the iOS ReaderChapterBoundaries helper.
 */
object ReaderChapterBoundaries {

    /**
     * The indices of [hadiths] that open a chapter on this page. A hadith
     * opens a chapter when its source chapter name is non-empty and differs
     * from the previous hadith's chapter name (a nil previous name starts a
     * boundary, so the first named hadith on a page gets its header).
     */
    fun openingIndices(hadiths: List<ReaderHadith>): Set<Int> {
        val openings = mutableSetOf<Int>()
        var previousName: String? = null
        hadiths.forEachIndexed { index, hadith ->
            val name = hadith.chapterName?.trim().orEmpty()
            if (name.isNotEmpty() && name != previousName) {
                openings.add(index)
            }
            if (name.isNotEmpty()) previousName = name
        }
        return openings
    }
}
