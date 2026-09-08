package com.hadithly.app.core.data

import kotlinx.coroutines.CoroutineScope
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
                repository.subscribe<List<DetailedRow>>("library:listBookmarksDetailed")
                    .collect { rows -> _bookmarks.value = rows.map { it.toEntry() } }
            }.failed()
        )
        subscriptions.add(
            scope.launch(Dispatchers.IO) {
                repository.subscribe<List<DetailedRow>>("library:listFavoritesDetailed")
                    .collect { rows -> _favorites.value = rows.map { it.toEntry() } }
            }.failed()
        )
        subscriptions.add(
            scope.launch(Dispatchers.IO) {
                repository.subscribe<List<DetailedNoteRow>>("library:listNotesDetailed")
                    .collect { rows ->
                        _notes.value = rows.map {
                            SavedEntry(
                                rowId = it._id,
                                createdAt = it.createdAt,
                                updatedAt = it.updatedAt,
                                noteContent = it.content,
                                hadith = it.hadith?.let { h -> h.toRef() },
                            )
                        }
                    }
            }.failed()
        )
        subscriptions.add(
            scope.launch(Dispatchers.IO) {
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
            }.failed()
        )
    }

    /**
     * A subscription that raced the Convex session errors without data.
     * Re-open everything, bounded.
     */
    private fun Job.failed(): Job = this.also { job ->
        // collect() throws into the coroutine; wrap via invokeOnCompletion.
        job.invokeOnCompletion { cause ->
            if (cause != null) subscriptionFailed()
        }
    }

    private fun subscriptionFailed() {
        subscriptionsActive = false
        if (retriesLeft > 0 && isSignedIn()) {
            retriesLeft -= 1
            scope.launch {
                delay(1500)
                refresh()
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
