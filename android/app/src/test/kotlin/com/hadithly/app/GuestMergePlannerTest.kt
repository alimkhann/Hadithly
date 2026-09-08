package com.hadithly.app

import com.hadithly.app.core.data.GuestBookmarkDraft
import com.hadithly.app.core.data.GuestFavoriteDraft
import com.hadithly.app.core.data.GuestMergePlanner
import com.hadithly.app.core.data.GuestNoteDraft
import com.hadithly.app.core.data.GuestReadingProgressDraft
import com.hadithly.app.core.data.TranslationFailure
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

private const val ID_A = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" // 32 chars
private const val ID_B = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

class GuestMergePlannerTest {

    @Test
    fun `valid hadith ids are 32 lowercase alphanumeric characters`() {
        assertTrue(GuestMergePlanner.isValidHadithId(ID_A))
        assertFalse(GuestMergePlanner.isValidHadithId("short"))
        assertFalse(GuestMergePlanner.isValidHadithId("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"))
        assertFalse(GuestMergePlanner.isValidHadithId(""))
        assertFalse(GuestMergePlanner.isValidHadithId("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-"))
    }

    @Test
    fun `invalid ids are dropped from the payload`() {
        val payload = GuestMergePlanner.makePayload(
            bookmarks = listOf(
                GuestBookmarkDraft(hadithId = "bad", createdAt = 1.0),
                GuestBookmarkDraft(hadithId = ID_A, createdAt = 2.0),
            ),
            notes = emptyList(),
        )
        assertEquals(listOf(ID_A), payload.bookmarks.map { it.hadithId })
    }

    @Test
    fun `duplicate bookmarks keep the earliest record`() {
        val payload = GuestMergePlanner.makePayload(
            bookmarks = listOf(
                GuestBookmarkDraft(hadithId = ID_A, createdAt = 5.0),
                GuestBookmarkDraft(hadithId = ID_A, createdAt = 3.0),
            ),
        )
        assertEquals(1, payload.bookmarks.size)
        assertEquals(3.0, payload.bookmarks.first().createdAt, 0.0)
    }

    @Test
    fun `duplicate notes keep the most recently edited version`() {
        val payload = GuestMergePlanner.makePayload(
            notes = listOf(
                GuestNoteDraft(hadithId = ID_A, content = "old", createdAt = 1.0, updatedAt = 2.0),
                GuestNoteDraft(hadithId = ID_A, content = "new", createdAt = 1.0, updatedAt = 7.0),
            ),
        )
        assertEquals(1, payload.notes.size)
        assertEquals("new", payload.notes.first().content)
    }

    @Test
    fun `progress keeps one entry per collection with the newest position`() {
        val payload = GuestMergePlanner.makePayload(
            progress = listOf(
                GuestReadingProgressDraft(
                    collectionSlug = "bukhari", collectionName = "Bukhari",
                    hadithId = ID_A, updatedAt = 1.0,
                ),
                GuestReadingProgressDraft(
                    collectionSlug = "bukhari", collectionName = "Bukhari",
                    hadithId = ID_B, updatedAt = 9.0,
                ),
                GuestReadingProgressDraft(
                    collectionSlug = "muslim", collectionName = "Muslim",
                    hadithId = ID_A, updatedAt = 4.0,
                ),
            ),
        )
        assertEquals(2, payload.readingProgress.size)
        assertTrue(payload.readingProgress.all { it.updatedAt >= 4.0 })
    }

    @Test
    fun `favorites dedupe and sort by creation`() {
        val payload = GuestMergePlanner.makePayload(
            favorites = listOf(
                GuestFavoriteDraft(hadithId = ID_B, createdAt = 8.0),
                GuestFavoriteDraft(hadithId = ID_A, createdAt = 2.0),
            ),
        )
        assertEquals(listOf(ID_A, ID_B), payload.favorites.map { it.hadithId })
    }

    @Test
    fun `empty input produces an empty payload`() {
        val payload = GuestMergePlanner.makePayload(
            bookmarks = emptyList(), notes = emptyList(),
            favorites = emptyList(), progress = emptyList(),
        )
        assertTrue(payload.isEmpty)
    }
}

class TranslationFailureTest {

    @Test
    fun `quota wall message maps to quota exceeded`() {
        assertEquals(
            TranslationFailure.QuotaExceeded,
            TranslationFailure.of("AI_GENERATION_QUOTA_EXCEEDED"),
        )
    }

    @Test
    fun `unauthenticated maps to requires sign in`() {
        assertEquals(
            TranslationFailure.RequiresSignIn,
            TranslationFailure.of("Unauthenticated calling function"),
        )
    }

    @Test
    fun `other errors pass through as failed`() {
        val failure = TranslationFailure.of("Gemini returned 500")
        assertTrue(failure is TranslationFailure.Failed)
    }
}
