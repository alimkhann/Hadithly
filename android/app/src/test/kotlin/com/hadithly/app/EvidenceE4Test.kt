package com.hadithly.app

import com.hadithly.app.core.data.EvidenceAppealState
import com.hadithly.app.core.data.PublicationAvailability
import com.hadithly.app.core.data.ReaderTranslation
import com.hadithly.app.features.reader.TranslationUiState
import com.hadithly.app.features.reader.keepAvailableTranslations
import org.junit.Assert.*
import org.junit.Test

class EvidenceE4Test {
    @Test fun appealDeadlineAndPendingStateAreEnforced() {
        assertTrue(EvidenceAppealState(true, 100.0, "not_requested").canRequest(99))
        assertFalse(EvidenceAppealState(true, 100.0, "not_requested").canRequest(100))
        assertFalse(EvidenceAppealState(true, 100.0, "processing").canRequest(99))
    }
    @Test fun revocationAndDifferentDeadlinesRemoveLoadedTextAndCitations() {
        val original = mapOf("one" to TranslationUiState.Loaded(ReaderTranslation("first", "Test one", source = "community", sourceLabel = "Community")), "two" to TranslationUiState.Loaded(ReaderTranslation("second", "Test two", source = "community", sourceLabel = "Community")))
        val statuses = listOf(PublicationAvailability("first", true, 100.0), PublicationAvailability("second", true, 200.0))
        val first = keepAvailableTranslations(original, statuses, 100)
        assertFalse(first.containsKey("one"))
        assertTrue(first.containsKey("two"))
        assertTrue(keepAvailableTranslations(first, statuses, 200).isEmpty())
        assertTrue(keepAvailableTranslations(original, listOf(PublicationAvailability("first", false), PublicationAvailability("second", false)), 0).isEmpty())
    }
}
