package com.hadithly.app.features.settings

import androidx.compose.material3.Surface
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.runtime.CompositionLocalProvider
import com.hadithly.app.core.theme.LocalHadithlyColors
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import com.hadithly.app.core.preferences.ReaderPreferences
import com.hadithly.app.core.preferences.ReaderTheme
import com.hadithly.app.core.theme.HadithlyTheme
import org.junit.Rule
import org.junit.Test

class ReaderPreferenceContentTest {
    @get:Rule val compose = createComposeRule()

    @Test fun readerControlsPreserveSelectionsSizesAndLastVisibleLayer() = verifyControls("reader")

    @Test fun globalControlsPreserveSelectionsSizesAndLastVisibleLayer() = verifyControls("settings", fontScale = 2f)

    private fun capture(name: String) {
        compose.waitForIdle()
        val instrumentation = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
        val file = java.io.File(instrumentation.targetContext.getExternalFilesDir(null), "$name.png")
        file.outputStream().use { compose.onRoot().captureToImage().asAndroidBitmap().compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        android.os.ParcelFileDescriptor.AutoCloseInputStream(
            instrumentation.uiAutomation.executeShellCommand("cp ${file.absolutePath} /sdcard/Pictures/Hadithly-$name.png")
        ).use { it.readBytes() }
    }

    private fun verifyControls(prefix: String, fontScale: Float = 1f) {
        compose.setContent {
            var preferences by remember { mutableStateOf(ReaderPreferences(appTheme = ReaderTheme.DARK)) }
            HadithlyTheme(theme = if (preferences.usesSeparateReaderTheme) preferences.readerTheme else preferences.appTheme) {
                CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, fontScale)) {
                Surface(modifier = Modifier.fillMaxSize(), color = LocalHadithlyColors.current.background) {
                ReaderPreferenceContent(
                    preferences = preferences,
                    prefix = prefix,
                    onLanguage = { preferences = preferences.copy(translationLocale = it) },
                    onArabicFontSize = { preferences = preferences.copy(arabicFontSize = it) },
                    onTranslationFontSize = { preferences = preferences.copy(translationFontSize = it) },
                    onTheme = { preferences = preferences.copy(readerTheme = it, usesSeparateReaderTheme = true) },
                    onArabicFont = { preferences = preferences.copy(arabicFont = it) },
                    onVisibility = { arabic, translation ->
                        val next = preferences.copy(arabicVisible = arabic ?: preferences.arabicVisible, translationVisible = translation ?: preferences.translationVisible)
                        if (next.arabicVisible || next.translationVisible) preferences = next
                    },
                    onDismiss = {},
                )
                }
                }
            }
        }
        compose.onNodeWithTag("$prefix.settings.title").assertIsDisplayed()
        compose.onNodeWithTag("$prefix.visibility.arabic").performScrollTo().performClick().assertIsOff()
        compose.onNodeWithTag("$prefix.visibility.translation").performClick().assertIsOn()
        capture("$prefix-root")
        compose.onNodeWithTag("$prefix.settings.arabic").performScrollTo().performClick()
        compose.onNodeWithTag("$prefix.settings.back").assertIsDisplayed()
        compose.onNodeWithTag("$prefix.arabicSize.larger").performClick()
        capture("$prefix-arabic")
        compose.onNodeWithText("30", substring = true).assertIsDisplayed()
        compose.onNodeWithTag("$prefix.font.amiri").performClick().assertIsSelected()
        compose.onNodeWithTag("$prefix.settings.back").performClick()
        compose.onNodeWithText("Amiri · 30 pt").assertIsDisplayed()
        compose.onNodeWithTag("$prefix.settings.translation").performClick()
        capture("$prefix-languages")
        compose.onNodeWithTag("$prefix.translationSize.larger").performClick()
        compose.onNodeWithText("18", substring = true).assertIsDisplayed()
        compose.onNodeWithTag("$prefix.language.ru").performScrollTo().performClick().assertIsSelected()
        compose.onNodeWithTag("$prefix.settings.back").performClick()
        compose.onNodeWithText("RU · 18 pt").assertIsDisplayed()
        compose.onNodeWithTag("$prefix.settings.appearance").performClick()
        compose.onNodeWithTag("$prefix.theme.paper").performClick().assertIsSelected()
        capture("$prefix-paper")
        val rendered = compose.onRoot().captureToImage().asAndroidBitmap()
        val pixel = rendered.getPixel(10, rendered.height / 2)
        org.junit.Assert.assertTrue("Paper must render a light background", android.graphics.Color.red(pixel) > 220)
        org.junit.Assert.assertTrue("Paper must retain its warm tint", android.graphics.Color.red(pixel) - android.graphics.Color.blue(pixel) > 10)
    }
}
