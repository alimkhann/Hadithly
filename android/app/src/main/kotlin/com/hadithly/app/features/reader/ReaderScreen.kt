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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.pager.HorizontalPager
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
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
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
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.hadithly.app.core.data.ReaderHadith
import com.hadithly.app.core.data.ReaderTranslation
import com.hadithly.app.core.data.ReadingWidthClass
import com.hadithly.app.core.data.SupportedLanguages
import com.hadithly.app.core.data.TranslationFailure
import com.hadithly.app.core.theme.LocalHadithlyColors
import com.hadithly.app.features.purchases.QuotaPaywallSheet
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch

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
    val colors = LocalHadithlyColors.current

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
                onOpenContents = { showContents = true },
                onOpenSettings = { showSettings = true },
                onShowPaywall = { showQuotaPaywall = true },
                onClose = onClose,
            )
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
                language = state.language,
                arabicFontSize = preferences.arabicFontSize,
                onLanguage = { viewModel.setLanguage(it) },
                onArabicFontSize = app.preferences::setArabicFontSize,
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
    onOpenContents: () -> Unit,
    onOpenSettings: () -> Unit,
    onShowPaywall: () -> Unit,
    onClose: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    val coroutine = rememberCoroutineScope()

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

    Box(modifier = Modifier.fillMaxSize()) {
        HorizontalPager(
            state = pagerState,
            modifier = Modifier.fillMaxSize(),
        ) { pageIndex ->
            val pages = state.pages
            val hadiths = if (pageIndex in pages.indices) pages[pageIndex].items else emptyList()
            ReaderPage(
                viewModel = viewModel,
                state = state,
                hadiths = hadiths,
                arabicFontSize = arabicFontSize,
                isSentinel = pageIndex >= pages.size,
                onTap = { viewModel.toggleChrome() },
                onShowPaywall = onShowPaywall,
            )
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

        // Quiet page-turn arrows, always visible in chrome.
        if (state.chromeVisible && viewModel.hasPreviousPage()) {
            Box(
                modifier = Modifier
                    .align(Alignment.CenterStart)
                    .padding(8.dp)
                    .background(colors.surface.copy(alpha = 0.96f), CircleShape)
                    .clickable {
                        coroutine.launch {
                            if (pagerState.currentPage > 0) pagerState.animateScrollToPage(pagerState.currentPage - 1)
                        }
                    }
                    .padding(10.dp),
            ) {
                Icon(
                    Icons.AutoMirrored.Filled.NavigateBefore,
                    contentDescription = "Previous page",
                    tint = colors.textSecondary,
                )
            }
        }
        if (state.chromeVisible && viewModel.hasNextPage()) {
            Box(
                modifier = Modifier
                    .align(Alignment.CenterEnd)
                    .padding(8.dp)
                    .background(colors.surface.copy(alpha = 0.96f), CircleShape)
                    .clickable {
                        coroutine.launch {
                            val next = pagerState.currentPage + 1
                            if (next < pagerState.pageCount) pagerState.animateScrollToPage(next)
                        }
                    }
                    .padding(10.dp),
            ) {
                Icon(
                    Icons.AutoMirrored.Filled.NavigateNext,
                    contentDescription = "Next page",
                    tint = colors.textSecondary,
                )
            }
        }
    }
}

@Composable
private fun ReaderPage(
    viewModel: ReaderViewModel,
    state: ReaderViewModel.ReaderState,
    hadiths: List<ReaderHadith>,
    arabicFontSize: Float,
    isSentinel: Boolean,
    onTap: () -> Unit,
    onShowPaywall: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    var citationsTranslation by remember { mutableStateOf<ReaderTranslation?>(null) }
    var noteTarget by remember { mutableStateOf<ReaderHadith?>(null) }
    var submissionTarget by remember { mutableStateOf<Pair<ReaderHadith, ReaderTranslation?>?>(null) }
    var reportTarget by remember { mutableStateOf<Pair<ReaderHadith, ReaderTranslation>?>(null) }

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
                verticalArrangement = Arrangement.spacedBy(40.dp),
                modifier = Modifier.fillMaxSize(),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(
                    start = 22.dp, end = 22.dp, top = 20.dp, bottom = 80.dp,
                ),
            ) {
                items(hadiths, key = { it._id }) { hadith ->
                    HadithBlock(
                        viewModel = viewModel,
                        hadith = hadith,
                        translationState = state.translations[hadith.internalId],
                        language = state.language,
                        arabicFontSize = arabicFontSize,
                        onRetry = { viewModel.retryTranslation(hadith) },
                        onShowCitations = { citationsTranslation = it },
                        onEditNote = { noteTarget = hadith },
                        onSuggest = { translation -> submissionTarget = hadith to translation },
                        onReport = { translation -> reportTarget = hadith to translation },
                        onShowPaywall = onShowPaywall,
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

// One hadith

@Composable
private fun HadithBlock(
    viewModel: ReaderViewModel,
    hadith: ReaderHadith,
    translationState: TranslationUiState?,
    language: String,
    arabicFontSize: Float,
    onRetry: () -> Unit,
    onShowCitations: (ReaderTranslation) -> Unit,
    onEditNote: () -> Unit,
    onSuggest: (ReaderTranslation?) -> Unit,
    onReport: (ReaderTranslation) -> Unit,
    onShowPaywall: () -> Unit,
) {
    val colors = LocalHadithlyColors.current

    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        // Numbered medallion
        Text(
            text = hadith.providerHadithId,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            color = colors.accent,
            modifier = Modifier
                .align(Alignment.CenterHorizontally)
                .background(colors.accentSoft, CircleShape)
                .padding(10.dp),
        )

        Text(
            text = hadith.arabicText,
            fontSize = arabicFontSize.sp,
            fontWeight = FontWeight.Medium,
            color = colors.textPrimary,
            lineHeight = (arabicFontSize * 1.75).sp,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )

        if (!hadith.narrator.isNullOrEmpty()) {
            Text(
                text = hadith.narrator,
                fontSize = 12.sp,
                color = colors.textSecondary,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        TranslationSection(
            hadith = hadith,
            translationState = translationState,
            language = language,
            onRetry = onRetry,
            onShowCitations = onShowCitations,
            onShowPaywall = onShowPaywall,
        )

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
            text = hadith.referenceDisplay,
            fontSize = 11.sp,
            color = colors.textSecondary,
            modifier = Modifier.align(Alignment.CenterHorizontally),
        )

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

@Composable
private fun SettingsSheet(
    language: String,
    arabicFontSize: Float,
    onLanguage: (String) -> Unit,
    onArabicFontSize: (Float) -> Unit,
) {
    val colors = LocalHadithlyColors.current
    Column(
        verticalArrangement = Arrangement.spacedBy(16.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(20.dp),
    ) {
        Text("Reader settings", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)

        Text("Translation language", fontSize = 13.sp, color = colors.textSecondary)
        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(SupportedLanguages.all, key = { it.first }) { (code, name) ->
                val selected = code == language
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(if (selected) colors.accentSoft else colors.surfaceElevated, RoundedCornerShape(12.dp))
                        .clickable { onLanguage(code) }
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                ) {
                    Text(name, fontSize = 15.sp, color = colors.textPrimary, modifier = Modifier.weight(1f))
                    if (selected) {
                        Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = colors.accent, modifier = Modifier.size(18.dp))
                    }
                }
            }
        }

        Text("Arabic type size", fontSize = 13.sp, color = colors.textSecondary)
        Text("بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ", fontSize = arabicFontSize.sp, color = colors.textPrimary)
        Slider(
            value = arabicFontSize,
            onValueChange = onArabicFontSize,
            valueRange = 18f..40f,
            colors = SliderDefaults.colors(
                thumbColor = colors.accent,
                activeTrackColor = colors.accent,
                inactiveTrackColor = colors.surfaceElevated,
            ),
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
