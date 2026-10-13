package com.hadithly.app
import com.hadithly.app.core.analytics.AnalyticsMetric
import com.hadithly.app.core.analytics.ReaderMeasurement
import org.junit.Assert.*
import org.junit.Test

class ReaderMeasurementTest {
    @Test fun closingPendingWorkIsAbandonmentAndCannotBecomeAnError() {
        val measurement = ReaderMeasurement()
        measurement.begin(true, false, false)
        assertEquals(listOf(AnalyticsMetric.readerOpenResultAbandoned), measurement.close())
        assertTrue(measurement.failure().isEmpty())
        val failedTarget = ReaderMeasurement()
        failedTarget.begin(true, true, true); failedTarget.failure()
        assertEquals(listOf(AnalyticsMetric.restorationResultFailed, AnalyticsMetric.notificationOpenResultFailed), failedTarget.close())
    }
    @Test fun recoveryIsSeparateAndAnInitialFallbackCannotBecomeExactLater() {
        val measurement = ReaderMeasurement()
        measurement.begin(true, true, true)
        assertEquals(listOf(AnalyticsMetric.readerOpenResultFailed, AnalyticsMetric.recoverableErrorReader), measurement.failure())
        assertTrue(measurement.failure().isEmpty())
        assertEquals(listOf(AnalyticsMetric.readerOpenResultGuestStarted, AnalyticsMetric.readerOpenResultGuestOnline, AnalyticsMetric.recoverableErrorReaderRecovered), measurement.visible(false))
        assertEquals(listOf(AnalyticsMetric.restorationResultFallback, AnalyticsMetric.notificationOpenResultFallback), measurement.settleTarget(false))
        assertTrue(measurement.settleTarget(true).isEmpty())
        assertEquals(listOf(AnalyticsMetric.recoverableErrorReader), measurement.failure())
        assertEquals(listOf(AnalyticsMetric.recoverableErrorReaderRecovered), measurement.visible(true))
    }
}
