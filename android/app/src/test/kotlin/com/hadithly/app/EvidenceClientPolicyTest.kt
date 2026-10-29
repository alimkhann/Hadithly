package com.hadithly.app

import com.hadithly.app.core.data.EvidenceClientPolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EvidenceClientPolicyTest {
    @Test fun progressKeepsWholePercentTruncationInEveryLocale() {
        for (tag in listOf("en", "ar", "ru", "kk", "ky", "uz", "tr", "id", "ur", "fr", "es-419", "pt-BR", "sw", "hi", "bn")) {
            val locale = java.util.Locale.forLanguageTag(tag)
            val formatter = java.text.NumberFormat.getPercentInstance(locale).apply { maximumFractionDigits = 0 }
            for ((value, percent) in listOf(0.0 to 0, 0.001 to 0, 0.429 to 42, 0.999 to 99, 1.0 to 100)) {
                assertEquals(formatter.format(percent / 100.0), com.hadithly.app.features.reader.evidenceUploadProgressLabel(value, locale))
            }
        }
    }

    @Test fun fileSizeAndHttpsPreflightBoundaries() {
        assertFalse(EvidenceClientPolicy.acceptsFileSize(0))
        assertTrue(EvidenceClientPolicy.acceptsFileSize(10_000_000))
        assertFalse(EvidenceClientPolicy.acceptsFileSize(10_000_001))
        assertEquals("example.org", EvidenceClientPolicy.httpsURL(" https://example.org/source ")?.host)
        listOf("http://example.org", "https://user:password@example.org", "https:/source").forEach {
            assertNull(EvidenceClientPolicy.httpsURL(it))
        }
    }
}
