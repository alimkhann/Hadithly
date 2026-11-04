@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.hadithly.app.features.reader

import com.hadithly.app.core.data.UserLibraryModel
import com.hadithly.app.core.preferences.nativeText
import com.hadithly.app.core.preferences.runtimeNoticeText

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.interaction.DragInteraction
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
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
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PagerScope
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.automirrored.filled.Note
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.automirrored.filled.NavigateNext
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.BookmarkBorder
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.HourglassEmpty
import androidx.compose.material.icons.filled.PersonOutline
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.ChatBubbleOutline
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FormatSize
import androidx.compose.material.icons.filled.Note
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.State
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.activity.ComponentActivity
import android.content.ClipData
import android.content.Intent
import com.hadithly.app.R
import com.hadithly.app.core.data.EnglishSearchResult
import com.hadithly.app.core.data.HadithRef
import com.hadithly.app.core.data.OutlineVolume
import com.hadithly.app.core.data.ReaderHadith
import com.hadithly.app.core.data.SavedEntry
import com.hadithly.app.core.data.ReaderPageResult
import com.hadithly.app.core.data.ReaderTranslation
import com.hadithly.app.core.data.ReadingPosition
import com.hadithly.app.core.data.ReaderTargetSource
import com.hadithly.app.core.data.ReadingWidthClass
import com.hadithly.app.core.data.TranslationFailure
import com.hadithly.app.core.preferences.LocaleFallback
import com.hadithly.app.core.preferences.ReaderPageTurn
import com.hadithly.app.core.preferences.PageDirection
import com.hadithly.app.core.preferences.ReaderPagingPolicy
import com.hadithly.app.core.preferences.ReaderPreferences
import com.hadithly.app.core.preferences.SwipeDirection
import com.hadithly.app.core.theme.LocalHadithlyColors
import com.hadithly.app.features.purchases.QuotaPaywallSheet
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.abs
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
    onOpenSaved: () -> Unit = {},
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
            pageStore = app.readerPages.also { it.beginReading() },
        )
    }
    val state by viewModel.state.collectAsStateWithLifecycle()
    val activeSession by com.clerk.api.Clerk.sessionFlow.collectAsStateWithLifecycle()
    LaunchedEffect(activeSession?.id) { viewModel.updateRecentPositionAccount(activeSession?.id); viewModel.resetTranslationRequestsForAccount() }
    DisposableEffect(viewModel) {
        viewModel.beginMeasurement()
        onDispose { viewModel.endMeasurement(); viewModel.saveCurrentProgress() }
    }
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
    val savedItems by viewModel.library.savedItems.collectAsStateWithLifecycle()
    val savedFolders by viewModel.library.folders.collectAsStateWithLifecycle()
    val preferences by app.preferences.preferences.collectAsStateWithLifecycle()
    val systemDark = androidx.compose.foundation.isSystemInDarkTheme()
    // R4: the reader honors the ReaderTheme preference; everything outside
    // keeps the app-wide dark canvas.
    val effectiveReaderTheme = if (preferences.usesSeparateReaderTheme) preferences.readerTheme else preferences.appTheme
    val colors = com.hadithly.app.core.theme.ReaderPalettes.resolved(effectiveReaderTheme, systemDark)

    var showContents by remember { mutableStateOf(false) }
    var showSettings by remember { mutableStateOf(false) }
    var showQuotaPaywall by remember { mutableStateOf(false) }
    var showPageJump by remember { mutableStateOf(false) }

    fun closeReader() {
        viewModel.closeReaderSession()
        onClose()
    }
    BackHandler(enabled = !showContents && !showSettings && !showPageJump, onBack = ::closeReader)

    // Round 7: the themed reader palette drives EVERY reader surface —
    // the page, the reader menu, and all sheets/dialogs presented from the
    // reader (contents, settings, bookmark, search, saved, paywall) — in
    // all four palettes, never the global app theme.
    CompositionLocalProvider(LocalHadithlyColors provides colors) {
        MaterialTheme(colorScheme = com.hadithly.app.core.theme.nativeColorScheme(colors, colors.background.luminance() < 0.5f)) {
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
                    arabicFontSize = preferences.arabicFontSize,
                    preferences = preferences,
                    onOpenContents = { showContents = true },
                    onOpenSettings = { showSettings = true },
                    onOpenPageJump = { showPageJump = true },
                    onShowPaywall = { showQuotaPaywall = true },
                    onClose = ::closeReader,
                    onOpenSaved = { viewModel.closeReaderSession(); onOpenSaved() },
                )
            }
        }

    if (showContents) {
        // Long list: settles expanded with the drag handle; sized to
        // content, never full-screen (no fillMaxHeight anywhere inside).
        val contentsSheetState = androidx.compose.material3.rememberModalBottomSheetState(
            skipPartiallyExpanded = false,
        )
        ModalBottomSheet(
            onDismissRequest = { showContents = false },
            sheetState = contentsSheetState,
            containerColor = colors.surface,
        ) {
            ContentsSheet(
                volumes = state.volumes,
                selectedVolumeId = state.selectedVolumeId,
                collectionName = collectionName,
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
        val settingsSheetState = androidx.compose.material3.rememberModalBottomSheetState(
            skipPartiallyExpanded = true,
        )
        ModalBottomSheet(
            onDismissRequest = { showSettings = false },
            sheetState = settingsSheetState,
            containerColor = colors.background,
        ) {
            SettingsSheet(
                preferences = preferences,
                language = state.language,
                onLanguage = { viewModel.setLanguage(it) },
                onArabicFontSize = app.preferences::setArabicFontSize,
                onTranslationFontSize = app.preferences::setTranslationFontSize,
                onTheme = { app.preferences.setSeparateReaderTheme(true); app.preferences.setReaderTheme(it) },
                onArabicFont = app.preferences::setArabicFont,
                onVisibility = { arabic: Boolean?, translation: Boolean? ->
                    app.preferences.setVisibility(arabic = arabic, translation = translation)
                },
                onDismiss = { showSettings = false },
            )
        }
    }

    if (showPageJump) {
        val initialJump = remember(showPageJump) { state.selectedVolumeId to state.pageIndex }
        ModalBottomSheet(
            onDismissRequest = { showPageJump = false },
            sheetState = androidx.compose.material3.rememberModalBottomSheetState(
                skipPartiallyExpanded = true,
            ),
            dragHandle = {
                Box(
                    Modifier
                        .padding(top = 8.dp, bottom = 6.dp)
                        .width(36.dp)
                        .height(4.dp)
                        .background(colors.textSecondary.copy(alpha = 0.4f), CircleShape),
                )
            },
            containerColor = colors.background,
        ) {
            val volumeId = initialJump.first
            if (volumeId != null) {
                ReaderJumpSheet(
                    viewModel = viewModel,
                    initialVolumeId = volumeId,
                    initialPageIndex = initialJump.second,
                    onDismiss = { showPageJump = false },
                )
            }
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
    }
}

@Composable
private fun LoadingView(collectionName: String) {
    com.hadithly.app.core.theme.ArticleLoadingView(nativeText("Opening %1\$s…", collectionName), Modifier.testTag("reader.loading"))
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
        Text(nativeText("Could not open this collection"), fontSize = 17.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)
        Text(
            text = runtimeNoticeText(message),
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
    arabicFontSize: Float,
    preferences: ReaderPreferences,
    onOpenContents: () -> Unit,
    onOpenSettings: () -> Unit,
    onOpenPageJump: () -> Unit,
    onShowPaywall: () -> Unit,
    onClose: () -> Unit,
    onOpenSaved: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    val experience = com.hadithly.app.HadithlyApplication.instance().readerExperience

    val androidView = LocalView.current
    var readerMenuExpanded by remember { mutableStateOf(false) }
    var showSearch by remember { mutableStateOf(false) }
    var showReaderSaved by remember { mutableStateOf(false) }
    val headerConfiguration = LocalConfiguration.current
    val headerDensity = LocalDensity.current
    var progressHeaderHeight by remember(headerConfiguration.locales[0].toLanguageTag(), headerConfiguration.screenWidthDp, headerDensity.fontScale) { mutableStateOf(56.dp) }
    var showBookmarkPlacement by remember { mutableStateOf(false) }
    val bookmarks by viewModel.library.bookmarks.collectAsStateWithLifecycle()
    val favorites by viewModel.library.favorites.collectAsStateWithLifecycle()
    val notes by viewModel.library.notes.collectAsStateWithLifecycle()
    val savedItems by viewModel.library.savedItems.collectAsStateWithLifecycle()
    val savedFolders by viewModel.library.folders.collectAsStateWithLifecycle()
    val coroutine = rememberCoroutineScope()
    val pagingPolicy = remember(preferences) { ReaderPagingPolicy(preferences) }

    /**
     * R6 round 3: any scroll lands focused with no haptic and closes the
     * reader menu — the menu never survives a focus change. Only the
     * tap-once toggle below plays the haptic.
     */
    fun collapseToFocusedAndCloseMenu() {
        readerMenuExpanded = false
        viewModel.collapseToFocused()
    }

    // Volume selects, chapter jumps, reference jumps, search and Saved
    // navigation all reset the page index: the menu never survives them.
    LaunchedEffect(state.pageIndex, state.selectedVolumeId) {
        readerMenuExpanded = false
    }

    val currentPage = viewModel.preparedCurrent()
    val previousPage = viewModel.preparedNeighbor(ReaderPageTurn.PREVIOUS)
    val nextPage = viewModel.preparedNeighbor(ReaderPageTurn.NEXT)
    val freshSlots = listOf(previousPage, currentPage, nextPage)
    var frozenSlots by remember { mutableStateOf<List<ReaderViewModel.PreparedPage?>?>(null) }
    val frozenCurrent = frozenSlots?.getOrNull(1)
    val frozenOriginIsCurrent = currentPage != null && frozenCurrent?.volume == currentPage.volume &&
        frozenCurrent.index == currentPage.index && frozenCurrent.page == currentPage.page && frozenCurrent.epoch == currentPage.epoch
    val slots = if (frozenOriginIsCurrent) frozenSlots ?: freshSlots else freshSlots
    val pagerState = rememberPagerState(initialPage = 1, pageCount = { 3 })
    val committedIdentity = currentPage?.let { listOf(it.volume, it.index, it.page, it.epoch) }
    val lastIdentity = remember { arrayOf(committedIdentity) }
    SideEffect {
        if (lastIdentity[0] != committedIdentity) {
            lastIdentity[0] = committedIdentity
            frozenSlots = null
            pagerState.requestScrollToPage(1)
        }
    }
    val currentFirstHadithId = state.pages.getOrNull(state.pageIndex)?.items?.firstOrNull()?._id
    LaunchedEffect(currentFirstHadithId) {
        if (currentFirstHadithId != null) viewModel.saveCurrentProgress()
    }
    LaunchedEffect(pagerState) {
        snapshotFlow { pagerState.isScrollInProgress to pagerState.settledPage }
            .distinctUntilChanged().collect { (scrolling, slot) ->
                if (!scrolling && slot != 1) {
                    val committed = frozenSlots?.getOrNull(slot)?.let { viewModel.commitPreparedNeighbor(it) } == true
                    if (!committed) {
                        frozenSlots = null
                        pagerState.requestScrollToPage(1)
                    }
                } else if (!scrolling && slot == 1) {
                    frozenSlots = null
                }
            }
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
    val reduceMotion = !com.hadithly.app.core.theme.rememberMotionAllowed()

    // The page remains full-bleed while native window insets animate the
    // status bar with focused mode. Reader controls animate independently.
    // Page content never moves or re-composes layout.
    val focused = !state.chromeVisible
    val activity = remember(androidView) {
        generateSequence(androidView.context) { context ->
            (context as? android.content.ContextWrapper)?.baseContext
        }.filterIsInstance<ComponentActivity>().firstOrNull()
    }
    DisposableEffect(activity) {
        onDispose {
            activity?.window?.let { window ->
                WindowInsetsControllerCompat(window, androidView)
                    .show(WindowInsetsCompat.Type.statusBars())
            }
        }
    }
    LaunchedEffect(activity, focused, colors.background) {
        activity?.window?.let { window ->
            val controller = WindowInsetsControllerCompat(window, androidView)
            controller.isAppearanceLightStatusBars = colors.background.luminance() > 0.5f
            controller.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            if (focused) controller.hide(WindowInsetsCompat.Type.statusBars())
            else controller.show(WindowInsetsCompat.Type.statusBars())
        }
    }
    val chromeAnim: FiniteAnimationSpec<Float> =
        if (reduceMotion) snap() else tween(200)
    // Unfocused chrome (pills row, bottom chrome, corner label): visible in
    // unfocused mode — shrinks while fading out, grows while fading in.
    val chromeAlpha by animateFloatAsState(
        targetValue = if (state.chromeVisible) 1f else 0f,
        animationSpec = chromeAnim,
        label = "readerChromeAlpha",
    )
    val chromeScale by animateFloatAsState(
        targetValue = if (state.chromeVisible) 1f else 0.96f,
        animationSpec = chromeAnim,
        label = "readerChromeScale",
    )

    fun turnPage(turn: ReaderPageTurn): Boolean {
        val pill = if (turn == ReaderPageTurn.PREVIOUS) viewModel.pagePills().previous else viewModel.pagePills().next
        if (pill == null) return false
        val slot = if (turn == ReaderPageTurn.PREVIOUS) 0 else 2
        if (slots[slot] == null) {
            viewModel.followPill(pill)
        } else {
            if (frozenSlots == null) frozenSlots = slots
            if (reduceMotion) coroutine.launch { pagerState.scrollToPage(slot) }
            else coroutine.launch { pagerState.animateScrollToPage(slot) }
        }
        return true
    }

    val previousPageAction = nativeText("Previous page")
    val nextPageAction = nativeText("Next page")
    val controlsAction = nativeText(if (state.chromeVisible) "Hide reader controls" else "Show reader controls")
    val accessibilityActions = buildList {
        add(
            CustomAccessibilityAction(
                controlsAction,
                action = {
                    viewModel.toggleChrome()
                    true
                },
            ),
        )
        if (viewModel.pagePills().previous != null) {
            add(CustomAccessibilityAction(previousPageAction) { turnPage(ReaderPageTurn.PREVIOUS) })
        }
        if (viewModel.pagePills().next != null) {
            add(CustomAccessibilityAction(nextPageAction) { turnPage(ReaderPageTurn.NEXT) })
        }
    }

    // Intra-page scroll fraction drives the dynamic page bars (item 6).
    // Reset on every page turn; ReaderPage reports (page, fraction) pairs
    // so a stale late emission cannot move another page's bar.
    val pageScroll = remember { mutableStateOf(0 to 0f) }
    LaunchedEffect(state.selectedVolumeId, state.pageIndex) {
        pageScroll.value = state.pageIndex to 0f
    }

    val totalPages = viewModel.totalPages()
    val volumeFraction = volumeProgressFraction(
        volumeCount = state.volumes.size,
        selectedIndex = state.volumes.indexOfFirst { it.volumeId == state.selectedVolumeId },
    )
    // Unfocused pills (Sajda `208 page` + `11 juz` style): the Page pill
    // fills with the intra-page scroll fraction; the Volume pill fills with
    // the current page fraction within the volume (static outline fraction
    // only until the backend reports a page total).
    val unfocusedVolumeNumber = state.volumes
        .firstOrNull { it.volumeId == state.selectedVolumeId }
        ?.let(::volumeHeaderNumber)
        ?: state.volumes
            .indexOfFirst { it.volumeId == state.selectedVolumeId }
            .takeIf { it >= 0 }
            ?.plus(1)

    Box(
        modifier = Modifier
            .fillMaxSize()
            .semantics { customActions = accessibilityActions },
    ) {
        DirectionAwareHorizontalPager(
            state = pagerState,
            policy = pagingPolicy,
            pageKey = { slot -> slots[slot]?.let { context ->
                "${context.volume}:${context.index}:${context.page.pageKey}:${context.page.contentVersion}:${context.page.paginationVersion}:${context.page.items.joinToString("|") { it.internalId }}"
            } ?: "empty-slot-$slot" },
            isMissingPage = { slot -> slots.getOrNull(slot) == null },
            onMissingPage = { slot -> turnPage(if (slot == 0) ReaderPageTurn.PREVIOUS else ReaderPageTurn.NEXT) },
            captureGestureValidity = {
                val origin = viewModel.preparedCurrent()
                val pills = viewModel.pagePills()
                val valid: () -> Boolean = { viewModel.isPreparedOriginCurrent(origin) && viewModel.pagePills() == pills }
                valid
            },
            onUserDragStart = {
                if (frozenSlots == null) frozenSlots = slots
                viewModel.cancelPendingTurn()
                collapseToFocusedAndCloseMenu()
            },
            modifier = Modifier.fillMaxSize(),
        ) { slot ->
            val context = slots[slot]
            if (context == null) {
                Box(Modifier.fillMaxSize()) {
                    if (slot == 1) com.hadithly.app.core.theme.ArticleLoadingView(nativeText("Loading page"))
                }
            } else {
                val active = state.selectedVolumeId == context.volume && state.pageIndex == context.index &&
                    state.pages.getOrNull(state.pageIndex) == context.page
                val pages = (if (state.selectedVolumeId == context.volume) state.pages else emptyList()).toMutableList().apply {
                    while (size <= context.index) add(ReaderPageResult())
                    this[context.index] = context.page
                }
                val pageState = state.copy(selectedVolumeId = context.volume, pageIndex = context.index, pages = pages,
                    translations = if (state.selectedVolumeId == context.volume) state.translations else emptyMap(),
                    translationAllowances = if (state.selectedVolumeId == context.volume) state.translationAllowances else emptyMap(),
                    verticalLanding = if (active) state.verticalLanding else context.landing)
                val pagePillState = pagePillsForPage(context.index, pages, state.volumes, context.volume)
                ReaderPage(
                    viewModel = viewModel,
                    state = pageState,
                    hadiths = context.page.items,
                    arabicFontSize = arabicFontSize,
                    preferences = preferences,
                    pagingPolicy = pagingPolicy,
                    pageIndex = context.index,
                    isActivePage = active,
                    pillState = pagePillState,
                    verticalLanding = if (active) state.verticalLanding else context.landing,
                    topContentPadding = progressHeaderHeight,
                    isSentinel = false,
                    chromeAlpha = chromeAlpha,
                    chromeScale = chromeScale,
                    onFollowPill = { if (active) turnPage(it.turn) },
                    onTap = {
                        if (active) {
                            ReaderHaptics.perform(androidView, ReaderHapticKind.TAP_TOGGLE)
                            viewModel.toggleChrome()
                        }
                    },
                    onUserScroll = { if (active) collapseToFocusedAndCloseMenu() },
                    onPageScrollFraction = { page, fraction -> if (active) pageScroll.value = page to fraction },
                    onShowPaywall = { if (active) onShowPaywall() },
                )
            }
        }

        state.pendingTurn?.let { pending ->
            Surface(
                modifier = Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top = 56.dp)
                    .testTag("reader.pendingTurn")
                    .semantics { liveRegion = LiveRegionMode.Polite },
                shape = RoundedCornerShape(16.dp), tonalElevation = 3.dp,
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(horizontal = 12.dp)) {
                    Text(nativeText(if (pending.status == ReaderViewModel.TurnStatus.LOADING) "Loading page" else "Could not load page"))
                    if (pending.status == ReaderViewModel.TurnStatus.FAILED) {
                        TextButton(onClick = viewModel::retryPendingTurn) { Text(nativeText("Retry")) }
                    }
                    TextButton(onClick = viewModel::cancelPendingTurn) { Text(nativeText("Cancel")) }
                }
            }
        }

        if (!showReaderSaved) {
            Column(
                modifier = Modifier.align(Alignment.BottomCenter)
                    .navigationBarsPadding()
                    .padding(horizontal = 20.dp)
                    .padding(bottom = if (state.chromeVisible) 96.dp else 20.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                if (!readerMenuExpanded) ReaderActionHint(experience, Modifier.fillMaxWidth())
                com.hadithly.app.features.saved.SavedUndoBanner(
                    testTag = "reader.undoBanner",
                    controller = viewModel.library.undo,
                )
            }
        }

        ReaderProgressHUD(pageScroll, state.pageIndex, totalPages, unfocusedVolumeNumber, volumeFraction,
            state.chromeVisible, reduceMotion, onHeaderHeight = { progressHeaderHeight = maxOf(progressHeaderHeight, it + 12.dp) },
            onOpenJump = if (currentPage != null) onOpenPageJump else null)

        AnimatedVisibility(
            visible = state.chromeVisible,
            enter = fadeIn(chromeAnim) + scaleIn(chromeAnim, initialScale = 0.96f),
            exit = fadeOut(chromeAnim) + scaleOut(chromeAnim, targetScale = 0.96f),
            modifier = Modifier.align(Alignment.BottomCenter),
        ) {
            Column(
                horizontalAlignment = Alignment.End,
                modifier = Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 24.dp, vertical = 16.dp),
            ) {
                if (readerMenuExpanded) {
                    val positioned = viewModel.positionedHadith()
                    ReaderMenuStack(
                        positionedReference = positioned?.referenceDisplay,
                        isPositionedBookmarked = positioned?.let(viewModel::isBookmarked) == true,
                        onContents = {
                            viewModel.cancelPendingTurn()
                            readerMenuExpanded = false
                            onOpenContents()
                        },
                        onSaved = {
                            readerMenuExpanded = false
                            viewModel.cancelPendingTurn()
                            showReaderSaved = true
                        },
                        onSettings = {
                            readerMenuExpanded = false
                            onOpenSettings()
                        },
                        onBookmark = {
                            // Round 8: the menu closes before the centered
                            // placement dialog presents — a single dialog over
                            // a single scrim, never menu cards ghosting
                            // behind the card.
                            readerMenuExpanded = false
                            showBookmarkPlacement = true
                        },
                        onSearch = {
                            viewModel.cancelPendingTurn()
                            readerMenuExpanded = false
                            showSearch = true
                        },
                    )
                    Spacer(Modifier.height(12.dp))
                }
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    ReaderChromeCircle(Icons.AutoMirrored.Filled.ArrowBack, "Back", onClose)
                    ReaderChromeCircle(
                        if (readerMenuExpanded) Icons.Filled.Close else Icons.AutoMirrored.Filled.List,
                        if (readerMenuExpanded) "Close reader menu" else "Open reader menu",
                    ) {
                        ReaderHaptics.perform(androidView, ReaderHapticKind.MENU_OPEN_CLOSE)
                        readerMenuExpanded = !readerMenuExpanded
                    }
                }
            }
        }

        if (showBookmarkPlacement) {
            // Round 7: bookmark placement is a centered dialog (dimmed
            // scrim, centered card), not a bottom sheet. Content, actions,
            // and test tags are unchanged.
            val placementTargets = bookmarkPlacementTargets(
                pageHadiths = viewModel.currentPageHadiths(),
                positioned = viewModel.positionedHadith(),
            )
            fun choosePlacement(hadith: ReaderHadith?) {
                if (hadith != null) {
                    val adding = !viewModel.isBookmarked(hadith)
                    viewModel.toggleBookmark(hadith)
                    if (adding) ReaderHaptics.perform(androidView, ReaderHapticKind.BOOKMARK_FAVORITE_ADD)
                }
                showBookmarkPlacement = false
                readerMenuExpanded = false
            }
                BookmarkPlacementSheet(
                    targets = placementTargets,
                    isBookmarked = viewModel::isBookmarked,
                    onChoose = { choosePlacement(it) },
                    onDismiss = { showBookmarkPlacement = false },
                )
        }

        if (showSearch) {
            // Round 6: default half/full behavior (no forced expansion);
            // the inner column fills the allotted height instead.
            ModalBottomSheet(
                onDismissRequest = { showSearch = false },
                containerColor = colors.surface,
            ) {
                ReaderSearchSheet(
                    onDismiss = { showSearch = false },
                    search = { query -> viewModel.searchEnglish(query) },
                    onNavigate = { result ->
                        if (viewModel.navigateToSearchResult(result)) showSearch = false
                    },
                )
            }
        }

        if (showReaderSaved) {
            // Round 6: default half/full behavior (no forced expansion);
            // the inner column fills the allotted height instead.
            ModalBottomSheet(
                onDismissRequest = { showReaderSaved = false },
                containerColor = colors.surface,
            ) {
                ReaderSavedSheet(
                    onDismiss = { showReaderSaved = false },
                    items = savedItems,
                    folders = savedFolders,
                    library = viewModel.library,
                    onOpen = { ref ->
                        showReaderSaved = false
                        viewModel.navigateToSaved(ref)
                    },
                    onEdit = {
                        showReaderSaved = false
                        onOpenSaved()
                    },
                )
            }
        }

    }
}

@Composable
internal fun ReaderActionHint(experience: com.hadithly.app.core.preferences.ReaderExperiencePreferences, modifier: Modifier = Modifier) {
    val colors = LocalHadithlyColors.current
    val visible by experience.showsActionHint.collectAsStateWithLifecycle()
    LaunchedEffect(experience) {
        experience.offerActionHint()
        if (experience.showsActionHint.value) {
            try { kotlinx.coroutines.delay(7000) }
            finally { experience.dismissActionHint() }
        }
    }
    AnimatedVisibility(
        visible = visible,
        enter = fadeIn(tween(180)) + androidx.compose.animation.slideInVertically(tween(180)) { it / 3 },
        exit = fadeOut(tween(150)) + androidx.compose.animation.slideOutVertically(tween(150)) { it / 3 },
    ) {
        Surface(
            shape = RoundedCornerShape(16.dp),
            color = colors.surface.copy(alpha = 0.92f),
            contentColor = colors.textPrimary,
            tonalElevation = 2.dp,
            shadowElevation = 3.dp,
            border = androidx.compose.foundation.BorderStroke(0.5.dp, colors.divider.copy(alpha = 0.65f)),
            modifier = modifier.testTag("reader.actionHint"),
        ) {
            Row(Modifier.padding(start = 16.dp, end = 6.dp, top = 4.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(nativeText("Touch and hold a hadith to bookmark, add a note or share."), color = colors.textPrimary, fontSize = 12.sp, modifier = Modifier.weight(1f))
                IconButton(onClick = experience::dismissActionHint) { Icon(Icons.Filled.Close, nativeText("Dismiss hint"), tint = colors.textSecondary) }
            }
        }
    }
}

@Composable
internal fun ReaderChromeCircle(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit) {
    val colors = LocalHadithlyColors.current
    val accessibleLabel = nativeText(label)
    Surface(
        onClick = onClick,
        shape = CircleShape,
        color = colors.surfaceElevated.copy(alpha = .96f),
        contentColor = colors.textPrimary,
        tonalElevation = 3.dp,
        shadowElevation = 3.dp,
        border = androidx.compose.foundation.BorderStroke(.5.dp, colors.divider.copy(alpha = .65f)),
        modifier = Modifier.size(52.dp).semantics { contentDescription = accessibleLabel },
    ) {
        Box(contentAlignment = Alignment.Center) { Icon(icon, null, modifier = Modifier.size(24.dp)) }
    }
}

/** Observe per-frame scroll only in the HUD, outside the pager's composition scope. */
@Composable
internal fun ReaderProgressHUD(
    pageScroll: State<Pair<Int, Float>>,
    pageIndex: Int,
    totalPages: Int?,
    unfocusedVolumeNumber: Int?,
    volumeFraction: Double?,
    chromeVisible: Boolean,
    reduceMotion: Boolean,
    onHeaderHeight: (androidx.compose.ui.unit.Dp) -> Unit = {},
    onOpenJump: (() -> Unit)? = null,
) {
    val density = LocalDensity.current
    val focused = !chromeVisible
    val chromeAnim: FiniteAnimationSpec<Float> = if (reduceMotion) snap() else tween(200)
    val intraPageFraction = if (pageScroll.value.first == pageIndex) pageScroll.value.second else 0f
    val dynamicPageFraction = focusedProgressFraction(
        pageIndex = pageIndex,
        totalPages = totalPages,
        intraPageFraction = intraPageFraction,
    )
    val unfocusedPageFill = pagePillFillFraction(intraPageFraction)
    val unfocusedVolumeFill = (
        volumePillFillFraction(pageIndex, totalPages, intraPageFraction)
            ?: volumeFraction ?: 0.0
        )
    Box(Modifier.fillMaxSize()) {
        // Round 7, focused: ONE 4dp narrow dynamic PAGE bar, ~1/4 width,
        // centered near the top safe area. ALWAYS rendered
        // in focused mode in every palette — the null-total fallback keeps
        // the track visible instead of hiding the capsule. Fades + grows in
        // with the toggle; the page underneath never moves.
        AnimatedVisibility(
            visible = focused,
            enter = fadeIn(chromeAnim) + scaleIn(chromeAnim, initialScale = 0.96f),
            exit = fadeOut(chromeAnim) + scaleOut(chromeAnim, targetScale = 0.96f),
            modifier = Modifier.align(Alignment.TopCenter),
        ) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.fillMaxWidth().statusBarsPadding(),
            ) {
                ReaderProgressCapsule(
                    fraction = dynamicPageFraction ?: 0.0,
                    thickness = 4.dp,
                    testTag = "reader.focusedPageBar",
                    reduceMotion = reduceMotion,
                    modifier = Modifier.fillMaxWidth(0.25f).padding(top = 8.dp),
                )
            }
        }

        // Item 6, unfocused: TWO pills side by side (Sajda style: bold
        // number + lighter suffix) — Page pill filled by intra-page scroll,
        // Volume pill filled by the page fraction within the volume. The
        // status bar is visible here, so the row sits below it. Fades +
        // scales with the toggle; the page underneath never moves.
        val pillAlpha by animateFloatAsState(if (chromeVisible) 1f else 0f, chromeAnim, label = "progressPillsVisibility")
        Box(Modifier.align(Alignment.TopCenter).graphicsLayer {
            alpha = pillAlpha
            scaleX = 0.96f + 0.04f * pillAlpha
            scaleY = 0.96f + 0.04f * pillAlpha
        }.then(if (chromeVisible) Modifier else Modifier.clearAndSetSemantics {})) {
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                maxItemsInEachRow = 2,
                modifier = Modifier.fillMaxWidth()
                    .onSizeChanged { onHeaderHeight(with(density) { it.height.toDp() }) }
                    .statusBarsPadding().padding(start = 20.dp, end = 20.dp, top = 6.dp),
            ) {
                ReaderProgressPill(
                    number = java.text.NumberFormat.getIntegerInstance(LocalConfiguration.current.locales[0]).format(pageIndex + 1),
                    suffix = nativeText("page"),
                    accessibilityLabel = nativeText("Page %1$@", java.text.NumberFormat.getIntegerInstance(LocalConfiguration.current.locales[0]).format(pageIndex + 1)),
                    fraction = unfocusedPageFill.toDouble(),
                    testTag = "reader.unfocusedPageBar",
                    reduceMotion = reduceMotion,
                    onClick = onOpenJump,
                )
                if (unfocusedVolumeNumber != null) {
                    ReaderProgressPill(
                        number = java.text.NumberFormat.getIntegerInstance(LocalConfiguration.current.locales[0]).format(unfocusedVolumeNumber),
                        suffix = stringResource(R.string.reader_volume_pill_suffix),
                        accessibilityLabel = nativeText("Volume %lld", unfocusedVolumeNumber),
                        fraction = unfocusedVolumeFill,
                        testTag = "reader.unfocusedVolumeBar",
                        reduceMotion = reduceMotion,
                        onClick = onOpenJump,
                    )
                }
            }
        }

    }
}

@Composable
internal fun ReaderMenuStack(
    positionedReference: String?,
    isPositionedBookmarked: Boolean,
    onContents: () -> Unit,
    onSaved: () -> Unit,
    onSettings: () -> Unit,
    onBookmark: () -> Unit,
    onSearch: () -> Unit,
) {
    // Sajda `menu open` anchoring: inset from the leading edge, roughly the
    // trailing two-thirds, tighter rhythm than the old full-width cards.
    val colors = LocalHadithlyColors.current
    val view = LocalView.current
    fun tapped(item: () -> Unit) {
        ReaderHaptics.perform(view, ReaderHapticKind.MENU_ITEM)
        item()
    }
    BoxWithConstraints {
    Surface(
        shape = RoundedCornerShape(24.dp),
        color = colors.surface.copy(alpha = 0.36f),
        contentColor = colors.textPrimary,
        tonalElevation = 2.dp,
        shadowElevation = 4.dp,
        border = androidx.compose.foundation.BorderStroke(0.5.dp, colors.divider.copy(alpha = 0.62f)),
        modifier = Modifier.fillMaxWidth(0.66f).heightIn(max = minOf(maxHeight, LocalConfiguration.current.screenHeightDp.dp)).testTag("reader.menu"),
    ) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(4.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            ReaderMenuCard(
                title = "Contents",
                subtitle = "Volumes and chapters",
                icon = Icons.AutoMirrored.Filled.List,
                onClick = { tapped(onContents) },
                testTag = "reader.menu.contents",
            )
            ReaderMenuCard(
                title = "Bookmarks & Notes",
                subtitle = "Your private saved reading",
                icon = Icons.Filled.Bookmark,
                onClick = { tapped(onSaved) },
                testTag = "reader.menu.saved",
            )
            ReaderMenuCard(
                title = "Settings",
                subtitle = "Type, appearance, and text",
                icon = Icons.Filled.FormatSize,
                onClick = { tapped(onSettings) },
                testTag = "reader.menu.settings",
            )
            // Bottom row: icon-only, equal size. Active bookmark colors only
            // the icon, keeping the background neutral in every palette.
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                ReaderMenuIconButton(
                    icon = if (isPositionedBookmarked) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder,
                    contentDescription = if (isPositionedBookmarked) nativeText("Remove bookmark for positioned hadith") else if (positionedReference != null) nativeText("Bookmark %@", positionedReference) else nativeText("Bookmark current hadith"),
                    iconTint = if (isPositionedBookmarked) colors.bookmark else null,
                    onClick = { tapped(onBookmark) },
                    modifier = Modifier.weight(1f).height(56.dp),
                    testTag = "reader.menu.bookmark",
                )
                ReaderMenuIconButton(
                    icon = Icons.Filled.Search,
                    contentDescription = nativeText("Search"),
                    onClick = { tapped(onSearch) },
                    modifier = Modifier.weight(1f).height(56.dp),
                    testTag = "reader.menu.search",
                )
            }
        }
    }
}
}

@Composable
private fun ReaderMenuIconButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    contentDescription: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    iconTint: androidx.compose.ui.graphics.Color? = null,
    testTag: String? = null,
) {
    val colors = LocalHadithlyColors.current
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(18.dp),
        color = colors.surface.copy(alpha = 0.88f),
        contentColor = colors.textPrimary,
        tonalElevation = 2.dp,
        shadowElevation = 3.dp,
        border = androidx.compose.foundation.BorderStroke(0.5.dp, colors.divider.copy(alpha = 0.6f)),
        modifier = modifier.semantics { this.contentDescription = contentDescription }
            .then(if (testTag != null) Modifier.testTag(testTag) else Modifier),
    ) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = iconTint ?: colors.textSecondary, modifier = Modifier.size(22.dp))
        }
    }
}

@Composable
private fun ReaderMenuCard(
    title: String,
    subtitle: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    iconTint: androidx.compose.ui.graphics.Color? = null,
    testTag: String? = null,
) {
    val colors = LocalHadithlyColors.current
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(18.dp),
        color = colors.surface.copy(alpha = 0.88f),
        contentColor = colors.textPrimary,
        tonalElevation = 2.dp,
        shadowElevation = 3.dp,
        border = androidx.compose.foundation.BorderStroke(0.5.dp, colors.divider.copy(alpha = 0.6f)),
        modifier = modifier.fillMaxWidth()
            .then(if (testTag != null) Modifier.testTag(testTag) else Modifier),
    ) {
        Row(Modifier.padding(horizontal = 14.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(nativeText(title), fontSize = 16.sp, fontWeight = FontWeight.SemiBold,
                    color = colors.textPrimary)
                Text(nativeText(subtitle), fontSize = 12.sp, color = colors.textSecondary)
            }
            Icon(icon, null, tint = iconTint ?: colors.textSecondary, modifier = Modifier.size(22.dp))
        }
    }
}

@Composable
internal fun SynchronizeReaderPager(state: PagerState, pageIndex: Int, pageCount: Int) {
    LaunchedEffect(pageIndex, pageCount) {
        val draggingFromModelPage = state.isScrollInProgress && state.settledPage == pageIndex
        if (!draggingFromModelPage && pageIndex in 0 until maxOf(pageCount, 1) && state.currentPage != pageIndex) {
            state.scrollToPage(pageIndex)
        }
    }
}

@Composable
internal fun DirectionAwareHorizontalPager(
    state: PagerState,
    policy: ReaderPagingPolicy,
    onOutwardEdgeTurn: ((ReaderPageTurn) -> Boolean)? = null,
    pageKey: ((Int) -> Any)? = null,
    isMissingPage: (Int) -> Boolean = { false },
    onMissingPage: (Int) -> Unit = {},
    captureGestureValidity: () -> (() -> Boolean) = { { true } },
    onUserDragStart: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
    content: @Composable PagerScope.(page: Int) -> Unit,
) {
    // A user drag collapses the reader to focused (no haptic) and closes
    // the menu. DragInteraction.Start fires only for real drags —
    // programmatic turns and cancel-backs never emit it.
    LaunchedEffect(state, onUserDragStart) {
        state.interactionSource.interactions.collect { interaction ->
            if (interaction is DragInteraction.Start) onUserDragStart?.invoke()
        }
    }
    val missingPage = rememberUpdatedState(isMissingPage)
    val requestMissingPage = rememberUpdatedState(onMissingPage)
    val captureValidity = rememberUpdatedState(captureGestureValidity)
    val missingGesture = remember(state, policy) { MissingPageGesture() }
    val missingConnection = remember(state, policy) {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                if (source != NestedScrollSource.UserInput || available.x == 0f) return Offset.Zero
                if (!missingGesture.isValid()) return Offset(available.x, 0f)
                val logicalDirection = if (policy.reverseLayout) 1f else -1f
                val pageExtent = (state.layoutInfo.pageSize + state.layoutInfo.pageSpacing).toFloat()
                if (pageExtent <= 0f) return Offset.Zero
                val position = (state.currentPage - missingGesture.originSlot + state.currentPageOffsetFraction) * pageExtent
                val delta = available.x * logicalDirection
                val destination = position + delta
                val turn = if (destination > 0f) ReaderPageTurn.NEXT else if (destination < 0f) ReaderPageTurn.PREVIOUS else return Offset.Zero
                val target = policy.destination(missingGesture.originSlot, state.pageCount, turn) ?: return Offset.Zero
                if (!missingPage.value(target)) return Offset.Zero
                val allowed = if (position * delta < 0f) -position else 0f
                val consumed = delta - allowed
                if (consumed == 0f) return Offset.Zero
                missingGesture.blockedTarget = target
                return Offset(consumed * logicalDirection, 0f)
            }

            override suspend fun onPreFling(available: Velocity): Velocity {
                if (!missingGesture.isValid()) return Velocity(available.x, 0f)
                val direction = if (available.x < 0f) SwipeDirection.LEFT else SwipeDirection.RIGHT
                val target = policy.destination(missingGesture.originSlot, state.pageCount, policy.turn(direction))
                return if (available.x != 0f && target != null && missingPage.value(target)) Velocity(available.x, 0f) else Velocity.Zero
            }
        }
    }
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
        HorizontalPager(
            state = state,
            key = pageKey,
            reverseLayout = policy.reverseLayout,
            // Neighbors stay rendered during drags so a mid-gesture
            // cancel-back never flashes an empty page.
            beyondViewportPageCount = 1,
            modifier = modifier.missingPageSwipe(state, policy, missingGesture, requestMissingPage, captureValidity)
                .nestedScroll(missingConnection)
                .edgeVolumeSwipe(state, policy, onOutwardEdgeTurn),
            pageContent = content,
        )
    }
}

private class MissingPageGesture {
    var blockedTarget: Int? = null
    var originSlot = 0
    var isValid: () -> Boolean = { false }
    fun begin(slot: Int, validity: () -> Boolean) { blockedTarget = null; originSlot = slot; isValid = validity }
}

private fun Modifier.missingPageSwipe(
    state: PagerState,
    policy: ReaderPagingPolicy,
    gesture: MissingPageGesture,
    onMissingPage: State<(Int) -> Unit>,
    captureValidity: State<() -> (() -> Boolean)>,
): Modifier = pointerInput(state, policy, gesture) {
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
        gesture.begin(state.settledPage, captureValidity.value())
        var deltaX = 0f
        do {
            val event = awaitPointerEvent(PointerEventPass.Initial)
            val change = event.changes.firstOrNull { it.id == down.id } ?: break
            deltaX = change.position.x - down.position.x
        } while (change.pressed)
        val direction = if (deltaX < 0f) SwipeDirection.LEFT else SwipeDirection.RIGHT
        val target = policy.destination(gesture.originSlot, state.pageCount, policy.turn(direction))
        if (gesture.isValid() && target != null && target == gesture.blockedTarget && kotlin.math.abs(deltaX) >= 96f) onMissingPage.value(target)
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

/**
 * Round 7 tap-vs-drag disambiguation for the page-level chrome toggle.
 * Fires [onConfirmedTap] only for a confirmed tap: every pointer up,
 * within the platform touch slop of the down position, and within
 * [CONFIRMED_TAP_TIMEOUT_MILLIS]. A touch that becomes a drag/swipe/scroll
 * is consumed by the pager/list (no up is ever observed) or exceeds the
 * slop, so it never toggles chrome and never fires haptics. The tick lives
 * with the toggle at the call site — confirmed taps only.
 */
private fun Modifier.confirmedTapGesture(onConfirmedTap: () -> Unit): Modifier =
    pointerInput(onConfirmedTap) {
        awaitEachGesture {
            val down = awaitFirstDown()
            val downTime = android.os.SystemClock.uptimeMillis()
            val up = waitForUpOrCancellation()
            if (up != null) {
                val duration = android.os.SystemClock.uptimeMillis() - downTime
                if (
                    isConfirmedTap(
                        downX = down.position.x,
                        downY = down.position.y,
                        upX = up.position.x,
                        upY = up.position.y,
                        durationMillis = duration,
                        slopPx = viewConfiguration.touchSlop,
                    )
                ) {
                    onConfirmedTap()
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
    isActivePage: Boolean,
    pillState: ReaderPagePills.State,
    verticalLanding: ReaderVerticalLandingRequest?,
    isSentinel: Boolean,
    topContentPadding: androidx.compose.ui.unit.Dp,
    // Round 7: the animated chrome fade+scale driven in ReadingView. The
    // inline corner label rides these through graphicsLayer — always
    // composed, so page layout never moves.
    chromeAlpha: Float = 1f,
    chromeScale: Float = 1f,
    onFollowPill: (ReaderPagePills.Pill) -> Unit,
    onTap: () -> Unit,
    onUserScroll: () -> Unit,
    onPageScrollFraction: (Int, Float) -> Unit,
    onShowPaywall: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    val resContext = androidx.compose.ui.platform.LocalResources.current
    var sourceHadith by remember { mutableStateOf<ReaderHadith?>(null) }
    var noteTarget by remember { mutableStateOf<ReaderHadith?>(null) }
    var submissionTarget by remember { mutableStateOf<Pair<ReaderHadith, ReaderTranslation?>?>(null) }
    var reportTarget by remember { mutableStateOf<Pair<ReaderHadith, ReaderTranslation>?>(null) }
    var initialLanding by remember { mutableStateOf(
        if (isActivePage && verticalLanding == null) viewModel.recentLandingForPage(pageIndex) else null
    ) }
    val landing = (verticalLanding ?: initialLanding)?.takeIf {
        it.page == ReaderVerticalLandingPage(state.selectedVolumeId.orEmpty(), pageIndex)
    }
    val listState = rememberLazyListState()
    var appliedLandingToken by remember { mutableStateOf<Int?>(null) }
    var appliedLandingLayout by remember { mutableStateOf<ReaderViewportLayout?>(null) }
    val density = LocalDensity.current
    val viewportSize by remember { derivedStateOf { listState.layoutInfo.viewportSize } }
    val selectedLayoutVolume = remember(state.volumes, state.selectedVolumeId) {
        state.volumes.firstOrNull { it.volumeId == state.selectedVolumeId }
    }
    val layoutTranslations = remember(hadiths, state.translations) { hadiths.map { state.translations[it.internalId] } }
    val layoutAllowances = remember(hadiths, state.translationAllowances) { hadiths.map { state.translationAllowances[it.internalId] } }
    val configuration = androidx.compose.ui.platform.LocalConfiguration.current
    val layoutProjection = preferences.layoutProjection + "|${preferences.uiLocale}|${configuration.locales}|${state.language}|${density.density}|${density.fontScale}|$topContentPadding"
    fun viewportLayout() = ReaderViewportLayout(layoutProjection, listState.layoutInfo.viewportSize.width,
        listState.layoutInfo.viewportSize.height, hadiths, selectedLayoutVolume, layoutTranslations, layoutAllowances)
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
    val arabicOnly = preferences.arabicVisible && !preferences.translationVisible
    val localizedVolumeName: (Int) -> String = { number ->
        resContext.getString(R.string.reader_volume_title, number)
    }
    val context = androidx.compose.ui.platform.LocalContext.current
    val translationResources = remember(context, preferences.translationLocale) {
        val configuration = android.content.res.Configuration(context.resources.configuration).apply {
            setLocale(java.util.Locale.forLanguageTag(preferences.translationLocale.replace('_', '-')))
        }
        context.createConfigurationContext(configuration).resources
    }
    val cornerTitle: String? = selectedVolume?.title?.let { title ->
        volumeCornerTitle(title) { number ->
            val resources = if (preferences.translationVisible) translationResources else resContext
            resources.getString(R.string.reader_volume_title, number)
        }
    }
    // Round 8: the range resolves from already-cached synchronous sources
    // (the outline counts plus the loaded pages list) and latches per
    // volume the first time it computes — a later prefetch append can never
    // flip `Title: a–b` back to `Title` for a frame. Single-line slot, so
    // even the first arrival never changes height.
    val latchedRanges = remember { mutableMapOf<String, Pair<Int, Int>>() }
    val freshRange = remember(state.volumes, state.selectedVolumeId, state.pages) {
        val volumeId = state.selectedVolumeId ?: return@remember null
        if (!viewModel.hasKnownVolumeRange(volumeId) && !ReaderViewModel.isVolumeFullyCached(state.pages)) return@remember null
        ReaderViewModel.volumeHadithRange(state.volumes, volumeId)
    }
    if (freshRange != null && state.selectedVolumeId != null) {
        latchedRanges[state.selectedVolumeId] = freshRange
    }
    val cornerRange = latchedRanges[state.selectedVolumeId] ?: freshRange
    // Volume start: the pages list resets on every volume select/jump, so
    // page index 0 with content is the volume's first page. The header slot
    // itself is emitted synchronously (see below); only the header CONTENT
    // waits on the volume resolving.
    // R6 fix round: the big centered title is the ACTUAL volume name
    // (firstChapterTitle, else first chapter, else outline title). The
    // localized `Volume N` survives only as a small quiet eyebrow above it;
    // corner label and volume-edge pills keep `Volume N` untouched.
    val volumeStartTitle = selectedVolume?.let { volume ->
        val header = volumeHeaderTitle(volume)
        if (header == volume.title) {
            volumeTitleForDisplay(header, arabicOnly, localizedVolumeName)
        } else {
            header
        }
    }
    val volumeStartEyebrow = selectedVolume
        ?.let(::volumeHeaderNumber)
        ?.let(localizedVolumeName)

    // R6 round 3: a user vertical drag collapses to focused (no haptic)
    // and closes the menu. The DragInteraction gate keeps programmatic
    // restoration scrolls from collapsing; tap-chrome is untouched.
    LaunchedEffect(listState, isActivePage) {
        var userDragging = false
        launch {
            listState.interactionSource.interactions.collect { interaction ->
                userDragging = interaction is DragInteraction.Start
            }
        }
        snapshotFlow { listState.isScrollInProgress }.collect { scrolling ->
            if (scrolling && userDragging && isActivePage) onUserScroll()
        }
    }

    // This is the only vertical-scroll writer. A command waits through a
    // sentinel/unloaded page, then applies once the matching list exists.
    LaunchedEffect(landing?.token, hadiths.firstOrNull()?._id, pageIndex, isActivePage,
        layoutProjection, hadiths, selectedLayoutVolume, layoutTranslations, layoutAllowances, viewportSize) {
        val request = landing ?: return@LaunchedEffect
        if (!viewModel.isRecentLandingValid(request)) {
            if (initialLanding == request) initialLanding = null
            return@LaunchedEffect
        }
        if (hadiths.isEmpty()) return@LaunchedEffect
        val layout = viewportLayout()
        if (appliedLandingToken == request.token && appliedLandingLayout == layout) {
            if (isActivePage) viewModel.acknowledgeVerticalLanding(request)
            return@LaunchedEffect
        }
        val snapshot = request.viewport
        if (snapshot != null && (viewportSize.width == 0 || viewportSize.height == 0)) return@LaunchedEffect
        if (snapshot != null && snapshot.layout == layout) {
            listState.scrollToItem(snapshot.firstItemIndex, snapshot.firstItemOffset)
        } else when (val destination = request.landing) {
            ReaderVerticalLanding.Header -> listState.scrollToItem(0, 0)
            is ReaderVerticalLanding.Semantic -> {
                val itemIndex = hadiths.indexOfFirst {
                    it.providerHadithId == destination.providerHadithId
                }.takeIf { it >= 0 }?.plus(1) ?: return@LaunchedEffect
                listState.scrollToItem(itemIndex)
                if (destination.normalizedOffset > 0.0) {
                    withFrameNanos { }
                    if (!viewModel.isRecentLandingValid(request)) return@LaunchedEffect
                    val size = listState.layoutInfo.visibleItemsInfo
                        .firstOrNull { it.index == itemIndex }
                        ?.size
                        ?: return@LaunchedEffect
                    listState.scrollToItem(itemIndex, (size * destination.normalizedOffset).roundToInt())
                }
            }
        }
        appliedLandingToken = request.token
        appliedLandingLayout = layout
        if (initialLanding == request) initialLanding = null
        if (isActivePage) viewModel.acknowledgeVerticalLanding(request)
    }

    // Clearing the command cancels its effect; observe the acknowledged frame separately.
    LaunchedEffect(isActivePage, state.verticalLanding, state.pageIndex, hadiths, state.translations, preferences.arabicVisible, preferences.translationVisible) {
        if (state.verticalLanding != null || !isActivePage || hadiths.isEmpty()) return@LaunchedEffect
        withFrameNanos { }
        val visible = listState.layoutInfo.visibleItemsInfo.mapNotNull { item ->
            readerHadithIndex(item.index, hadiths.size)?.let { index ->
                Triple(hadiths[index].providerHadithId, item.offset.toDouble(), item.size.toDouble())
            }
        }
        viewModel.inspectInitialTarget(visible, listState.layoutInfo.viewportEndOffset.toDouble())
        visible.forEach { anchor -> viewModel.observeVisibleEntry(anchor.first, anchor.second, anchor.third,
            listState.layoutInfo.viewportEndOffset.toDouble()) }
    }

    // Intra-page scroll fraction for the dynamic page bars: leading item
    // plus its consumed offset over the page's item count.
    LaunchedEffect(listState, hadiths, isActivePage) {
        snapshotFlow {
            val info = listState.layoutInfo
            val total = info.totalItemsCount.coerceAtLeast(1)
            val first = info.visibleItemsInfo.firstOrNull()
            if (first == null) {
                0f
            } else {
                val consumed = (-first.offset).coerceAtLeast(0).toFloat() /
                    first.size.coerceAtLeast(1)
                ((first.index + consumed) / total).coerceIn(0f, 1f)
            }
        }.distinctUntilChanged { a, b -> abs(a - b) < 0.005f }
            .collect { if (isActivePage) onPageScrollFraction(pageIndex, it) }
    }

    LaunchedEffect(listState, hadiths, isActivePage, initialLanding, layoutProjection, selectedLayoutVolume, layoutTranslations, layoutAllowances) {
        if (!isActivePage || hadiths.isEmpty() || initialLanding != null) return@LaunchedEffect
        snapshotFlow {
            val info = listState.layoutInfo
            info.visibleItemsInfo.firstOrNull { item ->
                readerHadithIndex(item.index, hadiths.size) != null && item.offset + item.size > 0
            }?.let {
                Triple(it.index, it.offset, it.size)
            }
        }
            .filterNotNull()
            .distinctUntilChanged()
            .onEach { (index, offset, size) ->
                viewModel.captureStableScroll(hadiths, readerHadithIndex(index, hadiths.size) ?: return@onEach,
                    (-offset).coerceAtLeast(0).toDouble(), (-offset).coerceAtLeast(0).toDouble() / size.coerceAtLeast(1), persist = false, atHeader = listState.firstVisibleItemIndex == 0 && listState.firstVisibleItemScrollOffset == 0,
                    viewport = ReaderViewportSnapshot(viewportLayout(), listState.firstVisibleItemIndex, listState.firstVisibleItemScrollOffset))
            }
            .debounce(500)
            .collect { (index, offset, size) ->
                readerHadithIndex(index, hadiths.size)?.let { hadithIndex ->
                    viewModel.observeVisibleEntry(hadiths[hadithIndex].providerHadithId, offset.toDouble(), size.toDouble(),
                        listState.layoutInfo.viewportEndOffset.toDouble())
                }
                viewModel.captureStableScroll(
                    hadiths = hadiths,
                    leadingIndex = readerHadithIndex(index, hadiths.size) ?: return@collect,
                    rawPageOffset = (-offset).coerceAtLeast(0).toDouble(),
                    normalizedOffset = (-offset).coerceAtLeast(0).toDouble() / size.coerceAtLeast(1),
                    atHeader = listState.firstVisibleItemIndex == 0 && listState.firstVisibleItemScrollOffset == 0,
                    viewport = ReaderViewportSnapshot(viewportLayout(), listState.firstVisibleItemIndex, listState.firstVisibleItemScrollOffset),
                )
            }
    }

    val experience = com.hadithly.app.HadithlyApplication.instance().readerExperience
    val automatic by experience.automaticallyTranslates.collectAsStateWithLifecycle()
    val activeSession by com.clerk.api.Clerk.sessionFlow.collectAsStateWithLifecycle()
    LaunchedEffect(listState, isActivePage, automatic, preferences.translationVisible, state.language, activeSession?.id) {
        if (!isActivePage || !automatic || !preferences.translationVisible) return@LaunchedEffect
        snapshotFlow {
            val info = listState.layoutInfo
            info.visibleItemsInfo.mapNotNull { item ->
                readerHadithIndex(item.index, hadiths.size)?.let { hadiths[it].internalId }
            }
        }.distinctUntilChanged().debounce(450).collect(viewModel::automaticallyTranslateVisible)
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .testTag("reader.pageViewport")
            .then(if (isActivePage) Modifier else Modifier.clearAndSetSemantics { }.pointerInput(Unit) {
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial).consume()
                    do {
                        val event = awaitPointerEvent(PointerEventPass.Initial)
                        event.changes.forEach { it.consume() }
                    } while (event.changes.any { it.pressed })
                }
            })
            .confirmedTapGesture { if (isActivePage) onTap() },
    ) {
        if (isSentinel || hadiths.isEmpty()) {
            Box(
                modifier = Modifier.fillMaxSize().testTag("reader.pageLoading"),
                contentAlignment = Alignment.TopCenter,
            ) {
                com.hadithly.app.core.theme.ArticleLoadingView(nativeText("Loading page"))
            }
        } else {
            LazyColumn(
                state = listState,
                verticalArrangement = Arrangement.spacedBy(0.dp),
                // Round 7 full-bleed (pre-round-4 behavior): edge-to-edge
                // is on and the page flows INTO the system-bar zones with
                // no status/navigation inset on the list — exactly as
                // before commit 6409bbd. The status bar stays visible; the
                // chrome overlays carry their own statusBars/
                // navigationBars padding.
                modifier = Modifier.fillMaxSize(),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(
                    start = 22.dp, end = 22.dp,
                    top = topContentPadding,
                    bottom = 80.dp,
                ),
            ) {
                // Round 8, no top jerk (mirrors iOS headerSlot): the first
                // page of a volume shows ONLY the volume-start header slot;
                // every other page shows ONLY the corner slot. Each slot is
                // composed synchronously at its FINAL height from the first
                // frame — real content when the volume has resolved, an
                // invisible same-layout placeholder until then — so nothing
                // pops in late and content never shifts down. Placeholders
                // carry no test tags, so queries only match real content.
                if (pageIndex == 0) {
                    item(key = "reader-volume-start") {
                        val volumeTitle = volumeStartTitle
                        val volume = selectedVolume
                        if (volume != null && volumeTitle != null) {
                            VolumeStartHeader(
                                title = volumeTitle,
                                eyebrow = volumeStartEyebrow,
                                hadithCount = volume.hadithCount.toInt(),
                            )
                        } else {
                            VolumeStartHeaderPlaceholder()
                        }
                    }
                } else {
                    item(key = "reader-volume-corner") {
                        VolumeCornerLabel(
                            title = cornerTitle ?: " ",
                            range = cornerRange,
                            placeholder = cornerTitle == null,
                            modifier = Modifier.graphicsLayer {
                                alpha = chromeAlpha
                                scaleX = chromeScale
                                scaleY = chromeScale
                            },
                        )
                    }
                }
                itemsIndexed(hadiths, key = { _, hadith -> hadith._id }) { index, hadith ->
                    Column {
                        if (chapterOpenings.contains(index)) {
                            val chapterName = hadith.chapterName.orEmpty()
                            // Item 2: Arabic-only reading uses the provider's
                            // arabicTitle as the chapter line when present;
                            // mixed/translation-only behavior is unchanged.
                            val arabicTitleFor = ReaderChapterBoundaries.arabicTitleFor(
                                volumeChapters,
                                chapterName,
                            )
                            ReaderChapterHeader(
                                title = chapterTitleForDisplay(chapterName, arabicTitleFor, arabicOnly),
                                arabicTitle = if (arabicOnly) {
                                    null
                                } else {
                                    visibleArabicChapterTitle(
                                        arabicVisible = preferences.arabicVisible,
                                        title = chapterName,
                                        arabicTitle = arabicTitleFor,
                                    )
                                },
                            )
                        }
                        HadithBlock(
                            hadith = hadith,
                            translationState = state.translations[hadith.internalId],
                            allowance = state.translationAllowances[hadith.internalId],
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
                            onShowSource = { sourceHadith = hadith },
                            onEditNote = { noteTarget = hadith },
                            onSuggest = { translation -> submissionTarget = hadith to translation },
                            onReport = { translation -> reportTarget = hadith to translation },
                            onShowPaywall = onShowPaywall,
                            library = viewModel.library,
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
                        arabicOnly = preferences.arabicVisible && !preferences.translationVisible,
                    )
                }
            }
        }

        // R6A: one tap on the grade-dot label opens the small source sheet.
        // Copy/share payloads keep the full source line (ReaderShare).
        sourceHadith?.let { hadith ->
            ModalBottomSheet(
                onDismissRequest = { sourceHadith = null },
                containerColor = colors.surface,
            ) {
                val translation = (state.translations[hadith.internalId] as? TranslationUiState.Loaded)?.translation
                HadithSourceSheet(hadith = hadith, translation = translation, onDismiss = { sourceHadith = null })
            }
        }

        noteTarget?.let { hadith ->
            ModalBottomSheet(
                onDismissRequest = { noteTarget = null },
                containerColor = colors.surface,
            ) {
                NoteEditorSheet(
                    initialContent = viewModel.noteContent(hadith),
                    initialScope = viewModel.libraryActionScope,
                    isScopeCurrent = viewModel::isLibraryActionCurrent,
                    onSave = { content ->
                        val saved = viewModel.saveNote(hadith, content).await()
                        if (saved) noteTarget = null
                        saved
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
    arabicOnly: Boolean = false,
) {
    CompositionLocalProvider(LocalLayoutDirection provides if (policy.pageDirection == PageDirection.RTL) LayoutDirection.Rtl else LayoutDirection.Ltr) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 12.dp)
                .testTag("reader.pagePills"),
        ) {
            state.previous?.let { PagePill(it, policy, onFollow, Modifier.weight(1f), arabicOnly) } ?: Spacer(Modifier.weight(1f))
            state.next?.let { PagePill(it, policy, onFollow, Modifier.weight(1f), arabicOnly) } ?: Spacer(Modifier.weight(1f))
        }
    }
}

@Composable
private fun PagePill(
    pill: ReaderPagePills.Pill,
    policy: ReaderPagingPolicy,
    onFollow: (ReaderPagePills.Pill) -> Unit,
    modifier: Modifier,
    arabicOnly: Boolean,
) {
    val colors = LocalHadithlyColors.current
    val numbers = java.text.NumberFormat.getIntegerInstance(LocalConfiguration.current.locales[0])
    val resources = androidx.compose.ui.platform.LocalResources.current
    val label = when (val target = pill.target) {
        is ReaderPagePills.Target.Page -> nativeText("Page %1$@", numbers.format(target.index + 1))
        is ReaderPagePills.Target.VolumeFirst, is ReaderPagePills.Target.VolumeLast -> volumeTitleForDisplay(pill.label, arabicOnly) { resources.getString(R.string.reader_volume_title, it) }
    }
    val accessibleLabel = nativeText(if (pill.turn == ReaderPageTurn.PREVIOUS) "Previous page, %1$@" else "Next page, %1$@", label)
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
            .semantics { contentDescription = accessibleLabel },
    ) {
        if (pill.turn == ReaderPageTurn.PREVIOUS) {
            PagePillChevron(pointsLeft)
        }
        Text(
            text = label,
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
        imageVector = if (pointsLeft) Icons.Filled.ChevronLeft else Icons.Filled.ChevronRight,
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
 * the chevron glyphs follow the explicit reading direction and the
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
    val numbers = java.text.NumberFormat.getIntegerInstance(LocalConfiguration.current.locales[0])
    CompositionLocalProvider(LocalLayoutDirection provides if (policy.pageDirection == PageDirection.RTL) LayoutDirection.Rtl else LayoutDirection.Ltr) {
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
                        nativeText("Page %1$@ of %2$@", numbers.format(currentPageIndex + 1), numbers.format(pageCount))
                    } else {
                        nativeText("Page %1$@", numbers.format(currentPageIndex + 1))
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
}

@Composable
private fun PageChevron(
    turn: ReaderPageTurn,
    destination: Int,
    pointsLeft: Boolean,
    onTurn: (ReaderPageTurn) -> Unit,
) {
    val colors = LocalHadithlyColors.current
    val number = java.text.NumberFormat.getIntegerInstance(LocalConfiguration.current.locales[0]).format(destination + 1)
    val page = nativeText("Page %1$@", number)
    val accessibleLabel = nativeText(if (turn == ReaderPageTurn.PREVIOUS) "Previous page, %1$@" else "Next page, %1$@", page)
    val actionLabel = nativeText(if (turn == ReaderPageTurn.PREVIOUS) "Previous page" else "Next page")
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
                contentDescription = accessibleLabel
                customActions = listOf(
                    CustomAccessibilityAction(
                        actionLabel,
                    ) {
                        onTurn(turn)
                        true
                    },
                )
            },
    ) {
        Icon(
            if (pointsLeft) {
                Icons.Filled.ChevronLeft
            } else {
                Icons.Filled.ChevronRight
            },
            contentDescription = null,
            tint = colors.textSecondary,
            modifier = Modifier.size(22.dp),
        )
    }
}

/**
 * The unfocused progress pill (Sajda `208 page` / `11 juz` style): a short
 * capsule with a neutral fill plus a bold number and a lighter suffix
 * (`Page N`, `Volume N`). Non-interactive, hidden from traversal.
 */
@Composable
private fun ReaderProgressPill(
    number: String,
    suffix: String,
    accessibilityLabel: String,
    fraction: Double,
    testTag: String,
    modifier: Modifier = Modifier,
    reduceMotion: Boolean = false,
    onClick: (() -> Unit)? = null,
) {
    val colors = LocalHadithlyColors.current
    // Round 7: the fill animates to its new fraction on page switch
    // instead of jumping (~250ms; snapped on Reduce Motion).
    val animatedFraction by animateFloatAsState(
        targetValue = fraction.toFloat().coerceIn(0.02f, 1f),
        animationSpec = if (reduceMotion) snap() else tween(250),
        label = "readerPillFill",
    )
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .width(IntrinsicSize.Max)
            .heightIn(min = if (onClick != null) 44.dp else 32.dp)
            .clip(RoundedCornerShape(50))
            .background(colors.surface.copy(alpha = 0.84f))
            .border(
                androidx.compose.foundation.BorderStroke(0.5.dp, colors.divider.copy(alpha = 0.62f)),
                RoundedCornerShape(50),
            )
            .then(if (onClick != null) Modifier.clickable(enabled = true, onClick = onClick) else Modifier)
            .testTag(testTag)
            .semantics(mergeDescendants = true) { contentDescription = accessibilityLabel },
    ) {
        // Round 8: the fill occupies the FULL pill height — no top/bottom
        // inset, only a small horizontal inset — clipped to the pill
        // capsule, so low fills stay a rounded nub and never show square
        // corners. The fill fraction still animates (see above).
        Box(Modifier.matchParentSize()) {
            Box(
                modifier = Modifier
                .align(Alignment.CenterStart)
                .fillMaxHeight()
                .padding(horizontal = 3.dp)
                .fillMaxWidth(animatedFraction)
                .clip(RoundedCornerShape(50))
                .background(colors.textSecondary.copy(alpha = 0.22f)),
            )
        }
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
        ) {
            Text(
                text = number,
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold,
                color = colors.textPrimary,
            )
            Text(
                text = suffix,
                fontSize = 12.sp,
                color = colors.textSecondary,
            )
        }
    }
}

/**
 * The short neutral progress capsule (item 6): a narrow track with a
 * neutral fill, never green, never full-width. The one mid-screen bar is
 * gone; focused shows one thin capsule, unfocused a static volume capsule
 * plus a thicker page capsule. Non-interactive and hidden from traversal.
 */
@Composable
private fun ReaderProgressCapsule(
    fraction: Double,
    thickness: androidx.compose.ui.unit.Dp,
    testTag: String,
    modifier: Modifier = Modifier,
    reduceMotion: Boolean = false,
) {
    val colors = LocalHadithlyColors.current
    // Round 7: the fill animates to its new fraction on page switch
    // instead of jumping (~250ms; snapped on Reduce Motion).
    val animatedFraction by animateFloatAsState(
        targetValue = fraction.toFloat().coerceIn(0.02f, 1f),
        animationSpec = if (reduceMotion) snap() else tween(250),
        label = "readerCapsuleFill",
    )
    Box(
        modifier = modifier
            .height(thickness)
            .clip(RoundedCornerShape(50))
            .background(colors.surfaceElevated.copy(alpha = 0.76f))
            .testTag(testTag),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth(animatedFraction)
                .height(thickness)
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
 *
 * Round 7: always exactly one line (minLines + maxLines with ellipsis), so
 * the slot height is fixed from first paint — a late-resolving title or
 * range can never shift content. [placeholder] renders the blank slot
 * transparently until the title resolves.
 */
@Composable
internal fun VolumeCornerLabel(
    title: String,
    range: Pair<Int, Int>?,
    modifier: Modifier = Modifier,
    placeholder: Boolean = false,
) {
    val colors = LocalHadithlyColors.current
    // Round 8: the placeholder is an invisible same-font single space —
    // same line height as real text — and carries no test tag, so element
    // queries only ever match real content (mirrors iOS headerSlot).
    if (placeholder) {
        Text(
            text = " ",
            fontSize = 12.sp,
            color = colors.textSecondary.copy(alpha = 0f),
            textAlign = TextAlign.Start,
            minLines = 1,
            maxLines = 1,
            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
            modifier = modifier.fillMaxWidth(),
        )
        return
    }
    Text(
        text = if (range != null && title.isNotBlank()) "$title: ${range.first}–${range.second}" else title,
        fontSize = 12.sp,
        color = colors.textSecondary,
        textAlign = TextAlign.Start,
        minLines = 1,
        maxLines = 1,
        overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
        modifier = modifier
            .fillMaxWidth()
            .testTag("reader.volumeCorner"),
    )
}

/**
 * R6A volume start: the ACTUAL volume name as the big centered title with
 * a small quiet localized `Volume N` eyebrow above it and a localized
 * ICU-plural count line beneath (e.g. "10 hadiths"). Rendered on the
 * volume's first page only.
 *
 * Round 8: every line slot is always composed — a missing eyebrow or count
 * renders as invisible same-font text — so the header height is identical
 * before and after each piece of data lands. Real lines keep their test
 * tags; invisible slots carry none.
 */
@Composable
internal fun VolumeStartHeader(title: String, eyebrow: String? = null, hadithCount: Int) {
    val colors = LocalHadithlyColors.current
    val invisible = colors.textSecondary.copy(alpha = 0f)
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 12.dp, bottom = 24.dp),
    ) {
        Text(
            text = eyebrow ?: " ",
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium,
            color = if (eyebrow != null) colors.textSecondary else invisible,
            textAlign = TextAlign.Center,
            maxLines = 1,
            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
            modifier = if (eyebrow != null) Modifier.testTag("reader.volumeEyebrow") else Modifier,
        )
        Text(
            text = title,
            fontSize = 20.sp,
            fontWeight = FontWeight.SemiBold,
            color = colors.textPrimary,
            textAlign = TextAlign.Center,
        )
        Text(
            text = if (hadithCount > 0) {
                pluralStringResource(R.plurals.reader_hadith_count, hadithCount, hadithCount)
            } else {
                " "
            },
            fontSize = 13.sp,
            color = if (hadithCount > 0) colors.textSecondary else invisible,
            textAlign = TextAlign.Center,
            maxLines = 1,
            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 4.dp),
        )
    }
}

/**
 * Round 8: identifier-free stand-in with the exact font stack, weights,
 * and padding of [VolumeStartHeader], so the first-page slot keeps its
 * height before the volume arrives. Hidden from assistive tech and element
 * queries (mirrors iOS ReaderVolumeHeaderPlaceholder).
 */
@Composable
internal fun VolumeStartHeaderPlaceholder() {
    val colors = LocalHadithlyColors.current
    val invisible = colors.textSecondary.copy(alpha = 0f)
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 12.dp, bottom = 24.dp)
            .clearAndSetSemantics {},
    ) {
        Text(
            text = " ",
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium,
            color = invisible,
            textAlign = TextAlign.Center,
            maxLines = 1,
            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
        )
        Text(
            text = " ",
            fontSize = 20.sp,
            fontWeight = FontWeight.SemiBold,
            color = invisible,
            textAlign = TextAlign.Center,
        )
        Text(
            text = " ",
            fontSize = 13.sp,
            color = invisible,
            textAlign = TextAlign.Center,
            maxLines = 1,
            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 4.dp),
        )
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
 * theme-aware across System, Light, Paper, and Dark: sahih emerald
 * (semantic-only, deliberately not the monochrome accent), hasan amber
 * (bookmark), daif red (destructive), anything else gray (secondary text).
 */
internal fun gradeDotColor(
    grade: ReaderGrade,
    colors: com.hadithly.app.core.theme.HadithlyColors,
): androidx.compose.ui.graphics.Color = when (grade) {
    ReaderGrade.SAHIH -> colors.gradeSahih
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
    allowance: com.hadithly.app.core.data.TranslationAllowance? = null,
    arabicFontSize: Float,
    preferences: ReaderPreferences,
    deps: HadithBlockDeps,
    modifier: Modifier = Modifier,
    onTap: () -> Unit,
    onRetry: () -> Unit,
    onShowSource: () -> Unit,
    onEditNote: () -> Unit,
    onSuggest: (ReaderTranslation?) -> Unit,
    onReport: (ReaderTranslation) -> Unit,
    onShowPaywall: () -> Unit,
    library: UserLibraryModel? = null,
) {
    val colors = LocalHadithlyColors.current
    val clipboard = LocalClipboard.current
    val clipboardScope = rememberCoroutineScope()
    val context = LocalContext.current
    val hapticView = LocalView.current
    var menuExpanded by remember { mutableStateOf(false) }
    val app = com.hadithly.app.HadithlyApplication.instance()
    val savedLibrary = library ?: app.library
    var pendingRemoval by remember { mutableStateOf<String?>(null) }
    val bookmarkRemovedLabel = stringResource(R.string.saved_bookmark_removed)
    val favoriteRemovedLabel = stringResource(R.string.saved_favorite_removed)
    val savedRef = HadithRef(hadith._id, hadith.collectionSlug, hadith.collectionName, hadith.volumeId, hadith.providerHadithId, hadith.arabicText, hadith.englishText, hadith.referenceDisplay)

    fun toggleBookmarkSafely() {
        if (deps.isBookmarked) {
            val createdAt = savedLibrary.savedItems.value.firstOrNull { it.hadithId == hadith._id }?.bookmarkCreatedAt
            deps.onToggleBookmark()
            if (createdAt != null) savedLibrary.undo.show(bookmarkRemovedLabel) { savedLibrary.restoreBookmark(savedRef, createdAt) }
        } else deps.onToggleBookmark()
    }
    fun toggleFavoriteSafely() {
        if (deps.isFavorite) {
            val createdAt = savedLibrary.savedItems.value.firstOrNull { it.hadithId == hadith._id }?.favoriteCreatedAt
            deps.onToggleFavorite()
            if (createdAt != null) savedLibrary.undo.show(favoriteRemovedLabel) { savedLibrary.restoreFavorite(savedRef, createdAt) }
        } else deps.onToggleFavorite()
    }

    val loadedTranslation = (translationState as? TranslationUiState.Loaded)?.translation
    val visibleArabic = hadith.arabicText.takeIf { preferences.arabicVisible }
    val visibleTranslation: String?
    val visibleTranslationIsAi: Boolean
    if (language == "en") {
        visibleTranslation = (loadedTranslation?.translation ?: hadith.englishText).takeIf { preferences.translationVisible }
        visibleTranslationIsAi = loadedTranslation?.source == "gemini_ai"
    } else {
        visibleTranslation = loadedTranslation?.translation.takeIf { preferences.translationVisible }
        visibleTranslationIsAi = loadedTranslation?.source == "gemini_ai"
    }

    val copyHadithLabel = nativeText("Hadith")
    val copyAiLabel = nativeText("AI translation")
    fun doCopy() {
        val text = ReaderShare.formatCopyText(
            arabicText = visibleArabic,
            translationText = visibleTranslation,
            translationIsAi = visibleTranslationIsAi,
            collectionName = hadith.collectionName,
            providerHadithId = hadith.providerHadithId,
            sourceName = hadith.authenticity.sourceName,
            hadithLabel = copyHadithLabel,
            aiLabel = copyAiLabel,
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
    val menuActions = localizedHadithMenuActions(hadithMenuActions(
        isBookmarked = deps.isBookmarked,
        isFavorite = deps.isFavorite,
        hasNote = deps.hasNote,
        loadedTranslation = loadedTranslation,
        onToggleBookmark = {
            val adding = !deps.isBookmarked
            if (!adding && app.savedSafety.confirmsRemoval) pendingRemoval = "bookmark" else toggleBookmarkSafely()
            if (adding) ReaderHaptics.perform(hapticView, ReaderHapticKind.BOOKMARK_FAVORITE_ADD)
        },
        onToggleFavorite = {
            val adding = !deps.isFavorite
            if (!adding && app.savedSafety.confirmsRemoval) pendingRemoval = "favorite" else toggleFavoriteSafely()
            if (adding) ReaderHaptics.perform(hapticView, ReaderHapticKind.BOOKMARK_FAVORITE_ADD)
        },
        onEditNote = onEditNote,
        onCopy = { doCopy() },
        onShare = { doShare() },
        onReport = onReport,
        onSuggest = onSuggest,
    ))

    Column(
        verticalArrangement = Arrangement.spacedBy(16.dp),
        modifier = modifier
            .combinedClickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                // Tap still toggles the chrome; the block consumes the press
                // so the page-level tap detector must be invoked explicitly.
                onClick = onTap,
                onLongClick = {
                    app.readerExperience.dismissActionHint()
                    ReaderHaptics.perform(hapticView, ReaderHapticKind.LONG_PRESS_MENU)
                    menuExpanded = true
                },
            )
            .semantics {
                customActions = customActionsFor(menuActions)
            }
            .testTag("reader.hadithBlock"),
    ) {
        HadithHeader(
            hadith = hadith,
            isBookmarked = deps.isBookmarked,
            isFavorite = deps.isFavorite,
            hasNote = deps.hasNote,
            onShowSource = onShowSource,
        )

        HadithContextMenu(
            referenceDisplay = hadith.referenceDisplay,
            actions = menuActions,
            expanded = menuExpanded,
            onDismiss = { menuExpanded = false },
        )

        // Item 2: Arabic-only reading shows the provider's Arabic narrator
        // line (narratorAr, RTL) between the header and the Arabic; a
        // missing line stays hidden. Mixed/translation-only keep the
        // English narrator at the translation's leading edge.
        val arabicOnly = preferences.arabicVisible && !preferences.translationVisible
        val narratorText = narratorForMode(hadith, arabicOnly)
        if (arabicOnly) {
            NarratorLine(narratorText, preferences, arabicAligned = true)
        }

        if (preferences.arabicVisible) {
            ReaderArabicText(hadith.arabicText, arabicFontSize, preferences.arabicFont)
        }

        // Translation-only and mixed modes retain the narrator at the
        // translation's leading edge. Arabic-only mode placed it above the
        // Arabic block, under the source header, in the Arabic direction.
        if (!arabicOnly) {
            NarratorLine(narratorText, preferences, arabicAligned = false)
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
                    fontSize = preferences.translationFontSize,
                    onRetry = onRetry,
                    onShowPaywall = onShowPaywall,
                    allowance = allowance,
                )

            }
        }

        // R6A fix: no bottom label — the top header is the single per-hadith
        // header (source sheet tap lives there; copy/share payloads keep
        // the full source line via ReaderShare).
    }
    if (pendingRemoval != null) AlertDialog(onDismissRequest = { pendingRemoval = null }, title = { Text(nativeText("Remove saved item?")) }, text = { Text(stringResource(R.string.saved_removal_undo_message)) }, confirmButton = { TextButton(onClick = { if (pendingRemoval == "bookmark") toggleBookmarkSafely() else toggleFavoriteSafely(); pendingRemoval = null }) { Text(nativeText("Remove")) } }, dismissButton = { Column { TextButton(onClick = { app.savedSafety.confirmsRemoval = false; if (pendingRemoval == "bookmark") toggleBookmarkSafely() else toggleFavoriteSafely(); pendingRemoval = null }) { Text(nativeText("Remove and don't ask again")) }; TextButton(onClick = { pendingRemoval = null }) { Text(nativeText("Cancel")) } } })
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
 * label. Bookmark and favorite plus the R6 round 3 green note dot — like
 * the Sajda verse markers, indicators only, never buttons.
 */
internal enum class SavedMiniMarker {
    BOOKMARK,
    FAVORITE,
    NOTE;
}

internal fun savedMiniMarkers(
    isBookmarked: Boolean,
    isFavorite: Boolean,
    hasNote: Boolean = false,
): List<SavedMiniMarker> = buildList {
    if (isBookmarked) add(SavedMiniMarker.BOOKMARK)
    if (isFavorite) add(SavedMiniMarker.FAVORITE)
    if (hasNote) add(SavedMiniMarker.NOTE)
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
    hasNote: Boolean = false,
) {
    val colors = LocalHadithlyColors.current
    val grade = ReaderGrade.from(hadith.authenticity.normalizedGrade)
    val gradeLabel = nativeText(grade.displayName)
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
                        "${ReaderViewModel.shortCollectionName(hadith.collectionSlug, hadith.collectionName)} – ${hadith.providerHadithId}, ${gradeLabel}"
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
        for (marker in savedMiniMarkers(isBookmarked, isFavorite, hasNote)) {
            Spacer(modifier = Modifier.width(7.dp))
            Icon(
                imageVector = when (marker) {
                    SavedMiniMarker.BOOKMARK -> Icons.Filled.Bookmark
                    SavedMiniMarker.FAVORITE -> Icons.Filled.Favorite
                    SavedMiniMarker.NOTE -> Icons.Filled.Note
                },
                contentDescription = nativeText(when (marker) {
                    SavedMiniMarker.BOOKMARK -> "Bookmarked"
                    SavedMiniMarker.FAVORITE -> "Favorited"
                    SavedMiniMarker.NOTE -> "Has note"
                }),
                tint = when (marker) {
                    SavedMiniMarker.BOOKMARK -> colors.bookmark
                    SavedMiniMarker.FAVORITE -> colors.favorite
                    SavedMiniMarker.NOTE -> colors.interactive
                },
                modifier = Modifier
                    .size(12.dp)
                    .testTag(
                        when (marker) {
                            SavedMiniMarker.BOOKMARK -> "reader.savedBookmark"
                            SavedMiniMarker.FAVORITE -> "reader.savedFavorite"
                            SavedMiniMarker.NOTE -> "reader.savedNote"
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
internal fun HadithSourceSheet(hadith: ReaderHadith, translation: ReaderTranslation? = null, onDismiss: (() -> Unit)? = null) {
    val colors = LocalHadithlyColors.current
    Column(
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier
            .fillMaxWidth().verticalScroll(rememberScrollState())
            .padding(20.dp)
            .testTag("reader.sourceSheet"),
    ) {
        if (onDismiss != null) ReaderSheetHeader(hadithHeaderText(hadith.collectionSlug, hadith.collectionName, hadith.providerHadithId), onDismiss, "reader.sourceSheet.close")
        Text(
            text = hadith.authenticity.sourceName,
            fontSize = 17.sp,
            fontWeight = FontWeight.SemiBold,
            color = colors.textPrimary,
        )
        Text(
            text = com.hadithly.app.core.preferences.authenticityText(hadith.authenticity.claimScope, hadith.authenticity.normalizedGrade, hadith.authenticity.sourceName),
            fontSize = 13.sp,
            color = colors.textSecondary,
        )
        if (hadith.authenticity.sourceUrl.isNotBlank()) {
            Text(
                text = hadith.authenticity.sourceUrl,
                fontSize = 12.sp,
                color = colors.interactive,
            )
        }
        translation?.let {
            HorizontalDivider(color = colors.divider, modifier = Modifier.padding(vertical = 12.dp))
            Text(nativeText("Translation sources"), fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
            TranslationSourceDetails(it, showsTranslation = false)
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

@Composable
internal fun localizedHadithMenuActions(actions: List<HadithMenuAction>): List<HadithMenuAction> = actions.map { action ->
    val key = when (action.label) {
        "Bookmark" -> "Add bookmark"
        "Remove from favorites" -> "Remove favorite"
        "Suggest translation" -> "Suggest a translation"
        else -> action.label
    }
    action.copy(label = nativeText(key))
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
internal fun TranslationSection(
    hadith: ReaderHadith,
    translationState: TranslationUiState?,
    language: String,
    onRetry: () -> Unit,
    onShowPaywall: () -> Unit,
    allowance: com.hadithly.app.core.data.TranslationAllowance? = null,
    fontSize: Float = 16f,
) {
    val colors = LocalHadithlyColors.current
    val stored = (translationState as? TranslationUiState.Loaded)?.translation
    if (stored != null) {
        com.hadithly.app.core.theme.TranslationReveal(com.hadithly.app.core.theme.TranslationPresentationPhase.Available) {
            TranslationText(text = stored.translation, fontSize = fontSize)
        }
        GlossaryNotes(stored.glossaryNotes)
        return
    }
    if (language == "en" && !hadith.englishText.isNullOrEmpty()) {
        TranslationText(text = hadith.englishText, fontSize = fontSize)
        return
    }

    val failure = (translationState as? TranslationUiState.Failed)?.failure
    val retryAt = if (failure == TranslationFailure.QuotaExceeded) allowance?.retryAt else failure?.retryAt
    var now by remember(retryAt) { mutableStateOf(System.currentTimeMillis()) }
    LaunchedEffect(retryAt) {
        if (retryAt != null && retryAt > now) {
            kotlinx.coroutines.delay((retryAt - System.currentTimeMillis()).toLong().coerceAtLeast(0))
            now = System.currentTimeMillis()
        }
    }
    val waiting = retryAt != null && retryAt > now
    val uiDirection = if (LocalConfiguration.current.layoutDirection == android.view.View.LAYOUT_DIRECTION_RTL) LayoutDirection.Rtl else LayoutDirection.Ltr
    CompositionLocalProvider(LocalLayoutDirection provides uiDirection) {
        Column(Modifier.fillMaxWidth().padding(vertical = 16.dp).testTag("reader.translationStatus"),
            verticalArrangement = Arrangement.spacedBy(8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                if (translationState != TranslationUiState.Loading) {
                    val symbol = when (failure) {
                        TranslationFailure.QuotaExceeded -> Icons.Default.HourglassEmpty
                        TranslationFailure.RequiresSignIn -> Icons.Default.PersonOutline
                        null -> Icons.Default.ChatBubbleOutline
                        else -> if (waiting) Icons.Default.Schedule else Icons.Default.ErrorOutline
                    }
                    val tint = when {
                        failure == TranslationFailure.QuotaExceeded || waiting -> colors.bookmark
                        failure != null && failure != TranslationFailure.RequiresSignIn -> colors.destructive
                        else -> colors.textSecondary
                    }
                    Icon(symbol, contentDescription = null, tint = tint, modifier = Modifier.size(24.dp))
                }
                when {
                    translationState == TranslationUiState.Loading -> com.hadithly.app.core.theme.TranslationThinkingView()
                    failure == TranslationFailure.RequiresSignIn -> {
                        Text(nativeText("No translation yet"), textAlign = TextAlign.Center, style = MaterialTheme.typography.titleSmall, color = colors.textPrimary)
                        Text(nativeText("Sign in from Settings to translate this hadith."), textAlign = TextAlign.Center, style = MaterialTheme.typography.bodySmall, color = colors.textSecondary)
                    }
                    failure == TranslationFailure.QuotaExceeded -> {
                        Text(nativeText("Translation allowance used"), textAlign = TextAlign.Center, style = MaterialTheme.typography.titleSmall, color = colors.textPrimary)
                        Text(nativeText("Existing translations are still available."), textAlign = TextAlign.Center, style = MaterialTheme.typography.bodySmall, color = colors.textSecondary)
                    }
                    failure != null -> Text(nativeText(if (waiting) "Translation temporarily unavailable" else "Translation couldn’t finish"), textAlign = TextAlign.Center, style = MaterialTheme.typography.titleSmall, color = colors.textPrimary)
                    else -> Text(nativeText("No translation yet"), textAlign = TextAlign.Center, style = MaterialTheme.typography.titleSmall, color = colors.textPrimary)
                }
                allowance?.let {
                    Text(nativeText("%1$@ of %2$@ translations left", java.text.NumberFormat.getIntegerInstance(LocalConfiguration.current.locales[0]).format(it.remaining.toInt()), java.text.NumberFormat.getIntegerInstance(LocalConfiguration.current.locales[0]).format(it.limit.toInt())), textAlign = TextAlign.Center, style = MaterialTheme.typography.labelSmall, color = colors.textSecondary, modifier = Modifier.testTag("reader.translationAllowance"))
                }
                if (waiting) {
                    val date = java.text.DateFormat.getDateTimeInstance(java.text.DateFormat.SHORT, java.text.DateFormat.SHORT, LocalConfiguration.current.locales[0]).format(java.util.Date(retryAt.toLong()))
                    Text(nativeText("Try again %@", date), textAlign = TextAlign.Center, style = MaterialTheme.typography.labelSmall, color = colors.textSecondary, modifier = Modifier.testTag("reader.translationRetryAt"))
                }
                when {
                    translationState == null -> TranslationAction("Translate", "reader.generateTranslation", onClick = onRetry)
                    failure == TranslationFailure.QuotaExceeded -> {
                        if (!waiting && retryAt != null) TranslationAction("Try again", "reader.retryTranslation", onClick = onRetry)
                        else if (allowance == null || allowance.limit == 5.0) TranslationAction("See plans", "reader.quotaPaywall", onClick = onShowPaywall)
                        else if (retryAt == null) TranslationAction("Try again", "reader.retryTranslation", onClick = onRetry)
                    }
                    failure is TranslationFailure.Failed -> TranslationAction("Try again", "reader.retryTranslation", enabled = !waiting, onClick = onRetry)
                }
        }
    }
}

@Composable
private fun TranslationAction(title: String, tag: String, enabled: Boolean = true, onClick: () -> Unit) {
    val colors = LocalHadithlyColors.current
    androidx.compose.material3.OutlinedButton(onClick = onClick, enabled = enabled, modifier = Modifier.heightIn(min = 48.dp).testTag(tag)) {
        Text(nativeText(title), color = if (enabled) colors.interactive else colors.textSecondary)
    }
}

@Composable
internal fun ReaderArabicText(
    text: String,
    fontSize: Float,
    font: com.hadithly.app.core.preferences.ArabicFont,
) {
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
        Text(
            text = text,
            fontSize = fontSize.sp,
            fontFamily = com.hadithly.app.core.theme.ArabicTypefaces.forFont(font),
            fontWeight = FontWeight.Medium,
            color = LocalHadithlyColors.current.textPrimary,
            lineHeight = (fontSize * 1.75).sp,
            textAlign = TextAlign.Start,
            modifier = Modifier.fillMaxWidth().testTag("reader.arabic"),
        )
    }
}

@Composable
internal fun TranslationText(
    text: String,
    fontSize: Float,
) {
    val colors = LocalHadithlyColors.current
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            text = text,
            fontSize = fontSize.sp,
            lineHeight = (fontSize + 7).sp,
            color = colors.textPrimary.copy(alpha = 0.92f),
        )
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

// Contents sheet

/**
 * Dark Sajda card aesthetic shared by the reader sheets (contents,
 * settings, search results, bookmarks and notes): near-black canvas cards
 * with a quiet title, a secondary subtitle, and a trailing count or
 * chevron. No Quran-only modes or tabs.
 */
@Composable
internal fun SajdaCardRow(
    title: String,
    subtitle: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    trailingCount: String? = null,
    showChevron: Boolean = true,
    selected: Boolean = false,
    testTag: String? = null,
) {
    val colors = LocalHadithlyColors.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
            .fillMaxWidth()
            .background(
                if (selected) colors.interactiveSoft else colors.surface,
                RoundedCornerShape(16.dp),
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 14.dp)
            .then(if (testTag != null) Modifier.testTag(testTag) else Modifier),
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                fontSize = 16.sp,
                fontWeight = FontWeight.Medium,
                color = colors.textPrimary,
            )
            if (!subtitle.isNullOrEmpty()) {
                Text(
                    text = subtitle,
                    fontSize = 12.sp,
                    color = colors.textSecondary,
                    modifier = Modifier.padding(top = 2.dp),
                )
            }
        }
        if (trailingCount != null) {
            Text(
                text = trailingCount,
                fontSize = 14.sp,
                color = colors.textSecondary,
            )
            Spacer(modifier = Modifier.width(8.dp))
        }
        if (showChevron) {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.NavigateNext,
                contentDescription = null,
                tint = colors.textSecondary,
                modifier = Modifier.size(18.dp),
            )
        }
    }
}

@Composable
internal fun ReaderSheetHeader(title: String, onDismiss: (() -> Unit)? = null, closeTag: String = "reader.sheet.close",
    subtitle: String? = null, onEdit: (() -> Unit)? = null) {
    val colors = LocalHadithlyColors.current
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.weight(1f)) {
            Text(nativeText(title), fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
            if (!subtitle.isNullOrBlank()) Text(subtitle, fontSize = 12.sp, color = colors.textSecondary)
        }
        if (onEdit != null) TextButton(onClick = onEdit, modifier = Modifier.testTag("reader.saved.edit")) { Text(nativeText("EDIT"), color = colors.textPrimary) }
        if (onDismiss != null) TextButton(onClick = onDismiss, modifier = Modifier.testTag(closeTag)) { Text(nativeText("Done"), color = colors.textPrimary) }
    }
}

@Composable
internal fun ContentsSheet(
    volumes: List<com.hadithly.app.core.data.OutlineVolume>,
    selectedVolumeId: String?,
    collectionName: String = "",
    arabicVisible: Boolean,
    onSelect: (String) -> Unit,
    onSelectChapter: (String, com.hadithly.app.core.data.OutlineChapter) -> Unit,
    onJumpToReference: (String) -> Boolean,
    onDismiss: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    var expandedVolumeId by remember(selectedVolumeId) { mutableStateOf(selectedVolumeId) }
    val locale = LocalConfiguration.current.locales[0]
    var jumpInput by remember { mutableStateOf("") }
    var jumpError by remember { mutableStateOf<String?>(null) }

    fun submitJump() {
        if (onJumpToReference(jumpInput.trim())) {
            onDismiss()
        } else {
            jumpError = "Enter a hadith number like 57 or 4.5."
        }
    }

    // Sajda `contents from menu` density: plain rows, a VOLUMES section
    // label, minimal dividers — no heavy cards.
    LazyColumn(
        contentPadding = androidx.compose.foundation.layout.PaddingValues(
            start = 20.dp, end = 20.dp, top = 8.dp, bottom = 24.dp,
        ),
        modifier = Modifier.testTag("reader.contents.sheet"),
    ) {
        item { ReaderSheetHeader("Contents", onDismiss, "reader.contents.close", collectionName) }
        item(key = "contents-jump") {
            Column(modifier = Modifier.padding(top = 4.dp)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    androidx.compose.material3.TextField(
                        value = jumpInput,
                        onValueChange = {
                            jumpInput = it
                            jumpError = null
                        },
                        placeholder = { Text(nativeText("Hadith number"), color = colors.textSecondary) },
                        shape = RoundedCornerShape(20.dp),
                        singleLine = true,
                        isError = jumpError != null,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                        keyboardActions = KeyboardActions(onDone = { submitJump() }),
                        colors = androidx.compose.material3.TextFieldDefaults.colors(
                            focusedIndicatorColor = Color.Transparent,
                            unfocusedIndicatorColor = Color.Transparent,
                            focusedTextColor = colors.textPrimary,
                            unfocusedTextColor = colors.textPrimary,
                            cursorColor = colors.interactive,
                            focusedContainerColor = colors.surfaceElevated,
                            unfocusedContainerColor = colors.surfaceElevated,
                            errorIndicatorColor = colors.destructive,
                        ),
                        modifier = Modifier
                            .weight(1f)
                            .testTag("reader.contents.jump"),
                    )
                    TextButton(
                        onClick = { submitJump() },
                        enabled = jumpInput.isNotBlank(),
                        modifier = Modifier.testTag("reader.contents.go"),
                    ) {
                        Text(
                            nativeText("Go"),
                            fontSize = 16.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = if (jumpInput.isNotBlank()) colors.interactive else colors.textSecondary,
                        )
                    }
                }
                Text(
                    text = nativeText(jumpError ?: "Jump to a hadith number, e.g. 57."),
                    fontSize = 12.sp,
                    color = colors.textSecondary,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
        }
        item(key = "contents-volumes-label") {
            Text(
                nativeText("VOLUMES"),
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                color = colors.textSecondary,
                modifier = Modifier.padding(top = 16.dp, bottom = 4.dp),
            )
        }
        items(volumes, key = { it.volumeId }) { volume ->
            val selected = volume.volumeId == selectedVolumeId
            val expanded = expandedVolumeId == volume.volumeId
            Column(modifier = Modifier.fillMaxWidth()) {
                val name = volumeHeaderTitle(volume)
                val number = volumeHeaderNumber(volume)?.takeIf { it > 0 }
                val title = if (ReaderViewModel.volumeTitleNumber(name) != null || number == null) name
                    else "${java.text.NumberFormat.getIntegerInstance(locale).format(number)}. $name"
                ListItem(
                    headlineContent = {
                        Text(
                            text = title,
                            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
                            color = if (selected) colors.interactive else colors.textPrimary,
                            maxLines = 2,
                            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                        )
                    },
                    trailingContent = {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(volume.hadithCount.toInt().toString(), color = colors.textSecondary)
                            if (volume.chapters.isNotEmpty()) {
                                IconButton(
                                    onClick = { expandedVolumeId = if (expanded) null else volume.volumeId },
                                    modifier = Modifier.size(48.dp),
                                ) {
                                    Icon(
                                        imageVector = if (expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                                        contentDescription = nativeText(if (expanded) "Collapse chapters in %@" else "Expand chapters in %@", volume.title),
                                        tint = colors.textSecondary,
                                    )
                                }
                            } else {
                                Icon(Icons.AutoMirrored.Filled.NavigateNext, null, tint = colors.textSecondary)
                            }
                        }
                    },
                    colors = ListItemDefaults.colors(
                        containerColor = if (selected) colors.interactiveSoft else Color.Transparent,
                    ),
                    modifier = Modifier.fillMaxWidth().testTag("reader.contents.volume.${volume.volumeId}").clickable { onSelect(volume.volumeId) },
                )
                if (expanded) {
                    for (chapter in volume.chapters) {
                        HorizontalDivider(color = colors.divider.copy(alpha = 0.5f), modifier = Modifier.padding(start = 16.dp))
                        val arabic = visibleArabicChapterTitle(
                            arabicVisible = arabicVisible,
                            title = chapter.title,
                            arabicTitle = chapter.arabicTitle,
                        )
                        ListItem(
                            headlineContent = {
                                Text(chapter.title, color = colors.textPrimary, maxLines = 2,
                                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
                            },
                            supportingContent = arabic?.let { title ->
                                { Text(title, color = colors.textSecondary, maxLines = 1,
                                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis) }
                            },
                            trailingContent = {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text(chapter.firstProviderHadithId, color = colors.textSecondary)
                                    Icon(Icons.AutoMirrored.Filled.NavigateNext, null, tint = colors.textSecondary)
                                }
                            },
                            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                            modifier = Modifier.fillMaxWidth()
                                .padding(start = 16.dp)
                                .clickable { onSelectChapter(volume.volumeId, chapter) }
                                .testTag("reader.contents.chapter.${volume.volumeId}.${chapter.firstProviderHadithId}"),
                        )
                    }
                }
            }
            HorizontalDivider(color = colors.divider.copy(alpha = 0.5f))
        }
    }
}

// Reader settings sheet

/** Reader controls shared with Reading & type in the Settings tab. */
@Composable
internal fun SettingsSheet(
    preferences: ReaderPreferences,
    language: String,
    onLanguage: (String) -> Unit,
    onArabicFontSize: (Float) -> Unit,
    onTheme: (com.hadithly.app.core.preferences.ReaderTheme) -> Unit,
    onArabicFont: (com.hadithly.app.core.preferences.ArabicFont) -> Unit,
    onVisibility: (arabic: Boolean?, translation: Boolean?) -> Boolean,
    onDismiss: () -> Unit = {},
    onTranslationFontSize: (Float) -> Unit,
) {
    val view = LocalView.current
    com.hadithly.app.features.settings.ReaderPreferenceContent(
        preferences = preferences.copy(translationLocale = language),
        prefix = "reader",
        onLanguage = onLanguage,
        onArabicFontSize = onArabicFontSize,
        onTranslationFontSize = onTranslationFontSize,
        onTheme = onTheme,
        onArabicFont = onArabicFont,
        onVisibility = { arabic, translation ->
            if (!onVisibility(arabic, translation)) ReaderHaptics.perform(view, ReaderHapticKind.REJECT_BOTH_HIDDEN)
        },
        onDismiss = onDismiss,
    )
}

// Citations sheet

@Composable
internal fun CitationsSheet(translation: ReaderTranslation) {
    Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp)) { TranslationSourceDetails(translation) }
}

@Composable
internal fun TranslationSourceDetails(translation: ReaderTranslation, showsTranslation: Boolean = true) {
    val colors = LocalHadithlyColors.current
    val uriHandler = LocalUriHandler.current
    Column(
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
    ) {
        if (showsTranslation) Text(
            text = translation.translation,
            fontSize = 15.sp,
            color = colors.textPrimary,
        )
        translation.sourceReferenceUrl?.let { url ->
            TextButton(onClick = { uriHandler.openUri(url) }, enabled = isPublicSourceUrl(url)) {
                Text(nativeText("Reference: %1\$s", url), fontSize = 12.sp, color = colors.interactive)
            }
        }
        if (translation.citations.isEmpty()) {
            Text(nativeText("No external sources were cited for this translation."), fontSize = 12.sp, color = colors.textSecondary)
        } else {
            for (citation in translation.citations) {
                TextButton(onClick = { uriHandler.openUri(citation.url) }, enabled = isPublicSourceUrl(citation.url)) {
                    Column(Modifier.fillMaxWidth()) {
                        Text(citation.title ?: citation.url, fontSize = 13.sp, color = colors.textPrimary)
                        citation.domain?.let { Text(it, fontSize = 11.sp, color = colors.textSecondary) }
                    }
                }
            }
        }
        Text(
            text = if (translation.source == "gemini_ai") nativeText("This translation was generated by AI (%@). It is not an authoritative rendering; verify important meanings against a qualified source.", translation.aiModel?.takeIf { it.isNotBlank() } ?: nativeText("model unavailable")) else stringResource(R.string.e3_community_sources_message),
            fontSize = 11.sp,
            color = colors.textSecondary,
            modifier = Modifier.testTag(if (translation.source == "gemini_ai") "translation.sources.ai" else "translation.sources.community"),
        )
    }
}

private fun isPublicSourceUrl(value: String): Boolean = runCatching {
    val uri = java.net.URI(value)
    uri.scheme.equals("https", ignoreCase = true) && !uri.host.isNullOrBlank() && uri.rawUserInfo == null
}.getOrDefault(false)

// Note editor sheet

@Composable
private fun NoteEditorSheet(
    initialContent: String?,
    initialScope: String,
    isScopeCurrent: (String?) -> Boolean,
    onSave: suspend (String) -> Boolean,
    onCancel: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    var content by remember { mutableStateOf(initialContent ?: "") }
    val editingScope = remember { initialScope }
    val saveScope = rememberCoroutineScope()
    var saving by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    LaunchedEffect(initialScope) { if (initialScope != editingScope) onCancel() }

    Column(
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(20.dp),
    ) {
        Text(nativeText("Note"), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)
        androidx.compose.material3.OutlinedTextField(
            value = content,
            onValueChange = { content = it },
            placeholder = { Text(nativeText("Write a private note…"), color = colors.textSecondary) },
            colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
                focusedBorderColor = colors.interactive,
                unfocusedBorderColor = colors.surfaceElevated,
                focusedTextColor = colors.textPrimary,
                unfocusedTextColor = colors.textPrimary,
                cursorColor = colors.interactive,
                focusedContainerColor = colors.surfaceElevated,
                unfocusedContainerColor = colors.surfaceElevated,
            ),
            modifier = Modifier
                .fillMaxWidth()
                .height(160.dp),
        )
        if (failed) Text(nativeText("Try again"), color = colors.destructive)
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            TextButton(enabled = !saving, onClick = onCancel) { Text(nativeText("Cancel"), color = colors.textSecondary) }
            TextButton(
                onClick = {
                    val trimmed = content.trim()
                    if (!isScopeCurrent(editingScope)) { onCancel(); return@TextButton }
                    if (trimmed.isNotEmpty() && !saving) saveScope.launch {
                        saving = true
                        try { failed = !onSave(trimmed) } finally { saving = false }
                    }
                },
                enabled = !saving && content.isNotBlank(),
            ) { Text(nativeText("Save"), color = colors.interactive, fontWeight = FontWeight.Bold) }
        }
    }
}

// Bookmark placement sheet (item 8)

@Composable
internal fun BookmarkPlacementSheet(
    targets: BookmarkPlacementTargets,
    isBookmarked: (ReaderHadith) -> Boolean,
    onChoose: (ReaderHadith) -> Unit,
    onDismiss: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    // Round 7: centered dialog card content (the caller presents it in a
    // Dialog with a dimmed scrim) — wraps its content, never full-height.
    // Round 8: the rows come from bookmarkDialogRows, which always returns
    // exactly [pageStart, positioned, cancel] — every row renders with its
    // test tag, so a Cancel-only card plus ghosted layers cannot happen.
    // Single presentation: the caller closes the reader menu before showing
    // this one Dialog (single scrim, tap-outside cancels).
    val pageStartRow: BookmarkDialogRow
    val positionedRow: BookmarkDialogRow
    val cancelRow: BookmarkDialogRow
    bookmarkDialogRows(targets, isBookmarked).also {
        pageStartRow = it[0]
        positionedRow = it[1]
        cancelRow = it[2]
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = colors.surface,
        titleContentColor = colors.textPrimary,
        textContentColor = colors.textSecondary,
        title = { Text(nativeText("Add bookmark")) },
        text = {
            Column(Modifier.testTag("reader.bookmarkSheet")) {
                PlacementRow(pageStartRow.title, if (pageStartRow.target == null) nativeText("This page") else pageStartRow.subtitle, pageStartRow.enabled, pageStartRow.bookmarked, pageStartRow.testTag) { pageStartRow.target?.let(onChoose) }
                HorizontalDivider(color = colors.divider)
                PlacementRow(positionedRow.title, if (positionedRow.target == null) nativeText("Positioned hadith") else positionedRow.subtitle, positionedRow.enabled, positionedRow.bookmarked, positionedRow.testTag) { positionedRow.target?.let(onChoose) }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss, modifier = Modifier.testTag(cancelRow.testTag)) { Text(nativeText(cancelRow.title)) } },
    )
}

@Composable
private fun PlacementRow(
    title: String,
    subtitle: String,
    enabled: Boolean,
    bookmarked: Boolean,
    testTag: String,
    onClick: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = enabled, onClick = onClick)
            .padding(vertical = 12.dp)
            .testTag(testTag),
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = nativeText(title),
                fontSize = 16.sp,
                fontWeight = FontWeight.Medium,
                color = if (enabled) colors.textPrimary else colors.textSecondary,
            )
            Text(
                text = subtitle,
                fontSize = 12.sp,
                color = colors.textSecondary,
                modifier = Modifier.padding(top = 2.dp),
            )
        }
        Icon(
            imageVector = if (bookmarked) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder,
            contentDescription = nativeText(if (bookmarked) "Bookmarked" else "Not bookmarked"),
            tint = if (bookmarked) colors.bookmark else colors.textSecondary,
            modifier = Modifier.size(22.dp),
        )
    }
}

// Search sheet (item 8)

@Composable
internal fun ReaderSearchSheet(
    search: suspend (String) -> List<EnglishSearchResult>,
    onNavigate: (EnglishSearchResult) -> Unit,
    onDismiss: (() -> Unit)? = null,
) {
    val colors = LocalHadithlyColors.current
    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<EnglishSearchResult>>(emptyList()) }
    var searching by remember { mutableStateOf(false) }
    var unavailable by remember { mutableStateOf(false) }
    var generation by remember { mutableStateOf(0) }
    val scope = rememberCoroutineScope()

    fun runSearch(text: String) {
        generation += 1
        val current = generation
        if (text.isBlank()) {
            results = emptyList()
            searching = false
            unavailable = false
            return
        }
        searching = true
        unavailable = false
        scope.launch {
            delay(350)
            if (current != generation) return@launch
            runCatching { search(text) }
                .onSuccess { hits ->
                    if (current != generation) return@launch
                    results = hits
                    searching = false
                }
                .onFailure {
                    if (current != generation) return@launch
                    results = emptyList()
                    searching = false
                    unavailable = true
                }
        }
    }

    Column(
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier
            .fillMaxWidth()
            // Round 6: the sheet uses the default half/full behavior (no
            // forced expansion); the column fills the allotted height and
            // every state — initial, loading, unavailable, empty, results —
            // owns the full remaining space.
            .fillMaxHeight()
            .padding(20.dp)
            .testTag("reader.search.sheet"),
    ) {
        ReaderSheetHeader("Search", onDismiss, "reader.search.close")
        androidx.compose.material3.TextField(
            value = query,
            onValueChange = {
                query = it
                runSearch(it)
            },
            placeholder = { Text(nativeText("Search English text"), color = colors.textSecondary) },
            shape = RoundedCornerShape(28.dp),
            leadingIcon = {
                Icon(Icons.Filled.Search, contentDescription = null, tint = colors.textSecondary)
            },
            singleLine = true,
            colors = androidx.compose.material3.TextFieldDefaults.colors(
                focusedIndicatorColor = Color.Transparent,
                unfocusedIndicatorColor = Color.Transparent,
                focusedTextColor = colors.textPrimary,
                unfocusedTextColor = colors.textPrimary,
                cursorColor = colors.interactive,
                focusedContainerColor = colors.surfaceElevated,
                unfocusedContainerColor = colors.surfaceElevated,
            ),
            modifier = Modifier
                .fillMaxWidth()
                .testTag("reader.search.field"),
        )
        when {
            searching -> Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.fillMaxWidth().weight(1f),
            ) {
                com.hadithly.app.core.theme.ContentSkeleton(com.hadithly.app.core.theme.SkeletonKind.Rows, label = nativeText("Searching…"))
            }

            unavailable -> Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.fillMaxWidth().weight(1f),
            ) {
                Text(
                    nativeText("Search is unavailable offline."),
                    fontSize = 13.sp,
                    color = colors.textSecondary,
                )
            }

            query.isBlank() -> com.hadithly.app.core.theme.QuietEmptyState("Search this collection", "Find a word or phrase in the available English text.", Icons.Filled.Search, Modifier.weight(1f).testTag("reader.search.hint"))
            results.isEmpty() -> com.hadithly.app.core.theme.QuietEmptyState("No results", "Try another word or a shorter phrase.", Icons.Filled.Search, Modifier.weight(1f).testTag("reader.search.empty"))

            else -> Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .testTag("reader.search.results"),
            ) {
                Text(nativeText("Sunnah.now English (%@)", java.text.NumberFormat.getIntegerInstance(LocalConfiguration.current.locales[0]).format(results.size)), color = colors.textSecondary, fontSize = 12.sp, modifier = Modifier.testTag("reader.search.section"))
                for ((resultIndex, result) in results.withIndex()) {
                    if (resultIndex > 0) {
                        HorizontalDivider(color = colors.divider.copy(alpha = 0.5f))
                    }
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onNavigate(result) }
                            .padding(vertical = 12.dp)
                            .testTag("reader.search.result.${result.canonicalId}"),
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = result.referenceDisplay.ifEmpty { result.providerHadithId },
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Medium,
                                color = colors.textPrimary,
                            )
                            if (result.snippet.isNotEmpty()) {
                                Text(
                                    text = result.snippet,
                                    fontSize = 13.sp,
                                    color = colors.textSecondary,
                                    maxLines = 3,
                                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                                    modifier = Modifier.padding(top = 2.dp),
                                )
                            }
                            Text(
                                text = nativeText("Sunnah.now English text"),
                                fontSize = 11.sp,
                                color = colors.textSecondary,
                                modifier = Modifier
                                    .padding(top = 4.dp)
                                    .testTag("reader.search.sourceLabel"),
                            )
                        }
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.NavigateNext,
                            contentDescription = null,
                            tint = colors.textSecondary,
                            modifier = Modifier.size(18.dp),
                        )
                    }
                }
            }
        }
    }
}

// Reader Bookmarks and Notes sheet (item 10)

internal enum class ReaderSavedTab(val title: String, val tag: String) {
    ALL("All", "all"),
    BOOKMARKS("Bookmarks", "bookmarks"),
    FAVORITES("Favorites", "favorites"),
    NOTES("Notes", "notes"),
}

@Composable
internal fun ReaderSavedSheet(
    items: List<com.hadithly.app.core.data.SavedItemEntry>,
    folders: List<com.hadithly.app.core.data.SavedFolder>,
    library: com.hadithly.app.core.data.UserLibraryModel,
    onOpen: (HadithRef) -> Unit,
    onEdit: () -> Unit,
    onDismiss: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    val app = com.hadithly.app.HadithlyApplication.instance()
    val preferences by app.preferences.preferences.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val clipboard = LocalClipboard.current
    val scope = rememberCoroutineScope()
    val actionScope = library.actionScope
    var removalScope by remember { mutableStateOf<String?>(null) }
    var tab by remember { mutableStateOf(ReaderSavedTab.BOOKMARKS) }
    var folderId by remember { mutableStateOf<String?>(null) }
    var folderMenuOpen by remember { mutableStateOf(false) }
    val loadState by library.loadState.collectAsStateWithLifecycle()
    var removal by remember { mutableStateOf<Triple<com.hadithly.app.features.saved.SavedFacet, com.hadithly.app.core.data.SavedItemEntry, HadithRef>?>(null) }
    val bookmarkRemovedLabel = stringResource(R.string.saved_bookmark_removed)
    val favoriteRemovedLabel = stringResource(R.string.saved_favorite_removed)
    val noteDeletedLabel = stringResource(R.string.saved_note_deleted)
    val folderDeletedTemplate = stringResource(R.string.saved_folder_deleted, "%1\$s")
    LaunchedEffect(actionScope) { removal = null; removalScope = null; folderId = null; folderMenuOpen = false }
    val visible = items.filter { item ->
        val matches = when (tab) {
            ReaderSavedTab.ALL -> true
            ReaderSavedTab.BOOKMARKS -> item.bookmarkCreatedAt != null
            ReaderSavedTab.FAVORITES -> item.favoriteCreatedAt != null
            ReaderSavedTab.NOTES -> item.noteContent != null
        }
        matches && (folderId == null || item.folderId == folderId)
    }.sortedByDescending { it.sortDate }
    fun remove(value: Triple<com.hadithly.app.features.saved.SavedFacet, com.hadithly.app.core.data.SavedItemEntry, HadithRef>) {
        if (!library.isActionCurrent(removalScope ?: actionScope)) return
        val (facet, item, ref) = value
        scope.launch {
        when (facet) {
            com.hadithly.app.features.saved.SavedFacet.BOOKMARK -> item.bookmarkCreatedAt?.let { at -> if (library.removeBookmark(ref, removalScope ?: actionScope).await()) library.undo.show(bookmarkRemovedLabel) { library.restoreBookmark(ref, at) } }
            com.hadithly.app.features.saved.SavedFacet.FAVORITE -> item.favoriteCreatedAt?.let { at -> if (library.removeFavorite(ref, removalScope ?: actionScope).await()) library.undo.show(favoriteRemovedLabel) { library.restoreFavorite(ref, at) } }
            com.hadithly.app.features.saved.SavedFacet.NOTE -> item.noteContent?.let { note -> if (library.deleteNote(ref, removalScope ?: actionScope).await()) library.undo.show(noteDeletedLabel) { library.restoreNote(ref, note, item.createdAt, item.updatedAt) } }
        }
        }
    }
    Column(Modifier.fillMaxWidth().fillMaxHeight().padding(20.dp).testTag("reader.saved.sheet")) {
        ReaderSheetHeader("Bookmarks & Notes", onDismiss, "reader.saved.close", onEdit = onEdit)
        if (folders.isNotEmpty()) Box {
            TextButton(onClick = { folderMenuOpen = true }) { Text(folders.firstOrNull { it.id == folderId }?.name ?: stringResource(R.string.saved_all_folders), color = colors.textSecondary) }
            DropdownMenu(expanded = folderMenuOpen, onDismissRequest = { folderMenuOpen = false }) {
                DropdownMenuItem(text = { Text(stringResource(R.string.saved_all_folders)) }, onClick = { folderId = null; folderMenuOpen = false })
                folders.forEach { folder ->
                    DropdownMenuItem(text = { Text(folder.name) }, onClick = { folderId = folder.id; folderMenuOpen = false })
                    DropdownMenuItem(text = { Text(stringResource(R.string.saved_delete_folder) + ": " + folder.name, color = colors.destructive) }, onClick = {
                        if (folderId == folder.id) folderId = null
                        library.deleteFolder(folder, folderDeletedTemplate.format(folder.name), actionScope); folderMenuOpen = false
                    })
                }
            }
        }
        if (items.isEmpty() && loadState == UserLibraryModel.LoadState.Loading) Box(Modifier.weight(1f).padding(top = 16.dp)) {
            com.hadithly.app.core.theme.ContentSkeleton(com.hadithly.app.core.theme.SkeletonKind.Rows, label = "Loading saved items")
        }
        else if (items.isEmpty() && loadState == UserLibraryModel.LoadState.Failed) Column(Modifier.weight(1f), verticalArrangement = Arrangement.Center) {
            Text(nativeText("Saved items could not load"), color = colors.textSecondary)
            TextButton(onClick = library::refresh) { Text(nativeText("Retry")) }
        }
        else if (visible.isEmpty()) com.hadithly.app.features.saved.SavedEmptyState(tab.ordinal, folderId != null, Icons.Filled.BookmarkBorder, Modifier.weight(1f).testTag("reader.saved.empty"))
        else LazyColumn(Modifier.weight(1f).testTag("reader.saved.rows"), verticalArrangement = Arrangement.spacedBy(10.dp)) { items(visible, key = { it.hadithId }) { item -> com.hadithly.app.features.saved.SharedSavedItemRow(item, folders, folderId == null, onOpen, { facet, saved, ref -> val request = Triple(facet, saved, ref); removalScope = actionScope; if (app.savedSafety.confirmsRemoval) removal = request else remove(request) }, { library.assignFolder(item.hadithId, it, actionScope) }, { ref -> scope.launch { clipboard.setClipEntry(ClipEntry(ClipData.newPlainText(ref.referenceDisplay, listOfNotNull(ref.arabicText, ref.englishText, ref.referenceDisplay).joinToString("\n\n")))) } }, { ref -> context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, "https://hadithly.app/hadith/${ref.collectionSlug}/${ref.hadithNumber}"), null)) }, onOpen,
            loadPreview = app.repository::loadSavedPreview,
            preferences = preferences,
            loadTranslation = app.repository::savedPreviewTranslation,
        ) } }
        com.hadithly.app.features.saved.SavedUndoBanner(testTag = "reader.saved.undoBanner", controller = library.undo)
        com.hadithly.app.features.saved.SavedFilterBar(tab.ordinal, { tab = ReaderSavedTab.entries[it] }, "reader.saved.tab", Modifier.padding(top = 8.dp))
    }
    removal?.let { request -> AlertDialog(onDismissRequest = { removal = null }, title = { Text(nativeText("Remove saved item?")) }, text = { Text(stringResource(R.string.saved_removal_undo_message)) }, confirmButton = { TextButton(onClick = { remove(request); removal = null }) { Text(nativeText("Remove")) } }, dismissButton = { Column { TextButton(onClick = { app.savedSafety.confirmsRemoval = false; remove(request); removal = null }) { Text(nativeText("Remove and don't ask again")) }; TextButton(onClick = { removal = null }) { Text(nativeText("Cancel")) } } }) }
}
