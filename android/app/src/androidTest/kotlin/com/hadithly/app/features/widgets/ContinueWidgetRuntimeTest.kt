package com.hadithly.app.features.widgets

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.clerk.api.Clerk
import com.hadithly.app.HadithlyApplication
import com.hadithly.app.core.data.GuestReadingProgressDraft
import com.hadithly.app.core.data.GuestStoreFile
import com.hadithly.app.core.data.ReadingPosition
import com.hadithly.app.core.widgets.WidgetSnapshotStore
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class ContinueWidgetRuntimeTest {
    @Test
    fun guestPositionRendersTheInstalledWidgetWithoutCachingRawPosition() { runBlocking {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val app = instrumentation.targetContext.applicationContext as HadithlyApplication
        val before = app.guestData.snapshots()
        assumeTrue("Run this fixture only on an empty guest store", before == GuestStoreFile())
        assumeTrue("Run this fixture only while signed out", Clerk.sessionsFlow.value.isEmpty())
        assumeTrue("An installed widget is required", androidx.glance.appwidget.GlanceAppWidgetManager(app)
            .getGlanceIds(ContinueReadingWidget::class.java).isNotEmpty())

        val now = System.currentTimeMillis().toDouble()
        val position = ReadingPosition.legacy("bukhari", "57", "2", now)
        assertNotNull(position)
        val previousLocale = app.preferences.preferences.value.uiLocale
        try {
            app.preferences.setUILocale("ar")
            app.guestData.saveProgress(GuestReadingProgressDraft(
                collectionSlug = "bukhari", collectionName = "Sahih al-Bukhari",
                hadithId = "fixture-only", volumeId = "2", hadithNumber = "57",
                referenceDisplay = "Bukhari · Hadith 57", updatedAt = now,
                arabicText = "private fixture text", englishText = "private fixture translation",
                position = position,
            ))
            app.library.refresh()
            var snapshot = WidgetSnapshotStore(app).continueReading()
            repeat(30) {
                if (snapshot?.reference == "Bukhari · Hadith 57") return@repeat
                delay(100)
                snapshot = WidgetSnapshotStore(app).continueReading()
            }
            assertEquals("Bukhari · Hadith 57", snapshot?.reference)
            assertEquals(57, snapshot?.progressOrdinal)
            assertFalse(snapshot.toString().contains("private fixture text"))
            assertFalse(snapshot.toString().contains("position="))
            assertEquals("ar", snapshot?.locale)
            refreshContinueWidgets(app)
            instrumentation.uiAutomation.performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME)
            assertTrue("Populated Arabic widget did not render", waitForWidgetText(instrumentation.uiAutomation.rootInActiveWindow, "التقدم: الحديث 57") {
                instrumentation.uiAutomation.rootInActiveWindow
            })
            val screenshot = instrumentation.uiAutomation.takeScreenshot()
            val output = File(app.getExternalFilesDir(null), "w2-continue-populated.png")
            output.outputStream().use { screenshot.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        } finally {
            app.guestData.clearAll()
            app.library.refresh()
            WidgetSnapshotStore(app).saveContinue(null, "ar")
            refreshContinueWidgets(app)
            try {
                assertTrue("Cleared guest progress remained visible", waitForWidgetText(instrumentation.uiAutomation.rootInActiveWindow, "اقرأ حديثًا") {
                    instrumentation.uiAutomation.rootInActiveWindow
                })
            } finally {
                app.preferences.setUILocale(previousLocale)
            }
        }
    } }

    private suspend fun waitForWidgetText(first: AccessibilityNodeInfo?, text: String, read: () -> AccessibilityNodeInfo?): Boolean {
        if (containsText(first, text)) return true
        repeat(40) {
            delay(250)
            if (containsText(read(), text)) return true
        }
        return false
    }

    private fun containsText(node: AccessibilityNodeInfo?, text: String): Boolean {
        if (node == null) return false
        if (node.text?.contains(text) == true) return true
        return (0 until node.childCount).any { containsText(node.getChild(it), text) }
    }
}
