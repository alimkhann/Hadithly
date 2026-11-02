package com.hadithly.app.core.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Entry screens (Library/Home/Saved) warm only the most recent reading target's
 * outline and first page. The reader also warms adjacent volumes.
 *
 * Bounded (at most two entry fetches, at most two adjacent
 * volumes), silent (every fetch is individually guarded), offline-tolerant
 * (failures return normally), and UI-free (callers launch on
 * Dispatchers.IO; nothing here touches composition).
 */
object ReaderPrefetch {

    /** One entry fetch: an outline, or one volume's first page. */
    sealed interface EntryFetch {
        data class Outline(val collectionSlug: String) : EntryFetch
        data class FirstPage(val collectionSlug: String, val volumeId: String) : EntryFetch
    }

    /** Unopened collections stay cold; only a real resume target justifies warming. */
    fun entryPlan(progress: List<ProgressEntry>): List<EntryFetch> {
        val target = progress.filter { it.hadith != null }.maxByOrNull { it.updatedAt }
            ?: return emptyList()
        return buildList {
            add(EntryFetch.Outline(target.collectionSlug))
            target.hadith?.volumeId?.takeIf { it.isNotBlank() }?.let { volumeId ->
                add(EntryFetch.FirstPage(target.collectionSlug, volumeId))
            }
        }
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
        progress: List<ProgressEntry>,
        pages: ReaderPageContentStore? = null,
    ) = withContext(Dispatchers.IO) {
        val context = pages?.contextVersion()
        executePlan(
            plan = entryPlan(progress),
            fetchOutline = { slug -> repository.getCollectionOutline(slug) },
            fetchPage = { slug, volumeId ->
                if (pages != null) pages.load(ReaderPageContentStore.Request(slug, volumeId, 0), expectedVersion = context)
                else repository.getReaderPage(slug, volumeId, 0)
            },
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
