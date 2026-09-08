package com.hadithly.app.features.reader

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.hadithly.app.HadithlyApplication
import com.hadithly.app.core.data.CollectionOutlineResult
import com.hadithly.app.core.data.OutlineVolume
import com.hadithly.app.core.data.ReaderHadith
import com.hadithly.app.core.data.ReaderPageResult
import com.hadithly.app.core.data.ReaderTranslation
import com.hadithly.app.core.data.ReadingLayout
import com.hadithly.app.core.data.ReadingPosition
import com.hadithly.app.core.data.ReadingPositionAnchor
import com.hadithly.app.core.data.ReadingWidthClass
import com.hadithly.app.core.data.TranslationFailure
import com.hadithly.app.core.data.TranslationSubmissionResult
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Per-hadith AI translation state, keyed by the hadith's internal id. */
sealed interface TranslationUiState {
    data object Loading : TranslationUiState
    data class Loaded(val translation: ReaderTranslation) : TranslationUiState
    data class Failed(val failure: TranslationFailure) : TranslationUiState
}

/**
 * Drives the reader: loads the collection outline, pages hadiths by content
 * size through getReaderPage, prefetches forward, and pulls AI translations
 * for the chosen language with graceful quota/sign-in handling. Also owns
 * bookmark/favorite/note toggles and private progress saves. Port of the
 * iOS ReaderModel.
 */
class ReaderViewModel(
    private val app: HadithlyApplication,
    private val collectionSlug: String,
    private val openVolumeId: String?,
    private val openHadithNumber: String?,
) : ViewModel() {

    sealed interface Phase {
        data object LoadingOutline : Phase
        data object Reading : Phase
        data class Failed(val message: String) : Phase
    }

    data class ReaderState(
        val phase: Phase = Phase.LoadingOutline,
        val volumes: List<OutlineVolume> = emptyList(),
        val pages: List<ReaderPageResult> = emptyList(),
        val selectedVolumeId: String? = null,
        val isLoadingPage: Boolean = false,
        val pageIndex: Int = 0,
        val chromeVisible: Boolean = true,
        val language: String = "en",
        val translations: Map<String, TranslationUiState> = emptyMap(),
    )

    private val _state = MutableStateFlow(ReaderState(language = app.preferences.preferences.value.translationLocale))
    val state: StateFlow<ReaderState> = _state

    private var pageJob: Job? = null
    private var translationJob: Job? = null
    private var translationGeneration = 0
    private var readingWidthClass = ReadingWidthClass.COMPACT
    private var lastPositionUpdatedAt = 0.0

    val library = app.library

    init {
        loadOutline()
    }

    val collectionName: String =
        com.hadithly.app.core.data.Collections.all.firstOrNull { it.first == collectionSlug }?.second
            ?: collectionSlug

    fun currentVolumeTitle(): String? =
        _state.value.volumes.firstOrNull { it.volumeId == _state.value.selectedVolumeId }?.title

    fun totalPages(): Int? = _state.value.pages.lastOrNull()?.totalPagesInt?.takeIf { it > 0 }

    fun currentPageHadiths(): List<ReaderHadith> {
        val pages = _state.value.pages
        val index = _state.value.pageIndex
        return if (index in pages.indices) pages[index].items else emptyList()
    }

    fun hasPreviousPage(): Boolean = _state.value.pageIndex > 0

    fun hasNextPage(): Boolean {
        val s = _state.value
        if (s.pageIndex !in s.pages.indices) return false
        if (s.pageIndex < s.pages.size - 1) return true
        return s.pages[s.pageIndex].hasMore
    }

    fun toggleChrome() = _state.update { it.copy(chromeVisible = !it.chromeVisible) }

    fun setReadingWidthClass(widthClass: ReadingWidthClass) {
        readingWidthClass = widthClass
    }

    // Lifecycle

    private fun loadOutline() {
        viewModelScope.launch {
            try {
                val result = app.repository.getCollectionOutline(collectionSlug)
                // Explicit deep links (Today/Saved) name a volume; a canonical
                // link carries only the hadith number, so the volume holding
                // it comes from the outline's source-provided counts. Unknown
                // or stale numbers degrade to the first volume.
                val targetVolume = openHadithNumber?.let {
                    volumeIdForHadithNumber(it, result.volumes)
                }
                val requested = result.volumes.firstOrNull { it.volumeId == openVolumeId }?.volumeId
                val firstVolume = requested ?: targetVolume ?: result.volumes.firstOrNull()?.volumeId
                _state.update { it.copy(phase = Phase.Reading, volumes = result.volumes) }
                if (firstVolume != null) {
                    _state.update { it.copy(selectedVolumeId = firstVolume) }
                    loadPage(0, firstVolume, openHadithNumber)
                } else {
                    _state.update { it.copy(phase = Phase.Failed("No volumes found for this collection.")) }
                }
            } catch (error: Exception) {
                _state.update { it.copy(phase = Phase.Failed(errorMessage(error))) }
            }
        }
    }

    fun volumeIdForHadithNumber(
        hadithNumber: String,
        volumes: List<OutlineVolume>,
    ): String? = Companion.volumeIdForHadithNumber(hadithNumber, volumes)

    companion object {
        /**
         * Locates the source-provided volume that holds a hadith number by
         * walking the outline's counts in order. Sub-references ("4.5") use
         * the integer part. Returns null when the number exceeds the
         * collection.
         */
        fun volumeIdForHadithNumber(
            hadithNumber: String,
            volumes: List<OutlineVolume>,
        ): String? {
            val integerPart = hadithNumber.split(".").firstOrNull() ?: return null
            val target = integerPart.toDoubleOrNull() ?: return null
            var lower = 0.0
            for (volume in volumes) {
                val upper = lower + volume.hadithCount
                if (target > lower && target <= upper) return volume.volumeId
                lower = upper
            }
            return null
        }
    }

    fun selectVolume(volumeId: String) {
        if (volumeId == _state.value.selectedVolumeId) return
        _state.update {
            it.copy(
                selectedVolumeId = volumeId,
                pages = emptyList(),
                pageIndex = 0,
                translations = emptyMap(),
            )
        }
        cancelTranslationRun()
        loadPage(0, volumeId)
    }

    fun setLanguage(code: String) {
        if (code == _state.value.language) return
        app.preferences.setTranslationLocale(code)
        cancelTranslationRun()
        _state.update { it.copy(language = code, translations = emptyMap()) }
        scheduleTranslationsForCurrentPage()
    }

    // Paging

    /**
     * Loads reader page `index` (0-based) for the given volume. Pages before
     * the requested one are filled with empty results so the page index stays
     * aligned. When jumpToHadithNumber is set (continue reading), the backend
     * resolves the containing page and it lands at its true position.
     */
    private fun loadPage(index: Int, volumeId: String, jumpToHadithNumber: String? = null) {
        if (_state.value.isLoadingPage) return
        _state.update { it.copy(isLoadingPage = true) }
        pageJob = viewModelScope.launch {
            try {
                val result = app.repository.getReaderPage(
                    collectionSlug = collectionSlug,
                    volumeId = volumeId,
                    page = index,
                    targetHadithNumber = jumpToHadithNumber,
                )
                _state.update { s ->
                    val landingIndex = if (jumpToHadithNumber != null) maxOf(0, result.pageNumber - 1) else index
                    val pages = s.pages.toMutableList()
                    while (pages.size < landingIndex) pages.add(emptyPage())
                    if (landingIndex in pages.indices) pages[landingIndex] = result else pages.add(result)
                    s.copy(pages = pages, phase = Phase.Reading)
                }
                if (jumpToHadithNumber != null) {
                    _state.update { it.copy(pageIndex = maxOf(0, result.pageNumber - 1)) }
                } else if (_state.value.pageIndex == index) {
                    scheduleTranslationsForCurrentPage()
                }
            } catch (error: Exception) {
                if (_state.value.pages.isEmpty()) {
                    _state.update { it.copy(phase = Phase.Failed(errorMessage(error))) }
                }
            } finally {
                _state.update { it.copy(isLoadingPage = false) }
            }
        }
    }

    private fun emptyPage() = ReaderPageResult(items = emptyList(), page = 0.0)

    /** Swiping back onto a skipped-by-jump page loads it on demand. */
    fun onPageSettled(index: Int) {
        val s = _state.value
        if (index == s.pageIndex) return
        _state.update { it.copy(pageIndex = index) }
        val pages = s.pages
        if (index in pages.indices && pages[index].isPlaceholder) {
            s.selectedVolumeId?.let { loadPage(index, it) }
        }
        prefetchForwardIfNeeded()
        saveCurrentProgress()
        scheduleTranslationsForCurrentPage()
    }

    /**
     * Loads the next reader page when the selection moves onto or within one
     * page of the loaded edge. The selection may legitimately sit one past
     * the last loaded page while its content is in flight.
     */
    private fun prefetchForwardIfNeeded() {
        val s = _state.value
        if (s.isLoadingPage) return
        val lastPage = s.pages.lastOrNull() ?: return
        if (!lastPage.hasMore) return
        if (s.pageIndex < s.pages.size - 1) return
        s.selectedVolumeId?.let { loadPage(s.pages.size, it) }
    }

    // Translations

    private fun cancelTranslationRun() {
        translationJob?.cancel()
        translationJob = null
        translationGeneration += 1
    }

    private fun scheduleTranslationsForCurrentPage() {
        val s = _state.value
        if (s.language == "en") return
        val hadiths = currentPageHadiths()
        if (hadiths.isEmpty()) return

        translationGeneration += 1
        val generation = translationGeneration
        translationJob?.cancel()
        translationJob = viewModelScope.launch {
            for (hadith in hadiths) {
                translateIfNeeded(hadith, generation)
            }
        }
    }

    private suspend fun translateIfNeeded(hadith: ReaderHadith, generation: Int) {
        if (_state.value.translations[hadith.internalId] != null) return
        if (!app.isSignedIn()) {
            _state.update {
                it.copy(translations = it.translations + (hadith.internalId to TranslationUiState.Failed(TranslationFailure.RequiresSignIn)))
            }
            return
        }
        _state.update {
            it.copy(translations = it.translations + (hadith.internalId to TranslationUiState.Loading))
        }
        try {
            val result = app.repository.translateHadith(hadith.internalId, _state.value.language)
            if (generation != translationGeneration) return
            _state.update {
                it.copy(translations = it.translations + (hadith.internalId to TranslationUiState.Loaded(result)))
            }
        } catch (error: Exception) {
            if (generation != translationGeneration) return
            val failure = TranslationFailure.of(errorMessage(error))
            _state.update {
                it.copy(translations = it.translations + (hadith.internalId to TranslationUiState.Failed(failure)))
            }
            // A hard wall (quota, sign-in) applies to the rest of the page;
            // stop burning calls and let the rows surface the state.
            if (failure == TranslationFailure.QuotaExceeded || failure == TranslationFailure.RequiresSignIn) {
                translationJob?.cancel()
            }
        }
    }

    /** Manual retry from a failed translation row. */
    fun retryTranslation(hadith: ReaderHadith) {
        translationJob?.cancel()
        translationJob = viewModelScope.launch {
            translateIfNeeded(hadith, translationGeneration)
        }
    }

    fun hasQuotaFailure(): Boolean = _state.value.translations.values.any { translationState ->
        translationState is TranslationUiState.Failed && translationState.failure == TranslationFailure.QuotaExceeded
    }

    /** Retry only the quota-blocked rows after RevenueCat reports Pro active. */
    fun retryTranslationsAfterPurchase() {
        _state.update { current ->
            current.copy(
                translations = current.translations.filterValues { translationState ->
                    translationState !is TranslationUiState.Failed ||
                        translationState.failure != TranslationFailure.QuotaExceeded
                },
            )
        }
        scheduleTranslationsForCurrentPage()
    }

    val canContribute: Boolean get() = app.isSignedIn()

    suspend fun submitTranslation(
        hadith: ReaderHadith,
        proposedContent: String,
        replacing: ReaderTranslation?,
    ): TranslationSubmissionResult = app.repository.submitTranslation(
        hadithInternalId = hadith.internalId,
        language = _state.value.language,
        proposedContent = proposedContent,
        replacesTranslationId = replacing?.translationId,
    )

    suspend fun reportTranslation(translation: ReaderTranslation, reason: String) {
        app.repository.reportTranslation(translation.translationId, reason)
    }

    // Saved data

    private fun refFor(hadith: ReaderHadith) = com.hadithly.app.core.data.HadithRef(
        hadithId = hadith._id,
        collectionSlug = hadith.collectionSlug,
        collectionName = hadith.collectionName,
        volumeId = _state.value.selectedVolumeId,
        hadithNumber = hadith.providerHadithId,
        arabicText = hadith.arabicText,
        englishText = hadith.englishText,
        referenceDisplay = hadith.referenceDisplay,
    )

    fun isBookmarked(hadith: ReaderHadith) = library.isBookmarked(hadith._id)

    fun isFavorite(hadith: ReaderHadith) = library.isFavorite(hadith._id)

    fun toggleBookmark(hadith: ReaderHadith) = library.toggleBookmark(refFor(hadith))

    fun toggleFavorite(hadith: ReaderHadith) = library.toggleFavorite(refFor(hadith))

    fun noteContent(hadith: ReaderHadith): String? = library.noteContentFor(hadith._id)

    fun saveNote(hadith: ReaderHadith, content: String) = library.saveNote(refFor(hadith), content)

    /** Persists the position of the first hadith on the current page. */
    fun saveCurrentProgress() {
        val s = _state.value
        if (s.phase != Phase.Reading) return
        if (s.pageIndex !in s.pages.indices) return
        val page = s.pages[s.pageIndex]
        val first = page.items.firstOrNull() ?: return
        val preferences = app.preferences.preferences.value
        val layout = ReadingLayout(
            locale = preferences.translationLocale,
            arabicVisible = preferences.arabicVisible,
            translationVisible = preferences.translationVisible,
            arabicFontId = preferences.arabicFont.wire,
            arabicFontSize = preferences.arabicFontSize.toDouble(),
            widthClass = readingWidthClass,
            paginationVersion = page.paginationVersion,
        )
        val storedUpdatedAt = library.progressFor(collectionSlug)?.position?.updatedAt ?: 0.0
        val updatedAt = maxOf(
            System.currentTimeMillis().toDouble(),
            storedUpdatedAt + 1.0,
            lastPositionUpdatedAt + 1.0,
        )
        lastPositionUpdatedAt = updatedAt
        val position = ReadingPosition(
            anchor = ReadingPositionAnchor(
                provider = first.provider,
                collectionSlug = first.collectionSlug,
                providerHadithId = first.providerHadithId,
            ),
            contentVersion = page.contentVersion,
            volumeId = first.volumeId ?: s.selectedVolumeId ?: "unknown",
            chapterId = first.chapterId,
            pageKey = page.pageKey,
            displayPageIndex = page.page.coerceAtLeast(1.0),
            rawPageOffset = 0.0,
            normalizedOffset = 0.0,
            layoutSignature = layout.signature,
            updatedAt = updatedAt,
        )
        library.saveProgress(position, refFor(first))
    }

    private fun errorMessage(error: Exception): String = error.message ?: error.toString()

    override fun onCleared() {
        saveCurrentProgress()
        super.onCleared()
    }
}
