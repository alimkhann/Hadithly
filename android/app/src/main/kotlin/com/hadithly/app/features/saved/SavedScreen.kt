@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.hadithly.app.features.saved

import com.hadithly.app.R

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.FolderOff
import androidx.compose.material.icons.filled.Undo
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.hadithly.app.core.data.HadithRef
import com.hadithly.app.core.data.ReaderPrefetch
import com.hadithly.app.core.data.ReaderTargetSource
import com.hadithly.app.core.data.SavedItemEntry
import com.hadithly.app.core.data.Collections
import com.hadithly.app.core.theme.LocalHadithlyColors
import com.hadithly.app.features.main.ReaderOpenTarget
import com.hadithly.app.features.main.rememberApp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent

private enum class SavedFilter { All, Bookmarks, Favorites, Notes }
private data class RemovalRequest(val facet: SavedFacet, val item: SavedItemEntry, val ref: HadithRef)

@Composable
fun SavedScreen(onOpenTarget: (ReaderOpenTarget) -> Unit) {
    val app = rememberApp()
    val context = LocalContext.current
    val colors = LocalHadithlyColors.current
    val saved by app.library.savedItems.collectAsStateWithLifecycle()
    val folders by app.library.folders.collectAsStateWithLifecycle()
    val lastFolderDeletion by app.library.lastFolderDeletion.collectAsStateWithLifecycle()
    val bookmarkRemoved = stringResource(R.string.saved_bookmark_removed)
    val favoriteRemoved = stringResource(R.string.saved_favorite_removed)
    val noteDeleted = stringResource(R.string.saved_note_deleted)
    var filter by remember { mutableStateOf(SavedFilter.All) }
    var folderId by remember { mutableStateOf<String?>(null) }
    var showCreateFolder by remember { mutableStateOf(false) }
    var folderName by remember { mutableStateOf("") }
    var folderMenu by remember { mutableStateOf<com.hadithly.app.core.data.SavedFolder?>(null) }
    var removal by remember { mutableStateOf<RemovalRequest?>(null) }
    var undoMessage by remember { mutableStateOf<String?>(null) }
    var undoAction by remember { mutableStateOf<(() -> Unit)?>(null) }
    val visible = saved.filter { item ->
        val matches = when (filter) { SavedFilter.All -> true; SavedFilter.Bookmarks -> item.bookmarkCreatedAt != null; SavedFilter.Favorites -> item.favoriteCreatedAt != null; SavedFilter.Notes -> item.noteContent != null }
        matches && (folderId == null || item.folderId == folderId)
    }.sortedByDescending { it.sortDate }
    fun filterTitle(value: SavedFilter) = when (value) { SavedFilter.All -> R.string.saved_all; SavedFilter.Bookmarks -> R.string.saved_bookmarks; SavedFilter.Favorites -> R.string.saved_favorites; SavedFilter.Notes -> R.string.saved_notes }

    fun performRemoval(request: RemovalRequest) {
        when (request.facet) {
            SavedFacet.BOOKMARK -> request.item.bookmarkCreatedAt?.let { at -> app.library.toggleBookmark(request.ref); undoMessage = bookmarkRemoved; undoAction = { app.library.restoreBookmark(request.ref, at) } }
            SavedFacet.FAVORITE -> request.item.favoriteCreatedAt?.let { at -> app.library.toggleFavorite(request.ref); undoMessage = favoriteRemoved; undoAction = { app.library.restoreFavorite(request.ref, at) } }
            SavedFacet.NOTE -> request.item.noteContent?.let { content -> app.library.deleteNote(request.ref); undoMessage = noteDeleted; undoAction = { app.library.restoreNote(request.ref, content, request.item.createdAt, request.item.updatedAt) } }
        }
    }
    fun requestRemoval(facet: SavedFacet, item: SavedItemEntry, ref: HadithRef) {
        val request = RemovalRequest(facet, item, ref)
        if (app.savedSafety.confirmsRemoval) removal = request else performRemoval(request)
    }

    androidx.compose.runtime.LaunchedEffect(Unit) {
        withContext(Dispatchers.IO) { ReaderPrefetch.warmEntryCache(app.repository, Collections.all.map { it.first }, app.library.progress.value) }
    }
    Column(Modifier.fillMaxSize().background(colors.background).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.saved_title), fontSize = 30.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary, modifier = Modifier.weight(1f))
            IconButton(onClick = { showCreateFolder = true }, modifier = Modifier.testTag("saved.createFolder")) { Icon(Icons.Filled.Folder, stringResource(R.string.saved_create_folder), tint = colors.accent) }
        }
        val displayedUndo = undoMessage ?: lastFolderDeletion?.let { stringResource(R.string.saved_folder_deleted, it.name) }
        if (displayedUndo != null) {
            Row(Modifier.fillMaxWidth().background(colors.surfaceElevated, RoundedCornerShape(14.dp)).padding(horizontal = 14.dp, vertical = 10.dp).testTag("saved.undoBanner"), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Undo, null, tint = colors.accent); Spacer(Modifier.width(10.dp)); Text(displayedUndo, color = colors.textPrimary, modifier = Modifier.weight(1f)); TextButton(onClick = { undoAction?.invoke() ?: app.library.undoDeleteFolder(); undoMessage = null; undoAction = null }) { Text(stringResource(R.string.saved_undo), color = colors.accent) }
            }
        }
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            SavedFilter.entries.forEach { option -> TextButton(onClick = { filter = option }, modifier = Modifier.testTag("saved.filter.${option.name.lowercase()}")) { Text(stringResource(filterTitle(option)), color = if (filter == option) colors.accent else colors.textSecondary) } }
        }
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            TextButton(onClick = { folderId = null }) { Icon(Icons.Filled.FolderOff, null, tint = if (folderId == null) colors.accent else colors.textSecondary); Spacer(Modifier.width(4.dp)); Text(stringResource(R.string.saved_all_folders)) }
            folders.forEach { folder ->
                Row(Modifier.combinedClickable(onClick = { folderId = folder.id }, onLongClick = { folderMenu = folder }).background(colors.surfaceElevated, RoundedCornerShape(50)).padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.Folder, null, tint = if (folderId == folder.id) colors.accent else colors.textSecondary); Spacer(Modifier.width(4.dp)); Text(folder.name) }
                DropdownMenu(expanded = folderMenu?.id == folder.id, onDismissRequest = { folderMenu = null }) {
                    DropdownMenuItem(text = { Text(stringResource(R.string.saved_delete_folder)) }, onClick = { if (folderId == folder.id) folderId = null; app.library.deleteFolder(folder); folderMenu = null })
                }
            }
        }
        if (visible.isEmpty()) {
            Column(Modifier.fillMaxWidth().padding(top = 64.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Filled.Bookmark, null, tint = colors.textSecondary)
                Text(stringResource(R.string.saved_empty_title), fontWeight = FontWeight.Medium, color = colors.textPrimary)
                Text(stringResource(R.string.saved_empty_message), color = colors.textSecondary, fontSize = 13.sp)
            }
        } else {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxSize().testTag("saved.list")) {
                items(visible, key = { it.hadithId }) { item -> SharedSavedItemRow(item, folders, folderId == null, { ref -> onOpenTarget(ReaderOpenTarget(ref.collectionSlug, ref.collectionName, ref.volumeId, ref.hadithNumber, ReaderTargetSource.SAVED)) }, ::requestRemoval, { app.library.assignFolder(item.hadithId, it) }, { ref -> (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText(ref.referenceDisplay, listOfNotNull(ref.arabicText, ref.englishText, ref.referenceDisplay).joinToString("\n\n"))) }, { ref -> context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, "https://hadithly.app/hadith/${ref.collectionSlug}/${ref.hadithNumber}"), null)) }, { ref -> onOpenTarget(ReaderOpenTarget(ref.collectionSlug, ref.collectionName, ref.volumeId, ref.hadithNumber, ReaderTargetSource.SAVED)) }) }
            }
        }
    }
    if (showCreateFolder) AlertDialog(
        onDismissRequest = { showCreateFolder = false },
        title = { Text(stringResource(R.string.saved_new_folder)) },
        text = { OutlinedTextField(folderName, { folderName = it }, label = { Text(stringResource(R.string.saved_folder_name)) }, singleLine = true) },
        confirmButton = { Button(onClick = { app.library.createFolder(folderName); folderName = ""; showCreateFolder = false }) { Text(stringResource(R.string.saved_create)) } },
        dismissButton = { TextButton(onClick = { showCreateFolder = false }) { Text(stringResource(R.string.saved_cancel)) } },
    )
    removal?.let { request -> AlertDialog(onDismissRequest = { removal = null }, title = { Text(stringResource(R.string.saved_remove_title)) }, text = { Text(stringResource(R.string.saved_removal_undo_message)) }, confirmButton = { TextButton(onClick = { performRemoval(request); removal = null }) { Text(stringResource(R.string.saved_remove)) } }, dismissButton = { Column { TextButton(onClick = { app.savedSafety.confirmsRemoval = false; performRemoval(request); removal = null }) { Text(stringResource(R.string.saved_remove_dont_ask)) }; TextButton(onClick = { removal = null }) { Text(stringResource(R.string.saved_cancel)) } } }) }
}
