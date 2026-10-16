package com.hadithly.app.core.theme

import android.graphics.Bitmap
import android.graphics.Color
import android.os.ParcelFileDescriptor
import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import com.hadithly.app.core.preferences.ReaderPreferences
import com.hadithly.app.core.preferences.ReaderTheme
import com.hadithly.app.features.library.CollectionTitle
import com.hadithly.app.features.settings.ReaderPreferenceContent
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import kotlin.math.abs

class NativePolishTest {
    @get:Rule val compose = createComposeRule()

    @Test fun readerManualChoicePersistsAndHintOnlyAppearsOnce() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val defaults = context.getSharedPreferences("reader-experience-test", android.content.Context.MODE_PRIVATE)
        defaults.edit().clear().commit()
        try {
            val preferences = com.hadithly.app.core.preferences.ReaderExperiencePreferences(defaults)
            assertTrue(preferences.automaticallyTranslates.value)
            preferences.setAutomaticTranslation(false)
            assertFalse(com.hadithly.app.core.preferences.ReaderExperiencePreferences(defaults).automaticallyTranslates.value)
            preferences.offerActionHint()
            assertTrue(preferences.showsActionHint.value)
            preferences.dismissActionHint()
            preferences.offerActionHint()
            assertFalse(preferences.showsActionHint.value)
            val relaunched = com.hadithly.app.core.preferences.ReaderExperiencePreferences(defaults)
            relaunched.offerActionHint()
            assertFalse(relaunched.showsActionHint.value)
        } finally { defaults.edit().clear().commit() }
    }

    @Test fun closingReaderBeforeHintExpiresDoesNotShowItAgain() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val defaults = context.getSharedPreferences("reader-hint-disposal-test", android.content.Context.MODE_PRIVATE)
        defaults.edit().clear().commit()
        val experience = com.hadithly.app.core.preferences.ReaderExperiencePreferences(defaults)
        try {
            compose.setContent {
                var opened by remember { mutableStateOf(true) }
                HadithlyTheme {
                    Column {
                        TextButton(onClick = { opened = !opened }, modifier = Modifier.testTag("toggle-reader")) { Text("Toggle reader") }
                        if (opened) com.hadithly.app.features.reader.ReaderActionHint(experience)
                    }
                }
            }
            compose.onNodeWithTag("reader.actionHint").assertIsDisplayed()
            compose.onNodeWithTag("toggle-reader").performClick()
            compose.onNodeWithTag("reader.actionHint").assertDoesNotExist()
            compose.runOnIdle { assertFalse(experience.showsActionHint.value) }
            compose.onNodeWithTag("toggle-reader").performClick()
            compose.onNodeWithTag("reader.actionHint").assertDoesNotExist()
        } finally { defaults.edit().clear().commit() }
    }

    @Test fun lightSettingsSurfaceDiffersFromCanvas() {
        compose.setContent {
            HadithlyTheme(ReaderTheme.LIGHT) {
                Surface(Modifier.fillMaxSize(), color = LocalHadithlyColors.current.background) {
                    ReaderPreferenceContent(ReaderPreferences(appTheme = ReaderTheme.LIGHT), "polish", {}, {}, {}, {}, {}, { _, _ -> }, {})
                }
            }
        }
        val row = compose.onNodeWithTag("polish.settings.arabic").fetchSemanticsNode().boundsInRoot
        val bitmap = compose.onRoot().captureToImage().asAndroidBitmap()
        val canvas = bitmap.getPixel(4, row.center.y.toInt())
        val surface = bitmap.getPixel(row.left.toInt() + 8, row.center.y.toInt())
        assertTrue("Light settings must have a separate gray surface", Color.red(canvas) - Color.red(surface) > 10)
        capture("light-settings", bitmap)
    }

    @Test fun loadingAndAIStatesRenderAcrossThemes() {
        compose.setContent {
            var theme by remember { mutableStateOf(ReaderTheme.LIGHT) }
            HadithlyTheme(theme) {
                Surface(Modifier.fillMaxSize(), color = LocalHadithlyColors.current.background) {
                    Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
                        TextButton(onClick = { theme = if (theme == ReaderTheme.LIGHT) ReaderTheme.DARK else ReaderTheme.PAPER }, modifier = Modifier.testTag("next-theme")) { Text("Next theme") }
                        TranslationThinkingView()
                        ContentSkeleton(SkeletonKind.Daily, label = "Daily content loading")
                    }
                }
            }
        }
        for (theme in listOf("light", "dark", "paper")) {
            compose.onNodeWithTag("reader.translationLoading").assertIsDisplayed()
            compose.onNodeWithContentDescription("Daily content loading").assertIsDisplayed()
            capture("loading-$theme", compose.onRoot().captureToImage().asAndroidBitmap())
            compose.onNodeWithTag("next-theme").performClick()
        }
    }

    @Test fun onboardingUsesSharedArabicAndTranslationText() {
        compose.setContent {
            HadithlyTheme(ReaderTheme.PAPER) {
                Column(Modifier.fillMaxSize().padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Sahih al-Bukhari · Hadith 1", modifier = Modifier.testTag("onboarding.reference"))
                    HadithReadingText(
                        arabicText = "إِنَّمَا الأَعْمَالُ بِالنِّيَّاتِ",
                        translation = "Actions are judged by intentions.",
                        translationLanguage = "en",
                        textColor = LocalHadithlyColors.current.textPrimary,
                    )
                    Text("Sunnah.now", modifier = Modifier.testTag("onboarding.translationSource"))
                }
            }
        }
        compose.onNodeWithTag("onboarding.reference").assertIsDisplayed()
        compose.onNodeWithText("إِنَّمَا الأَعْمَالُ بِالنِّيَّاتِ", substring = true).assertIsDisplayed()
        compose.onNodeWithText("Actions are judged by intentions.").assertIsDisplayed()
        compose.onNodeWithTag("onboarding.translationSource").assertIsDisplayed()
        capture("onboarding-real-hadith-text", compose.onRoot().captureToImage().asAndroidBitmap())
    }

    @Test fun todaySkeletonRevealsContentAndHandlesFailure() {
        compose.setContent {
            var phase by remember { mutableStateOf("loading") }
            HadithlyTheme(ReaderTheme.LIGHT) {
                androidx.compose.foundation.layout.Box(Modifier.fillMaxSize()) {
                    com.hadithly.app.features.today.TodayScreen({}, previewState = phase)
                    Row(Modifier.align(androidx.compose.ui.Alignment.BottomCenter)) {
                        TextButton(onClick = { phase = "ready" }, modifier = Modifier.testTag("load-example")) { Text("Load example") }
                        TextButton(onClick = { phase = "failure" }, modifier = Modifier.testTag("fail-example")) { Text("Fail example") }
                    }
                }
            }
        }
        compose.onNodeWithTag("today.dailyLoading").assertIsDisplayed()
        compose.onNodeWithTag("load-example").performClick()
        compose.onNodeWithTag("today.dailyCard").assertIsDisplayed()
        capture("today-ready", compose.onNodeWithTag("today.dailyCard").captureToImage().asAndroidBitmap())
        compose.onNodeWithTag("today.expand").performScrollTo().performClick()
        compose.onNodeWithText("Show less").assertExists()
        compose.onNodeWithTag("fail-example").performClick()
        compose.onNodeWithTag("today.dailyCard").assertDoesNotExist()
        compose.onNodeWithTag("today.dailyLoading").assertDoesNotExist()
    }

    @Test fun collectionNumberSharesTheTitleRowAtLargeRTLSize() {
        compose.setContent {
            HadithlyTheme(ReaderTheme.LIGHT) {
                CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, 2f), LocalLayoutDirection provides LayoutDirection.Rtl) {
                    Surface(color = LocalHadithlyColors.current.surface) { CollectionTitle(1, "Sahih al-Bukhari", Modifier.width(180.dp).padding(12.dp)) }
                }
            }
        }
        val number = compose.onNodeWithTag("collection.number.1").fetchSemanticsNode().boundsInRoot
        val title = compose.onNodeWithTag("collection.name.1").fetchSemanticsNode().boundsInRoot
        assertTrue(number.left >= title.right)
        assertTrue("The number belongs beside the first title line", abs(number.top - title.top) < 24)
        capture("collection-title-large-rtl", compose.onRoot().captureToImage().asAndroidBitmap())
    }

    @Test fun activeAIIndicatorMovesAndRevealsTheFullResult() = checkMotion(reduced = false)
    @Test fun disabledAnimationsKeepAIIndicatorStaticAndReadable() = checkMotion(reduced = true)

    private fun checkMotion(reduced: Boolean) {
        val resolver = InstrumentationRegistry.getInstrumentation().targetContext.contentResolver
        val original = Settings.Global.getString(resolver, Settings.Global.ANIMATOR_DURATION_SCALE)
        shell("settings put global animator_duration_scale ${if (reduced) 0 else 1}")
        try {
            compose.mainClock.autoAdvance = false
            compose.setContent {
                var ready by remember { mutableStateOf(false) }
                HadithlyTheme(ReaderTheme.LIGHT) {
                    Surface(Modifier.fillMaxSize(), color = LocalHadithlyColors.current.background) {
                        Column(Modifier.padding(24.dp)) {
                            if (!ready) TranslationThinkingView()
                            else TranslationReveal(TranslationPresentationPhase.Available) { Text("Complete prepared translation", Modifier.testTag("result")) }
                            TextButton(onClick = { ready = true }, modifier = Modifier.testTag("finish")) { Text("Finish") }
                        }
                    }
                }
            }
            compose.mainClock.advanceTimeBy(500)
            val before = pixels(compose.onRoot().captureToImage().asAndroidBitmap())
            compose.mainClock.advanceTimeBy(350)
            val after = pixels(compose.onRoot().captureToImage().asAndroidBitmap())
            if (reduced) assertTrue("Reduced motion must be static", before.contentEquals(after))
            else assertFalse("The active request should animate", before.contentEquals(after))
            compose.onNodeWithTag("reader.translationLoading").assertIsDisplayed()
            compose.onNodeWithTag("finish").performClick()
            compose.mainClock.advanceTimeBy(600)
            compose.onNodeWithTag("result").assertIsDisplayed()
            compose.onNodeWithTag("reader.translationLoading").assertDoesNotExist()
        } finally {
            shell(if (original == null) "settings delete global animator_duration_scale" else "settings put global animator_duration_scale $original")
            compose.mainClock.autoAdvance = true
        }
    }

    private fun pixels(bitmap: Bitmap) = IntArray(bitmap.width * bitmap.height).also { bitmap.getPixels(it, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height) }
    private fun shell(command: String) {
        ParcelFileDescriptor.AutoCloseInputStream(InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command)).use { it.readBytes() }
    }
    private fun capture(name: String, bitmap: Bitmap) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val file = java.io.File(context.getExternalFilesDir(null), "polish-$name.png")
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        shell("cp ${file.absolutePath} /sdcard/Pictures/polish-$name.png")
    }
}
