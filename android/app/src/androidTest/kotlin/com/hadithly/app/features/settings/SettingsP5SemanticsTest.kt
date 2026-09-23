package com.hadithly.app.features.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import com.hadithly.app.core.preferences.ReaderTheme
import com.hadithly.app.core.theme.HadithlyTheme
import org.junit.Rule
import org.junit.Test

class SettingsP5SemanticsTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun paperThemeRadioRowsExposeOneNativeSelectionAndKeepTheirSurface() {
        compose.setContent {
            var selected by remember { mutableStateOf(ReaderTheme.SYSTEM) }
            HadithlyTheme(theme = ReaderTheme.PAPER) {
                Column {
                    SettingsSingleChoiceRow(
                        label = "System",
                        selected = selected == ReaderTheme.SYSTEM,
                        onClick = { selected = ReaderTheme.SYSTEM },
                        modifier = Modifier.testTag("settings.p5.system"),
                    )
                    SettingsSingleChoiceRow(
                        label = "Paper",
                        selected = selected == ReaderTheme.PAPER,
                        onClick = { selected = ReaderTheme.PAPER },
                        modifier = Modifier.testTag("settings.p5.paper"),
                    )
                }
            }
        }

        val radio = SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.RadioButton)
        compose.onNodeWithTag("settings.p5.system").assert(radio).assertIsSelected()
        compose.onNodeWithTag("settings.p5.paper").assert(radio).assertIsNotSelected().performClick()
        compose.onNodeWithTag("settings.p5.system").assertIsNotSelected()
        compose.onNodeWithTag("settings.p5.paper").assertIsSelected()
    }
}
