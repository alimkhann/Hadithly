package com.hadithly.app.core.data

import android.content.Context
import android.util.AtomicFile
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
    val updatedAt: Double? = null,
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
    val syncPartitions: List<LibrarySyncPartition> = emptyList(),
    val deletions: List<LibraryDeletionIntent> = emptyList(),
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
    private val atomicFile = AtomicFile(file)
    var onGuestChanged: (() -> Unit)? = null

    private suspend fun read(): GuestStoreFile = mutex.withLock { readLocked() }

    private fun readLocked(): GuestStoreFile {
        if (!file.exists() && !File(file.path + ".bak").exists()) return GuestStoreFile()
        return try { atomicFile.openRead().bufferedReader().use { json.decodeFromString<GuestStoreFile>(it.readText()) } }
        catch (_: Exception) { throw LibrarySyncFailure.StoreUnavailable }
    }

    private suspend fun writeLocked(notify: Boolean = true, transform: (GuestStoreFile) -> GuestStoreFile) {
        mutex.withLock {
            val next = transform(readLocked())
            withContext(Dispatchers.IO) {
                file.parentFile?.mkdirs()
                val stream = atomicFile.startWrite()
                try {
                    stream.write(json.encodeToString(next).toByteArray(Charsets.UTF_8))
                    atomicFile.finishWrite(stream)
                    if (notify) onGuestChanged?.invoke()
                } catch (error: Exception) { atomicFile.failWrite(stream); throw error }
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
            memberships + GuestSavedMembership(hadithId, folderLocalId, nowMillis())
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
                .map { GuestSavedMembership(it, deletion.folder.localId, nowMillis()) },
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

    suspend fun removeProgress(expected: GuestReadingProgressDraft) = writeLocked { store ->
        store.copy(progress = store.progress.filterNot { it == expected })
    }

    suspend fun syncPartition(owner: LibrarySyncOwner): LibraryPartitionState? = mutex.withLock {
        readLocked().syncPartitions.firstOrNull { it.ownerKey == owner.storageKey }?.also {
            if (it.subject != owner.subject) throw LibrarySyncFailure.OwnerMismatch
        }?.state
    }

    suspend fun claimGuestForSync(owner: LibrarySyncOwner) = writeLocked(notify = false) { store ->
        if (store.deletions.any { it.subject == owner.subject && it.namespace == owner.namespace }) throw LibrarySyncFailure.AccountDeleting
        val existing = store.syncPartitions.firstOrNull { it.ownerKey == owner.storageKey }
        if (existing != null && existing.subject != owner.subject) throw LibrarySyncFailure.OwnerMismatch
        val state = existing?.state ?: LibraryPartitionState()
        for (draft in store.savedFolders) {
            val name = draft.name.trim()
            state.append(LibraryLocalSource.Folder(draft), if (name.isNotEmpty() && name.codePointCount(0, name.length) <= LibrarySyncLimits.folderLength && name.none { Character.isISOControl(it) })
                SyncCommand.FolderCreate(draft.localId, draft.name, SyncCommandFolderCreatePurpose.GUEST_CLAIM) else null, draft.createdAt)
        }
        for (draft in store.bookmarks) state.append(LibraryLocalSource.Bookmark(draft), SyncCommand.BookmarkAdd(draft.hadithId, draft.createdAt), draft.createdAt)
        for (draft in store.favorites) state.append(LibraryLocalSource.Favorite(draft), SyncCommand.FavoriteAdd(draft.hadithId, draft.createdAt), draft.createdAt)
        for (draft in store.notes) state.append(LibraryLocalSource.Note(draft), if (draft.content.isNotEmpty() && draft.content.toByteArray(Charsets.UTF_8).size <= LibrarySyncLimits.noteBytes)
            SyncCommand.NotePut(draft.hadithId, draft.content, draft.createdAt, draft.updatedAt) else null, draft.updatedAt)
        for (draft in store.savedMemberships) {
            val known = store.savedFolders.firstOrNull { it.localId == draft.folderLocalId }?.createdAt ?: 0.0
            state.append(LibraryLocalSource.Membership(draft), SyncCommand.MembershipPut(draft.hadithId, SyncFolderReference.Local(draft.folderLocalId)), draft.updatedAt ?: known)
        }
        for (draft in store.progress) state.append(LibraryLocalSource.Position(draft), draft.readingPosition?.let { SyncCommand.PositionPut(it) }
            ?: SyncCommand.LegacyPositionPut(draft.hadithId, draft.updatedAt), draft.effectiveUpdatedAt)
        store.copy(bookmarks = emptyList(), notes = emptyList(), favorites = emptyList(), progress = emptyList(), savedFolders = emptyList(), savedMemberships = emptyList(),
            syncPartitions = store.syncPartitions.filterNot { it.ownerKey == owner.storageKey } + LibrarySyncPartition(owner.storageKey, owner.subject, state))
    }

    suspend fun freezeSyncFrame(owner: LibrarySyncOwner): SyncFrame? {
        var batch: SyncFrame? = null
        writeLocked(notify = false) { store ->
            val partition = store.syncPartitions.firstOrNull { it.ownerKey == owner.storageKey } ?: return@writeLocked store
            if (partition.subject != owner.subject) throw LibrarySyncFailure.OwnerMismatch
            batch = partition.state.freeze()
            store
        }
        return batch
    }

    suspend fun enqueueSyncChange(change: LibraryLocalChange, owner: LibrarySyncOwner) = writeLocked(notify = false) { store ->
        val partition = store.syncPartitions.firstOrNull { it.ownerKey == owner.storageKey } ?: throw LibrarySyncFailure.SessionChanged
        if (partition.subject != owner.subject) throw LibrarySyncFailure.OwnerMismatch
        val state = partition.state
        state.pending = state.pending + change
        store.copy(syncPartitions = store.syncPartitions.filterNot { it.ownerKey == owner.storageKey } + LibrarySyncPartition(owner.storageKey, owner.subject, state))
    }

    private fun validateSyncOwner(owner: LibrarySyncOwner, replyOwner: String, cursor: SyncCursor? = null) {
        if (replyOwner != owner.key || cursor?.active?.reply?.ownerKey?.let { it != owner.key } == true) throw LibrarySyncFailure.OwnerMismatch
    }

    suspend fun settleSyncExchange(exchange: SyncExchange, requested: SyncFrame, owner: LibrarySyncOwner, now: Double = nowMillis()) = writeLocked(notify = false) { store ->
        when (exchange) {
            is SyncExchange.Accepted -> validateSyncOwner(owner, exchange.committed.reply.ownerKey)
            is SyncExchange.Reconcile -> validateSyncOwner(owner, exchange.ownerKey, exchange.cursor)
        }
        val partition = store.syncPartitions.firstOrNull { it.ownerKey == owner.storageKey } ?: return@writeLocked store
        if (partition.subject != owner.subject) throw LibrarySyncFailure.OwnerMismatch
        partition.state.settle(exchange, requested, now)
        store
    }

    suspend fun settleSyncAcknowledgement(reply: SyncAckReply, requested: SyncAcknowledgement, owner: LibrarySyncOwner) = writeLocked(notify = false) { store ->
        validateSyncOwner(owner, reply.ownerKey, reply.cursor)
        val partition = store.syncPartitions.firstOrNull { it.ownerKey == owner.storageKey } ?: return@writeLocked store
        if (partition.subject != owner.subject) throw LibrarySyncFailure.OwnerMismatch
        partition.state.settleAcknowledgement(reply, requested)
        store
    }

    suspend fun cacheSavedSnapshot(snapshot: SyncSavedSnapshot, owner: LibrarySyncOwner) = writeLocked(notify = false) { store ->
        if (snapshot.ownerKey != owner.key) throw LibrarySyncFailure.OwnerMismatch
        val partition = store.syncPartitions.firstOrNull { it.ownerKey == owner.storageKey } ?: throw LibrarySyncFailure.SessionChanged
        if (partition.subject != owner.subject) throw LibrarySyncFailure.OwnerMismatch
        if (!snapshot.version.isFinite() || snapshot.version < 0 || kotlin.math.floor(snapshot.version) != snapshot.version) throw LibrarySyncFailure.InvalidReceipt
        if (snapshot.version >= (partition.state.savedSnapshot?.version ?: -1.0)) {
            partition.state.savedSnapshot = snapshot
            partition.state.pruneConfirmed()
        }
        store
    }

    suspend fun cachePositionsSnapshot(snapshot: SyncPositionsSnapshot, owner: LibrarySyncOwner) = writeLocked(notify = false) { store ->
        if (snapshot.ownerKey != owner.key) throw LibrarySyncFailure.OwnerMismatch
        val partition = store.syncPartitions.firstOrNull { it.ownerKey == owner.storageKey } ?: throw LibrarySyncFailure.SessionChanged
        if (partition.subject != owner.subject) throw LibrarySyncFailure.OwnerMismatch
        if (!snapshot.version.isFinite() || snapshot.version < 0 || kotlin.math.floor(snapshot.version) != snapshot.version) throw LibrarySyncFailure.InvalidReceipt
        if (snapshot.version >= (partition.state.positionsSnapshot?.version ?: -1.0)) {
            partition.state.positionsSnapshot = snapshot
            partition.state.pruneConfirmed()
        }
        store
    }

    suspend fun deletionPhase(subject: String, namespace: String): LibraryDeletionPhase? = mutex.withLock {
        readLocked().deletions.firstOrNull { it.subject == subject && it.namespace == namespace }?.phase
    }
    suspend fun beginDeletion(subject: String, namespace: String) = writeLocked(notify = false) { store ->
        if (store.deletions.any { it.subject == subject && it.namespace == namespace }) store
        else store.copy(deletions = store.deletions + LibraryDeletionIntent(subject, namespace, LibraryDeletionPhase.SERVER_PENDING))
    }
    suspend fun markDeletionBackendComplete(subject: String, namespace: String) = writeLocked(notify = false) { store ->
        if (store.deletions.none { it.subject == subject && it.namespace == namespace }) throw LibrarySyncFailure.SessionChanged
        store.copy(deletions = store.deletions.map { if (it.subject == subject && it.namespace == namespace) it.copy(phase = LibraryDeletionPhase.IDENTITY_PENDING) else it },
            syncPartitions = store.syncPartitions.filterNot { it.subject == subject && it.ownerKey.startsWith("$namespace|") })
    }
    suspend fun clearDeletion(subject: String, namespace: String) = writeLocked(notify = false) { store ->
        store.copy(deletions = store.deletions.filterNot { it.subject == subject && it.namespace == namespace })
    }

    suspend fun eraseSyncPartition(owner: LibrarySyncOwner) = writeLocked(notify = false) { store ->
        store.copy(syncPartitions = store.syncPartitions.filterNot { it.ownerKey == owner.storageKey && it.subject == owner.subject })
    }


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
