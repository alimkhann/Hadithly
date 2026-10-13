package com.hadithly.app.core.analytics

class ReaderMeasurement {
    var started = false; private set
    var rendered = false; private set
    private var failed = false
    private var closed = false
    private var targetSettled = false
    private var guest = true
    private var restoration = false
    private var notification = false
    fun begin(guest: Boolean, restoration: Boolean, notification: Boolean): List<AnalyticsMetric> {
        if (started) return emptyList()
        started = true; this.guest = guest; this.restoration = restoration; this.notification = notification
        return buildList {
            add(if (guest) AnalyticsMetric.readerOpenResultGuestStarted else AnalyticsMetric.readerOpenResultAccountStarted)
            if (restoration) add(AnalyticsMetric.restorationResultStarted)
            if (notification) add(AnalyticsMetric.notificationOpenResultStarted)
        }
    }
    fun failure(): List<AnalyticsMetric> {
        if (!started || closed || failed) return emptyList()
        failed = true
        return if (rendered) listOf(AnalyticsMetric.recoverableErrorReader)
            else listOf(AnalyticsMetric.readerOpenResultFailed, AnalyticsMetric.recoverableErrorReader)
    }
    fun visible(offline: Boolean): List<AnalyticsMetric> {
        if (!started || closed) return emptyList()
        return buildList {
            if (!rendered) {
                if (failed) add(if (guest) AnalyticsMetric.readerOpenResultGuestStarted else AnalyticsMetric.readerOpenResultAccountStarted)
                add(if (guest) { if (offline) AnalyticsMetric.readerOpenResultGuestOffline else AnalyticsMetric.readerOpenResultGuestOnline }
                    else { if (offline) AnalyticsMetric.readerOpenResultAccountOffline else AnalyticsMetric.readerOpenResultAccountOnline })
                rendered = true
            }
            if (failed) { add(AnalyticsMetric.recoverableErrorReaderRecovered); failed = false }
        }
    }
    fun settleTarget(exact: Boolean): List<AnalyticsMetric> {
        if (!started || closed || targetSettled) return emptyList()
        targetSettled = true
        return buildList {
            if (restoration) add(if (exact) AnalyticsMetric.restorationResultExact else AnalyticsMetric.restorationResultFallback)
            if (notification) add(if (exact) AnalyticsMetric.notificationOpenResultExact else AnalyticsMetric.notificationOpenResultFallback)
        }
    }
    fun close(): List<AnalyticsMetric> {
        if (!started || closed) return emptyList()
        val facts = if (failed && !rendered && !targetSettled) {
            targetSettled = true
            mutableListOf<AnalyticsMetric>().apply {
                if (restoration) add(AnalyticsMetric.restorationResultFailed)
                if (notification) add(AnalyticsMetric.notificationOpenResultFailed)
            }
        } else settleTarget(false).toMutableList()
        if (!rendered && !failed) facts.add(AnalyticsMetric.readerOpenResultAbandoned)
        closed = true
        return facts
    }
}
