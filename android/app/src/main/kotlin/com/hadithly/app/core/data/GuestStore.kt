package com.hadithly.app.core.data

import android.content.Context
import android.util.AtomicFile
import android.database.sqlite.SQLiteDatabase
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import java.util.UUID

/** Private local drafts. Guest and account state share the outcome journal's SQLite transaction. */
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
    val folderUpdatedAt: Double? = null,
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

    private val file = File(context.filesDir, "guest_store.json")
    private val atomicFile = AtomicFile(file)
    private val mutex = Mutex()
    private val outcomeJournal by lazy { LibraryOutcomeJournal(context) }
    var onGuestChanged: (() -> Unit)? = null

    private fun legacyBytes(): ByteArray? {
        if (!file.exists() && !File(file.path + ".bak").exists()) return null
        return try { atomicFile.openRead().use { it.readBytes() } }
        catch (_: Exception) { throw LibrarySyncFailure.StoreUnavailable }
    }
    private fun clearLegacyFiles() {
        for (path in listOf(file, File(file.path + ".bak"), File(file.path + ".new"))) {
            if (path.exists() && !path.delete() && path.exists()) throw LibrarySyncFailure.StoreUnavailable
        }
    }
    private suspend fun ensureReady() {
        val source = withContext(Dispatchers.IO) { outcomeJournal.localImportSource(::legacyBytes) }
        if (source != null) {
            while (withContext(Dispatchers.IO) { outcomeJournal.advanceLocalImport(source, ::legacyBytes) }) kotlinx.coroutines.yield()
        }
        withContext(Dispatchers.IO) {
            outcomeJournal.cleanupLocalImportStep()
            try { clearLegacyFiles() } catch (_: LibrarySyncFailure.StoreUnavailable) { /* Deletion retries this strictly before identity cleanup. */ }
        }
    }
    private suspend fun <T> withStorage(block: suspend () -> T): T {
        ensureReady()
        return mutex.withLock { block() }
    }
    private suspend fun read(): GuestSnapshot = withStorage { withContext(Dispatchers.IO) { outcomeJournal.localGuest() } }
    private suspend fun writeLocked(notify: Boolean = true, transform: (GuestSnapshot) -> GuestSnapshot) {
        val changed = withStorage { withContext(Dispatchers.IO) { outcomeJournal.updateLocalGuest(transform) } }
        if (changed && notify) onGuestChanged?.invoke()
    }
    private suspend fun <T> accountWrite(owner: LibrarySyncOwner, block: (SQLiteDatabase, LibraryPartitionState) -> T): T = withStorage {
        withContext(Dispatchers.IO) { outcomeJournal.mutateLocalAccount(owner, block) }
    }
    suspend fun snapshots(): GuestSnapshot = read()

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

    suspend fun syncPartition(owner: LibrarySyncOwner): LibraryPartitionState? = withStorage {
        withContext(Dispatchers.IO) { outcomeJournal.localAccount(owner) }
    }
    suspend fun claimGuestForSync(owner: LibrarySyncOwner) = withStorage {
        withContext(Dispatchers.IO) { outcomeJournal.claimLocalGuest(owner) }
    }
    suspend fun freezeSyncFrame(owner: LibrarySyncOwner): SyncFrame? = accountWrite(owner) { _, state -> state.freeze() }
    suspend fun enqueueSyncChange(change: LibraryLocalChange, owner: LibrarySyncOwner) = accountWrite(owner) { _, state -> state.pending = state.pending + change }
    private fun validateSyncOwner(owner: LibrarySyncOwner, replyOwner: String, cursor: SyncCursor? = null) {
        if (replyOwner != owner.key || cursor?.outstanding?.committedValue?.reply?.ownerKey?.let { it != owner.key } == true) throw LibrarySyncFailure.OwnerMismatch
    }
    private fun validateExchange(owner: LibrarySyncOwner, exchange: SyncExchange) {
        when (exchange) {
            is SyncExchange.Accepted -> validateSyncOwner(owner, exchange.committed.reply.ownerKey)
            is SyncExchange.Pending -> validateSyncOwner(owner, exchange.ownerKey)
            is SyncExchange.Reconcile -> validateSyncOwner(owner, exchange.ownerKey, exchange.cursor)
        }
    }
    suspend fun settleSyncExchange(exchange: SyncExchange, requested: SyncFrame, owner: LibrarySyncOwner, now: Double = nowMillis()) {
        validateExchange(owner, exchange)
        accountWrite(owner) { _, state -> state.settle(exchange, requested, now) }
    }
    suspend fun settleSyncPending(exchange: SyncExchange, requested: SyncPending, owner: LibrarySyncOwner, now: Double = nowMillis()) {
        validateExchange(owner, exchange)
        accountWrite(owner) { _, state -> state.settlePending(exchange, requested, now) }
    }
    suspend fun settleSyncRetirement(reply: SyncAckReply, requested: SyncFrame, owner: LibrarySyncOwner) {
        validateSyncOwner(owner, reply.ownerKey, reply.cursor)
        accountWrite(owner) { _, state -> state.settleRetirement(reply, requested) }
    }
    suspend fun settleSyncAcknowledgement(reply: SyncAckReply, requested: SyncAcknowledgement, owner: LibrarySyncOwner, now: Double = nowMillis()) = accountWrite(owner) { db, state ->
        validateSyncOwner(owner, reply.ownerKey, reply.cursor)
        val link = state.manifestAckLink; state.settleAcknowledgement(reply, requested)
        if (link != null && reply.cursor.closedThrough >= requested.sequence) {
            val binding = LibraryOutcomeBinding(link.owner, link.committed)
            if (link.owner != owner || binding.request.proof != requested) throw LibrarySyncFailure.InvalidReceipt
            outcomeJournal.acknowledgeIn(db, binding, now)
        }
    }
    suspend fun pruneOutcomeSuccessStep(owner: LibrarySyncOwner, now: Double): Boolean = accountWrite(owner) { db, state ->
        if (!now.isFinite() || now < 0) throw LibrarySyncFailure.InvalidReceipt
        if (!outcomeJournal.prepareExportStepIn(db)) return@accountWrite true
        val entries = outcomeJournal.retentionEntriesIn(db, owner, state.outcomeRetentionCursor)
        if (entries.isEmpty()) { state.outcomeRetentionCursor = null; return@accountWrite false }
        var cursor = state.outcomeRetentionCursor
        for (entry in entries) {
            val binding = entry.binding
            val dependency = if (binding.owner == owner) state else readLocalAccount(db, binding.owner)
            if (dependency != null && (entry.checkpoint.retention?.removed != null || dependency.canPruneOutcome(binding, entry.checkpoint, now))) {
                if (outcomeJournal.pruneIn(db, binding, entry.checkpoint)) cursor = binding.key
                state.outcomeRetentionCursor = cursor; return@accountWrite true
            }; cursor = binding.key
        }
        state.outcomeRetentionCursor = cursor; true
    }
    suspend fun settleCollectedOutcome(expected: LibraryPendingOutcome, owner: LibrarySyncOwner, now: Double): LibraryOutcomeSettlement = accountWrite(owner) { db, state ->
        val binding = LibraryOutcomeBinding(owner, expected.committed)
        state.settleCollectedOutcome(expected, binding, outcomeJournal.settlementCheckpointIn(db, binding), now)
    }
    suspend fun cacheSavedSnapshot(snapshot: SyncSavedSnapshot, owner: LibrarySyncOwner) = accountWrite(owner) { _, state ->
        if (snapshot.ownerKey != owner.key) throw LibrarySyncFailure.OwnerMismatch
        if (!snapshot.version.isFinite() || snapshot.version < 0 || kotlin.math.floor(snapshot.version) != snapshot.version) throw LibrarySyncFailure.InvalidReceipt
        if (snapshot.version >= (state.savedSnapshot?.version ?: -1.0)) { state.savedSnapshot = snapshot; state.pruneConfirmed() }
    }
    suspend fun cachePositionsSnapshot(snapshot: SyncPositionsSnapshot, owner: LibrarySyncOwner) = accountWrite(owner) { _, state ->
        if (snapshot.ownerKey != owner.key) throw LibrarySyncFailure.OwnerMismatch
        if (!snapshot.version.isFinite() || snapshot.version < 0 || kotlin.math.floor(snapshot.version) != snapshot.version) throw LibrarySyncFailure.InvalidReceipt
        if (snapshot.version >= (state.positionsSnapshot?.version ?: -1.0)) { state.positionsSnapshot = snapshot; state.pruneConfirmed() }
    }
    suspend fun deletionPhase(subject: String, namespace: String): LibraryDeletionPhase? = withStorage {
        val phase = withContext(Dispatchers.IO) { outcomeJournal.localDeletion(subject, namespace) }
        if (phase == LibraryDeletionPhase.IDENTITY_PENDING) withContext(Dispatchers.IO) { clearLegacyFiles() }
        phase
    }
    suspend fun beginDeletion(subject: String, namespace: String) = withStorage {
        withContext(Dispatchers.IO) { outcomeJournal.beginLocalDeletion(subject, namespace) }
    }
    suspend fun markDeletionBackendComplete(subject: String, namespace: String) {
        beginSavedErase(subject, namespace, null)
        while (eraseSavedStep(subject, namespace, null)) kotlinx.coroutines.yield()
        while (withStorage { withContext(Dispatchers.IO) { outcomeJournal.eraseLocalAccountsStep(subject, namespace) } }) kotlinx.coroutines.yield()
        withStorage { withContext(Dispatchers.IO) {
            outcomeJournal.beginErase(subject, namespace, full = true)
            clearArtifactScope(subject, namespace)
            outcomeJournal.erase(subject, namespace)
            clearLegacyFiles()
        } }
        while (withStorage { withContext(Dispatchers.IO) { outcomeJournal.cleanupLocalImportStep() } }) kotlinx.coroutines.yield()
        withStorage { withContext(Dispatchers.IO) { outcomeJournal.finishLocalDeletion(subject, namespace) } }
    }
    suspend fun clearDeletion(subject: String, namespace: String) = withStorage {
        withContext(Dispatchers.IO) { outcomeJournal.clearLocalDeletion(subject, namespace) }
    }
    // Fixture only. Normal erasure remains scoped by its durable deletion intent.
    suspend fun resetSyncPartitionForTesting(owner: LibrarySyncOwner) = withStorage {
        withContext(Dispatchers.IO) {
            outcomeJournal.beginSavedErase(owner.subject, owner.namespace, owner.storageKey)
            while (outcomeJournal.eraseSavedStep(owner.subject, owner.namespace, owner.storageKey)) { }
            outcomeJournal.beginErase(owner.subject, owner.namespace, full = false)
            clearArtifactScope(owner.subject, owner.namespace)
            outcomeJournal.erase(owner.subject, owner.namespace, owner.storageKey)
            outcomeJournal.removeLocalAccountForTesting(owner)
        }
    }
    private suspend fun assertOutcomeOwnerActive(owner: LibrarySyncOwner) {
        withContext(Dispatchers.IO) { outcomeJournal.transaction { db -> assertLocalOwner(db, owner) } }
    }

    suspend fun beginSavedErase(subject: String, namespace: String, ownerKey: String?) = withStorage {
        withContext(Dispatchers.IO) { outcomeJournal.beginSavedErase(subject, namespace, ownerKey) }
    }
    suspend fun eraseSavedStep(subject: String, namespace: String, ownerKey: String?): Boolean = withStorage {
        if (ownerKey == null && withContext(Dispatchers.IO) { outcomeJournal.localDeletion(subject, namespace) } == null) throw LibrarySyncFailure.SessionChanged
        withContext(Dispatchers.IO) { outcomeJournal.eraseSavedStep(subject, namespace, ownerKey) }
    }
    suspend fun savedExportRecords(fence: LibraryOutcomeExportFence, section: Int, after: String?) = withStorage {
        withContext(Dispatchers.IO) { outcomeJournal.savedExportRecords(fence, section, after) }
    }
    private val savedCollectorMutex = Mutex()
    suspend fun beginSavedAssembly(owner: LibrarySyncOwner): LibrarySavedLease = withStorage {
        assertOutcomeOwnerActive(owner); withContext(Dispatchers.IO) { outcomeJournal.beginSaved(owner) }
    }
    suspend fun savedCheckpoint(lease: LibrarySavedLease): LibrarySavedCheckpoint = withStorage {
        withContext(Dispatchers.IO) { outcomeJournal.savedCheckpoint(lease) }
    }
    suspend fun savedRawPage(lease: LibrarySavedLease, start: Long): LibrarySavedRawPage = withStorage {
        withContext(Dispatchers.IO) { outcomeJournal.savedRawPage(lease, start) }
    }
    suspend fun preparedSavedPage(lease: LibrarySavedLease, after: String?): LibrarySavedProjectionPage = withStorage {
        withContext(Dispatchers.IO) { outcomeJournal.savedPreparedPage(lease, after) }
    }
    suspend fun activeSavedGeneration(owner: LibrarySyncOwner): LibrarySavedActiveGeneration? = withStorage {
        withContext(Dispatchers.IO) { outcomeJournal.savedActive(owner) }
    }
    suspend fun activeSavedPage(handle: LibrarySavedActiveGeneration, after: String?): LibrarySavedProjectionPage = withStorage {
        withContext(Dispatchers.IO) { outcomeJournal.savedActivePage(handle, after) }
    }
    suspend fun replaceSavedCandidate(lease: LibrarySavedLease): LibrarySavedLease = withStorage {
        withContext(Dispatchers.IO) { outcomeJournal.replaceSavedCandidate(lease) }
    }
    suspend fun cleanupSavedGenerationStep(owner: LibrarySyncOwner): Boolean = withStorage {
        withContext(Dispatchers.IO) { outcomeJournal.cleanupSavedGenerationStep(owner) }
    }
    suspend fun activateSavedGeneration(lease: LibrarySavedLease, isCurrent: () -> Boolean, fetch: suspend (String) -> SavedFactsReply): LibrarySavedActivation {
        if (!isCurrent() || !savedCollectorMutex.tryLock()) throw LibrarySyncFailure.SessionChanged
        try {
            val captured = savedCheckpoint(lease)
            val position = captured.position ?: throw LibrarySyncFailure.InvalidReceipt
            if (captured.stage != LibrarySavedStage.Prepared) throw LibrarySyncFailure.InvalidReceipt
            activeSavedGeneration(lease.owner)?.let { if (!isCurrent()) throw LibrarySyncFailure.SessionChanged; if (it.lease == lease) return LibrarySavedActivation.Active(it) }
            if (!isCurrent()) throw LibrarySyncFailure.SessionChanged
            val reply = fetch(position.continuation.token)
            if (!isCurrent()) throw LibrarySyncFailure.SessionChanged
            val result = withStorage {
                withContext(Dispatchers.IO) { if (!isCurrent()) throw LibrarySyncFailure.SessionChanged; outcomeJournal.activateSaved(lease, captured, reply) }
            }
            if (!isCurrent()) throw LibrarySyncFailure.SessionChanged
            return result
        } finally { savedCollectorMutex.unlock() }
    }
    suspend fun collectSavedStep(lease: LibrarySavedLease, isCurrent: () -> Boolean, fetch: suspend (String?) -> SavedFactsReply): LibrarySavedCheckpoint {
        if (!isCurrent() || !savedCollectorMutex.tryLock()) throw LibrarySyncFailure.SessionChanged
        try {
            val checkpoint = savedCheckpoint(lease)
            if (checkpoint.stage != LibrarySavedStage.Collecting) {
                val result = withStorage {
                    if (!isCurrent()) throw LibrarySyncFailure.SessionChanged
                    withContext(Dispatchers.IO) { if (!isCurrent()) throw LibrarySyncFailure.SessionChanged; outcomeJournal.advanceSaved(lease) }
                }
                if (!isCurrent()) throw LibrarySyncFailure.SessionChanged
                return result
            }
            val requested = checkpoint.position?.continuation?.token; val reply = fetch(requested)
            if (!isCurrent()) throw LibrarySyncFailure.SessionChanged
            val result = withStorage {
                withContext(Dispatchers.IO) { if (!isCurrent()) throw LibrarySyncFailure.SessionChanged; outcomeJournal.persistSaved(lease, requested, reply) }
            }
            if (!isCurrent()) throw LibrarySyncFailure.SessionChanged
            return result
        } finally { savedCollectorMutex.unlock() }
    }

    suspend fun collectOutcomeStep(committed: SyncCommitted, owner: LibrarySyncOwner, isCurrent: () -> Boolean,
                                   fetch: suspend (SyncOutcomePageRequest) -> SyncOutcomePage): LibraryOutcomeCheckpoint {
        if (!isCurrent()) throw LibrarySyncFailure.SessionChanged
        val binding = LibraryOutcomeBinding(owner, committed)
        val (generation, checkpoint) = withStorage {
            assertOutcomeOwnerActive(owner)
            withContext(Dispatchers.IO) {
                val generation = outcomeJournal.captureGeneration(binding)
                generation to outcomeJournal.open(binding, generation)
            }
        }
        if (!isCurrent()) throw LibrarySyncFailure.SessionChanged
        if (checkpoint.status != LibraryOutcomeStatus.Collecting) return checkpoint
        val requested = binding.pageRequest(checkpoint.next)
        val page = fetch(requested)
        if (!isCurrent()) throw LibrarySyncFailure.SessionChanged
        val result = withStorage {
            assertOutcomeOwnerActive(owner)
            withContext(Dispatchers.IO) { outcomeJournal.persist(binding, generation, requested, page) }
        }
        if (!isCurrent()) throw LibrarySyncFailure.SessionChanged
        return result
    }

    suspend fun outcomeEvidencePage(committed: SyncCommitted, owner: LibrarySyncOwner, start: Long): LibraryOutcomeEvidencePage =
        withStorage { withContext(Dispatchers.IO) { outcomeJournal.evidence(LibraryOutcomeBinding(owner, committed), start) } }


    private val exportDirectory: File = File(context.cacheDir, "LibraryExports")
    private var exportCleanupDone = false
    private fun artifactDirectory(id: String): File {
        val parsed = try { UUID.fromString(id) } catch (_: IllegalArgumentException) { throw LibrarySyncFailure.StoreUnavailable }
        if (parsed.toString() != id.lowercase(java.util.Locale.ROOT)) throw LibrarySyncFailure.StoreUnavailable
        return File(exportDirectory, id)
    }
    private fun removeArtifactDirectory(id: String) {
        val directory = artifactDirectory(id)
        if (directory.exists() && !directory.deleteRecursively()) throw LibrarySyncFailure.StoreUnavailable
    }
    private fun clearArtifactScope(subject: String, namespace: String) {
        while (true) {
            val ids = outcomeJournal.artifactIds(subject, namespace)
            if (ids.isEmpty()) return
            ids.forEach { id -> removeArtifactDirectory(id); outcomeJournal.discardArtifact(id) }
        }
    }
    suspend fun clearAbandonedOutcomeExports() = withStorage {
        if (!exportCleanupDone) withContext(Dispatchers.IO) {
            while (true) {
                val ids = outcomeJournal.artifactIds()
                if (ids.isEmpty()) break
                ids.forEach { id -> removeArtifactDirectory(id); outcomeJournal.discardArtifact(id) }
            }
            if (exportDirectory.exists()) java.nio.file.Files.newDirectoryStream(exportDirectory.toPath()).use { entries ->
                for (entry in entries) {
                    val id = entry.fileName.toString()
                    if (runCatching { UUID.fromString(id).toString() == id.lowercase(java.util.Locale.ROOT) }.getOrDefault(false)) removeArtifactDirectory(id)
                }
            }
            exportCleanupDone = true
        }
    }
    suspend fun prepareOutcomeExport(owner: LibrarySyncOwner, isCurrent: () -> Boolean): LibraryOutcomeExportFence {
        clearAbandonedOutcomeExports()
        while (true) {
            if (!isCurrent()) throw LibrarySyncFailure.SessionChanged
            val ready = withStorage {
                assertOutcomeOwnerActive(owner)
                withContext(Dispatchers.IO) { outcomeJournal.prepareExportStep() }
            }
            if (ready) break
            kotlinx.coroutines.yield()
        }
        if (!isCurrent()) throw LibrarySyncFailure.SessionChanged
        return withStorage {
            assertOutcomeOwnerActive(owner)
            withContext(Dispatchers.IO) { outcomeJournal.captureExportFence(owner) }
        }
    }
    suspend fun validateOutcomeExport(fence: LibraryOutcomeExportFence) = withStorage {
        assertOutcomeOwnerActive(fence.owner)
        withContext(Dispatchers.IO) { outcomeJournal.validateExport(fence) }
    }
    suspend fun outcomeExportEntries(fence: LibraryOutcomeExportFence, after: String?): List<LibraryOutcomeExportEntry> = withStorage {
        assertOutcomeOwnerActive(fence.owner)
        withContext(Dispatchers.IO) { outcomeJournal.exportEntries(fence, after) }
    }
    suspend fun outcomeExportPage(fence: LibraryOutcomeExportFence, entry: LibraryOutcomeExportEntry, start: Long): LibraryOutcomeEvidencePage = withStorage {
        assertOutcomeOwnerActive(fence.owner)
        withContext(Dispatchers.IO) { outcomeJournal.exportPage(fence, entry, start) }
    }
    suspend fun beginOutcomeExportArtifact(fence: LibraryOutcomeExportFence): LibraryExportArtifact = withStorage {
        assertOutcomeOwnerActive(fence.owner)
        withContext(Dispatchers.IO) {
            val id = outcomeJournal.registerArtifact(fence)
            val directory = artifactDirectory(id)
            try {
                if (!directory.mkdirs() && !directory.isDirectory) throw LibrarySyncFailure.StoreUnavailable
                LibraryExportArtifact(id, directory)
            } catch (error: Exception) { removeArtifactDirectory(id); outcomeJournal.discardArtifact(id); throw error }
        }
    }
    suspend fun sealOutcomeExport(fence: LibraryOutcomeExportFence, artifact: LibraryExportArtifact, fileName: String): File = withStorage {
        assertOutcomeOwnerActive(fence.owner)
        withContext(Dispatchers.IO) {
            val directory = artifactDirectory(artifact.id)
            outcomeJournal.sealExport(fence, artifact.id) {
                val destination = File(directory, fileName)
                java.nio.file.Files.move(File(directory, "document.partial").toPath(), destination.toPath(), java.nio.file.StandardCopyOption.ATOMIC_MOVE)
                destination
            }
        }
    }
    suspend fun validateOutcomeExportArtifact(id: String, owner: LibrarySyncOwner) = withStorage {
        assertOutcomeOwnerActive(owner)
        withContext(Dispatchers.IO) { outcomeJournal.validateArtifact(id, owner) }
    }
    suspend fun discardOutcomeExportArtifact(id: String) = withStorage {
        withContext(Dispatchers.IO) { removeArtifactDirectory(id); outcomeJournal.discardArtifact(id) }
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
        val savedItems = byHadith.values.map { item -> item.copy(folderLocalId = membershipByHadith[item.hadithId]?.folderLocalId, folderUpdatedAt = membershipByHadith[item.hadithId]?.updatedAt) }.sortedBy { it.hadithId }
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
