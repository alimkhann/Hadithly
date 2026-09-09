package com.hadithly.app.features.reader

import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performImeAction
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import com.hadithly.app.core.data.OutlineChapter
import com.hadithly.app.core.data.OutlineVolume
import com.hadithly.app.core.theme.HadithlyTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/**
 * R5 on the hadithly emulator: contents chapters + jump field, and the
 * per-hadith context menu via long-press and via the quiet overflow button
 * (same content, one code path).
 */
class ReaderR5SheetTest {
    @get:Rule
    val compose = createComposeRule()

    private val volumes = listOf(
        OutlineVolume(
            volumeId = "1",
            title = "Volume 1",
            hadithCount = 58.0,
            chapters = listOf(
                OutlineChapter(title = "Revelation", arabicTitle = "الوحي", hadithCount = 7.0, firstProviderHadithId = "1"),
                OutlineChapter(chapterId = "c2", title = "Belief", hadithCount = 51.0, firstProviderHadithId = "8"),
            ),
        ),
        OutlineVolume(volumeId = "2", title = "Volume 2", hadithCount = 44.0),
    )

    @Composable
    private fun sheet(
        onSelectChapter: (String, OutlineChapter) -> Unit = { _, _ -> },
        onJumpToReference: (String) -> Boolean = { true },
        onDismiss: () -> Unit = {},
    ) {
        HadithlyTheme {
            ContentsSheet(
                volumes = volumes,
                selectedVolumeId = "1",
                arabicVisible = true,
                onSelect = {},
                onSelectChapter = onSelectChapter,
                onJumpToReference = onJumpToReference,
                onDismiss = onDismiss,
            )
        }
    }

    @Test
    fun contentsShowsSourceProvidedChapters() {
        compose.setContent { sheet() }

        compose.onNodeWithText("Revelation").assertIsDisplayed()
        compose.onNodeWithText("الوحي").assertIsDisplayed()
        compose.onNodeWithText("Belief").assertIsDisplayed()
        compose.onNodeWithText("Volume 2").assertIsDisplayed()
        compose.onNodeWithTag("reader.contents.chapter.1.1").assertIsDisplayed()
        compose.onNodeWithTag("reader.contents.chapter.1.8").assertIsDisplayed()
    }

    @Test
    fun chapterTapSelectsVolumeAndChapterTarget() {
        var selected: Pair<String, OutlineChapter>? = null
        compose.setContent {
            sheet(
                onSelectChapter = { volumeId, chapter -> selected = volumeId to chapter },
            )
        }

        compose.onNodeWithText("Belief").performClick()
        // The sheet passes the volume through; the caller (ReaderScreen)
        // selects the volume, targets the chapter's first hadith, dismisses.
        assertEquals("1", selected?.first)
        assertEquals("8", selected?.second?.firstProviderHadithId)
    }

    @Test
    fun malformedJumpShowsInlineErrorAndKeepsSheetOpen() {
        var jumps = 0
        var dismissed = false
        compose.setContent {
            sheet(
                onJumpToReference = { jumps += 1; false },
                onDismiss = { dismissed = true },
            )
        }

        compose.onNodeWithTag("reader.contents.jump").performTextInput("abc")
        compose.onNodeWithTag("reader.contents.jump").performImeAction()

        compose.onNodeWithText("Enter a hadith number like 57 or 4.5.").assertIsDisplayed()
        assertEquals(1, jumps)
        assertTrue(!dismissed)
        compose.onNodeWithText("Contents").assertIsDisplayed()
    }

    @Test
    fun wellFormedJumpDismissesSheet() {
        var jumped: String? = null
        var dismissed = false
        compose.setContent {
            sheet(
                onJumpToReference = { jumped = it; true },
                onDismiss = { dismissed = true },
            )
        }

        compose.onNodeWithTag("reader.contents.jump").performTextInput("57")
        compose.onNodeWithTag("reader.contents.jump").performImeAction()

        assertEquals("57", jumped)
        assertTrue(dismissed)
    }

    // Context menu: long-press and overflow open the same content.

    private val menuActions = listOf(
        HadithMenuAction(testTag = "reader.bookmark", label = "Bookmark") {},
        HadithMenuAction(testTag = "reader.favorite", label = "Add to favorites") {},
        HadithMenuAction(testTag = "reader.note", label = "Add note") {},
        HadithMenuAction(testTag = "reader.copy", label = "Copy") {},
        HadithMenuAction(testTag = "reader.share", label = "Share") {},
        HadithMenuAction(testTag = "reader.reportTranslation", label = "Report translation", secondary = true) {},
        HadithMenuAction(testTag = "reader.suggestTranslation", label = "Suggest translation", secondary = true) {},
    )

    @Composable
    private fun menuHarness(actions: List<HadithMenuAction> = menuActions, onCopy: () -> Unit = {}) {
        var expanded by remember { mutableStateOf(false) }
        HadithlyTheme {
            Column {
                Box(
                    modifier = Modifier
                        .combinedClickable(onClick = {}, onLongClick = { expanded = true })
                        .testTag("harness.block"),
                ) {
                    Text("hadith body")
                }
                IconButton(
                    onClick = { expanded = true },
                    modifier = Modifier.testTag("harness.overflow"),
                ) {
                    Text("…")
                }
                HadithContextMenu(
                    referenceDisplay = "Sahih al-Bukhari · Hadith 57",
                    actions = actions.map {
                        if (it.testTag == "reader.copy") it.copy(onInvoke = onCopy) else it
                    },
                    expanded = expanded,
                    onDismiss = { expanded = false },
                )
            }
        }
    }

    @Test
    fun longPressOpensMenuWithAllActions() {
        compose.setContent { menuHarness() }

        compose.onNodeWithTag("reader.copy").assertDoesNotExist()
        compose.onNodeWithTag("harness.block").performTouchInput {
            down(0, center)
            move()
            advanceEventTime(viewConfiguration.longPressTimeoutMillis)
            up(0)
        }
        compose.waitForIdle()

        compose.onNodeWithText("Sahih al-Bukhari · Hadith 57").assertIsDisplayed()
        for (tag in listOf("reader.bookmark", "reader.favorite", "reader.note", "reader.copy", "reader.share", "reader.reportTranslation", "reader.suggestTranslation")) {
            compose.onNodeWithTag(tag).assertIsDisplayed()
        }
    }

    @Test
    fun overflowOpensIdenticalMenuAndCopyInvokes() {
        var copied = false
        compose.setContent { menuHarness(onCopy = { copied = true }) }

        compose.onNodeWithTag("harness.overflow").performClick()
        compose.waitForIdle()

        for (tag in listOf("reader.bookmark", "reader.favorite", "reader.note", "reader.copy", "reader.share", "reader.reportTranslation", "reader.suggestTranslation")) {
            compose.onNodeWithTag(tag).assertIsDisplayed()
        }
        compose.onNodeWithTag("reader.copy").performClick()
        compose.waitForIdle()
        assertTrue(copied)
    }

    @Test
    fun menuWithoutReportOmitsIt() {
        compose.setContent {
            menuHarness(actions = menuActions.filter { it.testTag != "reader.reportTranslation" })
        }

        compose.onNodeWithTag("harness.overflow").performClick()
        compose.waitForIdle()

        compose.onNodeWithTag("reader.reportTranslation").assertDoesNotExist()
        compose.onNodeWithTag("reader.suggestTranslation").assertIsDisplayed()
    }
}
