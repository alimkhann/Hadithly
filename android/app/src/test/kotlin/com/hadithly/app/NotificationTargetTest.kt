package com.hadithly.app

import com.hadithly.app.core.push.DevicePushProfile
import com.hadithly.app.core.push.PushNotificationManager
import com.hadithly.app.core.push.notificationHadithTarget
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.ZoneId

/**
 * N1 gate: translated exact-target pushes resolve through the same
 * canonical boundary as App Links on cold and warm intents. Extra N1 keys
 * ride along harmlessly; malformed identity yields null (normal open).
 */
class NotificationTargetTest {

    @Test
    fun routesExactTargetWithN1Extras() {
        val target = notificationHadithTarget(
            mapOf(
                "collectionSlug" to "bukhari",
                "providerHadithId" to "57",
                "volumeId" to "2",
                "locale" to "kk",
                "ai" to "1",
                "hadithId" to "sunnah_now:bukhari:57",
            ),
        )
        assertEquals("bukhari", target?.collectionSlug)
        assertEquals("Sahih al-Bukhari", target?.collectionName)
        assertEquals("57", target?.providerHadithId)
        assertEquals("2", target?.volumeId)
    }

    @Test
    fun routesWithoutOptionals() {
        val target = notificationHadithTarget(
            mapOf("collectionSlug" to "muslim", "providerHadithId" to "12"),
        )
        assertEquals("muslim", target?.collectionSlug)
        assertEquals("12", target?.providerHadithId)
        assertEquals(null, target?.volumeId)
    }

    @Test
    fun rejectsMalformedIdentity() {
        assertEquals(
            null,
            notificationHadithTarget(
                mapOf("collectionSlug" to "bukhari", "providerHadithId" to "57abc"),
            ),
        )
        assertEquals(
            null,
            notificationHadithTarget(
                mapOf("collectionSlug" to "Bukhari", "providerHadithId" to "57"),
            ),
        )
        assertEquals(null, notificationHadithTarget(mapOf("locale" to "kk")))
        assertNull(notificationHadithTarget(emptyMap()))
    }

    @Test
    fun deviceProfileCarriesIanaZoneAndLocales() {
        val profile = DevicePushProfile(
            timezoneId = "Asia/Almaty",
            uiLocale = "en",
            translationLocale = "kk",
        )
        assertEquals("Asia/Almaty", profile.timezoneId)
        assertEquals("kk", profile.translationLocale)
    }

    @Test
    fun timezoneIdMatchesSystemZone() {
        assertEquals(ZoneId.systemDefault().id, PushNotificationManager.timezoneId())
    }
}
