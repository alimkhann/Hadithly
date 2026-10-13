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
    @Test fun realFlowRevealsExampleOffersGuestAndRecoversCancelledSignup() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val prefs = context.getSharedPreferences("onboarding", 0)
        val old = prefs.all
        val app = context.applicationContext as HadithlyApplication
        val previouslyComplete = app.settings.onboardingCompleted.value
        try {
            prefs.edit().clear().commit()
            app.settings.setOnboardingCompleted(false)
            compose.waitForIdle()
            compose.onNodeWithTag("onboarding.getStarted").assertIsDisplayed().performClick()
            compose.onNodeWithTag("onboarding.continue").performClick()
            compose.onNodeWithTag("onboarding.reveal").assertIsDisplayed().performClick()
            compose.onNodeWithTag("onboarding.example").assertIsDisplayed()
            val directory = File(context.getExternalFilesDir(null), "LA2").apply { mkdirs() }
            compose.onRoot().captureToImage().asAndroidBitmap().let { bitmap -> File(directory, "demo.png").outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) } }
            compose.onNodeWithTag("onboarding.continue").performClick()
            compose.onNodeWithTag("onboarding.createAccount").performScrollTo().assertIsDisplayed().performClick()
            compose.onNodeWithText("Close").performClick()
            compose.onNodeWithTag("onboarding.guest").performScrollTo().assertIsDisplayed()
            compose.onRoot().captureToImage().asAndroidBitmap().let { bitmap -> File(directory, "account.png").outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) } }
            compose.onNodeWithTag("onboarding.guest").performClick()
            compose.runOnIdle { assertTrue(app.settings.onboardingCompleted.value) }
            compose.waitUntil(timeoutMillis = 10_000) { compose.onAllNodesWithTag("tabs.library").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithTag("tabs.library").performClick()
            compose.onNodeWithTag("library.collection.bukhari").performClick()
            compose.waitUntil(timeoutMillis = 30_000) { compose.onAllNodesWithTag("reader.hadithLabel").fetchSemanticsNodes().isNotEmpty() }
            compose.onAllNodesWithTag("reader.hadithLabel")[0].assertIsDisplayed()
            compose.onRoot().performTouchInput { swipeUp() }
            compose.waitForIdle(); Thread.sleep(1000)
            app.analytics.flush(); Thread.sleep(3500)
        } finally {
            app.settings.setOnboardingCompleted(previouslyComplete)
            val edit = prefs.edit().clear()
            old.forEach { (key, value) -> when (value) { is Int -> edit.putInt(key, value); is String -> edit.putString(key, value); is Boolean -> edit.putBoolean(key, value) } }
            edit.commit()
        }
    }
}
