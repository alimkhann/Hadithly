package com.hadithly.app

import com.hadithly.app.core.preferences.ArabicFont
import com.hadithly.app.core.preferences.PageDirection
import com.hadithly.app.core.preferences.PreferencesException
import com.hadithly.app.core.preferences.ReaderPreferences
import com.hadithly.app.core.preferences.ReaderPreferencesValidator
import com.hadithly.app.core.preferences.ReadingDirection
import com.hadithly.app.core.preferences.toWireMap
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class ReaderPreferencesTest {

    @Test
    fun `defaults match the contract`() {
        val preferences = ReaderPreferences()
        assertEquals("en", preferences.uiLocale)
        assertEquals("en", preferences.translationLocale)
        assertEquals(ReadingDirection.AUTO, preferences.readingDirection)
        assertTrue(preferences.arabicVisible)
        assertTrue(preferences.translationVisible)
        assertEquals(26f, preferences.arabicFontSize)
        assertEquals(1, preferences.schemaVersion)
    }

    @Test
    fun `validated rejects the all-hidden visibility state`() {
        val hidden = ReaderPreferences(arabicVisible = false, translationVisible = false)
        val error = assertThrows(PreferencesException.AllHiddenVisibility::class.java) {
            ReaderPreferencesValidator.validated(hidden)
        }
        assertTrue(error.message.orEmpty().startsWith("VISIBILITY_ALL_HIDDEN"))
        // Either single layer alone remains valid.
        assertTrue(ReaderPreferences(arabicVisible = true, translationVisible = false).arabicVisible)
        ReaderPreferencesValidator.validated(ReaderPreferences(arabicVisible = false, translationVisible = true))
    }

    @Test
    fun `validated clamps the Arabic font size`() {
        assertEquals(18f, ReaderPreferencesValidator.validated(ReaderPreferences(arabicFontSize = 5f)).arabicFontSize)
        assertEquals(40f, ReaderPreferencesValidator.validated(ReaderPreferences(arabicFontSize = 90f)).arabicFontSize)
    }

    @Test
    fun `validated canonicalizes locales and rejects malformed ones`() {
        val validated = ReaderPreferencesValidator.validated(
            ReaderPreferences(uiLocale = "UR_PK", translationLocale = "es-419"),
        )
        assertEquals("ur-PK", validated.uiLocale)
        assertEquals("es-419", validated.translationLocale)
        assertThrows(PreferencesException.InvalidLocale::class.java) {
            ReaderPreferencesValidator.validated(ReaderPreferences(translationLocale = "???"))
        }
    }

    @Test
    fun `json round trip preserves every field`() {
        val preferences = ReaderPreferences(
            uiLocale = "ur-PK",
            translationLocale = "ar",
            readingDirection = ReadingDirection.RTL,
            theme = com.hadithly.app.core.preferences.ReaderTheme.PAPER,
            arabicFont = ArabicFont.AMIRI,
            arabicFontSize = 32f,
            arabicVisible = false,
            translationVisible = true,
            updatedAt = 1234.0,
        )
        val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
        val encoded = json.encodeToString(preferences)
        assertEquals(preferences, json.decodeFromString<ReaderPreferences>(encoded))
        // Wire spellings must match the backend contract.
        assertTrue(encoded.contains(""""readingDirection":"rtl""""))
        assertTrue(encoded.contains(""""theme":"paper""""))
        assertTrue(encoded.contains(""""arabicFont":"amiri""""))
    }

    @Test
    fun `wire encoding uses Double for every number`() {
        val wire = ReaderPreferences(updatedAt = 99.0).toWireMap()
        assertTrue(wire["schemaVersion"] is Double)
        assertTrue(wire["arabicFontSize"] is Double)
        assertTrue(wire["updatedAt"] is Double)
        assertEquals(1.0, wire["schemaVersion"])
        assertEquals(26.0, wire["arabicFontSize"])
        assertEquals("auto", wire["readingDirection"])
        assertEquals("system", wire["theme"])
        assertEquals("system", wire["arabicFont"])
    }

    @Test
    fun `direction metadata matrix`() {
        // Arabic-only reading auto-resolves RTL.
        val arabicOnly = ReaderPreferences(arabicVisible = true, translationVisible = false)
        assertEquals(
            PageDirection.RTL,
            ReaderPreferencesValidator.directionMetadata(arabicOnly).pageDirection,
        )
        // Translation-only follows the translation script.
        assertEquals(
            PageDirection.RTL,
            ReaderPreferencesValidator.directionMetadata(
                ReaderPreferences(arabicVisible = false, translationLocale = "ur"),
            ).pageDirection,
        )
        // Mixed pages follow the translation language; Arabic blocks stay RTL.
        val mixedEnglish = ReaderPreferences(translationLocale = "en")
        val mixedMetadata = ReaderPreferencesValidator.directionMetadata(mixedEnglish)
        assertEquals(PageDirection.LTR, mixedMetadata.pageDirection)
        assertTrue(mixedMetadata.arabicBlocksRtl)
        assertEquals(
            PageDirection.RTL,
            ReaderPreferencesValidator.directionMetadata(
                ReaderPreferences(translationLocale = "ar"),
            ).pageDirection,
        )
        // Explicit direction overrides auto.
        assertEquals(
            PageDirection.LTR,
            ReaderPreferencesValidator.directionMetadata(
                ReaderPreferences(translationLocale = "ar", readingDirection = ReadingDirection.LTR),
            ).pageDirection,
        )
    }

    @Test
    fun `decoding unknown font id falls back to system`() {
        val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
        val newerBuild = """
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
        val decoded = json.decodeFromString<ReaderPreferences>(newerBuild)
        // A newer build's font id this build does not know falls back to the
        // system face instead of failing the decode, matching iOS.
        assertEquals(ArabicFont.SYSTEM, decoded.arabicFont)
        assertEquals(com.hadithly.app.core.preferences.ReaderTheme.DARK, decoded.theme)
        assertEquals(99.0, decoded.updatedAt, 0.0)
    }
}
