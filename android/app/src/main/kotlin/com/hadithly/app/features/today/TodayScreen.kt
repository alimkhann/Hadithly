package com.hadithly.app.features.today

import com.hadithly.app.core.preferences.nativeText

import android.content.Intent
import android.content.ClipData
import androidx.compose.animation.Crossfade
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.snap
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.automirrored.filled.NavigateNext
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.hadithly.app.R
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.hadithly.app.core.data.Collections
import com.hadithly.app.core.data.DailyHadith
import com.hadithly.app.core.data.HadithRef
import com.hadithly.app.core.data.ReaderPrefetch
import com.hadithly.app.core.data.ReaderTargetSource
import com.hadithly.app.core.data.UserLibraryModel
import com.hadithly.app.core.preferences.LocaleFallback
import com.hadithly.app.core.preferences.ReaderPreferences
import com.hadithly.app.core.theme.HadithlyColors
import com.hadithly.app.core.theme.LocalHadithlyColors
import com.hadithly.app.core.theme.ReaderPalettes
import com.hadithly.app.features.main.ReaderOpenTarget
import com.hadithly.app.features.main.rememberApp
import com.hadithly.app.core.links.CanonicalHadithUrl
import com.hadithly.app.features.reader.ReaderShare
import com.hadithly.app.features.library.CollectionCover
import com.hadithly.app.features.library.LibraryViewModel
import com.hadithly.app.features.reader.ReaderGrade
import com.hadithly.app.features.reader.gradeDotColor
import com.hadithly.app.core.widgets.WidgetSnapshotStore
import com.hadithly.app.features.widgets.refreshDailyWidgets
import com.clerk.api.Clerk
import java.time.ZoneId
import java.time.LocalDate
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json

/** Shared short/long policy. Today stays a preview, never a second reader. */
object TodayContentPolicy {
    const val COLLAPSED_CHARACTER_LIMIT = 680
    fun needsCollapsedPreview(arabic: String, translation: String?): Boolean =
        arabic.length + (translation?.length ?: 0) > COLLAPSED_CHARACTER_LIMIT
}

private const val DAILY_CACHE_KEY = "today.daily-hadith.cache.v1"

@Composable
fun TodayScreen(onOpenTarget: (ReaderOpenTarget) -> Unit, previewState: String? = null) {
    val app = rememberApp()
    val homeColors = LocalHadithlyColors.current
    val preferences by app.preferences.preferences.collectAsStateWithLifecycle()
    val progress by app.library.progress.collectAsStateWithLifecycle()
    val libraryModel: LibraryViewModel = viewModel()
    val summaries by libraryModel.summaries.collectAsStateWithLifecycle()
    val progressLoading by libraryModel.loading.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val readerColors = ReaderPalettes.resolved(if (preferences.usesSeparateReaderTheme) preferences.readerTheme else preferences.appTheme, androidx.compose.foundation.isSystemInDarkTheme())
    var daily by remember { mutableStateOf<DailyHadith?>(null) }
    var loading by remember { mutableStateOf(true) }
    var failed by remember { mutableStateOf(false) }
    var offline by remember { mutableStateOf(false) }
    var reloadKey by remember { mutableStateOf(0) }

    LaunchedEffect(reloadKey, preferences.translationLocale, preferences.arabicVisible, preferences.translationVisible, previewState) {
        if (com.hadithly.app.BuildConfig.DEBUG && previewState != null) {
            loading = previewState == "loading"
            failed = previewState == "failure"
            daily = if (previewState == "ready") dailyInterfaceExample() else null
            offline = false
            return@LaunchedEffect
        }
        val dailyCacheKey = "$DAILY_CACHE_KEY:${LocalDate.now(ZoneId.systemDefault())}:${ZoneId.systemDefault().id}:${preferences.translationLocale}"
        loading = daily == null
        runCatching { app.repository.getDailyHadith(preferences.translationLocale) }
            .onSuccess { result ->
                daily = result
                if (result != null) context.getSharedPreferences("hadithly", 0).edit()
                    .putString(dailyCacheKey, Json.encodeToString(DailyHadith.serializer(), result)).apply()
                failed = false; offline = false
            }
            .onFailure {
                val cached = context.getSharedPreferences("hadithly", 0).getString(dailyCacheKey, null)
                    ?.let { encoded -> runCatching { Json.decodeFromString(DailyHadith.serializer(), encoded) }.getOrNull() }
                if (cached != null) {
                    daily = cached
                    WidgetSnapshotStore(context).markDailyOffline(preferences.translationLocale, ZoneId.systemDefault().id)
                    app.appScope.launch { refreshDailyWidgets(context) }
                    offline = true; failed = false
                } else failed = true
            }
        if (!offline && !failed) {
            WidgetSnapshotStore(context).saveDaily(
                runCatching { app.repository.getDailyWidgetPayload(preferences.translationLocale, preferences.arabicVisible, preferences.translationVisible) }.getOrNull(),
            )
            app.appScope.launch { refreshDailyWidgets(context) }
        }
        loading = false
    }

    LaunchedEffect(Unit) {
        if (com.hadithly.app.BuildConfig.DEBUG && previewState != null) return@LaunchedEffect
        withContext(Dispatchers.IO) {
            ReaderPrefetch.warmEntryCache(app.repository, Collections.all.map { it.first }, app.library.progress.value)
        }
    }

    Column(
        verticalArrangement = Arrangement.spacedBy(28.dp),
        modifier = Modifier.fillMaxSize().background(homeColors.background).verticalScroll(rememberScrollState()),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp), modifier = Modifier.padding(horizontal = 16.dp)) {
            Text(stringResource(R.string.app_today), fontSize = 30.sp, fontWeight = FontWeight.Bold, color = homeColors.textPrimary)
            Text(
                Clerk.user?.username?.takeIf { it.isNotBlank() }?.let { "As-salamu alaykum, $it" }
                    ?: Clerk.user?.firstName?.takeIf { it.isNotBlank() }?.let { "As-salamu alaykum, $it" }
                    ?: "As-salamu alaykum",
                fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = homeColors.textPrimary,
            )
        }
        val entries = com.hadithly.app.features.library.continueReadingEntries(progress)
        if (entries.isNotEmpty()) {
            com.hadithly.app.features.library.SectionTitleRow("Continue reading", Modifier.padding(horizontal = 16.dp))
            com.hadithly.app.features.library.ContinueReadingRail(entries) { entry ->
                onOpenTarget(com.hadithly.app.features.library.continueReadingTarget(entry))
            }
        }
        SectionTitle(stringResource(R.string.app_daily_hadith), homeColors, Modifier.padding(horizontal = 16.dp))
        val dailyPresentation = when {
            daily != null -> DailyPresentation.Ready(daily!!)
            loading -> DailyPresentation.Loading
            failed -> DailyPresentation.Failed
            else -> DailyPresentation.Empty
        }
        Crossfade(targetState = dailyPresentation, animationSpec = tween(com.hadithly.app.core.theme.InterfaceMotion.REVEAL),
            label = "Daily content reveal", modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)) { presentation ->
            when (presentation) {
                is DailyPresentation.Ready -> DailyCard(presentation.hadith, preferences, readerColors, offline, app.library, onOpenTarget)
                DailyPresentation.Loading -> CardShell(homeColors) {
                    com.hadithly.app.core.theme.ContentSkeleton(com.hadithly.app.core.theme.SkeletonKind.Daily,
                        label = nativeText("Bringing today's hadith…"), modifier = Modifier.testTag("today.dailyLoading"))
                }
                DailyPresentation.Failed -> CardShell(homeColors) {
                    Column {
                        Text(nativeText("Today's hadith could not load"), fontWeight = FontWeight.Medium, color = homeColors.textPrimary)
                        TextButton(onClick = { reloadKey++ }) { Text(nativeText("Try again"), color = homeColors.interactive) }
                    }
                }
                DailyPresentation.Empty -> CardShell(homeColors) {
                    Column {
                        Text(nativeText("No eligible hadith is cached yet"), fontWeight = FontWeight.Medium, color = homeColors.textPrimary)
                        Text(nativeText("Open a collection in the Library and Today will prepare one from verified content."), fontSize = 12.sp, color = homeColors.textSecondary)
                    }
                }
            }
        }
        SectionTitle(stringResource(R.string.app_library), homeColors, Modifier.padding(horizontal = 16.dp))
        LazyRow(contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            itemsIndexed(Collections.all, key = { _, collection -> collection.first }) { index, (slug, name) ->
                Column(
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.width(142.dp).combinedClickable(onClick = { onOpenTarget(ReaderOpenTarget(slug, name)) }).testTag("today.library.$slug"),
                ) {
                    CollectionCover(index + 1, Modifier.width(126.dp).height(164.dp))
                    com.hadithly.app.features.library.CollectionTitle(index + 1, name)
                    HomeCollectionProgress(summaries[slug], progressLoading)
                }
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable private fun HomeCollectionProgress(summary: com.hadithly.app.core.data.CollectionProgressSummary?, loading: Boolean) {
    if (summary == null && loading) {
        com.hadithly.app.core.theme.ContentSkeleton(com.hadithly.app.core.theme.SkeletonKind.Compact, label = "Loading reading progress")
        return
    }
    val colors = LocalHadithlyColors.current
    val fraction = summary?.takeIf { it.state == "in_progress" && (it.totalHadiths ?: 0.0) > 0.0 }
        ?.let { ((it.readOrdinal ?: 0.0) / (it.totalHadiths ?: 1.0)).coerceIn(0.0, 1.0) }
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Box(Modifier.fillMaxWidth().height(3.dp).background(colors.surfaceElevated, RoundedCornerShape(99.dp))) {
            if (fraction != null) Box(Modifier.fillMaxWidth(fraction.toFloat()).height(3.dp).background(colors.accent, RoundedCornerShape(99.dp)))
        }
        val label = if (summary?.state == "in_progress") {
            if (summary.readOrdinal != null && (summary.totalHadiths ?: 0.0) > 0.0) "Hadith ${summary.readOrdinal.toInt()} of ${summary.totalHadiths?.toInt()}"
            else "Continue reading"
        } else "Not started"
        Text(label, fontSize = 11.sp, color = colors.textSecondary, maxLines = 1)
    }
}

@Composable private fun SectionTitle(title: String, colors: HadithlyColors, modifier: Modifier = Modifier) = Text(title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary, modifier = modifier)

@OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
@Composable private fun DailyCard(hadith: DailyHadith, preferences: ReaderPreferences, colors: HadithlyColors, offline: Boolean, library: UserLibraryModel, onOpenTarget: (ReaderOpenTarget) -> Unit) {
    val context = LocalContext.current; val clipboard = LocalClipboard.current
    val clipboardScope = androidx.compose.runtime.rememberCoroutineScope()
    var expanded by remember { mutableStateOf(false) }; var menu by remember { mutableStateOf(false) }; var note by remember { mutableStateOf(false) }; var sourceSheet by remember { mutableStateOf(false) }; var noteText by remember { mutableStateOf(library.noteContentFor(hadith._id) ?: "") }
    val app = com.hadithly.app.HadithlyApplication.instance(); var pendingRemoval by remember { mutableStateOf<String?>(null) }
    val bookmarkRemovedLabel = stringResource(R.string.saved_bookmark_removed); val favoriteRemovedLabel = stringResource(R.string.saved_favorite_removed)
    val collapse = TodayContentPolicy.needsCollapsedPreview(hadith.arabicText, hadith.translation?.text)
    val reference = HadithRef(hadith._id, hadith.collectionSlug, hadith.collectionName, hadith.volumeId, hadith.providerHadithId, hadith.arabicText, hadith.translation?.text, hadith.referenceDisplay)
    fun open() = onOpenTarget(ReaderOpenTarget(hadith.collectionSlug, hadith.collectionName, hadith.volumeId, hadith.providerHadithId, ReaderTargetSource.TODAY))
    fun copy() {
        clipboardScope.launch {
            clipboard.setClipEntry(ClipEntry(ClipData.newPlainText(
                hadith.referenceDisplay,
                ReaderShare.formatCopyText(if (preferences.arabicVisible) hadith.arabicText else null, if (preferences.translationVisible) hadith.translation?.text else null, preferences.translationVisible && hadith.translation?.isAI == true, hadith.collectionName, hadith.providerHadithId, hadith.authenticity.sourceName),
            )))
        }
    }
    fun share() { runCatching { CanonicalHadithUrl.build(hadith.collectionSlug, hadith.providerHadithId) }.getOrNull()?.let { url -> context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, url), null)) } }
    fun toggleBookmark() { val date = library.savedItems.value.firstOrNull { it.hadithId == hadith._id }?.bookmarkCreatedAt; val removing = library.isBookmarked(hadith._id); library.toggleBookmark(reference); if (removing && date != null) library.undo.show(bookmarkRemovedLabel) { library.restoreBookmark(reference, date) } }
    fun toggleFavorite() { val date = library.savedItems.value.firstOrNull { it.hadithId == hadith._id }?.favoriteCreatedAt; val removing = library.isFavorite(hadith._id); library.toggleFavorite(reference); if (removing && date != null) library.undo.show(favoriteRemovedLabel) { library.restoreFavorite(reference, date) } }
    fun requestBookmark() { if (library.isBookmarked(hadith._id) && app.savedSafety.confirmsRemoval) pendingRemoval = "bookmark" else toggleBookmark() }
    fun requestFavorite() { if (library.isFavorite(hadith._id) && app.savedSafety.confirmsRemoval) pendingRemoval = "favorite" else toggleFavorite() }
    val actions = listOf(CustomAccessibilityAction("Open in reader") { open(); true }, CustomAccessibilityAction(if (library.isBookmarked(hadith._id)) "Remove Bookmark" else "Bookmark") { requestBookmark(); true }, CustomAccessibilityAction(if (library.isFavorite(hadith._id)) "Remove Favorite" else "Favorite") { requestFavorite(); true }, CustomAccessibilityAction(if (library.noteContentFor(hadith._id) == null) "Add Note" else "Edit Note") { note = true; true }, CustomAccessibilityAction("Copy") { copy(); true }, CustomAccessibilityAction("Share") { share(); true }, CustomAccessibilityAction("Suggest translation") { open(); true })
    Box {
        val inner: @Composable () -> Unit = {
            Column(verticalArrangement = Arrangement.spacedBy(13.dp), modifier = Modifier.fillMaxWidth().padding(18.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp), modifier = Modifier.combinedClickable(onClick = { sourceSheet = true }).testTag("today.authenticity")) {
                    Box(Modifier.size(8.dp).background(gradeDotColor(ReaderGrade.from(hadith.authenticity.normalizedGrade), colors), CircleShape))
                    Text(hadith.referenceDisplay, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
                    Spacer(Modifier.weight(1f))
                    if (offline) Text(nativeText("Offline"), fontSize = 11.sp, color = colors.textSecondary)
                }
                if (preferences.arabicVisible) Text(hadith.arabicText, fontSize = preferences.arabicFontSize.sp, lineHeight = (preferences.arabicFontSize * 1.75f).sp, color = colors.textPrimary, maxLines = if (expanded || !collapse) Int.MAX_VALUE else 7)
                if (preferences.translationVisible) {
                    hadith.translation?.let { translation -> Text(translation.text, fontSize = 16.sp, lineHeight = 22.sp, color = colors.textPrimary, maxLines = if (expanded || !collapse) Int.MAX_VALUE else 7) }
                        ?: Text(nativeText("No %1\$s translation is available yet.", preferences.translationLocale), fontSize = 12.sp, color = colors.textSecondary)
                }
                if (collapse) TextButton(onClick = { expanded = !expanded }, modifier = Modifier.testTag("today.expand")) { Text(if (expanded) "Show less" else "Read more", color = colors.accent) }
            }
        }
        val motionAllowed = com.hadithly.app.core.theme.rememberMotionAllowed()
        Box(modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(colors.surface)
            .animateContentSize(if (motionAllowed) tween(com.hadithly.app.core.theme.InterfaceMotion.STEP) else snap())
            .combinedClickable(onClick = { open() }, onLongClick = { menu = true }).semantics { customActions = actions }.testTag("today.dailyCard")) {
            if (expanded && collapse) Box(Modifier.heightIn(max = 420.dp).verticalScroll(rememberScrollState())) { inner() } else inner()
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(text = { Text(if (library.isBookmarked(hadith._id)) "Remove Bookmark" else "Bookmark") }, onClick = { requestBookmark(); menu = false })
            DropdownMenuItem(text = { Text(if (library.isFavorite(hadith._id)) "Remove Favorite" else "Favorite") }, onClick = { requestFavorite(); menu = false })
            DropdownMenuItem(text = { Text(if (library.noteContentFor(hadith._id) == null) "Add Note" else "Edit Note") }, onClick = { note = true; menu = false })
            DropdownMenuItem(text = { Text(nativeText("Copy")) }, onClick = { copy(); menu = false })
            DropdownMenuItem(text = { Text(nativeText("Share")) }, onClick = { share(); menu = false })
            DropdownMenuItem(text = { Text(nativeText("Suggest translation")) }, onClick = { open(); menu = false })
        }
    }
    if (pendingRemoval != null) AlertDialog(onDismissRequest = { pendingRemoval = null }, title = { Text(nativeText("Remove saved item?")) }, text = { Text(nativeText("You can undo this action from the message at the top.")) }, confirmButton = { TextButton(onClick = { if (pendingRemoval == "bookmark") toggleBookmark() else toggleFavorite(); pendingRemoval = null }) { Text(nativeText("Remove")) } }, dismissButton = { Column { TextButton(onClick = { app.savedSafety.confirmsRemoval = false; if (pendingRemoval == "bookmark") toggleBookmark() else toggleFavorite(); pendingRemoval = null }) { Text(nativeText("Remove and don't ask again")) }; TextButton(onClick = { pendingRemoval = null }) { Text(nativeText("Cancel")) } } })
    if (sourceSheet) {
        ModalBottomSheet(onDismissRequest = { sourceSheet = false }, containerColor = colors.surface) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth().padding(20.dp).testTag("today.sourceSheet")) {
                Text(hadith.authenticity.sourceName, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
                Text(hadith.authenticity.displayLabel, fontSize = 13.sp, color = colors.textSecondary)
                if (hadith.authenticity.sourceUrl.isNotBlank()) Text(hadith.authenticity.sourceUrl, fontSize = 12.sp, color = colors.accent)
            }
        }
    }
    if (note) AlertDialog(onDismissRequest = { note = false }, title = { Text(nativeText("Note")) }, text = { OutlinedTextField(noteText, { noteText = it }) }, confirmButton = { TextButton(onClick = { library.saveNote(reference, noteText); note = false }) { Text(nativeText("Save")) } }, dismissButton = { TextButton(onClick = { note = false }) { Text(nativeText("Cancel")) } })
}

@Composable private fun CardShell(colors: HadithlyColors, content: @Composable () -> Unit) = Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(colors.surface).padding(16.dp)) { content() }

private sealed interface DailyPresentation {
    data class Ready(val hadith: DailyHadith) : DailyPresentation
    data object Loading : DailyPresentation
    data object Failed : DailyPresentation
    data object Empty : DailyPresentation
}

/** Only reached by explicitly requested Debug previews; never provider content. */
private fun dailyInterfaceExample(): DailyHadith = DailyHadith(
    _id = "visual-preview", provider = "fixture", canonicalId = "fixture:preview:1", providerHadithId = "1",
    collectionSlug = "fixture", collectionName = "Prepared interface preview",
    arabicText = com.hadithly.app.features.onboarding.PreparedTranslationExample.arabic,
    translation = com.hadithly.app.core.data.DailyTranslation(
        text = List(12) { com.hadithly.app.features.onboarding.PreparedTranslationExample.translations["en"].orEmpty() }.joinToString(" "),
        language = "en", source = "fixture", sourceLabel = "Prepared example", isAI = false),
    referenceDisplay = "Prepared interface preview",
    authenticity = com.hadithly.app.core.data.AuthenticityClaim("unknown", claimScope = "unknown", sourceLabel = "Prepared example", sourceName = "Interface preview", sourceUrl = "", verificationMethod = "unverified"),
)
