package com.hadithly.app

import com.hadithly.app.core.data.EvidenceClientPolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EvidenceClientPolicyTest {
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
