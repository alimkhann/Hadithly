package com.hadithly.app

import com.hadithly.app.core.widgets.WidgetRefreshPolicy
import com.hadithly.app.core.widgets.DailyWidgetSnapshot
import com.hadithly.app.core.widgets.ContinueWidgetSnapshot
import com.hadithly.app.core.widgets.ContinueWidgetPresentation
import com.hadithly.app.features.widgets.ContinueWidgetSize
import com.hadithly.app.features.widgets.continueWidgetSize
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WidgetRefreshPolicyTest {
    @Test fun `fresh widget cache is not marked stale`() {
        assertFalse(WidgetRefreshPolicy.isStale(updatedAt = 1_000L, now = 1_000L + WidgetRefreshPolicy.MAX_AGE_MS))
    }

    @Test fun `cache beyond budget is marked stale`() {
        assertTrue(WidgetRefreshPolicy.isStale(updatedAt = 1_000L, now = 1_001L + WidgetRefreshPolicy.MAX_AGE_MS))
    }

    @Test fun `offline daily cache is visibly stale`() {
        val snapshot = DailyWidgetSnapshot(
            collectionSlug = "bukhari", providerHadithId = "1", reference = "Bukhari · 1",
            text = "Text", locale = "en", isAI = false,
            sourceScope = "Sahih collection scope · Sunnah.now", localDate = "2026-09-19",
            timezone = "Asia/Almaty", isOffline = true, updatedAt = Long.MAX_VALUE,
        )
        assertTrue(WidgetRefreshPolicy.isStale(snapshot, now = 1_000L))
    }

    @Test fun `continue snapshot contains presentation only`() {
        val snapshot = ContinueWidgetSnapshot(
            reference = "Bukhari · Hadith 57", arabicExcerpt = "نص", translationExcerpt = "A quiet reading excerpt.",
            arabicVisible = true, translationVisible = true, progressLabel = "Hadith 57 of 100", locale = "ur", updatedAt = 1_000L,
        )
        val encoded = Json.encodeToString(snapshot)
        listOf("collectionSlug", "providerHadithId", "position", "account", "note", "volumeId").forEach {
            assertFalse("Continue widget cache must not contain $it", encoded.contains(it))
        }
    }

    @Test fun `continue presentation keeps one reference and semantic progress`() {
        val presentation = ContinueWidgetPresentation("Bukhari · Hadith 57", "نص", "A quiet reading excerpt.", true, true, 0.57, "Hadith 57 of 100", "en")
        org.junit.Assert.assertEquals(listOf("Bukhari · Hadith 57", "Hadith 57 of 100"), presentation.compactLines)
        org.junit.Assert.assertEquals(2, presentation.mediumExcerptLines)
        org.junit.Assert.assertEquals(4, presentation.largeExcerptLines)
        org.junit.Assert.assertEquals("Resume reading", presentation.accessoryInlineText)
        assertFalse(presentation.isRightToLeft)
        assertTrue(ContinueWidgetPresentation("حوالہ", "متن", "text", true, true, 0.5, "Half read", "ur").isRightToLeft)
        org.junit.Assert.assertEquals("Read a hadith to continue here.", ContinueWidgetPresentation.EMPTY_MESSAGE)
        org.junit.Assert.assertEquals("Unlock Hadithly to resume reading.", ContinueWidgetPresentation.LOCK_MESSAGE)
    }

    @Test fun `continue widget chooses compact medium and large layouts`() {
        org.junit.Assert.assertEquals(ContinueWidgetSize.COMPACT, continueWidgetSize(DpSize(180.dp, 110.dp)))
        org.junit.Assert.assertEquals(ContinueWidgetSize.MEDIUM, continueWidgetSize(DpSize(240.dp, 160.dp)))
        org.junit.Assert.assertEquals(ContinueWidgetSize.LARGE, continueWidgetSize(DpSize(320.dp, 250.dp)))
    }
}
