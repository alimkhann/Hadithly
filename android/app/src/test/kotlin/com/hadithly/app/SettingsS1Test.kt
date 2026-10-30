package com.hadithly.app

import com.clerk.api.network.model.error.ClerkErrorResponse
import com.clerk.api.network.model.error.Error
import com.clerk.api.network.serialization.ClerkResult
import com.hadithly.app.features.settings.ProfileNotice
import com.hadithly.app.features.settings.profileUsernameFailure
import com.hadithly.app.features.settings.SettingsDeletionCopy
import com.hadithly.app.features.settings.SettingsDestination
import com.hadithly.app.features.settings.SettingsExport
import com.hadithly.app.features.settings.SettingsLinks
import com.hadithly.app.features.settings.SettingsSubscription
import java.util.Calendar
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * S1 gate: every Settings row resolves to a finished destination, deletion
 * keeps its separate subscription warning, and export filenames stay stable.
 * Mirrors iOS SettingsS1Tests.
 */
class SettingsS1Test {
    @Test fun profileFailuresUseCodesAndBoundUnknownDetails() {
        for (code in listOf("form_username_in_use", "form_identifier_exists", "unknown_provider_code")) {
            val failure = ClerkResult.Failure(error = ClerkErrorResponse(errors = listOf(
                Error(message = "Synthetic provider diagnostic %@", longMessage = "Private detail", code = code),
            )))
            val expected = if (code == "unknown_provider_code") ProfileNotice.RETRY else ProfileNotice.UNAVAILABLE
            assertEquals(expected, profileUsernameFailure(failure))
        }
        assertEquals(ProfileNotice.RETRY, profileUsernameFailure(null))
        assertEquals(ProfileNotice.RETRY, profileUsernameFailure(ClerkResult.Failure(error = null, throwable = java.io.IOException("Synthetic private detail"))))
    }


    @Test
    fun everyDestinationHasTitleSubtitleAndTestTag() {
        SettingsDestination.entries.forEach { destination ->
            assertTrue(destination.id, destination.title.isNotEmpty())
            assertTrue(destination.id, destination.subtitle.isNotEmpty())
            assertEquals("settings.row.${destination.id}", destination.testTag)
        }
    }

    @Test
    fun requiredS1DestinationsExist() {
        val ids = SettingsDestination.entries.map { it.id }.toSet()
        listOf(
            "profile", "appearance", "appLanguage", "hadithTranslation",
            "offlineStorage", "notifications", "subscription",
            "privacyAndData", "helpAndSupport", "aboutAndLegal",
            "readingAndType",
        ).forEach { required ->
            assertTrue("missing destination $required", ids.contains(required))
        }
    }

    @Test
    fun deletionKeepsSeparateSubscriptionWarning() {
        assertTrue(SettingsDeletionCopy.SUBSCRIPTION_WARNING.contains("subscription", ignoreCase = true))
        assertTrue(SettingsDeletionCopy.MESSAGE.contains("cannot be undone", ignoreCase = true))
        assertFalse("message must not absorb store warning", SettingsDeletionCopy.MESSAGE.contains("Play Store"))
    }

    @Test
    fun exportFileNameIsStableAndDated() {
        val calendar = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
            set(2026, Calendar.SEPTEMBER, 17, 0, 0, 0)
            set(Calendar.MILLISECOND, 0)
        }
        assertEquals("hadithly-export-2026-09-17.json", SettingsExport.fileName(calendar.time))
    }

    @Test
    fun exportForbiddenFragmentsCoverDeviceAndForeignData() {
        assertTrue(SettingsExport.forbiddenFragments.contains("pushTokens"))
        assertTrue(SettingsExport.forbiddenFragments.contains("adminAuditLog"))
    }

    @Test
    fun externalLinksStayOnHadithlyApp() {
        listOf(
            SettingsLinks.PRIVACY,
            SettingsLinks.TERMS,
            SettingsLinks.SUPPORT,
            SettingsLinks.DELETE_ACCOUNT_INFO,
        ).forEach { url ->
            assertTrue(url, url.startsWith("https://hadithly.app"))
        }
    }

    @Test
    fun subscriptionDisplayNames() {
        assertEquals("Hadithly Pro", SettingsSubscription.displayName("pro"))
        assertEquals("Pro trial", SettingsSubscription.displayName("trial"))
        assertEquals("Free", SettingsSubscription.displayName("free"))
        assertEquals("Free", SettingsSubscription.displayName(null))
    }


}
