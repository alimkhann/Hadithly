package com.hadithly.app.features.reader

import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertHeightIsEqualTo
import androidx.compose.ui.unit.dp
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.onNodeWithTag
import com.hadithly.app.core.preferences.ReaderTheme
import com.hadithly.app.core.theme.HadithlyTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger

class ReaderProgressObservationTest {
    @get:Rule val compose = createComposeRule()

    @Test fun progressControlsFitFifteenLocales() {
        val locale = mutableStateOf("en")
        val progress = mutableStateOf(2 to 0.4f)
        compose.setContent {
            com.hadithly.app.core.theme.LocalizedPreview(ReaderTheme.DARK, locale.value) {
                Box { ReaderProgressHUD(progress, 2, 3, 1, 0.4, true, true) }
            }
        }
        for (tag in listOf("en","ar","ru","kk","ky","uz","tr","id","ur","fr","es-419","pt-BR","sw","hi","bn")) {
            compose.runOnIdle { locale.value = tag }
            for (pill in listOf("reader.unfocusedPageBar", "reader.unfocusedVolumeBar")) {
                val capsule = compose.onNodeWithTag(pill).fetchSemanticsNode().boundsInRoot
                val texts = compose.onAllNodes(androidx.compose.ui.test.hasAnyAncestor(androidx.compose.ui.test.hasTestTag(pill)) and androidx.compose.ui.test.SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult), useUnmergedTree = true)
                assertEquals(2, texts.fetchSemanticsNodes().size)
                for (index in 0 until 2) {
                    val layouts = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
                    texts[index].performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) { it(layouts) }
                    val layout = layouts.single()
                    assertTrue("$tag:$pill vertical fit", !layout.didOverflowHeight && !layout.multiParagraph.didExceedMaxLines)
                    val bounds = texts[index].fetchSemanticsNode().boundsInRoot
                    for (line in 0 until layout.lineCount) {
                        assertTrue(!layout.isLineEllipsized(line))
                        assertTrue("$tag:$pill glyph fit", bounds.left + layout.getLineLeft(line) >= capsule.left - 2f && bounds.left + layout.getLineRight(line) <= capsule.right + 2f)
                    }
                    assertEquals(layout.layoutInput.text.length, layout.getLineEnd(layout.lineCount - 1))
                }
            }
        }
    }

    @Test fun focusKeepsThinProgressAcrossToggleAndUnknownTotal() {
        val chrome = mutableStateOf(true)
        val progress = mutableStateOf(0 to 0.4f)
        compose.setContent { HadithlyTheme(ReaderTheme.PAPER) {
            Box { ReaderProgressHUD(progress, 0, null, 1, null, chrome.value, true) }
        } }
        compose.onNodeWithTag("reader.focusedPageBar").assertDoesNotExist()
        compose.runOnIdle { chrome.value = false }
        compose.onNodeWithTag("reader.focusedPageBar").assertIsDisplayed().assertHeightIsEqualTo(4.dp)
        compose.runOnIdle { chrome.value = true }
        compose.onNodeWithTag("reader.focusedPageBar").assertDoesNotExist()
    }

    @Test fun scrollUpdatesTheRenderedHudWithoutRecomposingItsHost() {
        val progress = mutableStateOf(0 to 0f)
        val hostCompositions = AtomicInteger()
        compose.setContent {
            SideEffect { hostCompositions.incrementAndGet() }
            HadithlyTheme(ReaderTheme.DARK) {
                Box { ReaderProgressHUD(progress, 0, 1, 1, 1.0, false, true) }
            }
        }
        val bar = compose.onNodeWithTag("reader.focusedPageBar")
        compose.waitForIdle()
        val baseline = hostCompositions.get()
        fun middleRed(): Float {
            val pixels = bar.captureToImage().toPixelMap()
            return pixels[pixels.width / 2, pixels.height / 2].red
        }
        val before = middleRed()
        compose.runOnIdle { progress.value = 0 to 0.8f }
        compose.waitForIdle()
        assertTrue("The progress fill must actually update", middleRed() > before + 0.15f)
        assertEquals("Only the HUD observes scroll progress", baseline, hostCompositions.get())
    }
}
