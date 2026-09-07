package com.hadithly.app.features.today

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.automirrored.filled.NavigateNext
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.hadithly.app.core.data.DailyHadith
import com.hadithly.app.core.data.HadithRef
import com.hadithly.app.core.theme.LocalHadithlyColors
import com.hadithly.app.features.main.ReaderOpenTarget
import com.hadithly.app.features.main.rememberApp
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun TodayScreen(onOpenTarget: (ReaderOpenTarget) -> Unit) {
    val app = rememberApp()
    val colors = LocalHadithlyColors.current
    val progress by app.library.progress.collectAsStateWithLifecycle()
    val continueReading = progress.filter { it.hadith != null }.maxByOrNull { it.updatedAt }
    var daily by remember { mutableStateOf<DailyHadith?>(null) }
    var loading by remember { mutableStateOf(true) }
    var failed by remember { mutableStateOf(false) }
    var reloadKey by remember { mutableStateOf(0) }

    LaunchedEffect(reloadKey) {
        loading = true
        runCatching { app.repository.getDailyHadith() }
            .onSuccess { daily = it; failed = false }
            .onFailure { failed = true }
        loading = false
    }

    Column(
        verticalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
    ) {
        Text("Today", fontSize = 30.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("As-salamu alaykum", fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
            Text(
                SimpleDateFormat("EEEE, MMM d", Locale.getDefault()).format(Date()),
                fontSize = 14.sp,
                color = colors.textSecondary,
            )
        }

        when {
            daily != null -> DailyCard(daily!!) {
                onOpenTarget(
                    ReaderOpenTarget(
                        slug = daily!!.collectionSlug,
                        name = daily!!.collectionName,
                        volumeId = daily!!.volumeId,
                        hadithNumber = daily!!.providerHadithId,
                    ),
                )
            }
            loading -> CardShell {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(color = colors.textSecondary, modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                    Text("Bringing today's hadith…", fontSize = 14.sp, color = colors.textSecondary)
                }
            }
            failed -> CardShell {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Today's hadith could not load", fontSize = 14.sp, fontWeight = FontWeight.Medium, color = colors.textPrimary)
                    TextButton(onClick = { reloadKey += 1 }) { Text("Try again", color = colors.accent) }
                }
            }
            else -> CardShell {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("No hadith cached yet", fontSize = 14.sp, fontWeight = FontWeight.Medium, color = colors.textPrimary)
                    Text("Open a collection in the Library and today's hadith will appear here.", fontSize = 12.sp, color = colors.textSecondary)
                }
            }
        }

        continueReading?.hadith?.let { ref ->
            ContinueReadingCard(ref) {
                onOpenTarget(
                    ReaderOpenTarget(
                        slug = continueReading.collectionSlug,
                        name = ref.collectionName,
                        volumeId = ref.volumeId,
                        hadithNumber = ref.hadithNumber,
                    ),
                )
            }
        }
        Spacer(Modifier.size(12.dp))
    }
}

@Composable
private fun DailyCard(hadith: DailyHadith, onClick: () -> Unit) {
    val colors = LocalHadithlyColors.current
    CardShell(
        modifier = Modifier
            .clickable(onClick = onClick)
            .testTag("today.dailyCard"),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("HADITH OF THE DAY", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = colors.accent)
            Text(hadith.arabicText, fontSize = 22.sp, lineHeight = 38.sp, color = colors.textPrimary)
            hadith.englishText?.takeIf { it.isNotBlank() }?.let {
                Text(it, fontSize = 15.sp, lineHeight = 21.sp, color = colors.textPrimary.copy(alpha = 0.92f))
            }
            Text(hadith.referenceDisplay, fontSize = 11.sp, color = colors.textSecondary)
            Text(
                hadith.authenticity.displayLabel,
                fontSize = 11.sp,
                color = colors.textSecondary,
                modifier = Modifier.testTag("today.authenticity"),
            )
        }
    }
}

@Composable
private fun ContinueReadingCard(ref: HadithRef, onClick: () -> Unit) {
    val colors = LocalHadithlyColors.current
    CardShell(
        modifier = Modifier
            .clickable(onClick = onClick)
            .testTag("today.continueCard"),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier.size(38.dp).background(colors.accentSoft, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.AutoMirrored.Filled.MenuBook, null, tint = colors.accent, modifier = Modifier.size(20.dp))
            }
            Spacer(Modifier.size(14.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("CONTINUE READING", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = colors.accent)
                Text(ref.collectionName, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = colors.textPrimary)
                if (ref.referenceDisplay.isNotBlank()) Text(ref.referenceDisplay, fontSize = 11.sp, color = colors.textSecondary)
            }
            Icon(Icons.AutoMirrored.Filled.NavigateNext, null, tint = colors.textSecondary, modifier = Modifier.size(16.dp))
        }
    }
}

@Composable
private fun CardShell(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val colors = LocalHadithlyColors.current
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.surface, RoundedCornerShape(16.dp))
            .then(modifier)
            .padding(16.dp),
    ) { content() }
}
