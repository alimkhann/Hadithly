package com.hadithly.app

import com.hadithly.app.core.preferences.ReaderAutomaticTranslationLedger
import org.junit.Assert.*
import org.junit.Test

class ReaderAutomaticTranslationTest {
    @Test fun requestsArePerLocaleAndDoNotReplaceAvailablePendingOrFailedText() {
        val requests = ReaderAutomaticTranslationLedger()
        assertFalse(requests.claim("1", "en", true, false))
        assertFalse(requests.claim("1", "ru", false, true))
        assertTrue(requests.claim("1", "ru", false, false))
        assertFalse(requests.claim("1", "ru", false, false))
        assertTrue(requests.claim("1", "kk", false, false))
        requests.reset()
        assertTrue(requests.claim("1", "ru", false, false))
    }
}
