@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.hadithly.app.features.reader

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PagerScope
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.automirrored.filled.NavigateBefore
import androidx.compose.material.icons.automirrored.filled.NavigateNext
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FormatSize
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import android.content.ClipData
import android.content.Intent
import com.hadithly.app.R
import com.hadithly.app.core.data.OutlineVolume
import com.hadithly.app.core.data.ReaderHadith
import com.hadithly.app.core.data.ReaderPageResult
import com.hadithly.app.core.data.ReaderTranslation
import com.hadithly.app.core.data.ReadingPosition
import com.hadithly.app.core.data.ReaderTargetSource
import com.hadithly.app.core.data.ReadingWidthClass
import com.hadithly.app.core.data.SupportedLanguages
import com.hadithly.app.core.data.TranslationFailure
import com.hadithly.app.core.preferences.ArabicTypeSize
import com.hadithly.app.core.preferences.LocaleFallback
import com.hadithly.app.core.preferences.ReaderPageTurn
import com.hadithly.app.core.preferences.ReaderPagingPolicy
import com.hadithly.app.core.preferences.ReaderPreferences
import com.hadithly.app.core.preferences.SwipeDirection
import com.hadithly.app.core.theme.LocalHadithlyColors
import com.hadithly.app.features.purchases.QuotaPaywallSheet
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/**
 * The reader: a quiet dark page. Chrome (top bar, floating pills) hides on
 * tap; swiping turns pages. The close chevron is the explicit exit; system
 * back also closes, per Android convention.
 */
@Composable
fun ReaderScreen(
    collectionSlug: String,
    collectionName: String,
    openVolumeId: String?,
    openHadithNumber: String?,
    openPosition: ReadingPosition?,
    targetSource: ReaderTargetSource,
    instanceKey: Long,
    onClose: () -> Unit,
) {
    val app = com.hadithly.app.features.main.rememberApp()
    val viewModel: ReaderViewModel = androidx.lifecycle.viewmodel.compose.viewModel(
        key = "reader-$instanceKey",
    ) {
        ReaderViewModel(
            app = app,
            collectionSlug = collectionSlug,
            openVolumeId = openVolumeId,
            openHadithNumber = openHadithNumber,
            openPosition = openPosition,
            targetSource = targetSource,
        )
    }
    val state by viewModel.state.collectAsStateWithLifecycle()
    val readingWidthClass = ReadingWidthClass.fromWidthDp(
        LocalConfiguration.current.screenWidthDp.toDouble()
    )
    LaunchedEffect(viewModel, readingWidthClass) {
        viewModel.setReadingWidthClass(readingWidthClass)
    }
    // Personal-data writes update a separate shared model. Observe its
    // lists here so bookmark/favorite/note affordances repaint immediately.
    val bookmarks by viewModel.library.bookmarks.collectAsStateWithLifecycle()
    val favorites by viewModel.library.favorites.collectAsStateWithLifecycle()
    val notes by viewModel.library.notes.collectAsStateWithLifecycle()
    val preferences by app.preferences.preferences.collectAsStateWithLifecycle()
    val systemDark = androidx.compose.foundation.isSystemInDarkTheme()
    // R4: the reader honors the ReaderTheme preference; everything outside
    // keeps the app-wide dark canvas.
    val colors = com.hadithly.app.core.theme.ReaderPalettes.resolved(preferences.theme, systemDark)

    var showContents by remember { mutableStateOf(false) }
    var showSettings by remember { mutableStateOf(false) }
    var showQuotaPaywall by remember { mutableStateOf(false) }
    var hasAutoPresentedQuotaPaywall by remember { mutableStateOf(false) }

    val hasQuotaFailure = state.translations.values.any { translationState ->
        translationState is TranslationUiState.Failed && translationState.failure == TranslationFailure.QuotaExceeded
    }
    LaunchedEffect(hasQuotaFailure) {
        if (hasQuotaFailure && !hasAutoPresentedQuotaPaywall) {
            hasAutoPresentedQuotaPaywall = true
            showQuotaPaywall = true
        }
    }

    BackHandler(enabled = !showContents && !showSettings, onBack = onClose)

    // R4: the themed reader palette drives every reader surface, including
    // the sheets presented from the reader.
    CompositionLocalProvider(LocalHadithlyColors provides colors) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(colors.background),
        ) {
            when (val phase = state.phase) {
                is ReaderViewModel.Phase.LoadingOutline -> LoadingView(collectionName)
                is ReaderViewModel.Phase.Failed -> FailureView(phase.message)
                is ReaderViewModel.Phase.Reading -> ReadingView(
                    viewModel = viewModel,
                    state = state,
                    collectionName = collectionName,
                    arabicFontSize = preferences.arabicFontSize,
                    preferences = preferences,
                    onOpenContents = { showContents = true },
                    onOpenSettings = { showSettings = true },
                    onShowPaywall = { showQuotaPaywall = true },
                    onClose = onClose,
                )
            }
        }
    }

    if (showContents) {
        ModalBottomSheet(
            onDismissRequest = { showContents = false },
            containerColor = colors.surface,
        ) {
            ContentsSheet(
                volumes = state.volumes,
                selectedVolumeId = state.selectedVolumeId,
                arabicVisible = preferences.arabicVisible,
                onSelect = { viewModel.selectVolume(it) },
                onSelectChapter = { volumeId, chapter ->
                    viewModel.selectChapter(volumeId, chapter)
                    showContents = false
                },
                onJumpToReference = { viewModel.jumpToReference(it) },
                onDismiss = { showContents = false },
            )
        }
    }

    if (showSettings) {
        ModalBottomSheet(
            onDismissRequest = { showSettings = false },
            containerColor = colors.surface,
        ) {
            SettingsSheet(
                preferences = preferences,
                language = state.language,
                onLanguage = { viewModel.setLanguage(it) },
                onArabicFontSize = app.preferences::setArabicFontSize,
                onTheme = app.preferences::setTheme,
                onArabicFont = app.preferences::setArabicFont,
                onVisibility = { arabic: Boolean?, translation: Boolean? ->
                    app.preferences.setVisibility(arabic = arabic, translation = translation)
                },
            )
        }
    }

    if (showQuotaPaywall) {
        QuotaPaywallSheet(
            purchases = app.purchases,
            onDismiss = { showQuotaPaywall = false },
            onUnlocked = {
                app.appScope.launch {
                    kotlinx.coroutines.delay(1_000)
                    viewModel.retryTranslationsAfterPurchase()
                }
            },
        )
    }
}

@Composable
private fun LoadingView(collectionName: String) {
    val colors = LocalHadithlyColors.current
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxSize(),
    ) {
        CircularProgressIndicator(color = colors.textSecondary)
        Text(
            text = "Opening $collectionName…",
            fontSize = 15.sp,
            color = colors.textSecondary,
        )
    }
}

@Composable
private fun FailureView(message: String) {
    val colors = LocalHadithlyColors.current
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
    ) {
        Text("Could not open this collection", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)
        Text(
            text = message,
            fontSize = 13.sp,
            color = colors.textSecondary,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun ReadingView(
    viewModel: ReaderViewModel,
    state: ReaderViewModel.ReaderState,
    collectionName: String,
    arabicFontSize: Float,
    preferences: ReaderPreferences,
    onOpenContents: () -> Unit,
    onOpenSettings: () -> Unit,
    onShowPaywall: () -> Unit,
    onClose: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    val androidView = LocalView.current
    val coroutine = rememberCoroutineScope()
    val pagingPolicy = remember(preferences) { ReaderPagingPolicy(preferences) }

    // One extra sentinel page while more content exists; landing on it
    // triggers the load of the next page.
    val pageCount = state.pages.size + if (state.pages.lastOrNull()?.hasMore == true) 1 else 0
    val pagerState = rememberPagerState(pageCount = { maxOf(pageCount, 1) })
    val currentFirstHadithId = state.pages
        .getOrNull(state.pageIndex)
        ?.items
        ?.firstOrNull()
        ?._id

    // Persist the initial page as soon as it resolves. Previously progress
    // was only written after a swipe, so opening Today/Saved and closing the
    // reader without changing pages could never create Continue Reading.
    LaunchedEffect(currentFirstHadithId) {
        if (currentFirstHadithId != null) viewModel.saveCurrentProgress()
    }

    // Deep links resolve their containing page on the backend after the
    // pager is created. Move the visual pager to that resolved index so
    // Today/Saved/continue-reading never land on an earlier placeholder.
    LaunchedEffect(state.pageIndex, pageCount) {
        if (state.pageIndex in 0 until maxOf(pageCount, 1) && pagerState.currentPage != state.pageIndex) {
            pagerState.scrollToPage(state.pageIndex)
        }
    }

    LaunchedEffect(pagerState) {
        snapshotFlow { pagerState.settledPage }
            .distinctUntilChanged()
            // The pager always emits its synthetic initial page (0). A
            // reused/deep-linked ReaderViewModel may already be on another
            // page, so that first emission must not overwrite the target.
            .drop(1)
            .collect { index -> viewModel.onPageSettled(index) }
    }

    // A layout-affecting preference change (font, size, visibility, transla-
    // tion locale) invalidates the raw offset; the semantic anchor restores
    // the exact position against the new layout signature.
    LaunchedEffect(preferences.layoutProjection) {
        viewModel.reanchorAfterLayoutChange()
    }

    // Reduce Motion: follow the system animator scale; snap instead of
    // animating page turns when animation is disabled.
    val context = androidx.compose.ui.platform.LocalContext.current
    val reduceMotion = remember(context) {
        android.provider.Settings.Global.getFloat(
            context.contentResolver,
            android.provider.Settings.Global.ANIMATOR_DURATION_SCALE,
            1f,
        ) == 0f
    }

    fun turnPage(turn: ReaderPageTurn): Boolean {
        val destination = pagingPolicy.destination(
            pagerState.currentPage,
            pagerState.pageCount,
            turn,
        )
        if (destination != null) {
            if (reduceMotion) {
                coroutine.launch { pagerState.scrollToPage(destination) }
            } else {
                coroutine.launch { pagerState.animateScrollToPage(destination) }
            }
            return true
        }
        val pill = if (turn == ReaderPageTurn.PREVIOUS) {
            viewModel.pagePills().previous
        } else {
            viewModel.pagePills().next
        }
        if (pill?.crossesVolume != true) return false
        viewModel.followPill(pill)
        return true
    }

    val accessibilityActions = buildList {
        add(
            CustomAccessibilityAction(
                if (state.chromeVisible) "Hide reader controls" else "Show reader controls",
                action = {
                    viewModel.toggleChrome()
                    true
                },
            ),
        )
        if (viewModel.pagePills().previous != null) {
            add(CustomAccessibilityAction("Previous page") { turnPage(ReaderPageTurn.PREVIOUS) })
        }
        if (viewModel.pagePills().next != null) {
            add(CustomAccessibilityAction("Next page") { turnPage(ReaderPageTurn.NEXT) })
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .semantics { customActions = accessibilityActions },
    ) {
        DirectionAwareHorizontalPager(
            state = pagerState,
            policy = pagingPolicy,
            onOutwardEdgeTurn = ::turnPage,
            modifier = Modifier.fillMaxSize(),
        ) { pageIndex ->
                val pages = state.pages
                val hadiths = if (pageIndex in pages.indices) pages[pageIndex].items else emptyList()
                ReaderPage(
                    viewModel = viewModel,
                    state = state,
                    hadiths = hadiths,
                    arabicFontSize = arabicFontSize,
                    preferences = preferences,
                    pagingPolicy = pagingPolicy,
                    pageIndex = pageIndex,
                    pillState = viewModel.pagePills(),
                    restoration = viewModel.restoredPosition,
                    restorationGeneration = viewModel.restorationGeneration,
                    landingHadithNumber = viewModel.landingHadithNumber,
                    isSentinel = pageIndex >= pages.size,
                    onFollowPill = viewModel::followPill,
                    onTap = {
                        androidView.performHapticFeedback(android.view.HapticFeedbackConstants.KEYBOARD_TAP)
                        viewModel.toggleChrome()
                    },
                    onShowPaywall = onShowPaywall,
                )
        }

        // Compact progress (R4): a thin bar at the top stays visible while
        // the chrome is hidden, matching the quiet reading state.
        androidx.compose.animation.AnimatedVisibility(
            visible = !state.chromeVisible,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.align(Alignment.TopCenter),
        ) {
            viewModel.compactProgressFraction()?.let { fraction ->
                CompactProgressBar(fraction = fraction)
            }
        }

        androidx.compose.animation.AnimatedVisibility(
            visible = state.chromeVisible,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.align(Alignment.TopCenter),
        ) {
            ReaderTopBar(
                title = collectionName,
                subtitle = viewModel.currentVolumeTitle(),
                onClose = onClose,
                onIndex = onOpenContents,
                onSettings = onOpenSettings,
            )
        }

        androidx.compose.animation.AnimatedVisibility(
            visible = state.chromeVisible,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.align(Alignment.BottomCenter),
        ) {
            ReaderBottomPills(
                volumeTitle = viewModel.currentVolumeTitle(),
                currentPage = state.pageIndex + 1,
                totalPages = viewModel.totalPages(),
            )
        }

    }
}

@Composable
internal fun DirectionAwareHorizontalPager(
    state: PagerState,
    policy: ReaderPagingPolicy,
    onOutwardEdgeTurn: ((ReaderPageTurn) -> Boolean)? = null,
    modifier: Modifier = Modifier,
    content: @Composable PagerScope.(page: Int) -> Unit,
) {
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
        HorizontalPager(
            state = state,
            reverseLayout = policy.reverseLayout,
            modifier = modifier.edgeVolumeSwipe(state, policy, onOutwardEdgeTurn),
            pageContent = content,
        )
    }
}

/**
 * Observes, without consuming, an outward swipe at a pager boundary. Normal
 * in-volume paging and vertical reader scrolling remain owned by
 * HorizontalPager and LazyColumn. Only the otherwise-dead overscroll at an
 * edge reaches [onOutwardEdgeTurn].
 */
private fun Modifier.edgeVolumeSwipe(
    state: PagerState,
    policy: ReaderPagingPolicy,
    onOutwardEdgeTurn: ((ReaderPageTurn) -> Boolean)?,
): Modifier {
    if (onOutwardEdgeTurn == null) return this
    return pointerInput(state.currentPage, state.pageCount, policy) {
        awaitPointerEventScope {
            var startX: Float? = null
            while (true) {
                // Observe before HorizontalPager consumes the drag. At Final
                // the pager may have already consumed an outward boundary
                // swipe, which made the first cross-volume swipe disappear.
                val change = awaitPointerEvent(PointerEventPass.Initial).changes.firstOrNull() ?: continue
                if (startX == null && change.pressed) {
                    startX = change.position.x
                }
                if (startX != null && !change.pressed) {
                    val delta = change.position.x - startX
                    startX = null
                    val swipe = when {
                        delta <= -96f -> SwipeDirection.LEFT
                        delta >= 96f -> SwipeDirection.RIGHT
                        else -> null
                    } ?: continue
                    val turn = policy.turn(swipe)
                    val outward = when (turn) {
                        ReaderPageTurn.PREVIOUS -> state.currentPage == 0
                        ReaderPageTurn.NEXT -> state.currentPage == state.pageCount - 1
                    }
                    if (outward) onOutwardEdgeTurn(turn)
                }
            }
        }
    }
}

@Composable
@OptIn(kotlinx.coroutines.FlowPreview::class)
private fun ReaderPage(
    viewModel: ReaderViewModel,
    state: ReaderViewModel.ReaderState,
    hadiths: List<ReaderHadith>,
    arabicFontSize: Float,
    preferences: ReaderPreferences,
    pagingPolicy: ReaderPagingPolicy,
    pageIndex: Int,
    pillState: ReaderPagePills.State,
    restoration: ReadingPosition?,
    restorationGeneration: Int,
    landingHadithNumber: String?,
    isSentinel: Boolean,
    onFollowPill: (ReaderPagePills.Pill) -> Unit,
    onTap: () -> Unit,
    onShowPaywall: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    var citationsTranslation by remember { mutableStateOf<ReaderTranslation?>(null) }
    var sourceHadith by remember { mutableStateOf<ReaderHadith?>(null) }
    var noteTarget by remember { mutableStateOf<ReaderHadith?>(null) }
    var submissionTarget by remember { mutableStateOf<Pair<ReaderHadith, ReaderTranslation?>?>(null) }
    var reportTarget by remember { mutableStateOf<Pair<ReaderHadith, ReaderTranslation>?>(null) }
    val listState = rememberLazyListState()
    val chapterOpenings = remember(hadiths) { ReaderChapterBoundaries.openingIndices(hadiths) }
    // R6A: the selected volume's outline chapters feed the quiet chapter
    // header's optional Arabic second line; the cumulative counts feed the
    // corner range. Both stay source-provided — nothing is synthesized.
    val selectedVolume = remember(state.volumes, state.selectedVolumeId) {
        state.volumes.firstOrNull { it.volumeId == state.selectedVolumeId }
    }
    val volumeChapters = remember(selectedVolume) { selectedVolume?.chapters.orEmpty() }
    // R6A fix: the corner text is the localized title plus the WHOLE volume
    // range (`Volume 2: 8–58`) only when the volume is fully cached and the
    // range is computable from the outline counts; title-only otherwise.
    // The pure rule lives in volumeCornerText (unit-pinned); the localized
    // title is resolved here at the composition boundary.
    // Volume names are source-provided. Do not translate `Volume 2` into a
    // synthetic localized label when the provider supplied only that value.
    val cornerTitle: String? = selectedVolume?.title
    val cornerRange = remember(state.volumes, state.selectedVolumeId, state.pages) {
        val volumeId = state.selectedVolumeId ?: return@remember null
        if (!ReaderViewModel.isVolumeFullyCached(state.pages)) return@remember null
        ReaderViewModel.volumeHadithRange(state.volumes, volumeId)
    }
    // Volume start: the pages list resets on every volume select/jump, so
    // index 0 with content is the volume's first page.
    val isVolumeStart = pageIndex == 0 && hadiths.isNotEmpty() && selectedVolume != null

    LaunchedEffect(restorationGeneration, restoration?.anchor?.providerHadithId ?: landingHadithNumber, hadiths.firstOrNull()?._id) {
        val targetId = restoration?.anchor?.providerHadithId ?: landingHadithNumber
            ?: return@LaunchedEffect
        val index = hadiths.indexOfFirst { it.providerHadithId == targetId }
        if (index < 0) return@LaunchedEffect
        listState.scrollToItem(index)
        withFrameNanos { }
        val size = listState.layoutInfo.visibleItemsInfo.firstOrNull { it.index == index }?.size ?: 0
        listState.scrollToItem(index, (size * (restoration?.normalizedOffset ?: 0.0)).roundToInt())
    }

    LaunchedEffect(listState, hadiths) {
        snapshotFlow {
            listState.layoutInfo.visibleItemsInfo.firstOrNull()?.let {
                Triple(it.index, it.offset, it.size)
            }
        }
            .filterNotNull()
            .distinctUntilChanged()
            .debounce(500)
            .collect { (index, offset, size) ->
                viewModel.captureStableScroll(
                    hadiths = hadiths,
                    leadingIndex = index,
                    rawPageOffset = (-offset).coerceAtLeast(0).toDouble(),
                    normalizedOffset = (-offset).coerceAtLeast(0).toDouble() / size.coerceAtLeast(1),
                )
            }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .pointerInput(Unit) { detectTapGestures(onTap = { onTap() }) },
    ) {
        if (isSentinel || hadiths.isEmpty()) {
            Box(
                modifier = Modifier.fillMaxSize().testTag("reader.pageLoading"),
                contentAlignment = Alignment.TopCenter,
            ) {
                CircularProgressIndicator(color = colors.textSecondary, modifier = Modifier.padding(top = 120.dp))
            }
        } else {
            LazyColumn(
                state = listState,
                verticalArrangement = Arrangement.spacedBy(0.dp),
                modifier = Modifier.fillMaxSize(),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(
                    start = 22.dp, end = 22.dp, top = 20.dp, bottom = 80.dp,
                ),
            ) {
                // R6A page-top corner label: the localized volume title at the
                // leading edge (mirrored in RTL by start alignment), with the
                // whole-volume `: first–last` range only when fully cached
                // and computable.
                item(key = "reader-volume-corner") {
                    val title = cornerTitle
                    if (title != null) {
                        VolumeCornerLabel(title = title, range = cornerRange)
                    }
                }
                // R6A volume start: title header with a localized ICU-plural
                // count line beneath, on the volume's first page only.
                if (isVolumeStart) {
                    item(key = "reader-volume-start") {
                        val volume = selectedVolume
                        if (volume != null) {
                            VolumeStartHeader(
                                title = volume.title,
                                hadithCount = volume.hadithCount.toInt(),
                            )
                        }
                    }
                }
                itemsIndexed(hadiths, key = { _, hadith -> hadith._id }) { index, hadith ->
                    Column {
                        if (chapterOpenings.contains(index)) {
                            val chapterName = hadith.chapterName.orEmpty()
                            ReaderChapterHeader(
                                title = chapterName,
                                arabicTitle = visibleArabicChapterTitle(
                                    arabicVisible = preferences.arabicVisible,
                                    title = chapterName,
                                    arabicTitle = ReaderChapterBoundaries.arabicTitleFor(
                                        volumeChapters,
                                        chapterName,
                                    ),
                                ),
                            )
                        }
                        HadithBlock(
                            hadith = hadith,
                            translationState = state.translations[hadith.internalId],
                            language = state.language,
                            arabicFontSize = arabicFontSize,
                            preferences = preferences,
                            deps = remember(viewModel, hadith) {
                                object : HadithBlockDeps {
                                    override val isBookmarked: Boolean
                                        get() = viewModel.isBookmarked(hadith)
                                    override val isFavorite: Boolean
                                        get() = viewModel.isFavorite(hadith)
                                    override val hasNote: Boolean
                                        get() = viewModel.noteContent(hadith) != null
                                    override fun onToggleBookmark() = viewModel.toggleBookmark(hadith)
                                    override fun onToggleFavorite() = viewModel.toggleFavorite(hadith)
                                }
                            },
                            onTap = onTap,
                            onRetry = { viewModel.retryTranslation(hadith) },
                            onShowCitations = { citationsTranslation = it },
                            onShowSource = { sourceHadith = hadith },
                            onEditNote = { noteTarget = hadith },
                            onSuggest = { translation -> submissionTarget = hadith to translation },
                            onReport = { translation -> reportTarget = hadith to translation },
                            onShowPaywall = onShowPaywall,
                            // R6A fix: whitespace separates hadiths — no dividers.
                            // Calm rhythm: modest inter-hadith padding with
                            // generous space kept above chapter lines.
                            modifier = Modifier.padding(vertical = 24.dp),
                        )
                    }
                }
                item(key = "reader-end-navigation") {
                    ReaderVolumePills(
                        policy = pagingPolicy,
                        state = pillState,
                        onFollow = onFollowPill,
                    )
                }
            }
        }

        citationsTranslation?.let { translation ->
            ModalBottomSheet(
                onDismissRequest = { citationsTranslation = null },
                containerColor = colors.surface,
            ) {
                CitationsSheet(translation = translation)
            }
        }

        // R6A: one tap on the grade-dot label opens the small source sheet.
        // Copy/share payloads keep the full source line (ReaderShare).
        sourceHadith?.let { hadith ->
            ModalBottomSheet(
                onDismissRequest = { sourceHadith = null },
                containerColor = colors.surface,
            ) {
                HadithSourceSheet(hadith = hadith)
            }
        }

        noteTarget?.let { hadith ->
            ModalBottomSheet(
                onDismissRequest = { noteTarget = null },
                containerColor = colors.surface,
            ) {
                NoteEditorSheet(
                    initialContent = viewModel.noteContent(hadith),
                    onSave = { content ->
                        viewModel.saveNote(hadith, content)
                        noteTarget = null
                    },
                    onCancel = { noteTarget = null },
                )
            }
        }

        submissionTarget?.let { (hadith, translation) ->
            ModalBottomSheet(
                onDismissRequest = { submissionTarget = null },
                containerColor = colors.background,
            ) {
                TranslationSubmissionSheet(
                    viewModel = viewModel,
                    hadith = hadith,
                    existingTranslation = translation,
                    initialContent = if (state.language == "en") hadith.englishText.orEmpty() else translation?.translation.orEmpty(),
                    onDone = { submissionTarget = null },
                )
            }
        }

        reportTarget?.let { (hadith, translation) ->
            ModalBottomSheet(
                onDismissRequest = { reportTarget = null },
                containerColor = colors.background,
            ) {
                TranslationReportSheet(
                    viewModel = viewModel,
                    translation = translation,
                    referenceDisplay = hadith.referenceDisplay,
                    onDone = { reportTarget = null },
                )
            }
        }
    }
}

/** Pure counterpart to iOS `ReaderPagePills`: labels never derive a volume
 * number, and an edge target always lands on the neighbor's correct edge. */
internal object ReaderPagePills {
    sealed interface Target {
        data class Page(val index: Int) : Target
        data class VolumeFirst(val volumeId: String) : Target
        data class VolumeLast(val volumeId: String) : Target
    }

    data class Pill(
        val label: String,
        val target: Target,
        val turn: ReaderPageTurn,
        val crossesVolume: Boolean,
    )

    data class State(val previous: Pill?, val next: Pill?)

    fun state(
        pageIndex: Int,
        hasPreviousPage: Boolean,
        hasNextPage: Boolean,
        atLoadedPage: Boolean,
        volumes: List<OutlineVolume>,
        selectedVolumeId: String?,
    ): State {
        val volumeIndex = volumes.indexOfFirst { it.volumeId == selectedVolumeId }
        val previous = when {
            hasPreviousPage -> Pill("Page $pageIndex", Target.Page(pageIndex - 1), ReaderPageTurn.PREVIOUS, false)
            atLoadedPage && volumeIndex > 0 -> {
                val volume = volumes[volumeIndex - 1]
                Pill(volume.title, Target.VolumeLast(volume.volumeId), ReaderPageTurn.PREVIOUS, true)
            }
            else -> null
        }
        val next = when {
            hasNextPage -> Pill("Page ${pageIndex + 2}", Target.Page(pageIndex + 1), ReaderPageTurn.NEXT, false)
            atLoadedPage && volumeIndex >= 0 && volumeIndex < volumes.lastIndex -> {
                val volume = volumes[volumeIndex + 1]
                Pill(volume.title, Target.VolumeFirst(volume.volumeId), ReaderPageTurn.NEXT, true)
            }
            else -> null
        }
        return State(previous, next)
    }
}

/**
 * R6 round two end-of-page navigation: two calm, independently tappable
 * pills. At a volume edge the outward pill names the adjacent volume and
 * takes the same path as the matching accessibility action or edge swipe.
 */
@Composable
internal fun ReaderVolumePills(
    policy: ReaderPagingPolicy,
    state: ReaderPagePills.State,
    onFollow: (ReaderPagePills.Pill) -> Unit,
) {
    val colors = LocalHadithlyColors.current
    Row(
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 12.dp)
            .testTag("reader.pagePills"),
    ) {
        state.previous?.let { PagePill(it, policy, onFollow, Modifier.weight(1f)) } ?: Spacer(Modifier.weight(1f))
        state.next?.let { PagePill(it, policy, onFollow, Modifier.weight(1f)) } ?: Spacer(Modifier.weight(1f))
    }
}

@Composable
private fun PagePill(
    pill: ReaderPagePills.Pill,
    policy: ReaderPagingPolicy,
    onFollow: (ReaderPagePills.Pill) -> Unit,
    modifier: Modifier,
) {
    val colors = LocalHadithlyColors.current
    val pointsLeft = when (policy.pageDirection) {
        com.hadithly.app.core.preferences.PageDirection.LTR -> pill.turn == ReaderPageTurn.PREVIOUS
        com.hadithly.app.core.preferences.PageDirection.RTL -> pill.turn == ReaderPageTurn.NEXT
    }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
        modifier = modifier
            .heightIn(min = 48.dp)
            .background(colors.surface.copy(alpha = 0.96f), RoundedCornerShape(50))
            .clickable { onFollow(pill) }
            .padding(horizontal = 8.dp, vertical = 4.dp)
            .testTag(if (pill.turn == ReaderPageTurn.PREVIOUS) "reader.previousPage" else "reader.nextPage")
            .semantics {
                contentDescription = if (pill.turn == ReaderPageTurn.PREVIOUS) {
                    "Previous page, ${pill.label}"
                } else {
                    "Next page, ${pill.label}"
                }
            },
    ) {
        if (pill.turn == ReaderPageTurn.PREVIOUS) {
            PagePillChevron(pointsLeft)
        }
        Text(
            text = pill.label,
            color = colors.textSecondary,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
            maxLines = 1,
        )
        if (pill.turn == ReaderPageTurn.NEXT) {
            PagePillChevron(pointsLeft)
        }
    }
}

@Composable
private fun PagePillChevron(pointsLeft: Boolean) {
    val colors = LocalHadithlyColors.current
    Icon(
        imageVector = if (pointsLeft) Icons.AutoMirrored.Filled.NavigateBefore else Icons.AutoMirrored.Filled.NavigateNext,
        contentDescription = null,
        tint = colors.textSecondary,
        modifier = Modifier.size(22.dp),
    )
}

/**
 * Historical R6A component retained for the typographic fixture and pager
 * regression tests. The production reader uses [ReaderVolumePills].
 *
 * R6A end-of-page navigation: one centered cluster with the chevrons
 * immediately adjacent to the page pill (`‹ Page X of Y ›`). Direction-aware:
 * the chevron glyphs mirror with the layout direction (AutoMirrored) and the
 * logical previous/next order follows the paging policy. A missing
 * destination hides its chevron; the separated corner buttons are gone.
 */
@Composable
internal fun ReaderEndNavigation(
    policy: ReaderPagingPolicy,
    currentPageIndex: Int,
    pageCount: Int,
    onTurn: (ReaderPageTurn) -> Unit,
) {
    val colors = LocalHadithlyColors.current
    Row(
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 12.dp)
            .testTag("reader.pageCluster")
            .semantics(mergeDescendants = true) {},
    ) {
        val previous = policy.destination(currentPageIndex, pageCount, ReaderPageTurn.PREVIOUS)
        val next = policy.destination(currentPageIndex, pageCount, ReaderPageTurn.NEXT)
        // R6A fix: ONE tight pill — the chevrons sit snug against the label
        // (a few dp inside one capsule), never at the outer corners. The
        // volume pill stays text-only; no volume chevrons yet.
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier.background(colors.surface, RoundedCornerShape(50)),
        ) {
            if (previous != null) {
                PageChevron(
                    turn = ReaderPageTurn.PREVIOUS,
                    destination = previous,
                    pointsLeft = when (policy.pageDirection) {
                        com.hadithly.app.core.preferences.PageDirection.LTR -> true
                        com.hadithly.app.core.preferences.PageDirection.RTL -> false
                    },
                    onTurn = onTurn,
                )
            }
            Text(
                text = if (pageCount > 0) {
                    "Page ${currentPageIndex + 1} of $pageCount"
                } else {
                    "Page ${currentPageIndex + 1}"
                },
                color = colors.textSecondary,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                modifier = Modifier
                    .padding(horizontal = 8.dp, vertical = 10.dp)
                    .testTag("reader.pagePill"),
            )
            if (next != null) {
                PageChevron(
                    turn = ReaderPageTurn.NEXT,
                    destination = next,
                    pointsLeft = when (policy.pageDirection) {
                        com.hadithly.app.core.preferences.PageDirection.LTR -> false
                        com.hadithly.app.core.preferences.PageDirection.RTL -> true
                    },
                    onTurn = onTurn,
                )
            }
        }
    }
}

@Composable
private fun PageChevron(
    turn: ReaderPageTurn,
    destination: Int,
    pointsLeft: Boolean,
    onTurn: (ReaderPageTurn) -> Unit,
) {
    val colors = LocalHadithlyColors.current
    IconButton(
        onClick = { onTurn(turn) },
        modifier = Modifier
            .size(48.dp)
            .testTag(
                if (turn == ReaderPageTurn.PREVIOUS) {
                    "reader.previousPage"
                } else {
                    "reader.nextPage"
                },
            )
            .semantics {
                contentDescription = if (turn == ReaderPageTurn.PREVIOUS) {
                    "Previous page, Page ${destination + 1}"
                } else {
                    "Next page, Page ${destination + 1}"
                }
                customActions = listOf(
                    CustomAccessibilityAction(
                        if (turn == ReaderPageTurn.PREVIOUS) "Previous page" else "Next page",
                    ) {
                        onTurn(turn)
                        true
                    },
                )
            },
    ) {
        Icon(
            if (pointsLeft) {
                Icons.AutoMirrored.Filled.NavigateBefore
            } else {
                Icons.AutoMirrored.Filled.NavigateNext
            },
            contentDescription = null,
            tint = colors.textSecondary,
            modifier = Modifier.size(22.dp),
        )
    }
}

// Top bar

@Composable
private fun ReaderTopBar(
    title: String,
    subtitle: String?,
    onClose: () -> Unit,
    onIndex: () -> Unit,
    onSettings: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.background.copy(alpha = 0.96f))
            // Draw below the status bar; edge-to-edge puts the window under it.
            .statusBarsPadding()
            .padding(horizontal = 16.dp, vertical = 10.dp),
    ) {
        ChromeButton(Icons.Filled.ExpandLess, "Close reader", onClose)
        Spacer(modifier = Modifier.width(12.dp))
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.weight(1f),
        ) {
            Text(
                text = title,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = colors.textPrimary,
                maxLines = 1,
            )
            if (subtitle != null) {
                Text(text = subtitle, fontSize = 11.sp, color = colors.textSecondary, maxLines = 1)
            }
        }
        Spacer(modifier = Modifier.width(12.dp))
        ChromeButton(Icons.AutoMirrored.Filled.List, "Contents", onIndex)
        Spacer(modifier = Modifier.width(12.dp))
        ChromeButton(Icons.Filled.FormatSize, "Reader settings", onSettings)
    }
}

@Composable
private fun ChromeButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit) {
    val colors = LocalHadithlyColors.current
    Box(
        modifier = Modifier
            .size(38.dp)
            .background(colors.surface, CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = label,
            tint = colors.textSecondary,
            modifier = Modifier.size(20.dp),
        )
    }
}

// Bottom pills

@Composable
private fun ReaderBottomPills(volumeTitle: String?, currentPage: Int, totalPages: Int?) {
    val colors = LocalHadithlyColors.current
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .padding(bottom = 12.dp),
    ) {
        Pill(text = volumeTitle ?: return)
        Pill(text = if (totalPages != null) "Page $currentPage of $totalPages" else "Page $currentPage")
    }
}

@Composable
private fun Pill(text: String) {
    val colors = LocalHadithlyColors.current
    Text(
        text = text,
        fontSize = 12.sp,
        fontWeight = FontWeight.Medium,
        color = colors.textSecondary,
        modifier = Modifier
            .background(colors.surface.copy(alpha = 0.96f), RoundedCornerShape(50))
            .padding(horizontal = 12.dp, vertical = 7.dp),
    )
}

/** The thin top progress indicator shown while the reader chrome is hidden.
 * Non-interactive and hidden from traversal; the expanded pill carries the
 * accessible reading-position description. */
@Composable
private fun CompactProgressBar(fraction: Double) {
    val colors = LocalHadithlyColors.current
    Box(
        modifier = Modifier
            .statusBarsPadding()
            .padding(top = 6.dp, start = 24.dp, end = 24.dp)
            .fillMaxWidth()
            .height(3.dp)
            .background(colors.divider.copy(alpha = 0.6f), RoundedCornerShape(50)),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth(fraction.toFloat().coerceIn(0.02f, 1f))
                .height(3.dp)
                .background(colors.textSecondary.copy(alpha = 0.8f), RoundedCornerShape(50)),
        )
    }
}

/**
 * R6A fix: the page-top corner text rule. The WHOLE volume range
 * (`Volume 2: 8–58`) appends only when the volume is fully cached
 * ([ReaderViewModel.isVolumeFullyCached]) and the range is computable from
 * the outline's cumulative counts ([ReaderViewModel.volumeHadithRange]);
 * otherwise the title stands alone. Single-digit volumes render `Title: n`.
 */
internal fun volumeCornerText(
    title: String,
    volumes: List<OutlineVolume>,
    volumeId: String?,
    pages: List<ReaderPageResult>,
): String {
    val range = volumeId
        ?.takeIf { ReaderViewModel.isVolumeFullyCached(pages) }
        ?.let { ReaderViewModel.volumeHadithRange(volumes, it) }
    return if (range != null) "$title: ${range.first}–${range.second}" else title
}

/**
 * R6A page-top corner label: the localized volume title at the leading top
 * corner (start alignment mirrors in RTL), quiet secondary style. The
 * `: first–last` range appends only when the volume is fully cached and
 * computable; otherwise the title stands alone.
 */
@Composable
internal fun VolumeCornerLabel(title: String, range: Pair<Int, Int>?) {
    val colors = LocalHadithlyColors.current
    Text(
        text = if (range != null) "$title: ${range.first}–${range.second}" else title,
        fontSize = 12.sp,
        color = colors.textSecondary,
        textAlign = TextAlign.Start,
        modifier = Modifier
            .fillMaxWidth()
            .testTag("reader.volumeCorner"),
    )
}

/**
 * R6A volume start: the volume title header with a localized ICU-plural
 * count line beneath (e.g. "10 hadiths"). Rendered on the volume's first
 * page only.
 */
@Composable
internal fun VolumeStartHeader(title: String, hadithCount: Int) {
    val colors = LocalHadithlyColors.current
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 12.dp, bottom = 24.dp),
    ) {
        Text(
            text = title,
            fontSize = 20.sp,
            fontWeight = FontWeight.SemiBold,
            color = colors.textPrimary,
            textAlign = TextAlign.Center,
        )
        if (hadithCount > 0) {
            Text(
                text = pluralStringResource(R.plurals.reader_hadith_count, hadithCount, hadithCount),
                fontSize = 13.sp,
                color = colors.textSecondary,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 4.dp),
            )
        }
    }
}

/**
 * The quiet, source-provided chapter opening (R6A fix). A single name-only
 * line — never the word "Chapter" — at near-body size in the primary text
 * color, with generous space above. The source Arabic subtitle stays a
 * smaller secondary second line. Never synthesized: rendered only when the
 * provider data carries a chapter name.
 */
@Composable
internal fun ReaderChapterHeader(title: String, arabicTitle: String? = null) {
    val colors = LocalHadithlyColors.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 28.dp, bottom = 8.dp)
            .semantics(mergeDescendants = true) {}
            .testTag("reader.chapterHeader"),
    ) {
        Text(
            text = title,
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
            color = colors.textPrimary,
            textAlign = TextAlign.Start,
            modifier = Modifier.fillMaxWidth(),
        )
        if (!arabicTitle.isNullOrEmpty()) {
            Text(
                text = arabicTitle,
                fontSize = 13.sp,
                color = colors.textSecondary,
                textAlign = TextAlign.Start,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 2.dp),
            )
        }
    }
}

/** A source Arabic name is a secondary line only while Arabic text is on. */
internal fun visibleArabicChapterTitle(
    arabicVisible: Boolean,
    title: String,
    arabicTitle: String?,
): String? = arabicTitle
    ?.trim()
    ?.takeIf { arabicVisible && it.isNotEmpty() && it != title }

// One hadith

/**
 * The normalized authenticity grade behind the R6A grade dot. Anything
 * outside sahih/hasan/daif (including absent grades) renders gray.
 */
internal enum class ReaderGrade {
    SAHIH,
    HASAN,
    DAIF,
    OTHER;

    companion object {
        fun from(normalizedGrade: String?): ReaderGrade =
            when (normalizedGrade?.trim()?.lowercase()) {
                "sahih" -> SAHIH
                "hasan" -> HASAN
                "daif", "dhaif", "da'if", "daeef" -> DAIF
                else -> OTHER
            }
    }

    /** Screen-reader grade name, mirroring the iOS header label. */
    val displayName: String
        get() = when (this) {
            SAHIH -> "Sahih"
            HASAN -> "Hasan"
            DAIF -> "Daif"
            OTHER -> "Unverified"
        }
}

/**
 * R6A grade-dot color, resolved from the reader palette so it stays
 * theme-aware across System, Light, Paper, and Dark: sahih green (accent),
 * hasan amber (bookmark), daif red (destructive), anything else gray
 * (secondary text).
 */
internal fun gradeDotColor(
    grade: ReaderGrade,
    colors: com.hadithly.app.core.theme.HadithlyColors,
): androidx.compose.ui.graphics.Color = when (grade) {
    ReaderGrade.SAHIH -> colors.accent
    ReaderGrade.HASAN -> colors.bookmark
    ReaderGrade.DAIF -> colors.destructive
    ReaderGrade.OTHER -> colors.textSecondary
}

/**
 * The saved-state reads and toggles a hadith block needs. ReaderPage
 * supplies the ViewModel-backed implementation; tests supply a fake so the
 * real block (long-press menu, TalkBack actions) stays covered.
 */
internal interface HadithBlockDeps {
    val isBookmarked: Boolean
    val isFavorite: Boolean
    val hasNote: Boolean
    fun onToggleBookmark()
    fun onToggleFavorite()
}

@Composable
internal fun HadithBlock(
    hadith: ReaderHadith,
    translationState: TranslationUiState?,
    language: String,
    arabicFontSize: Float,
    preferences: ReaderPreferences,
    deps: HadithBlockDeps,
    modifier: Modifier = Modifier,
    onTap: () -> Unit,
    onRetry: () -> Unit,
    onShowCitations: (ReaderTranslation) -> Unit,
    onShowSource: () -> Unit,
    onEditNote: () -> Unit,
    onSuggest: (ReaderTranslation?) -> Unit,
    onReport: (ReaderTranslation) -> Unit,
    onShowPaywall: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    val arabicFamily = com.hadithly.app.core.theme.ArabicTypefaces.forFont(preferences.arabicFont)
    val clipboard = LocalClipboard.current
    val clipboardScope = rememberCoroutineScope()
    val context = LocalContext.current
    var menuExpanded by remember { mutableStateOf(false) }

    val loadedTranslation = (translationState as? TranslationUiState.Loaded)?.translation
    // Report gating matches the old inline row: a Loaded state only exists
    // for non-English translations, so its presence implies reportability.
    val visibleArabic = hadith.arabicText.takeIf { preferences.arabicVisible }
    val visibleTranslation: String?
    val visibleTranslationIsAi: Boolean
    if (language == "en") {
        visibleTranslation = hadith.englishText.takeIf { preferences.translationVisible }
        visibleTranslationIsAi = false
    } else {
        visibleTranslation = loadedTranslation?.translation.takeIf { preferences.translationVisible }
        visibleTranslationIsAi = loadedTranslation?.source == "gemini_ai"
    }

    fun doCopy() {
        val text = ReaderShare.formatCopyText(
            arabicText = visibleArabic,
            translationText = visibleTranslation,
            translationIsAi = visibleTranslationIsAi,
            collectionName = hadith.collectionName,
            providerHadithId = hadith.providerHadithId,
            sourceName = hadith.authenticity.sourceName,
        )
        clipboardScope.launch {
            clipboard.setClipEntry(ClipEntry(ClipData.newPlainText(hadith.referenceDisplay, text)))
        }
    }

    fun doShare() {
        val url = com.hadithly.app.core.links.CanonicalHadithUrl.build(
            hadith.collectionSlug,
            hadith.providerHadithId,
        )
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, url)
        }
        context.startActivity(Intent.createChooser(send, null))
    }

    // One code path: the long-press menu opens the shared DropdownMenu
    // content. The R5 overflow button is deleted with no visual replacement;
    // TalkBack custom actions below are the screen-reader equivalent.
    val menuActions = hadithMenuActions(
        isBookmarked = deps.isBookmarked,
        isFavorite = deps.isFavorite,
        hasNote = deps.hasNote,
        loadedTranslation = loadedTranslation,
        onToggleBookmark = deps::onToggleBookmark,
        onToggleFavorite = deps::onToggleFavorite,
        onEditNote = onEditNote,
        onCopy = { doCopy() },
        onShare = { doShare() },
        onReport = onReport,
        onSuggest = onSuggest,
    )

    Column(
        verticalArrangement = Arrangement.spacedBy(16.dp),
        modifier = modifier
            .combinedClickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                // Tap still toggles the chrome; the block consumes the press
                // so the page-level tap detector must be invoked explicitly.
                onClick = onTap,
                onLongClick = { menuExpanded = true },
            )
            .semantics {
                customActions = customActionsFor(menuActions)
            }
            .testTag("reader.hadithBlock"),
    ) {
        // R6A fix: one header per hadith at the TOP (`● [Collection – n]`,
        // tappable for the source sheet). The bottom compact label and the
        // dim bare-number marker are gone — no duplication.
        HadithHeader(
            hadith = hadith,
            isBookmarked = deps.isBookmarked,
            isFavorite = deps.isFavorite,
            onShowSource = onShowSource,
        )

        HadithContextMenu(
            referenceDisplay = hadith.referenceDisplay,
            actions = menuActions,
            expanded = menuExpanded,
            onDismiss = { menuExpanded = false },
        )

        val arabicOnly = preferences.arabicVisible && !preferences.translationVisible
        if (arabicOnly) {
            NarratorLine(hadith.narrator, preferences, arabicAligned = true)
        }

        if (preferences.arabicVisible) {
            CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                Text(
                    text = hadith.arabicText,
                    fontSize = arabicFontSize.sp,
                    fontFamily = arabicFamily,
                    fontWeight = FontWeight.Medium,
                    color = colors.textPrimary,
                    lineHeight = (arabicFontSize * 1.75).sp,
                    // R6A: start-aligned with RTL shaping kept (never LTR
                    // glyphs); only the alignment changes.
                    textAlign = TextAlign.Start,
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("reader.arabic"),
                )
            }
        }

        // Translation-only and mixed modes retain the narrator at the
        // translation's leading edge. Arabic-only mode placed it above the
        // Arabic block, under the source header, in the Arabic direction.
        if (!arabicOnly) {
            NarratorLine(hadith.narrator, preferences, arabicAligned = false)
        }

        if (preferences.translationVisible) {
            CompositionLocalProvider(
                LocalLayoutDirection provides if (LocaleFallback.isRTL(preferences.translationLocale)) {
                    LayoutDirection.Rtl
                } else {
                    LayoutDirection.Ltr
                },
            ) {
                TranslationSection(
                    hadith = hadith,
                    translationState = translationState,
                    language = language,
                    onRetry = onRetry,
                    onShowCitations = onShowCitations,
                    onShowPaywall = onShowPaywall,
                )
            }
        }

        // R6A fix: no bottom label — the top header is the single per-hadith
        // header (source sheet tap lives there; copy/share payloads keep
        // the full source line via ReaderShare).
    }
}

/**
 * The narrator is present whenever either visible text layer has content.
 * Arabic-only reading puts it in the Arabic flow; mixed and translation-only
 * reading uses the translation's leading edge.
 */
internal fun shouldShowNarrator(
    narrator: String?,
    arabicVisible: Boolean,
    translationVisible: Boolean,
): Boolean = !narrator.isNullOrBlank() && (arabicVisible || translationVisible)

@Composable
private fun NarratorLine(narrator: String?, preferences: ReaderPreferences, arabicAligned: Boolean) {
    if (!shouldShowNarrator(narrator, preferences.arabicVisible, preferences.translationVisible)) return
    val colors = LocalHadithlyColors.current
    val direction = if (arabicAligned || LocaleFallback.isRTL(preferences.translationLocale)) {
        LayoutDirection.Rtl
    } else {
        LayoutDirection.Ltr
    }
    CompositionLocalProvider(LocalLayoutDirection provides direction) {
        Text(
            text = narrator.orEmpty(),
            fontSize = 12.sp,
            color = colors.textSecondary,
            textAlign = if (arabicAligned) TextAlign.End else TextAlign.Start,
            modifier = Modifier
                .fillMaxWidth()
                .testTag("reader.narrator"),
        )
    }
}

/**
 * R6A fix: non-interactive saved-state indicators trailing the header
 * label. Bookmark and favorite only — there is no note icon (notes stay in
 * the long-press menu, TalkBack actions, and the bottom menu later).
 */
internal enum class SavedMiniMarker {
    BOOKMARK,
    FAVORITE;
}

internal fun savedMiniMarkers(isBookmarked: Boolean, isFavorite: Boolean): List<SavedMiniMarker> =
    buildList {
        if (isBookmarked) add(SavedMiniMarker.BOOKMARK)
        if (isFavorite) add(SavedMiniMarker.FAVORITE)
    }

/**
 * R6A fix: the bracketed per-hadith header label (`[Bukhari – 57]`).
 * The full source line stays in copy/share payloads; the header shows
 * only this quiet label with the grade dot before it.
 */
internal fun hadithHeaderText(collectionSlug: String, collectionName: String, providerHadithId: String): String =
    "${ReaderViewModel.shortCollectionName(collectionSlug, collectionName)} – $providerHadithId"

/**
 * R6A fix: one header per hadith at the TOP — grade dot plus the bracketed
 * `[short name – id]` (e.g. `● [Bukhari – 57]`). Tapping opens the source
 * bottom sheet. Saved-state mini markers (amber bookmark, pink heart)
 * trail the label as non-interactive indicators only (outside the tap
 * target, like iOS).
 */
@Composable
internal fun HadithHeader(
    hadith: ReaderHadith,
    isBookmarked: Boolean,
    isFavorite: Boolean,
    onShowSource: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    val grade = ReaderGrade.from(hadith.authenticity.normalizedGrade)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .clickable(onClick = onShowSource)
                .testTag("reader.hadithLabel")
                .semantics {
                    contentDescription =
                        "${ReaderViewModel.shortCollectionName(hadith.collectionSlug, hadith.collectionName)} – ${hadith.providerHadithId}, ${grade.displayName}"
                },
        ) {
            Box(
                modifier = Modifier
                    .size(8.dp)
                    .background(gradeDotColor(grade, colors), CircleShape),
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = hadithHeaderText(hadith.collectionSlug, hadith.collectionName, hadith.providerHadithId),
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                color = colors.textPrimary,
            )
        }
        for (marker in savedMiniMarkers(isBookmarked, isFavorite)) {
            Spacer(modifier = Modifier.width(7.dp))
            Icon(
                imageVector = when (marker) {
                    SavedMiniMarker.BOOKMARK -> Icons.Filled.Bookmark
                    SavedMiniMarker.FAVORITE -> Icons.Filled.Favorite
                },
                contentDescription = when (marker) {
                    SavedMiniMarker.BOOKMARK -> "Bookmarked"
                    SavedMiniMarker.FAVORITE -> "Favorited"
                },
                tint = when (marker) {
                    SavedMiniMarker.BOOKMARK -> colors.bookmark
                    SavedMiniMarker.FAVORITE -> colors.favorite
                },
                modifier = Modifier
                    .size(12.dp)
                    .testTag(
                        when (marker) {
                            SavedMiniMarker.BOOKMARK -> "reader.savedBookmark"
                            SavedMiniMarker.FAVORITE -> "reader.savedFavorite"
                        },
                    ),
            )
        }
    }
}

/**
 * R6A small source bottom sheet: source name, scope/grade text, and the
 * source URL when present.
 */
@Composable
internal fun HadithSourceSheet(hadith: ReaderHadith) {
    val colors = LocalHadithlyColors.current
    Column(
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(20.dp)
            .testTag("reader.sourceSheet"),
    ) {
        Text(
            text = hadith.authenticity.sourceName,
            fontSize = 17.sp,
            fontWeight = FontWeight.SemiBold,
            color = colors.textPrimary,
        )
        Text(
            text = hadith.authenticity.displayLabel,
            fontSize = 13.sp,
            color = colors.textSecondary,
        )
        if (hadith.authenticity.sourceUrl.isNotBlank()) {
            Text(
                text = hadith.authenticity.sourceUrl,
                fontSize = 12.sp,
                color = colors.accent,
            )
        }
    }
}

/** One hadith context action, shared by the DropdownMenu and TalkBack custom actions. */
internal data class HadithMenuAction(
    val testTag: String,
    val label: String,
    val secondary: Boolean = false,
    val onInvoke: () -> Unit,
)

/**
 * Builds the seven per-hadith actions (R5 set, kept in R6A) from saved state
 * and callbacks. One code path feeds both the long-press DropdownMenu and
 * the TalkBack custom actions. Report appears only when a loaded
 * non-English translation exists.
 */
internal fun hadithMenuActions(
    isBookmarked: Boolean,
    isFavorite: Boolean,
    hasNote: Boolean,
    loadedTranslation: ReaderTranslation?,
    onToggleBookmark: () -> Unit,
    onToggleFavorite: () -> Unit,
    onEditNote: () -> Unit,
    onCopy: () -> Unit,
    onShare: () -> Unit,
    onReport: (ReaderTranslation) -> Unit,
    onSuggest: (ReaderTranslation?) -> Unit,
): List<HadithMenuAction> = buildList {
    add(
        HadithMenuAction(
            testTag = "reader.bookmark",
            label = if (isBookmarked) "Remove bookmark" else "Bookmark",
        ) { onToggleBookmark() },
    )
    add(
        HadithMenuAction(
            testTag = "reader.favorite",
            label = if (isFavorite) "Remove from favorites" else "Add to favorites",
        ) { onToggleFavorite() },
    )
    add(
        HadithMenuAction(
            testTag = "reader.note",
            label = if (hasNote) "Edit note" else "Add note",
        ) { onEditNote() },
    )
    add(HadithMenuAction(testTag = "reader.copy", label = "Copy") { onCopy() })
    add(HadithMenuAction(testTag = "reader.share", label = "Share") { onShare() })
    loadedTranslation?.let { translation ->
        add(
            HadithMenuAction(
                testTag = "reader.reportTranslation",
                label = "Report translation",
                secondary = true,
            ) { onReport(translation) },
        )
    }
    add(
        HadithMenuAction(
            testTag = "reader.suggestTranslation",
            label = "Suggest translation",
            secondary = true,
        ) { onSuggest(loadedTranslation) },
    )
}

/**
 * The TalkBack custom actions for one hadith block: the same seven actions
 * as the long-press menu, label for label, as the screen-reader equivalent
 * of the deleted overflow button.
 */
internal fun customActionsFor(actions: List<HadithMenuAction>): List<CustomAccessibilityAction> =
    actions.map { action ->
        CustomAccessibilityAction(action.label) {
            action.onInvoke()
            true
        }
    }

/**
 * The native per-hadith context menu (R5, kept in R6A). Opened by long-press
 * only since R6A deleted the overflow button; no playback, Siri,
 * transcription, search, or reciter items.
 */
@Composable
internal fun HadithContextMenu(
    referenceDisplay: String,
    actions: List<HadithMenuAction>,
    expanded: Boolean,
    onDismiss: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    DropdownMenu(
        expanded = expanded,
        onDismissRequest = onDismiss,
        containerColor = colors.surface,
    ) {
        Text(
            text = referenceDisplay,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            color = colors.textSecondary,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        )
        val (primary, secondary) = actions.partition { !it.secondary }
        for (action in primary) {
            DropdownMenuItem(
                text = { Text(action.label, fontSize = 15.sp, color = colors.textPrimary) },
                onClick = {
                    onDismiss()
                    action.onInvoke()
                },
                modifier = Modifier.testTag(action.testTag),
            )
        }
        if (secondary.isNotEmpty()) {
            HorizontalDivider(color = colors.divider)
            for (action in secondary) {
                DropdownMenuItem(
                    text = { Text(action.label, fontSize = 15.sp, color = colors.textPrimary) },
                    onClick = {
                        onDismiss()
                        action.onInvoke()
                    },
                    modifier = Modifier.testTag(action.testTag),
                )
            }
        }
    }
}

@Composable
private fun TranslationSection(
    hadith: ReaderHadith,
    translationState: TranslationUiState?,
    language: String,
    onRetry: () -> Unit,
    onShowCitations: (ReaderTranslation) -> Unit,
    onShowPaywall: () -> Unit,
) {
    val colors = LocalHadithlyColors.current

    if (language == "en") {
        val english = hadith.englishText
        if (!english.isNullOrEmpty()) {
            TranslationText(text = english, storedTranslation = null, onShowCitations = {})
        } else {
            Text("No English translation available yet.", fontSize = 12.sp, color = colors.textSecondary)
        }
        return
    }

    when (translationState) {
        null, is TranslationUiState.Loading -> Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            CircularProgressIndicator(color = colors.textSecondary, modifier = Modifier.size(14.dp), strokeWidth = 2.dp)
            Text("AI translation…", fontSize = 12.sp, color = colors.textSecondary)
        }

        is TranslationUiState.Loaded -> {
            TranslationText(
                text = translationState.translation.translation,
                storedTranslation = translationState.translation,
                onShowCitations = { onShowCitations(translationState.translation) },
            )
            GlossaryNotes(translationState.translation.glossaryNotes)
        }

        is TranslationUiState.Failed -> when (translationState.failure) {
            TranslationFailure.RequiresSignIn -> QuietNotice(
                text = "Sign in to get AI translations in your language. Sign-in lives on the Settings tab.",
            )
            TranslationFailure.QuotaExceeded -> QuietNotice(
                text = "You've used your free AI translations for this month. Reading continues as usual.",
                actionTitle = "See plans",
                onAction = onShowPaywall,
            )
            is TranslationFailure.Failed -> TextButton(onClick = onRetry) {
                Text("AI translation unavailable · retry", fontSize = 12.sp, color = colors.textSecondary)
            }
        }
    }
}

@Composable
private fun TranslationText(
    text: String,
    storedTranslation: ReaderTranslation?,
    onShowCitations: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        when (storedTranslation?.source) {
            "gemini_ai" -> SourceBadge(
                icon = Icons.Filled.AutoAwesome,
                main = "AI",
                trailing = "· sources",
                onClick = onShowCitations,
            )
            "community" -> SourceBadge(
                icon = Icons.Filled.CheckCircle,
                main = "Community",
                trailing = "· admin approved",
                onClick = null,
            )
        }
        Text(
            text = text,
            fontSize = 16.sp,
            lineHeight = 23.sp,
            color = colors.textPrimary.copy(alpha = 0.92f),
        )
    }
}

@Composable
private fun SourceBadge(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    main: String,
    trailing: String,
    onClick: (() -> Unit)?,
) {
    val colors = LocalHadithlyColors.current
    Row(
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .background(colors.accentSoft, RoundedCornerShape(50))
            .clickable(enabled = onClick != null) { onClick?.invoke() }
            .padding(horizontal = 10.dp, vertical = 5.dp),
    ) {
        Icon(icon, contentDescription = null, tint = colors.accent, modifier = Modifier.size(12.dp))
        Text(main, fontSize = 11.sp, fontWeight = FontWeight.Bold, color = colors.accent)
        Text(trailing, fontSize = 11.sp, color = colors.textSecondary)
    }
}

@Composable
private fun GlossaryNotes(notes: List<String>) {
    val colors = LocalHadithlyColors.current
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        for (note in notes) {
            Text("· $note", fontSize = 11.sp, color = colors.textSecondary)
        }
    }
}

@Composable
private fun QuietNotice(
    text: String,
    actionTitle: String? = null,
    onAction: (() -> Unit)? = null,
) {
    val colors = LocalHadithlyColors.current
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.padding(vertical = 8.dp),
    ) {
        Text(
            text = text,
            fontSize = 12.sp,
            color = colors.textSecondary,
            textAlign = TextAlign.Center,
        )
        if (actionTitle != null && onAction != null) {
            TextButton(onClick = onAction) {
                Text(actionTitle, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = colors.accent)
            }
        }
    }
}

// Contents sheet

@Composable
internal fun ContentsSheet(
    volumes: List<com.hadithly.app.core.data.OutlineVolume>,
    selectedVolumeId: String?,
    arabicVisible: Boolean,
    onSelect: (String) -> Unit,
    onSelectChapter: (String, com.hadithly.app.core.data.OutlineChapter) -> Unit,
    onJumpToReference: (String) -> Boolean,
    onDismiss: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    var expandedVolumeId by remember(selectedVolumeId) { mutableStateOf(selectedVolumeId) }
    var jumpInput by remember { mutableStateOf("") }
    var jumpError by remember { mutableStateOf<String?>(null) }

    fun submitJump() {
        if (onJumpToReference(jumpInput.trim())) {
            onDismiss()
        } else {
            jumpError = "Enter a hadith number like 57 or 4.5."
        }
    }

    LazyColumn(
        verticalArrangement = Arrangement.spacedBy(8.dp),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp),
    ) {
        item {
            Text("Contents", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)
            Spacer(modifier = Modifier.height(8.dp))
        }
        item(key = "contents-jump") {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                OutlinedTextField(
                    value = jumpInput,
                    onValueChange = {
                        jumpInput = it
                        jumpError = null
                    },
                    label = { Text("Go to hadith number", color = colors.textSecondary) },
                    placeholder = { Text("57", color = colors.textSecondary) },
                    singleLine = true,
                    isError = jumpError != null,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { submitJump() }),
                    colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = colors.accent,
                        unfocusedBorderColor = colors.divider,
                        focusedTextColor = colors.textPrimary,
                        unfocusedTextColor = colors.textPrimary,
                        cursorColor = colors.accent,
                        focusedContainerColor = colors.surfaceElevated,
                        unfocusedContainerColor = colors.surfaceElevated,
                        errorBorderColor = colors.favorite,
                    ),
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("reader.contents.jump"),
                )
                if (jumpError != null) {
                    Text(jumpError.orEmpty(), fontSize = 12.sp, color = colors.textSecondary)
                }
            }
        }
        items(volumes, key = { it.volumeId }) { volume ->
            val selected = volume.volumeId == selectedVolumeId
            val expanded = expandedVolumeId == volume.volumeId
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(if (selected) colors.accentSoft else colors.surfaceElevated, RoundedCornerShape(12.dp))
                    .padding(horizontal = 16.dp, vertical = 6.dp),
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .clickable { onSelect(volume.volumeId) }
                            .padding(vertical = 8.dp),
                    ) {
                        Text(
                            text = volume.title,
                            fontSize = 15.sp,
                            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                            color = colors.textPrimary,
                        )
                        Text(
                            text = "${volume.hadithCount.toInt()} hadiths",
                            fontSize = 11.sp,
                            color = colors.textSecondary,
                        )
                    }
                    // Chapters render only when the source provides them;
                    // pre-R5 cached outlines show volumes exactly as before.
                    if (volume.chapters.isNotEmpty()) {
                        IconButton(
                            onClick = {
                                expandedVolumeId = if (expanded) null else volume.volumeId
                            },
                            modifier = Modifier.size(48.dp),
                        ) {
                            Icon(
                                imageVector = if (expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                                contentDescription = if (expanded) {
                                    "Collapse chapters in ${volume.title}"
                                } else {
                                    "Expand chapters in ${volume.title}"
                                },
                                tint = colors.textSecondary,
                                modifier = Modifier.size(20.dp),
                            )
                        }
                    }
                }
                if (expanded) {
                    for (chapter in volume.chapters) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onSelectChapter(volume.volumeId, chapter) }
                                .padding(start = 12.dp, top = 8.dp, bottom = 8.dp, end = 4.dp)
                                .testTag("reader.contents.chapter.${volume.volumeId}.${chapter.firstProviderHadithId}"),
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = chapter.title,
                                    fontSize = 14.sp,
                                    color = colors.textPrimary,
                                )
                                val arabic = visibleArabicChapterTitle(
                                    arabicVisible = arabicVisible,
                                    title = chapter.title,
                                    arabicTitle = chapter.arabicTitle,
                                )
                                if (arabic != null) {
                                    Text(
                                        text = arabic,
                                        fontSize = 12.sp,
                                        color = colors.textSecondary,
                                    )
                                }
                                Text(
                                    text = "${chapter.hadithCount.toInt()} hadiths",
                                    fontSize = 11.sp,
                                    color = colors.textSecondary,
                                )
                            }
                        }
                    }
                    Spacer(modifier = Modifier.height(4.dp))
                }
            }
        }
    }
}

// Reader settings sheet

/**
 * Reader settings (R4): visibility, theme, Arabic face and size with a live
 * preview, and the translation language. Direct controls, close to the text;
 * account and global settings stay in the Settings tab.
 */
@Composable
private fun SettingsSheet(
    preferences: ReaderPreferences,
    language: String,
    onLanguage: (String) -> Unit,
    onArabicFontSize: (Float) -> Unit,
    onTheme: (com.hadithly.app.core.preferences.ReaderTheme) -> Unit,
    onArabicFont: (com.hadithly.app.core.preferences.ArabicFont) -> Unit,
    onVisibility: (arabic: Boolean?, translation: Boolean?) -> Unit,
) {
    val colors = LocalHadithlyColors.current
    Column(
        verticalArrangement = Arrangement.spacedBy(16.dp),
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(start = 20.dp, top = 20.dp, end = 20.dp, bottom = 32.dp),
    ) {
        Text("Reader settings", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)

        Text("Show on page", fontSize = 13.sp, color = colors.textSecondary)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            VisibilityPill(
                title = "Arabic",
                isOn = preferences.arabicVisible,
                testTag = "reader.visibility.arabic",
            ) { onVisibility(!preferences.arabicVisible, null) }
            VisibilityPill(
                title = "Translation",
                isOn = preferences.translationVisible,
                testTag = "reader.visibility.translation",
            ) { onVisibility(null, !preferences.translationVisible) }
        }
        Text(
            "At least one text layer stays visible.",
            fontSize = 12.sp,
            color = colors.textSecondary,
        )

        Text("Color theme", fontSize = 13.sp, color = colors.textSecondary)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (theme in com.hadithly.app.core.preferences.ReaderTheme.entries) {
                val selected = preferences.theme == theme
                val swatch = com.hadithly.app.core.theme.ReaderPalettes.resolved(theme, systemDark = true)
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier
                        .background(
                            if (selected) colors.accentSoft else androidx.compose.ui.graphics.Color.Transparent,
                            RoundedCornerShape(10.dp),
                        )
                        .selectable(
                            selected = selected,
                            role = Role.RadioButton,
                            onClick = { onTheme(theme) },
                        )
                        .padding(6.dp)
                        .testTag("reader.theme.${theme.wire}"),
                ) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(34.dp)
                            .background(swatch.background, RoundedCornerShape(8.dp)),
                    )
                    Text(
                        text = theme.wire.replaceFirstChar { it.uppercase() },
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Medium,
                        color = if (selected) colors.accent else colors.textSecondary,
                        modifier = Modifier.padding(top = 4.dp),
                    )
                }
            }
        }

        Text("Arabic type", fontSize = 13.sp, color = colors.textSecondary)
        Text(
            text = "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ",
            fontSize = preferences.arabicFontSize.sp,
            fontFamily = com.hadithly.app.core.theme.ArabicTypefaces.forFont(preferences.arabicFont),
            lineHeight = (preferences.arabicFontSize * 1.75).sp,
            color = colors.textPrimary,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .background(colors.surfaceElevated, RoundedCornerShape(12.dp))
                .padding(vertical = 10.dp)
                .testTag("reader.typePreview"),
        )
        Row(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(48.dp)
                    .background(colors.surfaceElevated, RoundedCornerShape(50))
                    .clickable(
                        enabled = preferences.arabicFontSize > ReaderPreferences.MIN_ARABIC_FONT_SIZE,
                    ) { onArabicFontSize(ArabicTypeSize.stepDown(preferences.arabicFontSize)) }
                    .semantics { contentDescription = "Smaller Arabic type" }
                    .testTag("reader.sizeSmaller"),
                contentAlignment = Alignment.Center,
            ) { Text("A", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary) }
            Text(
                text = "${preferences.arabicFontSize.roundToInt()} pt",
                fontSize = 12.sp,
                color = colors.textSecondary,
            )
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(48.dp)
                    .background(colors.surfaceElevated, RoundedCornerShape(50))
                    .clickable(
                        enabled = preferences.arabicFontSize < ReaderPreferences.MAX_ARABIC_FONT_SIZE,
                    ) { onArabicFontSize(ArabicTypeSize.stepUp(preferences.arabicFontSize)) }
                    .semantics { contentDescription = "Larger Arabic type" }
                    .testTag("reader.sizeLarger"),
                contentAlignment = Alignment.Center,
            ) { Text("A", fontSize = 18.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary) }
        }

        for (font in com.hadithly.app.core.preferences.ArabicFont.entries) {
            val selected = preferences.arabicFont == font
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .background(if (selected) colors.accentSoft else colors.surfaceElevated, RoundedCornerShape(10.dp))
                    .selectable(
                        selected = selected,
                        role = Role.RadioButton,
                        onClick = { onArabicFont(font) },
                    )
                    .padding(horizontal = 14.dp, vertical = 10.dp)
                    .testTag("reader.font.${font.wire}"),
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "بِسْمِ اللَّهِ",
                        fontSize = 18.sp,
                        fontFamily = com.hadithly.app.core.theme.ArabicTypefaces.forFont(font),
                        color = colors.textPrimary,
                    )
                    Text(
                        text = font.wire,
                        fontSize = 11.sp,
                        color = colors.textSecondary,
                    )
                }
                if (selected) {
                    Icon(
                        Icons.Filled.CheckCircle,
                        contentDescription = null,
                        tint = colors.accent,
                        modifier = Modifier.size(18.dp),
                    )
                }
            }
        }

        Text("Translation language", fontSize = 13.sp, color = colors.textSecondary)
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for ((code, name) in SupportedLanguages.all) {
                val selected = code == language
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(if (selected) colors.accentSoft else colors.surfaceElevated, RoundedCornerShape(12.dp))
                        .selectable(
                            selected = selected,
                            role = Role.RadioButton,
                            onClick = { onLanguage(code) },
                        )
                        .padding(horizontal = 16.dp, vertical = 12.dp)
                        .testTag("reader.language.$code"),
                ) {
                    Text(name, fontSize = 15.sp, color = colors.textPrimary, modifier = Modifier.weight(1f))
                    if (selected) {
                        Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = colors.accent, modifier = Modifier.size(18.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun VisibilityPill(
    title: String,
    isOn: Boolean,
    testTag: String,
    onToggle: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    Row(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .background(if (isOn) colors.accentSoft else colors.surfaceElevated, RoundedCornerShape(50))
            .toggleable(
                value = isOn,
                role = Role.Switch,
                onValueChange = { onToggle() },
            )
            .padding(horizontal = 14.dp, vertical = 10.dp)
            .testTag(testTag),
    ) {
        Icon(
            imageVector = if (isOn) Icons.Filled.CheckCircle else Icons.Outlined.RadioButtonUnchecked,
            contentDescription = null,
            tint = if (isOn) colors.accent else colors.textSecondary,
            modifier = Modifier.size(18.dp),
        )
        Text(
            title,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
            color = if (isOn) colors.accent else colors.textSecondary,
        )
    }
}

// Citations sheet

@Composable
private fun CitationsSheet(translation: ReaderTranslation) {
    val colors = LocalHadithlyColors.current
    Column(
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(20.dp),
    ) {
        Text("Sources", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)
        Text(
            text = translation.translation,
            fontSize = 15.sp,
            color = colors.textPrimary,
        )
        translation.sourceReferenceUrl?.let { url ->
            Text("Reference: $url", fontSize = 12.sp, color = colors.accent)
        }
        if (translation.citations.isNotEmpty()) {
            Text("Grounding citations", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = colors.textSecondary)
            for (citation in translation.citations) {
                Column {
                    Text(citation.title ?: citation.url, fontSize = 13.sp, color = colors.textPrimary)
                    citation.domain?.let { Text(it, fontSize = 11.sp, color = colors.textSecondary) }
                }
            }
        }
        Text(
            text = "AI translations are generated with ${translation.aiModel ?: "an AI model"} and grounded in cited sources, but are not authoritative.",
            fontSize = 11.sp,
            color = colors.textSecondary,
        )
    }
}

// Note editor sheet

@Composable
private fun NoteEditorSheet(
    initialContent: String?,
    onSave: (String) -> Unit,
    onCancel: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    var content by remember { mutableStateOf(initialContent ?: "") }

    Column(
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(20.dp),
    ) {
        Text("Note", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)
        androidx.compose.material3.OutlinedTextField(
            value = content,
            onValueChange = { content = it },
            placeholder = { Text("Write a private note…", color = colors.textSecondary) },
            colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
                focusedBorderColor = colors.accent,
                unfocusedBorderColor = colors.surfaceElevated,
                focusedTextColor = colors.textPrimary,
                unfocusedTextColor = colors.textPrimary,
                cursorColor = colors.accent,
                focusedContainerColor = colors.surfaceElevated,
                unfocusedContainerColor = colors.surfaceElevated,
            ),
            modifier = Modifier
                .fillMaxWidth()
                .height(160.dp),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            TextButton(onClick = onCancel) { Text("Cancel", color = colors.textSecondary) }
            TextButton(
                onClick = {
                    val trimmed = content.trim()
                    if (trimmed.isNotEmpty()) onSave(trimmed)
                },
            ) { Text("Save", color = colors.accent, fontWeight = FontWeight.Bold) }
        }
    }
}
