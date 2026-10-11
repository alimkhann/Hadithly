package com.hadithly.app

import com.hadithly.app.core.data.TranslationAllowance
import com.hadithly.app.core.data.TranslationFailure
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class TranslationQ1Test {
    @Test fun onlyQuotaErrorMapsToPaywallAndRateErrorPreservesRetryTime() {
        assertEquals(TranslationFailure.QuotaExceeded, TranslationFailure.of("AI_GENERATION_QUOTA_EXCEEDED"))
        listOf("AI_RATE_LIMITED", "AI_GENERATION_BUSY", "AI_INTEGRITY_REJECTED", "AI_SERVICE_LIMIT", "AI_GENERATION_RETRY").forEach { code ->
            val failure = TranslationFailure.of("{\"code\":\"$code\",\"retryAt\":1800000000000}")
            assertNotEquals(TranslationFailure.QuotaExceeded, failure)
            assertEquals(1_800_000_000_000.0, failure.retryAt)
        }
    }
    @Test fun allowanceDecodesConvexNumbersAndOptionalRetry() {
        val allowance = Json.decodeFromString<TranslationAllowance>("""{"limit":5.0,"remaining":0.0,"retryAt":1800000000000.0}""")
        assertEquals(0.0, allowance.remaining, 0.0)
        assertEquals(1_800_000_000_000.0, allowance.retryAt)
    }
}
