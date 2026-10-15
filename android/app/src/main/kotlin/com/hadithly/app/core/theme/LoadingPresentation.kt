package com.hadithly.app.core.theme

import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.ContentDrawScope
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.hadithly.app.core.preferences.nativeText
import kotlin.math.sin

object InterfaceMotion {
    const val QUICK = 150
    const val STEP = 250
    const val REVEAL = 400
    const val SHIMMER = 2000
    const val THINKING_PULSE = 1500
    const val TRAVEL_DP = 8
}

@Composable
fun rememberMotionAllowed(): Boolean {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    fun animationsEnabled() = Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) > 0f
    var enabled by remember { mutableStateOf(animationsEnabled()) }
    var active by remember { mutableStateOf(lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) }
    DisposableEffect(context, lifecycle) {
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) { enabled = animationsEnabled() }
        }
        val lifecycleObserver = LifecycleEventObserver { _, _ ->
            active = lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)
            enabled = animationsEnabled()
        }
        context.contentResolver.registerContentObserver(Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE), false, observer)
        lifecycle.addObserver(lifecycleObserver)
        onDispose {
            context.contentResolver.unregisterContentObserver(observer)
            lifecycle.removeObserver(lifecycleObserver)
        }
    }
    return enabled && active
}

@Composable
private fun shimmerProgress(animated: Boolean, duration: Int = InterfaceMotion.SHIMMER): Float? {
    if (!animated || !rememberMotionAllowed()) return null
    val transition = rememberInfiniteTransition(label = "loading shimmer")
    return transition.animateFloat(0f, 1f, infiniteRepeatable(tween(duration, easing = LinearEasing)), label = "shimmer position").value
}

private fun ContentDrawScope.highlight(progress: Float, color: Color) {
    val start = size.width * (progress * 2 - 0.5f)
    drawRect(Brush.linearGradient(listOf(Color.Transparent, color, Color.Transparent), start = Offset(start, 0f), end = Offset(start + size.width * .5f, size.height)))
}

enum class SkeletonKind { Paragraph, Article, Daily, Rows, Compact }

@Composable
fun ContentSkeleton(
    kind: SkeletonKind = SkeletonKind.Paragraph,
    animated: Boolean = true,
    label: String = nativeText("Loading…"),
    modifier: Modifier = Modifier,
) {
    val colors = LocalHadithlyColors.current
    val progress = shimmerProgress(animated)
    val accessibleLabel = nativeText(label)
    Column(modifier.testTag("loading.skeleton").clearAndSetSemantics { contentDescription = accessibleLabel }) {
        when (kind) {
            SkeletonKind.Compact -> SkeletonLines(listOf(.78f, .48f), 7.dp, 7.dp, progress)
            SkeletonKind.Paragraph -> SkeletonLines(listOf(.96f, .88f, .63f), 11.dp, 10.dp, progress)
            SkeletonKind.Article -> Column(verticalArrangement = Arrangement.spacedBy(28.dp)) {
                SkeletonLines(listOf(.44f, .68f), 12.dp, 10.dp, progress)
                SkeletonLines(listOf(.95f, .89f, .97f, .61f), 20.dp, 22.dp, progress)
                SkeletonLines(listOf(.96f, .91f, .7f), 11.dp, 12.dp, progress)
            }
            SkeletonKind.Daily -> Column(verticalArrangement = Arrangement.spacedBy(22.dp)) {
                SkeletonLines(listOf(.48f), 10.dp, 0.dp, progress)
                SkeletonLines(listOf(.94f, .86f, .58f), 18.dp, 18.dp, progress)
                SkeletonLines(listOf(.96f, .84f, .64f), 11.dp, 10.dp, progress)
            }
            SkeletonKind.Rows -> Column(verticalArrangement = Arrangement.spacedBy(20.dp)) {
                repeat(3) {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(46.dp, 60.dp).clip(RoundedCornerShape(10.dp)).background(colors.surfaceElevated))
                        SkeletonLines(listOf(.92f, .62f, .42f), 10.dp, 9.dp, progress)
                    }
                }
            }
        }
    }
}

@Composable
private fun SkeletonLines(widths: List<Float>, height: Dp, gap: Dp, progress: Float?) {
    val colors = LocalHadithlyColors.current
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(gap)) {
        widths.forEach { fraction ->
            Box(Modifier.fillMaxWidth(fraction).height(height).clip(RoundedCornerShape(height / 2)).background(colors.surfaceElevated).drawWithContent {
                drawContent()
                if (progress != null) highlight(progress, colors.interactive.copy(alpha = .12f))
            })
        }
    }
}

@Composable
fun TranslationThinkingView(modifier: Modifier = Modifier) {
    val colors = LocalHadithlyColors.current
    val progress = shimmerProgress(true)
    val pulse = shimmerProgress(true, InterfaceMotion.THINKING_PULSE)
    val label = nativeText("AI translation…")
    Column(modifier.padding(vertical = 8.dp).testTag("reader.translationLoading").clearAndSetSemantics { contentDescription = label }, verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Filled.AutoAwesome, null, tint = colors.textSecondary, modifier = Modifier.size(14.dp))
            val brush = if (progress != null) Brush.linearGradient(
                listOf(colors.textSecondary, colors.textPrimary, colors.textSecondary),
                start = Offset(-100f + progress * 600f, 0f), end = Offset(progress * 600f, 0f),
            ) else null
            Text(label, style = MaterialTheme.typography.labelMedium.copy(brush = brush), color = if (brush == null) colors.textSecondary else Color.Unspecified)
            Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                repeat(3) { index ->
                    val opacity = if (pulse == null) .6f else .35f + .65f * ((sin(pulse * 6.283185f - index * .9f) + 1) / 2)
                    Box(Modifier.size(3.dp).background(colors.textSecondary.copy(alpha = opacity), RoundedCornerShape(50)))
                }
            }
        }
        ContentSkeleton(label = label)
    }
}

@Composable
fun ArticleLoadingView(title: String, modifier: Modifier = Modifier) {
    val colors = LocalHadithlyColors.current
    Column(modifier.fillMaxSize().padding(horizontal = 24.dp).padding(top = 96.dp), verticalArrangement = Arrangement.spacedBy(28.dp)) {
        Text(title, style = MaterialTheme.typography.bodyMedium, color = colors.textSecondary)
        ContentSkeleton(SkeletonKind.Article, label = title)
    }
}
