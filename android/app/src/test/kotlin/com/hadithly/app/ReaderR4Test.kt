package com.hadithly.app

import com.hadithly.app.core.preferences.ArabicTypeSize
import com.hadithly.app.core.preferences.ReaderPreferences
import com.hadithly.app.core.preferences.ReaderTheme
import com.hadithly.app.core.theme.ReaderPalettes
import com.hadithly.app.features.reader.ReaderChapterBoundaries
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * R4: reader themes, Arabic type ladder, source-provided chapter boundaries,
 * and the layout projection that recomputes layout signatures.
 */
class ReaderR4Test {

    // Themes

    @Test
    fun `resolved palettes follow the theme preference`() {
        assertEquals(ReaderPalettes.dark, ReaderPalettes.resolved(ReaderTheme.DARK, systemDark = false))
        assertEquals(ReaderPalettes.light, ReaderPalettes.resolved(ReaderTheme.LIGHT, systemDark = true))
        assertEquals(ReaderPalettes.paper, ReaderPalettes.resolved(ReaderTheme.PAPER, systemDark = false))
        assertEquals(ReaderPalettes.light, ReaderPalettes.resolved(ReaderTheme.SYSTEM, systemDark = false))
        assertEquals(ReaderPalettes.dark, ReaderPalettes.resolved(ReaderTheme.SYSTEM, systemDark = true))
    }

    @Test
    fun `light and paper palettes differ from the dark default`() {
        assertNotEquals(ReaderPalettes.dark.background, ReaderPalettes.light.background)
        assertNotEquals(ReaderPalettes.dark.background, ReaderPalettes.paper.background)
        assertTrue(ReaderPalettes.light.textPrimary != ReaderPalettes.light.background)
        assertTrue(ReaderPalettes.paper.textPrimary != ReaderPalettes.paper.background)
    }

    // Arabic type ladder

    @Test
    fun `type size ladder stays inside the preference clamp`() {
        assertEquals(ReaderPreferences.MIN_ARABIC_FONT_SIZE, ReaderPreferences.ARABIC_FONT_SIZE_STEPS.first())
        assertEquals(ReaderPreferences.MAX_ARABIC_FONT_SIZE, ReaderPreferences.ARABIC_FONT_SIZE_STEPS.last())
    }

    @Test
    fun `type size stepping is clamped at both ends`() {
        assertEquals(22f, ArabicTypeSize.stepUp(18f))
        assertEquals(40f, ArabicTypeSize.stepUp(40f))
        assertEquals(34f, ArabicTypeSize.stepDown(40f))
        assertEquals(18f, ArabicTypeSize.stepDown(18f))
        assertEquals(26f, ArabicTypeSize.nearest(27f))
        assertEquals(34f, ArabicTypeSize.nearest(36f))
    }

    // Layout projection

    @Test
    fun `layout projection tracks layout-affecting preferences`() {
        var preferences = ReaderPreferences()
        val baseline = preferences.layoutProjection

        preferences = preferences.copy(arabicFontSize = 30f)
        assertNotEquals(baseline, preferences.layoutProjection)

        preferences = preferences.copy(arabicFont = com.hadithly.app.core.preferences.ArabicFont.AMIRI)
        assertNotEquals(baseline, preferences.layoutProjection)

        preferences = preferences.copy(arabicVisible = false)
        assertNotEquals(baseline, preferences.layoutProjection)

        preferences = preferences.copy(translationLocale = "ur")
        assertNotEquals(baseline, preferences.layoutProjection)
    }

    @Test
    fun `layout projection ignores theme and direction`() {
        var preferences = ReaderPreferences()
        val baseline = preferences.layoutProjection
        preferences = preferences.copy(
            theme = ReaderTheme.PAPER,
            readingDirection = com.hadithly.app.core.preferences.ReadingDirection.RTL,
        )
        assertEquals(baseline, preferences.layoutProjection)
    }

    // Chapter boundaries

    private fun hadith(id: String, chapter: String?) = com.hadithly.app.core.data.ReaderHadith(
        _id = id,
        provider = "sunnah_now",
        canonicalId = "sunnah_now:bukhari:7",
        providerHadithId = "7",
        collectionSlug = "bukhari",
        arabicText = "نَمَّ",
        referenceDisplay = "Sahih al-Bukhari · Hadith 7",
        collectionName = "Sahih al-Bukhari",
        chapterName = chapter,
        authenticity = com.hadithly.app.core.data.AuthenticityClaim(
            kind = "collection_scope",
            normalizedGrade = "sahih",
            claimScope = "collection",
            sourceLabel = "Documented Sahih collection",
            sourceName = "Sunnah.now",
            sourceUrl = "https://sunnah.now/bukhari/about",
            verificationMethod = "manual_collection_mapping",
        ),
    )

    @Test
    fun `chapter openings only come from source names`() {
        val hadiths = listOf(
            hadith("a", "Revelation"),
            hadith("b", "Revelation"),
            hadith("c", null),
            hadith("d", "Belief"),
        )
        assertEquals(setOf(0, 3), ReaderChapterBoundaries.openingIndices(hadiths))
    }

    @Test
    fun `chapter openings handle an unnamed page start`() {
        val hadiths = listOf(hadith("a", null), hadith("b", "Belief"))
        assertEquals(setOf(1), ReaderChapterBoundaries.openingIndices(hadiths))
    }
}
