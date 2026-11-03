package com.hadithly.app.features.reader

import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.test.core.app.ApplicationProvider
import com.hadithly.app.HadithlyApplication
import com.hadithly.app.core.data.*
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.yield
import kotlinx.coroutines.CancellationException
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class ReaderPageReuseTest {
    @get:Rule val compose = createComposeRule()

    @Test fun adjacentWarmAndForegroundShareRequest() {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val directory = java.io.File(app.cacheDir, "page-reuse-${System.nanoTime()}").apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val library = UserLibraryModel(GuestDataStore(context), scope)
        val gate = CompletableDeferred<Unit>()
        val requests = mutableListOf<String>()
        lateinit var model: ReaderViewModel
        try {
            compose.runOnUiThread {
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION,
                    library = library,
                    outlineLoader = { CollectionOutlineResult(listOf(OutlineVolume("1", "One"), OutlineVolume("2", "Two"))) },
                    pageLoader = { volume, index, _ ->
                        requests.add("$volume:$index")
                        if (volume == "2") gate.await()
                        ReaderPageResult(page = 1.0, totalPages = 1.0, pageKey = "pg1:$volume", contentVersion = "cv1:$volume")
                    })
            }
            compose.waitUntil(10_000) { requests.contains("2:0") }
            compose.runOnIdle { model.switchToVolume("2", ReaderViewModel.VolumeEdge.FIRST); gate.complete(Unit) }
            compose.waitUntil(10_000) { model.state.value.selectedVolumeId == "2" && !model.state.value.isLoadingPage && model.state.value.pages.isNotEmpty() }
            compose.runOnIdle { assertEquals(1, requests.count { it == "2:0" }) }
        } finally {
            gate.complete(Unit)
            scope.cancel()
            directory.deleteRecursively()
        }
    }
    @Test fun storeReuseBoundsAndTargetIdentity() = runBlocking {
        withContext(Dispatchers.Main.immediate) {
            val requests = mutableListOf<ReaderPageContentStore.Request>()
            val store = ReaderPageContentStore(capacity = 2) { request -> requests.add(request); page(request.index) }
            store.load(ReaderPageContentStore.Request("bukhari", "2", 0))
            store.beginReading()
            store.load(ReaderPageContentStore.Request("bukhari", "2", 0, "1"))
            assertEquals(1, requests.size)
            store.load(ReaderPageContentStore.Request("bukhari", "2", 1))
            store.load(ReaderPageContentStore.Request("bukhari", "2", 2))
            assertEquals(2, store.retainedPageCount)
            assertNull(store.peek("bukhari", "2", 0))
            store.load(ReaderPageContentStore.Request("bukhari", "2", 0))
            assertEquals(4, requests.size)
        }
    }

    @Test fun sharedFlightSurvivesOneCanceledCallerAndClearsAtBoundary() = runBlocking {
        withContext(Dispatchers.Main.immediate) {
            withTimeout(5_000) {
                val gate = CompletableDeferred<Unit>()
                var calls = 0
                val store = ReaderPageContentStore { calls++; gate.await(); page(0) }
                val request = ReaderPageContentStore.Request("bukhari", "2", 0)
                val first = async { store.load(request) }
                yield()
                val second = async { store.load(request) }
                yield()
                first.cancel()
                gate.complete(Unit)
                assertEquals(1, second.await().pageNumber)
                assertEquals(1, calls)
                val version = store.contextVersion()
                store.clear()
                try { store.load(request, expectedVersion = version); fail("Stale entry warmth must not start another fetch") } catch (_: CancellationException) { }
                assertEquals(1, calls)
                val lateGate = CompletableDeferred<Unit>()
                val lateStore = ReaderPageContentStore { lateGate.await(); page(0) }
                val late = async { runCatching { lateStore.load(request) } }
                yield()
                lateStore.clear()
                lateGate.complete(Unit)
                assertTrue(late.await().isFailure)
                assertEquals(0, lateStore.retainedPageCount)
            }
        }
    }

    @Test fun resolvedTargetAndNewerVersionCannotUseFalseOrdinalAlias() = runBlocking {
        withContext(Dispatchers.Main.immediate) {
            val gate = CompletableDeferred<Unit>()
            val store = ReaderPageContentStore { request ->
                if (request.target != null) { gate.await(); page(0).copy(contentVersion = "cv1:old") }
                else page(0).copy(contentVersion = "cv1:new")
            }
            val old = async { store.load(ReaderPageContentStore.Request("bukhari", "2", 0, "1")) }
            yield()
            store.load(ReaderPageContentStore.Request("bukhari", "2", 0))
            gate.complete(Unit)
            assertEquals("cv1:new", old.await().contentVersion)
            val targetStore = ReaderPageContentStore { page(3) }
            targetStore.load(ReaderPageContentStore.Request("bukhari", "2", 0, "4"))
            assertNull(targetStore.peek("bukhari", "2", 0))
            assertEquals(4, targetStore.load(ReaderPageContentStore.Request("bukhari", "2", 3)).pageNumber)
        }
    }

    @Test fun paginationInvalidationRetryAndCoverageAfterEviction() = runBlocking {
        withContext(Dispatchers.Main.immediate) {
            var fail = true
            var pagination = 1.0
            var calls = 0
            val store = ReaderPageContentStore(capacity = 2) { request ->
                calls++
                if (fail) { fail = false; throw java.io.IOException("Fixture failure") }
                page(request.index).copy(contentVersion = "cv1:page-${request.index}", paginationVersion = pagination)
            }
            val request = ReaderPageContentStore.Request("bukhari", "2", 0)
            try { store.load(request); fail("First request must fail") } catch (_: java.io.IOException) { }
            assertEquals(0, store.inFlightPageCount)
            for (index in 0..4) store.load(request.copy(index = index))
            assertEquals(6, calls)
            assertEquals(2, store.retainedPageCount)
            assertTrue(store.hasCompleteVolume("bukhari", "2"))
            pagination = 2.0
            store.load(request)
            assertNull(store.peek("bukhari", "2", 4))
            assertFalse(store.hasCompleteVolume("bukhari", "2"))
            assertEquals(1, store.retainedPageCount)
            val idleCalls = calls
            kotlinx.coroutines.delay(100)
            assertEquals(idleCalls, calls)
            val offline = ReaderPageContentStore { page(0).copy(contentVersion = "legacy", pageKey = "legacy") }
            offline.load(request)
            assertEquals(0, offline.retainedPageCount)
        }
    }

    @Test fun accountChangeCancelsPendingLastVolumeEdge() {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val directory = java.io.File(app.cacheDir, "page-edge-${System.nanoTime()}").apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val library = UserLibraryModel(GuestDataStore(context), scope)
        var edgeCalls = 0
        val edgeGate = CompletableDeferred<Unit>()
        lateinit var model: ReaderViewModel
        try {
            compose.runOnUiThread {
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION, library = library,
                    outlineLoader = { CollectionOutlineResult(listOf(OutlineVolume("1", "One"), OutlineVolume("2", "Two"))) },
                    pageLoader = { volume, index, _ ->
                        if (volume == "2" && index == 4) { edgeCalls++; edgeGate.await() }
                        page(index)
                    })
            }
            compose.waitUntil(10_000) { model.state.value.pages.isNotEmpty() && !model.state.value.isLoadingPage }
            compose.runOnIdle { model.switchToVolume("2", ReaderViewModel.VolumeEdge.LAST) }
            compose.waitUntil(5_000) { edgeCalls > 0 && model.state.value.pendingTurn != null }
            compose.runOnIdle {
                model.clearRecentPositions(restartLoading = true)
                edgeGate.complete(Unit)
                assertNull(model.state.value.pendingTurn)
                assertEquals("1", model.state.value.selectedVolumeId)
                assertEquals(0, model.state.value.pageIndex)
            }
            compose.waitForIdle()
            compose.runOnIdle {
                assertEquals("1", model.state.value.selectedVolumeId)
                assertEquals(0, model.state.value.pageIndex)
                model.closeReaderSession()
            }
        } finally { edgeGate.complete(Unit); scope.cancel(); directory.deleteRecursively() }
    }

    @Test fun accountChangeReplaysOrdinaryInitialPageLoad() {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val directory = java.io.File(app.cacheDir, "page-replay-${System.nanoTime()}").apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val gate = CompletableDeferred<Unit>()
        val requests = mutableListOf<Triple<String, Int, String?>>()
        lateinit var model: ReaderViewModel
        try {
            compose.runOnUiThread {
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION,
                    library = UserLibraryModel(GuestDataStore(context), scope),
                    outlineLoader = { CollectionOutlineResult(listOf(OutlineVolume("1", "One"))) },
                    pageLoader = { volume, index, target ->
                        requests.add(Triple(volume, index, target))
                        gate.await()
                        page(index).copy(hasMore = false)
                    })
            }
            compose.waitUntil(5_000) { requests.isNotEmpty() && model.state.value.isLoadingPage }
            compose.runOnIdle { model.clearRecentPositions(restartLoading = true) }
            compose.waitUntil(5_000) { requests.size >= 2 }
            compose.runOnIdle {
                assertEquals(requests.first(), requests[1])
                gate.complete(Unit)
            }
            compose.waitUntil(10_000) { model.state.value.pages.firstOrNull()?.isPlaceholder == false && !model.state.value.isLoadingPage }
            compose.runOnIdle { assertEquals(0, model.state.value.pageIndex); model.closeReaderSession() }
        } finally { gate.complete(Unit); scope.cancel(); directory.deleteRecursively() }
    }

    @Test fun renderedLongJourneyKeepsPublicPayloadsBounded() {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val automaticTranslation = app.readerExperience.automaticallyTranslates.value
        app.readerExperience.setAutomaticTranslation(false)
        val original = app.preferences.preferences.value
        val directory = java.io.File(app.cacheDir, "reuse-journey-${System.nanoTime()}").apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val library = UserLibraryModel(GuestDataStore(context), scope)
        val owner = object : androidx.lifecycle.ViewModelStoreOwner { override val viewModelStore = androidx.lifecycle.ViewModelStore() }
        val requests = mutableListOf<Int>()
        lateinit var model: ReaderViewModel
        val pss = mutableListOf<Int>()
        fun sampleMemory() { val info = android.os.Debug.MemoryInfo(); android.os.Debug.getMemoryInfo(info); pss.add(info.totalPss) }
        try {
            compose.runOnUiThread {
                app.preferences.adoptServer(original.copy(uiLocale = "en", translationLocale = "en", arabicVisible = true,
                    translationVisible = true, readingDirection = com.hadithly.app.core.preferences.ReadingDirection.LTR, updatedAt = original.updatedAt + 1))
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION, library = library,
                    outlineLoader = { CollectionOutlineResult(listOf(OutlineVolume("2", "Fixture", hadithCount = 60.0))) },
                    pageLoader = { _, index, _ ->
                        requests.add(index)
                        page(index).copy(totalPages = 60.0, hasMore = index < 59, items = page(index).items.map {
                            it.copy(arabicText = "نَصّ الحديث الأصلي ".repeat(100), englishText = "Original bilingual reading text. ".repeat(80))
                        })
                    })
                owner.viewModelStore.put("reader-778", model)
            }
            compose.setContent {
                androidx.compose.runtime.CompositionLocalProvider(androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner provides owner) {
                    com.hadithly.app.core.theme.LocalizedPreview(com.hadithly.app.core.preferences.ReaderTheme.DARK, "en") {
                        ReaderScreen("bukhari", "Fixture", null, null, null, ReaderTargetSource.COLLECTION, 778L, {})
                    }
                }
            }
            compose.waitUntil(10_000) { model.state.value.pages.size >= 2 && !model.state.value.isLoadingPage }
            sampleMemory()
            var maximumSlots = 0
            for (index in (1..34) + (33 downTo 0)) {
                compose.runOnIdle { model.onPageSettled(index) }
                compose.waitUntil(10_000) { model.state.value.pages.getOrNull(index)?.items?.isNotEmpty() == true && !model.state.value.isLoadingPage }
                compose.waitForIdle()
                compose.runOnIdle {
                    val loaded = model.state.value.pages.count { !it.isPlaceholder }
                    maximumSlots = maxOf(maximumSlots, loaded)
                    assertTrue("At most four renderer pins", loaded <= 4)
                    assertEquals((index + 1).toString(), model.currentPageHadiths().first().providerHadithId)
                }
                sampleMemory()
            }
            val result = org.json.JSONObject().put("scope", "Android emulator native rendered fixture, 34 forward and 34 backward model-directed turns")
                .put("requests", requests.size).put("uniquePages", requests.toSet().size).put("maximumPopulatedSlots", maximumSlots)
                .put("firstPssKb", pss.first()).put("lastPssKb", pss.last()).put("peakPssKb", pss.maxOrNull())
            android.util.Log.i("HadithlyPagingProof", result.toString())
            compose.runOnIdle { model.closeReaderSession(); assertTrue(model.state.value.pages.isEmpty()) }
        } finally {
            compose.runOnIdle { app.preferences.adoptServer(original) }
            app.readerExperience.setAutomaticTranslation(automaticTranslation)
            owner.viewModelStore.clear(); scope.cancel(); directory.deleteRecursively()
        }
    }

    @Test fun returningLastEdgeReusesTailWithoutFirstPageRequest() {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val directory = java.io.File(app.cacheDir, "reuse-tail-${System.nanoTime()}").apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val library = UserLibraryModel(GuestDataStore(context), scope)
        val requests = mutableListOf<ReaderPageContentStore.Request>()
        val store = ReaderPageContentStore(capacity = 2) { request -> requests.add(request); page(request.index) }
        lateinit var model: ReaderViewModel
        try {
            compose.runOnUiThread {
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION, library = library,
                    outlineLoader = { CollectionOutlineResult(listOf(OutlineVolume("1", "One"), OutlineVolume("2", "Two"))) }, pageStore = store)
            }
            compose.waitUntil(10_000) { model.state.value.pages.size >= 2 && !model.state.value.isLoadingPage }
            runBlocking {
                store.load(ReaderPageContentStore.Request("bukhari", "2", 4))
                store.load(ReaderPageContentStore.Request("bukhari", "unused", 0))
            }
            var before = 0
            compose.runOnIdle { assertNull(store.peek("bukhari", "2", 0)); before = requests.count { it.volume == "2" }; model.switchToVolume("2", ReaderViewModel.VolumeEdge.LAST) }
            compose.waitUntil(10_000) { model.state.value.pageIndex == 4 && !model.state.value.isLoadingPage }
            compose.runOnIdle { assertEquals(before, requests.count { it.volume == "2" }); model.closeReaderSession() }
        } finally { scope.cancel(); directory.deleteRecursively() }
    }

    private fun page(index: Int): ReaderPageResult {
        val item = ReaderHadith(_id = "reuse-$index", provider = "sunnah_now", canonicalId = "sunnah_now:bukhari:${index + 1}",
            providerHadithId = "${index + 1}", collectionSlug = "bukhari", volumeId = "2", arabicText = "نص أصلي", englishText = "Original text",
            referenceDisplay = "Bukhari ${index + 1}", collectionName = "Bukhari",
            authenticity = AuthenticityClaim("unknown", claimScope = "hadith", sourceLabel = "Fixture", sourceName = "Fixture", sourceUrl = "", verificationMethod = "fixture"))
        return ReaderPageResult(items = listOf(item), page = (index + 1).toDouble(), totalPages = 5.0,
            hasMore = index < 4, pageKey = "pg1:reuse${index + 1}", contentVersion = "cv1:fixture")
    }

}
