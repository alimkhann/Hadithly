package com.hadithly.app.features.settings

import androidx.compose.ui.test.*
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
            compose.onNodeWithText("اليوم").assertExists()
            val today = compose.onNodeWithText("اليوم").fetchSemanticsNode().boundsInRoot
            val settings = compose.onNode(hasText("الإعدادات") and hasClickAction()).fetchSemanticsNode().boundsInRoot
            assertTrue(today.center.x > settings.center.x)
            compose.onAllNodesWithText("لغة التطبيق").assertCountEquals(2)
            compose.onNodeWithTag("settings.uiLanguage.en").performClick()
            compose.onNodeWithText("Today").assertExists()
            val englishToday = compose.onNodeWithText("Today").fetchSemanticsNode().boundsInRoot
            val englishSettings = compose.onNode(hasText("Settings") and hasClickAction()).fetchSemanticsNode().boundsInRoot
            assertTrue(englishToday.center.x < englishSettings.center.x)
            assertTrue(app.preferences.preferences.value.translationLocale == original.translationLocale)
        } finally {
            compose.runOnIdle {
                app.preferences.setUILocale(original.uiLocale)
                app.settings.setOnboardingCompleted(onboarded)
            }
        }
    }
}
