package com.hadithly.app.core.analytics

import android.content.SharedPreferences
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import org.json.JSONObject
import okhttp3.Call
import okhttp3.Callback
import okhttp3.CookieJar
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import java.util.UUID

class UsageStatistics(private val prefs: SharedPreferences, cloudURL: String, private val scope: CoroutineScope,
                      private val now: () -> Long = System::currentTimeMillis,
                      private val transport: ((String, ByteArray) -> Int)? = null) {
    private val _sharing = MutableStateFlow(runCatching { prefs.getBoolean("analytics.sharing", true) }.getOrDefault(false))
    val sharing: StateFlow<Boolean> = _sharing
    private val endpoint = cloudURL.trimEnd('/').takeIf { it.startsWith("https://") && it.endsWith(".convex.cloud") }
        ?.removeSuffix(".convex.cloud")?.plus(".convex.site/analytics/summary")
    private var job: Job? = null
    private var revision = 0
    private var onboarding = false
    private var firstReader = false
    private var firstReaderDeadline = 0L
    private val recoveryDeadlines = mutableMapOf<AnalyticsMetric, Long>()
    private var paywallStage = -1
    private var paywallHour = 0L
    private var paywallDeadline = 0L
    private var funnelStage = -1
    private var funnelHour = 0L
    private var funnelDeadline = 0L
    private var activeCall: Call? = null
    private val client = OkHttpClient.Builder().cookieJar(CookieJar.NO_COOKIES)
        .followRedirects(false).followSslRedirects(false).retryOnConnectionFailure(false).callTimeout(3, TimeUnit.SECONDS).build()
    private var state = runCatching {
        val raw = prefs.getString("analytics.counts.v1", "{}") ?: "{}"
        require(raw.toByteArray().size <= 16_384)
        JSONObject(raw).also { restored ->
            require(restored.optInt("admitted") in 0..40 && restored.optLong("day") >= 0 && restored.optLong("hour") in 0..now() / 3_600_000)
            val counts = restored.optJSONObject("counts") ?: JSONObject()
            var total = 0
            counts.keys().forEach { key ->
                require(AnalyticsMetric.entries.any { it.wire == key } && counts.optInt(key) in 1..40); total += counts.getInt(key)
            }
            require(total <= 40)
            val queue = restored.optJSONArray("queue") ?: JSONArray()
            require(queue.length() <= 3)
            for (index in 0 until queue.length()) {
                val item = queue.getJSONObject(index)
                require(item.getInt("attempts") in 0..3 && validatedPayload(item.getJSONObject("summary"), now()) != null)
            }
        }
    }.getOrDefault(JSONObject())
    var clipped = 0; private set
    init { expire() }
    @Synchronized fun setSharing(enabled: Boolean) {
        _sharing.value = enabled; clearPending()
        prefs.edit().putBoolean("analytics.sharing", enabled).remove("analytics.counts.v1").commit()
    }
    @Synchronized fun clearPending() {
        revision++; job?.cancel(); activeCall?.cancel(); activeCall = null
        job = null; onboarding = false; firstReader = false
        funnelStage = -1; paywallStage = -1; recoveryDeadlines.clear()
        state.remove("counts"); state.remove("queue"); prefs.edit().remove("analytics.counts.v1").apply()
    }
    @Synchronized fun record(metric: AnalyticsMetric) {
        if (!_sharing.value) return
        data class Recovery(val failure: AnalyticsMetric, val error: AnalyticsMetric, val successes: Set<AnalyticsMetric>, val recovered: AnalyticsMetric)
        val recoveries = listOf(
            Recovery(AnalyticsMetric.offlineActivationResultFailed, AnalyticsMetric.recoverableErrorOffline, setOf(AnalyticsMetric.offlineActivationResultActivated, AnalyticsMetric.offlineActivationResultUpdated), AnalyticsMetric.recoverableErrorOfflineRecovered),
            Recovery(AnalyticsMetric.translationResultFailed, AnalyticsMetric.recoverableErrorTranslation, setOf(AnalyticsMetric.translationResultCache, AnalyticsMetric.translationResultGenerated), AnalyticsMetric.recoverableErrorTranslationRecovered),
            Recovery(AnalyticsMetric.onboardingStepAuthFailed, AnalyticsMetric.recoverableErrorAuthentication, setOf(AnalyticsMetric.onboardingCompletedAccountNew, AnalyticsMetric.onboardingCompletedAccountExisting, AnalyticsMetric.onboardingCompletedAccountUnknown), AnalyticsMetric.recoverableErrorAuthenticationRecovered),
            Recovery(AnalyticsMetric.purchaseResultFailed, AnalyticsMetric.recoverableErrorPurchase, setOf(AnalyticsMetric.purchaseResultConfirmed, AnalyticsMetric.purchaseResultRestoreConfirmed), AnalyticsMetric.recoverableErrorPurchaseRecovered))
        for (recovery in recoveries) {
            if (metric == recovery.failure || recovery.failure == AnalyticsMetric.purchaseResultFailed && metric == AnalyticsMetric.purchaseResultRestoreFailed) {
                add(recovery.error, now() / 3_600_000); if (state.optInt("admitted") < 40) recoveryDeadlines[recovery.error] = now() + 1_800_000
            } else if (metric in recovery.successes) {
                recoveryDeadlines.remove(recovery.error)?.let { if (now() <= it) add(recovery.recovered, now() / 3_600_000) }
            } else if (metric == recovery.recovered) recoveryDeadlines.remove(recovery.error)
        }
        val paywallStages = setOf(AnalyticsMetric.paywallResultShown, AnalyticsMetric.paywallResultAvailable,
            AnalyticsMetric.paywallResultPurchaseStarted, AnalyticsMetric.paywallResultConfirmed, AnalyticsMetric.paywallResultDismissed)
        if (metric in paywallStages) {
            if (metric == AnalyticsMetric.paywallResultShown && (paywallStage == -1 || paywallStage == 3 || now() > paywallDeadline)) {
                paywallStage = 0; paywallHour = now() / 3_600_000; paywallDeadline = now() + 1_800_000
                add(metric, paywallHour)
            } else if (now() <= paywallDeadline) {
                when {
                    metric == AnalyticsMetric.paywallResultAvailable && paywallStage == 0 -> { paywallStage = 1; add(metric, paywallHour) }
                    metric == AnalyticsMetric.paywallResultPurchaseStarted && paywallStage == 1 -> { paywallStage = 2; add(metric, paywallHour) }
                    metric == AnalyticsMetric.paywallResultConfirmed && paywallStage == 2 -> { paywallStage = 3; add(metric, paywallHour) }
                    metric == AnalyticsMetric.paywallResultDismissed && paywallStage in 0..2 -> { paywallStage = -1; add(metric, paywallHour) }
                }
            }
            return
        }
        val stepViews = setOf(AnalyticsMetric.onboardingStepWelcomeViewed, AnalyticsMetric.onboardingStepLanguageViewed,
            AnalyticsMetric.onboardingStepDemoViewed, AnalyticsMetric.onboardingStepEntryViewed)
        if (metric !in stepViews) add(metric, now() / 3_600_000)
        if (metric == AnalyticsMetric.onboardingStepWelcomeViewed && funnelStage == -1) {
            funnelStage = 0; funnelHour = now() / 3_600_000; funnelDeadline = now() + 1_800_000
            add(AnalyticsMetric.onboardingStepOrderedStarted, funnelHour)
        }
        if (now() > funnelDeadline) return
        when {
            metric == AnalyticsMetric.onboardingStepLanguageViewed && funnelStage == 0 -> { funnelStage = 1; add(AnalyticsMetric.onboardingStepOrderedLanguage, funnelHour) }
            metric == AnalyticsMetric.onboardingStepDemoViewed && funnelStage == 1 -> { funnelStage = 2; add(AnalyticsMetric.onboardingStepOrderedDemo, funnelHour) }
            metric == AnalyticsMetric.onboardingStepEntryViewed && funnelStage == 2 -> { funnelStage = 3; add(AnalyticsMetric.onboardingStepOrderedEntry, funnelHour) }
            metric in listOf(AnalyticsMetric.onboardingCompletedGuest, AnalyticsMetric.onboardingCompletedAccountNew, AnalyticsMetric.onboardingCompletedAccountExisting) && funnelStage == 3 -> { funnelStage = 4; add(AnalyticsMetric.onboardingStepOrderedCompleted, funnelHour) }
            metric == AnalyticsMetric.onboardingCompletedFirstReaderSuccess && funnelStage == 4 -> { funnelStage = 5; add(AnalyticsMetric.onboardingStepOrderedFirstReader, funnelHour) }
        }
    }
    private fun add(metric: AnalyticsMetric, hour: Long) {
        if (!_sharing.value) return
        expire()
        val admitted = state.optInt("admitted")
        if (admitted >= 39) {
            clipped++; funnelStage = -2; paywallStage = -2; recoveryDeadlines.clear()
            if (admitted == 39) {
                state.put("admitted", 40)
                val counts = state.optJSONObject("counts") ?: JSONObject()
                if (counts.length() == 0) state.put("hour", hour)
                counts.put(AnalyticsMetric.recoverableErrorMeasurementClipped.wire, counts.optInt(AnalyticsMetric.recoverableErrorMeasurementClipped.wire) + 1)
                state.put("counts", counts); persist()
            }
            return
        }
        if ((state.optJSONObject("counts")?.length() ?: 0) > 0 && state.optLong("hour") != hour) {
            freezeCounters()
            if ((state.optJSONObject("counts")?.length() ?: 0) > 0) { clipped++; return }
        }
        state.put("admitted", admitted + 1)
        val counts = state.optJSONObject("counts") ?: JSONObject()
        if (counts.length() == 0) state.put("hour", hour)
        counts.put(metric.wire, counts.optInt(metric.wire) + 1); state.put("counts", counts); persist()
    }
    @Synchronized fun startOnboarding() { if (_sharing.value) onboarding = true }
    @Synchronized fun completeOnboarding(metric: AnalyticsMetric) { record(metric); firstReader = onboarding; firstReaderDeadline = now() + 1_800_000; onboarding = false; flush() }
    @Synchronized fun firstReaderSucceeded() {
        if (firstReader && now() <= firstReaderDeadline) record(AnalyticsMetric.onboardingCompletedFirstReaderSuccess)
        firstReader = false
        flush()
    }
    @Synchronized fun flush() {
        expire()
        val target = endpoint ?: return
        if (!_sharing.value || job != null) return
        freezeCounters()
        val queue = state.optJSONArray("queue") ?: return
        if (queue.length() == 0) return
        val pending = queue.getJSONObject(0)
        val attempt = pending.optInt("attempts") + 1
        if (attempt > 3) { queue.remove(0); persist(); return }
        val body = validatedPayload(pending.getJSONObject("summary"), now()) ?: run { queue.remove(0); persist(); return }
        pending.put("attempts", attempt); persist()
        val capturedRevision = revision
        job = scope.launch(Dispatchers.IO) {
            if (attempt > 1) delay(attempt * 5000L + kotlin.random.Random.nextLong(2000))
            synchronized(this@UsageStatistics) {
                if (!_sharing.value || revision != capturedRevision) return@launch
                expire()
                if (state.optJSONArray("queue")?.optJSONObject(0)?.optJSONObject("summary")?.optString("batchId") != pending.getJSONObject("summary").getString("batchId")) {
                    job = null; flush(); return@launch
                }
            }
            val status = if (transport != null) runCatching { transport.invoke(target, body) }.getOrDefault(0)
                else send(target, body, capturedRevision)
            synchronized(this@UsageStatistics) {
                if (revision != capturedRevision || !_sharing.value) return@launch
                job = null
                val current = state.optJSONArray("queue")
                if (current?.optJSONObject(0)?.optJSONObject("summary")?.optString("batchId") != pending.getJSONObject("summary").getString("batchId")) { flush(); return@launch }
                if (status == 204 || status in 400..499 && status != 429 || attempt == 3) current.remove(0)
                persist()
                if (current.length() > 0 || (state.optJSONObject("counts")?.length() ?: 0) > 0) flush()
            }
        }
    }
    private fun freezeCounters() {
        val queue = state.optJSONArray("queue") ?: JSONArray().also { state.put("queue", it) }
        val counts = state.optJSONObject("counts") ?: return
        while (queue.length() < 3 && counts.length() > 0) {
            val counters = JSONArray()
            var budget = 40
            counts.keys().asSequence().toList().sorted().take(32).forEach { key ->
                if (budget > 0 && AnalyticsMetric.entries.any { it.wire == key }) {
                    val count = counts.optInt(key); val accepted = minOf(count, budget); budget -= accepted
                    counters.put(JSONObject().put("metric", key).put("count", accepted))
                    if (count > accepted) counts.put(key, count - accepted) else counts.remove(key)
                }
            }
            if (counters.length() == 0) return
            val pending = JSONObject().put("attempts", 0).put("summary", JSONObject().put("version", 1).put("platform", "android")
                .put("batchId", UUID.randomUUID().toString()).put("hour", state.optLong("hour")).put("counters", counters))
            queue.put(pending)
        }
    }
    private fun expire() {
        val hour = now() / 3_600_000; val day = hour / 24
        if (state.optLong("hour") + 24 <= hour || state.optLong("hour") > hour) state.remove("counts")
        val queue = state.optJSONArray("queue")
        if (queue != null) for (i in (queue.length() - 1) downTo 0) {
            val pending = queue.optJSONObject(i); val created = pending?.optJSONObject("summary")?.optLong("hour") ?: 0
            if (created + 24 <= hour || created > hour || pending?.optInt("attempts") == 3 && job == null) queue.remove(i)
        }
        if (state.optLong("day") != day) {
            freezeCounters()
            state.optJSONObject("counts")?.let { counts -> if (counts.length() > 0) {
                clipped += counts.keys().asSequence().sumOf { counts.optInt(it) }; state.remove("counts")
            } }
            state.put("day", day); state.put("admitted", 0)
        }
        if (!_sharing.value) { state.remove("counts"); state.remove("queue"); prefs.edit().remove("analytics.counts.v1").apply() }
        persist()
    }
    private fun persist() { if (_sharing.value) prefs.edit().putString("analytics.counts.v1", state.toString()).apply() }
    private suspend fun send(target: String, body: ByteArray, expectedRevision: Int): Int = suspendCancellableCoroutine { continuation ->
        val request = Request.Builder().url(target).post(body.toRequestBody("application/json".toMediaType())).build()
        val call = client.newCall(request)
        synchronized(this) {
            if (!_sharing.value || revision != expectedRevision) { continuation.resume(0); return@suspendCancellableCoroutine }
            activeCall = call
        }
        continuation.invokeOnCancellation { call.cancel() }
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, error: IOException) {
                synchronized(this@UsageStatistics) { if (activeCall === call) activeCall = null }
                if (continuation.isActive) continuation.resume(0)
            }
            override fun onResponse(call: Call, response: Response) {
                val status = response.use { it.code }
                synchronized(this@UsageStatistics) { if (activeCall === call) activeCall = null }
                if (continuation.isActive) continuation.resume(status)
            }
        })
    }
    companion object {
        fun validatedPayload(summary: JSONObject, now: Long): ByteArray? = runCatching {
            require(summary.keys().asSequence().toSet() == setOf("version", "platform", "batchId", "hour", "counters"))
            require(summary.get("version") == 1 && summary.get("platform") == "android")
            require(summary.getString("batchId").matches(Regex("[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}")))
            val hour = summary.get("hour") as Number
            require(hour.toDouble() == hour.toLong().toDouble() && hour.toLong() <= now / 3_600_000 && (hour.toLong() + 24) * 3_600_000 > now)
            val counters = summary.getJSONArray("counters"); require(counters.length() in 1..32)
            val seen = mutableSetOf<String>(); var total = 0
            for (i in 0 until counters.length()) {
                val item = counters.getJSONObject(i)
                require(item.keys().asSequence().toSet() == setOf("metric", "count"))
                val metric = item.getString("metric"); require(AnalyticsMetric.entries.any { it.wire == metric } && seen.add(metric))
                val count = item.get("count") as Number
                require(count.toDouble() == count.toInt().toDouble() && count.toInt() in 1..40); total += count.toInt()
            }
            require(total <= 40)
            summary.toString().toByteArray(Charsets.UTF_8).also { require(it.size <= 4096) }
        }.getOrNull()
    }
}
