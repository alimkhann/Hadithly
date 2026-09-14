package com.hadithly.app.features.saved

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import com.hadithly.app.core.data.HadithRef
import com.hadithly.app.core.data.SavedItemEntry
import com.hadithly.app.core.theme.HadithlyTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class SavedItemRowTest {
    @get:Rule val compose = createComposeRule()

    @Test fun previewAndFacetIconsDoNotNavigate() {
        val ref = HadithRef("hadith", "bukhari", "Bukhari", "1", "57", "Arabic preview", "English preview", "Bukhari 57")
        val item = SavedItemEntry("hadith", 1.0, 2.0, bookmarkCreatedAt = 1.0, hadith = ref)
        var opens = 0
        var removals = 0
        compose.setContent { HadithlyTheme { SharedSavedItemRow(item, emptyList(), true, { opens += 1 }, { _, _, _ -> removals += 1 }, {}, {}, {}, {}) } }

        compose.onNodeWithText("Arabic preview").assertDoesNotExist()
        compose.onNodeWithTag("saved.preview.hadith").performClick()
        compose.onNodeWithText("Arabic preview").assertIsDisplayed()
        assertEquals(0, opens)
        compose.onNodeWithContentDescription("Remove bookmark").performClick()
        assertEquals(1, removals)
        assertEquals(0, opens)
        compose.onNodeWithText("Bukhari 57").performClick()
        assertEquals(1, opens)
    }
}
