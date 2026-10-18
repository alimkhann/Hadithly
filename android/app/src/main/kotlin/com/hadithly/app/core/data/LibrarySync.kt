package com.hadithly.app.core.data

import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
data class LibrarySyncOwner(val key: String, val subject: String, val namespace: String = "fixture") { val storageKey: String get() = "$namespace|$key" }

@Serializable
sealed interface LibraryLocalSource {
    @Serializable data class Bookmark(val value: GuestBookmarkDraft) : LibraryLocalSource
    @Serializable data class Favorite(val value: GuestFavoriteDraft) : LibraryLocalSource
    @Serializable data class Note(val value: GuestNoteDraft) : LibraryLocalSource
    @Serializable data class Folder(val value: GuestSavedFolderDraft) : LibraryLocalSource
    @Serializable data class Membership(val value: GuestSavedMembership) : LibraryLocalSource
    @Serializable data class Position(val value: GuestReadingProgressDraft) : LibraryLocalSource
    @Serializable data class Account(val reference: HadithRef?) : LibraryLocalSource
}

@Serializable
data class LibraryLocalChange(val operation: SyncOperation, val source: LibraryLocalSource) {
    constructor(command: SyncCommand, at: Double, source: LibraryLocalSource) : this(
        SyncOperation(UUID.randomUUID().toString(), UUID.randomUUID().toString(), at, command), source,
    )
}

@Serializable
data class LibraryFrozenBatch(val batch: SyncBatch, val changes: List<LibraryLocalChange>)

@Serializable
sealed interface LibraryRecovery {
    @Serializable data class Invalid(val source: LibraryLocalSource) : LibraryRecovery
    @Serializable data class Server(val change: LibraryLocalChange, val outcome: SyncOutcome) : LibraryRecovery
    @Serializable data class Historical(val change: LibraryLocalChange) : LibraryRecovery
}

@Serializable
data class LibraryRecentReceipt(val receipt: SyncReceipt, val expiresAt: Double)

@Serializable
data class LibrarySyncPartition(val ownerKey: String, val subject: String, val state: LibraryPartitionState)

@Serializable
data class LibraryPartitionState(
    var pending: List<LibraryLocalChange> = emptyList(),
    var frozen: LibraryFrozenBatch? = null,
    var recovery: List<LibraryRecovery> = emptyList(),
    var recent: List<LibraryRecentReceipt> = emptyList(),
    val clientKey: String = UUID.randomUUID().toString(),
    var nextSequence: Double = 1.0,
    var acknowledgement: SyncAcknowledgement? = null,
) {
    fun append(source: LibraryLocalSource, command: SyncCommand?, at: Double) {
        if (command == null || !at.isFinite() || at < 0) recovery = recovery + LibraryRecovery.Invalid(source)
        else pending = pending + LibraryLocalChange(command, at, source)
    }
    fun freeze(): SyncFrame? {
        if (acknowledgement != null) throw LibrarySyncFailure.InvalidReceipt
        frozen?.let { return SyncFrame(clientKey, nextSequence, it.batch) }
        if (pending.isEmpty()) return null
        val id = UUID.randomUUID().toString()
        val selected = mutableListOf<LibraryLocalChange>()
        var fanout = 0
        for (change in pending.take(LibrarySyncLimits.operations)) {
            val extra = when (change.operation.command) { is SyncCommand.FolderDelete, is SyncCommand.FolderRestore -> 1; else -> 0 }
            if (fanout + extra > LibrarySyncLimits.fanoutOperations) break
            val candidate = SyncBatch(id, (selected + change).map { it.operation })
            if (Json.encodeToString(candidate).toByteArray(Charsets.UTF_8).size > LibrarySyncLimits.bytes) break
            selected.add(change)
            fanout += extra
        }
        if (selected.isEmpty()) throw LibrarySyncFailure.OversizedChange
        val batch = SyncBatch(id, selected.map { it.operation })
        frozen = LibraryFrozenBatch(batch, selected)
        pending = pending.drop(selected.size)
        return SyncFrame(clientKey, nextSequence, batch)
    }
    private fun settleReceipts(reply: SyncReply, now: Double) {
        val captured = frozen ?: throw LibrarySyncFailure.InvalidReceipt
        if (captured.batch.id != reply.batchId || reply.receipts.size != captured.changes.size) throw LibrarySyncFailure.InvalidReceipt
        val byId = captured.changes.associateBy { it.operation.id }.toMutableMap()
        val stagedRecovery = mutableListOf<LibraryRecovery>()
        val stagedRecent = mutableListOf<LibraryRecentReceipt>()
        for (receipt in reply.receipts) {
            val change = byId.remove(receipt.id) ?: throw LibrarySyncFailure.InvalidReceipt
            if (change.operation.revision != receipt.revision) throw LibrarySyncFailure.InvalidReceipt
            when (receipt.outcome) {
                SyncOutcome.Preserved, is SyncOutcome.Folder, is SyncOutcome.FolderDeleted -> Unit
                is SyncOutcome.FolderRestored -> if (receipt.outcome.superseded.isNotEmpty() || receipt.outcome.missing.isNotEmpty()) stagedRecovery.add(LibraryRecovery.Server(change, receipt.outcome))
                is SyncOutcome.Superseded, is SyncOutcome.Unresolved, is SyncOutcome.ResolvedPosition -> stagedRecovery.add(LibraryRecovery.Server(change, receipt.outcome))
            }
            when (change.operation.command) {
                is SyncCommand.BookmarkRemove, is SyncCommand.FavoriteRemove, is SyncCommand.NoteRemove, is SyncCommand.FolderDelete -> {
                    val expiry = change.operation.at + 5_000
                    if (expiry > now) stagedRecent.add(LibraryRecentReceipt(receipt, expiry))
                }
                else -> Unit
            }
        }
        if (byId.isNotEmpty()) throw LibrarySyncFailure.InvalidReceipt
        recovery = recovery + stagedRecovery
        recent = recent.filter { it.expiresAt > now } + stagedRecent
        frozen = null
        nextSequence++
    }
    private fun checkCursor(cursor: SyncCursor) {
        if (!cursor.closedThrough.isFinite() || cursor.closedThrough < 0 || kotlin.math.floor(cursor.closedThrough) != cursor.closedThrough || cursor.closedThrough >= 9_007_199_254_740_991.0) throw LibrarySyncFailure.InvalidReceipt
        cursor.active?.let {
            if (it.clientKey != clientKey || it.sequence != cursor.closedThrough + 1 || it.reply.batchId.isEmpty() || it.digest.isEmpty()) throw LibrarySyncFailure.InvalidReceipt
        }
    }
    private fun adopt(cursor: SyncCursor) {
        checkCursor(cursor)
        frozen?.let { recovery = recovery + it.changes.map(LibraryRecovery::Historical) }
        frozen = null
        nextSequence = cursor.closedThrough + 1
        acknowledgement = cursor.active?.let { SyncAcknowledgement(clientKey, it.sequence, it.reply.batchId, it.digest) }
    }
    fun settle(exchange: SyncExchange, requested: SyncFrame, now: Double) {
        if (requested.clientKey != clientKey || requested.sequence != nextSequence || frozen?.batch != requested.batch || acknowledgement != null) throw LibrarySyncFailure.InvalidReceipt
        when (exchange) {
            is SyncExchange.Accepted -> {
                val committed = exchange.committed
                if (committed.clientKey != clientKey || committed.sequence != requested.sequence || committed.digest.isEmpty()) throw LibrarySyncFailure.InvalidReceipt
                settleReceipts(committed.reply, now)
                acknowledgement = SyncAcknowledgement(clientKey, committed.sequence, committed.reply.batchId, committed.digest)
            }
            is SyncExchange.Reconcile -> {
                if (exchange.clientKey != clientKey || exchange.requestedSequence != requested.sequence || exchange.requestedBatchId != requested.batch.id) throw LibrarySyncFailure.InvalidReceipt
                adopt(exchange.cursor)
            }
        }
    }
    fun settleAcknowledgement(reply: SyncAckReply, requested: SyncAcknowledgement) {
        if (acknowledgement != requested || reply.clientKey != clientKey) throw LibrarySyncFailure.InvalidReceipt
        adopt(reply.cursor)
    }

}

sealed class LibrarySyncFailure : Exception() {
    data object StoreUnavailable : LibrarySyncFailure()
    data object OwnerMismatch : LibrarySyncFailure()
    data object InvalidReceipt : LibrarySyncFailure()
    data object OversizedChange : LibrarySyncFailure()
    data object SessionChanged : LibrarySyncFailure()
}

data class LibrarySyncSession(val id: String, val subject: String)

class LibraryWriteContext internal constructor(
    internal val session: LibrarySyncSession,
    internal val owner: LibrarySyncOwner,
    internal val generation: String,
)

interface LibrarySyncTransport {
    val namespace: String
    suspend fun open(): SyncBinding
    suspend fun acknowledge(capability: String, acknowledgement: SyncAcknowledgement): SyncAckReply
    suspend fun send(capability: String, frame: SyncFrame): SyncExchange
}

class LibrarySync(
    private val store: GuestDataStore,
    private val transport: LibrarySyncTransport,
    scope: CoroutineScope,
    private val currentSession: () -> LibrarySyncSession?,
    private val now: () -> Double = { System.currentTimeMillis().toDouble() },
) {
    sealed interface Status {
        data object Idle : Status
        data object Syncing : Status
        data class Ready(val recovered: Int) : Status
        data object Failed : Status
    }
    private val scope = CoroutineScope(scope.coroutineContext + Dispatchers.Main.immediate)
    private val mutableOwner = kotlinx.coroutines.flow.MutableStateFlow<LibrarySyncOwner?>(null)
    val owner = mutableOwner.asStateFlow()
    private val mutableStatus = MutableStateFlow<Status>(Status.Idle)
    val status = mutableStatus.asStateFlow()
    var onOwnerChange: (LibrarySyncOwner?) -> Unit = {}
    private var session: LibrarySyncSession? = null
    private var binding: SyncBinding? = null
    private var generation = UUID.randomUUID().toString()
    private var worker: Deferred<Unit>? = null
    private var retryTask: Job? = null
    private var retryDelay = 1_000L
    private var requested = false
    init { store.onGuestChanged = { wake() } }

    suspend fun activate(next: LibrarySyncSession) = withContext(Dispatchers.Main.immediate) { activateOnMain(next) }

    private suspend fun activateOnMain(next: LibrarySyncSession) {
        if (currentSession() != next) return
        if (session != next) { deactivate(); session = next }
        worker?.let { it.await(); return }
        retryTask?.cancel()
        retryTask = null
        val epoch = generation
        mutableStatus.value = Status.Syncing
        requested = false
        val task = scope.async(start = CoroutineStart.LAZY) { run(next, epoch) }
        worker = task
        task.invokeOnCompletion {
            scope.launch {
                if (generation == epoch && worker === task) { worker = null; if (requested) wake() }
            }
        }
        task.start()
        task.await()
    }
    @androidx.annotation.MainThread
    fun deactivate() {
        generation = UUID.randomUUID().toString()
        worker?.cancel()
        retryTask?.cancel()
        worker = null
        retryTask = null
        session = null
        binding = null
        mutableOwner.value = null
        mutableStatus.value = Status.Idle
        onOwnerChange(null)
    }
    fun wake() {
        scope.launch {
            val current = session ?: return@launch
            if (currentSession() != current) return@launch
            requested = true
            if (worker == null) activateOnMain(current)
        }
    }
    @androidx.annotation.MainThread
    fun captureWriteContext(): LibraryWriteContext {
        val active = session ?: throw LibrarySyncFailure.SessionChanged
        val owner = mutableOwner.value ?: throw LibrarySyncFailure.SessionChanged
        if (currentSession() != active) throw LibrarySyncFailure.SessionChanged
        return LibraryWriteContext(active, owner, generation)
    }

    suspend fun enqueue(change: LibraryLocalChange, context: LibraryWriteContext) = withContext(Dispatchers.Main.immediate) { enqueueOnMain(change, context) }

    private suspend fun enqueueOnMain(change: LibraryLocalChange, context: LibraryWriteContext) {
        if (generation != context.generation || session != context.session || currentSession() != context.session || mutableOwner.value != context.owner) throw LibrarySyncFailure.SessionChanged
        store.enqueueSyncChange(change, context.owner)
        wake()
    }
    private fun checkSession(session: LibrarySyncSession, epoch: String) {
        if (generation != epoch || currentSession() != session) throw LibrarySyncFailure.SessionChanged
    }
    private suspend fun run(session: LibrarySyncSession, epoch: String) {
        try {
            checkSession(session, epoch)
            if (binding == null || (binding?.validUntil ?: 0.0) <= now() + 1_000) {
                val opened = transport.open()
                checkSession(session, epoch)
                if (opened.subject != session.subject || !opened.validUntil.isFinite() || opened.validUntil <= now()) throw LibrarySyncFailure.OwnerMismatch
                binding = opened
                val owner = LibrarySyncOwner(opened.ownerKey, opened.subject, transport.namespace)
                mutableOwner.value = owner
                onOwnerChange(owner)
            }
            val binding = binding ?: throw LibrarySyncFailure.OwnerMismatch
            val owner = mutableOwner.value ?: throw LibrarySyncFailure.OwnerMismatch
            repeat(8) {
                checkSession(session, epoch)
                store.claimGuestForSync(owner)
                checkSession(session, epoch)
                val acknowledgement = store.syncPartition(owner)?.acknowledgement
                if (acknowledgement != null) {
                    val reply = transport.acknowledge(binding.capability, acknowledgement)
                    store.settleSyncAcknowledgement(reply, acknowledgement, owner)
                    checkSession(session, epoch)
                    return@repeat
                }
                val frame = store.freezeSyncFrame(owner)
                if (frame == null) {
                    mutableStatus.value = Status.Ready(store.syncPartition(owner)?.recovery?.size ?: 0)
                    retryDelay = 1_000
                    return
                }
                val reply = transport.send(binding.capability, frame)
                store.settleSyncExchange(reply, frame, owner, now())
                checkSession(session, epoch)
            }
            schedule(session, epoch, 250)
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (_: LibrarySyncFailure.SessionChanged) { }
        catch (_: LibrarySyncFailure.OwnerMismatch) {
            if (generation == epoch) {
                binding = null
                mutableOwner.value = null
                mutableStatus.value = Status.Failed
                onOwnerChange(null)
            }
        } catch (_: Exception) {
            if (generation != epoch || currentSession() != session) return
            mutableStatus.value = Status.Failed
            schedule(session, epoch, retryDelay)
            retryDelay = (retryDelay * 2).coerceAtMost(30_000)
        }
    }
    private fun schedule(session: LibrarySyncSession, epoch: String, after: Long) {
        retryTask?.cancel()
        retryTask = scope.launch {
            delay(after)
            if (generation == epoch && currentSession() == session) { retryTask = null; activateOnMain(session) }
        }
    }
}
