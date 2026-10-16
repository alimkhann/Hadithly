package com.hadithly.app.features.saved

import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Notes
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.BookmarkBorder
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Layers
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.hadithly.app.R
import com.hadithly.app.core.theme.QuietDestination
import com.hadithly.app.core.theme.QuietNavigationBar

@Composable
internal fun SavedFilterBar(
    selected: Int,
    onSelect: (Int) -> Unit,
    tagPrefix: String,
    modifier: Modifier = Modifier,
) {
    val labels = listOf(
        R.string.saved_all,
        R.string.saved_bookmarks,
        R.string.saved_favorites,
        R.string.saved_notes,
    ).map { stringResource(it) }
    val icons = listOf(
        Icons.Filled.Layers,
        Icons.Filled.BookmarkBorder,
        Icons.Filled.FavoriteBorder,
        Icons.AutoMirrored.Filled.Notes,
    )
    val selectedIcons = listOf(
        Icons.Filled.Layers,
        Icons.Filled.Bookmark,
        Icons.Filled.Favorite,
        Icons.AutoMirrored.Filled.Notes,
    )
    val destinations = remember(labels) {
        labels.mapIndexed { index, label ->
            QuietDestination(
                label,
                icons[index],
                selectedIcons[index],
                "$tagPrefix.${listOf("all", "bookmarks", "favorites", "notes")[index]}",
            )
        }
    }
    val layoutDirection = LocalLayoutDirection.current
    val currentOnSelect = rememberUpdatedState(onSelect)
    val currentSelected = rememberUpdatedState(selected)
    QuietNavigationBar(
        destinations = destinations,
        selected = selected,
        onSelect = onSelect,
        modifier = modifier
            .padding(horizontal = 6.dp)
            .widthIn(max = 360.dp)
            .fillMaxWidth()
            .pointerInput(destinations.size, layoutDirection) {
                fun selectAt(x: Float) {
                    if (size.width <= 0) return
                    val fraction = (x / size.width).coerceIn(0f, 0.9999f)
                    val orderedIndex = (fraction * destinations.size).toInt()
                    val index = if (layoutDirection == LayoutDirection.Rtl) {
                        destinations.lastIndex - orderedIndex
                    } else {
                        orderedIndex
                    }
                    if (index != currentSelected.value) {
                        currentOnSelect.value(index)
                    }
                }
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                    while (true) {
                        val event = awaitPointerEvent(PointerEventPass.Initial)
                        val change = event.changes.firstOrNull { it.id == down.id } ?: break
                        if (!change.pressed) break
                        val delta = change.position - down.position
                        if (kotlin.math.abs(delta.x) > viewConfiguration.touchSlop &&
                            kotlin.math.abs(delta.x) > kotlin.math.abs(delta.y)
                        ) {
                            selectAt(change.position.x)
                            change.consume()
                        }
                    }
                }
            },
    )
}
