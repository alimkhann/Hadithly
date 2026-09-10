package com.hadithly.app.core.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * R6 round 3 quiet prefetch. Entry screens (Library/Home/Saved) ensure the
 * outline plus the continue-reading target volume's first page are cached;
 * the reader background-caches adjacent volumes so switches never wait.
 *
 * Bounded (at most [MAX_ENTRY_FETCHES] entry fetches, at most two adjacent
 * volumes), silent (every fetch is individually guarded), offline-tolerant
 * (failures return normally), and UI-free (callers launch on
 * Dispatchers.IO; nothing here touches composition).
 */
object ReaderPrefetch {

    /** Seven outlines plus one continue-reading page at most. */
    const val MAX_ENTRY_COLLECTIONS = 7

    /** One entry fetch: an outline, or one volume's first page. */
    sealed interface EntryFetch {
        data class Outline(val collectionSlug: String) : EntryFetch
        data class FirstPage(val collectionSlug: String, val volumeId: String) : EntryFetch
    }

    /**
     * Bounded entry plan: outlines for at most the first
     * [MAX_ENTRY_COLLECTIONS] distinct slugs, plus the most-recent
     * continue-reading target's volume first page when it names a volume.
     */
    fun entryPlan(slugs: List<String>, progress: List<ProgressEntry>): List<EntryFetch> {
        val plan = mutableListOf<EntryFetch>()
        for (slug in slugs.distinct().take(MAX_ENTRY_COLLECTIONS)) {
            plan.add(EntryFetch.Outline(slug))
        }
        val target = progress.filter { it.hadith != null }.maxByOrNull { it.updatedAt }
        val volumeId = target?.hadith?.volumeId?.takeIf { it.isNotBlank() }
        if (target != null && volumeId != null) {
            plan.add(EntryFetch.FirstPage(target.collectionSlug, volumeId))
        }
        return plan
    }

    /**
     * Adjacent source-provided volume ids around [selectedId] in outline
     * order: previous then next, at most two. Empty when the selection is
     * unknown or the outline holds one volume.
     */
    fun adjacentVolumeIds(volumes: List<OutlineVolume>, selectedId: String?): List<String> {
        if (selectedId == null) return emptyList()
        val index = volumes.indexOfFirst { it.volumeId == selectedId }
        if (index < 0) return emptyList()
        return buildList {
            volumes.getOrNull(index - 1)?.let { add(it.volumeId) }
            volumes.getOrNull(index + 1)?.let { add(it.volumeId) }
        }
    }

    /**
     * Runs the entry plan with existing cache-first repository actions.
     * Each fetch is guarded so one failure (offline, revoked session)
     * never fails the batch or reaches the UI.
     */
    suspend fun warmEntryCache(
        repository: ConvexRepository,
        slugs: List<String>,
        progress: List<ProgressEntry>,
    ) = withContext(Dispatchers.IO) {
        executePlan(
            plan = entryPlan(slugs, progress),
            fetchOutline = { slug -> repository.getCollectionOutline(slug) },
            fetchPage = { slug, volumeId -> repository.getReaderPage(slug, volumeId, 0) },
        )
    }

    /**
     * Executes one bounded plan; every fetch is individually guarded.
     * Separated for unit pins on bounds and silent failure tolerance.
     */
    suspend fun executePlan(
        plan: List<EntryFetch>,
        fetchOutline: suspend (String) -> Unit,
        fetchPage: suspend (String, String) -> Unit,
    ) {
        for (fetch in plan) {
            runCatching {
                when (fetch) {
                    is EntryFetch.Outline -> fetchOutline(fetch.collectionSlug)
                    is EntryFetch.FirstPage -> fetchPage(fetch.collectionSlug, fetch.volumeId)
                }
            }
        }
    }

    /**
     * Background-caches the volumes adjacent to the reader's selection
     * (first page each). Bounded to two fetches, silent, offline-tolerant.
     */
    suspend fun warmAdjacentVolumes(
        repository: ConvexRepository,
        collectionSlug: String,
        volumes: List<OutlineVolume>,
        selectedId: String?,
    ) = withContext(Dispatchers.IO) {
        for (volumeId in adjacentVolumeIds(volumes, selectedId)) {
            runCatching { repository.getReaderPage(collectionSlug, volumeId, 0) }
        }
    }
}
