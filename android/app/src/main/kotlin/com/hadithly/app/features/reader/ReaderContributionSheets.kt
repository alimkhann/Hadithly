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
fun TranslationSubmissionSheet(
    viewModel: ReaderViewModel,
    hadith: ReaderHadith,
    existingTranslation: ReaderTranslation?,
    initialContent: String,
    onDone: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    val scope = rememberCoroutineScope()
    var content by remember { mutableStateOf(initialContent) }
    var result by remember { mutableStateOf<TranslationSubmissionResult?>(null) }
    var submitting by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    Column(
        verticalArrangement = Arrangement.spacedBy(16.dp),
        modifier = Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(20.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Text(if (result == null) "Suggest a translation" else "AI review", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary, modifier = Modifier.weight(1f))
            TextButton(onClick = onDone) { Text(if (result == null) "Cancel" else "Done", color = colors.accent) }
        }

        when {
            result != null -> SubmissionVerdict(result!!, onRevise = { result = null; error = null })
            !viewModel.canContribute -> Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.fillMaxWidth().padding(vertical = 32.dp).testTag("submission.signInRequired"),
            ) {
                Icon(Icons.Filled.PersonOutline, null, tint = colors.textSecondary)
                Text("Sign in to contribute a translation.", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
                Text("You can sign in from Settings, then return to this hadith.", fontSize = 12.sp, color = colors.textSecondary)
            }
            else -> {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(hadith.referenceDisplay, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
                    val languageName = SupportedLanguages.all.firstOrNull { it.first == viewModel.state.value.language }?.second ?: viewModel.state.value.language
                    Text(languageName, fontSize = 12.sp, color = colors.textSecondary)
                }
                Text(
                    "Write the clearest faithful rendering you can. AI checks meaning and terminology; an admin decides whether it is published.",
                    fontSize = 12.sp,
                    color = colors.textSecondary,
                )
                OutlinedTextField(
                    value = content,
                    onValueChange = { content = it },
                    modifier = Modifier.fillMaxWidth().height(230.dp).testTag("submission.editor"),
                    colors = editorColors(),
                )
                error?.let { Text(it, fontSize = 12.sp, color = colors.textSecondary, modifier = Modifier.testTag("submission.error")) }
                Button(
                    enabled = !submitting && content.isNotBlank(),
                    onClick = {
                        val proposal = content.trim()
                        if (proposal.isEmpty()) return@Button
                        submitting = true
                        error = null
                        scope.launch {
                            runCatching { viewModel.submitTranslation(hadith, proposal, existingTranslation) }
                                .onSuccess { result = it }
                                .onFailure { error = it.message ?: it.toString() }
                            submitting = false
                        }
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = colors.accent,
                        contentColor = Color.Black,
                        disabledContainerColor = colors.surfaceElevated,
                        disabledContentColor = colors.textSecondary,
                    ),
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.fillMaxWidth().testTag("submission.submit"),
                ) {
                    if (submitting) CircularProgressIndicator(color = Color.Black, modifier = Modifier.padding(end = 8.dp), strokeWidth = 2.dp)
                    Text(if (submitting) "Reviewing…" else "Submit for AI review", fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

@Composable
private fun SubmissionVerdict(result: TranslationSubmissionResult, onRevise: () -> Unit) {
    val colors = LocalHadithlyColors.current
    val title: String
    val message: String
    val icon: ImageVector
    when (result.status) {
        "rejected" -> {
            title = "Please revise this translation"
            message = "The AI review found meaning or terminology concerns, so this version will not be published."
            icon = Icons.Filled.WarningAmber
        }
        "needs_admin" -> {
            title = "Sent for careful admin review"
            message = "The AI found uncertainty that needs a human decision. Your proposal is waiting for an admin."
            icon = Icons.Filled.PersonOutline
        }
        else -> {
            title = "AI review passed"
            message = "Your proposal is waiting for admin approval. It is not public yet."
            icon = Icons.Filled.CheckCircle
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(16.dp), modifier = Modifier.testTag("submission.verdict")) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
            Icon(icon, null, tint = colors.accent)
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
                Text(message, fontSize = 14.sp, color = colors.textSecondary)
            }
        }
        if (result.aiReview.reviewNotes.isEmpty()) {
            Text("The review found no specific meaning or terminology issues.", fontSize = 12.sp, color = colors.textSecondary)
        } else {
            Text("Review notes", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
            result.aiReview.reviewNotes.forEach { Text("• $it", fontSize = 12.sp, color = colors.textSecondary) }
        }
        Text(
            "Reviewed by ${result.aiReview.model}. AI review is advisory; only an admin can publish a contribution.",
            fontSize = 11.sp,
            color = colors.textSecondary.copy(alpha = 0.8f),
        )
        if (result.status == "rejected") TextButton(onClick = onRevise, modifier = Modifier.testTag("submission.revise")) {
            Text("Revise proposal", color = colors.accent, fontWeight = FontWeight.SemiBold)
        }
    }
}

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
            TextButton(onClick = onDone) { Text(if (submitted) "Done" else "Cancel", color = colors.accent) }
        }
        if (submitted) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.fillMaxWidth().padding(vertical = 32.dp).testTag("report.confirmation"),
            ) {
                Icon(Icons.Filled.CheckCircle, null, tint = colors.accent)
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
                colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = Color.Black),
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
