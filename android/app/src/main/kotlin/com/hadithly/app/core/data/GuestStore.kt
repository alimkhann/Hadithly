package com.hadithly.app.core.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File

/**
 * Local guest data — what readers collect before signing in. Stored as JSON
 * in the app's files directory. On sign-in the whole store merges into Convex
 * (idempotently) and is cleared. Mirrors the iOS SwiftData GuestDataStore.
 */
@Serializable
data class GuestBookmarkDraft(
    val hadithId: String,
    val createdAt: Double,
    val collectionName: String? = null,
    val referenceDisplay: String? = null,
    val volumeId: String? = null,
    val hadithNumber: String? = null,
    val collectionSlug: String? = null,
    val arabicText: String = "",
    val englishText: String? = null,
)

@Serializable
data class GuestFavoriteDraft(
    val hadithId: String,
    val createdAt: Double,
    val collectionName: String? = null,
    val referenceDisplay: String? = null,
    val volumeId: String? = null,
    val hadithNumber: String? = null,
    val collectionSlug: String? = null,
    val arabicText: String = "",
    val englishText: String? = null,
)

@Serializable
data class GuestNoteDraft(
    val hadithId: String,
    val content: String,
    val createdAt: Double,
    val updatedAt: Double,
    val collectionName: String? = null,
    val referenceDisplay: String? = null,
    val volumeId: String? = null,
    val hadithNumber: String? = null,
    val collectionSlug: String? = null,
    val arabicText: String = "",
    val englishText: String? = null,
)

@Serializable
data class GuestReadingProgressDraft(
    val collectionSlug: String,
    val collectionName: String,
    val hadithId: String,
    val volumeId: String? = null,
    val hadithNumber: String? = null,
    val referenceDisplay: String? = null,
    val updatedAt: Double,
    val arabicText: String = "",
    val englishText: String? = null,
)

@Serializable
data class GuestStoreFile(
    val bookmarks: List<GuestBookmarkDraft> = emptyList(),
    val favorites: List<GuestFavoriteDraft> = emptyList(),
    val notes: List<GuestNoteDraft> = emptyList(),
    val progress: List<GuestReadingProgressDraft> = emptyList(),
)

/** The merge request sent to `guestMerge:mergeGuestData`. Timestamps are milliseconds. */
data class GuestMergePayload(
    val bookmarks: List<GuestBookmarkDraft> = emptyList(),
    val notes: List<GuestNoteDraft> = emptyList(),
    val favorites: List<GuestFavoriteDraft> = emptyList(),
    val readingProgress: List<GuestReadingProgressDraft> = emptyList(),
) {
    val isEmpty: Boolean
        get() = bookmarks.isEmpty() && notes.isEmpty() && favorites.isEmpty() && readingProgress.isEmpty()
}

@Serializable
data class GuestMergeResult(
    val bookmarksMerged: Double = 0.0,
    val bookmarksSkipped: Double = 0.0,
    val notesMerged: Double = 0.0,
    val notesSkipped: Double = 0.0,
    val favoritesMerged: Double = 0.0,
    val favoritesSkipped: Double = 0.0,
    val progressMerged: Double = 0.0,
    val progressSkipped: Double = 0.0,
)

class GuestDataStore(context: Context) {

    private val json = Json { ignoreUnknownKeys = true }
    private val file: File = File(context.filesDir, "guest_store.json")
    private val mutex = Mutex()

    private suspend fun read(): GuestStoreFile = mutex.withLock { readLocked() }

    private fun readLocked(): GuestStoreFile =
        if (file.exists()) {
            runCatching { json.decodeFromString<GuestStoreFile>(file.readText()) }
                .getOrDefault(GuestStoreFile())
        } else {
            GuestStoreFile()
        }

    private suspend fun writeLocked(transform: (GuestStoreFile) -> GuestStoreFile) {
        mutex.withLock {
            val next = transform(readLocked())
            withContext(Dispatchers.IO) {
                file.parentFile?.mkdirs()
                file.writeText(json.encodeToString(next))
            }
        }
    }

    suspend fun snapshots(): GuestStoreFile = read()

    suspend fun isBookmarked(hadithId: String): Boolean =
        read().bookmarks.any { it.hadithId == hadithId }

    suspend fun isFavorite(hadithId: String): Boolean =
        read().favorites.any { it.hadithId == hadithId }

    suspend fun addBookmark(draft: GuestBookmarkDraft) =
        writeLocked { it.copy(bookmarks = it.bookmarks.filterNot { b -> b.hadithId == draft.hadithId } + draft) }

    suspend fun removeBookmark(hadithId: String) =
        writeLocked { it.copy(bookmarks = it.bookmarks.filterNot { b -> b.hadithId == hadithId }) }

    suspend fun addFavorite(draft: GuestFavoriteDraft) =
        writeLocked { it.copy(favorites = it.favorites.filterNot { f -> f.hadithId == draft.hadithId } + draft) }

    suspend fun removeFavorite(hadithId: String) =
        writeLocked { it.copy(favorites = it.favorites.filterNot { f -> f.hadithId == hadithId }) }

    suspend fun saveNote(
        hadithId: String,
        content: String,
        collectionName: String?,
        referenceDisplay: String?,
        volumeId: String?,
        hadithNumber: String?,
        collectionSlug: String?,
        arabicText: String,
        englishText: String?,
    ) {
        val now = nowMillis()
        writeLocked { store ->
            val existing = store.notes.firstOrNull { it.hadithId == hadithId }
            val next = existing?.copy(content = content, updatedAt = now)
                ?: GuestNoteDraft(
                    hadithId = hadithId,
                    content = content,
                    createdAt = now,
                    updatedAt = now,
                    collectionName = collectionName,
                    referenceDisplay = referenceDisplay,
                    volumeId = volumeId,
                    hadithNumber = hadithNumber,
                    collectionSlug = collectionSlug,
                    arabicText = arabicText,
                    englishText = englishText,
                )
            store.copy(notes = store.notes.filterNot { it.hadithId == hadithId } + next)
        }
    }

    suspend fun deleteNote(hadithId: String) =
        writeLocked { it.copy(notes = it.notes.filterNot { n -> n.hadithId == hadithId }) }

    suspend fun saveProgress(draft: GuestReadingProgressDraft) =
        writeLocked {
            it.copy(
                progress = it.progress
                    .filterNot { p -> p.collectionSlug == draft.collectionSlug } + draft
            )
        }

    suspend fun clearAll() = writeLocked { GuestStoreFile() }

    private fun nowMillis(): Double = System.currentTimeMillis().toDouble()
}

/**
 * Builds the merge payload from local guest data. Pure and deterministic so
 * the rules (dedupe, invalid-id filtering, ordering) are unit-testable
 * without Android or networking. Port of the iOS GuestMergePlanner.
 */
object GuestMergePlanner {

    /** Convex document ids are 32 lowercase alphanumeric characters. */
    fun isValidHadithId(id: String): Boolean =
        id.length == 32 && id.all { c -> c in 'a'..'z' || c in '0'..'9' }

    fun makePayload(
        bookmarks: List<GuestBookmarkDraft> = emptyList(),
        notes: List<GuestNoteDraft> = emptyList(),
        favorites: List<GuestFavoriteDraft> = emptyList(),
        progress: List<GuestReadingProgressDraft> = emptyList(),
    ): GuestMergePayload = GuestMergePayload(
        bookmarks = dedupeEarliest(bookmarks.filter { isValidHadithId(it.hadithId) }) { it.hadithId to it.createdAt }
            .sortedBy { it.createdAt },
        notes = dedupeLatest(notes.filter { isValidHadithId(it.hadithId) }) { it.hadithId to it.updatedAt }
            .sortedBy { it.updatedAt },
        favorites = dedupeEarliest(favorites.filter { isValidHadithId(it.hadithId) }) { it.hadithId to it.createdAt }
            .sortedBy { it.createdAt },
        readingProgress = dedupeLatest(progress.filter { isValidHadithId(it.hadithId) }) { it.collectionSlug to it.updatedAt }
            .sortedBy { it.updatedAt },
    )

    /** The same hadith bookmarked/favorited twice keeps its earliest record. */
    private inline fun <T> dedupeEarliest(items: List<T>, key: (T) -> Pair<String, Double>): List<T> {
        val byKey = LinkedHashMap<String, T>()
        for (item in items) {
            val (id, stamp) = key(item)
            val existing = byKey[id]
            if (existing == null || stamp < key(existing).second) byKey[id] = item
        }
        return byKey.values.toList()
    }

    /** The same hadith noted twice keeps the most recently edited version. */
    private inline fun <T> dedupeLatest(items: List<T>, key: (T) -> Pair<String, Double>): List<T> {
        val byKey = LinkedHashMap<String, T>()
        for (item in items) {
            val (id, stamp) = key(item)
            val existing = byKey[id]
            if (existing == null || stamp > key(existing).second) byKey[id] = item
        }
        return byKey.values.toList()
    }
}
