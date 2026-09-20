package com.hadithly.app

import com.hadithly.app.core.data.HadithRef
import com.hadithly.app.core.data.ProgressEntry
import com.hadithly.app.core.data.ReadingPosition
import com.hadithly.app.core.data.ReaderTargetSource
import com.hadithly.app.features.widgets.continueWidgetTarget
import org.junit.Assert.assertEquals
import org.junit.Test

class ContinueWidgetRouteTest {
    @Test fun `generic widget request uses current library position`() {
        val position = ReadingPosition.legacy("bukhari", "57", "2", 1_000.0)!!
        val entry = ProgressEntry(
            collectionSlug = "bukhari",
            hadith = HadithRef("local-only", "bukhari", "Sahih al-Bukhari", "2", "57", "", "", "Bukhari · Hadith 57"),
            position = position, updatedAt = 1_000.0,
        )
        val target = continueWidgetTarget(listOf(entry))
        assertEquals(ReaderTargetSource.CONTINUE_READING, target?.source)
        assertEquals("57", target?.position?.anchor?.providerHadithId)
        assertEquals(position.normalizedOffset, target?.position?.normalizedOffset)
    }

    @Test fun `generic widget request does nothing without current progress`() {
        assertEquals(null, continueWidgetTarget(emptyList()))
    }

    @Test fun `generic widget request prefers the newest synced position`() {
        fun entry(number: String, updatedAt: Double) = ProgressEntry(
            collectionSlug = "bukhari",
            hadith = HadithRef("local-$number", "bukhari", "Sahih al-Bukhari", "2", number, "", "", "Bukhari · Hadith $number"),
            position = ReadingPosition.legacy("bukhari", number, "2", updatedAt)!!,
            updatedAt = updatedAt,
        )
        val target = continueWidgetTarget(listOf(entry("21", 1_000.0), entry("57", 2_000.0)))
        assertEquals("57", target?.position?.anchor?.providerHadithId)
    }
}
