package com.hadithly.app

import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.text.TextLayoutResult
import androidx.test.platform.app.InstrumentationRegistry
import com.hadithly.app.core.preferences.nativeText
import com.hadithly.app.core.data.FirstReadingResult
import com.hadithly.app.core.theme.HadithlyTheme
import com.hadithly.app.features.onboarding.FirstReadingSession
import com.hadithly.app.features.onboarding.FirstReadingContent
import com.hadithly.app.features.onboarding.FirstReadingPhase
import kotlinx.serialization.json.Json
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.onCompletion
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class FirstReadingContentTest {
    @get:Rule val compose = createComposeRule()
    private fun fixture(name: String): FirstReadingResult {
        val source = InstrumentationRegistry.getInstrumentation().context.assets.open("first-reading/$name.json").bufferedReader().use { it.readText() }
        return Json.decodeFromString(source)
    }

    @Test fun unavailableHasLanguageChoiceWithoutRetryOrFalseReading() {
        var choices = 0
        var renders = 0
        compose.setContent { HadithlyTheme { FirstReadingContent(FirstReadingPhase.Result(fixture("unavailable-ru")), {}, { choices++ }, {}, { renders++ }) } }
        compose.onNodeWithTag("onboarding.chooseReadingLanguage").assertIsDisplayed().performClick()
        compose.onNodeWithTag("onboarding.dailyRetry").assertDoesNotExist()
        compose.onNodeWithTag("onboarding.dailyText").assertDoesNotExist()
        compose.runOnIdle { assertEquals(1, choices); assertEquals(0, renders) }
    }

    @Test fun transportRetryRendersExactTextAndOpensThatTarget() {
        val phase = mutableStateOf<FirstReadingPhase>(FirstReadingPhase.Failed)
        var opened: String? = null
        compose.setContent { HadithlyTheme { FirstReadingContent(phase.value, { phase.value = FirstReadingPhase.Result(fixture("starter-ru")) }, {}, { opened = it.canonicalId }) } }
        compose.onNodeWithTag("onboarding.dailyRetry").assertIsDisplayed().performClick()
        compose.onNodeWithText("Exact ru translation").assertIsDisplayed()
        compose.onNodeWithTag("onboarding.readingOrigin").assertTextEquals(InstrumentationRegistry.getInstrumentation().targetContext.nativeText("A first reading"))
        compose.onNodeWithTag("onboarding.dailyRetry").assertDoesNotExist()
        compose.onNodeWithTag("hadith.text.arabic").assertDoesNotExist()
        compose.onNodeWithTag("onboarding.readingArabic").performScrollTo().performClick()
        compose.onNodeWithTag("hadith.text.arabic").assertExists()
        compose.onNodeWithTag("onboarding.readingArabic").performClick()
        compose.onNodeWithTag("onboarding.readingCredits").performScrollTo().performClick()
        compose.onNodeWithText("Fixture display permission").assertExists()
        compose.onNodeWithTag("onboarding.openReading").performClick()
        compose.runOnIdle { assertEquals("sunnah_now:bukhari:1", opened) }
    }

    @Test fun dailyOriginIsVisible() {
        compose.setContent { HadithlyTheme { FirstReadingContent(FirstReadingPhase.Result(fixture("daily-ru")), {}, {}, {}) } }
        compose.onNodeWithTag("onboarding.readingOrigin").assertTextEquals(InstrumentationRegistry.getInstrumentation().targetContext.nativeText("Today's hadith"))
    }

    @Test fun fullTranslationIsNotClippedToThreeLines() {
        val result = fixture("starter-ru")
        check(result is FirstReadingResult.Ready)
        val full = result.copy(reading = result.reading.copy(text = result.reading.text.copy(text = "A complete reading sentence. ".repeat(32))))
        compose.setContent { HadithlyTheme { FirstReadingContent(FirstReadingPhase.Result(full), {}, {}, {}) } }
        val layouts = mutableListOf<TextLayoutResult>()
        compose.onNodeWithTag("hadith.text.translation").performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        assertTrue(layouts.single().lineCount > 3)
        assertFalse(layouts.single().hasVisualOverflow)
    }

    @Test fun arabicOriginalDoesNotDuplicateTranslationLayer() {
        compose.setContent { HadithlyTheme { FirstReadingContent(FirstReadingPhase.Result(fixture("original-ar")), {}, {}, {}) } }
        compose.onNodeWithTag("hadith.text.arabic").assertIsDisplayed()
        compose.onNodeWithTag("hadith.text.translation").assertDoesNotExist()
        compose.onNodeWithTag("onboarding.dailyRetry").assertDoesNotExist()
    }
    @Test fun subscriptionWithdrawalClearsDisplayedReading() {
        val results = MutableStateFlow(fixture("starter-ru"))
        compose.setContent { HadithlyTheme { FirstReadingSession("ru", { results }) } }
        compose.onNodeWithTag("onboarding.dailyText").assertIsDisplayed()
        compose.runOnIdle { results.value = fixture("unavailable-ru") }
        compose.waitUntil(5_000) { compose.onAllNodesWithTag("onboarding.readingUnavailable").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("onboarding.dailyText").assertDoesNotExist()
    }

    @Test fun permissionExpiresWithoutAnotherServerEmission() {
        val initial = fixture("starter-ru") as FirstReadingResult.Ready
        val results = MutableStateFlow<FirstReadingResult>(initial.copy(validUntil = System.currentTimeMillis() + 2_000.0))
        compose.setContent { HadithlyTheme { FirstReadingSession("ru", { results }) } }
        compose.onNodeWithTag("onboarding.dailyText").assertIsDisplayed()
        compose.waitUntil(5_000) { compose.onAllNodesWithTag("onboarding.readingUnavailable").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("onboarding.dailyText").assertDoesNotExist()
    }

    @Test fun changingLanguageCancelsTheOldSubscription() {
        val locale = mutableStateOf("ru")
        val streams = mapOf("ru" to MutableStateFlow(fixture("starter-ru")), "en" to MutableStateFlow(fixture("starter-en")))
        val stopped = mutableListOf<String>()
        compose.setContent { HadithlyTheme { FirstReadingSession(locale.value, { language -> streams.getValue(language).onCompletion { stopped.add(language) } }) } }
        compose.onNodeWithText("Exact ru translation").assertIsDisplayed()
        compose.runOnIdle { locale.value = "en" }
        compose.waitUntil(5_000) { compose.onAllNodesWithText("Existing English 1").fetchSemanticsNodes().isNotEmpty() }
        compose.runOnIdle {
            assertTrue(stopped.contains("ru"))
            streams.getValue("ru").value = fixture("unavailable-ru")
        }
        compose.onNodeWithText("Existing English 1").assertIsDisplayed()
        compose.onNodeWithText("Exact ru translation").assertDoesNotExist()
    }

}
