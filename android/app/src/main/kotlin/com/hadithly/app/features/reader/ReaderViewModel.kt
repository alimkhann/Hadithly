package com.hadithly.app.features.reader

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.hadithly.app.HadithlyApplication
import com.hadithly.app.core.data.CollectionOutlineResult
import com.hadithly.app.core.data.OutlineChapter
import com.hadithly.app.core.data.OutlineVolume
import com.hadithly.app.core.data.ReaderHadith
import com.hadithly.app.core.data.ReaderPageResult
import com.hadithly.app.core.data.ReaderTranslation
import com.hadithly.app.core.data.ReadingLayout
import com.hadithly.app.core.data.ReadingPosition
import com.hadithly.app.core.data.ReadingPositionAnchor
import com.hadithly.app.core.data.ReadingWidthClass
import com.hadithly.app.core.data.ReaderTarget
import com.hadithly.app.core.data.ReaderTargetResolver
import com.hadithly.app.core.data.ReaderTargetSource
import com.hadithly.app.core.data.TranslationFailure
import com.hadithly.app.core.data.TranslationSubmissionResult
import com.hadithly.app.core.links.CanonicalHadithLink
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
    private val openPosition: ReadingPosition?,
    private val targetSource: ReaderTargetSource,
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
    private var lastCapturedAnchor: String? = null
    private var lastCapturedNormalizedOffset: Double? = null
    private var lastStableAnchor: ReaderHadith? = null
    private var lastStableRawPageOffset = 0.0
    private var lastStableNormalizedOffset = 0.0
    var restoredPosition: ReadingPosition? = null
        private set

    /**
     * Bumped every time the model re-issues restoration (layout-preference
     * changes re-anchor the semantic position). The page keys its applied
     * restoration on this so a preference change re-scrolls exactly once.
     */
    var restorationGeneration: Int = 0
        private set
    var landingHadithNumber: String? = null
        private set

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
                val target = ReaderTargetResolver.resolve(
                    ReaderTarget(targetSource, collectionSlug, openHadithNumber, openPosition),
                )
                restoredPosition = target.position
                landingHadithNumber = target.hadithNumber
                val targetVolume = target.hadithNumber?.let {
                    volumeIdForHadithNumber(it, result.volumes)
                }
                val requested = result.volumes.firstOrNull { it.volumeId == openVolumeId }?.volumeId
                val restoredVolume = result.volumes.firstOrNull { it.volumeId == target.volumeId }?.volumeId
                val firstVolume = restoredVolume ?: requested ?: targetVolume ?: result.volumes.firstOrNull()?.volumeId
                _state.update { it.copy(phase = Phase.Reading, volumes = result.volumes) }
                if (firstVolume != null) {
                    _state.update { it.copy(selectedVolumeId = firstVolume) }
                    loadPage(0, firstVolume, target.hadithNumber)
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

        /**
         * R6A: short collection name for the compact source label
         * (`Bukhari – 57`). Falls back to the full collection name for
         * unknown slugs; never synthesized from anything else.
         */
        fun shortCollectionName(collectionSlug: String, fallbackName: String): String =
            when (collectionSlug) {
                "bukhari" -> "Bukhari"
                "muslim" -> "Muslim"
                "sunan-nasai" -> "Nasa'i"
                "abu-dawood" -> "Abu Dawood"
                "tirmidhi" -> "Tirmidhi"
                "ibn-majah" -> "Ibn Majah"
                "mishkat-al-masabih" -> "Mishkat"
                else -> fallbackName
            }

        /**
         * R6A: trailing number in a `Volume N` outline title, for localized
         * formatting (`reader_volume_title`). Null for any other title shape;
         * callers then render the raw title unchanged.
         */
        fun volumeTitleNumber(title: String): Int? =
            Regex("^Volume\\s+(\\d+)$").find(title.trim())?.groupValues?.get(1)?.toIntOrNull()

        /**
         * R6A: global hadith range (first to last, 1-based) for [volumeId]
         * from the outline's cumulative source-provided counts. Null when the
         * outline is missing, any count is non-positive, or the volume is
         * absent — the corner label then shows the title only.
         */
        fun volumeHadithRange(
            volumes: List<OutlineVolume>,
            volumeId: String,
        ): Pair<Int, Int>? {
            if (volumes.isEmpty()) return null
            var lower = 0
            for (volume in volumes) {
                val count = volume.hadithCount.toInt()
                if (count <= 0) return null
                val first = lower + 1
                val last = lower + count
                if (volume.volumeId == volumeId) return first to last
                lower = last
            }
            return null
        }

        /**
         * R6A: true when every page of the selected volume is in the local
         * cache — non-empty, no page still fetching forward, no
         * skipped-by-jump placeholder. The corner range appends only then.
         */
        fun isVolumeFullyCached(pages: List<ReaderPageResult>): Boolean =
            pages.isNotEmpty() && pages.none { it.hasMore || it.isPlaceholder }
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

    /**
     * R5: selects the volume holding [chapter] and targets the chapter's
     * first hadith through the same R2 target path as canonical links
     * (backend resolves the containing page; stale numbers keep volume
     * start via the resolver fallback).
     */
    fun selectChapter(volumeId: String, chapter: OutlineChapter) {
        jumpToHadith(volumeId, chapter.firstProviderHadithId)
    }

    /**
     * R5: jump-to-reference from the contents sheet. Well-formed input
     * navigates via the same path as canonical links: the volume holding
     * the number, or the first volume's start when the number is stale.
     * Returns false for malformed input (the sheet stays open with an
     * inline error); true dismisses the sheet.
     */
    fun jumpToReference(number: String): Boolean {
        val trimmed = number.trim()
        if (!CanonicalHadithLink.isValidProviderHadithId(trimmed)) return false
        val volumes = _state.value.volumes
        if (volumes.isEmpty()) return false
        val volumeId = volumeIdForHadithNumber(trimmed, volumes)
        // A stale number carries no page target: land at the first volume's
        // start, exactly like a stale canonical link.
        if (volumeId == null) {
            selectVolumeFallback(volumes.first().volumeId)
        } else {
            jumpToHadith(volumeId, trimmed)
        }
        return true
    }

    private fun selectVolumeFallback(volumeId: String) {
        landingHadithNumber = null
        restoredPosition = null
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

    /** Resets onto [volumeId] and lands the pager on the page holding [hadithNumber]. */
    private fun jumpToHadith(volumeId: String, hadithNumber: String) {
        landingHadithNumber = hadithNumber
        restoredPosition = null
        cancelTranslationRun()
        _state.update {
            it.copy(
                selectedVolumeId = volumeId,
                pages = emptyList(),
                pageIndex = 0,
                translations = emptyMap(),
            )
        }
        loadPage(0, volumeId, hadithNumber)
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
        val restoredHadith = restoredPosition?.let { position ->
            page.items.firstOrNull {
                it.provider == position.anchor.provider &&
                    it.collectionSlug == position.anchor.collectionSlug &&
                    it.providerHadithId == position.anchor.providerHadithId
            }
        }
        val landingHadith = landingHadithNumber?.let { number ->
            page.items.firstOrNull { it.providerHadithId == number }
        }
        saveProgress(
            anchor = restoredHadith ?: landingHadith ?: first,
            page = page,
            rawPageOffset = if (restoredHadith == null) 0.0 else restoredPosition?.rawPageOffset ?: 0.0,
            normalizedOffset = if (restoredHadith == null) 0.0 else restoredPosition?.normalizedOffset ?: 0.0,
        )
    }

    /** Records a settled visible hadith and ignores imperceptible scroll changes. */
    fun captureStableScroll(
        hadiths: List<ReaderHadith>,
        leadingIndex: Int,
        rawPageOffset: Double,
        normalizedOffset: Double,
    ) {
        val page = _state.value.pages.getOrNull(_state.value.pageIndex) ?: return
        val anchor = hadiths.getOrNull(leadingIndex) ?: return
        val clamped = normalizedOffset.coerceIn(0.0, 1.0)
        lastStableAnchor = anchor
        lastStableRawPageOffset = rawPageOffset.coerceAtLeast(0.0)
        lastStableNormalizedOffset = clamped
        if (lastCapturedAnchor == anchor.internalId &&
            lastCapturedNormalizedOffset?.let { kotlin.math.abs(it - clamped) < 0.02 } == true
        ) return
        lastCapturedAnchor = anchor.internalId
        lastCapturedNormalizedOffset = clamped
        saveProgress(anchor, page, rawPageOffset.coerceAtLeast(0.0), clamped)
    }

    /** Compact top progress fraction (R4); null until the backend reports a total. */
    fun compactProgressFraction(): Double? {
        val total = totalPages() ?: return null
        if (total <= 0) return null
        return (_state.value.pageIndex + 1).toDouble() / total
    }

    /**
     * Re-issues restoration against the current layout signature (R4). After
     * a font, size, visibility, or locale change the raw offset is stale; the
     * last stable semantic anchor recovers the exact position.
     */
    fun reanchorAfterLayoutChange() {
        val s = _state.value
        if (s.phase != Phase.Reading) return
        val page = s.pages.getOrNull(s.pageIndex) ?: return
        val anchor = lastStableAnchor ?: return
        if (page.items.none { it._id == anchor._id }) return
        val layout = readingLayout(page)
        restoredPosition = ReadingPosition(
            anchor = ReadingPositionAnchor(
                provider = anchor.provider,
                collectionSlug = anchor.collectionSlug,
                providerHadithId = anchor.providerHadithId,
            ),
            contentVersion = page.contentVersion,
            volumeId = anchor.volumeId ?: s.selectedVolumeId ?: "unknown",
            chapterId = anchor.chapterId,
            pageKey = page.pageKey,
            displayPageIndex = page.page.coerceAtLeast(1.0),
            rawPageOffset = lastStableRawPageOffset,
            normalizedOffset = lastStableNormalizedOffset,
            layoutSignature = layout.signature,
            updatedAt = System.currentTimeMillis().toDouble(),
        )
        restorationGeneration += 1
    }

    private fun readingLayout(page: ReaderPageResult): ReadingLayout {
        val preferences = app.preferences.preferences.value
        return ReadingLayout(
            locale = preferences.translationLocale,
            arabicVisible = preferences.arabicVisible,
            translationVisible = preferences.translationVisible,
            arabicFontId = preferences.arabicFont.wire,
            arabicFontSize = preferences.arabicFontSize.toDouble(),
            widthClass = readingWidthClass,
            paginationVersion = page.paginationVersion,
        )
    }

    private fun saveProgress(
        anchor: ReaderHadith,
        page: ReaderPageResult,
        rawPageOffset: Double,
        normalizedOffset: Double,
    ) {
        val s = _state.value
        val layout = readingLayout(page)
        val storedUpdatedAt = library.progressFor(collectionSlug)?.position?.updatedAt ?: 0.0
        val updatedAt = maxOf(
            System.currentTimeMillis().toDouble(),
            storedUpdatedAt + 1.0,
            lastPositionUpdatedAt + 1.0,
        )
        lastPositionUpdatedAt = updatedAt
        val position = ReadingPosition(
            anchor = ReadingPositionAnchor(
                provider = anchor.provider,
                collectionSlug = anchor.collectionSlug,
                providerHadithId = anchor.providerHadithId,
            ),
            contentVersion = page.contentVersion,
            volumeId = anchor.volumeId ?: s.selectedVolumeId ?: "unknown",
            chapterId = anchor.chapterId,
            pageKey = page.pageKey,
            displayPageIndex = page.page.coerceAtLeast(1.0),
            rawPageOffset = rawPageOffset,
            normalizedOffset = normalizedOffset,
            layoutSignature = layout.signature,
            updatedAt = updatedAt,
        )
        library.saveProgress(position, refFor(anchor))
    }

    private fun errorMessage(error: Exception): String = error.message ?: error.toString()

    override fun onCleared() {
        saveCurrentProgress()
        super.onCleared()
    }
}
