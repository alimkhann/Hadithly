package com.hadithly.app.features.widgets

import android.app.NotificationChannel
import android.app.NotificationManager
import androidx.test.platform.app.InstrumentationRegistry
import com.hadithly.app.core.push.ensureDailyNotificationChannel
import com.hadithly.app.core.push.notificationDisplayTitle
import com.hadithly.app.core.widgets.WidgetCopy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class WidgetNotificationCopyTest {
    @Test fun channelAndFallbackLocalizeWithoutChangingProviderTextOrChannelIdentity() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val manager = context.getSystemService(NotificationManager::class.java)
        val id = "daily_hadith"
        val before = manager.getNotificationChannel(id)
        try {
            for (locale in listOf("en", "ar", "ru", "kk", "ky", "uz", "tr", "id", "ur", "fr", "es-419", "pt-BR", "sw", "hi", "bn")) {
                ensureDailyNotificationChannel(context, locale)
                val channel = manager.getNotificationChannel(id)
                assertNotNull(channel)
                assertEquals(WidgetCopy.text(WidgetCopy.Key.notificationChannelTitle, locale), channel.name.toString())
                assertEquals(WidgetCopy.text(WidgetCopy.Key.notificationChannelDescription, locale), channel.description)
                if (before != null) assertEquals(before.importance, channel.importance)
                assertEquals(WidgetCopy.text(WidgetCopy.Key.dailyTitle, locale), notificationDisplayTitle(context, locale, null))
                assertEquals("Provider source title", notificationDisplayTitle(context, locale, "Provider source title"))
            }
        } finally {
            if (before == null) manager.deleteNotificationChannel(id)
            else manager.createNotificationChannel(NotificationChannel(id, before.name, before.importance).apply { description = before.description })
        }
    }
}
