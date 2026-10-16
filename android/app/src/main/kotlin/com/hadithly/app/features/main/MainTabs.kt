package com.hadithly.app.features.main

import com.hadithly.app.R
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.Column
import androidx.compose.ui.unit.dp
import com.hadithly.app.features.saved.SavedUndoBanner
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CollectionsBookmark
import androidx.compose.material.icons.filled.BookmarkBorder
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.platform.LocalContext
import com.hadithly.app.HadithlyApplication
import com.hadithly.app.core.data.HadithRef
import com.hadithly.app.core.data.ReadingPosition
import com.hadithly.app.core.data.ReaderTargetSource
import com.hadithly.app.core.links.CanonicalHadithLink
import com.hadithly.app.core.theme.LocalHadithlyColors
import com.hadithly.app.features.library.LibraryScreen
import com.hadithly.app.features.reader.ReaderScreen
import com.hadithly.app.features.settings.SettingsScreen
import com.hadithly.app.features.saved.SavedScreen
import com.hadithly.app.features.today.TodayScreen
import com.hadithly.app.features.widgets.continueWidgetTarget

/** Reach the dependency graph without a DI framework. */
@Composable
fun rememberApp(): HadithlyApplication =
    LocalContext.current.applicationContext as HadithlyApplication

/** Where to open the reader: a plain collection or a specific hadith. */
data class ReaderOpenTarget(
    val slug: String,
    val name: String,
    val volumeId: String? = null,
    val hadithNumber: String? = null,
    val source: ReaderTargetSource = ReaderTargetSource.COLLECTION,
    val position: ReadingPosition? = null,
    /** A fresh reader session even when the same saved row is reopened. */
    val instanceKey: Long = System.nanoTime(),
)

/**
 * Four quiet destinations matching iOS: Today, Library, Saved, Settings.
 * Reader opens full screen over
 * the tab bar; its close control — or system back — returns here.
 * A pending canonical link (F3 App Link) opens the reader exactly once;
 * while onboarding is unfinished it waits here and lands after completion.
 */
@Composable
fun MainTabs(
    showSignIn: Boolean,
    onShowSignIn: () -> Unit,
    onDismissSignIn: () -> Unit,
    pendingLink: CanonicalHadithLink? = null,
    notificationTarget: ReaderOpenTarget? = null,
    continueWidgetRequest: Long? = null,
) {
    val app = rememberApp()
    val progress by app.library.progress.collectAsState()
    val colors = LocalHadithlyColors.current
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var readerTarget by remember { mutableStateOf<ReaderOpenTarget?>(null) }
    var consumedLink by remember { mutableStateOf<CanonicalHadithLink?>(null) }
    var consumedContinueRequest by remember { mutableStateOf<Long?>(null) }

    LaunchedEffect(pendingLink) {
        if (pendingLink != null && pendingLink != consumedLink) {
            consumedLink = pendingLink
            readerTarget = ReaderOpenTarget(
                slug = pendingLink.collectionSlug,
                name = pendingLink.collectionName,
                hadithNumber = pendingLink.providerHadithId,
                source = ReaderTargetSource.CANONICAL_LINK,
            )
        }
    }

    LaunchedEffect(notificationTarget?.instanceKey) {
        if (notificationTarget != null) readerTarget = notificationTarget
    }

    LaunchedEffect(continueWidgetRequest) {
        if (continueWidgetRequest != null && continueWidgetRequest != consumedContinueRequest) {
            app.library.refresh()
        }
    }

    LaunchedEffect(continueWidgetRequest, progress) {
        if (continueWidgetRequest != null && continueWidgetRequest != consumedContinueRequest) {
            continueWidgetTarget(progress)?.let {
                readerTarget = it
                consumedContinueRequest = continueWidgetRequest
            }
        }
    }

    Scaffold(
        containerColor = colors.background,
        bottomBar = {
            if (readerTarget == null) {
                Column {
                    SavedUndoBanner(Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
                    HadithlyBottomNavigation(tab) { tab = it }
                }
            }
        },
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            when (tab) {
                0 -> TodayScreen(onOpenTarget = { readerTarget = it })
                1 -> LibraryScreen(
                    onOpenCollection = { slug, name ->
                        readerTarget = app.library.progress.value
                            .firstOrNull { it.collectionSlug == slug && it.hadith != null && it.position != null }
                            ?.let { com.hadithly.app.features.library.continueReadingTarget(it) }
                            ?: ReaderOpenTarget(slug, name)
                    },
                    onOpenTarget = { target -> readerTarget = target },
                )
                2 -> SavedScreen(onOpenTarget = { readerTarget = it })
                else -> SettingsScreen(
                    onShowSignIn = onShowSignIn,
                )
            }
        }
    }

    readerTarget?.let { target ->
        Box(modifier = Modifier.fillMaxSize()) {
            ReaderScreen(
                collectionSlug = target.slug,
                collectionName = target.name,
                openVolumeId = target.volumeId,
                openHadithNumber = target.hadithNumber,
                openPosition = target.position,
                targetSource = target.source,
                instanceKey = target.instanceKey,
                onClose = { readerTarget = null },
                // The reader Saved sheet's EDIT affordance opens the full
                // Saved destination (folders and filters stay H3 scope).
                onOpenSaved = {
                    readerTarget = null
                    tab = 2
                },
            )
        }
    }
}

@Composable
internal fun HadithlyBottomNavigation(selected: Int, onSelect: (Int) -> Unit) {
    val labels = listOf(stringResource(R.string.app_today), stringResource(R.string.app_library), stringResource(R.string.app_saved), stringResource(R.string.app_settings))
    val icons = listOf(Icons.Filled.WbSunny, Icons.Filled.CollectionsBookmark, Icons.Filled.BookmarkBorder, Icons.Filled.Settings)
    com.hadithly.app.core.theme.QuietNavigationBar(labels.mapIndexed { index, label ->
        com.hadithly.app.core.theme.QuietDestination(label, icons[index], tag = listOf("tabs.today", "tabs.library", "tabs.saved", "tabs.settings")[index])
    }, selected, onSelect, Modifier.navigationBarsPadding().padding(horizontal = 20.dp, vertical = 8.dp).testTag("tabs.bar"))
}
