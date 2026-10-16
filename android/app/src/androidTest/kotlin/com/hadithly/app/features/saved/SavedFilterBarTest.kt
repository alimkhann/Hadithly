package com.hadithly.app.features.saved

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipe
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.geometry.Offset
import com.hadithly.app.core.theme.HadithlyTheme
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class SavedFilterBarTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun dragSelectsFiltersAndKeepsEachNativeHitTargetAccessible() {
        compose.setContent {
            var selected by remember { mutableIntStateOf(0) }
            HadithlyTheme {
                androidx.compose.runtime.CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
                    Box(Modifier.fillMaxWidth()) {
                        SavedFilterBar(selected, { selected = it }, "saved.filter", Modifier.testTag("saved.filters"))
                    }
                }
            }
        }

        val filters = listOf("all", "bookmarks", "favorites", "notes")
        val minTargetHeight = with(compose.density) { 48.dp.roundToPx() }
        filters.forEach { filter ->
            assertTrue(
                "saved.filter.$filter should keep a 48dp target",
                compose.onNodeWithTag("saved.filter.$filter").fetchSemanticsNode().size.height >= minTargetHeight,
            )
        }
        val dockSize = compose.onNodeWithTag("saved.filters").fetchSemanticsNode().size
        compose.onNodeWithTag("saved.filters").performTouchInput {
            swipe(
                start = Offset(dockSize.width * 0.06f, dockSize.height / 2f),
                end = Offset(dockSize.width * 0.94f, dockSize.height / 2f),
                durationMillis = 500,
            )
        }
        compose.onNodeWithTag("saved.filter.notes").assertIsSelected()
    }

    @Test
    fun tappingThenDraggingWithinThePreviousSegmentUpdatesSelection() {
        compose.setContent {
            var selected by remember { mutableIntStateOf(0) }
            HadithlyTheme {
                androidx.compose.runtime.CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
                    Box(Modifier.fillMaxWidth()) {
                        SavedFilterBar(selected, { selected = it }, "saved.filter", Modifier.testTag("saved.filters"))
                    }
                }
            }
        }
        compose.onNodeWithTag("saved.filter.notes").performClick().assertIsSelected()
        val dockSize = compose.onNodeWithTag("saved.filters").fetchSemanticsNode().size
        compose.onNodeWithTag("saved.filters").performTouchInput {
            swipe(start = Offset(dockSize.width * 0.03f, dockSize.height / 2f),
                end = Offset(dockSize.width * 0.19f, dockSize.height / 2f), durationMillis = 350)
        }
        compose.onNodeWithTag("saved.filter.all").assertIsSelected()
    }

    @Test
    fun dragMapsTheRightToLeftOrderInRtl() {
        compose.setContent {
            var selected by remember { mutableIntStateOf(0) }
            HadithlyTheme {
                androidx.compose.runtime.CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                    Box(Modifier.fillMaxWidth()) {
                        SavedFilterBar(selected, { selected = it }, "saved.filter", Modifier.testTag("saved.filters"))
                    }
                }
            }
        }

        compose.onNodeWithTag("saved.filter.all").assertIsSelected()
        val dockSize = compose.onNodeWithTag("saved.filters").fetchSemanticsNode().size
        compose.onNodeWithTag("saved.filters").performTouchInput {
            swipe(
                start = Offset(dockSize.width * 0.94f, dockSize.height / 2f),
                end = Offset(dockSize.width * 0.06f, dockSize.height / 2f),
                durationMillis = 500,
            )
        }
        compose.onNodeWithTag("saved.filter.notes").assertIsSelected()
        compose.onNodeWithTag("saved.filter.all").assertIsNotSelected()
    }
}
