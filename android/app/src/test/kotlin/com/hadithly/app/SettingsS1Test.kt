package com.hadithly.app

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

    @Test
    fun subscriptionQuotaLine() {
        assertEquals(
            "2 of 20 AI translations used this month",
            SettingsSubscription.quotaLine(2.0, 20.0),
        )
        assertNull(SettingsSubscription.quotaLine(null, 20.0))
        assertNull(SettingsSubscription.quotaLine(2.0, 0.0))
    }
}
