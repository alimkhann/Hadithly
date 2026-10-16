package com.hadithly.app.core.theme

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeColorSchemeTest {
    @Test fun nativeControlsNeverFallBackToAnotherPalettesContainerColors() {
        for (palette in listOf(ReaderPalettes.light, ReaderPalettes.paper, ReaderPalettes.dark)) {
            val scheme = nativeColorScheme(palette, palette.background.luminance() < 0.5f)
            val surfaces = setOf(palette.background, palette.surface, palette.surfaceElevated)
            listOf(scheme.surfaceContainerLowest, scheme.surfaceContainerLow, scheme.surfaceContainer,
                scheme.surfaceContainerHigh, scheme.surfaceContainerHighest).forEach { assertTrue(it in surfaces) }
            assertEquals(palette.textPrimary, scheme.onSurface)
            assertEquals(palette.divider, scheme.outline)
            assertEquals(palette.interactiveSoft, scheme.primaryContainer)
            assertEquals(Color.Transparent, scheme.surfaceTint)
        }
    }
}
