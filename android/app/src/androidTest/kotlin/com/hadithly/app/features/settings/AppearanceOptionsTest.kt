package com.hadithly.app.features.settings

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import com.hadithly.app.core.preferences.ReaderPreferences
import com.hadithly.app.core.preferences.ReaderTheme
import com.hadithly.app.core.theme.HadithlyTheme
import org.junit.Rule
import org.junit.Test

class AppearanceOptionsTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun readerThemeChoicesAreASeparateConditionalGroup() {
        compose.setContent {
            var preferences by remember {
                mutableStateOf(
                    ReaderPreferences(
                        appTheme = ReaderTheme.LIGHT,
                        readerTheme = ReaderTheme.PAPER,
                        usesSeparateReaderTheme = false,
                    ),
                )
            }
            HadithlyTheme {
                AppearanceOptions(
                    preferences = preferences,
                    onAppTheme = { preferences = preferences.copy(appTheme = it) },
                    onSeparateReaderTheme = { preferences = preferences.copy(usesSeparateReaderTheme = it) },
                    onReaderTheme = { preferences = preferences.copy(readerTheme = it) },
                )
            }
        }

        compose.onNodeWithTag("settings.appearance.light").assertIsSelected()
        compose.onNodeWithTag("settings.appearance.reader.paper").assertDoesNotExist()
        compose.onNodeWithTag("settings.appearance.separateReader").performClick()
        compose.onNodeWithTag("settings.appearance.reader.paper").assertIsSelected()
        compose.onNodeWithTag("settings.appearance.reader.dark").performClick()
        compose.onNodeWithTag("settings.appearance.reader.dark").assertIsSelected()
        compose.onNodeWithTag("settings.appearance.separateReader").performClick()
        compose.onNodeWithTag("settings.appearance.reader.dark").assertDoesNotExist()
        compose.onNodeWithTag("settings.appearance.light").assertIsSelected()
    }
}
