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
import java.util.UUID

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
    val position: ReadingPosition? = null,
) {
    val readingPosition: ReadingPosition?
        get() = position ?: run {
            val currentVolumeId = volumeId ?: return@run null
            val currentHadithNumber = hadithNumber ?: return@run null
            ReadingPosition.legacy(
                collectionSlug = collectionSlug,
                providerHadithId = currentHadithNumber,
                volumeId = currentVolumeId,
                updatedAt = updatedAt,
            )
        }

    val effectiveUpdatedAt: Double
        get() = readingPosition?.updatedAt ?: updatedAt
}

/** A device-local folder identity. It is mapped to a private server folder at merge time. */
@Serializable
data class GuestSavedFolderDraft(
    val localId: String,
    val name: String,
    val createdAt: Double,
)

/** One zero-or-one folder placement for a canonical guest hadith target. */
@Serializable
data class GuestSavedMembership(
    val hadithId: String,
    val folderLocalId: String,
)

data class GuestFolderDeletion(
    val folder: GuestSavedFolderDraft,
    val hadithIds: List<String>,
)

data class GuestSavedItemPayload(
    val hadithId: String,
    val bookmarkCreatedAt: Double? = null,
    val favoriteCreatedAt: Double? = null,
    val noteContent: String? = null,
    val noteCreatedAt: Double? = null,
    val noteUpdatedAt: Double? = null,
    val folderLocalId: String? = null,
    val createdAt: Double,
    val updatedAt: Double,
)

@Serializable
data class GuestStoreFile(
    val bookmarks: List<GuestBookmarkDraft> = emptyList(),
    val favorites: List<GuestFavoriteDraft> = emptyList(),
    val notes: List<GuestNoteDraft> = emptyList(),
    val progress: List<GuestReadingProgressDraft> = emptyList(),
    // Defaults make V1 JSON files decode as an empty-folder V2 store.
    val savedFolders: List<GuestSavedFolderDraft> = emptyList(),
    val savedMemberships: List<GuestSavedMembership> = emptyList(),
)

/** The merge request sent to `guestMerge:mergeGuestData`. Timestamps are milliseconds. */
data class GuestMergePayload(
    val bookmarks: List<GuestBookmarkDraft> = emptyList(),
    val notes: List<GuestNoteDraft> = emptyList(),
    val favorites: List<GuestFavoriteDraft> = emptyList(),
    val readingProgress: List<GuestReadingProgressDraft> = emptyList(),
    val savedFolders: List<GuestSavedFolderDraft> = emptyList(),
    val savedItems: List<GuestSavedItemPayload> = emptyList(),
) {
    val isEmpty: Boolean
        get() = bookmarks.isEmpty() && notes.isEmpty() && favorites.isEmpty() && readingProgress.isEmpty() && savedFolders.isEmpty() && savedItems.isEmpty()
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

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
        explicitNulls = false
    }
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
        writeLocked { store -> val bookmarks = store.bookmarks.filterNot { it.hadithId == hadithId }; store.copy(bookmarks = bookmarks, savedMemberships = if (bookmarks.none { it.hadithId == hadithId } && store.favorites.none { it.hadithId == hadithId } && store.notes.none { it.hadithId == hadithId }) store.savedMemberships.filterNot { it.hadithId == hadithId } else store.savedMemberships) }

    suspend fun addFavorite(draft: GuestFavoriteDraft) =
        writeLocked { it.copy(favorites = it.favorites.filterNot { f -> f.hadithId == draft.hadithId } + draft) }

    suspend fun removeFavorite(hadithId: String) =
        writeLocked { store -> val favorites = store.favorites.filterNot { it.hadithId == hadithId }; store.copy(favorites = favorites, savedMemberships = if (favorites.none { it.hadithId == hadithId } && store.bookmarks.none { it.hadithId == hadithId } && store.notes.none { it.hadithId == hadithId }) store.savedMemberships.filterNot { it.hadithId == hadithId } else store.savedMemberships) }

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
        writeLocked { store -> val notes = store.notes.filterNot { it.hadithId == hadithId }; store.copy(notes = notes, savedMemberships = if (notes.none { it.hadithId == hadithId } && store.bookmarks.none { it.hadithId == hadithId } && store.favorites.none { it.hadithId == hadithId }) store.savedMemberships.filterNot { it.hadithId == hadithId } else store.savedMemberships) }

    suspend fun restoreNote(draft: GuestNoteDraft) = writeLocked { store ->
        if (store.notes.any { it.hadithId == draft.hadithId }) store
        else store.copy(notes = store.notes + draft)
    }

    suspend fun createSavedFolder(name: String): GuestSavedFolderDraft {
        val folder = GuestSavedFolderDraft(UUID.randomUUID().toString(), name, nowMillis())
        writeLocked { it.copy(savedFolders = it.savedFolders + folder) }
        return folder
    }

    suspend fun assignSavedFolder(hadithId: String, folderLocalId: String?) = writeLocked { store ->
        val hasSavedFacet = store.bookmarks.any { it.hadithId == hadithId }
            || store.favorites.any { it.hadithId == hadithId }
            || store.notes.any { it.hadithId == hadithId }
        if (!hasSavedFacet) return@writeLocked store
        val memberships = store.savedMemberships.filterNot { it.hadithId == hadithId }
        val nextMemberships = if (folderLocalId != null && store.savedFolders.any { it.localId == folderLocalId }) {
            memberships + GuestSavedMembership(hadithId, folderLocalId)
        } else memberships
        store.copy(savedMemberships = nextMemberships)
    }

    suspend fun deleteSavedFolder(localId: String): GuestFolderDeletion? {
        var deletion: GuestFolderDeletion? = null
        writeLocked { store ->
            val folder = store.savedFolders.firstOrNull { it.localId == localId } ?: return@writeLocked store
            deletion = GuestFolderDeletion(folder, store.savedMemberships.filter { it.folderLocalId == localId }.map { it.hadithId })
            store.copy(savedFolders = store.savedFolders.filterNot { it.localId == localId }, savedMemberships = store.savedMemberships.filterNot { it.folderLocalId == localId })
        }
        return deletion
    }

    suspend fun restoreSavedFolder(deletion: GuestFolderDeletion) = writeLocked { store ->
        if (store.savedFolders.any { it.localId == deletion.folder.localId }) return@writeLocked store
        val savedHadithIds = (store.bookmarks.map { it.hadithId } + store.favorites.map { it.hadithId } + store.notes.map { it.hadithId }).toSet()
        store.copy(
            savedFolders = store.savedFolders + deletion.folder,
            savedMemberships = store.savedMemberships + deletion.hadithIds
                .filter { it in savedHadithIds && store.savedMemberships.none { membership -> membership.hadithId == it } }
                .map { GuestSavedMembership(it, deletion.folder.localId) },
        )
    }

    suspend fun saveProgress(draft: GuestReadingProgressDraft) =
        writeLocked { store ->
            val existing = store.progress.firstOrNull { it.collectionSlug == draft.collectionSlug }
            if (existing != null && existing.effectiveUpdatedAt >= draft.effectiveUpdatedAt) {
                store
            } else {
                store.copy(
                    progress = store.progress
                        .filterNot { p -> p.collectionSlug == draft.collectionSlug } + draft
                )
            }
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
        folders: List<GuestSavedFolderDraft> = emptyList(),
        memberships: List<GuestSavedMembership> = emptyList(),
    ): GuestMergePayload {
        val validBookmarks = dedupeEarliest(bookmarks.filter { isValidHadithId(it.hadithId) }) { it.hadithId to it.createdAt }
        val validNotes = dedupeLatest(notes.filter { isValidHadithId(it.hadithId) }) { it.hadithId to it.updatedAt }
        val validFavorites = dedupeEarliest(favorites.filter { isValidHadithId(it.hadithId) }) { it.hadithId to it.createdAt }
        val validFolders = folders.filter { isValidFolderName(it.name) }.distinctBy { it.localId }
        val validFolderIds = validFolders.mapTo(mutableSetOf()) { it.localId }
        val membershipByHadith = memberships
            .filter { isValidHadithId(it.hadithId) && it.folderLocalId in validFolderIds }
            .associateBy { it.hadithId }
        val byHadith = linkedMapOf<String, GuestSavedItemPayload>()
        validBookmarks.forEach { bookmark ->
            byHadith[bookmark.hadithId] = GuestSavedItemPayload(bookmark.hadithId, bookmarkCreatedAt = bookmark.createdAt, createdAt = bookmark.createdAt, updatedAt = bookmark.createdAt)
        }
        validFavorites.forEach { favorite ->
            val previous = byHadith[favorite.hadithId]
            byHadith[favorite.hadithId] = GuestSavedItemPayload(favorite.hadithId, previous?.bookmarkCreatedAt, favorite.createdAt, previous?.noteContent, previous?.noteCreatedAt, previous?.noteUpdatedAt, createdAt = minOf(previous?.createdAt ?: favorite.createdAt, favorite.createdAt), updatedAt = maxOf(previous?.updatedAt ?: favorite.createdAt, favorite.createdAt))
        }
        validNotes.forEach { note ->
            val previous = byHadith[note.hadithId]
            byHadith[note.hadithId] = GuestSavedItemPayload(note.hadithId, previous?.bookmarkCreatedAt, previous?.favoriteCreatedAt, note.content, note.createdAt, note.updatedAt, createdAt = minOf(previous?.createdAt ?: note.createdAt, note.createdAt), updatedAt = maxOf(previous?.updatedAt ?: note.updatedAt, note.updatedAt))
        }
        val savedItems = byHadith.values.map { item -> item.copy(folderLocalId = membershipByHadith[item.hadithId]?.folderLocalId) }.sortedBy { it.hadithId }
        return GuestMergePayload(
        bookmarks = validBookmarks
            .sortedBy { it.createdAt },
        notes = validNotes
            .sortedBy { it.updatedAt },
        favorites = validFavorites
            .sortedBy { it.createdAt },
        readingProgress = dedupeLatest(
            progress.filter { it.readingPosition != null || isValidHadithId(it.hadithId) }
        ) { it.collectionSlug to it.effectiveUpdatedAt }
            .sortedBy { it.effectiveUpdatedAt },
        savedFolders = validFolders.sortedBy { it.localId },
        savedItems = savedItems,
    )
    }

    fun isValidFolderName(input: String): Boolean {
        val name = input.trim()
        return name.isNotEmpty() && name.codePointCount(0, name.length) <= 64 && name.none { it.isISOControl() }
    }

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
