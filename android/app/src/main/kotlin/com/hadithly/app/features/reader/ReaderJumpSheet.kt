package com.hadithly.app.features.reader

import androidx.compose.foundation.background
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
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.hadithly.app.core.preferences.nativeText
import com.hadithly.app.core.theme.LocalHadithlyColors
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import java.text.NumberFormat
import kotlin.coroutines.coroutineContext
import kotlin.math.abs
import kotlin.math.pow
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

private data class ReaderJumpPosition(val volumeId: String, val pageIndex: Int)

@Composable
internal fun ReaderJumpSheet(
    viewModel: ReaderViewModel,
    initialVolumeId: String,
    initialPageIndex: Int,
    onDismiss: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    val locale = LocalConfiguration.current.locales[0]
    val format = remember(locale) { NumberFormat.getIntegerInstance(locale) }
    val wheelRowHeight = with(androidx.compose.ui.platform.LocalDensity.current) { maxOf(40.dp, 31.sp.toDp()) }
    var counts by remember { mutableStateOf(mapOf<String, ReaderViewModel.JumpPageCount>()) }
    var selection by remember { mutableStateOf(ReaderJumpPosition(initialVolumeId, initialPageIndex)) }
    var pending by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    var retryTarget by remember { mutableStateOf(initialVolumeId to initialPageIndex) }
    var wheelGeneration by remember { mutableStateOf(0) }
    val scope = rememberCoroutineScope()
    var loadJob by remember { mutableStateOf<Job?>(null) }

    val state by viewModel.state.collectAsStateWithLifecycle()
    val volumes = state.volumes
    val headIndex = volumes.indexOfFirst { it.volumeId == selection.volumeId }
    val pageCount = counts[selection.volumeId]?.count ?: 0

    fun chooseVolume(volumeId: String, desiredPage: Int = 0) {
        loadJob?.cancel()
        failed = false
        retryTarget = volumeId to desiredPage
        val known = counts[volumeId] ?: viewModel.knownPageCountForJump(volumeId)
        if (known != null) {
            counts = counts + (volumeId to known)
            selection = ReaderJumpPosition(
                volumeId,
                desiredPage.coerceIn(0, known.count - 1),
            )
            wheelGeneration++
            pending = false
            return
        }
        selection = ReaderJumpPosition(volumeId, desiredPage)
        pending = true
        loadJob = scope.launch {
            try {
                val count = viewModel.pageCountForJump(volumeId)
                counts = counts + (volumeId to count)
                selection = ReaderJumpPosition(
                    volumeId,
                    desiredPage.coerceIn(0, count.count - 1),
                )
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

    fun pageWheelChanged(page: Int) {
        if (pending || failed || pageCount <= 0) return
        if (page != selection.pageIndex) selection = ReaderJumpPosition(selection.volumeId, page)
    }

    LaunchedEffect(Unit) {
        chooseVolume(initialVolumeId, initialPageIndex)
    }

    Column(
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.background)
            .padding(horizontal = 20.dp, vertical = 6.dp)
            .testTag("reader.jump.sheet"),
    ) {
        Box(Modifier.fillMaxWidth().height(36.dp)) {
            IconButton(onClick = onDismiss, modifier = Modifier.align(Alignment.CenterEnd).size(48.dp).testTag("reader.jump.close")) {
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier.size(28.dp).background(colors.surface, CircleShape),
                ) {
                    Icon(Icons.Filled.Close, contentDescription = nativeText("Close"), tint = colors.textPrimary, modifier = Modifier.size(18.dp))
                }
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
        Box(Modifier.fillMaxWidth().height(192.dp)) {
            Row(
                Modifier
                    .align(Alignment.Center)
                    .padding(horizontal = 24.dp)
                    .fillMaxWidth()
                    .height(wheelRowHeight)
                    .background(colors.surface, CircleShape),
            ) {}
            Row(Modifier.fillMaxWidth().height(192.dp)) {
                ReaderJumpWheel(
                    rowCount = volumes.size,
                    rowLabel = { index -> format.format(index + 1) },
                    selection = headIndex.coerceAtLeast(0),
                    onSelect = { index ->
                        val volume = volumes.getOrNull(index) ?: return@ReaderJumpWheel
                        if (volume.volumeId != selection.volumeId) chooseVolume(volume.volumeId)
                    },
                    modifier = Modifier.weight(1f),
                    enabled = true,
                    testTag = "reader.jump.volume",
                    accessibilityLabel = nativeText("volume"),
                    itemHeight = wheelRowHeight,
                )
                if (pageCount > 0) {
                    key(selection.volumeId, pageCount) {
                        ReaderLoopPageWheel(
                            pageCount = pageCount,
                            page = selection.pageIndex,
                            generation = wheelGeneration,
                            onSelect = ::pageWheelChanged,
                            modifier = Modifier.weight(1f),
                            label = { format.format(it) },
                            testTag = "reader.jump.page",
                            accessibilityLabel = nativeText("page"),
                            itemHeight = wheelRowHeight,
                        )
                    }
                }
            }
        }
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier.fillMaxWidth().height(36.dp).testTag("reader.jump.status"),
        ) {
            if (pending) {
                CircularProgressIndicator(
                    color = colors.interactive,
                    modifier = Modifier.size(24.dp).testTag("reader.jump.loading"),
                )
            } else if (failed) {
                TextButton(
                    onClick = { chooseVolume(retryTarget.first, retryTarget.second) },
                    colors = ButtonDefaults.textButtonColors(contentColor = colors.interactive),
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
            enabled = !pending && !failed && pageCount > 0,
            shape = CircleShape,
            colors = ButtonDefaults.buttonColors(containerColor = colors.interactive, contentColor = colors.onInteractive),
            modifier = Modifier.fillMaxWidth().padding(bottom = 22.dp).testTag("reader.jump.go"),
        ) {
            Text(nativeText("Go"), fontSize = 16.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(vertical = 8.dp))
        }
    }
}

@Composable
private fun ReaderJumpWheel(
    rowCount: Int,
    rowLabel: (Int) -> String,
    selection: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    testTag: String,
    accessibilityLabel: String,
    itemHeight: Dp,
) {
    val density = androidx.compose.ui.platform.LocalDensity.current
    val itemHpx = with(density) { itemHeight.toPx() }
    val listState = rememberLazyListState(initialFirstVisibleItemIndex = selection.coerceAtLeast(0))
    val fling = rememberSnapFlingBehavior(listState)
    val currentOnSelect by rememberUpdatedState(onSelect)
    val currentRowCount by rememberUpdatedState(rowCount)
    var centered by remember { mutableStateOf(selection) }

    LaunchedEffect(listState) {
        snapshotFlow { listState.layoutInfo }
            .mapNotNull { info ->
                if (info.visibleItemsInfo.isEmpty()) return@mapNotNull null
                val center = info.viewportStartOffset + info.viewportSize.height / 2
                info.visibleItemsInfo.minByOrNull { abs(it.offset + it.size / 2 - center) }?.index
            }
            .collect { index ->
                if (index in 0 until currentRowCount && index != centered) {
                    centered = index
                    if (enabled) currentOnSelect(index)
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
        contentPadding = PaddingValues(vertical = (192.dp - itemHeight) / 2),
        userScrollEnabled = enabled,
        modifier = modifier
            .fillMaxHeight()
            .semantics { contentDescription = accessibilityLabel; stateDescription = rowLabel(selection) }
            .testTag(testTag),
    ) {
        items(rowCount, key = { it }) { index ->
            MagnifiedWheelRow(
                listState = listState,
                index = index,
                itemHpx = itemHpx,
                itemHeight = itemHeight,
                text = rowLabel(index),
            )
        }
    }
}

/**
 * Infinite Page wheel. The LazyColumn holds a huge repeated row space indexed
 * from the middle, so it never dead-ends while wrapping inside the volume's
 * pages; `generation` marks sheet-driven recenters (volume change, retry)
 * that must move the drum silently.
 */
@Composable
private fun ReaderLoopPageWheel(
    pageCount: Int,
    page: Int,
    generation: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
    label: (Int) -> String,
    testTag: String,
    accessibilityLabel: String,
    itemHeight: Dp,
) {
    val density = androidx.compose.ui.platform.LocalDensity.current
    val itemHpx = with(density) { itemHeight.toPx() }
    val virtualCount = Int.MAX_VALUE / 2
    val base = remember(pageCount) { (virtualCount / 2 / pageCount) * pageCount }
    val listState = rememberLazyListState(initialFirstVisibleItemIndex = base + page)
    val fling = rememberSnapFlingBehavior(listState)
    val currentOnSelect by rememberUpdatedState(onSelect)
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
                    currentOnSelect(raw % pageCount)
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
        contentPadding = PaddingValues(vertical = (192.dp - itemHeight) / 2),
        modifier = modifier
            .fillMaxHeight()
            .semantics { contentDescription = accessibilityLabel; stateDescription = label(page + 1) }
            .testTag(testTag),
    ) {
        items(virtualCount, key = { it }) { raw ->
            MagnifiedWheelRow(
                listState = listState,
                index = raw,
                itemHpx = itemHpx,
                itemHeight = itemHeight,
                text = label((raw % pageCount) + 1),
            )
        }
    }
}

@Composable
private fun MagnifiedWheelRow(
    listState: LazyListState,
    index: Int,
    itemHpx: Float,
    itemHeight: Dp,
    text: String,
) {
    val colors = LocalHadithlyColors.current
    val layout = listState.layoutInfo
    val viewportCenter = layout.viewportStartOffset + layout.viewportSize.height / 2
    val info = layout.visibleItemsInfo.firstOrNull { it.index == index }
    val distance = if (info != null) abs(info.offset + info.size / 2 - viewportCenter).toFloat() else itemHpx * 2f
    val eased = (1f - distance / (itemHpx * 1.6f)).coerceIn(0f, 1f).pow(1.5f)
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .fillMaxWidth()
            .height(itemHeight),
    ) {
        Text(
            text,
            fontSize = 19.sp,
            color = colors.textPrimary,
            textAlign = TextAlign.Center,
            modifier = Modifier.graphicsLayer {
                val scale = 0.70f + 0.54f * eased
                scaleX = scale
                scaleY = scale
                alpha = 0.42f + 0.58f * eased
            },
        )
    }
}
