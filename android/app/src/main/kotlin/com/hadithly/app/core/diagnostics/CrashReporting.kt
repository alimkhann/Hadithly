package com.hadithly.app.core.diagnostics

import android.content.Context
import com.hadithly.app.BuildConfig
import io.sentry.Sentry
import io.sentry.SentryEvent
import io.sentry.SentryLevel
import io.sentry.android.core.SentryAndroid
import io.sentry.protocol.Mechanism
import io.sentry.protocol.SentryException
import io.sentry.protocol.SentryStackFrame
import io.sentry.protocol.SentryStackTrace
import io.sentry.protocol.DebugImage
import io.sentry.protocol.DebugMeta
import java.io.File

enum class DiagnosticFailure(val code: String) { OfflineManifest("offline_manifest"), Synthetic("synthetic") }

object CrashReporting {
    private var context: Context? = null
    private var running = false
    val hasConsent: Boolean get() = preferences()?.getBoolean("consent", true) == true
    private fun preferences() = context?.getSharedPreferences("diagnostics", Context.MODE_PRIVATE)
    private fun cache() = context?.let { File(it.cacheDir, "HadithlyDiagnostics") }

    fun initialize(appContext: Context) {
        context = appContext.applicationContext
        if (!hasConsent) { cache()?.deleteRecursively(); return }
        start()
    }

    @Synchronized fun setConsent(enabled: Boolean) {
        if (preferences()?.edit()?.putBoolean("consent", enabled)?.commit() != true) return
        if (enabled) start()
        else { Sentry.close(); running = false; cache()?.deleteRecursively() }
    }

    private fun start() {
        val appContext = context ?: return
        if (running || !BuildConfig.DIAGNOSTICS_DSN.startsWith("https://")) return
        cache()?.walkBottomUp()?.filter { it.isFile && System.currentTimeMillis() - it.lastModified() > 7L * 86400000 }?.forEach { it.delete() }
        SentryAndroid.init(appContext) { options ->
            options.dsn = BuildConfig.DIAGNOSTICS_DSN
            options.release = DIAGNOSTICS_RELEASE
            options.environment = BuildConfig.DIAGNOSTICS_ENVIRONMENT
            options.dist = BuildConfig.VERSION_CODE.toString()
            options.cacheDirPath = cache()?.absolutePath
            options.maxCacheItems = 10
            options.maxQueueSize = 10
            options.shutdownTimeoutMillis = 0
            options.flushTimeoutMillis = 3000
            options.connectionTimeoutMillis = 3000
            options.readTimeoutMillis = 3000
            options.isSendDefaultPii = false
            options.isEnableNdk = false
            options.isTombstoneEnabled = true
            options.isAttachRawTombstone = false
            options.isAttachAnrThreadDump = false
            options.isEnableAutoSessionTracking = false
            options.isEnableScopePersistence = false
            options.isEnableAutoActivityLifecycleTracing = false
            options.isEnableUserInteractionTracing = false
            options.isEnableUserInteractionBreadcrumbs = false
            options.isEnableActivityLifecycleBreadcrumbs = false
            options.isEnableAppLifecycleBreadcrumbs = false
            options.isEnableSystemEventBreadcrumbs = false
            options.isEnableAppComponentBreadcrumbs = false
            options.isEnableNetworkEventBreadcrumbs = false
            options.isAttachScreenshot = false
            options.isAttachViewHierarchy = false
            options.isSendClientReports = false
            options.isAttachServerName = false
            options.logs.isEnabled = false
            options.metrics.isEnabled = false
            options.tracesSampleRate = 0.0
            options.sessionReplay.sessionSampleRate = 0.0
            options.sessionReplay.onErrorSampleRate = 0.0
            options.maxBreadcrumbs = 0
            options.setBeforeBreadcrumb { _, _ -> null }
            options.setBeforeSend { event, hint ->
                hint.clearAttachments()
                if (!hasConsent || !admit()) null else redacted(event)
            }
        }
        running = true
    }

    @Synchronized private fun admit(): Boolean {
        val prefs = preferences() ?: return false
        val day = System.currentTimeMillis() / 86400000
        val count = if (prefs.getLong("day", 0) == day) prefs.getInt("count", 0) else 0
        return count < 5 && prefs.edit().putLong("day", day).putInt("count", count + 1).commit()
    }

    fun failure(failure: DiagnosticFailure) {
        if (!hasConsent || !running) return
        val event = SentryEvent()
        event.level = SentryLevel.ERROR
        event.exceptions = listOf(SentryException().apply { type = "HadithlyFailure"; value = failure.code })
        event.setTag("operation", failure.code)
        Sentry.captureEvent(event)
    }

    internal fun redacted(source: SentryEvent): SentryEvent = SentryEvent().apply {
        eventId = source.eventId
        timestamp = source.timestamp
        platform = "java"
        level = if (source.level == SentryLevel.FATAL) SentryLevel.FATAL else SentryLevel.ERROR
        release = source.release?.takeIf { it.matches(Regex("hadithly@[a-f0-9]{12}")) } ?: DIAGNOSTICS_RELEASE
        environment = source.environment?.takeIf { it in listOf("development", "production") } ?: BuildConfig.DIAGNOSTICS_ENVIRONMENT
        dist = BuildConfig.VERSION_CODE.toString()
        val operation = source.getTag("operation")?.takeIf { it in listOf("synthetic", "offline_manifest") } ?: "native_crash"
        setTag("surface", "android"); setTag("operation", operation)
        exceptions = source.exceptions?.take(4)?.map { original ->
            SentryException().apply {
                type = "HadithlyNativeFailure"; value = operation
                mechanism = Mechanism().apply { type = "generic"; isHandled = original.mechanism?.isHandled ?: (level != SentryLevel.FATAL) }
                stacktrace = stack(original.stacktrace)
            }
        }
        debugMeta = source.debugMeta?.let { original ->
            DebugMeta().apply {
                images = original.images?.take(256)?.mapNotNull { image ->
                    val id = image.debugId?.takeIf { it.matches(Regex("[a-fA-F0-9-]{32,45}")) } ?: return@mapNotNull null
                    DebugImage().apply {
                        debugId = id; type = if (image.type == "elf") "elf" else "macho"
                        imageAddr = image.imageAddr?.takeIf { it.matches(Regex("0x[a-fA-F0-9]{1,16}")) }
                        imageSize = image.imageSize?.takeIf { it > 0 }
                        codeId = image.codeId?.takeIf { it.matches(Regex("[a-fA-F0-9]{8,64}")) }
                        codeFile = "binary"
                    }
                }
            }
        }
    }

    private fun stack(source: SentryStackTrace?): SentryStackTrace? = source?.let {
        SentryStackTrace(it.frames?.takeLast(128)?.map { original ->
            SentryStackFrame().apply {
                module = original.module?.takeIf { name -> name.matches(Regex("(?:com\\.hadithly\\.|java\\.|kotlin\\.|android\\.|androidx\\.|dev\\.convex\\.|io\\.sentry\\.)[A-Za-z0-9_.$]{1,200}")) }
                function = original.function?.takeIf { name -> name.matches(Regex("[A-Za-z_$<>][A-Za-z0-9_$<>]{0,120}")) }
                filename = original.filename?.takeIf { name -> name.matches(Regex("[A-Za-z0-9_.$-]{1,120}\\.(?:kt|java)")) }
                lineno = original.lineno?.takeIf { line -> line in 1..100000 }
                isInApp = original.isInApp
                instructionAddr = original.instructionAddr?.takeIf { address -> address.matches(Regex("0x[a-fA-F0-9]{1,16}")) }
                imageAddr = original.imageAddr?.takeIf { address -> address.matches(Regex("0x[a-fA-F0-9]{1,16}")) }
            }
        }.orEmpty())
    }
}
