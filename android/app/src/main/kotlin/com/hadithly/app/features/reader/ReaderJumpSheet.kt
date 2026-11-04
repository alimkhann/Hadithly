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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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
 * Reader volume + page jump sheet, mirroring iOS `ReaderJumpSheet`. The Page
 * wheel is a looping alarm wheel: one step past the volume's last page rolls
 * into the next volume's first page (and back), so it never dead-ends while
 * the Volume wheel owns direct selects. Go hands the exact destination to the
 * reader's normal turn machinery, so loading, pending surfaces and retry stay
 * the existing behavior.
 */

private data class ReaderJumpPosition(val volumeId: String, val pageIndex: Int)

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
    var previousRaw by remember { mutableStateOf<Int?>(null) }
    var wheelGeneration by remember { mutableStateOf(0) }
    val scope = rememberCoroutineScope()
    var loadJob by remember { mutableStateOf<Job?>(null) }

    val state by viewModel.state.collectAsStateWithLifecycle()
    val volumes = state.volumes
    val headIndex = volumes.indexOfFirst { it.volumeId == selection.volumeId }
    val pageCount = counts[selection.volumeId]?.count ?: 0

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
            previousRaw = null
            wheelGeneration++
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
                previousRaw = null
                wheelGeneration++
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

    fun pageWheelChanged(raw: Int) {
        if (pending || failed || pageCount <= 0) return
        val page = ((raw % pageCount) + pageCount) % pageCount
        val previous = previousRaw
        if (previous != null && pageCount > 1) {
            val previousPage = ((previous % pageCount) + pageCount) % pageCount
            if (page == 0 && previousPage == pageCount - 1 && raw > previous && headIndex + 1 < volumes.size) {
                previousRaw = null
                chooseVolume(volumes[headIndex + 1].volumeId, last = false)
                return
            }
            if (page == pageCount - 1 && previousPage == 0 && raw < previous && headIndex > 0) {
                previousRaw = null
                chooseVolume(volumes[headIndex - 1].volumeId, last = true)
                return
            }
        }
        previousRaw = raw
        if (page != selection.pageIndex) selection = ReaderJumpPosition(selection.volumeId, page)
    }

    LaunchedEffect(Unit) {
        for (volume in volumes) {
            viewModel.knownPageCountForJump(volume.volumeId)?.let { counts = counts + (volume.volumeId to it) }
        }
        if (counts[selection.volumeId] == null) chooseVolume(selection.volumeId, last = false, initial = true)
        wheelGeneration++
    }

    Column(
        verticalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.background)
            .padding(horizontal = 20.dp, vertical = 6.dp)
            .testTag("reader.jump.sheet"),
    ) {
        Box(Modifier.fillMaxWidth().height(36.dp)) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .align(Alignment.CenterEnd)
                    .size(28.dp)
                    .background(colors.surface.copy(alpha = 0.84f), CircleShape)
                    .border(0.5.dp, colors.divider.copy(alpha = 0.62f), CircleShape)
                    .clickable { onDismiss() }
                    .testTag("reader.jump.close"),
            ) {
                Text(nativeText("Close"), fontSize = 11.sp)
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
        Box(Modifier.fillMaxWidth().height(216.dp)) {
            Row(
                Modifier
                    .align(Alignment.Center)
                    .padding(horizontal = 8.dp)
                    .fillMaxWidth()
                    .height(40.dp)
                    .background(colors.surface, CircleShape)
                    .border(0.5.dp, colors.divider.copy(alpha = 0.62f), CircleShape),
            ) {}
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
                if (pageCount > 0) {
                    ReaderLoopPageWheel(
                        pageCount = pageCount,
                        page = selection.pageIndex,
                        generation = wheelGeneration,
                        onSelectRaw = ::pageWheelChanged,
                        modifier = Modifier.weight(1f),
                        label = { format.format(it) },
                        textColor = colors.textPrimary,
                        dimColor = colors.textSecondary,
                        testTag = "reader.jump.page",
                    )
                }
            }
        }
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier.fillMaxWidth().height(36.dp).testTag("reader.jump.status"),
        ) {
            if (pending) {
                CircularProgressIndicator(
                    modifier = Modifier.size(24.dp).testTag("reader.jump.loading"),
                )
            } else if (failed) {
                TextButton(
                    onClick = { chooseVolume(retryTarget.first, retryTarget.second) },
                    modifier = Modifier.testTag("reader.jump.retry"),
                ) {
                    Text(nativeText("Retry"))
                }
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
            modifier = Modifier.fillMaxWidth().padding(bottom = 22.dp).testTag("reader.jump.go"),
        ) {
            Text(nativeText("Go"), fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(vertical = 8.dp))
        }
    }
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

/**
 * Infinite Page wheel. The LazyColumn holds a huge repeated row space indexed
 * from the middle, so it never dead-ends; `generation` marks sheet-driven
 * recenters (volume change, retry) that must move the drum without counting
 * as user scrolling.
 */
@Composable
private fun ReaderLoopPageWheel(
    pageCount: Int,
    page: Int,
    generation: Int,
    onSelectRaw: (Int) -> Unit,
    modifier: Modifier = Modifier,
    label: (Int) -> String,
    textColor: androidx.compose.ui.graphics.Color,
    dimColor: androidx.compose.ui.graphics.Color,
    testTag: String,
) {
    val itemHeight = 40.dp
    val listState = rememberLazyListState()
    val virtualCount = Int.MAX_VALUE / 2
    val base = remember(pageCount) { (virtualCount / pageCount) * pageCount }
    val fling = rememberSnapFlingBehavior(listState)
    var centeredRaw by remember { mutableStateOf(base + page) }

    LaunchedEffect(listState) {
        snapshotFlow { listState.layoutInfo }
            .mapNotNull { info ->
                if (info.visibleItemsInfo.isEmpty()) return@mapNotNull null
                val center = info.viewportStartOffset + info.viewportSize.height / 2
                info.visibleItemsInfo.minByOrNull { abs(it.offset + it.size / 2 - center) }?.index
            }
            .collect { raw ->
                if (raw != centeredRaw) {
                    centeredRaw = raw
                    onSelectRaw(raw)
                }
            }
    }
    LaunchedEffect(generation) {
        val target = base + page
        centeredRaw = target
        listState.scrollToItem(target)
    }

    LazyColumn(
        state = listState,
        flingBehavior = fling,
        contentPadding = PaddingValues(vertical = (216.dp - itemHeight) / 2),
        modifier = modifier
            .fillMaxHeight()
            .testTag(testTag),
    ) {
        items(virtualCount, key = { it }) { raw ->
            val index = raw % pageCount
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(itemHeight),
            ) {
                Text(
                    label(index + 1),
                    fontSize = if (raw == centeredRaw) 20.sp else 16.sp,
                    fontWeight = if (raw == centeredRaw) FontWeight.SemiBold else FontWeight.Normal,
                    color = if (raw == centeredRaw) textColor else dimColor,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}
