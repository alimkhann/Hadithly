@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.hadithly.app.features.reader

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.automirrored.filled.NavigateBefore
import androidx.compose.material.icons.automirrored.filled.NavigateNext
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.BookmarkBorder
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.FormatSize
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Textsms
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
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
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.hadithly.app.core.data.ReaderHadith
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
                onSelect = { viewModel.selectVolume(it) },
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
        ) ?: return false
        if (reduceMotion) {
            coroutine.launch { pagerState.scrollToPage(destination) }
        } else {
            coroutine.launch { pagerState.animateScrollToPage(destination) }
        }
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
        if (pagingPolicy.destination(pagerState.currentPage, pagerState.pageCount, ReaderPageTurn.PREVIOUS) != null) {
            add(CustomAccessibilityAction("Previous page") { turnPage(ReaderPageTurn.PREVIOUS) })
        }
        if (pagingPolicy.destination(pagerState.currentPage, pagerState.pageCount, ReaderPageTurn.NEXT) != null) {
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
                    pageCount = pageCount,
                    restoration = viewModel.restoredPosition,
                    restorationGeneration = viewModel.restorationGeneration,
                    landingHadithNumber = viewModel.landingHadithNumber,
                    isSentinel = pageIndex >= pages.size,
                    onTurn = { turnPage(it) },
                    onTap = { viewModel.toggleChrome() },
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
    modifier: Modifier = Modifier,
    content: @Composable PagerScope.(page: Int) -> Unit,
) {
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
        HorizontalPager(
            state = state,
            reverseLayout = policy.reverseLayout,
            modifier = modifier,
            pageContent = content,
        )
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
    pageCount: Int,
    restoration: ReadingPosition?,
    restorationGeneration: Int,
    landingHadithNumber: String?,
    isSentinel: Boolean,
    onTurn: (ReaderPageTurn) -> Unit,
    onTap: () -> Unit,
    onShowPaywall: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    var citationsTranslation by remember { mutableStateOf<ReaderTranslation?>(null) }
    var noteTarget by remember { mutableStateOf<ReaderHadith?>(null) }
    var submissionTarget by remember { mutableStateOf<Pair<ReaderHadith, ReaderTranslation?>?>(null) }
    var reportTarget by remember { mutableStateOf<Pair<ReaderHadith, ReaderTranslation>?>(null) }
    val listState = rememberLazyListState()
    val chapterOpenings = remember(hadiths) { ReaderChapterBoundaries.openingIndices(hadiths) }

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
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
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
                itemsIndexed(hadiths, key = { _, hadith -> hadith._id }) { index, hadith ->
                    Column {
                        if (index > 0) {
                            ReaderHadithDivider()
                        }
                        if (chapterOpenings.contains(index)) {
                            ReaderChapterHeader(title = hadith.chapterName.orEmpty())
                        }
                        HadithBlock(
                            viewModel = viewModel,
                            hadith = hadith,
                            translationState = state.translations[hadith.internalId],
                            language = state.language,
                            arabicFontSize = arabicFontSize,
                            preferences = preferences,
                            onRetry = { viewModel.retryTranslation(hadith) },
                            onShowCitations = { citationsTranslation = it },
                            onEditNote = { noteTarget = hadith },
                            onSuggest = { translation -> submissionTarget = hadith to translation },
                            onReport = { translation -> reportTarget = hadith to translation },
                            onShowPaywall = onShowPaywall,
                            modifier = Modifier.padding(vertical = 20.dp),
                        )
                    }
                }
                item(key = "reader-end-navigation") {
                    ReaderEndNavigation(
                        policy = pagingPolicy,
                        currentPageIndex = pageIndex,
                        pageCount = pageCount,
                        onTurn = onTurn,
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

@Composable
internal fun ReaderEndNavigation(
    policy: ReaderPagingPolicy,
    currentPageIndex: Int,
    pageCount: Int,
    onTurn: (ReaderPageTurn) -> Unit,
) {
    val colors = LocalHadithlyColors.current
    Row(
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        policy.endControlOrder.forEach { turn ->
            val destination = policy.destination(currentPageIndex, pageCount, turn)
                ?: return@forEach
            val pointsLeft = when (policy.pageDirection) {
                com.hadithly.app.core.preferences.PageDirection.LTR -> turn == ReaderPageTurn.PREVIOUS
                com.hadithly.app.core.preferences.PageDirection.RTL -> turn == ReaderPageTurn.NEXT
            }
            Row(
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .weight(1f)
                    .height(48.dp)
                    .background(colors.surface, RoundedCornerShape(50))
                    .clickable { onTurn(turn) }
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
                if (pointsLeft) {
                    Icon(
                        Icons.AutoMirrored.Filled.NavigateBefore,
                        contentDescription = null,
                        tint = colors.textSecondary,
                    )
                }
                Text(
                    text = "Page ${destination + 1}",
                    color = colors.textSecondary,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                )
                if (!pointsLeft) {
                    Icon(
                        Icons.AutoMirrored.Filled.NavigateNext,
                        contentDescription = null,
                        tint = colors.textSecondary,
                    )
                }
            }
        }
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
                .background(colors.accent.copy(alpha = 0.8f), RoundedCornerShape(50)),
        )
    }
}

/** A restrained hairline between hadiths (R4): no cards, no ornament. */
@Composable
internal fun ReaderHadithDivider() {
    val colors = LocalHadithlyColors.current
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 20.dp)
            .height(0.5.dp)
            .background(colors.divider),
    )
}

/** The strong, source-provided chapter opening (R4). Never invented: rendered
 * only when the provider data carries a chapter name. */
@Composable
internal fun ReaderChapterHeader(title: String) {
    val colors = LocalHadithlyColors.current
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {}
            .testTag("reader.chapterHeader"),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(0.5.dp)
                .background(colors.divider),
        )
        Text(
            text = "Chapter",
            fontSize = 11.sp,
            color = colors.textSecondary,
            modifier = Modifier.padding(top = 12.dp),
        )
        Text(
            text = title,
            fontSize = 20.sp,
            fontWeight = FontWeight.SemiBold,
            color = colors.textPrimary,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 2.dp, bottom = 6.dp),
        )
    }
}

// One hadith

@Composable
private fun HadithBlock(
    viewModel: ReaderViewModel,
    hadith: ReaderHadith,
    translationState: TranslationUiState?,
    language: String,
    arabicFontSize: Float,
    preferences: ReaderPreferences,
    modifier: Modifier = Modifier,
    onRetry: () -> Unit,
    onShowCitations: (ReaderTranslation) -> Unit,
    onEditNote: () -> Unit,
    onSuggest: (ReaderTranslation?) -> Unit,
    onReport: (ReaderTranslation) -> Unit,
    onShowPaywall: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    val arabicFamily = com.hadithly.app.core.theme.ArabicTypefaces.forFont(preferences.arabicFont)

    Column(
        verticalArrangement = Arrangement.spacedBy(16.dp),
        modifier = modifier,
    ) {
        // The quiet reference label (R4) replaces the numbered medallion,
        // matching the minimal reference treatment in the Sajda reference.
        Text(
            text = hadith.referenceDisplay,
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium,
            color = colors.textSecondary,
            modifier = Modifier
                .testTag("reader.reference"),
        )

        if (preferences.arabicVisible) {
            CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                Text(
                    text = hadith.arabicText,
                    fontSize = arabicFontSize.sp,
                    fontFamily = arabicFamily,
                    fontWeight = FontWeight.Medium,
                    color = colors.textPrimary,
                    lineHeight = (arabicFontSize * 1.75).sp,
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("reader.arabic"),
                )
            }
        }

        if (!hadith.narrator.isNullOrEmpty()) {
            Text(
                text = hadith.narrator,
                fontSize = 12.sp,
                color = colors.textSecondary,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
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

        val activeTranslation = (translationState as? TranslationUiState.Loaded)?.translation
        Row(
            horizontalArrangement = Arrangement.spacedBy(18.dp),
            modifier = Modifier.align(Alignment.CenterHorizontally),
        ) {
            ContributionAction(Icons.Filled.Textsms, "Suggest translation") { onSuggest(activeTranslation) }
            activeTranslation?.let { translation ->
                ContributionAction(Icons.Filled.Flag, "Report") { onReport(translation) }
            }
        }

        Text(
            text = hadith.authenticity.displayLabel,
            fontSize = 11.sp,
            color = colors.textSecondary,
            modifier = Modifier
                .align(Alignment.CenterHorizontally)
                .testTag("reader.authenticity"),
        )

        HadithActionRow(
            modifier = Modifier.align(Alignment.CenterHorizontally),
            isBookmarked = viewModel.isBookmarked(hadith),
            isFavorite = viewModel.isFavorite(hadith),
            hasNote = viewModel.noteContent(hadith) != null,
            onBookmark = { viewModel.toggleBookmark(hadith) },
            onFavorite = { viewModel.toggleFavorite(hadith) },
            onNote = onEditNote,
        )
    }
}

@Composable
private fun ContributionAction(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    onClick: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    Row(
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.clickable(onClick = onClick).padding(vertical = 6.dp),
    ) {
        Icon(icon, contentDescription = null, tint = colors.textSecondary.copy(alpha = 0.8f), modifier = Modifier.size(14.dp))
        Text(label, fontSize = 12.sp, color = colors.textSecondary.copy(alpha = 0.8f))
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

@Composable
private fun HadithActionRow(
    modifier: Modifier = Modifier,
    isBookmarked: Boolean,
    isFavorite: Boolean,
    hasNote: Boolean,
    onBookmark: () -> Unit,
    onFavorite: () -> Unit,
    onNote: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    Row(
        horizontalArrangement = Arrangement.spacedBy(26.dp),
        modifier = modifier,
    ) {
        ActionIcon(
            icon = if (isBookmarked) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder,
            tint = if (isBookmarked) colors.bookmark else colors.textSecondary.copy(alpha = 0.75f),
            label = if (isBookmarked) "Remove bookmark" else "Bookmark",
            onClick = onBookmark,
        )
        ActionIcon(
            icon = if (isFavorite) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
            tint = if (isFavorite) colors.favorite else colors.textSecondary.copy(alpha = 0.75f),
            label = if (isFavorite) "Remove favorite" else "Favorite",
            onClick = onFavorite,
        )
        ActionIcon(
            icon = Icons.Filled.Edit,
            tint = colors.textSecondary.copy(alpha = 0.75f),
            label = if (hasNote) "Edit note" else "Add note",
            onClick = onNote,
        )
    }
}

@Composable
private fun ActionIcon(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    tint: androidx.compose.ui.graphics.Color,
    label: String,
    onClick: () -> Unit,
) {
    Icon(
        imageVector = icon,
        contentDescription = label,
        tint = tint,
        modifier = Modifier
            .size(22.dp)
            .clickable(onClick = onClick),
    )
}

// Contents sheet

@Composable
private fun ContentsSheet(
    volumes: List<com.hadithly.app.core.data.OutlineVolume>,
    selectedVolumeId: String?,
    onSelect: (String) -> Unit,
) {
    val colors = LocalHadithlyColors.current
    LazyColumn(
        verticalArrangement = Arrangement.spacedBy(8.dp),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp),
    ) {
        item {
            Text("Contents", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)
            Spacer(modifier = Modifier.height(8.dp))
        }
        items(volumes, key = { it.volumeId }) { volume ->
            val selected = volume.volumeId == selectedVolumeId
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(if (selected) colors.accentSoft else colors.surfaceElevated, RoundedCornerShape(12.dp))
                    .clickable { onSelect(volume.volumeId) }
                    .padding(horizontal = 16.dp, vertical = 14.dp),
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
