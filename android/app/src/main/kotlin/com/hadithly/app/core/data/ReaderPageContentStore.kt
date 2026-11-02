package com.hadithly.app.core.data

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlin.coroutines.coroutineContext

class ReaderPageContentStore(
    private val capacity: Int = 28,
    private val fetch: suspend (Request) -> ReaderPageResult,
) {
    data class Request(val collection: String, val volume: String, val index: Int, val target: String? = null)
    private data class Slot(val collection: String, val volume: String, val index: Int)
    private data class Identity(val key: String, val version: String, val pagination: Double, val providers: List<String>)
    private data class Entry(val identity: Identity, val page: ReaderPageResult, val sequence: Long, val storedAt: Long)
    private data class Flight(val task: Deferred<ReaderPageResult>, val sequence: Long, val generation: Long)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val entries = linkedMapOf<Slot, Entry>()
    private val flights = mutableMapOf<Request, Flight>()
    private val latestSequences = linkedMapOf<Slot, Long>()
    private var oldestAcceptedSequence = 0L
    private var sequence = 0L
    private var generation = 0L
    private var reading = false
    private data class Volume(val collection: String, val volume: String)
    private data class Coverage(val total: Int, val loaded: java.util.BitSet = java.util.BitSet())
    private val coverage = mutableMapOf<Volume, Coverage>()
    private val paginationByCollection = mutableMapOf<String, Pair<Double, Long>>()
    var observedIdentityChanges = 0
        private set

    fun beginReading() { if (!reading) expireEntryWarmth(); reading = true }

    fun clear() {
        generation++
        flights.values.forEach { it.task.cancel() }
        flights.clear(); entries.clear(); latestSequences.clear(); paginationByCollection.clear(); coverage.clear()
        reading = false
    }

    private fun expireEntryWarmth() {
        val now = System.nanoTime()
        entries.entries.removeAll { now - it.value.storedAt > 120_000_000_000L }
    }

    fun hasCompleteVolume(collection: String, volume: String): Boolean =
        coverage[Volume(collection, volume)]?.let { it.loaded.cardinality() == it.total } ?: false

    private fun rememberCoverage(page: ReaderPageResult, request: Request) {
        val index = page.pageNumber - 1
        if (index < 0 || index >= page.totalPagesInt || page.items.isEmpty()) return
        val key = Volume(request.collection, request.volume)
        val known = coverage[key]?.takeIf { it.total == page.totalPagesInt } ?: Coverage(page.totalPagesInt)
        known.loaded.set(index)
        coverage[key] = known
    }

    fun isCompatible(page: ReaderPageResult, collection: String) =
        paginationByCollection[collection]?.first?.let { it == page.paginationVersion } ?: true

    fun peek(collection: String, volume: String, index: Int): ReaderPageResult? {
        if (!reading) expireEntryWarmth()
        val slot = Slot(collection, volume, index)
        val entry = entries.remove(slot) ?: return null
        entries[slot] = entry
        return entry.page
    }

    fun peekLast(collection: String, volume: String): ReaderPageResult? {
        val slot = entries.filter { (slot, entry) -> slot.collection == collection && slot.volume == volume &&
            slot.index == entry.page.totalPagesInt - 1 }.maxByOrNull { it.value.sequence }?.key ?: return null
        return peek(collection, volume, slot.index)
    }

    suspend fun contextVersion(): Long = withContext(Dispatchers.Main.immediate) { generation }

    suspend fun load(request: Request, expectedVersion: Long? = null): ReaderPageResult = withContext(Dispatchers.Main.immediate) {
        coroutineContext.ensureActive()
        if (expectedVersion != null && expectedVersion != generation) throw CancellationException()
        if (!reading) expireEntryWarmth()
        val target = request.target
        if (target != null) {
            val hit = entries.filter { (slot, entry) -> slot.collection == request.collection && slot.volume == request.volume &&
                entry.page.items.any { it.providerHadithId == target } }.maxByOrNull { it.value.sequence }
            if (hit != null) {
                val entry = entries.remove(hit.key)!!; entries[hit.key] = entry
                coroutineContext.ensureActive()
                return@withContext entry.page
            }
        } else {
            peek(request.collection, request.volume, request.index)?.let {
                coroutineContext.ensureActive()
                return@withContext it
            }
        }
        val flight = flights[request] ?: run {
            if (flights.size >= 4) {
                val waitingGeneration = generation
                kotlinx.coroutines.delay(25)
                return@withContext load(request, expectedVersion = waitingGeneration)
            }
            val requestSequence = ++sequence
            val requestGeneration = generation
            val task = scope.async {
                try {
                    val page = withTimeout(10_000) { fetch(request) }
                    coroutineContext.ensureActive()
                    if (requestGeneration != generation || requestSequence < oldestAcceptedSequence) throw CancellationException()
                    accept(request, page, requestSequence)
                } finally {
                    if (requestGeneration == generation && flights[request]?.sequence == requestSequence) flights.remove(request)
                }
            }
            Flight(task, requestSequence, requestGeneration).also { if (!task.isCompleted) flights[request] = it }
        }
        val page = flight.task.await()
        coroutineContext.ensureActive()
        if (flight.generation != generation) throw CancellationException()
        page
    }

    private fun accept(request: Request, page: ReaderPageResult, requestSequence: Long): ReaderPageResult {
        val slot = Slot(request.collection, request.volume, (page.pageNumber - 1).coerceAtLeast(0))
        if ((latestSequences[slot] ?: -1) > requestSequence) {
            val current = entries[slot] ?: throw CancellationException()
            if (request.target != null && current.page.items.none { it.providerHadithId == request.target }) throw CancellationException()
            return current.page
        }
        if (!page.isPlaceholder && page.pageKey != "legacy" && page.contentVersion != "legacy") {
            val priorPagination = paginationByCollection[request.collection]
            if (priorPagination != null && priorPagination.first != page.paginationVersion) {
                if (priorPagination.second > requestSequence) throw CancellationException()
                entries.entries.removeAll { it.key.collection == request.collection }
                coverage.keys.removeAll { it.collection == request.collection }
            }
            if ((priorPagination?.second ?: -1) < requestSequence) paginationByCollection[request.collection] = page.paginationVersion to requestSequence
            rememberCoverage(page, request)
            val identity = Identity(page.pageKey, page.contentVersion, page.paginationVersion,
                page.items.map { "${it.provider}|${it.internalId}|${it._id}" })
            if (entries[slot]?.identity?.let { it != identity } == true) observedIdentityChanges++
            entries.remove(slot)
            entries[slot] = Entry(identity, page, requestSequence, System.nanoTime())
            latestSequences.remove(slot); latestSequences[slot] = requestSequence
            while (latestSequences.size > capacity.coerceAtLeast(1) * 2) {
                val removed = latestSequences.entries.first()
                oldestAcceptedSequence = maxOf(oldestAcceptedSequence, removed.value)
                latestSequences.remove(removed.key)
            }
            while (entries.size > capacity.coerceAtLeast(1)) entries.remove(entries.keys.first())
        }
        return page
    }

    val retainedPageCount: Int get() = entries.size
    val inFlightPageCount: Int get() = flights.size
}
