package com.hadithly.app.features.reader

import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import com.hadithly.app.core.data.AuthenticityClaim
import com.hadithly.app.core.data.ReaderHadith
import com.hadithly.app.core.data.ReaderTranslation
import com.hadithly.app.core.data.TranslationFailure
import com.hadithly.app.core.theme.HadithlyTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class TranslationQ1Test {
    @get:Rule val compose = createComposeRule()
    private val hadith = ReaderHadith("fixture", "sunnah_now", "sunnah_now:bukhari:1", "1", "bukhari",
        arabicText = "اختبار", englishText = "Provider text", referenceDisplay = "Synthetic", collectionName = "Synthetic",
        authenticity = AuthenticityClaim("unverified", claimScope = "none", sourceLabel = "Fixture", sourceName = "Fixture", sourceUrl = "https://example.org", verificationMethod = "unverified"))

    @Test fun missingTranslationWaitsForOneExplicitHadithAction() {
        var requests = 0
        val state = mutableStateOf<TranslationUiState?>(null)
        compose.setContent { HadithlyTheme { TranslationSection(hadith, state.value, "ru", {
            requests++
            state.value = TranslationUiState.Loaded(ReaderTranslation("generated", "Generated text", source = "gemini_ai", sourceLabel = "AI"))
        }, {}, {}) } }
        compose.onNodeWithTag("reader.generateTranslation").assertHeightIsAtLeast(48.dp).assertIsDisplayed()
        compose.runOnIdle { assertEquals(0, requests) }
        compose.onNodeWithTag("reader.generateTranslation").performClick()
        compose.onNodeWithText("Generated text").assertIsDisplayed()
        compose.runOnIdle { assertEquals(1, requests) }
    }

    @Test fun onlyActualQuotaRejectionOffersPlans() {
        var paywalls = 0
        val state = mutableStateOf<TranslationUiState?>(TranslationUiState.Failed(TranslationFailure.Failed("AI_RATE_LIMITED")))
        compose.setContent { HadithlyTheme { TranslationSection(hadith, state.value, "ru", {}, {}, { paywalls++ }) } }
        compose.onNodeWithText("See plans").assertDoesNotExist()
        compose.runOnIdle { state.value = TranslationUiState.Failed(TranslationFailure.RequiresSignIn) }
        compose.onNodeWithText("See plans").assertDoesNotExist()
        compose.runOnIdle { state.value = TranslationUiState.Failed(TranslationFailure.QuotaExceeded) }
        compose.onNodeWithText("See plans").performClick()
        compose.runOnIdle { assertEquals(1, paywalls) }
    }

    @Test fun cachedGuestTranslationRendersWithoutGenerateOrPaywall() {
        compose.setContent { HadithlyTheme { TranslationSection(hadith, TranslationUiState.Loaded(
            ReaderTranslation("cached", "Cached exact-locale text", source = "official", sourceLabel = "Official", cached = true)), "ru", {}, {}, {}) } }
        compose.onNodeWithText("Cached exact-locale text").assertIsDisplayed()
        compose.onNodeWithTag("reader.generateTranslation").assertDoesNotExist()
        compose.onNodeWithText("See plans").assertDoesNotExist()
    }
}
