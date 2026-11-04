package com.hadithly.app.features.reader

import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.test.core.app.ApplicationProvider
import com.hadithly.app.HadithlyApplication
import com.hadithly.app.core.data.*
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

/**
 * Instrumented model coverage for the reader volume/page jump: Go inside one
 * volume, crossing into the next volume, and placing the wheels without a
 * fetch when counts are already cached. The sheet UI itself is exercised by
 * the iOS simulator and Android manual gates recorded in the verification doc.
 */
class ReaderJumpTest {
    @get:Rule val compose = createComposeRule()
    private val noTranslationReads = ReaderTranslationReads(
        defaults = { _, _ -> emptyList() },
        publications = { kotlinx.coroutines.flow.flow { kotlinx.coroutines.awaitCancellation() } },
    )

    private fun fixturePage(volume: String, index: Int, version: String): ReaderPageResult {
        val hadith = ReaderHadith("fixture-$volume-$index", "sunnah_now", "sunnah_now:bukhari:${index + 1}",
            "${index + 1}", "bukhari", volume, arabicText = "نص تجريبي", englishText = "Fixture text",
            referenceDisplay = "Bukhari ${index + 1}", collectionName = "Bukhari",
            authenticity = AuthenticityClaim("unknown", claimScope = "hadith", sourceLabel = "Fixture",
                sourceName = "Fixture", sourceUrl = "", verificationMethod = "fixture"))
        return ReaderPageResult(items = listOf(hadith), page = (index + 1).toDouble(), pageSize = 1.0,
            totalPages = 2.0, hasMore = index == 0, pageKey = "pg1:vol$volume-page$index",
            contentVersion = version)
    }

    private fun makeModel(
        app: HadithlyApplication,
        scope: CoroutineScope,
        directory: File,
        volumes: List<OutlineVolume>,
    ) : ReaderViewModel {
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        return ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION,
            translationReads = noTranslationReads, library = UserLibraryModel(GuestDataStore(context), scope),
            outlineLoader = { CollectionOutlineResult(volumes) },
            pageLoader = { volume, index, _ -> fixturePage(volume ?: "1", index, "cv1:vol$volume") })
    }

    private fun awaitJump(model: ReaderViewModel, volume: String, index: Int) {
        val deadline = System.currentTimeMillis() + 15_000
        while (System.currentTimeMillis() < deadline) {
            val state = model.state.value
            if (state.selectedVolumeId == volume && state.pageIndex == index && state.pendingTurn == null) return
            Thread.sleep(200)
        }
        fail("Jump did not land: state=${model.state.value}")
    }

    @Test fun jumpToVolumePageLandsAndClearsPendingTurn() {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val original = app.preferences.preferences.value
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        lateinit var model: ReaderViewModel
        try {
            compose.runOnUiThread {
                model = makeModel(
                    app, scope,
                    File(app.cacheDir, "jump-${System.nanoTime()}").apply { mkdirs() },
                    listOf(OutlineVolume("1", "Volume 1", hadithCount = 2.0)),
                )
            }
            compose.waitUntil(10_000) { model.state.value.pages.firstOrNull()?.isPlaceholder == false }
            compose.runOnIdle {
                val count = runBlocking { model.pageCountForJump("1") }
                model.jumpToPage(ReaderViewModel.JumpDestination("1", 1, count))
            }
            awaitJump(model, "1", 1)
            compose.runOnIdle {
                assertEquals("1", model.state.value.selectedVolumeId)
                assertEquals(1, model.state.value.pageIndex)
            }
        } finally {
            compose.runOnUiThread { scope.cancel() }
        }
    }

    @Test fun jumpAcrossVolumesFetchesCountAndLandsFirstPage() {        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        lateinit var model: ReaderViewModel
        try {
            compose.runOnUiThread {
                model = makeModel(
                    app, scope,
                    File(app.cacheDir, "jump-cross-${System.nanoTime()}").apply { mkdirs() },
                    listOf(OutlineVolume("1", "Volume 1", hadithCount = 2.0), OutlineVolume("2", "Volume 2", hadithCount = 2.0)),
                )
            }
            compose.waitUntil(10_000) { model.state.value.pages.firstOrNull()?.isPlaceholder == false }
            compose.runOnUiThread {
                // Count resolution hops to Main internally; the await must not
                // run on the main thread itself.
                scope.launch(Dispatchers.IO) {
                    val count = model.pageCountForJump("2")
                    assertEquals(2, count.count)
                    model.jumpToPage(ReaderViewModel.JumpDestination("2", 0, count))
                }
            }
            awaitJump(model, "2", 0)
            compose.runOnIdle {
                assertEquals(0, model.state.value.pageIndex)
                assertEquals("2", model.state.value.selectedVolumeId)
            }
        } finally {
            compose.runOnUiThread { scope.cancel() }
        }
    }

    @Test fun jumpToCurrentPageKeepsPositionWithoutTurn() {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        lateinit var model: ReaderViewModel
        try {
            compose.runOnUiThread {
                model = makeModel(
                    app, scope,
                    File(app.cacheDir, "jump-same-${System.nanoTime()}").apply { mkdirs() },
                    listOf(OutlineVolume("1", "Volume 1", hadithCount = 2.0)),
                )
            }
            compose.waitUntil(10_000) { model.state.value.pages.firstOrNull()?.isPlaceholder == false }
            compose.runOnIdle {
                val count = runBlocking { model.pageCountForJump(model.state.value.selectedVolumeId!!) }
                model.jumpToPage(ReaderViewModel.JumpDestination(model.state.value.selectedVolumeId!!, model.state.value.pageIndex, count))
                assertNull(model.state.value.pendingTurn)
                assertEquals(0, model.state.value.pageIndex)
            }
        } finally {
            compose.runOnUiThread { scope.cancel() }
        }
    }
}
