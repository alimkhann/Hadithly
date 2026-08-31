package com.hadithly.app.features.main

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CollectionsBookmark
import androidx.compose.material.icons.filled.BookmarkBorder
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import com.hadithly.app.HadithlyApplication
import com.hadithly.app.core.data.HadithRef
import com.hadithly.app.core.theme.LocalHadithlyColors
import com.hadithly.app.features.library.LibraryScreen
import com.hadithly.app.features.reader.ReaderScreen
import com.hadithly.app.features.settings.SettingsScreen
import com.hadithly.app.features.saved.SavedScreen
import com.hadithly.app.features.today.TodayScreen

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
    /** A fresh reader session even when the same saved row is reopened. */
    val instanceKey: Long = System.nanoTime(),
)

/**
 * Four quiet destinations matching iOS: Today, Library, Saved, Settings.
 * Reader opens full screen over
 * the tab bar; its close control — or system back — returns here.
 */
@Composable
fun MainTabs(
    showSignIn: Boolean,
    onShowSignIn: () -> Unit,
    onDismissSignIn: () -> Unit,
) {
    val app = rememberApp()
    val colors = LocalHadithlyColors.current
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var readerTarget by remember { mutableStateOf<ReaderOpenTarget?>(null) }

    Scaffold(
        containerColor = colors.background,
        bottomBar = {
            if (readerTarget == null) {
                NavigationBar(containerColor = colors.surface) {
                    NavigationBarItem(
                        selected = tab == 0,
                        onClick = { tab = 0 },
                        icon = { Icon(Icons.Filled.WbSunny, contentDescription = null) },
                        label = { Text("Today") },
                        colors = navigationColors(colors),
                    )
                    NavigationBarItem(
                        selected = tab == 1,
                        onClick = { tab = 1 },
                        icon = { Icon(Icons.Filled.CollectionsBookmark, contentDescription = null) },
                        label = { Text("Library") },
                        colors = navigationColors(colors),
                    )
                    NavigationBarItem(
                        selected = tab == 2,
                        onClick = { tab = 2 },
                        icon = { Icon(Icons.Filled.BookmarkBorder, contentDescription = null) },
                        label = { Text("Saved") },
                        colors = navigationColors(colors),
                    )
                    NavigationBarItem(
                        selected = tab == 3,
                        onClick = { tab = 3 },
                        icon = { Icon(Icons.Filled.Settings, contentDescription = null) },
                        label = { Text("Settings") },
                        colors = navigationColors(colors),
                    )
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
                    onOpenCollection = { slug, name -> readerTarget = ReaderOpenTarget(slug, name) },
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
                instanceKey = target.instanceKey,
                onClose = { readerTarget = null },
            )
        }
    }
}

@Composable
private fun navigationColors(colors: com.hadithly.app.core.theme.HadithlyColors) =
    NavigationBarItemDefaults.colors(
        selectedIconColor = colors.accent,
        selectedTextColor = colors.accent,
        indicatorColor = colors.accentSoft,
        unselectedIconColor = colors.textSecondary,
        unselectedTextColor = colors.textSecondary,
    )
