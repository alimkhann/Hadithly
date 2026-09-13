@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.hadithly.app.features.saved

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
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

private enum class SavedFilter(val title: String) { All("All"), Bookmarks("Bookmarks"), Favorites("Favorites"), Notes("Notes") }

@Composable
fun SavedScreen(onOpenTarget: (ReaderOpenTarget) -> Unit) {
    val app = rememberApp()
    val colors = LocalHadithlyColors.current
    val saved by app.library.savedItems.collectAsStateWithLifecycle()
    val folders by app.library.folders.collectAsStateWithLifecycle()
    val lastFolderDeletion by app.library.lastFolderDeletion.collectAsStateWithLifecycle()
    var filter by remember { mutableStateOf(SavedFilter.All) }
    var folderId by remember { mutableStateOf<String?>(null) }
    var showCreateFolder by remember { mutableStateOf(false) }
    var folderName by remember { mutableStateOf("") }
    val visible = saved.filter { item ->
        val matches = when (filter) { SavedFilter.All -> true; SavedFilter.Bookmarks -> item.bookmarkCreatedAt != null; SavedFilter.Favorites -> item.favoriteCreatedAt != null; SavedFilter.Notes -> item.noteContent != null }
        matches && (folderId == null || item.folderId == folderId)
    }.sortedByDescending { it.sortDate }

    androidx.compose.runtime.LaunchedEffect(Unit) {
        withContext(Dispatchers.IO) { ReaderPrefetch.warmEntryCache(app.repository, Collections.all.map { it.first }, app.library.progress.value) }
    }
    Column(Modifier.fillMaxSize().background(colors.background).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Text("Saved", fontSize = 30.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary, modifier = Modifier.weight(1f))
            IconButton(onClick = { showCreateFolder = true }, modifier = Modifier.testTag("saved.createFolder")) { Icon(Icons.Filled.Folder, "Create saved folder", tint = colors.accent) }
        }
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            SavedFilter.entries.forEach { option -> TextButton(onClick = { filter = option }, modifier = Modifier.testTag("saved.filter.${option.name.lowercase()}")) { Text(option.title, color = if (filter == option) colors.accent else colors.textSecondary) } }
        }
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            TextButton(onClick = { folderId = null }) { Icon(Icons.Filled.FolderOff, null, tint = if (folderId == null) colors.accent else colors.textSecondary); Spacer(Modifier.width(4.dp)); Text("All folders") }
            folders.forEach { folder ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    TextButton(onClick = { folderId = folder.id }) { Icon(Icons.Filled.Folder, null, tint = if (folderId == folder.id) colors.accent else colors.textSecondary); Spacer(Modifier.width(4.dp)); Text(folder.name) }
                    IconButton(onClick = { if (folderId == folder.id) folderId = null; app.library.deleteFolder(folder) }) { Icon(Icons.Filled.DeleteOutline, "Delete folder ${folder.name}", tint = colors.destructive) }
                }
            }
        }
        lastFolderDeletion?.let { deletion ->
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("Folder ${deletion.name} deleted", color = colors.textSecondary, modifier = Modifier.weight(1f))
                TextButton(onClick = app.library::undoDeleteFolder, modifier = Modifier.testTag("saved.undoFolderDelete")) { Text("Undo", color = colors.accent) }
            }
        }
        if (visible.isEmpty()) {
            Column(Modifier.fillMaxWidth().padding(top = 64.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Filled.Bookmark, null, tint = colors.textSecondary)
                Text("Nothing saved yet", fontWeight = FontWeight.Medium, color = colors.textPrimary)
                Text("Bookmark, favorite, or add a note while reading to keep a hadith here.", color = colors.textSecondary, fontSize = 13.sp)
            }
        } else {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxSize().testTag("saved.list")) {
                items(visible, key = { it.hadithId }) { item -> item.hadith?.let { SavedItemRow(item, folders, folders.firstOrNull { folder -> folder.id == item.folderId }?.name, onOpenTarget, app.library) } }
            }
        }
    }
    if (showCreateFolder) AlertDialog(
        onDismissRequest = { showCreateFolder = false },
        title = { Text("New folder") },
        text = { OutlinedTextField(folderName, { folderName = it }, label = { Text("Folder name") }, singleLine = true) },
        confirmButton = { Button(onClick = { app.library.createFolder(folderName); folderName = ""; showCreateFolder = false }) { Text("Create") } },
        dismissButton = { TextButton(onClick = { showCreateFolder = false }) { Text("Cancel") } },
    )
}

@Composable private fun SavedItemRow(item: SavedItemEntry, folders: List<com.hadithly.app.core.data.SavedFolder>, folderName: String?, onOpenTarget: (ReaderOpenTarget) -> Unit, library: com.hadithly.app.core.data.UserLibraryModel) {
    val colors = LocalHadithlyColors.current
    val ref = item.hadith ?: return
    var folderMenuOpen by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(12.dp)).clickable { onOpenTarget(ReaderOpenTarget(ref.collectionSlug, ref.collectionName, ref.volumeId, ref.hadithNumber, ReaderTargetSource.SAVED)) }.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(ref.referenceDisplay.ifBlank { ref.collectionName }, color = colors.textPrimary, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (item.bookmarkCreatedAt != null) Icon(Icons.Filled.Bookmark, "Bookmarked", tint = colors.bookmark)
            if (item.favoriteCreatedAt != null) Icon(Icons.Filled.Favorite, "Favorite", tint = colors.favorite)
            if (item.noteContent != null) Icon(Icons.Filled.EditNote, "Has note", tint = colors.accent)
            IconButton(onClick = { folderMenuOpen = true }) { Icon(Icons.Filled.Folder, "Move to folder", tint = colors.textSecondary) }
            DropdownMenu(expanded = folderMenuOpen, onDismissRequest = { folderMenuOpen = false }) {
                DropdownMenuItem(text = { Text("No folder") }, onClick = { library.assignFolder(item.hadithId, null); folderMenuOpen = false })
                folders.forEach { folder -> DropdownMenuItem(text = { Text(folder.name) }, onClick = { library.assignFolder(item.hadithId, folder.id); folderMenuOpen = false }) }
            }
        }
        if (folderName != null) Text(folderName, fontSize = 12.sp, color = colors.textSecondary)
        item.noteContent?.takeIf { it.isNotBlank() }?.let { Text(it, fontSize = 14.sp, color = colors.textSecondary, maxLines = 2, overflow = TextOverflow.Ellipsis) }
        if (ref.arabicText.isNotBlank()) Text(ref.arabicText, fontSize = 17.sp, color = colors.textPrimary, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}
