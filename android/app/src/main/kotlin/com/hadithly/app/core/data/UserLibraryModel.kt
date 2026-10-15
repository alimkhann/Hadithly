package com.hadithly.app.core.data

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable

/**
 * A hadith reference shared by the Library continue-reading card and the
 * reader deep-link. Mirrors the iOS HadithRef.
 */
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

@Serializable
private data class HadithSummary(
    val _id: String,
    val providerHadithId: String,
    val collectionSlug: String,
    val collectionName: String,
    val volumeId: String? = null,
    val arabicText: String,
    val englishText: String? = null,
    val referenceDisplay: String,
)

@Serializable
private data class DetailedRow(
    val _id: String,
    val createdAt: Double,
    val hadith: HadithSummary? = null,
)

@Serializable
private data class DetailedNoteRow(
    val _id: String,
    val content: String,
    val createdAt: Double,
    val updatedAt: Double,
    val hadith: HadithSummary? = null,
)

@Serializable
private data class ProgressRow(
    val collectionSlug: String,
    val hadithId: String,
    val updatedAt: Double,
    val position: ReadingPosition? = null,
    val hadith: HadithSummary? = null,
)

@Serializable
private data class SavedFolderRow(val _id: String, val name: String, val createdAt: Double)

@Serializable
private data class SavedItemRow(
    val hadithId: String,
    val createdAt: Double,
    val updatedAt: Double,
    val bookmarkCreatedAt: Double? = null,
    val favoriteCreatedAt: Double? = null,
    val noteContent: String? = null,
    val folderId: String? = null,
    val hadith: HadithSummary? = null,
)

@Serializable
private data class SavedSnapshotRow(val folders: List<SavedFolderRow>, val items: List<SavedItemRow>)

/**
 * Single facade over the user's personal data — bookmarks, favorites, notes,
 * reading progress — for both auth states. Signed in, everything is realtime
 * through Convex subscriptions; guests read and write the local guest store,
 * which merges into Convex on sign-in.
 */
class UserLibraryModel(
    private val repository: ConvexRepository,
    private val guestData: GuestDataStore,
    private val scope: CoroutineScope,
    private val isSignedIn: () -> Boolean,
) {

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

    /**
     * Idempotent. Signed in → (re)subscribe to the four Convex queries.
     * Guest → pull local drafts. Call on every auth-state transition — a
     * subscription opened before the Convex session activated fails with
     * Unauthenticated and must be re-opened.
     */
    fun refresh() {
        if (isSignedIn()) {
            if (subscriptionsActive) return
            subscriptionsActive = true
            if (_loadState.value != LoadState.Ready) _loadState.value = LoadState.Loading
            retriesLeft = 5
            subscribeAll()
        } else {
            unsubscribe()
            scope.launch { loadGuestData() }
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

    fun toggleBookmark(ref: HadithRef) {
        if (isSignedIn()) {
            scope.launch { runCatching { repository.toggleBookmark(ref.hadithId) } }
        } else {
            scope.launch {
                if (guestData.isBookmarked(ref.hadithId)) {
                    guestData.removeBookmark(ref.hadithId)
                } else {
                    guestData.addBookmark(
                        GuestBookmarkDraft(
                            hadithId = ref.hadithId,
                            createdAt = nowMillis(),
                            collectionName = ref.collectionName,
                            referenceDisplay = ref.referenceDisplay,
                            volumeId = ref.volumeId,
                            hadithNumber = ref.hadithNumber,
                            collectionSlug = ref.collectionSlug,
                            arabicText = ref.arabicText,
                            englishText = ref.englishText,
                        )
                    )
                }
                loadGuestData()
            }
        }
    }

    fun toggleFavorite(ref: HadithRef) {
        if (isSignedIn()) {
            scope.launch { runCatching { repository.toggleFavorite(ref.hadithId) } }
        } else {
            scope.launch {
                if (guestData.isFavorite(ref.hadithId)) {
                    guestData.removeFavorite(ref.hadithId)
                } else {
                    guestData.addFavorite(
                        GuestFavoriteDraft(
                            hadithId = ref.hadithId,
                            createdAt = nowMillis(),
                            collectionName = ref.collectionName,
                            referenceDisplay = ref.referenceDisplay,
                            volumeId = ref.volumeId,
                            hadithNumber = ref.hadithNumber,
                            collectionSlug = ref.collectionSlug,
                            arabicText = ref.arabicText,
                            englishText = ref.englishText,
                        )
                    )
                }
                loadGuestData()
            }
        }
    }

    fun saveNote(ref: HadithRef, content: String) {
        if (isSignedIn()) {
            scope.launch { runCatching { repository.upsertNote(ref.hadithId, content) } }
        } else {
            scope.launch {
                guestData.saveNote(
                    hadithId = ref.hadithId,
                    content = content,
                    collectionName = ref.collectionName,
                    referenceDisplay = ref.referenceDisplay,
                    volumeId = ref.volumeId,
                    hadithNumber = ref.hadithNumber,
                    collectionSlug = ref.collectionSlug,
                    arabicText = ref.arabicText,
                    englishText = ref.englishText,
                )
                loadGuestData()
            }
        }
    }

    fun deleteNote(ref: HadithRef) {
        if (isSignedIn()) {
            scope.launch { runCatching { repository.deleteNote(ref.hadithId) } }
        } else {
            scope.launch {
                guestData.deleteNote(ref.hadithId)
                loadGuestData()
            }
        }
    }

    fun createFolder(name: String) {
        if (isSignedIn()) {
            scope.launch { runCatching { repository.createSavedFolder(name) } }
        } else {
            scope.launch {
                if (GuestMergePlanner.isValidFolderName(name)) guestData.createSavedFolder(name.trim())
                loadGuestData()
            }
        }
    }

    fun assignFolder(hadithId: String, folderId: String?) {
        if (isSignedIn()) {
            scope.launch { runCatching { repository.assignSavedFolder(hadithId, folderId) } }
        } else {
            scope.launch { guestData.assignSavedFolder(hadithId, folderId); loadGuestData() }
        }
    }

    fun deleteFolder(folder: SavedFolder, message: String) {
        if (isSignedIn()) {
            scope.launch {
                runCatching { repository.deleteSavedFolder(folder.id) }.onSuccess { deletion ->
                    undo.show(message) {
                        scope.launch { runCatching { repository.restoreSavedFolder(deletion.name, deletion.hadithIds, deletion.deletedAt) } }
                    }
                }
            }
        } else {
            scope.launch {
                val deletion = guestData.deleteSavedFolder(folder.id)
                loadGuestData()
                if (deletion != null) undo.show(message) {
                    scope.launch { guestData.restoreSavedFolder(deletion); loadGuestData() }
                }
            }
        }
    }

    fun restoreBookmark(ref: HadithRef, createdAt: Double) {
        if (isSignedIn()) scope.launch { runCatching { repository.restoreSavedFacet(ref.hadithId, "bookmark", createdAt) } }
        else scope.launch { guestData.addBookmark(GuestBookmarkDraft(ref.hadithId, createdAt, ref.collectionName, ref.referenceDisplay, ref.volumeId, ref.hadithNumber, ref.collectionSlug, ref.arabicText, ref.englishText)); loadGuestData() }
    }

    fun restoreFavorite(ref: HadithRef, createdAt: Double) {
        if (isSignedIn()) scope.launch { runCatching { repository.restoreSavedFacet(ref.hadithId, "favorite", createdAt) } }
        else scope.launch { guestData.addFavorite(GuestFavoriteDraft(ref.hadithId, createdAt, ref.collectionName, ref.referenceDisplay, ref.volumeId, ref.hadithNumber, ref.collectionSlug, ref.arabicText, ref.englishText)); loadGuestData() }
    }

    fun restoreNote(ref: HadithRef, content: String, createdAt: Double, updatedAt: Double) {
        if (isSignedIn()) scope.launch { runCatching { repository.restoreSavedFacet(ref.hadithId, "note", createdAt, content, updatedAt) } }
        else scope.launch { guestData.restoreNote(GuestNoteDraft(ref.hadithId, content, createdAt, updatedAt, ref.collectionName, ref.referenceDisplay, ref.volumeId, ref.hadithNumber, ref.collectionSlug, ref.arabicText, ref.englishText)); loadGuestData() }
    }

    fun noteContentFor(hadithId: String): String? =
        notes.value.firstOrNull { it.hadith?.hadithId == hadithId }?.noteContent

    /** Saves the reader position; per-collection upsert keeps repeats cheap. */
    fun saveProgress(position: ReadingPosition, ref: HadithRef) {
        if (isSignedIn()) {
            scope.launch {
                runCatching { repository.saveReadingProgress(position) }
            }
        } else {
            scope.launch {
                guestData.saveProgress(
                    GuestReadingProgressDraft(
                        collectionSlug = ref.collectionSlug,
                        collectionName = ref.collectionName,
                        hadithId = ref.hadithId,
                        volumeId = ref.volumeId,
                        hadithNumber = ref.hadithNumber,
                        referenceDisplay = ref.referenceDisplay,
                        updatedAt = nowMillis(),
                        arabicText = ref.arabicText,
                        englishText = ref.englishText,
                        position = position,
                    )
                )
                loadGuestData()
            }
        }
    }

    // Convex subscriptions (signed in)

    private fun subscribeAll() {
        unsubscribeJobs()
        subscriptions.add(
            scope.launch(Dispatchers.IO) {
                try {
                    repository.subscribe<SavedSnapshotRow>("library:listSavedSnapshot")
                        .collect { snapshot -> apply(snapshot) }
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (_: Exception) {
                    scope.launch { subscriptionFailed(savedSnapshot = true) }
                }
            }
        )
        subscriptions.add(
            scope.launch(Dispatchers.IO) {
                try {
                    repository.subscribe<List<ProgressRow>>("library:listReadingProgressDetailed")
                        .collect { rows ->
                            _progress.value = rows.map {
                                ProgressEntry(
                                    collectionSlug = it.collectionSlug,
                                    hadith = it.hadith?.let { h -> h.toRef() },
                                    position = it.position,
                                    updatedAt = it.updatedAt,
                                )
                            }
                        }
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (_: Exception) {
                    scope.launch { subscriptionFailed(savedSnapshot = false) }
                }
            }
        )
    }

    /**
     * A subscription that raced the Convex session errors without data.
     * Re-open everything, bounded.
     */
    private fun subscriptionFailed(savedSnapshot: Boolean) {
        if (!subscriptionsActive) return
        if (savedSnapshot && _savedItems.value.isEmpty()) _loadState.value = LoadState.Failed
        subscriptionsActive = false
        unsubscribeJobs()
        if (retriesLeft > 0 && isSignedIn()) {
            retriesLeft -= 1
            scope.launch {
                delay(1500)
                if (!subscriptionsActive && isSignedIn()) {
                    subscriptionsActive = true
                    subscribeAll()
                }
            }
        }
    }

    private fun unsubscribeJobs() {
        subscriptions.forEach { it.cancel() }
        subscriptions = mutableListOf()
    }

    private fun unsubscribe() {
        unsubscribeJobs()
        subscriptionsActive = false
        _savedItems.value = emptyList()
        _folders.value = emptyList()
        _bookmarks.value = emptyList()
        _favorites.value = emptyList()
        _notes.value = emptyList()
        _progress.value = emptyList()
    }

    // Guest data

    private suspend fun loadGuestData() {
        if (isSignedIn()) return
        val snapshot = guestData.snapshots()
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

    private fun apply(snapshot: SavedSnapshotRow) {
        _folders.value = snapshot.folders.map { SavedFolder(it._id, it.name, it.createdAt) }
        _savedItems.value = snapshot.items.map {
            SavedItemEntry(it.hadithId, it.createdAt, it.updatedAt, it.bookmarkCreatedAt, it.favoriteCreatedAt, it.noteContent, it.folderId, it.hadith?.toRef())
        }
        _bookmarks.value = _savedItems.value.mapNotNull { item -> item.bookmarkCreatedAt?.let { SavedEntry(item.hadithId, it, hadith = item.hadith) } }
        _favorites.value = _savedItems.value.mapNotNull { item -> item.favoriteCreatedAt?.let { SavedEntry(item.hadithId, it, hadith = item.hadith) } }
        _notes.value = _savedItems.value.mapNotNull { item -> item.noteContent?.let { SavedEntry(item.hadithId, item.createdAt, item.updatedAt, it, item.hadith) } }
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

    private fun DetailedRow.toEntry() = SavedEntry(
        rowId = _id,
        createdAt = createdAt,
        hadith = hadith?.let { h -> h.toRef() },
    )

    private fun HadithSummary.toRef() = HadithRef(
        hadithId = _id,
        collectionSlug = collectionSlug,
        collectionName = collectionName,
        volumeId = volumeId,
        hadithNumber = providerHadithId,
        arabicText = arabicText,
        englishText = englishText,
        referenceDisplay = referenceDisplay,
    )

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
