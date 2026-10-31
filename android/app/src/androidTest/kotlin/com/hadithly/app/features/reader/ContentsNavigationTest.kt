package com.hadithly.app.features.reader

import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
import androidx.test.core.app.ApplicationProvider
import com.hadithly.app.HadithlyApplication
import com.hadithly.app.core.data.*
import com.hadithly.app.core.theme.HadithlyTheme
import com.hadithly.app.core.preferences.ReaderTheme
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class ContentsNavigationTest {
    @get:Rule val compose = createComposeRule()

    @Test fun goOwnsTargetWhilePrefetchIsInFlight() = journey("en", false)
    @Test fun arabicLargeText() = journey("ar", true)
    @Test fun urduLargeText() = journey("ur", true)
    @Test fun russianLargeText() = journey("ru", true)
    @Test fun bengaliLargeText() = journey("bn", true)

    private fun journey(locale: String, large: Boolean) {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        assertNull("Guest-only controlled journey", com.clerk.api.Clerk.user)
        val directory = java.io.File(app.cacheDir, "a5-library-" + System.nanoTime()).apply { mkdirs() }
        val context = object : android.content.ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val library = UserLibraryModel(GuestDataStore(context), scope)
        val oldPage = CompletableDeferred<ReaderPageResult>()
        val targetPage = CompletableDeferred<ReaderPageResult>()
        var menuLabel = ""
        var backLabel = ""
        var closeCount = 0
        val requests = mutableListOf<String>()
        val owner = object : ViewModelStoreOwner { override val viewModelStore = ViewModelStore() }
        lateinit var model: ReaderViewModel
        compose.runOnUiThread {
            model = ReaderViewModel(app, "bukhari", null, null, null, ReaderTargetSource.COLLECTION,
                library = library,
                outlineLoader = { CollectionOutlineResult(listOf(OutlineVolume("1", "Original %@ مصدر", hadithCount = 100.0))) },
                pageLoader = { _, index, target ->
                    requests.add(target ?: "page$index")
                    if (target != null) targetPage.await() else if (index == 0) page("1", true) else oldPage.await()
                })
            owner.viewModelStore.put("reader-57", model)
        }
        try {
            compose.setContent {
                CompositionLocalProvider(LocalViewModelStoreOwner provides owner) {
                    com.hadithly.app.core.theme.LocalizedPreview(ReaderTheme.DARK, locale) {
                        menuLabel = com.hadithly.app.core.preferences.nativeText("Open reader menu")
                        backLabel = com.hadithly.app.core.preferences.nativeText("Back")
                        val density = androidx.compose.ui.platform.LocalDensity.current
                        CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density, if (large) 2f else 1f)) {
                            ReaderScreen("bukhari", "Original %@ مصدر", null, null, null, ReaderTargetSource.COLLECTION, 57L, { closeCount++ })
                        }
                    }
                }
            }
            compose.waitUntil(10000) { model.state.value.isLoadingPage && requests.contains("page1") }
            compose.onNodeWithContentDescription(menuLabel).performClick()
            compose.onNodeWithTag("reader.menu.contents").performClick()
            compose.onNodeWithTag("reader.contents.go").assertIsNotEnabled()
            compose.onNodeWithTag("reader.contents.jump").performTextInput("abc")
            compose.onNodeWithTag("reader.contents.go").performClick()
            compose.onNodeWithTag("reader.contents.sheet").assertIsDisplayed()
            compose.runOnIdle {
                assertEquals(listOf("page0", "page1"), requests)
                assertEquals("1", model.currentPageHadiths().first().providerHadithId)
            }
            compose.onNodeWithTag("reader.contents.jump").performTextReplacement("57")
            compose.onNodeWithTag("reader.contents.go").performClick()
            compose.onNodeWithTag("reader.contents.sheet").assertDoesNotExist()
            compose.waitUntil(10000) { requests.contains("57") }
            oldPage.complete(page("2"))
            compose.waitForIdle()
            compose.runOnIdle {
                assertTrue("Old cancellation must not release the target's loading state", model.state.value.isLoadingPage)
                assertTrue(model.state.value.pages.isEmpty())
            }
            targetPage.complete(page("57"))
            compose.waitUntil(10000) { !model.state.value.isLoadingPage }
            assertEquals("Go dismissed but lost target; requests=$requests", "57", model.currentPageHadiths().firstOrNull()?.providerHadithId)
            compose.waitUntil(10000) {
                try { compose.onNode(hasTestTag("reader.hadithLabel") and hasContentDescription("Bukhari – 57", substring = true)).assertIsDisplayed(); true }
                catch (_: AssertionError) { false }
            }
            compose.onNode(hasTestTag("reader.hadithLabel") and hasContentDescription("Bukhari – 57", substring = true)).assertIsDisplayed()
            compose.runOnIdle {
                assertEquals(1, requests.count { it == "57" })
                assertEquals("1", model.state.value.selectedVolumeId)
                assertEquals(2, model.state.value.pageIndex)
                assertEquals("Controlled original %@ text 57", model.currentPageHadiths().first().englishText)
                assertEquals(0, closeCount)
            }
            val bitmap = compose.onRoot().captureToImage()
            val path = java.io.File(androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().targetContext.getExternalFilesDir(null), "a5-go-$locale.png")
            java.io.FileOutputStream(path).use { bitmap.asAndroidBitmap().compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
            val transfer = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand("cp ${path.absolutePath} /data/local/tmp/a5-go-$locale.png")
            java.io.FileInputStream(transfer.fileDescriptor).use { it.readBytes() }
            transfer.close()
            compose.runOnIdle { if (!model.state.value.chromeVisible) model.toggleChrome() }
            compose.onNodeWithContentDescription(backLabel).performClick()
            compose.runOnIdle { assertEquals(1, closeCount) }
        } finally {
            oldPage.complete(page("2"))
            targetPage.complete(page("57"))
            compose.runOnUiThread { owner.viewModelStore.clear(); scope.cancel() }
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
