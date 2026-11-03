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
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class ReaderRecentPositionTest {
    @get:Rule val compose = createComposeRule()
    private val noTranslationReads = ReaderTranslationReads(
        defaults = { _, _ -> emptyList() },
        publications = { kotlinx.coroutines.flow.flow { kotlinx.coroutines.awaitCancellation() } },
    )

    @Test fun returningPageUsesCapturedSemanticPosition() {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val directory = java.io.File(app.cacheDir, "recent-position-${System.nanoTime()}").apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val library = UserLibraryModel(GuestDataStore(context), scope)
        lateinit var model: ReaderViewModel
        try {
            compose.runOnUiThread {
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION, translationReads = noTranslationReads,
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
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION, translationReads = noTranslationReads,
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

    @Test fun renderedContinueReadingRestoresSemanticAnchorAndFraction() {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val original = app.preferences.preferences.value
        val automatic = app.readerExperience.automaticallyTranslates.value
        val directory = java.io.File(app.cacheDir, "continue-render-${System.nanoTime()}").apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val library = UserLibraryModel(GuestDataStore(context), scope)
        val owner = object : ViewModelStoreOwner { override val viewModelStore = ViewModelStore() }
        val expectedFraction = .25
        val position = ReadingPosition(
            anchor = ReadingPositionAnchor("sunnah_now", "bukhari", "2"), contentVersion = "cv1:fixture",
            volumeId = "1", pageKey = "pg1:page2", displayPageIndex = 2.0, rawPageOffset = 0.0,
            normalizedOffset = expectedFraction, layoutSignature = "legacy", updatedAt = 1000.0,
        )
        val requests = mutableListOf<Triple<String, Int, String?>>()
        lateinit var model: ReaderViewModel
        try {
            compose.runOnUiThread {
                app.readerExperience.setAutomaticTranslation(false)
                app.preferences.adoptServer(original.copy(uiLocale = "en", translationLocale = "en", arabicVisible = true,
                    translationVisible = true, readingDirection = com.hadithly.app.core.preferences.ReadingDirection.LTR,
                    updatedAt = original.updatedAt + 1))
                model = ReaderViewModel(app, "bukhari", "1", null, position, ReaderTargetSource.CONTINUE_READING,
                    library = library,
                    translationReads = noTranslationReads,
                    outlineLoader = { CollectionOutlineResult(listOf(OutlineVolume("1", "Fixture", hadithCount = 2.0))) },
                    pageLoader = { volume, index, target ->
                        requests.add(Triple(volume, index, target))
                        val result = page(if (target == "2") 1 else index)
                        result.copy(items = result.items.map { it.copy(arabicText = "نص الحديث ".repeat(80),
                            englishText = "Continue reading rendered fixture. ".repeat(120)) })
                    })
                owner.viewModelStore.put("reader-783", model)
            }
            compose.setContent {
                CompositionLocalProvider(LocalViewModelStoreOwner provides owner) {
                    com.hadithly.app.core.theme.LocalizedPreview(com.hadithly.app.core.preferences.ReaderTheme.DARK, "en") {
                        ReaderScreen("bukhari", "Fixture", "1", null, position, ReaderTargetSource.CONTINUE_READING, 783L, {})
                    }
                }
            }
            compose.waitUntil(10_000) { model.state.value.pageIndex == 1 && model.state.value.verticalLanding == null }
            compose.waitUntil(10_000) {
                val captured = library.progressFor("bukhari")?.position
                captured != null && captured.anchor.providerHadithId == "2" && captured.rawPageOffset > 20.0 &&
                    kotlin.math.abs(captured.normalizedOffset - expectedFraction) < .04
            }
            compose.onNodeWithTag("reader.hadithBlock").assertIsDisplayed()
            compose.runOnIdle {
                assertEquals("2", model.positionedHadith()?.providerHadithId)
                assertTrue(requests.any { it.first == "1" && it.third == "2" })
            }
        } finally {
            compose.runOnUiThread {
                owner.viewModelStore.clear()
                app.preferences.adoptServer(original)
                app.readerExperience.setAutomaticTranslation(automatic)
            }
            scope.cancel(); directory.deleteRecursively()
        }
    }

    @Test fun renderedReturnReanchorsAfterDelayedPrivateDefaultGrowth() = renderedPrivateDefaultReturn(false)
    @Test fun inactivePrivateDefaultRevocationRemovesPreview() = renderedPrivateDefaultReturn(true)

    private fun renderedPrivateDefaultReturn(revokeWhileInactive: Boolean) {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val original = app.preferences.preferences.value
        val automatic = app.readerExperience.automaticallyTranslates.value
        val directory = java.io.File(app.cacheDir, "private-growth-${System.nanoTime()}").apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val library = UserLibraryModel(GuestDataStore(context), scope)
        val owner = object : ViewModelStoreOwner { override val viewModelStore = ViewModelStore() }
        val gate = CompletableDeferred<Unit>()
        val statuses = MutableStateFlow(listOf(PublicationAvailability("fixture-private", true)))
        val firstId = "sunnah_now:bukhari:1"
        val shortText = "Short private translation."
        val grownText = "Long private translation after return. ".repeat(100)
        var firstPageReads = 0
        lateinit var model: ReaderViewModel
        try {
            compose.runOnUiThread {
                app.readerExperience.setAutomaticTranslation(false)
                app.preferences.adoptServer(original.copy(uiLocale = "en", translationLocale = "en", arabicVisible = true,
                    translationVisible = true, readingDirection = com.hadithly.app.core.preferences.ReadingDirection.LTR,
                    updatedAt = original.updatedAt + 1))
                model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION,
                    library = library,
                    translationReads = ReaderTranslationReads(
                        defaults = { hadiths, _ ->
                            if (hadiths.none { it.internalId == firstId }) emptyList() else {
                                firstPageReads++
                                if (firstPageReads > 1) gate.await()
                                val content = if (firstPageReads > 1) grownText else shortText
                                listOf(ReaderDefaultTranslation(firstId, StoredReaderTranslation("fixture-private", content, "community", "Fixture")))
                            }
                        },
                        publications = { statuses },
                    ),
                    outlineLoader = { CollectionOutlineResult(listOf(OutlineVolume("1", "Fixture", hadithCount = 2.0))) },
                    pageLoader = { _, index, _ ->
                        page(index).let { result -> result.copy(items = result.items.map {
                            it.copy(arabicText = (if (index == 0) "نص الصفحة الأولى " else "نص الصفحة الثانية ").repeat(80), englishText = "Fallback fixture")
                        }) }
                    })
                owner.viewModelStore.put("reader-784", model)
            }
            compose.setContent {
                CompositionLocalProvider(LocalViewModelStoreOwner provides owner) {
                    com.hadithly.app.core.theme.LocalizedPreview(com.hadithly.app.core.preferences.ReaderTheme.DARK, "en") {
                        ReaderScreen("bukhari", "Fixture", null, null, null, ReaderTargetSource.COLLECTION, 784L, {})
                    }
                }
            }
            compose.waitUntil(10_000) {
                (model.state.value.translations[firstId] as? TranslationUiState.Loaded)?.translation?.translation == shortText &&
                    model.state.value.pages.size == 2 && model.state.value.verticalLanding == null
            }
            repeat(2) { compose.onRoot().performTouchInput { swipeUp(startY = height * .72f, endY = height * .3f, durationMillis = 700) } }
            compose.waitUntil(10_000) {
                val actual = library.progressFor("bukhari")?.position
                actual != null && actual.anchor.providerHadithId == "1" && actual.rawPageOffset > 20.0
            }
            val before = library.progressFor("bukhari")!!.position!!
            compose.onRoot().performTouchInput { swipeLeft(durationMillis = 500) }
            compose.waitUntil(10_000) { model.state.value.pageIndex == 1 && model.state.value.verticalLanding == null }
            compose.runOnIdle {
                assertEquals(shortText, (model.state.value.translations[firstId] as? TranslationUiState.Loaded)?.translation?.translation)
                if (revokeWhileInactive) statuses.value = listOf(PublicationAvailability("fixture-private", false))
            }
            if (revokeWhileInactive) compose.waitUntil(10_000) { model.state.value.translations[firstId] == null }
            compose.onRoot().performTouchInput { swipeRight(durationMillis = 500) }
            compose.waitUntil(10_000) { model.state.value.pageIndex == 0 && firstPageReads > 1 && model.state.value.verticalLanding == null }
            if (revokeWhileInactive) {
                compose.runOnIdle { assertNull(model.state.value.translations[firstId]) }
                compose.onAllNodesWithText(shortText).assertCountEquals(0)
                return
            }
            compose.waitUntil(10_000) {
                val request = model.recentLandingForPage(0)
                val viewport = request?.viewport
                val semantic = request?.landing as? ReaderVerticalLanding.Semantic
                viewport?.firstItemIndex == 1 && viewport.firstItemOffset > 20 && semantic != null &&
                    semantic.normalizedOffset > .02 && viewport.layout.translations.any {
                        (it as? TranslationUiState.Loaded)?.translation?.translation == shortText
                    }
            }
            val beforeGrowth = model.recentLandingForPage(0)!!
            val beforeViewport = beforeGrowth.viewport!!
            val beforeFraction = (beforeGrowth.landing as ReaderVerticalLanding.Semantic).normalizedOffset
            assertEquals(before.normalizedOffset, beforeFraction, .04)
            val arabic = compose.onNode(hasTestTag("reader.arabic") and hasText("نص الصفحة الأولى", substring = true), useUnmergedTree = true)
            arabic.assertIsDisplayed()
            val beforeArabicTop = arabic.fetchSemanticsNode().positionInRoot.y
            compose.runOnIdle { gate.complete(Unit) }
            compose.waitUntil(10_000) {
                val request = model.recentLandingForPage(0)
                val viewport = request?.viewport
                request != null && request.token != beforeGrowth.token && viewport?.firstItemIndex == 1 &&
                    viewport.layout.translations.any { (it as? TranslationUiState.Loaded)?.translation?.translation == grownText }
            }
            val afterGrowth = model.recentLandingForPage(0)!!
            val afterViewport = afterGrowth.viewport!!
            val afterFraction = (afterGrowth.landing as ReaderVerticalLanding.Semantic).normalizedOffset
            assertTrue("The captured grown fraction must be nonzero", afterFraction > .001)
            val beforeHeight = beforeViewport.firstItemOffset / beforeFraction
            val afterHeight = afterViewport.firstItemOffset / afterFraction
            val afterArabicTop = arabic.fetchSemanticsNode().positionInRoot.y
            android.util.Log.i("HadithlyPagingProof", "private-growth beforeArabicTop=$beforeArabicTop afterArabicTop=$afterArabicTop beforeRaw=${beforeViewport.firstItemOffset} afterRaw=${afterViewport.firstItemOffset} beforeFraction=$beforeFraction afterFraction=$afterFraction beforeHeight=$beforeHeight afterHeight=$afterHeight")
            assertTrue("Captured hadith row did not grow: $beforeHeight -> $afterHeight", afterHeight > beforeHeight * 1.05)
            assertEquals("Visible Arabic moved during a below-anchor addition", beforeArabicTop, afterArabicTop, 3f)
            assertEquals("Raw row position moved during a below-anchor addition", beforeViewport.firstItemOffset.toFloat(), afterViewport.firstItemOffset.toFloat(), 3f)
            compose.runOnIdle { assertEquals("1", model.positionedHadith()?.providerHadithId) }
            compose.onRoot().performTouchInput { swipeLeft(durationMillis = 500) }
            compose.waitUntil(10_000) { model.state.value.pageIndex == 1 && model.state.value.verticalLanding == null }
            compose.onRoot().performTouchInput { swipeRight(durationMillis = 500) }
            compose.waitUntil(10_000) {
                val request = model.recentLandingForPage(0)
                model.state.value.pageIndex == 0 && model.state.value.verticalLanding == null && request != null &&
                    request.token != afterGrowth.token && request.viewport?.layout?.translations?.any {
                        (it as? TranslationUiState.Loaded)?.translation?.translation == grownText
                    } == true
            }
            val returned = model.recentLandingForPage(0)!!
            val returnedFraction = (returned.landing as ReaderVerticalLanding.Semantic).normalizedOffset
            val returnedTop = arabic.fetchSemanticsNode().positionInRoot.y
            android.util.Log.i("HadithlyPagingProof", "private-growth-return arabicTop=$returnedTop raw=${returned.viewport!!.firstItemOffset} fraction=$returnedFraction")
            assertEquals("Returning to the grown layout changed the visible anchor", afterArabicTop, returnedTop, 3f)
            assertEquals("Returning to the grown layout changed the captured fraction", afterFraction, returnedFraction, .04)
            compose.onNodeWithTag("reader.hadithBlock").assertIsDisplayed()
        } finally {
            gate.complete(Unit)
            compose.runOnUiThread {
                owner.viewModelStore.clear()
                app.preferences.adoptServer(original)
                app.readerExperience.setAutomaticTranslation(automatic)
            }
            scope.cancel(); directory.deleteRecursively()
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
            model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION, translationReads = noTranslationReads,
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
