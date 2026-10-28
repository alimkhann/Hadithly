package com.hadithly.app.features.widgets

import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetHostView
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import android.content.ComponentName
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.glance.appwidget.AppWidgetId
import androidx.test.platform.app.InstrumentationRegistry
import com.hadithly.app.core.data.HadithRef
import com.hadithly.app.core.data.ProgressEntry
import com.hadithly.app.core.widgets.DailyWidgetPayload
import com.hadithly.app.core.widgets.WidgetCopy
import com.hadithly.app.core.widgets.WidgetSnapshotStore
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.io.File
import java.time.LocalDate
import java.time.ZoneId

class WidgetCopyHostTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Test fun realRemoteViewsRenderLocalizedCopyForEverySupportedLocale() = runBlocking {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val app = instrumentation.targetContext
        val automation = instrumentation.uiAutomation
        fun shell(command: String): String = ParcelFileDescriptor.AutoCloseInputStream(automation.executeShellCommand(command)).bufferedReader().use { it.readText() }
        fun grants(): String = shell("dumpsys appwidget").lineSequence().dropWhile { it.trim() != "Grants:" }.drop(1).takeWhile { it.isNotBlank() }.joinToString("\n")
        val userId = shell("am get-current-user").trim().toInt()
        val hadBindPermission = grants().contains(app.packageName)
        val grantOutput = shell("appwidget grantbind --package ${app.packageName} --user $userId")
        val prefs = app.getSharedPreferences("hadithly.widgets", 0)
        val original = listOf("daily.v2", "continue.v2", "continue.v1").associateWith { prefs.getString(it, null) }
        val manager = AppWidgetManager.getInstance(app)
        lateinit var host: AppWidgetHost
        instrumentation.runOnMainSync { host = AppWidgetHost(app, 0xA4401) }
        val ids = mutableListOf<Int>()
        try {
            assertTrue("Widget binding permission: $grantOutput", grantOutput.isBlank())
            assertTrue("Widget bind permission was not recorded for ${app.packageName}: ${grants()}", grants().contains(app.packageName))
            val dailyId = host.allocateAppWidgetId().also(ids::add)
            val continueId = host.allocateAppWidgetId().also(ids::add)
            val options = Bundle().apply {
                putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 320)
                putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 320)
                putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 200)
                putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 200)
                putInt(AppWidgetManager.OPTION_APPWIDGET_HOST_CATEGORY, android.appwidget.AppWidgetProviderInfo.WIDGET_CATEGORY_HOME_SCREEN)
            }
            val providers = manager.installedProviders.filter { it.provider.packageName == app.packageName }.map { it.provider.className }
            assertTrue("Target widget providers unavailable: $providers; host=${compose.activity.packageName}; target=${app.packageName}", providers.contains(DailyHadithWidgetReceiver::class.java.name))
            assertTrue("Daily widget provider did not bind; host=${compose.activity.packageName}; target=${app.packageName}; grants=${grants()}", manager.bindAppWidgetIdIfAllowed(dailyId, ComponentName(app, DailyHadithWidgetReceiver::class.java), options))
            assertTrue("Continue widget provider did not bind", manager.bindAppWidgetIdIfAllowed(continueId, ComponentName(app, ContinueReadingWidgetReceiver::class.java), options))
            lateinit var dailyView: AppWidgetHostView
            compose.setContent {
                Column(Modifier.statusBarsPadding().navigationBarsPadding()) {
                    AndroidView(factory = { host.createView(it, dailyId, manager.getAppWidgetInfo(dailyId)).also { view -> dailyView = view } }, modifier = Modifier.width(320.dp).height(220.dp))
                    AndroidView(factory = { host.createView(it, continueId, manager.getAppWidgetInfo(continueId)) }, modifier = Modifier.width(320.dp).height(220.dp))
                }
            }
            instrumentation.runOnMainSync { host.startListening() }
            val store = WidgetSnapshotStore(app)
            val ref = HadithRef("widget-copy-fixture", "fixture", "Source collection", "1", "37", "Prepared text", "Prepared text", "Original source reference")
            for (locale in listOf("en", "ar", "ru", "kk", "ky", "uz", "tr", "id", "ur", "fr", "es-419", "pt-BR", "sw", "hi", "bn")) {
                val now = System.currentTimeMillis().toDouble()
                store.saveDaily(DailyWidgetPayload("fixture", "1", "Public source reference", "Prepared interface example", "Prepared Arabic example", locale, true, true, true, "Source scope", LocalDate.now().toString(), ZoneId.systemDefault().id, now))
                store.markDailyOffline(locale, ZoneId.systemDefault().id)
                store.saveContinue(ProgressEntry("fixture", ref, updatedAt = now), locale, 0.37, 37, 100)
                DailyHadithWidget().update(app, AppWidgetId(dailyId))
                ContinueReadingWidget().update(app, AppWidgetId(continueId))
                val expected = listOf(WidgetCopy.text(WidgetCopy.Key.dailyTitle, locale), WidgetCopy.text(WidgetCopy.Key.continueTitle, locale), WidgetCopy.text(WidgetCopy.Key.dailyAI, locale), WidgetCopy.text(WidgetCopy.Key.dailyOffline, locale), WidgetCopy.format(WidgetCopy.Key.continueProgressTotal, locale, 37, 100), "Original source reference")
                var matched = false
                repeat(80) {
                    if (!matched) {
                        matched = expected.all { contains(automation.rootInActiveWindow, it) }
                        if (!matched) delay(150)
                    }
                }
                assertTrue("Real widget text did not render for $locale", matched)
                instrumentation.runOnMainSync {
                    for (example in listOf("Prepared interface example")) {
                        val excerpt = textViews(dailyView).firstOrNull { it.text.toString() == example }
                        val visible = android.graphics.Rect()
                        assertTrue("Daily excerpt is not visible for $locale: $example; views=${textViews(dailyView).map { "${it.text}:${it.width}x${it.height}" }}", excerpt != null && excerpt.getGlobalVisibleRect(visible) && visible.height() > 0 && excerpt.layout?.lineCount != 0)
                    }
                    val metadata = textViews(dailyView).first { it.text.contains(WidgetCopy.text(WidgetCopy.Key.dailyOffline, locale)) }
                    val layout = metadata.layout
                    assertTrue("Metadata missing layout for $locale", layout != null)
                    assertTrue("Metadata is visually truncated for $locale", (0 until layout.lineCount).all { layout.getEllipsisCount(it) == 0 })
                    val title = textViews(dailyView).first { it.text.toString() == WidgetCopy.text(WidgetCopy.Key.dailyTitle, locale) }
                    val expectedGravity = if (com.hadithly.app.core.preferences.LocaleFallback.isRTL(locale)) android.view.Gravity.RIGHT else android.view.Gravity.LEFT
                    assertTrue("Title alignment ignored $locale", title.gravity and android.view.Gravity.HORIZONTAL_GRAVITY_MASK == expectedGravity)
                }
                val bitmap = automation.takeScreenshot()
                val output = File(app.getExternalFilesDir(null), "widget-copy-host-$locale.png")
                output.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
                bitmap.recycle()
                shell("cp ${output.absolutePath} /sdcard/Pictures/widget-copy-host-$locale.png")
            }
        } finally {
            instrumentation.runOnMainSync { host.stopListening() }
            ids.forEach(host::deleteAppWidgetId)
            prefs.edit().apply {
                original.forEach { (key, value) -> if (value == null) remove(key) else putString(key, value) }
            }.commit()
            if (!hadBindPermission) shell("appwidget revokebind --package ${app.packageName} --user $userId")
        }
    }

    private fun textViews(view: View): List<TextView> = when (view) {
        is TextView -> listOf(view)
        is ViewGroup -> (0 until view.childCount).flatMap { textViews(view.getChildAt(it)) }
        else -> emptyList()
    }

    private fun contains(node: AccessibilityNodeInfo?, value: String): Boolean {
        if (node == null) return false
        if (node.text?.contains(value) == true || node.contentDescription?.contains(value) == true) return true
        return (0 until node.childCount).any { contains(node.getChild(it), value) }
    }
}
