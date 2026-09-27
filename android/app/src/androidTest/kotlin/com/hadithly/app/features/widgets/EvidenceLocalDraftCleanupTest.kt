package com.hadithly.app.features.widgets

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.hadithly.app.core.data.EvidenceLocalDrafts
import com.hadithly.app.core.data.LocalEvidenceChoice
import com.hadithly.app.core.data.LocalEvidenceDraft
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class EvidenceLocalDraftCleanupTest {
    @Test fun accountDeletionRemovesOnlyOwnedDraftsAndFiles() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.filesDir, "evidenceDrafts").apply { mkdirs() }
        val first = File(directory, UUID.randomUUID().toString()).apply { writeText("first") }
        val second = File(directory, UUID.randomUUID().toString()).apply { writeText("second") }
        val firstOwner = "test-${UUID.randomUUID()}"
        val secondOwner = "test-${UUID.randomUUID()}"
        val firstKey = "evidence.draft.$firstOwner.hadith"
        val secondKey = "evidence.draft.$secondOwner.hadith"
        val prefs = context.getSharedPreferences(EvidenceLocalDrafts.PREFERENCES_NAME, 0)
        try {
            for ((key, file) in listOf(firstKey to first, secondKey to second)) {
                val draft = LocalEvidenceDraft(
                    draftKey = UUID.randomUUID().toString(), proposedContent = "Private suggestion",
                    urlInput = "", choices = listOf(LocalEvidenceChoice("file", "file", "Evidence", filePath = file.absolutePath)),
                    createdAt = 1_000,
                )
                prefs.edit().putString(key, Json.encodeToString(draft)).commit()
            }

            EvidenceLocalDrafts.clearForAccount(context, firstOwner)

            assertNull(prefs.getString(firstKey, null))
            assertFalse(first.exists())
            assertNotNull(prefs.getString(secondKey, null))
            assertTrue(second.exists())
        } finally {
            prefs.edit().remove(firstKey).remove(secondKey).commit()
            first.delete()
            second.delete()
        }
    }
}
