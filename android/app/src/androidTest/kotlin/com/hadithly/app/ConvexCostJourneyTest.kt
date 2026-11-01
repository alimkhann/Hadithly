package com.hadithly.app

import android.os.Process
import android.os.SystemClock
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import com.clerk.api.Clerk
import java.time.Instant
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** Existing development content only; automatic generation remains disabled. */
@OptIn(ExperimentalTestApi::class)
class ConvexCostJourneyTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test fun coldLaunchLibraryAndTenPageMoves() {
        val app = compose.activity.application as HadithlyApplication
        assertTrue(BuildConfig.CONVEX_URL.contains("festive-cobra-664"))
        assertNull("Use a guest emulator, never sign out an existing account", Clerk.user)
        val original = app.preferences.preferences.value
        assertTrue("Pin the default reading sizes", original.arabicFontSize == 26f && original.translationFontSize == 16f)
        val automatic = app.readerExperience.automaticallyTranslates.value
        val onboarded = app.settings.onboardingCompleted.value
        val started = System.currentTimeMillis() - (SystemClock.uptimeMillis() - Process.getStartUptimeMillis())
        try {
            compose.runOnIdle {
                app.readerExperience.setAutomaticTranslation(false)
                app.preferences.setUILocale("en")
                app.preferences.setTranslationLocale("en")
                app.settings.setOnboardingCompleted(true)
            }
            compose.onNodeWithTag("tabs.library").performClick()
            compose.waitUntil(30_000) { compose.onAllNodesWithTag("library.collection.bukhari").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithTag("library.collection.bukhari").performClick()
            compose.waitUntil(30_000) { compose.onAllNodesWithTag("reader.pageViewport").fetchSemanticsNodes().isNotEmpty() }
            val readerActions = SemanticsMatcher("reader navigation actions") { node ->
                node.config.getOrNull(SemanticsActions.CustomActions)
                    ?.any { it.label == "Show reader controls" || it.label == "Hide reader controls" } == true
            }
            fun showControls() {
                val reader = compose.onNode(readerActions)
                val actions = reader.fetchSemanticsNode().config[SemanticsActions.CustomActions]
                if (actions.any { it.label == "Show reader controls" }) {
                    reader.performCustomAccessibilityActionWithLabel("Show reader controls")
                }
            }
            fun position(): String = listOf("reader.unfocusedPageBar", "reader.unfocusedVolumeBar")
                .joinToString("|") { tag ->
                    compose.onNodeWithTag(tag).fetchSemanticsNode()
                        .config[SemanticsProperties.ContentDescription].joinToString()
                }
            compose.waitUntil(30_000) {
                compose.onAllNodes(readerActions).fetchSemanticsNodes().singleOrNull()
                    ?.config?.getOrNull(SemanticsActions.CustomActions)?.any { it.label == "Next page" } == true
            }
            showControls()
            println("COST_JOURNEY_STARTPOS ${position()}")
            repeat(10) { step ->
                compose.waitUntil(30_000) {
                    compose.onAllNodes(readerActions).fetchSemanticsNodes().singleOrNull()
                        ?.config?.getOrNull(SemanticsActions.CustomActions)?.any { it.label == "Next page" } == true
                }
                val previous = position()
                compose.onNode(readerActions).performCustomAccessibilityActionWithLabel("Next page")
                compose.waitUntil(30_000) {
                    showControls()
                    runCatching { position() != previous }.getOrDefault(false)
                }
                println("COST_JOURNEY_STEP ${step + 1} ${position()}")
            }
            assertNull("Guest state changed during the measurement", Clerk.user)
            println("COST_JOURNEY_JSON {\"platform\":\"android\",\"startedAtUtc\":\"${Instant.ofEpochMilli(started)}\",\"endedAtUtc\":\"${Instant.now()}\",\"pageMoves\":10,\"locale\":\"en\",\"auth\":\"guest\",\"automaticGeneration\":false}")
        } finally {
            compose.runOnIdle {
                app.preferences.setUILocale(original.uiLocale)
                app.preferences.setTranslationLocale(original.translationLocale)
                app.readerExperience.setAutomaticTranslation(automatic)
                app.settings.setOnboardingCompleted(onboarded)
            }
        }
    }
}
