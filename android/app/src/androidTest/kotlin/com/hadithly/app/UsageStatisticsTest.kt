package com.hadithly.app

import androidx.test.platform.app.InstrumentationRegistry
import com.hadithly.app.core.analytics.AnalyticsMetric
import com.hadithly.app.core.analytics.UsageStatistics
import com.hadithly.app.core.analytics.ReaderMeasurement
import com.hadithly.app.core.preferences.PreferencesStore
import kotlinx.coroutines.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

class UsageStatisticsTest {
    @Test fun developmentNativeTransportFixture() = runBlocking {
        org.junit.Assume.assumeTrue(InstrumentationRegistry.getArguments().getString("la2Live") == "1")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        repeat(5) {
            val prefs = context.getSharedPreferences("la2-live-" + UUID.randomUUID(), 0)
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
            try {
                val store = UsageStatistics(prefs, "https://festive-cobra-664.eu-west-1.convex.cloud", scope)
                suspend fun waitForUpload() {
                    withTimeout(10_000) { while (JSONObject(prefs.getString("analytics.counts.v1", "{}")!!).optJSONArray("queue")?.length() != 0) delay(100) }
                }
                store.startOnboarding()
                listOf(AnalyticsMetric.onboardingStepWelcomeViewed, AnalyticsMetric.onboardingStepLanguageViewed, AnalyticsMetric.onboardingStepDemoViewed,
                    AnalyticsMetric.onboardingStepDemoUsed, AnalyticsMetric.onboardingStepEntryViewed).forEach(store::record)
                store.completeOnboarding(AnalyticsMetric.onboardingCompletedGuest); waitForUpload()
                val reader = ReaderMeasurement()
                reader.begin(guest = true, restoration = true, notification = true).forEach(store::record)
                (reader.visible(offline = false) + reader.settleTarget(exact = true)).forEach(store::record)
                store.firstReaderSucceeded(); waitForUpload()
                listOf(AnalyticsMetric.offlineActivationResultStarted, AnalyticsMetric.offlineActivationResultActivated, AnalyticsMetric.translationResultStarted,
                    AnalyticsMetric.translationResultQuota, AnalyticsMetric.paywallResultShown, AnalyticsMetric.paywallResultAvailable, AnalyticsMetric.paywallResultPurchaseStarted,
                    AnalyticsMetric.purchaseResultMonthlyStarted, AnalyticsMetric.purchaseResultConfirmed, AnalyticsMetric.paywallResultConfirmed,
                    AnalyticsMetric.recoverableErrorTranslation, AnalyticsMetric.recoverableErrorTranslationRecovered).forEach(store::record)
                store.flush(); waitForUpload(); assertEquals(0, store.clipped); store.setSharing(false)
            } finally { scope.cancel(); prefs.edit().clear().commit() }
        }
    }
    @Test fun sameOperationRecoveryExpiresWithoutKeepingAnIdentity() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val prefs = context.getSharedPreferences("la2-test-" + UUID.randomUUID(), 0)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        var now = 3_600_000_000L
        try {
            val store = UsageStatistics(prefs, "invalid", scope, now = { now })
            store.record(AnalyticsMetric.translationResultFailed); store.record(AnalyticsMetric.offlineActivationResultActivated)
            store.record(AnalyticsMetric.translationResultCache)
            store.record(AnalyticsMetric.purchaseResultRestoreFailed); now += 1_801_000; store.record(AnalyticsMetric.purchaseResultRestoreConfirmed)
            val raw = prefs.getString("analytics.counts.v1", "")!!
            assertTrue(raw.contains("recoverable_error.translation_recovered")); assertFalse(raw.contains("recoverable_error.purchase_recovered"))
            store.setSharing(false); assertFalse(prefs.contains("analytics.counts.v1"))
        } finally { scope.cancel(); prefs.edit().clear().commit() }
    }
    @Test fun paywallSequenceRejectsOutOfOrderAndRepeatedStages() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val prefs = context.getSharedPreferences("la2-test-" + UUID.randomUUID(), 0)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        try {
            val store = UsageStatistics(prefs, "invalid", scope)
            store.record(AnalyticsMetric.paywallResultConfirmed)
            repeat(2) { store.record(AnalyticsMetric.paywallResultShown); store.record(AnalyticsMetric.paywallResultAvailable); store.record(AnalyticsMetric.paywallResultPurchaseStarted) }
            store.record(AnalyticsMetric.paywallResultConfirmed); store.record(AnalyticsMetric.paywallResultConfirmed)
            val counts = JSONObject(prefs.getString("analytics.counts.v1", "{}")!!).getJSONObject("counts")
            assertEquals(4, counts.length()); counts.keys().forEach { assertEquals(1, counts.getInt(it)) }
        } finally { scope.cancel(); prefs.edit().clear().commit() }
    }
    @Test fun actualSerializedSummaryAndOptOutHaveNoContentOrAccountBinding() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val prefs = context.getSharedPreferences("la2-test-" + UUID.randomUUID(), 0)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val received = CompletableDeferred<JSONObject>()
        try {
            val statistics = UsageStatistics(prefs, "https://test.convex.cloud", scope, transport = { _, bytes ->
                received.complete(JSONObject(String(bytes))); 204
            })
            statistics.record(AnalyticsMetric.readerOpenResultGuestOnline); statistics.flush()
            val body = withTimeout(3000) { received.await() }
            assertEquals(setOf("version", "platform", "batchId", "hour", "counters"), body.keys().asSequence().toSet())
            assertNotNull(UsageStatistics.validatedPayload(body, System.currentTimeMillis()))
            for (key in listOf("text", "notes", "locale", "email", "token", "canonicalId", "properties")) {
                val dirty = JSONObject(body.toString()).put(key, "PRIVATE_CANARY")
                assertNull(UsageStatistics.validatedPayload(dirty, System.currentTimeMillis()))
            }
            statistics.setSharing(false)
            assertFalse(prefs.contains("analytics.counts.v1"))
            statistics.record(AnalyticsMetric.onboardingCompletedGuest)
            assertFalse(prefs.contains("analytics.counts.v1"))
            assertFalse(UsageStatistics(prefs, "invalid", scope).sharing.value)
        } finally { scope.cancel(); prefs.edit().clear().commit() }
    }
    @Test fun expiryBudgetAndCatalogAreBounded() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val prefs = context.getSharedPreferences("la2-test-" + UUID.randomUUID(), 0)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        var now = 3_600_000_000L
        try {
            val statistics = UsageStatistics(prefs, "invalid", scope, now = { now })
            repeat(50) { statistics.record(AnalyticsMetric.restorationResultExact) }
            assertEquals(40, JSONObject(prefs.getString("analytics.counts.v1", "{}")!!).getInt("admitted"))
            assertEquals(11, statistics.clipped)
            now += 86_400_000L; statistics.flush()
            assertFalse(prefs.getString("analytics.counts.v1", "")!!.contains("restoration_result.exact"))
            statistics.clearPending(); assertFalse(prefs.contains("analytics.counts.v1"))
            assertEquals(10, AnalyticsMetric.entries.map { it.wire.substringBefore('.') }.toSet().size)
            assertEquals("kk", PreferencesStore.suggestedLanguage(listOf("de-DE", "kk-KZ", "en-US")))
        } finally { scope.cancel(); prefs.edit().clear().commit() }
    }
}
