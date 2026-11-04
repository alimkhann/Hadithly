package com.hadithly.app.features.reader

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.hadithly.app.core.data.OutlineVolume
import com.hadithly.app.core.preferences.nativeText
import com.hadithly.app.core.theme.LocalHadithlyColors
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import java.text.NumberFormat
import java.util.Locale
import kotlin.coroutines.coroutineContext
import kotlin.math.abs
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Reader volume + page jump sheet, mirroring iOS `ReaderJumpSheet`. The two
 * wheels use volume-relative page numbers: crossing a volume edge advances
 * the neighbor volume instead of showing a rewritten page range. Go hands
 * the exact destination to the reader's normal turn machinery, so loading,
 * pending surfaces and retry stay the existing behavior.
 */

private data class ReaderJumpPosition(val volumeId: String, val pageIndex: Int)

private sealed interface ReaderJumpWheelRow {
    data class Page(val position: ReaderJumpPosition) : ReaderJumpWheelRow
    data class PreviousVolume(val volumeId: String) : ReaderJumpWheelRow
    data class NextVolume(val volumeId: String) : ReaderJumpWheelRow
}

@Composable
internal fun ReaderJumpSheet(
    viewModel: ReaderViewModel,
    initialVolumeId: String,
    initialPageIndex: Int,
    onDismiss: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    val locale = Locale.getDefault()
    val format = remember(locale) { NumberFormat.getIntegerInstance(locale) }
    var counts by remember { mutableStateOf(mapOf<String, ReaderViewModel.JumpPageCount>()) }
    var selection by remember { mutableStateOf(ReaderJumpPosition(initialVolumeId, initialPageIndex)) }
    var pending by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    var retryTarget by remember { mutableStateOf(initialVolumeId to false) }
    val scope = rememberCoroutineScope()
    var loadJob by remember { mutableStateOf<Job?>(null) }

    val state by viewModel.state.collectAsStateWithLifecycle()
    val volumes = state.volumes
    val headIndex = volumes.indexOfFirst { it.volumeId == selection.volumeId }

    fun chooseVolume(volumeId: String, last: Boolean, initial: Boolean = false) {
        loadJob?.cancel()
        failed = false
        retryTarget = volumeId to last
        val known = counts[volumeId] ?: viewModel.knownPageCountForJump(volumeId)
        if (known != null) {
            counts = counts + (volumeId to known)
            selection = ReaderJumpPosition(
                volumeId,
                if (initial) selection.pageIndex.coerceAtMost(known.count - 1)
                else if (last) known.count - 1 else 0,
            )
            pending = false
            return
        }
        pending = true
        loadJob = scope.launch {
            try {
                val count = viewModel.pageCountForJump(volumeId)
                counts = counts + (volumeId to count)
                selection = ReaderJumpPosition(
                    volumeId,
                    if (initial) selection.pageIndex.coerceAtMost(count.count - 1)
                    else if (last) count.count - 1 else 0,
                )
                pending = false
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                if (coroutineContext.isActive) {
                    pending = false
                    failed = true
                }
            }
        }
    }

    LaunchedEffect(Unit) {
        for (volume in volumes) {
            viewModel.knownPageCountForJump(volume.volumeId)?.let { counts = counts + (volume.volumeId to it) }
        }
        if (counts[selection.volumeId] == null) chooseVolume(selection.volumeId, last = false, initial = true)
    }

    val pageWheelRows = jumpWheelRows(volumes, headIndex, counts[selection.volumeId]?.count ?: 0)

    Column(
        verticalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.background)
            .padding(horizontal = 20.dp, vertical = 16.dp)
            .testTag("reader.jump.sheet"),
    ) {
        Box(Modifier.fillMaxWidth()) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .align(Alignment.CenterEnd)
                    .size(44.dp)
                    .background(colors.surface.copy(alpha = 0.84f), CircleShape)
                    .border(0.5.dp, colors.divider.copy(alpha = 0.62f), CircleShape)
                    .clickable { onDismiss() }
                    .testTag("reader.jump.close"),
            ) {
                Text(nativeText("Close"))
            }
        }
        Row(Modifier.fillMaxWidth()) {
            Text(
                nativeText("volume").uppercase(locale),
                textAlign = TextAlign.Center,
                color = colors.textSecondary,
                fontSize = 12.sp,
                modifier = Modifier.weight(1f),
            )
            Text(
                nativeText("page").uppercase(locale),
                textAlign = TextAlign.Center,
                color = colors.textSecondary,
                fontSize = 12.sp,
                modifier = Modifier.weight(1f),
            )
        }
        Row(Modifier.fillMaxWidth().height(216.dp)) {
            ReaderJumpWheel(
                rowCount = volumes.size,
                rowLabel = { index -> format.format(index + 1) },
                selection = headIndex.coerceAtLeast(0),
                onSelect = { index ->
                    val volume = volumes.getOrNull(index) ?: return@ReaderJumpWheel
                    if (volume.volumeId != selection.volumeId) chooseVolume(volume.volumeId, last = false)
                },
                modifier = Modifier.weight(1f),
                enabled = true,
                testTag = "reader.jump.volume",
            )
            ReaderJumpWheel(
                rowCount = pageWheelRows.size,
                rowLabel = { index ->
                    when (val row = pageWheelRows.getOrNull(index)) {
                        is ReaderJumpWheelRow.Page -> format.format(row.position.pageIndex + 1)
                        is ReaderJumpWheelRow.PreviousVolume ->
                            (counts[row.volumeId] ?: viewModel.knownPageCountForJump(row.volumeId))
                                ?.let { format.format(it.count) } ?: "…"
                        is ReaderJumpWheelRow.NextVolume -> "1"
                        null -> ""
                    }
                },
                selection = pageWheelRows.indexOfFirst { it is ReaderJumpWheelRow.Page && it.position == selection },
                onSelect = { index ->
                    when (val row = pageWheelRows.getOrNull(index)) {
                        is ReaderJumpWheelRow.Page -> selection = row.position
                        is ReaderJumpWheelRow.PreviousVolume -> chooseVolume(row.volumeId, last = true)
                        is ReaderJumpWheelRow.NextVolume -> chooseVolume(row.volumeId, last = false)
                        null -> Unit
                    }
                },
                modifier = Modifier.weight(1f),
                enabled = !pending && !failed && pageWheelRows.isNotEmpty(),
                testTag = "reader.jump.page",
            )
        }
        if (pending) {
            CircularProgressIndicator(
                modifier = Modifier
                    .align(Alignment.CenterHorizontally)
                    .testTag("reader.jump.loading"),
            )
        } else if (failed) {
            TextButton(
                onClick = { chooseVolume(retryTarget.first, retryTarget.second) },
                modifier = Modifier.align(Alignment.CenterHorizontally).testTag("reader.jump.retry"),
            ) {
                Text(nativeText("Retry"))
            }
        }
        Button(
            onClick = {
                val count = counts[selection.volumeId] ?: return@Button
                if (selection.pageIndex !in 0 until count.count) return@Button
                onDismiss()
                viewModel.jumpToPage(
                    ReaderViewModel.JumpDestination(selection.volumeId, selection.pageIndex, count),
                )
            },
            shape = CircleShape,
            colors = ButtonDefaults.buttonColors(containerColor = colors.interactive, contentColor = colors.onInteractive),
            modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp).testTag("reader.jump.go"),
        ) {
            Text(nativeText("Go"), fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(vertical = 6.dp))
        }
    }
}

/**
 * The Page wheel never renumbers: pages of the chosen volume sit between two
 * edge rows for the neighbor volumes, so a fast scroll through the wheel visits
 * the same pages as the alarm-wheel metaphor requires.
 */
private fun jumpWheelRows(
    volumes: List<OutlineVolume>,
    headIndex: Int,
    pageCount: Int,
): List<ReaderJumpWheelRow> {
    if (headIndex < 0 || pageCount <= 0) return emptyList()
    val result = mutableListOf<ReaderJumpWheelRow>()
    if (headIndex > 0) result.add(ReaderJumpWheelRow.PreviousVolume(volumes[headIndex - 1].volumeId))
    for (index in 0 until pageCount) {
        result.add(ReaderJumpWheelRow.Page(ReaderJumpPosition(volumes[headIndex].volumeId, index)))
    }
    if (headIndex + 1 < volumes.size) result.add(ReaderJumpWheelRow.NextVolume(volumes[headIndex + 1].volumeId))
    return result
}

/** One alarm-clock-style snapping wheel column with a highlighted center row. */
@Composable
private fun ReaderJumpWheel(
    rowCount: Int,
    rowLabel: (Int) -> String,
    selection: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    testTag: String,
) {
    val colors = LocalHadithlyColors.current
    val itemHeight = 40.dp
    val listState = rememberLazyListState()
    val fling = rememberSnapFlingBehavior(listState)
    var centered by remember { mutableStateOf(selection) }

    LaunchedEffect(listState) {
        snapshotFlow { listState.layoutInfo }
            .mapNotNull { info ->
                if (info.visibleItemsInfo.isEmpty()) return@mapNotNull null
                val center = info.viewportStartOffset + info.viewportSize.height / 2
                info.visibleItemsInfo.minByOrNull { abs(it.offset + it.size / 2 - center) }?.index
            }
            .collect { index ->
                if (index in 0 until rowCount && index != centered) {
                    centered = index
                    if (enabled) onSelect(index)
                }
            }
    }
    // The model selected a row from outside this wheel (for example the Page
    // wheel crossed into another volume): center it without fighting scroll.
    LaunchedEffect(selection, rowCount) {
        if (selection in 0 until rowCount && selection != centered) {
            centered = selection
            listState.scrollToItem(selection)
        }
    }

    LazyColumn(
        state = listState,
        flingBehavior = fling,
        contentPadding = PaddingValues(vertical = (216.dp - itemHeight) / 2),
        userScrollEnabled = enabled,
        modifier = modifier
            .fillMaxHeight()
            .testTag(testTag),
    ) {
        items(rowCount, key = { it }) { index ->
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(itemHeight),
            ) {
                Text(
                    rowLabel(index),
                    fontSize = if (index == centered) 20.sp else 16.sp,
                    fontWeight = if (index == centered) FontWeight.SemiBold else FontWeight.Normal,
                    color = if (index == centered) colors.textPrimary else colors.textSecondary,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}
