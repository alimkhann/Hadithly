package com.hadithly.app

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.test.platform.app.InstrumentationRegistry
import com.hadithly.app.core.theme.HadithlyTheme
import com.hadithly.app.features.onboarding.OnboardingFlow
import org.junit.Rule
import org.junit.Test
import org.junit.Assert.*
import java.io.File

class OnboardingLA2Test {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    @Test fun realFlowLoadsDailyHadithAndOffersGuestAfterSignInEntry() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val prefs = context.getSharedPreferences("onboarding", 0)
        val old = prefs.all
        val app = context.applicationContext as HadithlyApplication
        val previouslyComplete = app.settings.onboardingCompleted.value
        try {
            prefs.edit().clear().commit()
            app.settings.setOnboardingCompleted(false)
            compose.waitForIdle()
            val welcomeCtaTop = compose.onNodeWithTag("onboarding.getStarted").fetchSemanticsNode().boundsInRoot.top
            compose.onNodeWithTag("onboarding.getStarted").assertIsDisplayed().performClick()
            val languageCtaTop = compose.onNodeWithTag("onboarding.continue").fetchSemanticsNode().boundsInRoot.top
            assertEquals(welcomeCtaTop, languageCtaTop, 1f)
            compose.onNodeWithTag("onboarding.continue").performClick()
            compose.waitUntil(timeoutMillis = 30_000) {
                compose.onAllNodesWithTag("onboarding.dailyText").fetchSemanticsNodes().isNotEmpty() ||
                    compose.onAllNodesWithTag("onboarding.dailyRetry").fetchSemanticsNodes().isNotEmpty()
            }
            val dailyText = compose.onAllNodesWithTag("onboarding.dailyText").fetchSemanticsNodes().isNotEmpty()
            val demoCtaTop = compose.onNodeWithTag("onboarding.continue").fetchSemanticsNode().boundsInRoot.top
            assertEquals(languageCtaTop, demoCtaTop, 1f)
            if (dailyText) {
                compose.onNodeWithTag("onboarding.dailyText").assertIsDisplayed()
                if (compose.onAllNodesWithTag("hadith.text.translation").fetchSemanticsNodes().isNotEmpty()) {
                    compose.onNodeWithTag("hadith.text.translation").assertIsDisplayed()
                }
            }
            else compose.onNodeWithTag("onboarding.dailyRetry").assertIsDisplayed()
            val directory = File(context.getExternalFilesDir(null), "LA2").apply { mkdirs() }
            compose.onRoot().captureToImage().asAndroidBitmap().let { bitmap ->
                val name = if (dailyText) "demo-daily-hadith.png" else "demo-unavailable-retry.png"
                File(directory, name).outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
            }
            compose.onNodeWithTag("onboarding.continue").performClick()
            compose.onNodeWithTag("onboarding.signIn").assertIsDisplayed().performClick()
            compose.onNodeWithTag("signin.close").performClick()
            compose.onNodeWithTag("onboarding.guest").assertIsDisplayed()
            compose.onRoot().captureToImage().asAndroidBitmap().let { bitmap -> File(directory, "account.png").outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) } }
            compose.onNodeWithTag("onboarding.guest").performClick()
            compose.runOnIdle { assertTrue(app.settings.onboardingCompleted.value) }
            compose.waitUntil(timeoutMillis = 10_000) { compose.onAllNodesWithTag("tabs.library").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithTag("tabs.library").performClick()
            compose.onNodeWithTag("library.collection.bukhari").assertIsDisplayed()
        } finally {
            app.settings.setOnboardingCompleted(previouslyComplete)
            val edit = prefs.edit().clear()
            old.forEach { (key, value) -> when (value) { is Int -> edit.putInt(key, value); is String -> edit.putString(key, value); is Boolean -> edit.putBoolean(key, value) } }
            edit.commit()
        }
    }
}
