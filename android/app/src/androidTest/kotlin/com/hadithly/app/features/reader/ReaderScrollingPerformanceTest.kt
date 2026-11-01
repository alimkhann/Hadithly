package com.hadithly.app.features.reader

import android.content.ComponentName
import android.content.Intent
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.CompositionLocalProvider
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import com.hadithly.app.HadithlyApplication
import com.hadithly.app.core.data.*
import com.hadithly.app.core.preferences.ReaderTheme
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import org.junit.Assert.*
import org.junit.Test

class ReaderScrollingPerformanceTest {
    @Test fun loadedProductionReaderScrollingPerformance() {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        assertNull("Guest-only controlled workload", com.clerk.api.Clerk.user)
        val original = app.preferences.preferences.value
        val directory = java.io.File(app.cacheDir, "scroll-workload-" + System.nanoTime()).apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val owner = object : ViewModelStoreOwner { override val viewModelStore = ViewModelStore() }
        val library = UserLibraryModel(GuestDataStore(context), scope)
        val requests = java.util.concurrent.atomic.AtomicInteger()
        val metrics = java.util.Collections.synchronizedList(mutableListOf<LongArray>())
        val recording = java.util.concurrent.atomic.AtomicBoolean(false)
        val dropped = java.util.concurrent.atomic.AtomicInteger()
        val worker = android.os.HandlerThread("reader-scroll-metrics").apply { start() }
        var window: android.view.Window? = null
        lateinit var model: ReaderViewModel
        val listener = android.view.Window.OnFrameMetricsAvailableListener { _, frame, lost ->
            if (recording.get()) {
                metrics.add(longArrayOf(
                    frame.getMetric(android.view.FrameMetrics.TOTAL_DURATION),
                    if (android.os.Build.VERSION.SDK_INT >= 31) frame.getMetric(android.view.FrameMetrics.DEADLINE) else -1,
                    frame.getMetric(android.view.FrameMetrics.LAYOUT_MEASURE_DURATION),
                    frame.getMetric(android.view.FrameMetrics.DRAW_DURATION),
                    frame.getMetric(android.view.FrameMetrics.UNKNOWN_DELAY_DURATION),
                    if (android.os.Build.VERSION.SDK_INT >= 31) frame.getMetric(android.view.FrameMetrics.GPU_DURATION) else -1,
                ))
                dropped.addAndGet(lost)
            }
        }
        val intent = Intent().setComponent(ComponentName(app.packageName, ComponentActivity::class.java.name))
        val scenario = ActivityScenario.launch<ComponentActivity>(intent)
        scenario.onActivity {
            app.preferences.adoptServer(com.hadithly.app.core.preferences.ReaderPreferences(
                uiLocale = "en", translationLocale = "en", appTheme = ReaderTheme.DARK,
                arabicFontSize = 26f, translationFontSize = 16f, updatedAt = original.updatedAt + 1,
            ))
            val first = page("57").items.single().copy(
                arabicText = "نَصّ الحديث الأول ".repeat(180), englishText = "Deeds are judged by intentions.",
            )
            val second = page("58").items.single().copy(arabicText = "نَصّ الحديث الثاني", englishText = "Faith has many branches.")
            val loaded = ReaderPageResult(listOf(first, second), page = 1.0, pageSize = 10.0, totalPages = 1.0, hasMore = false)
            model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION,
                library = library,
                outlineLoader = { CollectionOutlineResult(listOf(OutlineVolume("1", "Loaded scrolling workload", hadithCount = 2.0))) },
                pageLoader = { _, _, _ -> requests.incrementAndGet(); loaded })
            owner.viewModelStore.put("reader-57", model)
        }
        try {
            scenario.onActivity { activity ->
                window = activity.window
                activity.setContent {
                    CompositionLocalProvider(LocalViewModelStoreOwner provides owner) {
                        com.hadithly.app.core.theme.LocalizedPreview(ReaderTheme.DARK, "en") {
                            ReaderScreen("bukhari", "Loaded scrolling workload", null, null, null, ReaderTargetSource.COLLECTION, 57L, {})
                        }
                    }
                }
            }
            val deadline = SystemClock.uptimeMillis() + 10_000
            while (model.state.value.isLoadingPage || model.currentPageHadiths().size != 2 || model.state.value.verticalLanding != null) {
                check(SystemClock.uptimeMillis() < deadline) { "Reader did not settle" }
                SystemClock.sleep(20)
            }
            SystemClock.sleep(750)
            val measuredWindow = checkNotNull(window)
            var width = 0
            var height = 0
            var before = 0.0
            scenario.onActivity {
                width = measuredWindow.decorView.width
                height = measuredWindow.decorView.height
                before = -(library.progressFor("bukhari")?.position?.rawPageOffset ?: 0.0)
                measuredWindow.addOnFrameMetricsAvailableListener(listener, android.os.Handler(worker.looper))
            }
            val instrumentation = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
            fun shell(command: String): String = android.os.ParcelFileDescriptor.AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand(command)).use { it.readBytes().toString(Charsets.UTF_8) }
            shell("screencap -p /data/local/tmp/reader-scroll-before.png")
            println("READER_SCROLL viewport=${width}x$height before=$before hardware=${measuredWindow.decorView.isHardwareAccelerated}")
            shell("dumpsys gfxinfo ${instrumentation.targetContext.packageName} reset")
            val started = android.os.SystemClock.elapsedRealtimeNanos()
            recording.set(true)
            repeat(3) {
                val command = "input swipe ${width / 2} ${(height * .6f).toInt()} ${width / 2} ${(height * .15f).toInt()} 500"
                assertEquals("Touch injection must succeed", "", shell(command).trim())
                android.os.SystemClock.sleep(500)
            }
            recording.set(false)
            val elapsed = android.os.SystemClock.elapsedRealtimeNanos() - started
            var after = 0.0
            scenario.onActivity {
                model.saveCurrentProgress()
                after = -(library.progressFor("bukhari")?.position?.rawPageOffset ?: 0.0)
            }
            shell("screencap -p /data/local/tmp/reader-scroll-after.png")
            val dumpFile = java.io.File(instrumentation.targetContext.getExternalFilesDir(null), "reader-scroll-framestats.txt")
            dumpFile.writeText(shell("dumpsys gfxinfo ${instrumentation.targetContext.packageName} framestats"))
            shell("cp ${dumpFile.absolutePath} /data/local/tmp/reader-scroll-framestats.txt")
            assertTrue("The workload must actually scroll: $before / $after", after < before - 100)
            assertEquals("Vertical scrolling must retain the page", 0, model.state.value.pageIndex)
            assertEquals("Loaded scrolling must not fetch more pages", 1, requests.get())
            assertTrue("Frame timing must be available", metrics.size >= 10)
            val json = org.json.JSONObject().apply {
                put("sdk", android.os.Build.VERSION.SDK_INT); put("deviceModel", android.os.Build.MODEL)
                put("hardwareAccelerated", measuredWindow.decorView.isHardwareAccelerated)
                put("refreshRateHz", measuredWindow.decorView.display.refreshRate)
                put("elapsedNanos", elapsed); put("droppedReports", dropped.get()); put("pageRequests", requests.get())
                put("arabicFontSize", 26); put("translationFontSize", 16); put("translationLocale", "en")
                put("arabicTopBefore", before); put("arabicTopAfter", after)
                put("columns", org.json.JSONArray(listOf("totalNanos", "deadlineNanos", "layoutNanos", "drawNanos", "unknownDelayNanos", "gpuNanos")))
                put("frames", org.json.JSONArray(metrics.map { org.json.JSONArray(it.toList()) }))
            }
            val file = java.io.File(instrumentation.targetContext.getExternalFilesDir(null), "reader-scroll-metrics.json")
            file.writeText(json.toString(2))
            android.os.ParcelFileDescriptor.AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand("cp ${file.absolutePath} /data/local/tmp/reader-scroll-metrics.json")).use { it.readBytes() }
        } finally {
            recording.set(false)
            window?.let { measured -> scenario.onActivity { measured.removeOnFrameMetricsAvailableListener(listener) } }
            worker.quitSafely()
            scenario.onActivity {
                owner.viewModelStore.clear()
                app.preferences.adoptServer(original.copy(updatedAt = app.preferences.preferences.value.updatedAt + 1))
            }
            scenario.close()
            scope.cancel()
            directory.deleteRecursively()
        }
    }

    private fun page(number: String, more: Boolean = false) = ReaderPageResult(
        items = listOf(ReaderHadith("fixture-$number", "sunnah_now", "sunnah_now:bukhari:$number", number, "bukhari", "1",
            arabicText = "نص تجريبي %@", englishText = "Controlled original %@ text $number", referenceDisplay = "Original %@ $number",
            collectionName = "Original %@ مصدر", authenticity = AuthenticityClaim("unknown", claimScope = "hadith", sourceLabel = "Original %@", sourceName = "Fixture", sourceUrl = "", verificationMethod = "fixture"))),
        page = if (number == "57") 3.0 else if (number == "2") 2.0 else 1.0, pageSize = 1.0, totalPages = 3.0, hasMore = more,
    )
}
