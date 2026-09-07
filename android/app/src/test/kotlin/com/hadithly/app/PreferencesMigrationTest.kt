package com.hadithly.app

import com.hadithly.app.core.preferences.PreferencesStore
import com.hadithly.app.core.preferences.ReaderPreferences
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PreferencesMigrationTest {

    @Test
    fun `without legacy state seeds English defaults`() {
        val result = PreferencesStore.migrate(storedJson = null, legacyLanguage = null)
        assertFalse(result.seededFromLegacy)
        assertEquals("en", result.preferences.uiLocale)
        assertEquals("en", result.preferences.translationLocale)
    }

    @Test
    fun `legacy translation setting migrates to both locales once`() {
        val result = PreferencesStore.migrate(storedJson = null, legacyLanguage = "ur")
        assertTrue(result.seededFromLegacy)
        assertEquals("ur", result.preferences.uiLocale)
        assertEquals("ur", result.preferences.translationLocale)
    }

    @Test
    fun `legacy Arabic font size migrates and clamps`() {
        val seeded = PreferencesStore.migrate(storedJson = null, legacyLanguage = "en", legacyArabicFontSize = 33f)
        assertEquals(33f, seeded.preferences.arabicFontSize)
        val clamped = PreferencesStore.migrate(storedJson = null, legacyLanguage = "en", legacyArabicFontSize = 90f)
        assertEquals(40f, clamped.preferences.arabicFontSize)
    }

    @Test
    fun `stored v1 payload wins and legacy value does not reset explicit choice`() {
        val explicit = ReaderPreferences(
            uiLocale = "en",
            translationLocale = "ar",
            theme = com.hadithly.app.core.preferences.ReaderTheme.PAPER,
            updatedAt = 500.0,
        )
        val json = kotlinx.serialization.json.Json { encodeDefaults = true }
        val stored = json.encodeToString(explicit)

        val result = PreferencesStore.migrate(storedJson = stored, legacyLanguage = "ur")
        assertFalse(result.seededFromLegacy)
        assertEquals("ar", result.preferences.translationLocale)
        assertEquals(com.hadithly.app.core.preferences.ReaderTheme.PAPER, result.preferences.theme)
        assertEquals(500.0, result.preferences.updatedAt, 0.0)
    }

    @Test
    fun `corrupt stored payload falls back to legacy seed`() {
        val result = PreferencesStore.migrate(storedJson = "{not json", legacyLanguage = "ar")
        assertTrue(result.seededFromLegacy)
        assertEquals("ar", result.preferences.uiLocale)
        assertEquals("ar", result.preferences.translationLocale)
    }

    @Test
    fun `unknown font id in stored payload falls back to system`() {
        val stored = """
            {
              "schemaVersion": 1,
              "uiLocale": "en",
              "translationLocale": "en",
              "readingDirection": "auto",
              "theme": "dark",
              "arabicFont": "some-future-naskh",
              "arabicFontSize": 30.0,
              "arabicVisible": true,
              "translationVisible": true,
              "updatedAt": 99.0
            }
        """.trimIndent()
        val result = PreferencesStore.migrate(storedJson = stored, legacyLanguage = null)
        assertEquals(com.hadithly.app.core.preferences.ArabicFont.SYSTEM, result.preferences.arabicFont)
        assertEquals("dark", result.preferences.theme.wire)
    }
}
