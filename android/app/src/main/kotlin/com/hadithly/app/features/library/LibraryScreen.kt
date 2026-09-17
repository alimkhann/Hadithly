package com.hadithly.app.features.library

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed as gridItemsIndexed
import androidx.compose.foundation.lazy.itemsIndexed as listItemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ViewList
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.hadithly.app.core.data.Collections
import com.hadithly.app.core.data.ReaderPrefetch
import com.hadithly.app.core.data.CollectionProgressSummary
import com.hadithly.app.core.theme.LocalHadithlyColors
import com.hadithly.app.features.main.rememberApp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Collection browsing only. H2 owns authoritative progress summaries. */
@Composable
fun LibraryScreen(onOpenCollection: (String, String) -> Unit, onOpenTarget: (com.hadithly.app.features.main.ReaderOpenTarget) -> Unit) {
    val app = rememberApp()
    val viewModel: LibraryViewModel = viewModel()
    val colors = LocalHadithlyColors.current
    val progress by app.library.progress.collectAsStateWithLifecycle()
    val summaries by viewModel.summaries.collectAsStateWithLifecycle()
    var grid by rememberSaveable { mutableStateOf(true) }

    LaunchedEffect(Unit) {
        withContext(Dispatchers.IO) {
            ReaderPrefetch.warmEntryCache(app.repository, Collections.all.map { it.first }, progress)
        }
    }

    Column(Modifier.fillMaxSize().background(colors.background)) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp, top = 20.dp, bottom = 8.dp),
        ) {
            Text("Library", fontSize = 30.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary, modifier = Modifier.weight(1f))
            IconButton(
                onClick = { grid = !grid },
                modifier = Modifier.testTag("library.layoutToggle").semantics {
                    contentDescription = if (grid) "Show Library list" else "Show Library grid"
                },
            ) {
                Icon(if (grid) Icons.AutoMirrored.Filled.ViewList else Icons.Filled.GridView, null, tint = colors.textPrimary)            }
        }
        continueReadingEntries(progress).takeIf { it.isNotEmpty() }?.let { entries ->
            SectionTitleRow("Continue reading", Modifier.padding(start = 16.dp, top = 8.dp, bottom = 8.dp))
            ContinueReadingRail(
                entries,
                cardTagPrefix = "library.continueCard",
            ) { entry ->
                onOpenTarget(continueReadingTarget(entry))
            }
        }
        if (grid) {
            LazyVerticalGrid(
                columns = GridCells.Fixed(2),
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 24.dp),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalArrangement = Arrangement.spacedBy(24.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
                gridItemsIndexed(Collections.all, key = { _, collection -> collection.first }) { index, (slug, name) ->
                    GridCollection(position = index + 1, name = name, summary = summaryFor(slug, summaries[slug], progress), onClick = { onOpenCollection(slug, name) }, modifier = Modifier.testTag("library.collection.$slug"))
                }
            }
        } else {
            LazyColumn(
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
                listItemsIndexed(Collections.all, key = { _, collection -> collection.first }) { index, (slug, name) ->
                    ListCollection(position = index + 1, name = name, summary = summaryFor(slug, summaries[slug], progress), onClick = { onOpenCollection(slug, name) }, modifier = Modifier.testTag("library.collection.$slug"))
                }
            }
        }
    }
}

private fun summaryFor(slug: String, summary: CollectionProgressSummary?, progress: List<com.hadithly.app.core.data.ProgressEntry>): CollectionProgressSummary? {
    val local = progress.firstOrNull { it.collectionSlug == slug } ?: return summary
    if (summary?.state != "unopened") return summary
    return summary.copy(state = "in_progress", readOrdinal = local.hadith?.hadithNumber?.toDoubleOrNull())
}

@Composable
private fun GridCollection(position: Int, name: String, summary: CollectionProgressSummary?, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalHadithlyColors.current
    Column(
        verticalArrangement = Arrangement.spacedBy(9.dp),
        modifier = modifier.fillMaxWidth().clickable(onClick = onClick).semantics { contentDescription = "$position. $name" },
    ) {
        CollectionCover(position, Modifier.fillMaxWidth().aspectRatio(0.66f))
        Text(position.toString(), fontSize = 12.sp, color = colors.textSecondary)
        Text(name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary, maxLines = 2, overflow = TextOverflow.Ellipsis)
        ProgressSlot(summary)
    }
}

@Composable
private fun ListCollection(position: Int, name: String, summary: CollectionProgressSummary?, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalHadithlyColors.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier.fillMaxWidth().background(colors.surface, androidx.compose.foundation.shape.RoundedCornerShape(14.dp)).clickable(onClick = onClick).padding(10.dp).semantics { contentDescription = "$position. $name" },
    ) {
        CollectionCover(position, Modifier.width(56.dp).height(82.dp))
        Spacer(Modifier.size(14.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Text(position.toString(), fontSize = 12.sp, color = colors.textSecondary)
            Text(name, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
            ProgressSlot(summary)
        }
    }
}

@Composable
private fun ProgressSlot(summary: CollectionProgressSummary?) {
    val colors = LocalHadithlyColors.current
    val label = when (summary?.state) {
        "unopened" -> "Not started"
        "in_progress" -> "Hadith ${summary.readOrdinal?.toInt()} of ${summary.totalHadiths?.toInt()}"
        "completed" -> "Complete"
        "stale" -> "Position unavailable"
        else -> "Progress unavailable"
    }
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Box(Modifier.fillMaxWidth().height(3.dp).background(colors.surfaceElevated, androidx.compose.foundation.shape.RoundedCornerShape(99.dp)))
        Text(label, fontSize = 11.sp, color = colors.textSecondary)
    }
}
