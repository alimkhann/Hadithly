@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)

package com.hadithly.app.features.saved

import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import kotlinx.coroutines.CancellationException
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import com.hadithly.app.core.preferences.nativeText
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.hadithly.app.core.data.*
import com.hadithly.app.core.theme.LocalHadithlyColors
import com.hadithly.app.core.theme.InterfaceMotion
import com.hadithly.app.core.theme.rememberMotionAllowed
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
    loadPreview: suspend (HadithRef) -> HadithRef = { it },
) {
    val ref = item.hadith ?: return
    val colors = LocalHadithlyColors.current
    val motionAllowed = rememberMotionAllowed()
    var expanded by remember(item.hadithId) { mutableStateOf(false) }
    var preview by remember(ref) { mutableStateOf(ref) }
    var loading by remember(ref) { mutableStateOf(false) }
    var failed by remember(ref) { mutableStateOf(false) }
    var retry by remember(ref) { mutableStateOf(0) }
    var menuOpen by remember(item.hadithId) { mutableStateOf(false) }
    var folderMenuOpen by remember(item.hadithId) { mutableStateOf(false) }
    LaunchedEffect(expanded, ref, retry) {
        if (!expanded || (preview.arabicText.isNotBlank() && !preview.englishText.isNullOrBlank())) return@LaunchedEffect
        loading = true
        failed = false
        try {
            preview = loadPreview(ref)
            failed = preview.arabicText.isBlank() && preview.englishText.isNullOrBlank()
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            failed = true
        } finally {
            loading = false
        }
    }
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(colors.surface)
        .animateContentSize(if (motionAllowed) tween(InterfaceMotion.STEP) else snap())
        .padding(12.dp).testTag("saved.row.${item.hadithId}")) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f).combinedClickable(onClick = { onOpen(ref) }, onLongClick = { menuOpen = true }).padding(vertical = 8.dp)) {
                Text(ref.referenceDisplay.ifBlank { ref.collectionName }, fontWeight = FontWeight.SemiBold, color = colors.textPrimary, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (item.bookmarkCreatedAt != null) Icon(Icons.Filled.Bookmark, null, Modifier.size(12.dp), tint = colors.textSecondary)
                    if (item.favoriteCreatedAt != null) Icon(Icons.Filled.Favorite, null, Modifier.size(12.dp), tint = colors.textSecondary)
                    if (item.noteContent != null) Icon(Icons.Filled.EditNote, null, Modifier.size(12.dp), tint = colors.textSecondary)
                    Text(relativeSavedTime(item.sortDate), fontSize = 12.sp, color = colors.textSecondary)
                }
            }
            IconButton(onClick = { menuOpen = true }, modifier = Modifier.testTag("saved.actions.${item.hadithId}")) { Icon(Icons.Filled.MoreHoriz, nativeText("Saved item actions"), tint = colors.textSecondary) }
            IconButton(onClick = { expanded = !expanded }, modifier = Modifier.testTag("saved.preview.${item.hadithId}")) { Icon(if (expanded) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown, stringResource(if (expanded) R.string.saved_hide_preview else R.string.saved_show_preview), tint = colors.textSecondary) }
        }
        if (showFolder) folders.firstOrNull { it.id == item.folderId }?.let { Text(it.name, fontSize = 12.sp, color = colors.textSecondary) }
        item.noteContent?.takeIf { it.isNotBlank() }?.let { Text(it, fontSize = 13.sp, color = colors.textSecondary, maxLines = if (expanded) Int.MAX_VALUE else 2) }
        if (expanded) {
            preview.arabicText.takeIf { it.isNotBlank() }?.let { Text(it, fontSize = 19.sp, lineHeight = 31.sp, color = colors.textPrimary, modifier = Modifier.fillMaxWidth()) }
            preview.englishText?.takeIf { it.isNotBlank() }?.let { Text(it, fontSize = 14.sp, color = colors.textSecondary) }
            if (loading) CircularProgressIndicator(Modifier.size(20.dp).testTag("saved.preview.loading"), color = colors.textSecondary)
            if (failed) TextButton(onClick = { retry++ }, modifier = Modifier.testTag("saved.preview.retry")) { Text(stringResource(R.string.saved_preview_retry), color = colors.textSecondary) }
        }
        DropdownMenu(expanded = folderMenuOpen, onDismissRequest = { folderMenuOpen = false }) {
            DropdownMenuItem(text = { Text(stringResource(R.string.saved_no_folder), color = if (item.folderId == null) colors.accent else colors.textSecondary) }, onClick = { onMove(null); folderMenuOpen = false })
            folders.forEach { folder ->
                DropdownMenuItem(text = { Text(folder.name, color = if (item.folderId == folder.id) colors.accent else colors.textSecondary) }, onClick = { onMove(folder.id); folderMenuOpen = false })
            }
        }
        DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
            DropdownMenuItem(text = { Text(stringResource(R.string.saved_move_folder)) }, onClick = { menuOpen = false; folderMenuOpen = true })
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
