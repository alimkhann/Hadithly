package com.hadithly.app.features.saved

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Undo
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
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
import com.hadithly.app.features.main.rememberApp

@Composable
fun SavedUndoBanner(modifier: Modifier = Modifier, testTag: String = "saved.undoBanner") {
    val app = rememberApp()
    val colors = LocalHadithlyColors.current
    val notice by app.library.undo.notice.collectAsStateWithLifecycle()
    val current = notice ?: return
    var nowElapsed by remember(current) { mutableLongStateOf(app.library.undo.now()) }
    LaunchedEffect(current) {
        while (app.library.undo.remainingFraction(current) > 0f) {
            nowElapsed = app.library.undo.now()
            withFrameMillis { }
        }
    }
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(colors.surfaceElevated, RoundedCornerShape(14.dp))
            .padding(horizontal = 14.dp, vertical = 10.dp)
            .testTag(testTag),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Filled.Undo, null, tint = colors.accent)
        Spacer(Modifier.size(10.dp))
        Text(current.message, color = colors.textPrimary, modifier = Modifier.weight(1f), fontSize = 13.sp)
        CountdownRing(fraction = current.remainingFraction(nowElapsed), tint = colors.textSecondary)
        Spacer(Modifier.size(6.dp))
        TextButton(onClick = { app.library.undo.undo() }) {
            Text(stringResource(R.string.saved_undo), color = colors.accent)
        }
    }
}

@Composable
private fun CountdownRing(fraction: Float, tint: androidx.compose.ui.graphics.Color) {
    Canvas(modifier = Modifier.size(16.dp)) {
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
