package com.hadithly.app.features.saved

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.automirrored.filled.Notes
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.hadithly.app.R
import com.hadithly.app.core.theme.QuietDestination
import com.hadithly.app.core.theme.QuietNavigationBar

@Composable
internal fun SavedFilterBar(selected: Int, onSelect: (Int) -> Unit, tagPrefix: String, modifier: Modifier = Modifier) {
    val labels = listOf(R.string.saved_all, R.string.saved_bookmarks, R.string.saved_favorites, R.string.saved_notes).map { stringResource(it) }
    val icons = listOf(Icons.Filled.Layers, Icons.Filled.BookmarkBorder, Icons.Filled.FavoriteBorder, Icons.AutoMirrored.Filled.Notes)
    val selectedIcons = listOf(Icons.Filled.Layers, Icons.Filled.Bookmark, Icons.Filled.Favorite, Icons.AutoMirrored.Filled.Notes)
    QuietNavigationBar(labels.mapIndexed { index, label -> QuietDestination(label, icons[index], selectedIcons[index], "$tagPrefix.${listOf("all", "bookmarks", "favorites", "notes")[index]}") }, selected, onSelect, modifier)
}
