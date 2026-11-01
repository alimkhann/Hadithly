package com.hadithly.app.features.reader

import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
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

    @Test fun topControlsDoNotOverlapAtLargeText() = journey("ar", true, checkControls = true)

    @Test fun guestSavingNoteUndoAndSavedReaderReturn() = journey("en", false, checkSaved = true)

    private fun journey(locale: String, large: Boolean, checkControls: Boolean = true, checkSaved: Boolean = false) {
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
        val readerOpen = mutableStateOf(true)
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
                            val saved = library.savedItems.collectAsState().value
                            val folders = library.folders.collectAsState().value
                            if (readerOpen.value) {
                                ReaderScreen("bukhari", "Original %@ مصدر", null, null, null, ReaderTargetSource.COLLECTION, 57L, { closeCount++; if (checkSaved) readerOpen.value = false })
                            } else {
                                ReaderSavedSheet(items = saved, folders = folders, library = library, onDismiss = {}, onOpen = { ref -> model.navigateToSaved(ref); readerOpen.value = true }, onEdit = {})
                            }
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
            if (checkControls) {
                compose.runOnIdle { if (!model.state.value.chromeVisible) model.toggleChrome() }
                compose.waitForIdle()
                val pagePill = compose.onNodeWithTag("reader.unfocusedPageBar").fetchSemanticsNode().boundsInRoot
                val volumePill = compose.onNodeWithTag("reader.unfocusedVolumeBar").fetchSemanticsNode().boundsInRoot
                val viewport = compose.onNode(hasTestTag("reader.pageViewport") and hasAnyDescendant(hasTestTag("reader.hadithLabel") and hasContentDescription("Bukhari – 57", substring = true))).fetchSemanticsNode().boundsInRoot
                val corners = compose.onAllNodesWithTag("reader.volumeCorner").fetchSemanticsNodes()
                val capture = compose.onRoot().captureToImage()
                val file = java.io.File(androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().targetContext.getExternalFilesDir(null), "a5-controls-$locale.png")
                java.io.FileOutputStream(file).use { capture.asAndroidBitmap().compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
                val transfer = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand("cp ${file.absolutePath} /data/local/tmp/a5-controls-$locale.png")
                java.io.FileInputStream(transfer.fileDescriptor).use { it.readBytes() }; transfer.close()
                assertTrue("Reader viewport must extend behind floating controls: $viewport / $pagePill", viewport.top < minOf(pagePill.top, volumePill.top))
                for (corner in corners.map { it.boundsInRoot }.filter { it.height > 0 }) {
                    assertTrue("Visible source overlaps progress: $corner", corner.top >= maxOf(pagePill.bottom, volumePill.bottom))
                }
                for (tag in listOf("reader.unfocusedPageBar", "reader.unfocusedVolumeBar")) {
                    val texts = compose.onAllNodes(hasAnyAncestor(hasTestTag(tag)) and SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult), useUnmergedTree = true)
                    assertEquals(2, texts.fetchSemanticsNodes().size)
                    for (index in 0 until 2) {
                        val layouts = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
                        texts[index].performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) { it(layouts) }
                        val layout = layouts.single()
                        assertFalse("$locale:$tag clipped vertically", layout.didOverflowHeight)
                        assertFalse("$locale:$tag dropped lines", layout.multiParagraph.didExceedMaxLines)
                        val bounds = texts[index].fetchSemanticsNode().boundsInRoot
                        val capsule = if (tag.endsWith("PageBar")) pagePill else volumePill
                        assertTrue("$tag text outside capsule: $bounds / $capsule", bounds.top >= capsule.top && bounds.bottom <= capsule.bottom)
                        for (line in 0 until layout.lineCount) {
                            assertFalse(layout.isLineEllipsized(line))
                            assertTrue("$locale:$tag glyphs exceed capsule", bounds.left + layout.getLineLeft(line) >= capsule.left - 2f && bounds.left + layout.getLineRight(line) <= capsule.right + 2f)
                        }
                        assertEquals(layout.layoutInput.text.length, layout.getLineEnd(layout.lineCount - 1))
                    }
                }
                val header = compose.onNode(hasTestTag("reader.hadithLabel") and hasContentDescription("Bukhari – 57", substring = true)).fetchSemanticsNode().boundsInRoot
                assertTrue("Navigation target must clear floating controls", header.top >= maxOf(pagePill.bottom, volumePill.bottom))
                compose.onNodeWithTag("reader.arabic", useUnmergedTree = true).performTouchInput { click(center) }
                compose.waitForIdle()
                compose.runOnIdle { assertFalse(model.state.value.chromeVisible) }
                val focusedHeader = compose.onNode(hasTestTag("reader.hadithLabel") and hasContentDescription("Bukhari – 57", substring = true)).fetchSemanticsNode().boundsInRoot
                assertEquals("Focus must not move the reading anchor", header.top, focusedHeader.top, 1f)
                compose.onNodeWithTag("reader.arabic", useUnmergedTree = true).performTouchInput { click(center) }
                compose.waitForIdle()
                compose.runOnIdle { assertTrue(model.state.value.chromeVisible) }
                compose.onNodeWithTag("reader.unfocusedPageBar").performTouchInput { click(center) }
                compose.runOnIdle { assertEquals("57", model.currentPageHadiths().first().providerHadithId) }
            }
            if (checkSaved) {
                fun menu(tag: String) {
                    compose.onNodeWithTag("reader.arabic", useUnmergedTree = true).performTouchInput { longClick() }
                    compose.onNodeWithTag(tag).performClick()
                }
                menu("reader.bookmark")
                compose.waitUntil(5000) { library.bookmarks.value.size == 1 }
                menu("reader.favorite")
                compose.waitUntil(5000) { library.favorites.value.size == 1 }
                menu("reader.note")
                compose.onNode(hasSetTextAction()).performTextInput("Private %@ note اسم")
                compose.onNodeWithText("Save").performClick()
                compose.waitUntil(5000) { library.notes.value.firstOrNull()?.noteContent == "Private %@ note اسم" }
                menu("reader.bookmark")
                if (compose.onAllNodesWithText("Remove").fetchSemanticsNodes().isNotEmpty()) compose.onNodeWithText("Remove").performClick()
                compose.waitUntil(5000) { library.bookmarks.value.isEmpty() }
                compose.onNodeWithText("Undo").performClick()
                compose.waitUntil(5000) { library.bookmarks.value.size == 1 }
                compose.runOnIdle { if (!model.state.value.chromeVisible) model.toggleChrome() }
                compose.onNodeWithContentDescription(backLabel).performClick()
                compose.onNodeWithText("Original %@ 57").performClick()
                compose.waitUntil(5000) { model.currentPageHadiths().firstOrNull()?.providerHadithId == "57" }
                compose.onNode(hasTestTag("reader.hadithLabel") and hasContentDescription("Bukhari – 57", substring = true)).assertIsDisplayed()
                compose.runOnIdle {
                    assertEquals(1, library.savedItems.value.size)
                    assertEquals("Private %@ note اسم", library.notes.value.first().noteContent)
                    assertEquals(1, closeCount)
                    assertEquals(2, requests.count { it == "57" })
                }
            }
            val bitmap = compose.onRoot().captureToImage()
            val path = java.io.File(androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().targetContext.getExternalFilesDir(null), "a5-go-$locale.png")
            java.io.FileOutputStream(path).use { bitmap.asAndroidBitmap().compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
            val transfer = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand("cp ${path.absolutePath} /data/local/tmp/a5-go-$locale.png")
            java.io.FileInputStream(transfer.fileDescriptor).use { it.readBytes() }
            transfer.close()
            compose.runOnIdle { if (!model.state.value.chromeVisible) model.toggleChrome() }
            compose.onNodeWithContentDescription(backLabel).performClick()
            compose.runOnIdle { assertEquals(if (checkSaved) 2 else 1, closeCount) }
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
