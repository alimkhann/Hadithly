package com.hadithly.app

import com.hadithly.app.core.preferences.LocaleFallback
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LocaleFallbackTest {

    @Test
    fun `canonicalizes BCP 47 casing and separators`() {
        assertEquals("en", LocaleFallback.canonicalizeLocaleTag("en"))
        assertEquals("en", LocaleFallback.canonicalizeLocaleTag("EN"))
        assertEquals("en-US", LocaleFallback.canonicalizeLocaleTag("en_US"))
        assertEquals("pt-BR", LocaleFallback.canonicalizeLocaleTag("pt-br"))
        assertEquals("es-419", LocaleFallback.canonicalizeLocaleTag("ES-419"))
        assertEquals("zh-Hans", LocaleFallback.canonicalizeLocaleTag("zh-HANS"))
    }

    @Test
    fun `canonicalize rejects malformed tags`() {
        assertNull(LocaleFallback.canonicalizeLocaleTag(""))
        assertNull(LocaleFallback.canonicalizeLocaleTag("not a locale"))
        assertNull(LocaleFallback.canonicalizeLocaleTag("1n"))
        assertNull(LocaleFallback.canonicalizeLocaleTag("e"))
        assertNull(LocaleFallback.canonicalizeLocaleTag("a-b-c-d-e-f-g-h-i"))
    }

    @Test
    fun `fallback chains end at English`() {
        assertEquals(listOf("ur-PK", "ur", "en"), LocaleFallback.fallbackChain("ur-PK"))
        assertEquals(listOf("en"), LocaleFallback.fallbackChain("en"))
        assertEquals(listOf("es-419", "es", "en"), LocaleFallback.fallbackChain("es-419"))
        assertEquals(listOf("en"), LocaleFallback.fallbackChain("!!!"))
    }

    @Test
    fun `resolve walks the chain`() {
        val supported = setOf("en", "es", "es-419", "ar")
        assertEquals("es", LocaleFallback.resolve("es-MX", supported))
        assertEquals("en", LocaleFallback.resolve("pt-BR", supported))
        assertEquals("ar", LocaleFallback.resolve("ar-EG", supported))
    }

    @Test
    fun `RTL metadata covers Arabic Urdu and Persian`() {
        for (tag in listOf("ar", "ar-EG", "ur", "ur-PK", "fa", "he", "ps", "ug")) {
            assertTrue("$tag should resolve RTL", LocaleFallback.isRTL(tag))
        }
        for (tag in listOf("en", "tr", "ru", "kk", "id", "fr", "hi", "bn")) {
            assertFalse("$tag should resolve LTR", LocaleFallback.isRTL(tag))
        }
    }

    @Test
    fun `pseudolocales resolve without crashing`() {
        assertEquals("en-XA", LocaleFallback.canonicalizeLocaleTag("en-XA"))
        assertEquals("ar-XB", LocaleFallback.canonicalizeLocaleTag("ar-XB"))
        assertFalse(LocaleFallback.isRTL("en-XA"))
        assertTrue(LocaleFallback.isRTL("ar-XB"))
        assertEquals("en", LocaleFallback.resolve("en-XA", setOf("en")))
        assertEquals(listOf("zz-QU", "zz", "en"), LocaleFallback.fallbackChain("zz-QU"))
    }
}
