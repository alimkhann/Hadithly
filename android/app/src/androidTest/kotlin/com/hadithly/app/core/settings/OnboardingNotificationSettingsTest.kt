package com.hadithly.app.core.settings

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class OnboardingNotificationSettingsTest {
    @Test fun freshCompletionArmsOnceAndGuestGrantRemainsWithFirstAccount() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val name = "notification-fixture-${UUID.randomUUID()}"
        val prefs = context.getSharedPreferences(name, Context.MODE_PRIVATE)
        try {
            prefs.edit().putBoolean("onboarding.completed", true).commit()
            val existing = AppSettings(prefs)
            assertFalse(existing.onboardingNotificationPromptPending.value)
            prefs.edit().clear().commit()
            val fresh = AppSettings(prefs)
            fresh.finishOnboarding()
            assertTrue(AppSettings(prefs).onboardingNotificationPromptPending.value)
            fresh.consumeOnboardingNotificationPrompt(null)
            fresh.finishOnboarding()
            assertFalse(AppSettings(prefs).onboardingNotificationPromptPending.value)
            fresh.recordOnboardingNotificationGrant()
            assertFalse(AppSettings(prefs).onboardingNotificationPromptPending.value)
            assertTrue(AppSettings(prefs).claimOnboardingNotificationGrant("user-a"))
            assertFalse(AppSettings(prefs).claimOnboardingNotificationGrant("user-b"))
            assertTrue(AppSettings(prefs).claimOnboardingNotificationGrant("user-a"))
            fresh.clearOnboardingNotificationGrant()
            assertFalse(AppSettings(prefs).claimOnboardingNotificationGrant("user-a"))
            prefs.edit().clear().commit()
            val denied = AppSettings(prefs)
            denied.finishOnboarding()
            denied.consumeOnboardingNotificationPrompt(null)
            denied.clearOnboardingPromptOwner()
            assertFalse(AppSettings(prefs).onboardingNotificationPromptPending.value)
            assertFalse(AppSettings(prefs).claimOnboardingNotificationGrant("user-a"))
        } finally {
            prefs.edit().clear().commit()
            context.deleteSharedPreferences(name)
        }
    }
}
