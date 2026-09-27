package com.hadithly.app.features.reader

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.PersonOutline
import androidx.compose.material.icons.filled.WarningAmber
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.hadithly.app.core.data.ReaderHadith
import com.hadithly.app.core.data.ReaderTranslation
import com.hadithly.app.core.data.SupportedLanguages
import com.hadithly.app.core.data.TranslationSubmissionResult
import com.hadithly.app.core.theme.LocalHadithlyColors
import kotlinx.coroutines.launch

@Composable
fun TranslationReportSheet(
    viewModel: ReaderViewModel,
    translation: ReaderTranslation,
    referenceDisplay: String,
    onDone: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    val scope = rememberCoroutineScope()
    var reason by remember { mutableStateOf("") }
    var submitting by remember { mutableStateOf(false) }
    var submitted by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    Column(verticalArrangement = Arrangement.spacedBy(14.dp), modifier = Modifier.fillMaxWidth().padding(20.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Text("Report translation", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary, modifier = Modifier.weight(1f))
            TextButton(onClick = onDone) { Text(if (submitted) "Done" else "Cancel", color = colors.interactive) }
        }
        if (submitted) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.fillMaxWidth().padding(vertical = 32.dp).testTag("report.confirmation"),
            ) {
                Icon(Icons.Filled.CheckCircle, null, tint = colors.interactive)
                Text("Report sent privately", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
                Text("An admin can review the translation and your note.", fontSize = 12.sp, color = colors.textSecondary)
            }
        } else {
            Text(referenceDisplay, fontSize = 12.sp, color = colors.textSecondary)
            Text("Describe a meaning, wording, or attribution concern. Reports are private and are not votes or ratings.", fontSize = 12.sp, color = colors.textSecondary)
            OutlinedTextField(
                value = reason,
                onValueChange = { reason = it },
                placeholder = { Text("Private reason", color = colors.textSecondary) },
                colors = editorColors(),
                modifier = Modifier.fillMaxWidth().height(130.dp).testTag("report.editor"),
            )
            error?.let { Text(it, fontSize = 12.sp, color = colors.textSecondary) }
            Button(
                enabled = !submitting && reason.isNotBlank(),
                onClick = {
                    val trimmed = reason.trim()
                    if (trimmed.isEmpty()) return@Button
                    submitting = true
                    error = null
                    scope.launch {
                        runCatching { viewModel.reportTranslation(translation, trimmed) }
                            .onSuccess { submitted = true }
                            .onFailure { error = it.message ?: it.toString() }
                        submitting = false
                    }
                },
                // Round 8: reader-palette button colors (matches the
                // submission sheet) in all four palettes — never the global
                // MaterialTheme defaults.
                colors = ButtonDefaults.buttonColors(
                    containerColor = colors.interactive,
                    contentColor = Color.Black,
                    disabledContainerColor = colors.surfaceElevated,
                    disabledContentColor = colors.textSecondary,
                ),
                shape = RoundedCornerShape(12.dp),
                modifier = Modifier.fillMaxWidth().testTag("report.submit"),
            ) { Text(if (submitting) "Sending…" else "Send private report", fontWeight = FontWeight.SemiBold) }
        }
    }
}

@Composable
private fun editorColors() = with(LocalHadithlyColors.current) {
    OutlinedTextFieldDefaults.colors(
        focusedBorderColor = accent,
        unfocusedBorderColor = surfaceElevated,
        focusedTextColor = textPrimary,
        unfocusedTextColor = textPrimary,
        cursorColor = accent,
        focusedContainerColor = surface,
        unfocusedContainerColor = surface,
    )
}
