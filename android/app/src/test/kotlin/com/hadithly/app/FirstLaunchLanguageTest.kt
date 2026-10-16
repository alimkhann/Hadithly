package com.hadithly.app

import com.hadithly.app.core.preferences.PreferencesStore
import org.junit.Assert.assertEquals
import org.junit.Test

class FirstLaunchLanguageTest {
    @Test fun everyOfferedLanguageCanBeDetectedBeforeWelcome() {
        val cases = listOf("en-US" to "en", "ar-SA" to "ar", "ru-RU" to "ru", "kk-KZ" to "kk", "ky-KG" to "ky", "uz-Latn-UZ" to "uz", "tr-TR" to "tr", "id-ID" to "id", "ur-PK" to "ur", "fr-FR" to "fr", "es-MX" to "es-419", "pt-PT" to "pt-BR", "sw-KE" to "sw", "hi-IN" to "hi", "bn-BD" to "bn")
        cases.forEach { (device, expected) -> assertEquals(device, expected, PreferencesStore.suggestedLanguage(listOf(device))) }
        assertEquals("fr", PreferencesStore.suggestedLanguage(listOf("de-DE", "fr-CA", "en-US")))
    }
}
