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
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.unit.dp
import com.hadithly.app.core.data.EvidenceCitation
import com.hadithly.app.core.data.ReaderTranslation
import com.hadithly.app.core.data.ReaderHadith
import com.hadithly.app.core.data.AuthenticityClaim
import com.hadithly.app.core.data.ReaderCitation
import com.hadithly.app.core.theme.HadithlyTheme
import org.junit.Rule
import org.junit.Test

class EvidenceProcessingStatusTest {
    @get:Rule val compose = createComposeRule()

    @Test fun communitySourceSheetDoesNotClaimAIAuthorship() {
        compose.setContent {
            HadithlyTheme {
                CitationsSheet(ReaderTranslation("fixture", "This is a test text.", source = "community", sourceLabel = "Community", citations = listOf(ReaderCitation("https://example.org/fixture", "Licensed source", "example.org"))))
            }
        }
        compose.onNodeWithTag("translation.sources.community").assertIsDisplayed()
        compose.onNodeWithTag("translation.sources.ai").assertDoesNotExist()
    }

    @Test fun englishReaderUsesPublishedCommunityTextAndOpensItsSources() {
        val showSources = mutableStateOf(false)
        val translation = ReaderTranslation("fixture", "Published fixture text", source = "community", sourceLabel = "Community", citations = listOf(ReaderCitation("https://example.org/fixture")))
        val hadith = ReaderHadith("fixture", "local_dump", "local_dump:e3_fixture:9002", "9002", "e3_fixture", arabicText = "اختبار", englishText = "Provider fallback", referenceDisplay = "Synthetic", collectionName = "Synthetic", authenticity = AuthenticityClaim("unverified", claimScope = "none", sourceLabel = "Fixture", sourceName = "Fixture", sourceUrl = "https://example.org", verificationMethod = "unverified"))
        compose.setContent {
            HadithlyTheme {
                if (showSources.value) CitationsSheet(translation)
                else TranslationSection(hadith, TranslationUiState.Loaded(translation), "en", {}, { showSources.value = true }, {})
            }
        }
        compose.onNodeWithText("Published fixture text").assertIsDisplayed()
        compose.onNodeWithText("Provider fallback").assertDoesNotExist()
        compose.onNodeWithText("Community").assertHeightIsAtLeast(48.dp).performClick()
        compose.onNodeWithTag("translation.sources.community").assertIsDisplayed()
        compose.onNodeWithTag("translation.sources.ai").assertDoesNotExist()
    }

    @Test fun e3PrivateReviewStatesShowCitationsWithoutScores() {
        val status = mutableStateOf("under_review")
        compose.setContent {
            HadithlyTheme {
                Column {
                    listOf("under_review", "held", "rejected", "review_unavailable", "approved").forEach { value ->
                        TextButton(onClick = { status.value = value }) { Text(value) }
                    }
                    EvidenceProcessingStatusContent(status.value, emptyList(), listOf(EvidenceCitation("https://example.org/fixture", "Licensed source", "p. 1"))) {}
                }
            }
        }
        listOf("under_review", "held", "rejected", "review_unavailable", "approved").forEach { value ->
            compose.onNodeWithText(value).performClick()
            compose.onNodeWithTag("submission.$value").assertIsDisplayed()
            compose.onNodeWithTag("submission.citation.0").assertIsDisplayed().assertHasClickAction()
            compose.onNodeWithText("confidence", substring = true).assertDoesNotExist()
            compose.onNodeWithText("reputation", substring = true).assertDoesNotExist()
        }
    }

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
