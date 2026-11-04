package com.hadithly.app.core.push

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import androidx.test.platform.app.InstrumentationRegistry
import com.google.firebase.messaging.RemoteMessage
import com.hadithly.app.MainActivity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class SyntheticNotificationTest {
    @Test fun syntheticReceivePostsAndTapsExactTarget() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        if (Build.VERSION.SDK_INT >= 33) instrumentation.uiAutomation.grantRuntimePermission(context.packageName, Manifest.permission.POST_NOTIFICATIONS)
        val manager = context.getSystemService(NotificationManager::class.java)
        val monitor = instrumentation.addMonitor(MainActivity::class.java.name, null, false)
        val message = RemoteMessage(Bundle().apply {
            putString("gcm.n.e", "1")
            putString("gcm.n.title", "Synthetic notification")
            putString("gcm.n.body", "Synthetic cached translation")
            putString("collectionSlug", "bukhari")
            putString("providerHadithId", "7")
            putString("volumeId", "1")
            putString("locale", "ru")
            putString("ai", "1")
        })
        try {
            postDailyNotification(context, message)
            val posted = manager.activeNotifications.single { it.id == 1001 }.notification
            assertEquals("Synthetic notification", posted.extras.getCharSequence(Notification.EXTRA_TITLE).toString())
            assertEquals("Synthetic cached translation", posted.extras.getCharSequence(Notification.EXTRA_TEXT).toString())
            posted.contentIntent.send()
            val activity = instrumentation.waitForMonitorWithTimeout(monitor, 10000)
            assertNotNull(activity)
            assertEquals("bukhari", activity.intent.getStringExtra("collectionSlug"))
            assertEquals("7", activity.intent.getStringExtra("providerHadithId"))
            assertEquals("1", activity.intent.getStringExtra("volumeId"))
            assertEquals("ru", activity.intent.getStringExtra("locale"))
            assertEquals("1", activity.intent.getStringExtra("ai"))
            val target = notificationHadithTarget(listOf("collectionSlug", "providerHadithId", "volumeId", "locale", "ai").associateWith { activity.intent.getStringExtra(it) })
            assertEquals("7", target?.providerHadithId)
            assertEquals("bukhari", target?.collectionSlug)
            activity.finish()
        } finally {
            manager.cancel(1001)
            instrumentation.removeMonitor(monitor)
        }
    }
}
