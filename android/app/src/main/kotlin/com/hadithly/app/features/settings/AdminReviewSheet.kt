@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.hadithly.app.features.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.hadithly.app.core.data.AdminTranslationSubmission
import com.hadithly.app.core.data.SupportedLanguages
import com.hadithly.app.core.theme.LocalHadithlyColors
import com.hadithly.app.features.main.rememberApp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun AdminReviewSheet(onDismiss: () -> Unit) {
    val app = rememberApp()
    val colors = LocalHadithlyColors.current
    val scope = rememberCoroutineScope()
    var submissions by remember { mutableStateOf<List<AdminTranslationSubmission>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var approvingIds by remember { mutableStateOf<Set<String>>(emptySet()) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        try {
            withContext(Dispatchers.IO) {
                app.repository.subscribe<List<AdminTranslationSubmission>>("community:listPendingSubmissions")
                    .collect { submissions = it; loading = false; error = null }
            }
        } catch (failure: Exception) {
            error = failure.message ?: failure.toString()
            loading = false
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = colors.background) {
        Column(Modifier.fillMaxSize()) {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
                Text("Translation review", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary, modifier = Modifier.weight(1f))
                TextButton(onClick = onDismiss) { Text("Done", color = colors.accent) }
            }
            when {
                loading -> Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth().padding(48.dp)) {
                    CircularProgressIndicator(color = colors.textSecondary)
                }
                submissions.isEmpty() -> Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                    modifier = Modifier.fillMaxWidth().padding(48.dp).testTag("admin.empty"),
                ) {
                    Icon(Icons.Filled.CheckCircle, null, tint = colors.accent)
                    Text("No translations are waiting", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
                    error?.let { Text(it, fontSize = 12.sp, color = colors.textSecondary) }
                }
                else -> LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
                ) {
                    error?.let { item { Text(it, fontSize = 12.sp, color = colors.textSecondary) } }
                    items(submissions, key = { it._id }) { submission ->
                        SubmissionCard(
                            submission = submission,
                            approving = submission._id in approvingIds,
                            onApprove = {
                                if (submission._id in approvingIds) return@SubmissionCard
                                approvingIds = approvingIds + submission._id
                                scope.launch {
                                    runCatching { app.repository.approveSubmission(submission._id) }
                                        .onFailure { error = it.message ?: it.toString() }
                                    approvingIds = approvingIds - submission._id
                                }
                            },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun SubmissionCard(submission: AdminTranslationSubmission, approving: Boolean, onApprove: () -> Unit) {
    val colors = LocalHadithlyColors.current
    Column(
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(16.dp)).padding(16.dp),
    ) {
        Row(verticalAlignment = Alignment.Top) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(submission.hadith?.referenceDisplay ?: "Hadith unavailable", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
                Text(SupportedLanguages.all.firstOrNull { it.first == submission.language }?.second ?: submission.language, fontSize = 12.sp, color = colors.textSecondary)
            }
            Text(if (submission.status == "needs_admin") "Careful review" else "AI passed", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = colors.accent)
        }
        Text(submission.proposedContent, fontSize = 16.sp, lineHeight = 23.sp, color = colors.textPrimary.copy(alpha = 0.92f))
        submission.aiReview.reviewNotes.forEach { Text("• $it", fontSize = 11.sp, color = colors.textSecondary) }
        Button(
            enabled = !approving,
            onClick = onApprove,
            colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = Color.Black),
            shape = RoundedCornerShape(10.dp),
            modifier = Modifier.fillMaxWidth().testTag("admin.approve.${submission._id}"),
        ) {
            if (approving) CircularProgressIndicator(color = Color.Black, strokeWidth = 2.dp, modifier = Modifier.padding(end = 8.dp))
            Text("Approve and publish", fontWeight = FontWeight.SemiBold)
        }
    }
}
