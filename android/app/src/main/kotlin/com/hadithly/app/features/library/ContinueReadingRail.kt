package com.hadithly.app.features.library

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.hadithly.app.core.data.Collections
import com.hadithly.app.core.data.ProgressEntry
import com.hadithly.app.core.theme.LocalHadithlyColors
import com.hadithly.app.features.main.ReaderOpenTarget

@Composable
fun ContinueReadingRail(
    entries: List<ProgressEntry>,
    modifier: Modifier = Modifier,
    cardTagPrefix: String = "continue.card",
    onOpen: (ProgressEntry) -> Unit,
) {
    if (entries.isEmpty()) return
    LazyRow(
        modifier = modifier,
        contentPadding = PaddingValues(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        itemsIndexed(entries, key = { _, entry -> entry.collectionSlug }) { _, entry ->
            val hadith = entry.hadith ?: return@itemsIndexed
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .width(218.dp)
                    .clip(RoundedCornerShape(16.dp))
                    .background(LocalHadithlyColors.current.surface)
                    .clickable { onOpen(entry) }
                    .padding(10.dp)
                    .testTag("$cardTagPrefix.${entry.collectionSlug}"),
            ) {
                CollectionCover(
                    Collections.all.indexOfFirst { it.first == entry.collectionSlug } + 1,
                    Modifier.size(width = 52.dp, height = 76.dp),
                )
                Spacer(Modifier.size(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(hadith.collectionName, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = LocalHadithlyColors.current.textPrimary, maxLines = 2)
                    Text(hadith.referenceDisplay, fontSize = 11.sp, color = LocalHadithlyColors.current.textSecondary, maxLines = 1)
                }
            }
        }
    }
}

@Composable
fun SectionTitleRow(title: String, modifier: Modifier = Modifier) =
    Text(
        title,
        fontSize = 17.sp,
        fontWeight = FontWeight.SemiBold,
        color = LocalHadithlyColors.current.textPrimary,
        modifier = modifier,
    )

fun continueReadingEntries(progress: List<ProgressEntry>): List<ProgressEntry> =
    progress.filter { it.hadith != null }.sortedByDescending { it.updatedAt }.take(3)

fun continueReadingTarget(entry: ProgressEntry): ReaderOpenTarget {
    val hadith = entry.hadith ?: error("Continue entry has no hadith")
    return ReaderOpenTarget(
        entry.collectionSlug,
        hadith.collectionName,
        hadith.volumeId,
        hadith.hadithNumber,
        com.hadithly.app.core.data.ReaderTargetSource.CONTINUE_READING,
        entry.position,
    )
}
