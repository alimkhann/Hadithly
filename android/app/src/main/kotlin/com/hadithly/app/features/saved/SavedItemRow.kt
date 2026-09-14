@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)

package com.hadithly.app.features.saved

import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.hadithly.app.core.data.*
import com.hadithly.app.core.theme.LocalHadithlyColors
import com.hadithly.app.R
import androidx.compose.ui.res.stringResource

enum class SavedFacet { BOOKMARK, FAVORITE, NOTE }

@Composable
fun SharedSavedItemRow(
    item: SavedItemEntry,
    folders: List<SavedFolder>,
    showFolder: Boolean,
    onOpen: (HadithRef) -> Unit,
    onRemove: (SavedFacet, SavedItemEntry, HadithRef) -> Unit,
    onMove: (String?) -> Unit,
    onCopy: (HadithRef) -> Unit,
    onShare: (HadithRef) -> Unit,
    onSuggestTranslation: (HadithRef) -> Unit,
) {
    val ref = item.hadith ?: return
    val colors = LocalHadithlyColors.current
    var expanded by remember(item.hadithId) { mutableStateOf(false) }
    var menuOpen by remember { mutableStateOf(false) }
    var folderMenuOpen by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().padding(top = 8.dp).testTag("saved.row.${item.hadithId}")) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f).combinedClickable(onClick = { onOpen(ref) }, onLongClick = { menuOpen = true }).padding(vertical = 8.dp)) {
                Text(ref.referenceDisplay.ifBlank { ref.collectionName }, fontWeight = FontWeight.SemiBold, color = colors.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(relativeSavedTime(item.sortDate), fontSize = 12.sp, color = colors.textSecondary)
            }
            if (item.bookmarkCreatedAt != null) IconButton(onClick = { onRemove(SavedFacet.BOOKMARK, item, ref) }) { Icon(Icons.Filled.Bookmark, stringResource(R.string.saved_remove_bookmark), tint = colors.bookmark) }
            if (item.favoriteCreatedAt != null) IconButton(onClick = { onRemove(SavedFacet.FAVORITE, item, ref) }) { Icon(Icons.Filled.Favorite, stringResource(R.string.saved_remove_favorite), tint = colors.favorite) }
            if (item.noteContent != null) IconButton(onClick = { onRemove(SavedFacet.NOTE, item, ref) }) { Icon(Icons.Filled.EditNote, stringResource(R.string.saved_delete_note), tint = colors.accent) }
            IconButton(onClick = { folderMenuOpen = true }) { Icon(Icons.Filled.Folder, stringResource(R.string.saved_move_folder), tint = colors.textSecondary) }
            DropdownMenu(expanded = folderMenuOpen, onDismissRequest = { folderMenuOpen = false }) {
                DropdownMenuItem(text = { Text(stringResource(R.string.saved_no_folder)) }, onClick = { onMove(null); folderMenuOpen = false })
                folders.forEach { folder -> DropdownMenuItem(text = { Text(folder.name) }, onClick = { onMove(folder.id); folderMenuOpen = false }) }
            }
            IconButton(onClick = { expanded = !expanded }, modifier = Modifier.testTag("saved.preview.${item.hadithId}")) { Icon(if (expanded) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown, stringResource(if (expanded) R.string.saved_hide_preview else R.string.saved_show_preview), tint = colors.textSecondary) }
        }
        if (showFolder) folders.firstOrNull { it.id == item.folderId }?.let { Text(it.name, fontSize = 12.sp, color = colors.textSecondary) }
        item.noteContent?.takeIf { it.isNotBlank() }?.let { Text(it, fontSize = 13.sp, color = colors.textSecondary, maxLines = if (expanded) Int.MAX_VALUE else 1) }
        if (expanded) {
            if (ref.arabicText.isNotBlank()) Text(ref.arabicText, fontSize = 19.sp, lineHeight = 31.sp, color = colors.textPrimary, modifier = Modifier.fillMaxWidth())
            ref.englishText?.takeIf { it.isNotBlank() }?.let { Text(it, fontSize = 14.sp, color = colors.textSecondary) }
        }
        HorizontalDivider(color = colors.divider.copy(alpha = 0.55f))
        DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
            DropdownMenuItem(text = { Text(stringResource(R.string.saved_move_folder)) }, onClick = { folderMenuOpen = true; menuOpen = false })
            if (item.bookmarkCreatedAt != null) DropdownMenuItem(text = { Text(stringResource(R.string.saved_remove_bookmark)) }, onClick = { onRemove(SavedFacet.BOOKMARK, item, ref); menuOpen = false })
            if (item.favoriteCreatedAt != null) DropdownMenuItem(text = { Text(stringResource(R.string.saved_remove_favorite)) }, onClick = { onRemove(SavedFacet.FAVORITE, item, ref); menuOpen = false })
            if (item.noteContent != null) DropdownMenuItem(text = { Text(stringResource(R.string.saved_delete_note)) }, onClick = { onRemove(SavedFacet.NOTE, item, ref); menuOpen = false })
            DropdownMenuItem(text = { Text(stringResource(R.string.saved_copy)) }, onClick = { onCopy(ref); menuOpen = false })
            DropdownMenuItem(text = { Text(stringResource(R.string.saved_share)) }, onClick = { onShare(ref); menuOpen = false })
            DropdownMenuItem(text = { Text(stringResource(R.string.saved_suggest_translation)) }, onClick = { onSuggestTranslation(ref); menuOpen = false })
        }
    }
}

private fun relativeSavedTime(timestamp: Double): String {
    val minutes = ((System.currentTimeMillis() - timestamp).coerceAtLeast(0.0) / 60_000).toLong()
    return when {
        minutes < 1 -> "Added just now"
        minutes < 60 -> "Added ${minutes}m ago"
        minutes < 1_440 -> "Added ${minutes / 60}h ago"
        else -> "Added ${minutes / 1_440}d ago"
    }
}
