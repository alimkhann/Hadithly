package com.hadithly.app.features.saved

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.hadithly.app.R
import com.hadithly.app.core.theme.LocalHadithlyColors
import com.hadithly.app.core.theme.rememberMotionAllowed
import com.hadithly.app.features.main.rememberApp

@Composable
fun SavedUndoBanner(modifier: Modifier = Modifier, testTag: String = "saved.undoBanner") {
    val app = rememberApp()
    val colors = LocalHadithlyColors.current
    val notice by app.library.undo.notice.collectAsStateWithLifecycle()
    val motionAllowed = rememberMotionAllowed()
    var displayedNotice by remember { mutableStateOf(notice) }
    LaunchedEffect(notice) {
        if (notice != null) displayedNotice = notice
    }
    AnimatedVisibility(
        visible = notice != null,
        enter = fadeIn(tween(180)) + slideInVertically(tween(180)) { it / 2 },
        exit = fadeOut(tween(140)) + slideOutVertically(tween(140)) { it / 2 },
    ) {
        val current = notice ?: displayedNotice ?: return@AnimatedVisibility
        val countdown = remember(current) {
            Animatable(app.library.undo.remainingFraction(current))
        }
        LaunchedEffect(current, motionAllowed) {
            val remainingMillis = (current.deadlineElapsedMillis - app.library.undo.now()).coerceAtLeast(0L)
            countdown.snapTo(current.remainingFraction(app.library.undo.now()))
            if (remainingMillis == 0L) {
                countdown.snapTo(0f)
            } else if (motionAllowed) {
                countdown.animateTo(
                    targetValue = 0f,
                    animationSpec = tween(
                        durationMillis = remainingMillis.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
                        easing = LinearEasing,
                    ),
                )
            }
        }
        Row(
            modifier = modifier
                .fillMaxWidth()
                .background(colors.surfaceElevated.copy(alpha = 0.94f), RoundedCornerShape(14.dp))
                .padding(horizontal = 14.dp, vertical = 8.dp)
                .testTag(testTag),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.AutoMirrored.Filled.Undo, null, tint = colors.accent)
            Spacer(Modifier.size(10.dp))
            Text(current.message, color = colors.textPrimary, modifier = Modifier.weight(1f), fontSize = 13.sp)
            CountdownRing(progress = countdown, tint = colors.textSecondary)
            Spacer(Modifier.size(6.dp))
            TextButton(onClick = { app.library.undo.undo() }) {
                Text(stringResource(R.string.saved_undo), color = colors.accent)
            }
        }
    }
}

@Composable
private fun CountdownRing(progress: Animatable<Float, *>, tint: androidx.compose.ui.graphics.Color) {
    Canvas(modifier = Modifier.size(16.dp)) {
        // Read the animation in the draw phase so ticking only invalidates
        // this ring, not the banner's text and button composition.
        val fraction = progress.value
        val stroke = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round)
        drawCircle(color = tint.copy(alpha = 0.25f), radius = size.minDimension / 2f, style = stroke)
        if (fraction > 0f) {
            drawArc(
                color = tint,
                startAngle = -90f,
                sweepAngle = 360f * fraction,
                useCenter = false,
                style = stroke,
            )
        }
    }
}
