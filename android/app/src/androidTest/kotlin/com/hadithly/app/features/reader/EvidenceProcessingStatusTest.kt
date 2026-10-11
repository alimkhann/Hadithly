package com.hadithly.app.features.reader

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import com.hadithly.app.core.theme.HadithlyTheme
import org.junit.Rule
import org.junit.Test

class EvidenceProcessingStatusTest {
    @get:Rule val compose = createComposeRule()

    @Test fun processingFailedInfectedReadyAndRetryUseTheProductionContent() {
        val status = mutableStateOf("awaiting_processing")
        compose.setContent {
            HadithlyTheme {
                Column {
                    listOf("processing_failed", "infected", "evidence_ready").forEach { value ->
                        TextButton(onClick = { status.value = value }) { Text(value) }
                    }
                    EvidenceProcessingStatusContent(status.value, listOf("test-item")) { status.value = "awaiting_processing" }
                }
            }
        }
        compose.onNodeWithTag("submission.processing").assertIsDisplayed()
        compose.onNodeWithText("processing_failed").performClick()
        compose.onNodeWithTag("submission.failed").assertIsDisplayed()
        compose.onNodeWithTag("submission.retryProcessing").performClick()
        compose.onNodeWithTag("submission.processing").assertIsDisplayed()
        compose.onNodeWithText("infected").performClick()
        compose.onNodeWithTag("submission.infected").assertIsDisplayed()
        compose.onNodeWithTag("submission.retryProcessing").assertDoesNotExist()
        compose.onNodeWithText("evidence_ready").performClick()
        compose.onNodeWithTag("submission.ready").assertIsDisplayed()
        compose.onNodeWithText("ClamAV", substring = true).assertDoesNotExist()
    }
}
