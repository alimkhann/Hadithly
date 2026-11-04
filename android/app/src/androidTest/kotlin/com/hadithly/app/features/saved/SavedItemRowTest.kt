package com.hadithly.app.features.saved

import android.content.ContextWrapper
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.sp
import androidx.test.core.app.ApplicationProvider
import com.hadithly.app.HadithlyApplication
import com.hadithly.app.core.data.GuestBookmarkDraft
import com.hadithly.app.core.data.GuestDataStore
import com.hadithly.app.core.data.UserLibraryModel
import com.hadithly.app.core.preferences.ArabicFont
import com.hadithly.app.core.preferences.ReaderPreferences
import com.hadithly.app.core.preferences.ReaderTheme
import com.hadithly.app.core.theme.ArabicTypefaces
import com.hadithly.app.core.theme.LocalHadithlyColors
import com.hadithly.app.core.theme.ReaderPalettes
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.longClick
import androidx.compose.ui.res.stringResource
import com.hadithly.app.R
import com.hadithly.app.core.data.SavedFolder
import com.hadithly.app.core.data.HadithRef
import com.hadithly.app.core.data.SavedItemEntry
import com.hadithly.app.core.theme.HadithlyTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class SavedItemRowTest {
    @get:Rule val compose = createComposeRule()

    @Test fun guestPreviewLoadsBothTextsWithoutNavigating() {
        val ref = HadithRef("guest", "bukhari", "Bukhari", "1", "57", "", null, "Guest reference")
        val item = SavedItemEntry("guest", 1.0, 2.0, bookmarkCreatedAt = 1.0, noteContent = "Private note", hadith = ref)
        var opens = 0
        var loads = 0
        compose.setContent {
            HadithlyTheme {
                SharedSavedItemRow(item, emptyList(), true, { opens++ }, { _, _, _ -> }, {}, {}, {}, {}, {
                    loads++
                    it.copy(arabicText = "Loaded Arabic", englishText = "Loaded English")
                })
            }
        }
        compose.onNodeWithTag("saved.preview.guest").performClick()
        compose.onNodeWithText("Loaded Arabic").assertIsDisplayed()
        compose.onNodeWithText("Loaded English").assertIsDisplayed()
        compose.onNodeWithText("Private note").assertIsDisplayed()
        assertEquals(1, loads)
        assertEquals(0, opens)
        compose.onNodeWithTag("saved.preview.guest").performClick()
        compose.onNodeWithText("Loaded English").assertDoesNotExist()
        compose.onNodeWithTag("saved.preview.guest").performClick()
        assertEquals(1, loads)
    }

    @Test fun existingSavedPreviewUsesReaderPreferencesOnPaper() {
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val directory = File(app.cacheDir, "saved-preview-${System.nanoTime()}").apply { mkdirs() }
        val context = object : ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(Dispatchers.Main)
        val id = "sunnah_now:bukhari:7"
        try {
            runBlocking {
                GuestDataStore(context).addBookmark(GuestBookmarkDraft(id, 1.0, "Sahih al-Bukhari",
                    "Sahih al-Bukhari 7", "1", "7", "bukhari"))
            }
            val library = UserLibraryModel(GuestDataStore(context), scope)
            compose.runOnUiThread { library.refresh() }
            compose.waitUntil(5_000) { library.savedItems.value.any { it.hadithId == id } }
            val item = library.savedItems.value.single()
            var preferences by mutableStateOf(ReaderPreferences(
                appTheme = ReaderTheme.PAPER, readerTheme = ReaderTheme.DARK, usesSeparateReaderTheme = true,
                translationLocale = "ru", arabicFont = ArabicFont.AMIRI, arabicFontSize = 34f,
                translationFontSize = 22f, arabicVisible = false,
            ))
            val stored = runBlocking { withTimeout(15_000) { app.repository.savedPreviewTranslation(requireNotNull(item.hadith), "ru") } }
            val russian = requireNotNull(stored).translation
            val paper = ReaderPalettes.resolved(ReaderTheme.PAPER, false)
            compose.setContent {
                HadithlyTheme(preferences.appTheme) {
                    Column(Modifier.fillMaxSize().background(LocalHadithlyColors.current.background)
                        .statusBarsPadding().verticalScroll(rememberScrollState()).testTag("saved.fixture")) {
                        SharedSavedItemRow(item, emptyList(), false, {}, { _, _, _ -> }, {}, {}, {}, {},
                            app.repository::loadSavedPreview, preferences, app.repository::savedPreviewTranslation)
                    }
                }
            }
            val arabic = compose.onNodeWithTag("reader.arabic")
            val translation = compose.onNodeWithText(russian)
            compose.onNodeWithTag("saved.preview.$id").performClick()
            compose.waitUntil(15_000) { compose.onAllNodes(hasText(russian)).fetchSemanticsNodes().isNotEmpty() }
            arabic.assertDoesNotExist()
            val translationStyle = translation.textLayout().layoutInput.style
            assertEquals(22.sp, translationStyle.fontSize)
            assertEquals(paper.textPrimary.copy(alpha = 0.92f), translationStyle.color)
            val image = compose.onNodeWithTag("saved.fixture").captureToImage().asAndroidBitmap()
            assertEquals(paper.background.toArgb(), image.getPixel(1, 1))

            compose.runOnIdle { preferences = preferences.copy(arabicVisible = true, translationVisible = false) }
            translation.assertDoesNotExist()
            compose.waitUntil(15_000) { compose.onAllNodes(hasTestTag("reader.arabic")).fetchSemanticsNodes().isNotEmpty() }
            val arabicStyle = arabic.textLayout().layoutInput.style
            assertEquals(34.sp, arabicStyle.fontSize)
            assertEquals(ArabicTypefaces.amiri, arabicStyle.fontFamily)
            assertEquals(paper.textPrimary, arabicStyle.color)
        } finally {
            scope.cancel()
        }
    }

    private fun SemanticsNodeInteraction.textLayout(): TextLayoutResult {
        val results = mutableListOf<TextLayoutResult>()
        performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(results) }
        return results.single()
    }

    @Test fun moveRemainsAvailableOnlyThroughContextMenu() {
        val ref = HadithRef("move", "bukhari", "Bukhari", "1", "57", "Arabic", "English", "Move reference")
        val item = SavedItemEntry("move", 1.0, 2.0, bookmarkCreatedAt = 1.0, hadith = ref)
        var moved: String? = null
        var moveLabel = ""
        compose.setContent {
            moveLabel = stringResource(R.string.saved_move_folder)
            HadithlyTheme { SharedSavedItemRow(item, listOf(SavedFolder("folder", "Study", 1.0)), true, {}, { _, _, _ -> }, { moved = it }, {}, {}, {}) }
        }
        compose.onNodeWithContentDescription(moveLabel).assertDoesNotExist()
        compose.onNodeWithText("Move reference").performTouchInput { longClick() }
        compose.onNodeWithText(moveLabel).performClick()
        compose.onNodeWithText("Study").performClick()
        assertEquals("folder", moved)
    }

    @Test fun previewAndActionMenuDoNotNavigate() {
        val ref = HadithRef("hadith", "bukhari", "Bukhari", "1", "57", "Arabic preview", "English preview", "Bukhari 57")
        val item = SavedItemEntry("hadith", 1.0, 2.0, bookmarkCreatedAt = 1.0, hadith = ref)
        var opens = 0
        var removals = 0
        var removeBookmarkLabel = ""
        compose.setContent {
            removeBookmarkLabel = androidx.compose.ui.res.stringResource(com.hadithly.app.R.string.saved_remove_bookmark)
            HadithlyTheme { SharedSavedItemRow(item, emptyList(), true, { opens += 1 }, { _, _, _ -> removals += 1 }, {}, {}, {}, {}) }
        }

        compose.onNodeWithText("Arabic preview").assertDoesNotExist()
        compose.onNodeWithTag("saved.preview.hadith").performClick()
        compose.onNodeWithText("Arabic preview").assertIsDisplayed()
        assertEquals(0, opens)
        compose.onNodeWithTag("saved.actions.hadith").performClick()
        compose.onNodeWithText(removeBookmarkLabel).performClick()
        assertEquals(1, removals)
        assertEquals(0, opens)
        compose.onNodeWithText("Bukhari 57").performClick()
        assertEquals(1, opens)
    }
}
