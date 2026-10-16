package com.hadithly.app.features.saved

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
