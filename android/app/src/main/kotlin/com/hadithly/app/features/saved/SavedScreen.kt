@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.hadithly.app.features.saved

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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.NavigateNext
import androidx.compose.material.icons.filled.BookmarkBorder
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.hadithly.app.core.data.HadithRef
import com.hadithly.app.core.data.SavedEntry
import com.hadithly.app.core.theme.LocalHadithlyColors
import com.hadithly.app.features.main.ReaderOpenTarget
import com.hadithly.app.features.main.rememberApp

private enum class SavedSection(val title: String, val tag: String) {
    Bookmarks("Bookmarks", "bookmarks"),
    Favorites("Favorites", "favorites"),
    Notes("Notes", "notes"),
}

@Composable
fun SavedScreen(onOpenTarget: (ReaderOpenTarget) -> Unit) {
    val app = rememberApp()
    val colors = LocalHadithlyColors.current
    val bookmarks by app.library.bookmarks.collectAsStateWithLifecycle()
    val favorites by app.library.favorites.collectAsStateWithLifecycle()
    val notes by app.library.notes.collectAsStateWithLifecycle()
    var active by remember { mutableStateOf<SavedSection?>(null) }

    fun entries(section: SavedSection) = when (section) {
        SavedSection.Bookmarks -> bookmarks
        SavedSection.Favorites -> favorites
        SavedSection.Notes -> notes
    }

    Column(
        verticalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier.fillMaxSize().background(colors.background).padding(16.dp),
    ) {
        Text("Saved", fontSize = 30.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)
        SavedSection.entries.forEach { section ->
            val tint = sectionTint(section)
            val icon = sectionIcon(section)
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .background(colors.surface, RoundedCornerShape(14.dp))
                    .clickable { active = section }
                    .testTag("saved.section.${section.tag}")
                    .padding(horizontal = 16.dp, vertical = 14.dp),
            ) {
                Box(Modifier.size(38.dp).background(tint.copy(alpha = 0.14f), CircleShape), contentAlignment = Alignment.Center) {
                    Icon(icon, null, tint = tint, modifier = Modifier.size(20.dp))
                }
                Spacer(Modifier.size(14.dp))
                Text(section.title, fontSize = 16.sp, fontWeight = FontWeight.Medium, color = colors.textPrimary, modifier = Modifier.weight(1f))
                Text(entries(section).size.toString(), fontSize = 14.sp, color = colors.textSecondary)
                Spacer(Modifier.size(12.dp))
                Icon(Icons.AutoMirrored.Filled.NavigateNext, null, tint = colors.textSecondary, modifier = Modifier.size(16.dp))
            }
        }
    }

    active?.let { section ->
        ModalBottomSheet(onDismissRequest = { active = null }, containerColor = colors.background) {
            SavedListSheet(
                section = section,
                entries = entries(section),
                onDone = { active = null },
                onOpen = { ref ->
                    active = null
                    onOpenTarget(ReaderOpenTarget(ref.collectionSlug, ref.collectionName, ref.volumeId, ref.hadithNumber))
                },
                onRemove = { ref ->
                    when (section) {
                        SavedSection.Bookmarks -> app.library.toggleBookmark(ref)
                        SavedSection.Favorites -> app.library.toggleFavorite(ref)
                        SavedSection.Notes -> app.library.deleteNote(ref)
                    }
                },
            )
        }
    }
}

@Composable
private fun SavedListSheet(
    section: SavedSection,
    entries: List<SavedEntry>,
    onDone: () -> Unit,
    onOpen: (HadithRef) -> Unit,
    onRemove: (HadithRef) -> Unit,
) {
    val colors = LocalHadithlyColors.current
    Column(Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
            Text(section.title, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary, modifier = Modifier.weight(1f))
            TextButton(onClick = onDone) { Text("Done", color = colors.accent) }
        }
        if (entries.isEmpty()) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxWidth().padding(48.dp),
            ) {
                Icon(sectionIcon(section), null, tint = colors.textSecondary)
                Text("Nothing saved yet", fontSize = 15.sp, fontWeight = FontWeight.Medium, color = colors.textPrimary)
                Text("While reading, tap the ${section.title.lowercase()} action under a hadith.", fontSize = 12.sp, color = colors.textSecondary)
            }
        } else {
            LazyColumn(
                verticalArrangement = Arrangement.spacedBy(8.dp),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            ) {
                items(entries.sortedByDescending { it.sortDate }, key = { it.rowId }) { entry ->
                    entry.hadith?.let { ref -> SavedRow(entry, ref, section, onOpen, onRemove) }
                }
            }
        }
    }
}

@Composable
private fun SavedRow(
    entry: SavedEntry,
    ref: HadithRef,
    section: SavedSection,
    onOpen: (HadithRef) -> Unit,
    onRemove: (HadithRef) -> Unit,
) {
    val colors = LocalHadithlyColors.current
    Column(
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(12.dp)).clickable { onOpen(ref) }.padding(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                ref.referenceDisplay.ifBlank { ref.collectionName },
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                color = colors.textSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            IconButton(onClick = { onRemove(ref) }, modifier = Modifier.size(32.dp)) {
                Icon(
                    if (section == SavedSection.Notes) Icons.Filled.DeleteOutline else Icons.Filled.Close,
                    if (section == SavedSection.Notes) "Delete note" else "Remove",
                    tint = if (section == SavedSection.Notes) colors.destructive else colors.textSecondary,
                    modifier = Modifier.size(17.dp),
                )
            }
        }
        if (ref.arabicText.isNotBlank()) {
            Text(ref.arabicText, fontSize = 17.sp, lineHeight = 29.sp, color = colors.textPrimary, maxLines = 3, overflow = TextOverflow.Ellipsis)
        }
        entry.noteContent?.takeIf { it.isNotBlank() }?.let {
            Text(it, fontSize = 14.sp, color = sectionTint(section).copy(alpha = 0.9f), maxLines = 3, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
private fun sectionTint(section: SavedSection): Color {
    val colors = LocalHadithlyColors.current
    return when (section) {
        SavedSection.Bookmarks -> colors.bookmark
        SavedSection.Favorites -> colors.favorite
        SavedSection.Notes -> colors.accent
    }
}

private fun sectionIcon(section: SavedSection): ImageVector = when (section) {
    SavedSection.Bookmarks -> Icons.Filled.BookmarkBorder
    SavedSection.Favorites -> Icons.Filled.FavoriteBorder
    SavedSection.Notes -> Icons.Filled.EditNote
}
