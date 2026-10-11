@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.hadithly.app.features.reader

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
import androidx.compose.foundation.layout.Column
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
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.automirrored.filled.NavigateBefore
import androidx.compose.material.icons.automirrored.filled.NavigateNext
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.BookmarkBorder
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FormatSize
import androidx.compose.material.icons.filled.Note
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.AlertDialog
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
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.window.Dialog
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
import androidx.compose.ui.semantics.clearAndSetSemantics
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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.debounce
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
        )
    }
    val state by viewModel.state.collectAsStateWithLifecycle()
    val sessions by com.clerk.api.Clerk.sessionsFlow.collectAsStateWithLifecycle()
    LaunchedEffect(sessions.map { it.id }) { viewModel.resetTranslationRequestsForAccount() }
    DisposableEffect(viewModel) {
        onDispose { viewModel.saveCurrentProgress() }
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

    fun closeReader() {
        viewModel.saveCurrentProgress()
        onClose()
    }
    BackHandler(enabled = !showContents && !showSettings, onBack = ::closeReader)

    // Round 7: the themed reader palette drives EVERY reader surface —
    // the page, the reader menu, and all sheets/dialogs presented from the
    // reader (contents, settings, bookmark, search, saved, paywall) — in
    // all four palettes, never the global app theme.
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
                    arabicFontSize = preferences.arabicFontSize,
                    preferences = preferences,
                    onOpenContents = { showContents = true },
                    onOpenSettings = { showSettings = true },
                    onShowPaywall = { showQuotaPaywall = true },
                    onClose = ::closeReader,
                    onOpenSaved = onOpenSaved,
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
            containerColor = colors.surface,
        ) {
            SettingsSheet(
                preferences = preferences,
                language = state.language,
                onLanguage = { viewModel.setLanguage(it) },
                onArabicFontSize = app.preferences::setArabicFontSize,
                onTheme = app.preferences::setReaderTheme,
                onArabicFont = app.preferences::setArabicFont,
                onVisibility = { arabic: Boolean?, translation: Boolean? ->
                    app.preferences.setVisibility(arabic = arabic, translation = translation)
                },
                onDismiss = { showSettings = false },
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
    arabicFontSize: Float,
    preferences: ReaderPreferences,
    onOpenContents: () -> Unit,
    onOpenSettings: () -> Unit,
    onShowPaywall: () -> Unit,
    onClose: () -> Unit,
    onOpenSaved: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    val androidView = LocalView.current
    var readerMenuExpanded by remember { mutableStateOf(false) }
    var showSearch by remember { mutableStateOf(false) }
    var showReaderSaved by remember { mutableStateOf(false) }
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

    // Round 6: the status bar stays ALWAYS visible (no programmatic
    // hiding). The page is full-bleed edge-to-edge into the system-bar
    // zones (pre-round-4 behavior); the bottom chrome sits above the
    // navigation bar — toggling chrome never moves the page.
    // Round 7: toggling focused↔unfocused animates ONLY the chrome
    // elements (corner label, progress pills/bar, back/menu buttons) with
    // a fade + scale (~200ms, snapped when animator-duration-scale is 0).
    // Page content never moves or re-composes layout.
    val focused = !state.chromeVisible
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

    // Intra-page scroll fraction drives the dynamic page bars (item 6).
    // Reset on every page turn; ReaderPage reports (page, fraction) pairs
    // so a stale late emission cannot move another page's bar.
    var pageScroll by remember { mutableStateOf(0 to 0f) }
    LaunchedEffect(pagerState.currentPage) {
        pageScroll = pagerState.currentPage to 0f
    }

    val totalPages = viewModel.totalPages()
    val intraPageFraction = if (pageScroll.first == state.pageIndex) pageScroll.second else 0f
    val dynamicPageFraction = focusedProgressFraction(
        pageIndex = state.pageIndex,
        totalPages = totalPages,
        intraPageFraction = intraPageFraction,
    )
    val volumeFraction = volumeProgressFraction(
        volumeCount = state.volumes.size,
        selectedIndex = state.volumes.indexOfFirst { it.volumeId == state.selectedVolumeId },
    )
    // Unfocused pills (Sajda `208 page` + `11 juz` style): the Page pill
    // fills with the intra-page scroll fraction; the Volume pill fills with
    // the current page fraction within the volume (static outline fraction
    // only until the backend reports a page total).
    val unfocusedPageFill = pagePillFillFraction(intraPageFraction)
    val unfocusedVolumeFill = (
        volumePillFillFraction(state.pageIndex, totalPages, intraPageFraction)
            ?: volumeFraction ?: 0.0
        )
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
            onOutwardEdgeTurn = ::turnPage,
            // A user horizontal drag collapses to focused immediately (no
            // haptic) and closes the menu. Programmatic turns settle through
            // onPageSettled, which collapses there.
            onUserDragStart = {
                collapseToFocusedAndCloseMenu()
            },
            modifier = Modifier.fillMaxSize(),
        ) { pageIndex ->
                val pages = state.pages
                // Stable per-page identity: volume plus the backend pageKey
                // when loaded, the index otherwise. The key never involves
                // the settled pageIndex, so a settle never re-creates the
                // current page composition. The model's one landing command
                // is the only vertical-scroll authority. The pager's neighbor compositions
                // (beyondViewportPageCount) then survive list appends and the
                // outgoing page never drops mid-gesture (no flicker); a
                // settle-or-cancel just reuses the kept composition.
                // Round 5: the items snapshot is remembered against the page
                // identity, so an unrelated state change mid-gesture (pills,
                // translations, progress) can never rebind neighbor content
                // while the swipe is in flight. A real page replacement
                // (placeholder load, volume switch) changes identity and
                // re-resolves exactly once.
                val page = pages.getOrNull(pageIndex)
                key("${state.selectedVolumeId}:${page?.pageKey ?: "page-$pageIndex"}") {
                    val stableHadiths = remember(page) { page?.items ?: emptyList() }
                    // Round 8: end-of-page pills resolve per pager slot from
                    // already-cached synchronous sources (this slot's index,
                    // the loaded pages list, the outline). Keyed on those —
                    // never on the settled pageIndex — so settling a swipe
                    // recomposes no pill and nothing arrives a frame late.
                    val pagePillState = remember(pageIndex, pages, state.volumes, state.selectedVolumeId) {
                        pagePillsForPage(pageIndex, pages, state.volumes, state.selectedVolumeId)
                    }
                    ReaderPage(
                        viewModel = viewModel,
                        state = state,
                        hadiths = stableHadiths,
                        arabicFontSize = arabicFontSize,
                        preferences = preferences,
                        pagingPolicy = pagingPolicy,
                        pageIndex = pageIndex,
                        pillState = pagePillState,
                        verticalLanding = state.verticalLanding,
                        isSentinel = pageIndex >= pages.size,
                        // Round 7: the inline corner label rides the chrome
                        // fade+scale through graphicsLayer — always composed,
                        // so the page layout never moves.
                        chromeAlpha = chromeAlpha,
                        chromeScale = chromeScale,
                        onFollowPill = viewModel::followPill,
                        // Round 7: the tap toggle (and its single tick) fires
                        // only on a confirmed tap — up with minimal movement
                        // and a short duration. A touch that becomes a
                        // drag/swipe/scroll never toggles and never ticks.
                        onTap = {
                            ReaderHaptics.perform(androidView, ReaderHapticKind.TAP_TOGGLE)
                            viewModel.toggleChrome()
                        },
                        onUserScroll = ::collapseToFocusedAndCloseMenu,
                        onPageScrollFraction = { page, fraction ->
                            pageScroll = page to fraction
                        },
                        onShowPaywall = onShowPaywall,
                    )
                }
        }

        if (!showReaderSaved) {
            com.hadithly.app.features.saved.SavedUndoBanner(
                Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(horizontal = 20.dp, vertical = 80.dp),
                testTag = "reader.undoBanner",
            )
        }

        // Round 7, focused: ONE 4dp narrow dynamic PAGE bar, ~1/4 width,
        // centered below the (always visible) status bar. ALWAYS rendered
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
        AnimatedVisibility(
            visible = state.chromeVisible,
            enter = fadeIn(chromeAnim) + scaleIn(chromeAnim, initialScale = 0.96f),
            exit = fadeOut(chromeAnim) + scaleOut(chromeAnim, targetScale = 0.96f),
            modifier = Modifier.align(Alignment.TopCenter),
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.statusBarsPadding().padding(top = 6.dp),
            ) {
                ReaderProgressPill(
                    number = "${state.pageIndex + 1}",
                    suffix = "page",
                    fraction = unfocusedPageFill.toDouble(),
                    testTag = "reader.unfocusedPageBar",
                    reduceMotion = reduceMotion,
                )
                if (unfocusedVolumeNumber != null) {
                    ReaderProgressPill(
                        number = "$unfocusedVolumeNumber",
                        suffix = stringResource(R.string.reader_volume_pill_suffix),
                        fraction = unfocusedVolumeFill,
                        testTag = "reader.unfocusedVolumeBar",
                        reduceMotion = reduceMotion,
                    )
                }
            }
        }

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
                            readerMenuExpanded = false
                            onOpenContents()
                        },
                        onSaved = {
                            readerMenuExpanded = false
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
            Dialog(
                onDismissRequest = { showBookmarkPlacement = false },
            ) {
                BookmarkPlacementSheet(
                    targets = placementTargets,
                    isBookmarked = viewModel::isBookmarked,
                    onChoose = { choosePlacement(it) },
                    onDismiss = { showBookmarkPlacement = false },
                )
            }
        }

        if (showSearch) {
            // Round 6: default half/full behavior (no forced expansion);
            // the inner column fills the allotted height instead.
            ModalBottomSheet(
                onDismissRequest = { showSearch = false },
                containerColor = colors.surface,
            ) {
                ReaderSearchSheet(
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
                UnifiedReaderSavedSheet(
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
private fun ReaderChromeCircle(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit) {
    val colors = LocalHadithlyColors.current
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier.size(52.dp).background(colors.surface.copy(alpha = 0.98f), CircleShape).clickable(onClick = onClick).semantics { contentDescription = label },
    ) { Icon(icon, null, tint = colors.textPrimary, modifier = Modifier.size(24.dp)) }
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
    val view = LocalView.current
    fun tapped(item: () -> Unit) {
        ReaderHaptics.perform(view, ReaderHapticKind.MENU_ITEM)
        item()
    }
    Column(
        verticalArrangement = Arrangement.spacedBy(6.dp),
        // The parent chrome column aligns End: this 2/3-width stack docks
        // to the trailing edge like the Sajda menu.
        modifier = Modifier.fillMaxWidth(0.66f).testTag("reader.menu"),
    ) {
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
        // Bottom row: icon-only, equal size — no text. Active bookmark:
        // ONLY the icon turns amber; the background keeps default contrast
        // (never full-yellow).
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            ReaderMenuIconButton(
                icon = if (isPositionedBookmarked) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder,
                contentDescription = if (positionedReference != null) {
                    "Bookmark $positionedReference"
                } else {
                    "Bookmark current hadith"
                },
                iconTint = if (isPositionedBookmarked) LocalHadithlyColors.current.bookmark else null,
                onClick = { tapped(onBookmark) },
                modifier = Modifier.weight(1f).height(56.dp),
                testTag = "reader.menu.bookmark",
            )
            ReaderMenuIconButton(
                icon = Icons.Filled.Search,
                contentDescription = "Search",
                onClick = { tapped(onSearch) },
                modifier = Modifier.weight(1f).height(56.dp),
                testTag = "reader.menu.search",
            )
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
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .background(colors.surface.copy(alpha = 0.98f), RoundedCornerShape(18.dp))
            .clickable(onClick = onClick)
            .semantics { this.contentDescription = contentDescription }
            .then(if (testTag != null) Modifier.testTag(testTag) else Modifier),
    ) {
        Icon(icon, null, tint = iconTint ?: colors.textSecondary, modifier = Modifier.size(22.dp))
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
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
            .fillMaxWidth()
            .background(colors.surface.copy(alpha = 0.98f), RoundedCornerShape(18.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 12.dp)
            .then(if (testTag != null) Modifier.testTag(testTag) else Modifier),
    ) {
        Column(Modifier.weight(1f)) {
            Text(
                title,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                color = colors.textPrimary,
                maxLines = 1,
                overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
            )
            Text(
                subtitle,
                fontSize = 12.sp,
                color = colors.textSecondary,
                maxLines = 1,
                overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
            )
        }
        Icon(icon, null, tint = iconTint ?: colors.textSecondary, modifier = Modifier.size(22.dp))
    }
}

@Composable
internal fun DirectionAwareHorizontalPager(
    state: PagerState,
    policy: ReaderPagingPolicy,
    onOutwardEdgeTurn: ((ReaderPageTurn) -> Boolean)? = null,
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
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
        HorizontalPager(
            state = state,
            reverseLayout = policy.reverseLayout,
            // Neighbors stay rendered during drags so a mid-gesture
            // cancel-back never flashes an empty page.
            beyondViewportPageCount = 1,
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
    pillState: ReaderPagePills.State,
    verticalLanding: ReaderVerticalLandingRequest?,
    isSentinel: Boolean,
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
    var citationsTranslation by remember { mutableStateOf<ReaderTranslation?>(null) }
    var sourceHadith by remember { mutableStateOf<ReaderHadith?>(null) }
    var noteTarget by remember { mutableStateOf<ReaderHadith?>(null) }
    var submissionTarget by remember { mutableStateOf<Pair<ReaderHadith, ReaderTranslation?>?>(null) }
    var reportTarget by remember { mutableStateOf<Pair<ReaderHadith, ReaderTranslation>?>(null) }
    val landing = verticalLanding?.takeIf {
        it.page == ReaderVerticalLandingPage(state.selectedVolumeId.orEmpty(), pageIndex)
    }
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
    val arabicOnly = preferences.arabicVisible && !preferences.translationVisible
    val localizedVolumeName: (Int) -> String = { number ->
        resContext.getString(R.string.reader_volume_title, number)
    }
    val cornerTitle: String? = selectedVolume?.title?.let { title ->
        volumeTitleForDisplay(title, arabicOnly, localizedVolumeName)
    }
    // Round 8: the range resolves from already-cached synchronous sources
    // (the outline counts plus the loaded pages list) and latches per
    // volume the first time it computes — a later prefetch append can never
    // flip `Title: a–b` back to `Title` for a frame. Single-line slot, so
    // even the first arrival never changes height.
    val latchedRanges = remember { mutableMapOf<String, Pair<Int, Int>>() }
    val freshRange = remember(state.volumes, state.selectedVolumeId, state.pages) {
        val volumeId = state.selectedVolumeId ?: return@remember null
        if (!ReaderViewModel.isVolumeFullyCached(state.pages)) return@remember null
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
    LaunchedEffect(listState) {
        var userDragging = false
        launch {
            listState.interactionSource.interactions.collect { interaction ->
                userDragging = interaction is DragInteraction.Start
            }
        }
        snapshotFlow { listState.isScrollInProgress }.collect { scrolling ->
            if (scrolling && userDragging) onUserScroll()
        }
    }

    // This is the only vertical-scroll writer. A command waits through a
    // sentinel/unloaded page, then applies once the matching list exists.
    LaunchedEffect(landing?.token, hadiths.firstOrNull()?._id, pageIndex) {
        val request = landing ?: return@LaunchedEffect
        if (hadiths.isEmpty()) return@LaunchedEffect
        when (val destination = request.landing) {
            ReaderVerticalLanding.Header -> listState.scrollToItem(0, 0)
            is ReaderVerticalLanding.Semantic -> {
                val itemIndex = hadiths.indexOfFirst {
                    it.providerHadithId == destination.providerHadithId
                }.takeIf { it >= 0 }?.plus(1) ?: return@LaunchedEffect
                listState.scrollToItem(itemIndex)
                if (destination.normalizedOffset > 0.0) {
                    withFrameNanos { }
                    val size = listState.layoutInfo.visibleItemsInfo
                        .firstOrNull { it.index == itemIndex }
                        ?.size
                        ?: return@LaunchedEffect
                    listState.scrollToItem(itemIndex, (size * destination.normalizedOffset).roundToInt())
                }
            }
        }
        viewModel.acknowledgeVerticalLanding(request)
    }

    // Intra-page scroll fraction for the dynamic page bars: leading item
    // plus its consumed offset over the page's item count.
    LaunchedEffect(listState, hadiths) {
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
            .collect { onPageScrollFraction(pageIndex, it) }
    }

    LaunchedEffect(listState, hadiths, state.pageIndex == pageIndex) {
        if (state.pageIndex != pageIndex || hadiths.isEmpty()) return@LaunchedEffect
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
            .debounce(500)
            .collect { (index, offset, size) ->
                viewModel.captureStableScroll(
                    hadiths = hadiths,
                    leadingIndex = readerHadithIndex(index, hadiths.size) ?: return@collect,
                    rawPageOffset = (-offset).coerceAtLeast(0).toDouble(),
                    normalizedOffset = (-offset).coerceAtLeast(0).toDouble() / size.coerceAtLeast(1),
                )
            }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .confirmedTapGesture { onTap() },
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
                // Round 7 full-bleed (pre-round-4 behavior): edge-to-edge
                // is on and the page flows INTO the system-bar zones with
                // no status/navigation inset on the list — exactly as
                // before commit 6409bbd. The status bar stays visible; the
                // chrome overlays carry their own statusBars/
                // navigationBars padding.
                modifier = Modifier.fillMaxSize(),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(
                    start = 22.dp, end = 22.dp,
                    // Reader pages never sit below an iPhone/Android cutout.
                    // Keep this stable across chrome states so page turns do
                    // not shift the reading position.
                    top = 56.dp,
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

/**
 * The unfocused progress pill (Sajda `208 page` / `11 juz` style): a short
 * capsule with a neutral fill plus a bold number and a lighter suffix
 * (`Page N`, `Volume N`). Non-interactive, hidden from traversal.
 */
@Composable
private fun ReaderProgressPill(
    number: String,
    suffix: String,
    fraction: Double,
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
        label = "readerPillFill",
    )
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .height(32.dp)
            .clip(RoundedCornerShape(50))
            .background(colors.surface.copy(alpha = 0.92f))
            .testTag(testTag),
    ) {
        // Round 8: the fill occupies the FULL pill height — no top/bottom
        // inset, only a small horizontal inset — clipped to the pill
        // capsule, so low fills stay a rounded nub and never show square
        // corners. The fill fraction still animates (see above).
        Box(
            modifier = Modifier
                .align(Alignment.CenterStart)
                .fillMaxHeight()
                .padding(horizontal = 3.dp)
                .fillMaxWidth(animatedFraction)
                .clip(RoundedCornerShape(50))
                .background(colors.textSecondary.copy(alpha = 0.22f)),
        )
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
            .background(colors.divider.copy(alpha = 0.6f))
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
    val hapticView = LocalView.current
    var menuExpanded by remember { mutableStateOf(false) }
    val app = com.hadithly.app.HadithlyApplication.instance()
    var pendingRemoval by remember { mutableStateOf<String?>(null) }
    val bookmarkRemovedLabel = stringResource(R.string.saved_bookmark_removed)
    val favoriteRemovedLabel = stringResource(R.string.saved_favorite_removed)
    val savedRef = HadithRef(hadith._id, hadith.collectionSlug, hadith.collectionName, hadith.volumeId, hadith.providerHadithId, hadith.arabicText, hadith.englishText, hadith.referenceDisplay)

    fun toggleBookmarkSafely() {
        if (deps.isBookmarked) {
            val createdAt = app.library.savedItems.value.firstOrNull { it.hadithId == hadith._id }?.bookmarkCreatedAt
            deps.onToggleBookmark()
            if (createdAt != null) app.library.undo.show(bookmarkRemovedLabel) { app.library.restoreBookmark(savedRef, createdAt) }
        } else deps.onToggleBookmark()
    }
    fun toggleFavoriteSafely() {
        if (deps.isFavorite) {
            val createdAt = app.library.savedItems.value.firstOrNull { it.hadithId == hadith._id }?.favoriteCreatedAt
            deps.onToggleFavorite()
            if (createdAt != null) app.library.undo.show(favoriteRemovedLabel) { app.library.restoreFavorite(savedRef, createdAt) }
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
                onLongClick = {
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
                    onRetry = onRetry,
                    onShowCitations = onShowCitations,
                    onShowPaywall = onShowPaywall,
                )
                allowance?.let {
                    Text(stringResource(R.string.q1_remaining, it.remaining.toInt(), it.limit.toInt()), fontSize = 12.sp, color = colors.textSecondary, modifier = Modifier.testTag("reader.translationAllowance"))
                    it.retryAt?.let { retry ->
                        val date = java.text.DateFormat.getDateTimeInstance(java.text.DateFormat.SHORT, java.text.DateFormat.SHORT).format(java.util.Date(retry.toLong()))
                        Text(stringResource(R.string.q1_retry_at, date), fontSize = 12.sp, color = colors.textSecondary, modifier = Modifier.testTag("reader.translationRetryAt"))
                    }
                }
            }
        }

        // R6A fix: no bottom label — the top header is the single per-hadith
        // header (source sheet tap lives there; copy/share payloads keep
        // the full source line via ReaderShare).
    }
    if (pendingRemoval != null) AlertDialog(onDismissRequest = { pendingRemoval = null }, title = { Text("Remove saved item?") }, text = { Text(stringResource(R.string.saved_removal_undo_message)) }, confirmButton = { TextButton(onClick = { if (pendingRemoval == "bookmark") toggleBookmarkSafely() else toggleFavoriteSafely(); pendingRemoval = null }) { Text("Remove") } }, dismissButton = { Column { TextButton(onClick = { app.savedSafety.confirmsRemoval = false; if (pendingRemoval == "bookmark") toggleBookmarkSafely() else toggleFavoriteSafely(); pendingRemoval = null }) { Text("Remove and don't ask again") }; TextButton(onClick = { pendingRemoval = null }) { Text("Cancel") } } })
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
        for (marker in savedMiniMarkers(isBookmarked, isFavorite, hasNote)) {
            Spacer(modifier = Modifier.width(7.dp))
            Icon(
                imageVector = when (marker) {
                    SavedMiniMarker.BOOKMARK -> Icons.Filled.Bookmark
                    SavedMiniMarker.FAVORITE -> Icons.Filled.Favorite
                    SavedMiniMarker.NOTE -> Icons.Filled.Note
                },
                contentDescription = when (marker) {
                    SavedMiniMarker.BOOKMARK -> "Bookmarked"
                    SavedMiniMarker.FAVORITE -> "Favorited"
                    SavedMiniMarker.NOTE -> "Has note"
                },
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
                color = colors.interactive,
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
internal fun TranslationSection(
    hadith: ReaderHadith,
    translationState: TranslationUiState?,
    language: String,
    onRetry: () -> Unit,
    onShowCitations: (ReaderTranslation) -> Unit,
    onShowPaywall: () -> Unit,
) {
    val colors = LocalHadithlyColors.current

    if (language == "en") {
        val stored = (translationState as? TranslationUiState.Loaded)?.translation
        val english = hadith.englishText
        if (stored != null) {
            TranslationText(text = stored.translation, storedTranslation = stored, onShowCitations = { onShowCitations(stored) })
        } else if (!english.isNullOrEmpty()) {
            TranslationText(text = english, storedTranslation = null, onShowCitations = {})
        } else {
            Text("No English translation available yet.", fontSize = 12.sp, color = colors.textSecondary)
        }
        return
    }

    when (translationState) {
        null -> TextButton(onClick = onRetry, modifier = Modifier.heightIn(min = 48.dp).testTag("reader.generateTranslation")) {
            Text(stringResource(R.string.q1_generate), fontSize = 12.sp, color = colors.interactive)
        }
        is TranslationUiState.Loading -> Row(
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
                text = stringResource(R.string.q1_quota_exhausted),
                actionTitle = "See plans",
                onAction = onShowPaywall,
            )
            is TranslationFailure.Failed -> Column {
                translationState.failure.retryAt?.let { retry ->
                    val date = java.text.DateFormat.getDateTimeInstance(java.text.DateFormat.SHORT, java.text.DateFormat.SHORT).format(java.util.Date(retry.toLong()))
                    Text(stringResource(R.string.q1_retry_at, date), fontSize = 12.sp, color = colors.textSecondary)
                }
                TextButton(onClick = onRetry) {
                    Text("AI translation unavailable · retry", fontSize = 12.sp, color = colors.textSecondary)
                }
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
                trailing = stringResource(R.string.e3_contributor_label),
                onClick = onShowCitations,
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
            .background(colors.interactiveSoft, RoundedCornerShape(50))
            .clickable(enabled = onClick != null) { onClick?.invoke() }
            .heightIn(min = 48.dp)
            .padding(horizontal = 10.dp, vertical = 5.dp),
    ) {
        Icon(icon, contentDescription = null, tint = colors.interactive, modifier = Modifier.size(12.dp))
        Text(main, fontSize = 11.sp, fontWeight = FontWeight.Bold, color = colors.interactive)
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
                Text(actionTitle, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = colors.interactive)
            }
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
        item {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        "Contents",
                        fontSize = 20.sp,
                        fontWeight = FontWeight.Bold,
                        color = colors.textPrimary,
                    )
                    if (collectionName.isNotEmpty()) {
                        Text(
                            collectionName,
                            fontSize = 13.sp,
                            color = colors.textSecondary,
                        )
                    }
                }
                IconButton(
                    onClick = onDismiss,
                    modifier = Modifier.size(48.dp).testTag("reader.contents.close"),
                ) {
                    Icon(
                        Icons.Filled.Close,
                        contentDescription = "Close contents",
                        tint = colors.textSecondary,
                        modifier = Modifier.size(20.dp),
                    )
                }
            }
        }
        item(key = "contents-jump") {
            Column(modifier = Modifier.padding(top = 4.dp)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    OutlinedTextField(
                        value = jumpInput,
                        onValueChange = {
                            jumpInput = it
                            jumpError = null
                        },
                        label = { Text("Hadith number", color = colors.textSecondary) },
                        placeholder = { Text("e.g. 57", color = colors.textSecondary) },
                        singleLine = true,
                        isError = jumpError != null,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                        keyboardActions = KeyboardActions(onDone = { submitJump() }),
                        colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = colors.interactive,
                            unfocusedBorderColor = colors.divider,
                            focusedTextColor = colors.textPrimary,
                            unfocusedTextColor = colors.textPrimary,
                            cursorColor = colors.interactive,
                            focusedContainerColor = colors.surfaceElevated,
                            unfocusedContainerColor = colors.surfaceElevated,
                            errorBorderColor = colors.favorite,
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
                            "Go",
                            fontSize = 16.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = if (jumpInput.isNotBlank()) colors.interactive else colors.textSecondary,
                        )
                    }
                }
                Text(
                    text = jumpError ?: "Jump to a hadith number, e.g. 57.",
                    fontSize = 12.sp,
                    color = colors.textSecondary,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
        }
        item(key = "contents-volumes-label") {
            Text(
                "VOLUMES",
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
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .clickable { onSelect(volume.volumeId) }
                            .padding(vertical = 12.dp),
                    ) {
                        Text(
                            text = volume.title,
                            fontSize = 16.sp,
                            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
                            color = if (selected) colors.interactive else colors.textPrimary,
                            maxLines = 1,
                            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                        )
                        // Plain-row subtitle: the source-provided first
                        // chapter title only (the expanded chapter list
                        // already names every chapter, so the first chapter
                        // is never repeated here); otherwise the count line.
                        val subtitle = volume.firstChapterTitle?.trim()
                            ?.takeIf { it.isNotEmpty() && it != volume.title }
                        Text(
                            text = subtitle ?: "${volume.hadithCount.toInt()} hadiths",
                            fontSize = 12.sp,
                            color = colors.textSecondary,
                            maxLines = 1,
                            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                            modifier = Modifier.padding(top = 2.dp),
                        )
                    }
                    Text(
                        text = volume.hadithCount.toInt().toString(),
                        fontSize = 14.sp,
                        color = colors.textSecondary,
                    )
                    Spacer(modifier = Modifier.width(4.dp))
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
                    } else {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.NavigateNext,
                            contentDescription = null,
                            tint = colors.textSecondary,
                            modifier = Modifier.size(18.dp),
                        )
                    }
                }
                if (expanded) {
                    for ((chapterIndex, chapter) in volume.chapters.withIndex()) {
                        if (chapterIndex > 0) {
                            HorizontalDivider(
                                color = colors.divider.copy(alpha = 0.5f),
                                modifier = Modifier.padding(start = 12.dp),
                            )
                        }
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onSelectChapter(volume.volumeId, chapter) }
                                .padding(start = 12.dp, top = 10.dp, bottom = 10.dp, end = 4.dp)
                                .testTag("reader.contents.chapter.${volume.volumeId}.${chapter.firstProviderHadithId}"),
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = chapter.title,
                                    fontSize = 15.sp,
                                    color = colors.textPrimary,
                                    maxLines = 2,
                                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
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
                            }
                            Text(
                                text = chapter.firstProviderHadithId,
                                fontSize = 13.sp,
                                color = colors.textSecondary,
                            )
                            Spacer(modifier = Modifier.width(8.dp))
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
            HorizontalDivider(color = colors.divider.copy(alpha = 0.5f))
        }
    }
}

// Reader settings sheet

/**
 * Reader settings (R4; Sajda plain-row restyle in the R6 fix round):
 * visibility chips, theme, Arabic face and size with a live preview, and
 * the translation language. Plain caps section labels, simple
 * title+subtitle+chevron rows, minimal dividers — no heavy cards. Direct
 * controls, close to the text; account and global settings stay in the
 * Settings tab. No Quran-only modes or tabs.
 */
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
) {
    val colors = LocalHadithlyColors.current
    val view = LocalView.current
    var detail by remember { mutableStateOf<ReaderSettingsDetail?>(null) }

    // The all-hidden state is rejected by the store (returns false): answer
    // with the native reject haptic so the refusal is felt.
    fun attemptVisibility(arabic: Boolean?, translation: Boolean?) {
        if (!onVisibility(arabic, translation)) {
            ReaderHaptics.perform(view, ReaderHapticKind.REJECT_BOTH_HIDDEN)
        }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(start = 20.dp, top = 8.dp, end = 20.dp, bottom = 32.dp)
            .testTag("reader.settings.sheet"),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(
                detail?.title ?: "Settings",
                fontSize = 28.sp,
                fontWeight = FontWeight.SemiBold,
                color = colors.textPrimary,
                modifier = Modifier.weight(1f),
            )
            IconButton(
                onClick = onDismiss,
                modifier = Modifier.size(48.dp).background(colors.surfaceElevated, RoundedCornerShape(50)).testTag("reader.settings.close"),
            ) {
                Icon(
                    Icons.Filled.Close,
                    contentDescription = "Close settings",
                    tint = colors.textSecondary,
                    modifier = Modifier.size(20.dp),
                )
            }
        }

        if (detail == null) {
            SettingsSectionLabel("DISPLAY")
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                VisibilityPill("Arabic", preferences.arabicVisible, "reader.visibility.arabic") { attemptVisibility(!preferences.arabicVisible, null) }
                VisibilityPill("Translation", preferences.translationVisible, "reader.visibility.translation") { attemptVisibility(null, !preferences.translationVisible) }
            }
            Text("At least one text layer stays visible.", fontSize = 12.sp, color = colors.textSecondary, modifier = Modifier.padding(top = 6.dp))
            SettingsSectionLabel("SETTINGS")
            ReaderSettingsNavigationRow("Arabic font", "${preferences.arabicFont.wire} · ${preferences.arabicFontSize.roundToInt()} pt", "reader.settings.arabic") { detail = ReaderSettingsDetail.ARABIC }
            ReaderSettingsNavigationRow("Translation", language.uppercase(), "reader.settings.translation") { detail = ReaderSettingsDetail.TRANSLATION }
            ReaderSettingsNavigationRow("Color themes", preferences.readerTheme.wire.replaceFirstChar { it.uppercase() }, "reader.settings.appearance") { detail = ReaderSettingsDetail.APPEARANCE }
        } else {
            TextButton(onClick = { detail = null }, modifier = Modifier.height(44.dp)) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null, tint = colors.textSecondary)
                Text("Settings", color = colors.textSecondary)
            }
        if (detail == ReaderSettingsDetail.APPEARANCE) {
        SettingsSectionLabel("COLOR THEME")
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.padding(top = 4.dp),
        ) {
            for (theme in com.hadithly.app.core.preferences.ReaderTheme.entries) {
                val selected = (if (preferences.usesSeparateReaderTheme) preferences.readerTheme else preferences.appTheme) == theme
                val swatch = com.hadithly.app.core.theme.ReaderPalettes.resolved(theme, systemDark = true)
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier
                        .background(
                            if (selected) colors.interactiveSoft else androidx.compose.ui.graphics.Color.Transparent,
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
                        color = if (selected) colors.interactive else colors.textSecondary,
                        modifier = Modifier.padding(top = 4.dp),
                    )
                }
            }
        }
        }

        if (detail == ReaderSettingsDetail.ARABIC) {
        SettingsSectionLabel("ARABIC TYPE")
        Text(
            text = "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ",
            fontSize = preferences.arabicFontSize.sp,
            fontFamily = com.hadithly.app.core.theme.ArabicTypefaces.forFont(preferences.arabicFont),
            lineHeight = (preferences.arabicFontSize * 1.75).sp,
            color = colors.textPrimary,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 10.dp)
                .testTag("reader.typePreview"),
        )
        Row(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(bottom = 4.dp),
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

        val fontEntries = com.hadithly.app.core.preferences.ArabicFont.entries
        for ((fontIndex, font) in fontEntries.withIndex()) {
            val selected = preferences.arabicFont == font
            if (fontIndex > 0) {
                HorizontalDivider(color = colors.divider.copy(alpha = 0.5f))
            }
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .selectable(
                        selected = selected,
                        role = Role.RadioButton,
                        onClick = { onArabicFont(font) },
                    )
                    .padding(vertical = 10.dp)
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
                        tint = colors.interactive,
                        modifier = Modifier.size(18.dp),
                    )
                } else {
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

        if (detail == ReaderSettingsDetail.TRANSLATION) {
        SettingsSectionLabel("TRANSLATION LANGUAGE")
        Column {
            val languages = SupportedLanguages.all
            for ((languageIndex, languageEntry) in languages.withIndex()) {
                val (code, name) = languageEntry
                val selected = code == language
                if (languageIndex > 0) {
                    HorizontalDivider(color = colors.divider.copy(alpha = 0.5f))
                }
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .selectable(
                            selected = selected,
                            role = Role.RadioButton,
                            onClick = { onLanguage(code) },
                        )
                        .padding(vertical = 12.dp)
                        .testTag("reader.language.$code"),
                ) {
                    Text(name, fontSize = 15.sp, color = colors.textPrimary, modifier = Modifier.weight(1f))
                    if (selected) {
                        Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = colors.interactive, modifier = Modifier.size(18.dp))
                    } else {
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
    }
}

private enum class ReaderSettingsDetail(val title: String) {
    APPEARANCE("Color themes"), ARABIC("Arabic font"), TRANSLATION("Translation"),
}

@Composable
private fun ReaderSettingsNavigationRow(title: String, subtitle: String, testTag: String, onClick: () -> Unit) {
    val colors = LocalHadithlyColors.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().heightIn(min = 72.dp).clickable(onClick = onClick).testTag(testTag),
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, fontSize = 21.sp, fontWeight = FontWeight.Medium, color = colors.textPrimary)
            Text(subtitle, fontSize = 16.sp, color = colors.textSecondary, modifier = Modifier.padding(top = 4.dp))
        }
        Icon(Icons.AutoMirrored.Filled.NavigateNext, contentDescription = null, tint = colors.textSecondary, modifier = Modifier.size(24.dp))
    }
}

/** Plain caps section label shared by the Sajda-style reader sheets. */
@Composable
private fun SettingsSectionLabel(text: String) {
    val colors = LocalHadithlyColors.current
    Text(
        text = text,
        fontSize = 12.sp,
        fontWeight = FontWeight.SemiBold,
        color = colors.textSecondary,
        modifier = Modifier.padding(top = 20.dp, bottom = 4.dp),
    )
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
            .background(if (isOn) colors.interactiveSoft else colors.surfaceElevated, RoundedCornerShape(50))
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
            tint = if (isOn) colors.interactive else colors.textSecondary,
            modifier = Modifier.size(18.dp),
        )
        Text(
            title,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
            color = if (isOn) colors.interactive else colors.textSecondary,
        )
    }
}

// Citations sheet

@Composable
internal fun CitationsSheet(translation: ReaderTranslation) {
    val colors = LocalHadithlyColors.current
    Column(
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
    ) {
        Text("Sources", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)
        Text(
            text = translation.translation,
            fontSize = 15.sp,
            color = colors.textPrimary,
        )
        translation.sourceReferenceUrl?.let { url ->
            Text("Reference: $url", fontSize = 12.sp, color = colors.interactive)
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
            text = if (translation.source == "gemini_ai") "AI translations are generated with ${translation.aiModel ?: "an AI model"} and grounded in cited sources, but are not authoritative." else stringResource(R.string.e3_community_sources_message),
            fontSize = 11.sp,
            color = colors.textSecondary,
            modifier = Modifier.testTag(if (translation.source == "gemini_ai") "translation.sources.ai" else "translation.sources.community"),
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
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            TextButton(onClick = onCancel) { Text("Cancel", color = colors.textSecondary) }
            TextButton(
                onClick = {
                    val trimmed = content.trim()
                    if (trimmed.isNotEmpty()) onSave(trimmed)
                },
            ) { Text("Save", color = colors.interactive, fontWeight = FontWeight.Bold) }
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
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.surface, RoundedCornerShape(24.dp))
            .padding(start = 20.dp, end = 20.dp, top = 20.dp, bottom = 12.dp)
            .testTag("reader.bookmarkSheet"),
    ) {
        Text("Bookmark", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)
        PlacementRow(
            title = pageStartRow.title,
            subtitle = pageStartRow.subtitle,
            enabled = pageStartRow.enabled,
            bookmarked = pageStartRow.bookmarked,
            testTag = pageStartRow.testTag,
            onClick = { pageStartRow.target?.let(onChoose) },
        )
        HorizontalDivider(color = colors.divider.copy(alpha = 0.5f))
        PlacementRow(
            title = positionedRow.title,
            subtitle = positionedRow.subtitle,
            enabled = positionedRow.enabled,
            bookmarked = positionedRow.bookmarked,
            testTag = positionedRow.testTag,
            onClick = { positionedRow.target?.let(onChoose) },
        )
        HorizontalDivider(color = colors.divider.copy(alpha = 0.5f))
        TextButton(
            onClick = onDismiss,
            modifier = Modifier.align(Alignment.End).testTag(cancelRow.testTag),
        ) { Text(cancelRow.title, color = colors.textSecondary) }
    }
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
                text = title,
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
            contentDescription = if (bookmarked) "Bookmarked" else "Not bookmarked",
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
        Text("Search", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)
        OutlinedTextField(
            value = query,
            onValueChange = {
                query = it
                runSearch(it)
            },
            label = { Text("Search English text", color = colors.textSecondary) },
            leadingIcon = {
                Icon(Icons.Filled.Search, contentDescription = null, tint = colors.textSecondary)
            },
            singleLine = true,
            colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
                focusedBorderColor = colors.interactive,
                unfocusedBorderColor = colors.divider,
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
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CircularProgressIndicator(
                        color = colors.textSecondary,
                        modifier = Modifier.size(14.dp),
                        strokeWidth = 2.dp,
                    )
                    Text("Searching…", fontSize = 12.sp, color = colors.textSecondary)
                }
            }

            unavailable -> Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.fillMaxWidth().weight(1f),
            ) {
                Text(
                    "Search is unavailable offline.",
                    fontSize = 13.sp,
                    color = colors.textSecondary,
                )
            }

            query.isBlank() -> Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.fillMaxWidth().weight(1f),
            ) {
                Text(
                    "Type above to search the English text.",
                    fontSize = 13.sp,
                    color = colors.textSecondary,
                    modifier = Modifier.testTag("reader.search.hint"),
                )
            }

            results.isEmpty() -> Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.fillMaxWidth().weight(1f),
            ) {
                Text(
                    "No matches in Sunnah.now English text.",
                    fontSize = 13.sp,
                    color = colors.textSecondary,
                    modifier = Modifier.testTag("reader.search.empty"),
                )
            }

            else -> Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .testTag("reader.search.results"),
            ) {
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
                                text = "Sunnah.now English text",
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
    BOOKMARKS("Bookmarks", "bookmarks"),
    FAVORITES("Favorites", "favorites"),
    NOTES("Notes", "notes"),
}

@Composable
internal fun ReaderSavedSheet(
    bookmarks: List<SavedEntry>,
    favorites: List<SavedEntry>,
    notes: List<SavedEntry>,
    nowMillis: Long,
    onOpen: (HadithRef) -> Unit,
    onEdit: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    var tab by remember { mutableStateOf(ReaderSavedTab.BOOKMARKS) }
    val entries = when (tab) {
        ReaderSavedTab.BOOKMARKS -> bookmarks
        ReaderSavedTab.FAVORITES -> favorites
        ReaderSavedTab.NOTES -> notes
    }
    // Sajda `bookmarks tab` structure: segmented Bookmarks/Favorites/Notes
    // tabs, plain rows (amber icon + title + relative time + chevron),
    // minimal dividers, EDIT at the bottom end. The column fills the
    // allotted height (round 6: default half/full behavior, no forced
    // expansion) with the empty state centered — no dead blank region.
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .fillMaxHeight()
            .padding(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 16.dp)
            .testTag("reader.saved.sheet"),
    ) {
        Text(
            "Bookmarks & Notes",
            fontSize = 20.sp,
            fontWeight = FontWeight.Bold,
            color = colors.textPrimary,
        )
        Row(
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 12.dp)
                .background(colors.surfaceElevated, RoundedCornerShape(50))
                .padding(4.dp),
        ) {
            for (entry in ReaderSavedTab.entries) {
                val selected = tab == entry
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .weight(1f)
                        .background(
                            if (selected) colors.surface else androidx.compose.ui.graphics.Color.Transparent,
                            RoundedCornerShape(50),
                        )
                        .clickable { tab = entry }
                        .padding(vertical = 8.dp)
                        .testTag("reader.saved.tab.${entry.tag}"),
                ) {
                    Text(
                        entry.title,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Medium,
                        color = if (selected) colors.textPrimary else colors.textSecondary,
                    )
                }
            }
        }
        if (entries.isEmpty()) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.fillMaxWidth().weight(1f),
            ) {
                Text(
                    "Nothing saved here yet.",
                    fontSize = 13.sp,
                    color = colors.textSecondary,
                )
            }
        } else {
            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .testTag("reader.saved.rows"),
            ) {
                for ((entryIndex, entry) in entries.withIndex()) {
                    if (entryIndex > 0) {
                        HorizontalDivider(color = colors.divider.copy(alpha = 0.5f))
                    }
                    val ref = entry.hadith
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable(enabled = ref != null) { ref?.let(onOpen) }
                            .padding(vertical = 12.dp)
                            .testTag("reader.saved.row.${entry.rowId}"),
                    ) {
                        Box(
                            contentAlignment = Alignment.Center,
                            modifier = Modifier
                                .size(36.dp)
                                .background(
                                    when (tab) {
                                        ReaderSavedTab.FAVORITES -> colors.favorite
                                        ReaderSavedTab.NOTES -> colors.interactive
                                        ReaderSavedTab.BOOKMARKS -> colors.bookmark
                                    },
                                    RoundedCornerShape(10.dp),
                                ),
                        ) {
                            Icon(
                                imageVector = when (tab) {
                                    ReaderSavedTab.FAVORITES -> Icons.Filled.Favorite
                                    ReaderSavedTab.NOTES -> Icons.Filled.Note
                                    ReaderSavedTab.BOOKMARKS -> Icons.Filled.Bookmark
                                },
                                contentDescription = null,
                                tint = androidx.compose.ui.graphics.Color.White,
                                modifier = Modifier.size(18.dp),
                            )
                        }
                        Spacer(modifier = Modifier.width(12.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = ref?.referenceDisplay?.takeIf { it.isNotEmpty() }
                                    ?: "Saved hadith",
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Medium,
                                color = colors.textPrimary,
                            )
                            if (tab == ReaderSavedTab.NOTES && !entry.noteContent.isNullOrBlank()) {
                                Text(
                                    text = entry.noteContent,
                                    fontSize = 13.sp,
                                    color = colors.textSecondary,
                                    maxLines = 2,
                                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                                    modifier = Modifier.padding(top = 2.dp),
                                )
                            }
                            Text(
                                text = relativeTimeLabel(nowMillis, entry.sortDate),
                                fontSize = 11.sp,
                                color = colors.textSecondary,
                                modifier = Modifier.padding(top = 2.dp),
                            )
                        }
                        if (ref != null) {
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
        TextButton(
            onClick = onEdit,
            modifier = Modifier.align(Alignment.End).testTag("reader.saved.edit"),
        ) { Text("EDIT", color = colors.textSecondary, fontWeight = FontWeight.Bold) }
    }
}

@Composable
private fun UnifiedReaderSavedSheet(
    items: List<com.hadithly.app.core.data.SavedItemEntry>,
    folders: List<com.hadithly.app.core.data.SavedFolder>,
    library: com.hadithly.app.core.data.UserLibraryModel,
    onOpen: (HadithRef) -> Unit,
    onEdit: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    val app = com.hadithly.app.HadithlyApplication.instance()
    val context = LocalContext.current
    val clipboard = LocalClipboard.current
    val scope = rememberCoroutineScope()
    var tab by remember { mutableStateOf(ReaderSavedTab.BOOKMARKS) }
    var folderId by remember { mutableStateOf<String?>(null) }
    var folderMenu by remember { mutableStateOf<com.hadithly.app.core.data.SavedFolder?>(null) }
    var removal by remember { mutableStateOf<Triple<com.hadithly.app.features.saved.SavedFacet, com.hadithly.app.core.data.SavedItemEntry, HadithRef>?>(null) }
    val bookmarkRemovedLabel = stringResource(R.string.saved_bookmark_removed)
    val favoriteRemovedLabel = stringResource(R.string.saved_favorite_removed)
    val noteDeletedLabel = stringResource(R.string.saved_note_deleted)
    val folderDeletedTemplate = stringResource(R.string.saved_folder_deleted, "%1\$s")
    val visible = items.filter { item ->
        val matches = when (tab) {
            ReaderSavedTab.BOOKMARKS -> item.bookmarkCreatedAt != null
            ReaderSavedTab.FAVORITES -> item.favoriteCreatedAt != null
            ReaderSavedTab.NOTES -> item.noteContent != null
        }
        matches && (folderId == null || item.folderId == folderId)
    }.sortedByDescending { it.sortDate }
    fun remove(value: Triple<com.hadithly.app.features.saved.SavedFacet, com.hadithly.app.core.data.SavedItemEntry, HadithRef>) {
        val (facet, item, ref) = value
        when (facet) {
            com.hadithly.app.features.saved.SavedFacet.BOOKMARK -> item.bookmarkCreatedAt?.let { at -> library.toggleBookmark(ref); library.undo.show(bookmarkRemovedLabel) { library.restoreBookmark(ref, at) } }
            com.hadithly.app.features.saved.SavedFacet.FAVORITE -> item.favoriteCreatedAt?.let { at -> library.toggleFavorite(ref); library.undo.show(favoriteRemovedLabel) { library.restoreFavorite(ref, at) } }
            com.hadithly.app.features.saved.SavedFacet.NOTE -> item.noteContent?.let { note -> library.deleteNote(ref); library.undo.show(noteDeletedLabel) { library.restoreNote(ref, note, item.createdAt, item.updatedAt) } }
        }
    }
    Column(Modifier.fillMaxWidth().fillMaxHeight().padding(20.dp).testTag("reader.saved.sheet")) {
        Text("Bookmarks & Notes", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)
        Row(Modifier.fillMaxWidth().padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) { ReaderSavedTab.entries.forEach { candidate -> TextButton(onClick = { tab = candidate }, modifier = Modifier.weight(1f).testTag("reader.saved.tab.${candidate.tag}")) { Text(candidate.title, color = if (tab == candidate) colors.interactive else colors.textSecondary) } } }
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            TextButton(onClick = { folderId = null }) { Text(stringResource(R.string.saved_all_folders), color = if (folderId == null) colors.interactive else colors.textSecondary) }
            folders.forEach { folder ->
                val selected = folderId == folder.id
                Row(Modifier.combinedClickable(onClick = { folderId = folder.id }, onLongClick = { folderMenu = folder }).background(if (selected) colors.interactiveSoft else colors.surfaceElevated, RoundedCornerShape(50)).padding(horizontal = 12.dp, vertical = 8.dp)) {
                    Text(folder.name, color = if (selected) colors.interactive else colors.textSecondary)
                }
                DropdownMenu(expanded = folderMenu?.id == folder.id, onDismissRequest = { folderMenu = null }) {
                    DropdownMenuItem(text = { Text(stringResource(R.string.saved_delete_folder)) }, onClick = {
                        if (folderId == folder.id) folderId = null
                        library.deleteFolder(folder, folderDeletedTemplate.format(folder.name))
                        folderMenu = null
                    })
                }
            }
        }
        if (visible.isEmpty()) Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) { Text("Nothing saved here yet.", color = colors.textSecondary) }
        else Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) { visible.forEach { item -> com.hadithly.app.features.saved.SharedSavedItemRow(item, folders, folderId == null, onOpen, { facet, saved, ref -> val request = Triple(facet, saved, ref); if (app.savedSafety.confirmsRemoval) removal = request else remove(request) }, { library.assignFolder(item.hadithId, it) }, { ref -> scope.launch { clipboard.setClipEntry(ClipEntry(ClipData.newPlainText(ref.referenceDisplay, listOfNotNull(ref.arabicText, ref.englishText, ref.referenceDisplay).joinToString("\n\n")))) } }, { ref -> context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, "https://hadithly.app/hadith/${ref.collectionSlug}/${ref.hadithNumber}"), null)) }, onOpen, { ref -> withContext(Dispatchers.IO) { app.repository.loadSavedPreview(ref) } }) } }
        com.hadithly.app.features.saved.SavedUndoBanner(testTag = "reader.saved.undoBanner")
        TextButton(onClick = onEdit, modifier = Modifier.align(Alignment.End)) { Text("EDIT") }
    }
    removal?.let { request -> AlertDialog(onDismissRequest = { removal = null }, title = { Text("Remove saved item?") }, text = { Text(stringResource(R.string.saved_removal_undo_message)) }, confirmButton = { TextButton(onClick = { remove(request); removal = null }) { Text("Remove") } }, dismissButton = { Column { TextButton(onClick = { app.savedSafety.confirmsRemoval = false; remove(request); removal = null }) { Text("Remove and don't ask again") }; TextButton(onClick = { removal = null }) { Text("Cancel") } } }) }
}
