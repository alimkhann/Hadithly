package com.hadithly.app.features.reader

import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.*
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.getOrNull
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
import kotlinx.coroutines.launch
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class ReaderPendingTurnTest {
    @get:Rule val compose = createComposeRule()
    private val noTranslationReads = ReaderTranslationReads(
        defaults = { _, _ -> emptyList() },
        publications = { kotlinx.coroutines.flow.flow { kotlinx.coroutines.awaitCancellation() } },
    )

    @Test fun delayedTurnKeepsCommittedPageAndCancellationFencesCompletion() {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val directory = java.io.File(app.cacheDir, "pending-${System.nanoTime()}").apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val gate = CompletableDeferred<Unit>()
        lateinit var model: ReaderViewModel
        try {
            compose.runOnUiThread {
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION, translationReads = noTranslationReads,
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
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION, translationReads = noTranslationReads,
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
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION, translationReads = noTranslationReads,
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
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION, translationReads = noTranslationReads,
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
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION, translationReads = noTranslationReads,
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
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION, translationReads = noTranslationReads,
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
    @Test fun renderedExplicitSelectionDuringMissingDragDoesNotTurn() = renderedDelayedSwipe(false, explicitDuringDrag = true)

    private fun renderedDelayedSwipe(cancelBeforeRelease: Boolean, explicitDuringDrag: Boolean = false) {
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
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION, translationReads = noTranslationReads,
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
            if (explicitDuringDrag) {
                compose.onRoot().performTouchInput { down(centerRight); moveTo(centerLeft, delayMillis = 300) }
                compose.runOnIdle { model.selectVolume("1") }
                compose.onRoot().performTouchInput { up() }
                compose.runOnIdle { gate.complete(Unit) }
                compose.waitUntil(10_000) { !model.state.value.isLoadingPage }
                compose.runOnIdle { assertEquals(0, model.state.value.pageIndex); assertNull(model.state.value.pendingTurn) }
                compose.onNodeWithText("Outgoing readable fixture", substring = true).assertIsDisplayed()
                return
            }
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
                model = ReaderViewModel(app, "bukhari", "2", null, null, ReaderTargetSource.COLLECTION, translationReads = noTranslationReads,
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

    @Test fun renderedVerifiedOfflinePageSwipeAndReturn() {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val original = app.preferences.preferences.value
        val automatic = app.readerExperience.automaticallyTranslates.value
        val directory = File(app.cacheDir, "pending-offline-render-${System.nanoTime()}").apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val owner = object : ViewModelStoreOwner { override val viewModelStore = ViewModelStore() }
        val store = verifiedOfflineStore(File(directory, "offline"), scope)
        var calls = 0
        lateinit var model: ReaderViewModel
        try {
            compose.waitUntil(10_000) { store.recordFor("bukhari").activeBase != null }
            val first = store.offlinePage("bukhari", "2", 0, "en")!!
            assertEquals(2, first.totalPagesInt)
            compose.runOnUiThread {
                app.readerExperience.setAutomaticTranslation(false)
                app.preferences.adoptServer(original.copy(uiLocale = "en", translationLocale = "en", arabicVisible = true,
                    translationVisible = false, readingDirection = com.hadithly.app.core.preferences.ReadingDirection.LTR,
                    updatedAt = original.updatedAt + 1))
                model = ReaderViewModel(app, "bukhari", "2", null, null, ReaderTargetSource.COLLECTION, translationReads = noTranslationReads,
                    library = UserLibraryModel(GuestDataStore(context), scope), offlineStore = store,
                    outlineLoader = { CollectionOutlineResult(listOf(OutlineVolume("2", "Two"))) },
                    pageLoader = { _, index, _ ->
                        calls++
                        check(index == 0) { "Offline page turn unexpectedly called the live loader" }
                        first
                    })
                owner.viewModelStore.put("reader-782", model)
            }
            compose.setContent {
                CompositionLocalProvider(LocalViewModelStoreOwner provides owner) {
                    com.hadithly.app.core.theme.LocalizedPreview(com.hadithly.app.core.preferences.ReaderTheme.DARK, "en") {
                        ReaderScreen("bukhari", "Fixture", "2", null, null, ReaderTargetSource.COLLECTION, 782L, {})
                    }
                }
            }
            compose.waitUntil(10_000) { model.state.value.pages.firstOrNull()?.items?.isNotEmpty() == true && model.state.value.verticalLanding == null }
            compose.onNodeWithText("نص 1").assertIsDisplayed()
            compose.onNode(hasTestTag("reader.hadithLabel") and hasContentDescription("Bukhari – 1,", substring = true)).assertIsDisplayed()
            compose.onRoot().performTouchInput { swipeLeft(durationMillis = 500) }
            compose.waitUntil(10_000) { model.state.value.pageIndex == 1 && model.state.value.verticalLanding == null }
            compose.onNodeWithText("نص 11").assertIsDisplayed()
            compose.onNode(hasTestTag("reader.hadithLabel") and hasContentDescription("Bukhari – 11,", substring = true)).assertIsDisplayed()
            compose.onRoot().performTouchInput { swipeRight(durationMillis = 500) }
            compose.waitUntil(10_000) { model.state.value.pageIndex == 0 && model.state.value.verticalLanding == null }
            compose.onNodeWithText("نص 1").assertIsDisplayed()
            compose.onNode(hasTestTag("reader.hadithLabel") and hasContentDescription("Bukhari – 1,", substring = true)).assertIsDisplayed()
            compose.runOnIdle { assertEquals(1, calls) }
        } finally {
            compose.runOnUiThread {
                owner.viewModelStore.clear()
                app.preferences.adoptServer(original)
                app.readerExperience.setAutomaticTranslation(automatic)
            }
            scope.cancel(); directory.deleteRecursively()
        }
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
                model = ReaderViewModel(app, "bukhari", "2", null, null, ReaderTargetSource.COLLECTION, translationReads = noTranslationReads,
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

    @Test fun preparedCachedEdgeCommitsExactPreviewAndRejectsStaleOrigin() {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val directory = File(app.cacheDir, "prepared-edge-${System.nanoTime()}").apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val warm = CompletableDeferred<Unit>()
        var calls = 0
        lateinit var model: ReaderViewModel
        try {
            compose.runOnUiThread {
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION, translationReads = noTranslationReads,
                    library = UserLibraryModel(GuestDataStore(context), scope),
                    outlineLoader = { CollectionOutlineResult(listOf(OutlineVolume("1", "One"), OutlineVolume("2", "Two"))) },
                    pageLoader = { volume, _, _ ->
                        calls++
                        if (volume == "2") warm.await()
                        ReaderPageResult(page = 1.0, totalPages = 1.0, pageKey = "pg1:$volume", contentVersion = "cv1:$volume")
                    })
            }
            compose.waitUntil(10_000) { model.state.value.pages.firstOrNull()?.isPlaceholder == false }
            compose.runOnIdle { assertNull(model.preparedNeighbor(com.hadithly.app.core.preferences.ReaderPageTurn.NEXT)); warm.complete(Unit) }
            compose.waitUntil(10_000) { model.state.value.preparedCacheRevision > 0 }
            compose.runOnIdle {
                val stale = model.preparedNeighbor(com.hadithly.app.core.preferences.ReaderPageTurn.NEXT)!!
                model.selectVolume("1")
                assertFalse(model.commitPreparedNeighbor(stale))
                val preview = model.preparedNeighbor(com.hadithly.app.core.preferences.ReaderPageTurn.NEXT)!!
                assertEquals("2", preview.volume)
                assertEquals("pg1:2", preview.page.pageKey)
                assertTrue(model.commitPreparedNeighbor(preview))
                assertEquals("2", model.state.value.selectedVolumeId)
                assertEquals(preview.page, model.state.value.pages[0])
                assertEquals(preview.landing, model.state.value.verticalLanding)
                assertFalse(model.commitPreparedNeighbor(preview))
                val back = model.preparedNeighbor(com.hadithly.app.core.preferences.ReaderPageTurn.PREVIOUS)!!
                assertEquals("1", back.volume)
                assertTrue(model.commitPreparedNeighbor(back))
                assertEquals("1", model.state.value.selectedVolumeId)
                assertEquals(2, calls)
            }
        } finally { warm.complete(Unit); scope.cancel(); directory.deleteRecursively() }
    }

    @Test fun preparedSameVolumeResidentSurvivesCacheEviction() {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val directory = File(app.cacheDir, "prepared-resident-${System.nanoTime()}").apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val store = ReaderPageContentStore(capacity = 1) { request ->
            ReaderPageResult(page = (request.index + 1).toDouble(), totalPages = 2.0, hasMore = request.index == 0,
                pageKey = "pg1:${request.volume}:${request.index}", contentVersion = "cv1:${request.volume}")
        }
        val evicted = CompletableDeferred<Unit>()
        lateinit var model: ReaderViewModel
        lateinit var preview: ReaderViewModel.PreparedPage
        try {
            compose.runOnUiThread {
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION, translationReads = noTranslationReads,
                    library = UserLibraryModel(GuestDataStore(context), scope), pageStore = store,
                    outlineLoader = { CollectionOutlineResult(listOf(OutlineVolume("1", "One"))) })
            }
            compose.waitUntil(10_000) { model.state.value.pages.size == 2 && !model.state.value.isLoadingPage }
            compose.runOnIdle {
                preview = model.preparedNeighbor(com.hadithly.app.core.preferences.ReaderPageTurn.NEXT)!!
                scope.launch {
                    try { store.load(ReaderPageContentStore.Request("bukhari", "other", 0)); evicted.complete(Unit) }
                    catch (error: Throwable) { evicted.completeExceptionally(error) }
                }
            }
            compose.waitUntil(10_000) { evicted.isCompleted }
            assertFalse(evicted.isCancelled)
            compose.runOnIdle {
                assertNull(store.peek("bukhari", "1", 1))
                assertTrue(model.commitPreparedNeighbor(preview))
                assertEquals(1, model.state.value.pageIndex)
                assertEquals(preview.page, model.state.value.pages[1])
            }
        } finally { scope.cancel(); directory.deleteRecursively() }
    }

    @Test fun preparedCrossVolumeRejectsReplacedThenEvictedPayload() {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val directory = File(app.cacheDir, "prepared-eviction-${System.nanoTime()}").apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        var version = "old"
        val store = ReaderPageContentStore(capacity = 2) { request ->
            ReaderPageResult(page = 1.0, totalPages = 1.0, pageKey = "pg1:${request.volume}:$version",
                contentVersion = "cv1:${request.volume}:$version")
        }
        val finished = CompletableDeferred<Unit>()
        lateinit var model: ReaderViewModel
        lateinit var preview: ReaderViewModel.PreparedPage
        try {
            compose.runOnUiThread {
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION, translationReads = noTranslationReads,
                    library = UserLibraryModel(GuestDataStore(context), scope), pageStore = store,
                    outlineLoader = { CollectionOutlineResult(listOf(OutlineVolume("1", "One"), OutlineVolume("2", "Two"))) })
            }
            compose.waitUntil(10_000) { model.state.value.preparedCacheRevision > 0 }
            compose.runOnIdle {
                preview = model.preparedNeighbor(com.hadithly.app.core.preferences.ReaderPageTurn.NEXT)!!
                assertEquals("cv1:2:old", preview.page.contentVersion)
                version = "new"
                scope.launch {
                    try {
                        store.load(ReaderPageContentStore.Request("bukhari", "2", 0, "refresh"))
                        store.load(ReaderPageContentStore.Request("bukhari", "3", 0))
                        store.load(ReaderPageContentStore.Request("bukhari", "4", 0))
                        finished.complete(Unit)
                    } catch (error: Throwable) { finished.completeExceptionally(error) }
                }
            }
            compose.waitUntil(10_000) { finished.isCompleted }
            assertFalse(finished.isCancelled)
            compose.runOnIdle {
                assertNull(store.peek("bukhari", "2", 0))
                assertFalse(model.commitPreparedNeighbor(preview))
                assertEquals("1", model.state.value.selectedVolumeId)
            }
        } finally { scope.cancel(); directory.deleteRecursively() }
    }

    @Test fun renderedCachedVolumeEdgeSwipeAndReturn() = renderedCachedVolumeEdge(false)
    @Test fun renderedExplicitSelectionCancelsCachedEdgeMidDrag() = renderedCachedVolumeEdge(true)

    private fun renderedCachedVolumeEdge(interruptDrag: Boolean) {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val original = app.preferences.preferences.value
        val directory = File(app.cacheDir, "prepared-render-${System.nanoTime()}").apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val owner = object : ViewModelStoreOwner { override val viewModelStore = ViewModelStore() }
        var calls = 0
        lateinit var model: ReaderViewModel
        try {
            compose.runOnUiThread {
                app.preferences.adoptServer(original.copy(uiLocale = "en", translationLocale = "en", arabicVisible = false,
                    translationVisible = true, readingDirection = com.hadithly.app.core.preferences.ReadingDirection.LTR,
                    updatedAt = original.updatedAt + 1))
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION, translationReads = noTranslationReads,
                    library = UserLibraryModel(GuestDataStore(context), scope),
                    outlineLoader = { CollectionOutlineResult(listOf(OutlineVolume("1", "First volume"), OutlineVolume("2", "Second volume"))) },
                    pageLoader = { volume, _, _ ->
                        calls++
                        val hadith = ReaderHadith("fixture-$volume", "sunnah_now", "sunnah_now:bukhari:$volume", volume,
                            "bukhari", volume, arabicText = "نص", englishText = "Readable volume $volume",
                            referenceDisplay = "Bukhari $volume", collectionName = "Fixture",
                            authenticity = AuthenticityClaim("unknown", claimScope = "hadith", sourceLabel = "Fixture",
                                sourceName = "Fixture", sourceUrl = "", verificationMethod = "fixture"))
                        ReaderPageResult(items = listOf(hadith), page = 1.0, pageSize = 1.0, totalPages = 1.0,
                            pageKey = "pg1:$volume", contentVersion = "cv1:$volume")
                    })
                owner.viewModelStore.put("reader-780", model)
            }
            compose.setContent {
                CompositionLocalProvider(LocalViewModelStoreOwner provides owner) {
                    com.hadithly.app.core.theme.LocalizedPreview(com.hadithly.app.core.preferences.ReaderTheme.DARK, "en") {
                        ReaderScreen("bukhari", "Fixture", null, null, null, ReaderTargetSource.COLLECTION, 780L, {})
                    }
                }
            }
            compose.waitUntil(10_000) { model.state.value.preparedCacheRevision > 0 && model.state.value.verticalLanding == null }
            compose.onNodeWithText("Readable volume 1", substring = true).assertIsDisplayed()
            if (interruptDrag) {
                compose.onRoot().performTouchInput { down(center); moveTo(centerLeft) }
                compose.runOnIdle { model.selectVolume("1") }
                compose.onRoot().performTouchInput { up() }
                compose.waitForIdle()
                compose.runOnIdle { assertEquals("1", model.state.value.selectedVolumeId) }
                compose.onNodeWithText("Readable volume 1", substring = true).assertIsDisplayed()
            } else {
                compose.onRoot().performTouchInput { swipeLeft(durationMillis = 500) }
                compose.waitUntil(10_000) { model.state.value.selectedVolumeId == "2" && model.state.value.verticalLanding == null }
                compose.onNodeWithText("Readable volume 2", substring = true).assertIsDisplayed()
                compose.onRoot().performTouchInput { swipeRight(durationMillis = 500) }
                compose.waitUntil(10_000) { model.state.value.selectedVolumeId == "1" && model.state.value.verticalLanding == null }
                compose.onNodeWithText("Readable volume 1", substring = true).assertIsDisplayed()
            }
            compose.runOnIdle { assertEquals(2, calls) }
        } finally {
            compose.runOnUiThread { owner.viewModelStore.clear(); app.preferences.adoptServer(original) }
            scope.cancel(); directory.deleteRecursively()
        }
    }

    @Test fun renderedThreeVolumeLtrGestureMatrix() = renderedThreeVolumeMatrix(rtl = false, reducedMotion = false, gestures = true)
    @Test fun renderedThreeVolumeShortSlowSwipeFromRest() = renderedThreeVolumeMatrix(rtl = false, reducedMotion = false, gestures = true, shortOnly = true)
    @Test fun renderedThreeVolumeRtlLargeTextAccessibilityAndGrowth() = renderedThreeVolumeMatrix(rtl = true, reducedMotion = false, gestures = false)
    @Test fun renderedThreeVolumeReducedMotionAccessibility() = renderedThreeVolumeMatrix(rtl = false, reducedMotion = true, gestures = false)

    @OptIn(ExperimentalTestApi::class)
    private fun renderedThreeVolumeMatrix(rtl: Boolean, reducedMotion: Boolean, gestures: Boolean, shortOnly: Boolean = false) {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val motionScale = android.provider.Settings.Global.getFloat(app.contentResolver,
            android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f)
        if (reducedMotion) assertEquals("Run this case with animator_duration_scale=0", 0f, motionScale, 0f)
        val original = app.preferences.preferences.value
        val automatic = app.readerExperience.automaticallyTranslates.value
        val directory = File(app.cacheDir, "three-volume-matrix-${System.nanoTime()}").apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val owner = object : ViewModelStoreOwner { override val viewModelStore = ViewModelStore() }
        val warmed = CompletableDeferred<Unit>()
        var loads = 0
        var growInactiveSource = false
        lateinit var model: ReaderViewModel
        val store = ReaderPageContentStore { request ->
            loads++
            val grown = growInactiveSource && request.volume == "2" && request.index == 0
            val number = (request.volume.toInt() - 1) * 2 + request.index + 1
            val hadith = ReaderHadith("fixture-$number", "sunnah_now", "sunnah_now:bukhari:$number", "$number",
                "bukhari", request.volume, arabicText = "نص الحديث ".repeat(12),
                englishText = "Readable fixture $number. " + "Long source text for layout and vertical scrolling. ".repeat(if (grown) 50 else 18),
                referenceDisplay = "Bukhari $number", collectionName = "Fixture",
                authenticity = AuthenticityClaim("unknown", claimScope = "hadith", sourceLabel = "Fixture",
                    sourceName = "Fixture", sourceUrl = "", verificationMethod = "fixture"))
            ReaderPageResult(items = listOf(hadith), page = (request.index + 1).toDouble(), pageSize = 1.0,
                totalPages = 2.0, hasMore = request.index == 0,
                pageKey = "pg1:${request.volume}:${request.index}${if (grown) ":grown" else ""}",
                contentVersion = "cv1:${request.volume}${if (grown) ":grown" else ""}")
        }
        val actions = SemanticsMatcher("reader page actions") { node ->
            node.config.getOrNull(SemanticsActions.CustomActions)?.any {
                it.label == "Show reader controls" || it.label == "Hide reader controls"
            } == true
        }
        fun waitPosition(volume: String, index: Int) {
            compose.waitUntil(10_000) {
                model.state.value.selectedVolumeId == volume && model.state.value.pageIndex == index && model.state.value.verticalLanding == null
            }
        }
        fun swipeTurn(next: Boolean, duration: Long) {
            val left = next != rtl
            compose.onRoot().performTouchInput {
                if (left) swipeLeft(durationMillis = duration) else swipeRight(durationMillis = duration)
            }
        }
        fun accessibilityTurn(next: Boolean, volume: String, index: Int) {
            compose.onNode(actions).performCustomAccessibilityActionWithLabel(if (next) "Next page" else "Previous page")
            waitPosition(volume, index)
        }
        try {
            compose.runOnUiThread {
                app.readerExperience.setAutomaticTranslation(false)
                app.preferences.adoptServer(original.copy(uiLocale = "en", translationLocale = "en", arabicVisible = true,
                    translationVisible = true, arabicFontSize = if (rtl) 34f else 26f,
                    translationFontSize = if (rtl) 20f else 16f,
                    readingDirection = if (rtl) com.hadithly.app.core.preferences.ReadingDirection.RTL else com.hadithly.app.core.preferences.ReadingDirection.LTR,
                    updatedAt = original.updatedAt + 1))
                store.beginReading()
                scope.launch {
                    try {
                        for (volume in 1..3) for (index in 0..1) {
                            store.load(ReaderPageContentStore.Request("bukhari", "$volume", index))
                        }
                        warmed.complete(Unit)
                    } catch (error: Throwable) { warmed.completeExceptionally(error) }
                }
            }
            compose.waitUntil(10_000) { warmed.isCompleted }
            assertFalse("Fixture cache warming failed", warmed.isCancelled)
            compose.runOnUiThread {
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION, translationReads = noTranslationReads,
                    library = UserLibraryModel(GuestDataStore(context), scope), pageStore = store,
                    outlineLoader = { CollectionOutlineResult((1..3).map { OutlineVolume("$it", "Volume $it", hadithCount = 2.0) }) })
                owner.viewModelStore.put("reader-781", model)
            }
            compose.setContent {
                CompositionLocalProvider(LocalViewModelStoreOwner provides owner) {
                    com.hadithly.app.core.theme.LocalizedPreview(com.hadithly.app.core.preferences.ReaderTheme.DARK, "en") {
                        ReaderScreen("bukhari", "Fixture", null, null, null, ReaderTargetSource.COLLECTION, 781L, {})
                    }
                }
            }
            waitPosition("1", 0)
            if (shortOnly) {
                compose.onRoot().performTouchInput {
                    swipe(start = center, end = Offset(center.x - width * .04f, center.y), durationMillis = 350)
                }
                compose.waitForIdle()
                assertEquals("1", model.state.value.selectedVolumeId)
                assertEquals(0, model.state.value.pageIndex)
                return
            }
            if (gestures) {
                swipeTurn(next = false, duration = 400)
                compose.waitForIdle()
                assertEquals("1", model.state.value.selectedVolumeId)
                assertEquals(0, model.state.value.pageIndex)
                compose.onRoot().performTouchInput {
                    swipe(start = center, end = Offset(center.x - width * .04f, center.y), durationMillis = 350)
                }
                compose.waitForIdle()
                assertEquals(0, model.state.value.pageIndex)
                compose.onRoot().performTouchInput {
                    down(centerRight); moveTo(center, delayMillis = 90); cancel()
                }
                compose.waitForIdle()
                assertEquals(0, model.state.value.pageIndex)
                compose.onRoot().performTouchInput {
                    down(center); moveTo(Offset(center.x - width * .28f, center.y), delayMillis = 100)
                    moveTo(Offset(center.x + width * .1f, center.y), delayMillis = 100); cancel()
                }
                compose.waitForIdle()
                assertEquals(0, model.state.value.pageIndex)
                compose.onRoot().performTouchInput {
                    swipe(start = center, end = Offset(center.x - width * .06f, center.y - height * .38f), durationMillis = 500)
                }
                compose.waitForIdle()
                assertEquals(0, model.state.value.pageIndex)
                swipeTurn(next = true, duration = 800); waitPosition("1", 1)
                swipeTurn(next = true, duration = 100); waitPosition("2", 0)
                swipeTurn(next = false, duration = 650); waitPosition("1", 1)
                repeat(3) {
                    swipeTurn(next = true, duration = 250); waitPosition("2", 0)
                    swipeTurn(next = false, duration = 250); waitPosition("1", 1)
                }
                swipeTurn(next = true, duration = 250); waitPosition("2", 0)
                swipeTurn(next = true, duration = 250); waitPosition("2", 1)
                swipeTurn(next = true, duration = 250); waitPosition("3", 0)
                swipeTurn(next = true, duration = 250); waitPosition("3", 1)
                swipeTurn(next = true, duration = 250)
                compose.waitForIdle()
                assertEquals("3", model.state.value.selectedVolumeId)
                assertEquals(1, model.state.value.pageIndex)
            } else {
                compose.onNode(actions).performCustomAccessibilityActionWithLabel("Hide reader controls")
                compose.onNode(actions).performCustomAccessibilityActionWithLabel("Show reader controls")
                if (rtl) {
                    swipeTurn(next = true, duration = 500); waitPosition("1", 1)
                    swipeTurn(next = true, duration = 500); waitPosition("2", 0)
                    swipeTurn(next = false, duration = 500); waitPosition("1", 1)
                } else accessibilityTurn(next = true, volume = "1", index = 1)
                compose.runOnIdle {
                    val current = app.preferences.preferences.value
                    app.preferences.adoptServer(current.copy(arabicFontSize = 40f, translationFontSize = 22f,
                        updatedAt = current.updatedAt + 1))
                }
                if (rtl) {
                    val reloaded = CompletableDeferred<Unit>()
                    compose.runOnIdle {
                        growInactiveSource = true
                        store.clear()
                        store.beginReading()
                        scope.launch {
                            try {
                                for (volume in 1..3) for (index in 0..1) {
                                    store.load(ReaderPageContentStore.Request("bukhari", "$volume", index))
                                }
                                reloaded.complete(Unit)
                            } catch (error: Throwable) { reloaded.completeExceptionally(error) }
                        }
                    }
                    compose.waitUntil(10_000) { reloaded.isCompleted }
                    assertFalse("Fixture reload failed", reloaded.isCancelled)
                    compose.runOnIdle {
                        model.selectVolume("1")
                        val preview = model.preparedNeighbor(com.hadithly.app.core.preferences.ReaderPageTurn.NEXT)!!
                        assertEquals("cv1:2:grown", preview.page.contentVersion)
                        assertTrue(preview.page.items.single().englishText!!.length > 1000)
                    }
                }
                accessibilityTurn(next = true, volume = "2", index = 0)
                accessibilityTurn(next = false, volume = "1", index = 1)
                compose.onNodeWithText("Readable fixture 2.", substring = true).assertExists()
            }
            compose.runOnIdle { assertEquals("Only the controlled fixture cache loads ran", if (rtl) 12 else 6, loads) }
        } finally {
            compose.runOnUiThread {
                owner.viewModelStore.clear()
                app.preferences.adoptServer(original)
                app.readerExperience.setAutomaticTranslation(automatic)
            }
            scope.cancel(); directory.deleteRecursively()
        }
    }

}
