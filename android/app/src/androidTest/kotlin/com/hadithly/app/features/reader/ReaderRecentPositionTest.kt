package com.hadithly.app.features.reader

import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.*
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
import androidx.test.core.app.ApplicationProvider
import com.hadithly.app.HadithlyApplication
import com.hadithly.app.core.data.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class ReaderRecentPositionTest {
    @get:Rule val compose = createComposeRule()

    @Test fun returningPageUsesCapturedSemanticPosition() {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val directory = java.io.File(app.cacheDir, "recent-position-${System.nanoTime()}").apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val library = UserLibraryModel(GuestDataStore(context), scope)
        lateinit var model: ReaderViewModel
        try {
            compose.runOnUiThread {
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION,
                    library = library,
                    outlineLoader = { CollectionOutlineResult(listOf(OutlineVolume("1", "Fixture", hadithCount = 2.0))) },
                    pageLoader = { _, index, _ -> page(index) })
            }
            compose.waitUntil(10_000) { model.state.value.pages.size == 2 && !model.state.value.isLoadingPage }
            compose.runOnIdle {
                model.state.value.verticalLanding?.let(model::acknowledgeVerticalLanding)
                model.captureStableScroll(model.currentPageHadiths(), 0, 100.0, 0.4)
                val previousPage = model.currentPageHadiths()
                model.onPageSettled(1)
                model.state.value.verticalLanding?.let(model::acknowledgeVerticalLanding)
                model.captureStableScroll(previousPage, 0, 100.0, 0.4)
                assertNull(model.recentLandingForPage(1))
                model.onPageSettled(0)
                assertEquals(ReaderVerticalLanding.Semantic("1", 0.4), model.state.value.verticalLanding?.landing)
                val pending = model.state.value.verticalLanding!!
                model.clearRecentPositions()
                assertFalse(model.isRecentLandingValid(pending))
                assertEquals(ReaderVerticalLanding.Header, model.state.value.verticalLanding?.landing)
            }
        } finally {
            scope.cancel()
            directory.deleteRecursively()
        }
    }

    @Test fun clearAndExplicitContentsTargetOverrideRecentPosition() {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val directory = java.io.File(app.cacheDir, "recent-clear-${System.nanoTime()}").apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val library = UserLibraryModel(GuestDataStore(context), scope)
        lateinit var model: ReaderViewModel
        try {
            compose.runOnUiThread {
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION,
                    library = library,
                    outlineLoader = { CollectionOutlineResult(listOf(OutlineVolume("1", "Fixture", hadithCount = 2.0,
                        chapters = listOf(OutlineChapter(title = "First", firstProviderHadithId = "1"))))) },
                    pageLoader = { _, index, _ -> page(index) })
            }
            compose.waitUntil(10_000) { model.state.value.pages.size == 2 && !model.state.value.isLoadingPage }
            compose.runOnIdle {
                model.state.value.verticalLanding?.let(model::acknowledgeVerticalLanding)
                model.updateRecentPositionAccount(null)
                model.captureStableScroll(model.currentPageHadiths(), 0, 100.0, 0.4)
                model.updateRecentPositionAccount(null)
                assertNotNull(model.recentLandingForPage(0))
                model.onPageSettled(1)
                assertEquals(ReaderVerticalLanding.Header, model.state.value.verticalLanding?.landing)
                model.state.value.verticalLanding?.let(model::acknowledgeVerticalLanding)
                model.updateRecentPositionAccount("new-session")
                model.onPageSettled(0)
                assertEquals(ReaderVerticalLanding.Header, model.state.value.verticalLanding?.landing)
                model.state.value.verticalLanding?.let(model::acknowledgeVerticalLanding)
                model.captureStableScroll(model.currentPageHadiths(), 0, 100.0, 0.4)
                model.selectChapter("1", OutlineChapter(title = "First", firstProviderHadithId = "1"))
            }
            compose.waitUntil(10_000) { model.state.value.verticalLanding?.landing == ReaderVerticalLanding.Semantic("1", 0.0) }
            assertNull(model.state.value.verticalLanding?.viewport)
        } finally {
            scope.cancel()
            directory.deleteRecursively()
        }
    }

    @Test fun renderedOutAndBackRetainsPosition() = renderedJourney(false)
    @Test fun partialHeaderReturnRetainsPosition() = renderedJourney(true)
    @Test fun recreatedActivePageRetainsPosition() = renderedJourney(false, recreate = true)
    @Test fun inactiveLargeBilingualLayoutChangeReanchors() = renderedJourney(false, changeLayout = true)

    private fun renderedJourney(partialHeader: Boolean, recreate: Boolean = false, changeLayout: Boolean = false) {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val original = app.preferences.preferences.value
        val directory = java.io.File(app.cacheDir, "recent-render-${System.nanoTime()}").apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val library = UserLibraryModel(GuestDataStore(context), scope)
        val owner = object : ViewModelStoreOwner { override val viewModelStore = ViewModelStore() }
        lateinit var model: ReaderViewModel
        compose.runOnUiThread {
            app.preferences.adoptServer(original.copy(uiLocale = "en", translationLocale = "en",
                arabicVisible = true, translationVisible = true, readingDirection = com.hadithly.app.core.preferences.ReadingDirection.LTR, updatedAt = original.updatedAt + 1))
            model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION,
                library = library,
                outlineLoader = { CollectionOutlineResult(listOf(OutlineVolume("1", "Fixture", hadithCount = 2.0))) },
                pageLoader = { _, index, _ ->
                    val base = page(index)
                    base.copy(items = base.items.map { it.copy(arabicText = "نَصّ الحديث الأصلي ".repeat(100),
                        englishText = "Original bilingual reading text. ".repeat(80)) })
                })
            owner.viewModelStore.put("reader-777", model)
        }
        try {
            val showReader = mutableStateOf(true)
            compose.setContent {
                if (showReader.value) CompositionLocalProvider(LocalViewModelStoreOwner provides owner) {
                    com.hadithly.app.core.theme.LocalizedPreview(com.hadithly.app.core.preferences.ReaderTheme.DARK, "en") {
                        ReaderScreen("bukhari", "Fixture", null, null, null, ReaderTargetSource.COLLECTION, 777L, {})
                    }
                }
            }
            compose.waitUntil(10_000) { model.state.value.pages.size == 2 && model.state.value.verticalLanding == null }
            if (partialHeader) {
                compose.onRoot().performTouchInput { swipeUp(startY = height * .5f, endY = height * .45f, durationMillis = 700) }
            } else repeat(3) { compose.onRoot().performTouchInput { swipeUp(startY = height * .72f, endY = height * .3f, durationMillis = 700) } }
            compose.waitForIdle()
            Thread.sleep(800)
            val before = compose.onRoot().captureToImage().asAndroidBitmap()
            saveCapture(before, if (partialHeader) "unit1-android-header-scrolled.png" else "unit1-android-A-scrolled.png")
            compose.runOnIdle { model.saveCurrentProgress() }
            if (!partialHeader) compose.waitUntil(5_000) { (library.progressFor("bukhari")?.position?.rawPageOffset ?: 0.0) > 20 }
            compose.waitUntil(5_000) { library.progressFor("bukhari")?.position != null }
            val beforePosition = library.progressFor("bukhari")!!.position!!
            val beforeOffset = beforePosition.normalizedOffset
            if (recreate) {
                compose.runOnIdle { showReader.value = false }
                compose.waitForIdle()
                compose.runOnIdle { showReader.value = true }
                compose.waitUntil(5_000) { model.state.value.pageIndex == 0 && model.state.value.verticalLanding == null }
            } else {
                compose.onRoot().performTouchInput { swipeLeft(durationMillis = 500) }
                compose.waitUntil(5_000) { model.state.value.pageIndex == 1 && model.state.value.verticalLanding == null }
                if (changeLayout) compose.runOnIdle {
                    val current = app.preferences.preferences.value
                    app.preferences.adoptServer(current.copy(arabicFontSize = 40f, translationFontSize = 22f,
                        updatedAt = current.updatedAt + 1))
                }
                compose.onRoot().performTouchInput { swipeRight(durationMillis = 500) }
                compose.waitUntil(5_000) { model.state.value.pageIndex == 0 && model.state.value.verticalLanding == null }
            }
            Thread.sleep(800)
            compose.waitForIdle()
            val after = compose.onRoot().captureToImage().asAndroidBitmap()
            saveCapture(after, if (partialHeader) "unit1-android-header-returned.png" else "unit1-android-A-returned.png")
            var different = 0; var pixels = 0
            for (y in before.height / 4 until before.height * 3 / 4) {
                for (x in before.width / 10 until before.width * 9 / 10) {
                    pixels++
                    if (before.getPixel(x, y) != after.getPixel(x, y)) different++
                }
            }
            if (!changeLayout) assertTrue("Returning rendered text differs by ${different.toDouble() / pixels}", different.toDouble() / pixels < .03)
            compose.runOnIdle { model.saveCurrentProgress() }
            if (changeLayout) {
                compose.waitUntil(5_000) {
                    val actual = library.progressFor("bukhari")?.position
                    actual != null && actual.anchor.providerHadithId == "1" && actual.updatedAt > beforePosition.updatedAt && actual.rawPageOffset > 20.0 &&
                        kotlin.math.abs(beforeOffset - actual.normalizedOffset) < .005
                }
            } else {
                compose.waitUntil(5_000) { kotlin.math.abs(beforeOffset - (library.progressFor("bukhari")?.position?.normalizedOffset ?: 0.0)) < .005 }
            }
        } finally {
            compose.runOnUiThread { owner.viewModelStore.clear(); app.preferences.adoptServer(original) }
            scope.cancel(); directory.deleteRecursively()
        }
    }

    private fun saveCapture(bitmap: android.graphics.Bitmap, name: String) {
        val instrumentation = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
        val file = java.io.File(instrumentation.targetContext.getExternalFilesDir(null), name)
        java.io.FileOutputStream(file).use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        val descriptor = instrumentation.uiAutomation.executeShellCommand("cp ${file.absolutePath} /data/local/tmp/$name")
        java.io.FileInputStream(descriptor.fileDescriptor).use { it.readBytes() }; descriptor.close()
    }

    private fun page(index: Int) = ReaderPageResult(
        items = listOf(ReaderHadith("fixture-$index", "sunnah_now", "sunnah_now:bukhari:${index + 1}", "${index + 1}", "bukhari", "1",
            arabicText = "نص تجريبي", englishText = "Fixture", referenceDisplay = "Bukhari ${index + 1}",
            collectionName = "Bukhari", authenticity = AuthenticityClaim("unknown", claimScope = "hadith", sourceLabel = "Fixture", sourceName = "Fixture", sourceUrl = "", verificationMethod = "fixture"))),
        page = (index + 1).toDouble(), pageSize = 1.0, totalPages = 2.0, hasMore = index == 0,
        contentVersion = "cv1:fixture", pageKey = "pg1:page${index + 1}",
    )
}
