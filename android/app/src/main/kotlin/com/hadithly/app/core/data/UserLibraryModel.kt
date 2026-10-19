package com.hadithly.app.core.data

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable

/**
 * A hadith reference shared by the Library continue-reading card and the
 * reader deep-link. Mirrors the iOS HadithRef.
 */
@Serializable
data class HadithRef(
    val hadithId: String,
    val collectionSlug: String,
    val collectionName: String,
    val volumeId: String?,
    val hadithNumber: String?,
    val arabicText: String,
    val englishText: String?,
    val referenceDisplay: String,
)

/** One row of the Saved tab. */
data class SavedEntry(
    val rowId: String,
    val createdAt: Double,
    val updatedAt: Double? = null,
    val noteContent: String? = null,
    val hadith: HadithRef?,
    val noteCreatedAt: Double? = null,
    val noteUpdatedAt: Double? = null,
) {
    val sortDate: Double get() = updatedAt ?: createdAt
}

data class SavedItemEntry(
    val hadithId: String,
    val createdAt: Double,
    val updatedAt: Double,
    val bookmarkCreatedAt: Double? = null,
    val favoriteCreatedAt: Double? = null,
    val noteContent: String? = null,
    val folderId: String? = null,
    val hadith: HadithRef?,
    val noteCreatedAt: Double? = null,
    val noteUpdatedAt: Double? = null,
) {
    val sortDate: Double get() = updatedAt
}

data class SavedFolder(val id: String, val name: String, val createdAt: Double)

/** Private per-collection reading position (never shared, never ranked). */
data class ProgressEntry(
    val collectionSlug: String,
    val hadith: HadithRef?,
    val position: ReadingPosition? = null,
    val updatedAt: Double,
)

interface LibraryReadTransport {
    fun savedSnapshot(): kotlinx.coroutines.flow.Flow<SyncSavedSnapshot>
    fun positionsSnapshot(): kotlinx.coroutines.flow.Flow<SyncPositionsSnapshot>
}

private sealed interface LibraryAccess {
    data object Guest : LibraryAccess
    class Account(val reads: LibraryReadTransport, val sync: LibrarySync, val currentSession: () -> LibrarySyncSession?) : LibraryAccess
}

/**
 * Single facade over the user's personal data — bookmarks, favorites, notes,
 * reading progress — for both auth states. Signed in, everything is realtime
 * through Convex subscriptions; guests read and write the local guest store,
 * which merges into Convex on sign-in.
 */
class UserLibraryModel private constructor(
    private val guestData: GuestDataStore,
    scope: CoroutineScope,
    private val access: LibraryAccess,
) {
    constructor(guestData: GuestDataStore, scope: CoroutineScope) : this(guestData, scope, LibraryAccess.Guest)
    constructor(reads: LibraryReadTransport, guestData: GuestDataStore, scope: CoroutineScope, sync: LibrarySync, currentSession: () -> LibrarySyncSession?) : this(guestData, scope, LibraryAccess.Account(reads, sync, currentSession))
    private val scope = CoroutineScope(scope.coroutineContext + Dispatchers.Main.immediate)
    private val account: LibraryAccess.Account? get() = when (val value = access) { LibraryAccess.Guest -> null; is LibraryAccess.Account -> value }
    private fun currentSession() = account?.currentSession?.invoke()
    val actionScope: String get() = epoch
    fun isActionCurrent(captured: String?) = captured == epoch && currentSession() == scopedSession && (scopedOwner == account?.sync?.owner?.value || scopedOwner == null && currentSession() == null)
    private fun isSignedIn() = currentSession() != null
    private var scopedOwner: LibrarySyncOwner? = null
    private var scopedSession: LibrarySyncSession? = null
    private var epoch = java.util.UUID.randomUUID().toString()
    private var lastIntentAt = 0.0
    private val writeMutex = kotlinx.coroutines.sync.Mutex()
    private sealed interface UndoScope {
        data class Guest(val epoch: String) : UndoScope
        data class Account(val context: LibraryWriteContext) : UndoScope
    }
    private data class UndoAction(val deletionId: String, val scope: UndoScope, val deadline: Long)
    private val undoActions = mutableMapOf<String, UndoAction>()
    private val _lastWriteFailed = MutableStateFlow(false)
    val lastWriteFailed: StateFlow<Boolean> = _lastWriteFailed

    enum class LoadState { Loading, Ready, Failed }
    private val _loadState = MutableStateFlow(LoadState.Loading)
    val loadState: StateFlow<LoadState> = _loadState

    private val _savedItems = MutableStateFlow<List<SavedItemEntry>>(emptyList())
    val savedItems: StateFlow<List<SavedItemEntry>> = _savedItems

    private val _folders = MutableStateFlow<List<SavedFolder>>(emptyList())
    val folders: StateFlow<List<SavedFolder>> = _folders

    val undo = SavedUndoController(scope) { android.os.SystemClock.elapsedRealtime() }

    private val _bookmarks = MutableStateFlow<List<SavedEntry>>(emptyList())
    val bookmarks: StateFlow<List<SavedEntry>> = _bookmarks

    private val _favorites = MutableStateFlow<List<SavedEntry>>(emptyList())
    val favorites: StateFlow<List<SavedEntry>> = _favorites

    private val _notes = MutableStateFlow<List<SavedEntry>>(emptyList())
    val notes: StateFlow<List<SavedEntry>> = _notes

    private val _progress = MutableStateFlow<List<ProgressEntry>>(emptyList())
    val progress: StateFlow<List<ProgressEntry>> = _progress

    private var subscriptions: MutableList<Job> = mutableListOf()
    private var subscriptionsActive = false
    private var retriesLeft = 5

    fun refresh() {
        val session = currentSession()
        val owner = account?.sync?.owner?.value?.takeIf { it.subject == session?.subject }
        if (session != scopedSession || owner != scopedOwner) {
            unsubscribe(); scopedSession = session; scopedOwner = owner; retriesLeft = 5
        }
        if (session == null) { launchGuestOperation { loadGuestData() }; return }
        if (owner == null) { _loadState.value = LoadState.Loading; return }
        scope.launch { reloadAccount(owner) }
        if (subscriptionsActive) return
        subscriptionsActive = true
        subscribeAll(owner, session, epoch)
    }

    fun partitionChanged(owner: LibrarySyncOwner) { scope.launch { reloadAccount(owner) } }

    private suspend fun reloadAccount(owner: LibrarySyncOwner) {
        val capturedEpoch = epoch
        if (scopedOwner != owner || currentSession() != scopedSession) return
        try {
            val state = guestData.syncPartition(owner) ?: return
            if (epoch != capturedEpoch || scopedOwner != owner || currentSession() != scopedSession) return
            val value = LibraryProjection(state)
            _savedItems.value = value.items; _folders.value = value.folders; _progress.value = value.progress
            _bookmarks.value = value.items.mapNotNull { item -> item.bookmarkCreatedAt?.let { SavedEntry(item.hadithId, it, hadith = item.hadith) } }
            _favorites.value = value.items.mapNotNull { item -> item.favoriteCreatedAt?.let { SavedEntry(item.hadithId, it, hadith = item.hadith) } }
            _notes.value = value.items.mapNotNull { item -> item.noteContent?.let { SavedEntry(item.hadithId, item.noteCreatedAt ?: item.createdAt, item.noteUpdatedAt ?: item.updatedAt, it, item.hadith) } }
            _loadState.value = if (state.savedSnapshot != null || value.items.isNotEmpty()) LoadState.Ready else LoadState.Loading
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { if (epoch == capturedEpoch) _loadState.value = LoadState.Failed }
    }

    private fun folderReference(id: String?): SyncFolderReference = when {
        id == null -> SyncFolderReference.None
        id.startsWith("local:") -> SyncFolderReference.Local(id.removePrefix("local:"))
        else -> SyncFolderReference.Server(id)
    }

    private fun ownedWrite(ref: HadithRef? = null, captured: LibraryWriteContext? = null, command: (Double) -> SyncCommand, queued: (LibraryLocalChange, LibraryWriteContext) -> Unit = { _, _ -> }): Deferred<Boolean> {
        val active = account ?: return CompletableDeferred(false)
        val context = try { captured ?: active.sync.captureWriteContext() } catch (_: Exception) { _lastWriteFailed.value = true; return CompletableDeferred(false) }
        lastIntentAt = maxOf(nowMillis(), lastIntentAt + 1)
        val at = lastIntentAt
        return scope.async {
            try {
                writeMutex.withLock {
                    if (currentSession() != context.session) throw LibrarySyncFailure.SessionChanged
                    val change = LibraryLocalChange(command(at), at, LibraryLocalSource.Account(ref))
                    active.sync.enqueue(change, context)
                    if (currentSession() != context.session) return@withLock false
                    active.sync.owner.value?.let { reloadAccount(it) }
                    queued(change, context)
                    _lastWriteFailed.value = false
                    true
                }
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { if (currentSession() == context.session) { _lastWriteFailed.value = true; _loadState.value = LoadState.Failed }; false }
        }
    }

    private fun recordGuestUndo(key: String) {
        undoActions[key] = UndoAction("guest", UndoScope.Guest(epoch), android.os.SystemClock.elapsedRealtime() + UNDO_NOTICE_MILLIS)
    }
    private fun recordAccountUndo(key: String, change: LibraryLocalChange, context: LibraryWriteContext) {
        undoActions[key] = UndoAction(change.operation.id, UndoScope.Account(context), android.os.SystemClock.elapsedRealtime() + UNDO_NOTICE_MILLIS)
    }
    private fun restoreFacet(ref: HadithRef, key: String, value: SyncCommandFacetRestoreValue, guestRestore: suspend () -> Unit) {
        val action = undoActions.remove(key) ?: return
        if (action.deadline <= android.os.SystemClock.elapsedRealtime()) return
        when (val target = action.scope) {
            is UndoScope.Account -> ownedWrite(ref, target.context, { SyncCommand.FacetRestore(ref.hadithId, action.deletionId, value) })
            is UndoScope.Guest -> if (!isSignedIn() && target.epoch == epoch) launchGuestOperation { guestRestore(); loadGuestData() }
        }
    }

    val continueReading: ProgressEntry?
        get() = progress.value.filter { it.hadith != null }.maxByOrNull { it.updatedAt }

    fun progressFor(collectionSlug: String): ProgressEntry? =
        progress.value.firstOrNull { it.collectionSlug == collectionSlug }

    fun isBookmarked(hadithId: String): Boolean =
        bookmarks.value.any { it.hadith?.hadithId == hadithId }

    fun isFavorite(hadithId: String): Boolean =
        favorites.value.any { it.hadith?.hadithId == hadithId }

    fun toggleBookmark(ref: HadithRef): Deferred<Boolean> {
        val key = "bookmark:${ref.hadithId}"
        return if (isSignedIn()) ownedWrite(ref, command = { at -> if (isBookmarked(ref.hadithId)) SyncCommand.BookmarkRemove(ref.hadithId) else SyncCommand.BookmarkAdd(ref.hadithId, at) }, queued = { change, context ->
            if (change.operation.command is SyncCommand.BookmarkRemove) recordAccountUndo(key, change, context) else undoActions.remove(key)
        }) else launchGuestOperation {
            if (guestData.isBookmarked(ref.hadithId)) { guestData.removeBookmark(ref.hadithId); recordGuestUndo(key) }
            else { guestData.addBookmark(GuestBookmarkDraft(ref.hadithId, nowMillis(), ref.collectionName, ref.referenceDisplay, ref.volumeId, ref.hadithNumber, ref.collectionSlug, ref.arabicText, ref.englishText)); undoActions.remove(key) }
            loadGuestData()
        }
    }

    fun toggleFavorite(ref: HadithRef): Deferred<Boolean> {
        val key = "favorite:${ref.hadithId}"
        return if (isSignedIn()) ownedWrite(ref, command = { at -> if (isFavorite(ref.hadithId)) SyncCommand.FavoriteRemove(ref.hadithId) else SyncCommand.FavoriteAdd(ref.hadithId, at) }, queued = { change, context ->
            if (change.operation.command is SyncCommand.FavoriteRemove) recordAccountUndo(key, change, context) else undoActions.remove(key)
        }) else launchGuestOperation {
            if (guestData.isFavorite(ref.hadithId)) { guestData.removeFavorite(ref.hadithId); recordGuestUndo(key) }
            else { guestData.addFavorite(GuestFavoriteDraft(ref.hadithId, nowMillis(), ref.collectionName, ref.referenceDisplay, ref.volumeId, ref.hadithNumber, ref.collectionSlug, ref.arabicText, ref.englishText)); undoActions.remove(key) }
            loadGuestData()
        }
    }

    fun removeBookmark(ref: HadithRef, capturedScope: String): Deferred<Boolean> {
        if (!isActionCurrent(capturedScope) || !isBookmarked(ref.hadithId)) return CompletableDeferred(false)
        val key = "bookmark:${ref.hadithId}"
        return if (isSignedIn()) ownedWrite(ref, command = { SyncCommand.BookmarkRemove(ref.hadithId) }, queued = { change, context -> recordAccountUndo(key, change, context) })
        else launchGuestOperation { guestData.removeBookmark(ref.hadithId); recordGuestUndo(key); loadGuestData() }
    }
    fun removeFavorite(ref: HadithRef, capturedScope: String): Deferred<Boolean> {
        if (!isActionCurrent(capturedScope) || !isFavorite(ref.hadithId)) return CompletableDeferred(false)
        val key = "favorite:${ref.hadithId}"
        return if (isSignedIn()) ownedWrite(ref, command = { SyncCommand.FavoriteRemove(ref.hadithId) }, queued = { change, context -> recordAccountUndo(key, change, context) })
        else launchGuestOperation { guestData.removeFavorite(ref.hadithId); recordGuestUndo(key); loadGuestData() }
    }

    fun saveNote(ref: HadithRef, content: String): Deferred<Boolean> {
        return if (isSignedIn()) ownedWrite(ref, command = { at -> SyncCommand.NotePut(ref.hadithId, content, _notes.value.firstOrNull { it.hadith?.hadithId == ref.hadithId }?.createdAt ?: at, at) })
        else launchGuestOperation { guestData.saveNote(ref.hadithId, content, ref.collectionName, ref.referenceDisplay, ref.volumeId, ref.hadithNumber, ref.collectionSlug, ref.arabicText, ref.englishText); loadGuestData() }
    }
    fun deleteNote(ref: HadithRef, capturedScope: String): Deferred<Boolean> {
        if (!isActionCurrent(capturedScope) || _notes.value.none { it.hadith?.hadithId == ref.hadithId }) return CompletableDeferred(false)
        val key = "note:${ref.hadithId}"
        return if (isSignedIn()) ownedWrite(ref, command = { SyncCommand.NoteRemove(ref.hadithId) }, queued = { change, context -> recordAccountUndo(key, change, context) })
        else launchGuestOperation { guestData.deleteNote(ref.hadithId); recordGuestUndo(key); loadGuestData() }
    }
    fun createFolder(name: String, capturedScope: String) {
        if (!isActionCurrent(capturedScope)) return
        if (!GuestMergePlanner.isValidFolderName(name)) { _lastWriteFailed.value = true; return }
        if (isSignedIn()) { val key = java.util.UUID.randomUUID().toString(); ownedWrite(command = { SyncCommand.FolderCreate(key, name.trim(), SyncCommandFolderCreatePurpose.CREATE) }) }
        else launchGuestOperation { guestData.createSavedFolder(name.trim()); loadGuestData() }
    }
    fun assignFolder(hadithId: String, folderId: String?, capturedScope: String) {
        if (!isActionCurrent(capturedScope)) return
        if (isSignedIn()) ownedWrite(_savedItems.value.firstOrNull { it.hadithId == hadithId }?.hadith, command = { SyncCommand.MembershipPut(hadithId, folderReference(folderId)) })
        else launchGuestOperation { guestData.assignSavedFolder(hadithId, folderId); loadGuestData() }
    }
    fun deleteFolder(folder: SavedFolder, message: String, capturedScope: String) {
        if (!isActionCurrent(capturedScope)) return
        if (isSignedIn()) {
            var ids = emptyList<String>()
            ownedWrite(command = { ids = _savedItems.value.filter { it.folderId == folder.id }.map { it.hadithId }; SyncCommand.FolderDelete(folderReference(folder.id)) }, queued = { change, context ->
                undo.show(message) { ownedWrite(captured = context, command = { SyncCommand.FolderRestore(change.operation.id, folder.name, ids) }) }
            })
        } else launchGuestOperation {
            val deletion = guestData.deleteSavedFolder(folder.id)
            val capturedEpoch = epoch
            loadGuestData()
            if (deletion != null) undo.show(message) {
                if (!isSignedIn() && capturedEpoch == epoch) launchGuestOperation { guestData.restoreSavedFolder(deletion); loadGuestData() }
            }
        }
    }
    fun restoreBookmark(ref: HadithRef, createdAt: Double) = restoreFacet(ref, "bookmark:${ref.hadithId}", SyncCommandFacetRestoreValue.Bookmark(createdAt)) {
        guestData.addBookmark(GuestBookmarkDraft(ref.hadithId, createdAt, ref.collectionName, ref.referenceDisplay, ref.volumeId, ref.hadithNumber, ref.collectionSlug, ref.arabicText, ref.englishText))
    }
    fun restoreFavorite(ref: HadithRef, createdAt: Double) = restoreFacet(ref, "favorite:${ref.hadithId}", SyncCommandFacetRestoreValue.Favorite(createdAt)) {
        guestData.addFavorite(GuestFavoriteDraft(ref.hadithId, createdAt, ref.collectionName, ref.referenceDisplay, ref.volumeId, ref.hadithNumber, ref.collectionSlug, ref.arabicText, ref.englishText))
    }
    fun restoreNote(ref: HadithRef, content: String, createdAt: Double, updatedAt: Double) = restoreFacet(ref, "note:${ref.hadithId}", SyncCommandFacetRestoreValue.Note(content, createdAt, updatedAt)) {
        guestData.restoreNote(GuestNoteDraft(ref.hadithId, content, createdAt, updatedAt, ref.collectionName, ref.referenceDisplay, ref.volumeId, ref.hadithNumber, ref.collectionSlug, ref.arabicText, ref.englishText))
    }
    fun noteContentFor(hadithId: String): String? = _notes.value.firstOrNull { it.hadith?.hadithId == hadithId }?.noteContent
    fun saveProgress(position: ReadingPosition, ref: HadithRef) {
        if (isSignedIn()) ownedWrite(ref, command = { SyncCommand.PositionPut(position) })
        else launchGuestOperation { guestData.saveProgress(GuestReadingProgressDraft(ref.collectionSlug, ref.collectionName, ref.hadithId, ref.volumeId, ref.hadithNumber, ref.referenceDisplay, position.updatedAt, ref.arabicText, ref.englishText, position)); loadGuestData() }
    }

    // Owned subscriptions
    private fun matches(owner: LibrarySyncOwner, session: LibrarySyncSession, capturedEpoch: String) = epoch == capturedEpoch && scopedOwner == owner && scopedSession == session && currentSession() == session && account?.sync?.owner?.value == owner

    private fun subscribeAll(owner: LibrarySyncOwner, session: LibrarySyncSession, capturedEpoch: String) {
        val reads = account?.reads ?: return
        unsubscribeJobs()
        subscriptions.add(scope.launch {
            try { reads.savedSnapshot().collect { value ->
                if (!matches(owner, session, capturedEpoch) || value.ownerKey != owner.key) return@collect
                guestData.cacheSavedSnapshot(value, owner)
                if (matches(owner, session, capturedEpoch)) reloadAccount(owner)
            } } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { subscriptionFailed(owner, session, capturedEpoch) }
        })
        subscriptions.add(scope.launch {
            try { reads.positionsSnapshot().collect { value ->
                if (!matches(owner, session, capturedEpoch) || value.ownerKey != owner.key) return@collect
                guestData.cachePositionsSnapshot(value, owner)
                if (matches(owner, session, capturedEpoch)) reloadAccount(owner)
            } } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { subscriptionFailed(owner, session, capturedEpoch) }
        })
    }
    private fun subscriptionFailed(owner: LibrarySyncOwner, session: LibrarySyncSession, capturedEpoch: String) {
        if (!matches(owner, session, capturedEpoch)) return
        if (_savedItems.value.isEmpty()) _loadState.value = LoadState.Failed
        subscriptionsActive = false
        if (retriesLeft-- <= 0) return
        scope.launch { delay(1_500); if (matches(owner, session, capturedEpoch)) refresh() }
    }
    private fun unsubscribeJobs() { subscriptions.forEach { it.cancel() }; subscriptions.clear() }
    private fun unsubscribe() {
        epoch = java.util.UUID.randomUUID().toString()
        unsubscribeJobs(); subscriptionsActive = false
        _savedItems.value = emptyList(); _folders.value = emptyList(); _bookmarks.value = emptyList(); _favorites.value = emptyList(); _notes.value = emptyList(); _progress.value = emptyList()
        undoActions.clear(); undo.clear()
    }

    // Guest data

    private fun launchGuestOperation(block: suspend () -> Unit): Deferred<Boolean> {
        val capturedEpoch = epoch
        return scope.async {
            if (isSignedIn() || epoch != capturedEpoch) return@async false
            try { block(); true }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { _lastWriteFailed.value = true; _loadState.value = LoadState.Failed; false }
        }
    }

    private suspend fun loadGuestData() {
        if (isSignedIn()) return
        val capturedEpoch = epoch
        val snapshot = guestData.snapshots()
        if (isSignedIn() || epoch != capturedEpoch) return
        _bookmarks.value = snapshot.bookmarks.map {
            SavedEntry(
                rowId = "guest-bookmark-${it.hadithId}",
                createdAt = it.createdAt,
                hadith = it.toRef(),
            )
        }
        _favorites.value = snapshot.favorites.map {
            SavedEntry(
                rowId = "guest-favorite-${it.hadithId}",
                createdAt = it.createdAt,
                hadith = it.toRef(),
            )
        }
        _notes.value = snapshot.notes.map {
            SavedEntry(
                rowId = "guest-note-${it.hadithId}",
                createdAt = it.createdAt,
                updatedAt = it.updatedAt,
                noteContent = it.content,
                hadith = it.toRef(),
            )
        }
        _progress.value = snapshot.progress.map {
            ProgressEntry(
                collectionSlug = it.collectionSlug,
                hadith = it.toRef(),
                position = it.readingPosition,
                updatedAt = it.updatedAt,
            )
        }
        _folders.value = snapshot.savedFolders.map { SavedFolder(it.localId, it.name, it.createdAt) }
        rebuildGuestSavedItems(snapshot.savedMemberships)
        _loadState.value = LoadState.Ready
    }

    private fun rebuildGuestSavedItems(memberships: List<GuestSavedMembership> = emptyList()) {
        val folderByHadith = memberships.associate { it.hadithId to it.folderLocalId }
        val entries = linkedMapOf<String, SavedItemEntry>()
        _bookmarks.value.forEach { entry -> entry.hadith?.let { ref -> entries[ref.hadithId] = SavedItemEntry(ref.hadithId, entry.createdAt, entry.sortDate, bookmarkCreatedAt = entry.createdAt, folderId = folderByHadith[ref.hadithId], hadith = ref) } }
        _favorites.value.forEach { entry -> entry.hadith?.let { ref ->
            val prior = entries[ref.hadithId]
            entries[ref.hadithId] = SavedItemEntry(ref.hadithId, minOf(prior?.createdAt ?: entry.createdAt, entry.createdAt), maxOf(prior?.updatedAt ?: entry.sortDate, entry.sortDate), prior?.bookmarkCreatedAt, entry.createdAt, prior?.noteContent, folderByHadith[ref.hadithId], ref)
        } }
        _notes.value.forEach { entry -> entry.hadith?.let { ref ->
            val prior = entries[ref.hadithId]
            entries[ref.hadithId] = SavedItemEntry(ref.hadithId, minOf(prior?.createdAt ?: entry.createdAt, entry.createdAt), maxOf(prior?.updatedAt ?: entry.sortDate, entry.sortDate), prior?.bookmarkCreatedAt, prior?.favoriteCreatedAt, entry.noteContent, folderByHadith[ref.hadithId], ref)
        } }
        _savedItems.value = entries.values.sortedByDescending { it.sortDate }
    }

    private fun GuestBookmarkDraft.toRef() = HadithRef(
        hadithId = hadithId,
        collectionSlug = collectionSlug ?: Collections.slugForName(collectionName),
        collectionName = collectionName ?: "Saved hadith",
        volumeId = volumeId,
        hadithNumber = hadithNumber,
        arabicText = arabicText,
        englishText = englishText,
        referenceDisplay = referenceDisplay ?: "",
    )

    private fun GuestFavoriteDraft.toRef() = HadithRef(
        hadithId = hadithId,
        collectionSlug = collectionSlug ?: Collections.slugForName(collectionName),
        collectionName = collectionName ?: "Saved hadith",
        volumeId = volumeId,
        hadithNumber = hadithNumber,
        arabicText = arabicText,
        englishText = englishText,
        referenceDisplay = referenceDisplay ?: "",
    )

    private fun GuestNoteDraft.toRef() = HadithRef(
        hadithId = hadithId,
        collectionSlug = collectionSlug ?: Collections.slugForName(collectionName),
        collectionName = collectionName ?: "Saved hadith",
        volumeId = volumeId,
        hadithNumber = hadithNumber,
        arabicText = arabicText,
        englishText = englishText,
        referenceDisplay = referenceDisplay ?: "",
    )

    private fun GuestReadingProgressDraft.toRef() = HadithRef(
        hadithId = hadithId,
        collectionSlug = collectionSlug,
        collectionName = collectionName,
        volumeId = volumeId,
        hadithNumber = hadithNumber,
        arabicText = arabicText,
        englishText = englishText,
        referenceDisplay = referenceDisplay ?: "",
    )

    private fun nowMillis(): Double = System.currentTimeMillis().toDouble()
}
