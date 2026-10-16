package com.hadithly.app.core.theme

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.hadithly.app.core.preferences.nativeText

@Composable
fun QuietEmptyState(title: String, message: String, icon: ImageVector, modifier: Modifier = Modifier, action: (@Composable () -> Unit)? = null) {
    val colors = LocalHadithlyColors.current
    Box(modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Column(Modifier.widthIn(max = 340.dp).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(icon, null, Modifier.size(30.dp), tint = colors.textSecondary)
            Text(nativeText(title), style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center, color = colors.textPrimary)
            Text(nativeText(message), style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center, color = colors.textSecondary)
            action?.invoke()
        }
    }
}
