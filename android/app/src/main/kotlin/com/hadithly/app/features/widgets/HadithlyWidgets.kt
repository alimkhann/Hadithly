package com.hadithly.app.features.widgets

import android.content.ComponentName
import android.content.Context
import android.app.KeyguardManager
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalSize
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.hadithly.app.core.widgets.WidgetRefreshPolicy
import com.hadithly.app.core.widgets.WidgetSnapshotStore
import com.hadithly.app.core.widgets.DailyWidgetSnapshot
import com.hadithly.app.core.widgets.WidgetCopy
import com.hadithly.app.core.widgets.ContinueWidgetPresentation
import com.hadithly.app.core.data.ProgressEntry
import com.hadithly.app.features.library.continueReadingTarget

private val background = ColorProvider(Color(0xFF1A1A1A))
private val foreground = ColorProvider(Color(0xFFF2F2F2))
private val secondary = ColorProvider(Color(0xFF98989E))
private fun isLocked(context: Context): Boolean =
    context.getSystemService(KeyguardManager::class.java)?.isDeviceLocked == true

class DailyHadithWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(
        androidx.compose.ui.unit.DpSize(180.dp, 110.dp),
        androidx.compose.ui.unit.DpSize(220.dp, 160.dp),
        androidx.compose.ui.unit.DpSize(320.dp, 250.dp),
    ))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val locked = isLocked(context)
        val store = WidgetSnapshotStore(context)
        val initial = store.daily()
        val updates = store.observeDaily()
        provideContent {
            val current by updates.collectAsState(initial)
            val snapshot = if (locked) null else current
            val locale = snapshot?.locale ?: com.hadithly.app.HadithlyApplication.instance().preferences.preferences.value.uiLocale
            val alignment = if (com.hadithly.app.core.preferences.LocaleFallback.isRTL(locale)) TextAlign.Right else TextAlign.Left
            val size = dailyWidgetSize(LocalSize.current)
            Column(modifier = GlanceModifier.fillMaxSize().background(background).padding(14.dp), verticalAlignment = Alignment.Top) {
                Text(WidgetCopy.text(WidgetCopy.Key.dailyTitle, locale), modifier = GlanceModifier.fillMaxWidth(), style = TextStyle(color = secondary, fontWeight = FontWeight.Medium, textAlign = alignment))
                if (snapshot == null) {
                    Text(WidgetCopy.text(if (locked) WidgetCopy.Key.dailyLocked else WidgetCopy.Key.dailyEmpty, locale), modifier = GlanceModifier.fillMaxWidth(), style = TextStyle(color = foreground, textAlign = alignment))
                } else {
                    Column(modifier = GlanceModifier.fillMaxWidth().defaultWeight().clickable(actionStartActivity(ComponentName(context, DailyWidgetEntryActivity::class.java)))) {
                        Text(snapshot.reference, modifier = GlanceModifier.fillMaxWidth(), style = TextStyle(color = foreground, fontWeight = FontWeight.Bold, textAlign = alignment), maxLines = 1)
                        if (LocalSize.current.height >= 160.dp) {
                            if (size == DailyWidgetSize.LARGE && snapshot.arabicVisible && snapshot.translationVisible) {
                                Text(snapshot.arabicText, modifier = GlanceModifier.fillMaxWidth().defaultWeight(), style = TextStyle(color = foreground, textAlign = TextAlign.Right), maxLines = 4)
                                Text(snapshot.text, modifier = GlanceModifier.fillMaxWidth().defaultWeight(), style = TextStyle(color = foreground, textAlign = alignment), maxLines = 4)
                            } else {
                                Text(if (snapshot.arabicVisible && !snapshot.translationVisible) snapshot.arabicText else snapshot.text,
                                    modifier = GlanceModifier.fillMaxWidth().defaultWeight(), style = TextStyle(color = foreground, textAlign = if (snapshot.arabicVisible && !snapshot.translationVisible) TextAlign.Right else alignment), maxLines = size.previewLines)
                            }
                        } else {
                            androidx.glance.layout.Spacer(GlanceModifier.defaultWeight())
                        }
                        Text(dailyMetadata(snapshot), modifier = GlanceModifier.fillMaxWidth(), style = TextStyle(color = secondary, textAlign = alignment), maxLines = 3)
                    }
                }
            }
        }
    }
}

private enum class DailyWidgetSize(val previewLines: Int) { COMPACT(3), MEDIUM(5), LARGE(10) }

private fun dailyWidgetSize(size: androidx.compose.ui.unit.DpSize): DailyWidgetSize = when {
    size.height >= 250.dp || size.width >= 320.dp -> DailyWidgetSize.LARGE
    size.width >= 220.dp || size.height >= 160.dp -> DailyWidgetSize.MEDIUM
    else -> DailyWidgetSize.COMPACT
}

private fun dailyMetadata(snapshot: DailyWidgetSnapshot): String = buildString {
    append(snapshot.sourceScope)
    if (snapshot.isAI) append(" · " + WidgetCopy.text(WidgetCopy.Key.dailyAI, snapshot.locale))
    if (snapshot.isOffline) append(" · " + WidgetCopy.text(WidgetCopy.Key.dailyOffline, snapshot.locale))
    if (WidgetRefreshPolicy.isStale(snapshot)) append(" · " + WidgetCopy.text(WidgetCopy.Key.dailyStale, snapshot.locale))
}

class DailyHadithWidgetReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget = DailyHadithWidget() }

class ContinueReadingWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val locked = isLocked(context)
        val store = WidgetSnapshotStore(context)
        val initial = store.continueReading()
        val updates = store.observeContinue()
        provideContent {
            val cached by updates.collectAsState(initial)
            val snapshot = if (locked) null else cached
            val copy = ContinueWidgetPresentation("", null, null, null, cached?.locale ?: com.hadithly.app.HadithlyApplication.instance().preferences.preferences.value.uiLocale)
            val alignment = if (copy.isRightToLeft) TextAlign.Right else TextAlign.Left
            Column(
                modifier = GlanceModifier.fillMaxSize().background(background).padding(14.dp),
                verticalAlignment = Alignment.Top,
            ) {
                Text(copy.title, modifier = GlanceModifier.fillMaxWidth(), style = TextStyle(color = secondary, fontWeight = FontWeight.Medium, textAlign = alignment))
                if (snapshot == null) {
                    Text(if (locked) copy.lockMessage else copy.emptyMessage, modifier = GlanceModifier.fillMaxWidth(), style = TextStyle(color = foreground, textAlign = alignment))
                } else {
                    val presentation = ContinueWidgetPresentation(snapshot.reference, snapshot.progressFraction, snapshot.progressOrdinal, snapshot.progressTotal, snapshot.locale)
                    Column(modifier = GlanceModifier.fillMaxWidth().defaultWeight().clickable(actionStartActivity(ComponentName(context, ContinueWidgetEntryActivity::class.java)))) {
                        Text(presentation.reference, modifier = GlanceModifier.fillMaxWidth(), style = TextStyle(color = foreground, fontWeight = FontWeight.Bold, textAlign = alignment), maxLines = 2)
                        Text(presentation.progressLabel, modifier = GlanceModifier.fillMaxWidth(), style = TextStyle(color = secondary, textAlign = alignment), maxLines = 2)
                        if (WidgetRefreshPolicy.isStale(snapshot.updatedAt)) {
                            Text(presentation.staleMessage, modifier = GlanceModifier.fillMaxWidth(), style = TextStyle(color = secondary, textAlign = alignment), maxLines = 2)
                        }
                    }
                }
            }
        }
    }
}

enum class ContinueWidgetSize { COMPACT, MEDIUM, LARGE }

fun continueWidgetSize(size: androidx.compose.ui.unit.DpSize): ContinueWidgetSize = when {
    size.height >= 250.dp || size.width >= 320.dp -> ContinueWidgetSize.LARGE
    size.width >= 220.dp || size.height >= 160.dp -> ContinueWidgetSize.MEDIUM
    else -> ContinueWidgetSize.COMPACT
}

fun continueWidgetTarget(entries: List<ProgressEntry>) =
    entries.filter { it.hadith != null && it.position != null }
        .maxByOrNull { it.updatedAt }
        ?.let(::continueReadingTarget)

class ContinueReadingWidgetReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget = ContinueReadingWidget() }

suspend fun refreshDailyWidgets(context: Context) {
    val widget = DailyHadithWidget()
    GlanceAppWidgetManager(context).getGlanceIds(DailyHadithWidget::class.java)
        .forEach { widget.update(context, it) }
}

suspend fun refreshContinueWidgets(context: Context) {
    val widget = ContinueReadingWidget()
    GlanceAppWidgetManager(context).getGlanceIds(ContinueReadingWidget::class.java)
        .forEach { widget.update(context, it) }
}
