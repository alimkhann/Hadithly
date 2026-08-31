package com.hadithly.app.features.library

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.automirrored.filled.NavigateNext
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.hadithly.app.core.data.Collections
import com.hadithly.app.core.data.HadithRef
import com.hadithly.app.core.theme.LocalHadithlyColors
import com.hadithly.app.features.main.ReaderOpenTarget

/**
 * The seven collections. Tapping one opens the reader full screen over the
 * tab bar; the reader's close control is the way back to this tab.
 */
@Composable
fun LibraryScreen(
    onOpenCollection: (String, String) -> Unit,
    onOpenTarget: (ReaderOpenTarget) -> Unit,
) {
    val viewModel: LibraryViewModel = viewModel()
    val counts by viewModel.counts.collectAsStateWithLifecycle()
    val progressList by viewModel.progress.collectAsStateWithLifecycle()
    val continueReading = progressList
        .filter { it.hadith != null }
        .maxByOrNull { it.updatedAt }
    val colors = LocalHadithlyColors.current

    LazyColumn(
        verticalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
            .padding(horizontal = 16.dp),
    ) {
        item {
            Text(
                text = "Library",
                fontSize = 30.sp,
                fontWeight = FontWeight.Bold,
                color = colors.textPrimary,
                modifier = Modifier.padding(top = 20.dp, bottom = 8.dp),
            )
        }

        continueReading?.let { entry ->
            if (entry.hadith != null) {
                item(key = "continue") {
                    ContinueCard(
                        ref = entry.hadith,
                        onClick = {
                            onOpenTarget(
                                ReaderOpenTarget(
                                    slug = entry.collectionSlug,
                                    name = entry.hadith.collectionName,
                                    volumeId = entry.hadith.volumeId,
                                    hadithNumber = entry.hadith.hadithNumber,
                                )
                            )
                        },
                    )
                }
            }
        }

        itemsIndexed(Collections.all, key = { _, item -> item.first }) { index, (slug, name) ->
            CollectionRow(
                position = index + 1,
                name = name,
                counts = counts[slug],
                onClick = { onOpenCollection(slug, name) },
            )
        }

        item { Spacer(modifier = Modifier.height(16.dp)) }
    }
}

@Composable
private fun ContinueCard(ref: HadithRef, onClick: () -> Unit) {
    val colors = LocalHadithlyColors.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.surface, RoundedCornerShape(14.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
    ) {
        Box(
            modifier = Modifier
                .size(38.dp)
                .background(colors.accentSoft, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.MenuBook,
                contentDescription = null,
                tint = colors.accent,
                modifier = Modifier.size(20.dp),
            )
        }
        Spacer(modifier = Modifier.size(14.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = "CONTINUE READING",
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
                color = colors.accent,
            )
            Text(
                text = ref.collectionName,
                fontSize = 15.sp,
                fontWeight = FontWeight.Medium,
                color = colors.textPrimary,
            )
            if (ref.referenceDisplay.isNotEmpty()) {
                Text(
                    text = ref.referenceDisplay,
                    fontSize = 11.sp,
                    color = colors.textSecondary,
                )
            }
        }
        Icon(
            imageVector = Icons.AutoMirrored.Filled.NavigateNext,
            contentDescription = null,
            tint = colors.textSecondary,
            modifier = Modifier.size(16.dp),
        )
    }
}

@Composable
private fun CollectionRow(
    position: Int,
    name: String,
    counts: LibraryViewModel.VolumeCounts?,
    onClick: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.surface, RoundedCornerShape(14.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
    ) {
        Box(
            modifier = Modifier
                .size(34.dp)
                .background(colors.surfaceElevated, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = position.toString(),
                fontSize = 15.sp,
                color = colors.textSecondary,
            )
        }
        Spacer(modifier = Modifier.size(14.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = name,
                fontSize = 16.sp,
                fontWeight = FontWeight.Medium,
                color = colors.textPrimary,
            )
            counts?.let {
                Text(
                    text = volumeSummary(it),
                    fontSize = 11.sp,
                    color = colors.textSecondary,
                )
            }
        }
        Icon(
            imageVector = Icons.AutoMirrored.Filled.NavigateNext,
            contentDescription = null,
            tint = colors.textSecondary,
            modifier = Modifier.size(16.dp),
        )
    }
}

private fun volumeSummary(counts: LibraryViewModel.VolumeCounts): String {
    val volumes = if (counts.volumes == 1) "volume" else "volumes"
    val hadiths = if (counts.hadiths == 1) "hadith" else "hadiths"
    return "${counts.volumes} $volumes · ${counts.hadiths} $hadiths cached"
}
