package com.hadithly.app.features.reader

import com.clerk.api.Clerk
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.hadithly.app.HadithlyApplication
import com.hadithly.app.core.data.CollectionOutlineResult
import com.hadithly.app.core.data.EnglishSearchResult
import com.hadithly.app.core.data.HadithRef
import com.hadithly.app.core.data.OutlineChapter
import com.hadithly.app.core.data.OutlineVolume
import com.hadithly.app.core.data.ReaderHadith
import com.hadithly.app.core.data.ReaderPageResult
import com.hadithly.app.core.data.ReaderPrefetch
import com.hadithly.app.core.data.ReaderTranslation
import com.hadithly.app.core.data.PublicationAvailability
import com.hadithly.app.core.data.ReadingLayout
import com.hadithly.app.core.data.ReadingPosition
import com.hadithly.app.core.data.ReadingPositionAnchor
import com.hadithly.app.core.data.ReadingWidthClass
import com.hadithly.app.core.data.ReaderTarget
import com.hadithly.app.core.data.ReaderTargetResolver
import com.hadithly.app.core.data.ReaderTargetSource
import com.hadithly.app.core.data.TranslationFailure
import com.hadithly.app.core.links.CanonicalHadithLink
import kotlinx.coroutines.Job
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.delay

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
    private val measurement = com.hadithly.app.core.analytics.ReaderMeasurement()
    private var usedOfflineForEntry = false
    private var initialTargetInspected = false
    fun beginMeasurement() {
        emitMeasurement(measurement.begin(Clerk.user == null, openPosition != null, targetSource == ReaderTargetSource.NOTIFICATION))
        if (_state.value.phase is Phase.Failed) emitMeasurement(measurement.failure())
    }
    private fun emitMeasurement(facts: List<com.hadithly.app.core.analytics.AnalyticsMetric>) { facts.forEach(app.analytics::record) }
    fun endMeasurement() { emitMeasurement(measurement.close()); app.analytics.flush() }
    private fun readable(hadith: ReaderHadith): Boolean {
        val preferences = app.preferences.preferences.value
        if (preferences.arabicVisible && hadith.arabicText.isNotEmpty()) return true
        if (!preferences.translationVisible) return false
        val translation = (_state.value.translations[hadith.internalId] as? TranslationUiState.Loaded)?.translation
        return translation?.translation?.isNotEmpty() == true || _state.value.language == "en" && !hadith.englishText.isNullOrEmpty()
    }
    fun observeVisibleEntry(providerHadithId: String, minY: Double, height: Double, viewport: Double) {
        val hadith = currentPageHadiths().firstOrNull { it.providerHadithId == providerHadithId } ?: return
        if (_state.value.verticalLanding != null || minY >= viewport || minY + height <= 0 || !readable(hadith)) return
        val wasRendered = measurement.rendered
        emitMeasurement(measurement.visible(usedOfflineForEntry))
        if (!wasRendered && measurement.rendered) app.analytics.firstReaderSucceeded()
    }
    fun inspectInitialTarget(anchors: List<Triple<String, Double, Double>>, viewport: Double) {
        if (initialTargetInspected) return
        initialTargetInspected = true
        val expected = openPosition?.anchor?.providerHadithId ?: if (targetSource == ReaderTargetSource.NOTIFICATION) openHadithNumber else null
        val anchor = anchors.firstOrNull { it.first == expected }
        val desired = openPosition?.normalizedOffset ?: 0.0
        val exact = anchor != null && anchor.second < viewport && anchor.second + anchor.third > 0 &&
            kotlin.math.abs(anchor.second + desired * anchor.third) <= 8.0 * app.resources.displayMetrics.density
        emitMeasurement(measurement.settleTarget(exact)); app.analytics.flush()
    }

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
        val translationAllowances: Map<String, com.hadithly.app.core.data.TranslationAllowance> = emptyMap(),
        val verticalLanding: ReaderVerticalLandingRequest? = null,
    )

    private val _state = MutableStateFlow(ReaderState(language = app.preferences.preferences.value.translationLocale))
    val state: StateFlow<ReaderState> = _state

    private var pageJob: Job? = null
    private var translationJob: Job? = null
    private val automaticRequests = com.hadithly.app.core.preferences.ReaderAutomaticTranslationLedger()
    private val generationJobs = mutableMapOf<String, Job>()
    private var publicationJob: Job? = null
    private var publicationDeadlineJob: Job? = null
    private var translationGeneration = 0
    private var nextVerticalLandingToken = 0
    private var readingWidthClass = ReadingWidthClass.COMPACT
    private var lastPositionUpdatedAt = 0.0
    private var lastCapturedAnchor: String? = null
    private var lastCapturedNormalizedOffset: Double? = null
    private var lastStableAnchor: ReaderHadith? = null
    private var lastStableRawPageOffset = 0.0
    private var lastStableNormalizedOffset = 0.0
    var restoredPosition: ReadingPosition? = null
        private set

    var landingHadithNumber: String? = null
        private set

    val library = app.library

    init {
        viewModelScope.launch { _state.collect { if (it.phase is Phase.Failed) emitMeasurement(measurement.failure()) } }
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

    private fun requestVerticalLanding(
        landing: ReaderVerticalLanding,
        volumeId: String,
        pageIndex: Int,
    ) {
        nextVerticalLandingToken += 1
        _state.update {
            it.copy(
                verticalLanding = ReaderVerticalLandingRequest(
                    token = nextVerticalLandingToken,
                    page = ReaderVerticalLandingPage(volumeId, pageIndex),
                    landing = landing,
                ),
            )
        }
    }

    private fun requestHeaderLanding(pageIndex: Int = _state.value.pageIndex) {
        _state.value.selectedVolumeId?.let { requestVerticalLanding(ReaderVerticalLanding.Header, it, pageIndex) }
    }

    private fun requestEntryLanding(pageIndex: Int) {
        val state = _state.value
        val volumeId = state.selectedVolumeId ?: return
        val items = state.pages.getOrNull(pageIndex)?.items.orEmpty()
        val position = restoredPosition
        when {
            position != null && items.any { it.providerHadithId == position.anchor.providerHadithId } ->
                requestVerticalLanding(
                    ReaderVerticalLanding.Semantic(position.anchor.providerHadithId, position.normalizedOffset),
                    volumeId,
                    pageIndex,
                )
            landingHadithNumber != null && items.any { it.providerHadithId == landingHadithNumber } ->
                requestVerticalLanding(ReaderVerticalLanding.Semantic(landingHadithNumber!!, 0.0), volumeId, pageIndex)
            else -> requestHeaderLanding(pageIndex)
        }
    }

    fun acknowledgeVerticalLanding(request: ReaderVerticalLandingRequest) {
        if (_state.value.verticalLanding != request) return
        _state.update { state ->
            if (state.verticalLanding == request) state.copy(verticalLanding = null) else state
        }
    }

    fun positionedHadith(): ReaderHadith? {
        lastStableAnchor?.let { stable ->
            if (currentPageHadiths().any { it.internalId == stable.internalId }) return stable
        }
        val target = restoredPosition?.anchor?.providerHadithId ?: landingHadithNumber
        return currentPageHadiths().firstOrNull { it.providerHadithId == target }
            ?: currentPageHadiths().firstOrNull()
    }

    fun hasPreviousPage(): Boolean = _state.value.pageIndex > 0

    fun hasNextPage(): Boolean {
        val s = _state.value
        if (s.pageIndex !in s.pages.indices) return false
        if (s.pageIndex < s.pages.size - 1) return true
        return s.pages[s.pageIndex].hasMore
    }

    /** Adjacent source-provided volumes in outline order. */
    fun previousVolume(): OutlineVolume? {
        val state = _state.value
        val index = state.volumes.indexOfFirst { it.volumeId == state.selectedVolumeId }
        return state.volumes.getOrNull(index - 1)
    }

    fun nextVolume(): OutlineVolume? {
        val state = _state.value
        val index = state.volumes.indexOfFirst { it.volumeId == state.selectedVolumeId }
        return state.volumes.getOrNull(index + 1)
    }

    internal fun pagePills(): ReaderPagePills.State {
        val state = _state.value
        val loaded = state.pages.getOrNull(state.pageIndex)?.isPlaceholder == false
        return ReaderPagePills.state(
            pageIndex = state.pageIndex,
            hasPreviousPage = hasPreviousPage(),
            hasNextPage = hasNextPage(),
            atLoadedPage = loaded,
            volumes = state.volumes,
            selectedVolumeId = state.selectedVolumeId,
        )
    }

    fun toggleChrome() = _state.update { it.copy(chromeVisible = !it.chromeVisible) }

    /**
     * R6 round 3: any horizontal or vertical scroll collapses to the focused
     * view. Deliberately haptic-free (only the tap toggle plays the haptic)
     * and idempotent; the caller also closes the reader menu, which never
     * survives a focus change.
     */
    fun collapseToFocused() {
        _state.update { if (it.chromeVisible) it.copy(chromeVisible = false) else it }
    }

    fun setReadingWidthClass(widthClass: ReadingWidthClass) {
        readingWidthClass = widthClass
    }

    // Lifecycle

    /**
     * A fetch that never resolves (dead network, hung socket) must not
     * strand the reader on a spinner when a verified dump is on disk. Each
     * fetch races a bounded timeout; the timeout falls into the same
     * offline-fallback path as any other fetch failure.
     */
    private fun loadOutline() {
        viewModelScope.launch {
            try {
                val result = withTimeout(FETCH_TIMEOUT_MS) {
                    app.repository.getCollectionOutline(collectionSlug)
                }
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
                if (!useOfflineOutline()) {
                    _state.update { it.copy(phase = Phase.Failed(errorMessage(error))) }
                }
            }
        }
    }

    /**
     * O2: when the outline fetch fails (airplane mode, revoked session) and
     * a verified dump is active, read the outline from disk. Volumes come
     * from the dump's own volume ids; titles fall back to the id so nothing
     * is invented. Returns false when no dump is active.
     */
    private fun useOfflineOutline(): Boolean {
        val outline = app.offline.offlineOutline(collectionSlug) ?: return false
        if (outline.volumes.isEmpty()) return false
        usedOfflineForEntry = true
        val target = ReaderTargetResolver.resolve(
            ReaderTarget(targetSource, collectionSlug, openHadithNumber, openPosition),
        )
        restoredPosition = target.position
        landingHadithNumber = target.hadithNumber
        val targetVolume = target.hadithNumber?.let { volumeIdForHadithNumber(it, outline.volumes) }
        val requested = outline.volumes.firstOrNull { it.volumeId == openVolumeId }?.volumeId
        val restoredVolume = outline.volumes.firstOrNull { it.volumeId == target.volumeId }?.volumeId
        val firstVolume = requested ?: restoredVolume ?: targetVolume ?: outline.volumes.firstOrNull()?.volumeId
        _state.update { it.copy(phase = Phase.Reading, volumes = outline.volumes) }
        if (firstVolume != null) {
            _state.update { it.copy(selectedVolumeId = firstVolume) }
            loadPage(0, firstVolume, target.hadithNumber)
        } else {
            _state.update { it.copy(phase = Phase.Failed("No volumes found for this collection.")) }
        }
        return true
    }

    fun volumeIdForHadithNumber(
        hadithNumber: String,
        volumes: List<OutlineVolume>,
    ): String? = Companion.volumeIdForHadithNumber(hadithNumber, volumes)

    companion object {
        private const val FETCH_TIMEOUT_MS = 10_000L

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
        saveCurrentProgress()
        _state.update {
            it.copy(
                selectedVolumeId = volumeId,
                pages = emptyList(),
                pageIndex = 0,
                translations = emptyMap(), translationAllowances = emptyMap(),
                verticalLanding = null,
            )
        }
        cancelTranslationRun()
        loadPage(0, volumeId)
    }

    /** One page-pill target for both buttons and the outward-edge swipe. */
    internal fun followPill(pill: ReaderPagePills.Pill) {
        when (val target = pill.target) {
            is ReaderPagePills.Target.Page -> onPageSettled(target.index)
            is ReaderPagePills.Target.VolumeFirst -> switchToVolume(target.volumeId, VolumeEdge.FIRST)
            is ReaderPagePills.Target.VolumeLast -> switchToVolume(target.volumeId, VolumeEdge.LAST)
        }
    }

    enum class VolumeEdge { FIRST, LAST }

    /**
     * Saves the current R1 anchor, then fetches the requested edge of an
     * adjacent source-provided volume. The new edge becomes the R2 target;
     * a first visit remains visibly loading until that exact page is ready.
     */
    fun switchToVolume(volumeId: String, edge: VolumeEdge) {
        if (volumeId == _state.value.selectedVolumeId) return
        if (_state.value.volumes.none { it.volumeId == volumeId }) return
        saveCurrentProgress()
        pageJob?.cancel()
        cancelTranslationRun()
        landingHadithNumber = null
        restoredPosition = null
        _state.update {
            it.copy(
                selectedVolumeId = volumeId,
                pages = emptyList(),
                pageIndex = 0,
                isLoadingPage = true,
                translations = emptyMap(), translationAllowances = emptyMap(),
                verticalLanding = null,
            )
        }
        pageJob = viewModelScope.launch {
            try {
                val first = app.repository.getReaderPage(collectionSlug, volumeId, 0)
                val landing = if (edge == VolumeEdge.FIRST) 0 else maxOf(0, first.totalPagesInt - 1)
                val last = if (landing == 0) first else {
                    app.repository.getReaderPage(collectionSlug, volumeId, landing)
                }
                val pages = if (landing == 0) listOf(first) else {
                    List(landing) { emptyPage() } + last
                }
                _state.update {
                    it.copy(pages = pages, pageIndex = landing, phase = Phase.Reading)
                }
                requestHeaderLanding(landing)
                scheduleTranslationsForCurrentPage()
                cacheAdjacentVolumes()
                saveCurrentProgress()
            } catch (_: CancellationException) {
                // A newer page or volume target replaced this fetch.
            } catch (error: Exception) {
                if (_state.value.pages.isEmpty()) {
                    _state.update { it.copy(phase = Phase.Failed(errorMessage(error))) }
                }
            } finally {
                _state.update { it.copy(isLoadingPage = false) }
            }
        }
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
                translations = emptyMap(), translationAllowances = emptyMap(),
                verticalLanding = null,
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
                translations = emptyMap(), translationAllowances = emptyMap(),
                verticalLanding = null,
            )
        }
        loadPage(0, volumeId, hadithNumber)
    }

    fun setLanguage(code: String) {
        if (code == _state.value.language) return
        app.preferences.setTranslationLocale(code)
        cancelTranslationRun()
        _state.update { it.copy(language = code, translations = emptyMap(), translationAllowances = emptyMap()) }
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
            var shouldPrefetchNeighbor = false
            try {
                val result = withTimeout(FETCH_TIMEOUT_MS) {
                    app.repository.getReaderPage(
                        collectionSlug = collectionSlug,
                        volumeId = volumeId,
                        page = index,
                        targetHadithNumber = jumpToHadithNumber,
                    )
                }
                _state.update { s ->
                    val landingIndex = if (jumpToHadithNumber != null) maxOf(0, result.pageNumber - 1) else index
                    val pages = s.pages.toMutableList()
                    while (pages.size < landingIndex) pages.add(emptyPage())
                    if (landingIndex in pages.indices) pages[landingIndex] = result else pages.add(result)
                    s.copy(pages = pages, phase = Phase.Reading)
                }
                if (jumpToHadithNumber != null) {
                    val landingIndex = maxOf(0, result.pageNumber - 1)
                    _state.update { it.copy(pageIndex = landingIndex) }
                    requestEntryLanding(landingIndex)
                    shouldPrefetchNeighbor = true
                } else if (_state.value.pageIndex == index) {
                    if (_state.value.verticalLanding == null) requestHeaderLanding(index)
                    scheduleTranslationsForCurrentPage()
                    shouldPrefetchNeighbor = true
                }
                cacheAdjacentVolumes()
            } catch (error: Exception) {
                if (!useOfflinePage(index, volumeId, jumpToHadithNumber) &&
                    _state.value.pages.isEmpty()
                ) {
                    _state.update { it.copy(phase = Phase.Failed(errorMessage(error))) }
                }
            } finally {
                _state.update { it.copy(isLoadingPage = false) }
                // Publish the current page first, then release the
                // single-flight gate before asking for its next neighbor.
                // Otherwise every fresh reader starts with a loading page
                // beside it instead of a real drag preview.
                if (shouldPrefetchNeighbor) prefetchForwardIfNeeded()
            }
        }
    }

    private fun emptyPage() = ReaderPageResult(items = emptyList(), page = 0.0)

    /**
     * O2: when a page fetch fails and a verified dump is active, serve the
     * page from disk with the same content-sized chunking. Positions still
     * resolve by semantic anchor, so approximate page numbers never strand
     * the reader. Returns false when no dump covers the request.
     */
    private fun useOfflinePage(index: Int, volumeId: String, jumpToHadithNumber: String?): Boolean {
        usedOfflineForEntry = true
        val store = app.offline
        val language = _state.value.language
        jumpToHadithNumber?.let { jump ->
            store.offlineHadith("sunnah_now:$collectionSlug:$jump", collectionSlug, language)?.let { hadith ->
                // Legacy wire values: an offline jump target has no server
                // page identity; the anchor carries the position.
                val result = ReaderPageResult(
                    items = listOf(hadith),
                    page = 1.0,
                    pageSize = 1.0,
                    totalPages = 1.0,
                    hasMore = false,
                    contentVersion = "legacy",
                    paginationVersion = 1.0,
                    pageKey = "legacy",
                )
                _state.update { s ->
                    val pages = s.pages.toMutableList()
                    while (pages.size < index) pages.add(emptyPage())
                    if (index in pages.indices) pages[index] = result else pages.add(result)
                    s.copy(pages = pages, phase = Phase.Reading)
                }
                _state.update { it.copy(pageIndex = index) }
                return true
            }
        }
        val result = store.offlinePage(collectionSlug, volumeId, index, language) ?: return false
        _state.update { s ->
            val pages = s.pages.toMutableList()
            while (pages.size < index) pages.add(emptyPage())
            if (index in pages.indices) pages[index] = result else pages.add(result)
            s.copy(pages = pages, phase = Phase.Reading)
        }
        return true
    }

    /** Swiping back onto a skipped-by-jump page loads it on demand. */
    fun onPageSettled(index: Int) {
        val s = _state.value
        if (index == s.pageIndex) return
        _state.update { it.copy(pageIndex = index) }
        requestHeaderLanding(index)
        // A settled scroll (user swipe or pill/edge turn) lands focused:
        // the menu is closed by the screen observing the page index, and
        // the chrome collapses here with no haptic.
        collapseToFocused()
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

    /**
     * R6 round 3: background-caches the adjacent volumes' first pages so
     * volume switches never wait. Bounded (at most two), silent (no state
     * change), offline-tolerant (guarded); runs on Dispatchers.IO inside
     * the prefetch helper.
     */
    private fun cacheAdjacentVolumes() {
        val s = _state.value
        if (s.phase != Phase.Reading) return
        viewModelScope.launch {
            ReaderPrefetch.warmAdjacentVolumes(
                repository = app.repository,
                collectionSlug = collectionSlug,
                volumes = s.volumes,
                selectedId = s.selectedVolumeId,
            )
        }
    }

    /**
     * R6 round 3 menu search over cached provider English text. Explicit
     * return type; Dispatchers.IO and the blank short-circuit live in the
     * repository.
     */
    suspend fun searchEnglish(text: String): List<EnglishSearchResult> =
        app.repository.searchEnglish(text, collectionSlug)

    /**
     * R6 round 3: a search hit navigates exact through the R2 target path
     * (volume locator plus landing hadith, same stale fallback as canonical
     * links). Returns false when the hit names another collection, which
     * this reader cannot resolve.
     */
    fun navigateToSearchResult(result: EnglishSearchResult): Boolean {
        if (result.collectionSlug != collectionSlug) return false
        val volumes = _state.value.volumes
        if (volumes.isEmpty()) return false
        val volumeId = volumeIdForHadithNumber(result.providerHadithId, volumes)
            ?: volumes.first().volumeId
        jumpToHadith(volumeId, result.providerHadithId)
        return true
    }

    /**
     * R6 round 3: a reader Saved-sheet row navigates exact. A stored
     * volume id wins; otherwise the volume locator resolves the number;
     * a stale number degrades to the first volume's start.
     */
    fun navigateToSaved(ref: HadithRef): Boolean {
        val volumes = _state.value.volumes
        if (volumes.isEmpty()) return false
        val number = ref.hadithNumber
        val storedVolume = volumes.firstOrNull { it.volumeId == ref.volumeId }?.volumeId
        if (number.isNullOrBlank()) {
            if (storedVolume != null) {
                selectVolume(storedVolume)
                return true
            }
            return false
        }
        val volumeId = storedVolume
            ?: volumeIdForHadithNumber(number, volumes)
            ?: volumes.first().volumeId
        jumpToHadith(volumeId, number)
        return true
    }

    // Translations

    private fun cancelTranslationRun() {
        translationJob?.cancel()
        translationJob = null
        translationGeneration += 1
    }

    /** Page opening/paging reads one batch of existing exact-locale defaults. */
    private fun scheduleTranslationsForCurrentPage() {
        val hadiths = currentPageHadiths()
        if (hadiths.isEmpty()) return
        translationGeneration += 1
        val generation = translationGeneration
        val language = _state.value.language
        translationJob?.cancel()
        translationJob = viewModelScope.launch {
            try {
                val rows = app.repository.storedReaderTranslations(hadiths, language)
                if (generation != translationGeneration) return@launch
                val loaded = rows.mapNotNull { row -> row.translation?.let { row.hadithInternalId to TranslationUiState.Loaded(it.readerTranslation()) } }.toMap()
                _state.update { it.copy(translations = it.translations + loaded) }
                watchLoadedPublications()
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { /* Existing provider/offline content remains readable. */ }
        }
    }

    private suspend fun generateTranslation(hadith: ReaderHadith, language: String) {
        app.analytics.record(com.hadithly.app.core.analytics.AnalyticsMetric.translationResultStarted)
        val id = hadith.internalId
        val requestedAccountId = Clerk.user?.id
        if (!app.isSignedIn()) {
            app.analytics.record(com.hadithly.app.core.analytics.AnalyticsMetric.translationResultSignInRequired)
            _state.update { it.copy(translations = it.translations + (id to TranslationUiState.Failed(TranslationFailure.RequiresSignIn))) }
            return
        }
        _state.update { it.copy(translations = it.translations + (id to TranslationUiState.Loading)) }
        try {
            val cached = app.repository.storedReaderTranslation(hadith, language)
            if (cached != null) {
                if (_state.value.language == language && Clerk.user?.id == requestedAccountId) {
                    _state.update { it.copy(translations = it.translations + (id to TranslationUiState.Loaded(cached))) }
                    app.analytics.record(com.hadithly.app.core.analytics.AnalyticsMetric.translationResultCache)
                    watchLoadedPublications()
                    refreshTranslationAllowance(id, language, requestedAccountId)
                }
                return
            }
            refreshTranslationAllowance(id, language, requestedAccountId)
            val result = app.repository.translateHadith(id, language)
            if (_state.value.language != language || Clerk.user?.id != requestedAccountId) return
            _state.update { it.copy(translations = it.translations + (id to TranslationUiState.Loaded(result))) }
            app.analytics.record(if (result.cached) com.hadithly.app.core.analytics.AnalyticsMetric.translationResultCache else com.hadithly.app.core.analytics.AnalyticsMetric.translationResultGenerated)
            watchLoadedPublications()
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (error: Exception) {
            if (_state.value.language != language || Clerk.user?.id != requestedAccountId) return
            _state.update { it.copy(translations = it.translations + (id to TranslationUiState.Failed(TranslationFailure.of(errorMessage(error))))) }
            app.analytics.record(when (TranslationFailure.of(errorMessage(error))) {
                TranslationFailure.QuotaExceeded -> com.hadithly.app.core.analytics.AnalyticsMetric.translationResultQuota
                TranslationFailure.RequiresSignIn -> com.hadithly.app.core.analytics.AnalyticsMetric.translationResultSignInRequired
                else -> com.hadithly.app.core.analytics.AnalyticsMetric.translationResultFailed
            })
        }
        refreshTranslationAllowance(id, language, requestedAccountId)
    }

    private suspend fun refreshTranslationAllowance(id: String, language: String, accountId: String?) {
        val allowance = runCatching { app.repository.translationAllowance() }.getOrNull() ?: return
        if (_state.value.language != language || Clerk.user?.id != accountId || !app.isSignedIn()) return
        _state.update { it.copy(translationAllowances = it.translationAllowances + (id to allowance)) }
    }

    private fun watchLoadedPublications() {
        publicationJob?.cancel()
        publicationDeadlineJob?.cancel()
        val entries = _state.value.translations.entries.filter { it.value is TranslationUiState.Loaded }.sortedBy { it.key }
        val observed = entries.takeLast(40)
        val retained = observed.map { it.key }.toSet()
        _state.update { current -> current.copy(translations = current.translations.filter { it.value !is TranslationUiState.Loaded || it.key in retained }) }
        if (observed.isEmpty()) return
        val ids = observed.mapNotNull { (it.value as? TranslationUiState.Loaded)?.translation?.translationId }
        publicationJob = viewModelScope.launch {
            try {
                app.repository.watchPublications(ids).collect { statuses ->
                    _state.update { it.copy(translations = keepAvailableTranslations(it.translations, statuses)) }
                    publicationDeadlineJob?.cancel()
                    if (statuses.any { it.validUntil != null }) {
                        publicationDeadlineJob = viewModelScope.launch {
                            while (true) {
                                val deadline = statuses.mapNotNull { it.validUntil }.filter { it > System.currentTimeMillis() }.minOrNull() ?: break
                                delay((deadline - System.currentTimeMillis()).toLong().coerceAtLeast(1))
                                _state.update { it.copy(translations = keepAvailableTranslations(it.translations, statuses)) }
                            }
                        }
                    }
                }
                _state.update { it.copy(translations = it.translations.filterKeys { key -> key !in retained }) }
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { _state.update { it.copy(translations = it.translations.filterKeys { key -> key !in retained }) } }
        }
    }

    /** The only reader path that creates a new global translation. */
    fun automaticallyTranslateVisible(ids: List<String>) {
        val preferences = app.preferences.preferences.value
        if (!app.readerExperience.automaticallyTranslates.value || !preferences.translationVisible || !app.isSignedIn() || hasQuotaFailure()) return
        val state = _state.value
        currentPageHadiths().filter { it.internalId in ids }.forEach { hadith ->
            if (automaticRequests.claim(hadith.internalId, state.language,
                hasTranslation = state.language == "en" && !hadith.englishText.isNullOrEmpty(),
                hasRequestState = state.translations[hadith.internalId] != null)) retryTranslation(hadith)
        }
    }

    fun retryTranslation(hadith: ReaderHadith) {
        if (generationJobs[hadith.internalId]?.isActive == true) return
        val language = _state.value.language
        generationJobs[hadith.internalId] = viewModelScope.launch {
            try { generateTranslation(hadith, language) }
            finally { generationJobs.remove(hadith.internalId) }
        }
    }

    fun resetTranslationRequestsForAccount() {
        automaticRequests.reset()
        _state.update { it.copy(translationAllowances = emptyMap(), translations = it.translations.filterValues { state -> state is TranslationUiState.Loaded }) }
        generationJobs.values.forEach { it.cancel() }
        generationJobs.clear()
    }

    fun hasQuotaFailure(): Boolean = _state.value.translations.values.any { translationState ->
        translationState is TranslationUiState.Failed && translationState.failure == TranslationFailure.QuotaExceeded
    }

    /** Purchase retry resumes only explicitly requested, quota-rejected hadiths. */
    fun retryTranslationsAfterPurchase() {
        val requested = currentPageHadiths().filter { hadith ->
            val translation = _state.value.translations[hadith.internalId]
            translation is TranslationUiState.Failed && translation.failure == TranslationFailure.QuotaExceeded
        }
        requested.forEach(::retryTranslation)
    }

    val canContribute: Boolean get() = app.isSignedIn()

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
        val stableHadith = lastStableAnchor?.let { stable ->
            page.items.firstOrNull { it.internalId == stable.internalId }
        }
        saveProgress(
            anchor = stableHadith ?: restoredHadith ?: landingHadith ?: first,
            page = page,
            rawPageOffset = when {
                stableHadith != null -> lastStableRawPageOffset
                restoredHadith != null -> restoredPosition?.rawPageOffset ?: 0.0
                else -> 0.0
            },
            normalizedOffset = when {
                stableHadith != null -> lastStableNormalizedOffset
                restoredHadith != null -> restoredPosition?.normalizedOffset ?: 0.0
                else -> 0.0
            },
        )
    }

    /** Records a settled visible hadith and ignores imperceptible scroll changes. */
    fun captureStableScroll(
        hadiths: List<ReaderHadith>,
        leadingIndex: Int,
        rawPageOffset: Double,
        normalizedOffset: Double,
    ) {
        if (_state.value.verticalLanding != null) return
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
        s.selectedVolumeId?.let { volumeId ->
            requestVerticalLanding(
                ReaderVerticalLanding.Semantic(anchor.providerHadithId, lastStableNormalizedOffset),
                volumeId,
                s.pageIndex,
            )
        }
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

internal fun keepAvailableTranslations(translations: Map<String, TranslationUiState>, statuses: List<PublicationAvailability>, now: Long = System.currentTimeMillis()): Map<String, TranslationUiState> =
    translations.filterValues { state ->
        val translation = (state as? TranslationUiState.Loaded)?.translation
        val status = statuses.firstOrNull { it.translationId == translation?.translationId }
        status == null || status.available && (status.validUntil?.let { it > now } ?: true)
    }
