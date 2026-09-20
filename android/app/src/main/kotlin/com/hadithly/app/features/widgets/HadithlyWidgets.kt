package com.hadithly.app.features.widgets

import android.content.ComponentName
import android.content.Context
import android.app.KeyguardManager
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalSize
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.hadithly.app.core.widgets.WidgetRefreshPolicy
import com.hadithly.app.core.widgets.WidgetSnapshotStore
import com.hadithly.app.core.widgets.DailyWidgetSnapshot
import com.hadithly.app.core.widgets.ContinueWidgetPresentation
import com.hadithly.app.core.data.ProgressEntry
import com.hadithly.app.features.library.continueReadingTarget

private val background = ColorProvider(Color(0xFF1A1A1A))
private val foreground = ColorProvider(Color(0xFFF2F2F2))
private val secondary = ColorProvider(Color(0xFF98989E))
private fun isLocked(context: Context): Boolean =
    context.getSystemService(KeyguardManager::class.java)?.isDeviceLocked == true

class DailyHadithWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) = provideContent {
        val locked = isLocked(context)
        val snapshot = if (locked) null else WidgetSnapshotStore(context).daily()
        val size = dailyWidgetSize(LocalSize.current)
        Column(
            modifier = GlanceModifier.fillMaxSize().background(background).padding(14.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Text("DAILY HADITH", style = TextStyle(color = secondary, fontWeight = FontWeight.Medium))
            if (snapshot == null) {
                Text(if (locked) "Unlock Hadithly to view today’s hadith." else "Open Hadithly to prepare today’s hadith.", style = TextStyle(color = foreground))
            } else {
                Column(modifier = GlanceModifier.defaultWeight().clickable(actionStartActivity(ComponentName(context, DailyWidgetEntryActivity::class.java)))) {
                    Text(snapshot.reference, style = TextStyle(color = foreground, fontWeight = FontWeight.Bold), maxLines = 1)
                    if (size == DailyWidgetSize.LARGE && snapshot.arabicVisible && snapshot.translationVisible) {
                        Text(snapshot.arabicText, style = TextStyle(color = foreground), maxLines = 4)
                        Text(snapshot.text, style = TextStyle(color = foreground), maxLines = 4)
                    } else {
                        Text(if (snapshot.arabicVisible && !snapshot.translationVisible) snapshot.arabicText else snapshot.text, style = TextStyle(color = foreground), maxLines = size.previewLines)
                    }
                    Text(dailyMetadata(snapshot), style = TextStyle(color = secondary), maxLines = 1)
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
    if (snapshot.isAI) append(" · AI translation")
    if (snapshot.isOffline) append(" · Saved offline copy")
    if (WidgetRefreshPolicy.isStale(snapshot)) append(" · Update when opened")
}

class DailyHadithWidgetReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget = DailyHadithWidget() }

class ContinueReadingWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) = provideContent {
        val locked = isLocked(context)
        val snapshot = if (locked) null else WidgetSnapshotStore(context).continueReading()
        val size = continueWidgetSize(LocalSize.current)
        Column(
            modifier = GlanceModifier.fillMaxSize().background(background).padding(14.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Text("CONTINUE READING", style = TextStyle(color = secondary, fontWeight = FontWeight.Medium))
            if (snapshot == null) {
                Text(if (locked) ContinueWidgetPresentation.LOCK_MESSAGE else ContinueWidgetPresentation.EMPTY_MESSAGE, style = TextStyle(color = foreground))
            } else {
                val presentation = ContinueWidgetPresentation(snapshot.reference, snapshot.arabicExcerpt, snapshot.translationExcerpt, snapshot.arabicVisible, snapshot.translationVisible, snapshot.progressFraction, snapshot.progressLabel, snapshot.locale)
                Column(modifier = GlanceModifier.defaultWeight().clickable(actionStartActivity(ComponentName(context, ContinueWidgetEntryActivity::class.java)))) {
                    Text(presentation.reference, style = TextStyle(color = foreground, fontWeight = FontWeight.Bold), maxLines = 1)
                    if (size == ContinueWidgetSize.LARGE && presentation.arabicVisible && presentation.translationVisible) {
                        Text(presentation.arabicExcerpt, style = TextStyle(color = foreground), maxLines = 4)
                        Text(presentation.translationExcerpt, style = TextStyle(color = foreground), maxLines = 4)
                    } else if (size != ContinueWidgetSize.COMPACT && presentation.translationExcerpt.isNotBlank()) {
                        Text(if (presentation.arabicVisible && !presentation.translationVisible) presentation.arabicExcerpt else presentation.translationExcerpt, style = TextStyle(color = foreground), maxLines = if (size == ContinueWidgetSize.MEDIUM) presentation.mediumExcerptLines else presentation.largeExcerptLines)
                    }
                    Text(snapshot.progressLabel, style = TextStyle(color = secondary), maxLines = 1)
                    if (WidgetRefreshPolicy.isStale(snapshot.updatedAt)) {
                        Text("Position will be checked when opened", style = TextStyle(color = secondary), maxLines = 1)
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
