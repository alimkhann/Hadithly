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

    /**
     * Monochrome restyle gate: the palette-aware interactive tint keeps WCAG
     * AA contrast (4.5) for glyphs/links on every surface, and filled
     * interactive controls keep contrast with their foreground, on all
     * reader themes. A white accent on cream would fail this.
     */
    @Test
    fun `interactive tint meets contrast on every palette`() {
        listOf(ReaderPalettes.dark, ReaderPalettes.light, ReaderPalettes.paper).forEach { palette ->
            assertTrue(
                "interactive on background ${palette.interactive} ${palette.background}",
                contrast(palette.interactive, palette.background) >= 4.5,
            )
            assertTrue(
                "interactive on surface ${palette.interactive} ${palette.surface}",
                contrast(palette.interactive, palette.surface) >= 4.5,
            )
            assertTrue(
                "onInteractive on interactive",
                contrast(palette.onInteractive, palette.interactive) >= 4.5,
            )
        }
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

private fun relativeLuminance(color: androidx.compose.ui.graphics.Color): Double {
    fun lin(c: Double): Double = if (c <= 0.03928) c / 12.92 else Math.pow((c + 0.055) / 1.055, 2.4)
    return 0.2126 * lin(color.red.toDouble()) + 0.7152 * lin(color.green.toDouble()) + 0.0722 * lin(color.blue.toDouble())
}

private fun contrast(a: androidx.compose.ui.graphics.Color, b: androidx.compose.ui.graphics.Color): Double {
    val l1 = relativeLuminance(a)
    val l2 = relativeLuminance(b)
    return (maxOf(l1, l2) + 0.05) / (minOf(l1, l2) + 0.05)
}
