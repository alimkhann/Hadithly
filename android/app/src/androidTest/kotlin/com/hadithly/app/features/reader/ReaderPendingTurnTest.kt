package com.hadithly.app.features.reader

import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.*
import androidx.compose.runtime.CompositionLocalProvider
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
import androidx.test.core.app.ApplicationProvider
import com.hadithly.app.HadithlyApplication
import com.hadithly.app.core.data.*
import com.hadithly.app.core.offline.*
import kotlinx.serialization.json.Json
import java.io.File
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class ReaderPendingTurnTest {
    @get:Rule val compose = createComposeRule()

    @Test fun delayedTurnKeepsCommittedPageAndCancellationFencesCompletion() {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val directory = java.io.File(app.cacheDir, "pending-${System.nanoTime()}").apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val gate = CompletableDeferred<Unit>()
        lateinit var model: ReaderViewModel
        try {
            compose.runOnUiThread {
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION,
                    library = UserLibraryModel(GuestDataStore(context), scope),
                    outlineLoader = { CollectionOutlineResult(listOf(OutlineVolume("1", "One"))) },
                    pageLoader = { _, index, _ ->
                        if (index == 1) gate.await()
                        ReaderPageResult(page = (index + 1).toDouble(), totalPages = 2.0,
                            hasMore = index == 0, pageKey = "page-$index", contentVersion = "cv1:test")
                    })
            }
            compose.waitUntil(10_000) { model.state.value.pages.firstOrNull()?.isPlaceholder == false }
            compose.runOnIdle {
                model.onPageSettled(1)
                assertEquals(0, model.state.value.pageIndex)
                assertEquals("page-0", model.state.value.pages[0].pageKey)
                assertEquals(ReaderViewModel.TurnStatus.LOADING, model.state.value.pendingTurn?.status)
                model.cancelPendingTurn()
                gate.complete(Unit)
            }
            compose.waitForIdle()
            compose.runOnIdle {
                assertEquals(0, model.state.value.pageIndex)
                assertNull(model.state.value.pendingTurn)
            }
        } finally { gate.complete(Unit); scope.cancel(); directory.deleteRecursively() }
    }

    @Test fun pendingTurnUsesResolvedOrdinalAndShrunkenPageCount() {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val directory = java.io.File(app.cacheDir, "pending-clamped-${System.nanoTime()}").apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        lateinit var model: ReaderViewModel
        try {
            compose.runOnUiThread {
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION,
                    library = UserLibraryModel(GuestDataStore(context), scope),
                    outlineLoader = { CollectionOutlineResult(listOf(OutlineVolume("1", "One"))) },
                    pageLoader = { _, index, _ ->
                        ReaderPageResult(page = 1.0, totalPages = 1.0, hasMore = false,
                            pageKey = if (index == 0) "page-original" else "page-clamped", contentVersion = "cv1:test")
                    })
            }
            compose.waitUntil(10_000) { model.state.value.pages.isNotEmpty() && !model.state.value.isLoadingPage }
            compose.runOnIdle { model.requestTurn(ReaderViewModel.TurnTarget.Page("1", 3)) }
            compose.waitUntil(10_000) { model.state.value.pendingTurn == null }
            compose.runOnIdle {
                assertEquals(0, model.state.value.pageIndex)
                assertEquals(1, model.state.value.pages.size)
                assertEquals("page-clamped", model.state.value.pages[0].pageKey)
                model.closeReaderSession()
            }
        } finally { scope.cancel(); directory.deleteRecursively() }
    }

    @Test fun failedTurnRetriesAndCommitsDestination() {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val directory = java.io.File(app.cacheDir, "pending-retry-${System.nanoTime()}").apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        var allow = false
        lateinit var model: ReaderViewModel
        try {
            compose.runOnUiThread {
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION,
                    library = UserLibraryModel(GuestDataStore(context), scope),
                    outlineLoader = { CollectionOutlineResult(listOf(OutlineVolume("1", "One"))) },
                    pageLoader = { _, index, _ ->
                        if (index == 1 && !allow) throw java.io.IOException("fixture")
                        ReaderPageResult(page = (index + 1).toDouble(), totalPages = 2.0,
                            hasMore = index == 0, pageKey = "page-$index", contentVersion = "cv1:test")
                    })
            }
            compose.waitUntil(10_000) { model.state.value.pages.firstOrNull()?.isPlaceholder == false && !model.state.value.isLoadingPage }
            compose.runOnIdle { model.onPageSettled(1) }
            compose.waitUntil(10_000) { model.state.value.pendingTurn?.status == ReaderViewModel.TurnStatus.FAILED }
            compose.runOnIdle {
                assertEquals(0, model.state.value.pageIndex)
                allow = true
                model.retryPendingTurn()
            }
            compose.waitUntil(10_000) { model.state.value.pageIndex == 1 }
            compose.runOnIdle {
                assertNull(model.state.value.pendingTurn)
                assertEquals("page-1", model.state.value.pages[1].pageKey)
                assertEquals(1, model.state.value.verticalLanding?.page?.pageIndex)
            }
        } finally { scope.cancel(); directory.deleteRecursively() }
    }
    @Test fun supersededTurnCannotCommitAfterNewerTurn() {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val directory = java.io.File(app.cacheDir, "pending-supersede-${System.nanoTime()}").apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val first = CompletableDeferred<Unit>()
        val second = CompletableDeferred<Unit>()
        lateinit var model: ReaderViewModel
        try {
            compose.runOnUiThread {
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION,
                    library = UserLibraryModel(GuestDataStore(context), scope),
                    outlineLoader = { CollectionOutlineResult(listOf(OutlineVolume("1", "One"))) },
                    pageLoader = { _, index, _ ->
                        if (index == 1) first.await()
                        if (index == 2) second.await()
                        ReaderPageResult(page = (index + 1).toDouble(), totalPages = 3.0,
                            hasMore = index < 2, pageKey = "page-$index", contentVersion = "cv1:test")
                    })
            }
            compose.waitUntil(10_000) { model.state.value.pages.firstOrNull()?.isPlaceholder == false }
            compose.runOnIdle {
                model.requestTurn(ReaderViewModel.TurnTarget.Page("1", 1))
                model.requestTurn(ReaderViewModel.TurnTarget.Page("1", 2))
                assertEquals(0, model.state.value.pageIndex)
                second.complete(Unit)
            }
            compose.waitUntil(10_000) { model.state.value.pageIndex == 2 }
            compose.runOnIdle { first.complete(Unit) }
            compose.waitForIdle()
            compose.runOnIdle {
                assertEquals(2, model.state.value.pageIndex)
                assertEquals("page-2", model.state.value.pages[2].pageKey)
                assertNull(model.state.value.pendingTurn)
            }
        } finally { first.complete(Unit); second.complete(Unit); scope.cancel(); directory.deleteRecursively() }
    }

    @Test fun contentsChapterOverridesPendingTurn() {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val directory = java.io.File(app.cacheDir, "pending-contents-${System.nanoTime()}").apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val gate = CompletableDeferred<Unit>()
        lateinit var model: ReaderViewModel
        try {
            compose.runOnUiThread {
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION,
                    library = UserLibraryModel(GuestDataStore(context), scope),
                    outlineLoader = { CollectionOutlineResult(listOf(OutlineVolume("1", "One"))) },
                    pageLoader = { _, index, target ->
                        if (index == 1 && target == null) gate.await()
                        ReaderPageResult(page = (index + 1).toDouble(), totalPages = 2.0,
                            hasMore = index == 0, pageKey = "page-$index", contentVersion = "cv1:test")
                    })
            }
            compose.waitUntil(10_000) { model.state.value.pages.firstOrNull()?.isPlaceholder == false }
            compose.runOnIdle {
                model.requestTurn(ReaderViewModel.TurnTarget.Page("1", 1))
                model.selectChapter("1", OutlineChapter(title = "First", firstProviderHadithId = "1"))
                assertNull(model.state.value.pendingTurn)
                gate.complete(Unit)
            }
            compose.waitUntil(10_000) { model.state.value.pages.firstOrNull()?.isPlaceholder == false && !model.state.value.isLoadingPage }
            compose.runOnIdle { assertEquals(0, model.state.value.pageIndex); assertNull(model.state.value.pendingTurn) }
        } finally { gate.complete(Unit); scope.cancel(); directory.deleteRecursively() }
    }

    @Test fun firstAndLastVolumeEdgesCommitOnlyAfterReady() {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val directory = java.io.File(app.cacheDir, "pending-edges-${System.nanoTime()}").apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val first = CompletableDeferred<Unit>()
        val last = CompletableDeferred<Unit>()
        lateinit var model: ReaderViewModel
        try {
            compose.runOnUiThread {
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION,
                    library = UserLibraryModel(GuestDataStore(context), scope),
                    outlineLoader = { CollectionOutlineResult(listOf(OutlineVolume("1", "One"), OutlineVolume("2", "Two"))) },
                    pageLoader = { volume, index, _ ->
                        if (volume == "2" && index == 0) first.await()
                        if (volume == "1" && index == 2) last.await()
                        ReaderPageResult(page = (index + 1).toDouble(), totalPages = 3.0,
                            hasMore = index < 2, pageKey = "$volume-$index", contentVersion = "cv1:$volume")
                    })
            }
            compose.waitUntil(10_000) { model.state.value.pages.firstOrNull()?.isPlaceholder == false }
            compose.runOnIdle {
                model.switchToVolume("2", ReaderViewModel.VolumeEdge.FIRST)
                assertEquals("1", model.state.value.selectedVolumeId)
                assertEquals(0, model.state.value.pageIndex)
                first.complete(Unit)
            }
            compose.waitUntil(10_000) { model.state.value.selectedVolumeId == "2" }
            compose.runOnIdle {
                assertEquals(0, model.state.value.pageIndex)
                model.switchToVolume("1", ReaderViewModel.VolumeEdge.LAST)
                assertEquals("2", model.state.value.selectedVolumeId)
                last.complete(Unit)
            }
            compose.waitUntil(10_000) { model.state.value.selectedVolumeId == "1" && model.state.value.pageIndex == 2 }
            compose.runOnIdle {
                assertEquals("1-2", model.state.value.pages[2].pageKey)
                assertEquals(2, model.state.value.verticalLanding?.page?.pageIndex)
            }
        } finally { first.complete(Unit); last.complete(Unit); scope.cancel(); directory.deleteRecursively() }
    }

    @Test fun renderedDelayedSwipeKeepsOutgoingUntilDestinationReady() = renderedDelayedSwipe(false)
    @Test fun renderedCanceledSwipeDoesNotLandLate() = renderedDelayedSwipe(true)

    private fun renderedDelayedSwipe(cancelBeforeRelease: Boolean) {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val original = app.preferences.preferences.value
        val directory = java.io.File(app.cacheDir, "pending-render-${System.nanoTime()}").apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val owner = object : ViewModelStoreOwner { override val viewModelStore = ViewModelStore() }
        val gate = CompletableDeferred<Unit>()
        lateinit var model: ReaderViewModel
        try {
            compose.runOnUiThread {
                app.preferences.adoptServer(original.copy(uiLocale = "en", translationLocale = "en",
                    arabicVisible = false, translationVisible = true,
                    readingDirection = com.hadithly.app.core.preferences.ReadingDirection.LTR, updatedAt = original.updatedAt + 1))
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION,
                    library = UserLibraryModel(GuestDataStore(context), scope),
                    outlineLoader = { CollectionOutlineResult(listOf(OutlineVolume("1", "Fixture", hadithCount = 2.0))) },
                    pageLoader = { _, index, _ ->
                        if (index == 1) gate.await()
                        val hadith = ReaderHadith("fixture-$index", "sunnah_now", "sunnah_now:bukhari:${index + 1}",
                            "${index + 1}", "bukhari", "1", arabicText = "نص تجريبي",
                            englishText = if (index == 0) "Outgoing readable fixture" else "Destination readable fixture",
                            referenceDisplay = "Bukhari ${index + 1}", collectionName = "Bukhari",
                            authenticity = AuthenticityClaim("unknown", claimScope = "hadith", sourceLabel = "Fixture",
                                sourceName = "Fixture", sourceUrl = "", verificationMethod = "fixture"))
                        ReaderPageResult(items = listOf(hadith), page = (index + 1).toDouble(), pageSize = 1.0,
                            totalPages = 2.0, hasMore = index == 0, pageKey = "pg1:page${index + 1}", contentVersion = "cv1:fixture")
                    })
                owner.viewModelStore.put("reader-779", model)
            }
            compose.setContent {
                CompositionLocalProvider(LocalViewModelStoreOwner provides owner) {
                    com.hadithly.app.core.theme.LocalizedPreview(com.hadithly.app.core.preferences.ReaderTheme.DARK, "en") {
                        ReaderScreen("bukhari", "Fixture", null, null, null, ReaderTargetSource.COLLECTION, 779L, {})
                    }
                }
            }
            compose.waitUntil(10_000) { model.state.value.pages.firstOrNull()?.isPlaceholder == false && model.state.value.verticalLanding == null }
            compose.onRoot().performTouchInput { swipeLeft(durationMillis = 500) }
            compose.waitUntil(5_000) { model.state.value.pendingTurn != null }
            compose.onNodeWithText("Outgoing readable fixture", substring = true).assertIsDisplayed()
            compose.onNodeWithTag("reader.pendingTurn").assertIsDisplayed()
            if (cancelBeforeRelease) {
                compose.onNodeWithText("Cancel").performClick()
                compose.runOnIdle {
                    assertEquals(0, model.state.value.pageIndex)
                    assertNull(model.state.value.pendingTurn)
                    gate.complete(Unit)
                }
                compose.waitUntil(10_000) { !model.state.value.isLoadingPage }
                compose.runOnIdle { assertEquals(0, model.state.value.pageIndex); assertNull(model.state.value.pendingTurn) }
                compose.onNodeWithText("Outgoing readable fixture", substring = true).assertIsDisplayed()
            } else {
                compose.runOnIdle { gate.complete(Unit) }
                compose.waitUntil(10_000) { model.state.value.pageIndex == 1 }
                compose.onNodeWithText("Destination readable fixture", substring = true).assertIsDisplayed()
            }
        } finally {
            gate.complete(Unit)
            compose.runOnUiThread { owner.viewModelStore.clear(); app.preferences.adoptServer(original) }
            scope.cancel(); directory.deleteRecursively()
        }
    }

    @Test fun verifiedOfflineCurrentTurnsForwardAndBackWithoutLiveFetch() {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val directory = File(app.cacheDir, "pending-offline-${System.nanoTime()}").apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val store = verifiedOfflineStore(File(directory, "offline"), scope)
        var calls = 0
        lateinit var model: ReaderViewModel
        try {
            compose.waitUntil(10_000) { store.recordFor("bukhari").activeBase != null }
            val first = store.offlinePage("bukhari", "2", 0, "en")!!
            assertEquals(2, first.totalPagesInt)
            compose.runOnUiThread {
                model = ReaderViewModel(app, "bukhari", "2", null, null, ReaderTargetSource.COLLECTION,
                    library = UserLibraryModel(GuestDataStore(context), scope), offlineStore = store,
                    outlineLoader = { CollectionOutlineResult(listOf(OutlineVolume("2", "Two"))) },
                    pageLoader = { _, index, _ ->
                        calls++
                        check(index == 0) { "Offline page turn unexpectedly called the live loader" }
                        first
                    })
            }
            compose.waitUntil(10_000) { model.state.value.pages.firstOrNull()?.items?.isNotEmpty() == true && !model.state.value.isLoadingPage }
            compose.runOnIdle {
                assertEquals("1", model.state.value.pages[0].items.first().providerHadithId)
                model.onPageSettled(1)
            }
            compose.waitUntil(10_000) { model.state.value.pageIndex == 1 }
            compose.runOnIdle {
                assertEquals("11", model.state.value.pages[1].items.first().providerHadithId)
                assertEquals(1, calls)
                assertTrue(model.state.value.pages.filter { !it.isPlaceholder }.all { it.contentVersion == "legacy" && it.pageKey == "legacy" })
                model.onPageSettled(0)
                assertEquals("1", model.state.value.pages[model.state.value.pageIndex].items.first().providerHadithId)
                assertEquals(1, calls)
                assertTrue(model.state.value.pages.filter { !it.isPlaceholder }.all { it.contentVersion == "legacy" && it.pageKey == "legacy" })
            }
        } finally { scope.cancel(); directory.deleteRecursively() }
    }

    @Test fun liveCurrentFailureNeverUsesOfflineOrdinal() {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val directory = File(app.cacheDir, "pending-live-offline-${System.nanoTime()}").apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val store = verifiedOfflineStore(File(directory, "offline"), scope)
        lateinit var model: ReaderViewModel
        try {
            compose.waitUntil(10_000) { store.recordFor("bukhari").activeBase != null }
            val liveFirst = store.offlinePage("bukhari", "2", 0, "en")!!.copy(contentVersion = "cv1:live", pageKey = "pg1:live")
            compose.runOnUiThread {
                model = ReaderViewModel(app, "bukhari", "2", null, null, ReaderTargetSource.COLLECTION,
                    library = UserLibraryModel(GuestDataStore(context), scope), offlineStore = store,
                    outlineLoader = { CollectionOutlineResult(listOf(OutlineVolume("2", "Two"))) },
                    pageLoader = { _, index, _ -> if (index == 0) liveFirst else throw java.io.IOException("live page unavailable") })
            }
            compose.waitUntil(10_000) { model.state.value.pages.firstOrNull()?.items?.isNotEmpty() == true && !model.state.value.isLoadingPage }
            compose.runOnIdle { model.onPageSettled(1) }
            compose.waitUntil(10_000) { model.state.value.pendingTurn?.status == ReaderViewModel.TurnStatus.FAILED }
            compose.runOnIdle {
                assertEquals(0, model.state.value.pageIndex)
                assertEquals("cv1:live", model.state.value.pages[0].contentVersion)
                assertTrue(model.state.value.pages.filter { !it.isPlaceholder }.none { it.contentVersion == "legacy" })
            }
        } finally { scope.cancel(); directory.deleteRecursively() }
    }

    private fun verifiedOfflineStore(root: File, scope: CoroutineScope): OfflineStore {
        val license = OfflineLicenseRecord(
            sourceKey = "sunnah_now", sourceName = "Sunnah.now", sourceUrl = "https://sunnah.now",
            terms = OfflineLicenseTerms(kind = "verified", licenseName = "Fixture grant",
                licenseUrl = "https://example.invalid/license", permitsDisplay = true,
                permitsRedistribution = false, permitsOfflineDistribution = true, verifiedAt = 1700000000000.0),
        )
        val version = "a".repeat(64)
        val dump = OfflineBaseDump(format = OfflineDumps.BASE_FORMAT, schemaVersion = 1.0,
            collectionSlug = "bukhari", collectionName = "Fixture", contentVersion = "od1:$version",
            generatedAt = 1700000000000.0, license = license, hadiths = (1..11).map { number ->
                OfflineDumpHadith(canonicalId = "sunnah_now:bukhari:$number", provider = "sunnah_now",
                    collectionSlug = "bukhari", providerHadithId = "$number", volumeId = "2",
                    arabicText = "نص $number", referenceDisplay = "Hadith $number", collectionName = "Fixture",
                    authenticity = OfflineAuthenticity(kind = "collection_scope", normalizedGrade = "sahih",
                        claimScope = "collection", sourceLabel = "Fixture", sourceName = "Fixture",
                        sourceUrl = "https://example.invalid", verificationMethod = "manual_collection_mapping"))
            })
        val bytes = Json.encodeToString(OfflineBaseDump.serializer(), dump).toByteArray(Charsets.UTF_8)
        val manifest = OfflineManifest(format = OfflineDumps.MANIFEST_FORMAT, schemaVersion = 1.0, kind = "base",
            collectionSlug = "bukhari", contentVersion = "od1:$version", byteSize = bytes.size.toDouble(),
            sha256 = OfflineDumps.sha256Hex(bytes), minAppVersion = "0.1.0", generatedAt = 1700000000000.0,
            license = license, compatiblePacks = emptyList(), downloadUrl = "https://example.invalid/bukhari.json")
        val transport = object : OfflineDownloadTransport {
            override suspend fun downloadToFile(url: String, tmpFile: File, offset: Long, progress: (Double) -> Unit) {
                check(offset == 0L)
                tmpFile.writeBytes(bytes)
                progress(1.0)
            }
            override fun cancel() = Unit
        }
        val store = OfflineStore(root = root, transport = transport, appVersion = "0.1.0",
            manifestProvider = { OfflineManifestsResponse(listOf(manifest), emptyList()) }, ioScope = scope)
        store.noteManifests(listOf(manifest))
        assertEquals(OfflineEnqueueResult.Started, store.enqueue("bukhari", "base", null))
        return store
    }

}
