package com.hadithly.app.features.today

import android.content.Intent
import android.content.ClipData
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
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
import com.hadithly.app.features.reader.ReaderGrade
import com.hadithly.app.features.reader.gradeDotColor
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
fun TodayScreen(onOpenTarget: (ReaderOpenTarget) -> Unit) {
    val app = rememberApp()
    val homeColors = LocalHadithlyColors.current
    val preferences by app.preferences.preferences.collectAsStateWithLifecycle()
    val progress by app.library.progress.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val readerColors = ReaderPalettes.resolved(preferences.theme, androidx.compose.foundation.isSystemInDarkTheme())
    var daily by remember { mutableStateOf<DailyHadith?>(null) }
    var loading by remember { mutableStateOf(true) }
    var failed by remember { mutableStateOf(false) }
    var offline by remember { mutableStateOf(false) }
    var reloadKey by remember { mutableStateOf(0) }

    LaunchedEffect(reloadKey, preferences.translationLocale) {
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
                if (cached != null) { daily = cached; offline = true; failed = false } else failed = true
            }
        loading = false
    }

    LaunchedEffect(Unit) {
        withContext(Dispatchers.IO) {
            ReaderPrefetch.warmEntryCache(app.repository, Collections.all.map { it.first }, app.library.progress.value)
        }
    }

    Column(
        verticalArrangement = Arrangement.spacedBy(28.dp),
        modifier = Modifier.fillMaxSize().background(homeColors.background).verticalScroll(rememberScrollState()),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp), modifier = Modifier.padding(horizontal = 16.dp)) {
            Text("Today", fontSize = 30.sp, fontWeight = FontWeight.Bold, color = homeColors.textPrimary)
            Text(
                Clerk.user?.username?.takeIf { it.isNotBlank() }?.let { "As-salamu alaykum, $it" }
                    ?: Clerk.user?.firstName?.takeIf { it.isNotBlank() }?.let { "As-salamu alaykum, $it" }
                    ?: "As-salamu alaykum",
                fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = homeColors.textPrimary,
            )
        }
        val entries = progress.filter { it.hadith != null }.sortedByDescending { it.updatedAt }.take(3)
        if (entries.isNotEmpty()) {
            SectionTitle("Continue reading", homeColors, Modifier.padding(horizontal = 16.dp))
            LazyRow(contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                itemsIndexed(entries, key = { _, entry -> entry.collectionSlug }) { _, entry ->
                    val ref = entry.hadith ?: return@itemsIndexed
                    ContinueReadingCard(ref, Collections.all.indexOfFirst { it.first == entry.collectionSlug } + 1) {
                        onOpenTarget(ReaderOpenTarget(entry.collectionSlug, ref.collectionName, ref.volumeId, ref.hadithNumber, ReaderTargetSource.CONTINUE_READING, entry.position))
                    }
                }
            }
        }
        SectionTitle("Daily hadith", homeColors, Modifier.padding(horizontal = 16.dp))
        Box(Modifier.padding(horizontal = 16.dp)) {
            when {
                daily != null -> DailyCard(daily!!, preferences, readerColors, offline, app.library, onOpenTarget)
                loading -> CardShell(homeColors) { Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) { CircularProgressIndicator(color = homeColors.textSecondary, modifier = Modifier.size(18.dp), strokeWidth = 2.dp); Text("Bringing today's hadith…", color = homeColors.textSecondary) } }
                failed -> CardShell(homeColors) { Column { Text("Today's hadith could not load", fontWeight = FontWeight.Medium, color = homeColors.textPrimary); TextButton(onClick = { reloadKey++ }) { Text("Try again", color = homeColors.accent) } } }
                else -> CardShell(homeColors) { Column { Text("No eligible hadith is cached yet", fontWeight = FontWeight.Medium, color = homeColors.textPrimary); Text("Open a collection in the Library and Today will prepare one from verified content.", fontSize = 12.sp, color = homeColors.textSecondary) } }
            }
        }
        SectionTitle("Library", homeColors, Modifier.padding(horizontal = 16.dp))
        LazyRow(contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            itemsIndexed(Collections.all, key = { _, collection -> collection.first }) { index, (slug, name) ->
                Column(
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.width(142.dp).combinedClickable(onClick = { onOpenTarget(ReaderOpenTarget(slug, name)) }).testTag("today.library.$slug"),
                ) {
                    CollectionCover(index + 1, Modifier.width(126.dp).height(164.dp))
                    Text((index + 1).toString(), fontSize = 12.sp, color = homeColors.textSecondary)
                    Text(name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = homeColors.textPrimary, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable private fun SectionTitle(title: String, colors: HadithlyColors, modifier: Modifier = Modifier) = Text(title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary, modifier = modifier)

@Composable private fun ContinueReadingCard(ref: HadithRef, position: Int, onClick: () -> Unit) {
    val colors = LocalHadithlyColors.current
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.width(218.dp).clip(RoundedCornerShape(16.dp)).background(colors.surface).combinedClickable(onClick = onClick).padding(10.dp).testTag("today.continueCard")) {
        CollectionCover(position, Modifier.width(52.dp).height(76.dp))
        Spacer(Modifier.size(12.dp)); Column(Modifier.weight(1f)) { Text(ref.collectionName, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary, maxLines = 2); Text(ref.referenceDisplay, fontSize = 11.sp, color = colors.textSecondary, maxLines = 1) }
    }
}

@OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
@Composable private fun DailyCard(hadith: DailyHadith, preferences: ReaderPreferences, colors: HadithlyColors, offline: Boolean, library: UserLibraryModel, onOpenTarget: (ReaderOpenTarget) -> Unit) {
    val context = LocalContext.current; val clipboard = LocalClipboard.current
    val clipboardScope = androidx.compose.runtime.rememberCoroutineScope()
    var expanded by remember { mutableStateOf(false) }; var menu by remember { mutableStateOf(false) }; var note by remember { mutableStateOf(false) }; var sourceSheet by remember { mutableStateOf(false) }; var noteText by remember { mutableStateOf(library.noteContentFor(hadith._id) ?: "") }
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
    val actions = listOf(CustomAccessibilityAction("Open in reader") { open(); true }, CustomAccessibilityAction(if (library.isBookmarked(hadith._id)) "Remove Bookmark" else "Bookmark") { library.toggleBookmark(reference); true }, CustomAccessibilityAction(if (library.noteContentFor(hadith._id) == null) "Add Note" else "Edit Note") { note = true; true }, CustomAccessibilityAction("Copy") { copy(); true }, CustomAccessibilityAction("Share") { share(); true })
    Box {
        val inner: @Composable () -> Unit = {
            Column(verticalArrangement = Arrangement.spacedBy(13.dp), modifier = Modifier.fillMaxWidth().padding(18.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp), modifier = Modifier.combinedClickable(onClick = { sourceSheet = true }).testTag("today.authenticity")) {
                    Box(Modifier.size(8.dp).background(gradeDotColor(ReaderGrade.from(hadith.authenticity.normalizedGrade), colors), CircleShape))
                    Text(hadith.referenceDisplay, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
                    Spacer(Modifier.weight(1f))
                    if (offline) Text("Offline", fontSize = 11.sp, color = colors.textSecondary)
                }
                if (preferences.arabicVisible) Text(hadith.arabicText, fontSize = preferences.arabicFontSize.sp, lineHeight = (preferences.arabicFontSize * 1.75f).sp, color = colors.textPrimary, maxLines = if (expanded || !collapse) Int.MAX_VALUE else 7)
                if (preferences.translationVisible) {
                    hadith.translation?.let { translation -> Text(translation.text, fontSize = 16.sp, lineHeight = 22.sp, color = colors.textPrimary, maxLines = if (expanded || !collapse) Int.MAX_VALUE else 7) }
                        ?: Text("No ${preferences.translationLocale} translation is available yet.", fontSize = 12.sp, color = colors.textSecondary)
                }
                if (collapse) TextButton(onClick = { expanded = !expanded }) { Text(if (expanded) "Show less" else "Read more", color = colors.accent) }
            }
        }
        Box(modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(colors.surface).combinedClickable(onClick = { open() }, onLongClick = { menu = true }).semantics { customActions = actions }.testTag("today.dailyCard")) {
            if (expanded && collapse) Box(Modifier.heightIn(max = 420.dp).verticalScroll(rememberScrollState())) { inner() } else inner()
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(text = { Text(if (library.isBookmarked(hadith._id)) "Remove Bookmark" else "Bookmark") }, onClick = { library.toggleBookmark(reference); menu = false })
            DropdownMenuItem(text = { Text(if (library.noteContentFor(hadith._id) == null) "Add Note" else "Edit Note") }, onClick = { note = true; menu = false })
            DropdownMenuItem(text = { Text("Copy") }, onClick = { copy(); menu = false })
            DropdownMenuItem(text = { Text("Share") }, onClick = { share(); menu = false })
        }
    }
    if (sourceSheet) {
        ModalBottomSheet(onDismissRequest = { sourceSheet = false }, containerColor = colors.surface) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth().padding(20.dp).testTag("today.sourceSheet")) {
                Text(hadith.authenticity.sourceName, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
                Text(hadith.authenticity.displayLabel, fontSize = 13.sp, color = colors.textSecondary)
                if (hadith.authenticity.sourceUrl.isNotBlank()) Text(hadith.authenticity.sourceUrl, fontSize = 12.sp, color = colors.accent)
            }
        }
    }
    if (note) AlertDialog(onDismissRequest = { note = false }, title = { Text("Note") }, text = { OutlinedTextField(noteText, { noteText = it }) }, confirmButton = { TextButton(onClick = { library.saveNote(reference, noteText); note = false }) { Text("Save") } }, dismissButton = { TextButton(onClick = { note = false }) { Text("Cancel") } })
}

@Composable private fun CardShell(colors: HadithlyColors, content: @Composable () -> Unit) = Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(colors.surface).padding(16.dp)) { content() }
