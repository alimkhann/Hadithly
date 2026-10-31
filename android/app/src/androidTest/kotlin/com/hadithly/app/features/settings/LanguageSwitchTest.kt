package com.hadithly.app.features.settings

import androidx.compose.ui.test.*
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import com.hadithly.app.HadithlyApplication
import com.hadithly.app.MainActivity
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class LanguageSwitchTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test fun liveLocaleSwitchUpdatesLabelsAndDirectionWithoutChangingTranslation() {
        val app = compose.activity.application as HadithlyApplication
        assertTrue("This regression must run as a guest", !app.isSignedIn())
        val original = app.preferences.preferences.value
        val onboarded = app.settings.onboardingCompleted.value
        try {
            compose.runOnIdle {
                app.settings.setOnboardingCompleted(true)
                app.preferences.setUILocale("en")
            }
            compose.onNode(hasText("Settings") and hasClickAction()).performClick()
            compose.onNodeWithTag("settings.row.appLanguage").performClick()
            compose.onNodeWithTag("settings.uiLanguage.ar").performClick()
            compose.waitForIdle()
            assertTrue("selected locale: ${app.preferences.preferences.value.uiLocale}", app.preferences.preferences.value.uiLocale == "ar")
            compose.onNodeWithText("اليوم").assertExists()
            val today = compose.onNodeWithText("اليوم").fetchSemanticsNode().boundsInRoot
            val settings = compose.onNode(hasText("الإعدادات") and hasClickAction()).fetchSemanticsNode().boundsInRoot
            assertTrue(today.center.x > settings.center.x)
            compose.onAllNodesWithText("لغة التطبيق").assertCountEquals(2)
            compose.runOnUiThread { compose.activity.onBackPressedDispatcher.onBackPressed() }
            compose.onNodeWithTag("settings.row.appLanguage").assertExists().performClick()
            compose.onNodeWithTag("settings.uiLanguage.en").performClick()
            compose.runOnUiThread { compose.activity.onBackPressedDispatcher.onBackPressed() }
            compose.onNodeWithTag("settings.row.appLanguage").assertExists()
            compose.onNodeWithText("Today").assertExists()
            val englishToday = compose.onNodeWithText("Today").fetchSemanticsNode().boundsInRoot
            val englishSettings = compose.onNode(hasText("Settings") and hasClickAction()).fetchSemanticsNode().boundsInRoot
            assertTrue(englishToday.center.x < englishSettings.center.x)
            capture("english-return")
            compose.activityRule.scenario.recreate()
            compose.onNode(hasText("Settings") and hasClickAction()).performClick()
            compose.onNodeWithTag("settings.row.appLanguage").assertExists()
            val restartedToday = compose.onNodeWithText("Today").fetchSemanticsNode().boundsInRoot
            val restartedSettings = compose.onNode(hasText("Settings") and hasClickAction()).fetchSemanticsNode().boundsInRoot
            assertTrue(restartedToday.center.x < restartedSettings.center.x)
            capture("english-recreated")
            assertTrue(app.preferences.preferences.value.translationLocale == original.translationLocale)
        } finally {
            compose.runOnIdle {
                app.preferences.setUILocale(original.uiLocale)
                app.settings.setOnboardingCompleted(onboarded)
            }
        }
    }

    private fun capture(name: String) {
        val instrumentation = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
        val file = java.io.File(instrumentation.targetContext.getExternalFilesDir(null), "a5-language-$name.png")
        java.io.FileOutputStream(file).use { compose.onRoot().captureToImage().asAndroidBitmap().compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        val transfer = instrumentation.uiAutomation.executeShellCommand("cp ${file.absolutePath} /data/local/tmp/${file.name}")
        java.io.FileInputStream(transfer.fileDescriptor).use { it.readBytes() }
        transfer.close()
    }
}
