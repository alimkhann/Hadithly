package com.hadithly.app.features.reader

import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createComposeRule
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
