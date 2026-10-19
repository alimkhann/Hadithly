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
    @Serializable data class Rejected(val change: LibraryLocalChange) : LibraryRecovery
}

@Serializable
data class LibraryRecentReceipt(val receipt: SyncReceipt, val expiresAt: Double)

@Serializable
data class LibrarySyncPartition(val ownerKey: String, val subject: String, val state: LibraryPartitionState)

object LibrarySyncAdmission {
    fun accepts(frozen: LibraryFrozenBatch, now: Double = System.currentTimeMillis().toDouble()): Boolean {
        if (!accepts(frozen.batch, now) || frozen.changes.map { it.operation } != frozen.batch.operations) return false
        return frozen.changes.all { change ->
            val source = change.source
            val command = change.operation.command
            source !is LibraryLocalSource.Membership || source.value.updatedAt != null || command !is SyncCommand.MembershipPut || command.mode == "claim_if_unset"
        }
    }

    fun accepts(batch: SyncBatch, now: Double = System.currentTimeMillis().toDouble()): Boolean {
        fun identifier(value: String) = value.matches(Regex("^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$"))
        if (!identifier(batch.id) || batch.operations.isEmpty() || batch.operations.size > LibrarySyncLimits.operations ||
            batch.operations.map { it.id }.distinct().size != batch.operations.size || Json.encodeToString(batch).toByteArray(Charsets.UTF_8).size > LibrarySyncLimits.bytes) return false
        if (batch.operations.count { it.command is SyncCommand.FolderDelete || it.command is SyncCommand.FolderRestore } > LibrarySyncLimits.fanoutOperations) return false
        return batch.operations.all { identifier(it.id) && identifier(it.revision) && accepts(it.command, it.at, now) }
    }

    fun accepts(command: SyncCommand, at: Double, now: Double = System.currentTimeMillis().toDouble()): Boolean {
        fun time(value: Double) = value.isFinite() && value >= 0 && value <= now + 300_000
        fun target(value: String) = value.isNotEmpty() && value.length <= 128
        fun key(value: String) = value.matches(Regex("^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$"))
        fun note(value: String) = value.isNotEmpty() && value.toByteArray(Charsets.UTF_8).size <= LibrarySyncLimits.noteBytes
        fun folder(value: SyncFolderReference) = when (value) { SyncFolderReference.None -> true; is SyncFolderReference.Server -> target(value.id); is SyncFolderReference.Local -> key(value.key) }
        if (!time(at)) return false
        return when (command) {
            is SyncCommand.BookmarkAdd -> target(command.hadithId) && time(command.createdAt)
            is SyncCommand.FavoriteAdd -> target(command.hadithId) && time(command.createdAt)
            is SyncCommand.BookmarkRemove -> target(command.hadithId)
            is SyncCommand.FavoriteRemove -> target(command.hadithId)
            is SyncCommand.NotePut -> target(command.hadithId) && note(command.content) && time(command.createdAt) && time(command.updatedAt)
            is SyncCommand.NoteRemove -> target(command.hadithId)
            is SyncCommand.FolderCreate -> key(command.key) && GuestMergePlanner.isValidFolderName(command.name)
            is SyncCommand.FolderDelete -> command.folder != SyncFolderReference.None && folder(command.folder)
            is SyncCommand.MembershipPut -> target(command.hadithId) && folder(command.folder) &&
                (command.mode == null || command.mode == "claim_if_unset" && command.folder != SyncFolderReference.None)
            is SyncCommand.PositionPut -> time(command.position.updatedAt)
            is SyncCommand.LegacyPositionPut -> target(command.hadithId) && time(command.updatedAt)
            is SyncCommand.FacetRestore -> target(command.hadithId) && key(command.deletionId) && when (val value = command.value) {
                is SyncCommandFacetRestoreValue.Bookmark -> time(value.createdAt)
                is SyncCommandFacetRestoreValue.Favorite -> time(value.createdAt)
                is SyncCommandFacetRestoreValue.Note -> note(value.content) && time(value.createdAt) && time(value.updatedAt)
            }
            is SyncCommand.FolderRestore -> key(command.deletionId) && GuestMergePlanner.isValidFolderName(command.name) && command.hadithIds.size <= 500 && command.hadithIds.distinct().size == command.hadithIds.size && command.hadithIds.all(::target)
        }
    }
}

@Serializable
data class LibraryConfirmedChange(val change: LibraryLocalChange, val outcome: SyncOutcome, val version: Double)

val SyncCommand.isPositionChange: Boolean get() = this is SyncCommand.PositionPut || this is SyncCommand.LegacyPositionPut

val SyncOutstanding.committedValue: SyncCommitted? get() = when (this) { is SyncOutstanding.Committed -> committed; is SyncOutstanding.Pending -> null }
val SyncOutstanding.pendingValue: SyncPending? get() = when (this) { is SyncOutstanding.Pending -> pending; is SyncOutstanding.Committed -> null }
fun SyncPending.matches(other: SyncPending) = clientKey == other.clientKey && sequence == other.sequence && batchId == other.batchId && digest == other.digest && intentDigest == other.intentDigest && manifestId == other.manifestId && generation == other.generation

@Serializable
data class LibraryPartitionState(
    var pending: List<LibraryLocalChange> = emptyList(),
    var frozen: LibraryFrozenBatch? = null,
    var recovery: List<LibraryRecovery> = emptyList(),
    var recent: List<LibraryRecentReceipt> = emptyList(),
    val clientKey: String = UUID.randomUUID().toString(),
    var nextSequence: Double = 1.0,
    var acknowledgement: SyncAcknowledgement? = null,
    var waiting: SyncPending? = null,
    var confirmed: List<LibraryConfirmedChange> = emptyList(),
    var folderMappings: Map<String, String> = emptyMap(),
    var savedSnapshot: SyncSavedSnapshot? = null,
    var positionsSnapshot: SyncPositionsSnapshot? = null,
) {
    fun append(source: LibraryLocalSource, command: SyncCommand?, at: Double) {
        if (command == null || !LibrarySyncAdmission.accepts(command, at)) recovery = recovery + LibraryRecovery.Invalid(source)
        else pending = pending + LibraryLocalChange(command, at, source)
    }
    fun freeze(): SyncFrame? {
        if (acknowledgement != null || waiting != null) throw LibrarySyncFailure.InvalidReceipt
        frozen?.let {
            if (it.changes.map { change -> change.operation } != it.batch.operations) throw LibrarySyncFailure.InvalidReceipt
            return SyncFrame(clientKey, nextSequence, it.batch)
        }
        if (pending.isEmpty()) return null
        val id = UUID.randomUUID().toString()
        val selected = mutableListOf<LibraryLocalChange>()
        var inspected = 0
        while (pending.isNotEmpty() && inspected < LibrarySyncLimits.operations) {
            inspected++
            val change = pending.first()
            if (!LibrarySyncAdmission.accepts(change.operation.command, change.operation.at)) {
                recovery = recovery + LibraryRecovery.Rejected(change); pending = pending.drop(1); continue
            }
            val extra = when (change.operation.command) { is SyncCommand.FolderDelete, is SyncCommand.FolderRestore -> 1; else -> 0 }
            if (extra > 0 && selected.isNotEmpty()) break
            val candidate = SyncBatch(id, (selected + change).map { it.operation })
            if (Json.encodeToString(candidate).toByteArray(Charsets.UTF_8).size > LibrarySyncLimits.bytes) {
                if (selected.isEmpty()) { recovery = recovery + LibraryRecovery.Rejected(change); pending = pending.drop(1); continue }
                break
            }
            selected.add(change); pending = pending.drop(1)
            if (extra > 0) break
        }
        if (selected.isEmpty()) return null
        val batch = SyncBatch(id, selected.map { it.operation })
        frozen = LibraryFrozenBatch(batch, selected)
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
    fun pruneConfirmed() {
        confirmed = confirmed.filter { value ->
            val observed = if (value.change.operation.command.isPositionChange) positionsSnapshot?.version else savedSnapshot?.version
            (observed ?: -1.0) < value.version
        }
    }
    private fun checkCursor(cursor: SyncCursor) {
        if (!cursor.closedThrough.isFinite() || cursor.closedThrough < 0 || kotlin.math.floor(cursor.closedThrough) != cursor.closedThrough || cursor.closedThrough >= 9_007_199_254_740_991.0) throw LibrarySyncFailure.InvalidReceipt
        cursor.outstanding?.committedValue?.let {
            if (it.clientKey != clientKey || it.sequence != cursor.closedThrough + 1 || it.reply.batchId.isEmpty() || it.digest.isEmpty()) throw LibrarySyncFailure.InvalidReceipt
        }
        cursor.outstanding?.pendingValue?.let {
            if (it.clientKey != clientKey || it.sequence != cursor.closedThrough + 1 || !it.intentDigest.matches(Regex("^[a-f0-9]{64}$")) || listOf(it.batchId, it.digest, it.manifestId, it.generation).any { value -> value.isEmpty() || value.toByteArray(Charsets.UTF_8).size > 128 } || !it.retryAfterMs.isFinite() || it.retryAfterMs < 250 || it.retryAfterMs > 30_000) throw LibrarySyncFailure.InvalidReceipt
        }
    }
    private fun adopt(cursor: SyncCursor) {
        checkCursor(cursor)
        val pending = cursor.outstanding?.pendingValue
        val keepOriginal = pending != null && pending.sequence == nextSequence && pending.batchId == frozen?.batch?.id && pending.intentDigest == runCatching { frozen?.batch?.intentDigest() }.getOrNull()
        if (!keepOriginal) {
            frozen?.let { recovery = recovery + it.changes.map(LibraryRecovery::Historical) }
            frozen = null
        }
        nextSequence = cursor.closedThrough + 1
        waiting = pending
        acknowledgement = cursor.outstanding?.committedValue?.let { SyncAcknowledgement(clientKey, it.sequence, it.reply.batchId, it.digest) }
    }
    fun settle(exchange: SyncExchange, requested: SyncFrame, now: Double) {
        if (requested.clientKey != clientKey || requested.sequence != nextSequence || frozen?.batch != requested.batch || acknowledgement != null) throw LibrarySyncFailure.InvalidReceipt
        when (exchange) {
            is SyncExchange.Accepted -> {
                val committed = exchange.committed
                if (committed.clientKey != clientKey || committed.sequence != requested.sequence || committed.digest.isEmpty()) throw LibrarySyncFailure.InvalidReceipt
                val submitted = frozen?.changes.orEmpty()
                settleReceipts(committed.reply, now)
                for (change in submitted) {
                    val receipt = committed.reply.receipts.first { it.id == change.operation.id }
                    when (receipt.outcome) {
                        SyncOutcome.Preserved, is SyncOutcome.Folder, is SyncOutcome.FolderDeleted, is SyncOutcome.FolderRestored, is SyncOutcome.ResolvedPosition -> {
                            val version = if (change.operation.command.isPositionChange) committed.revision.position else committed.revision.saved
                            confirmed = confirmed + LibraryConfirmedChange(change, receipt.outcome, version)
                        }
                        is SyncOutcome.Superseded, is SyncOutcome.Unresolved -> Unit
                    }
                    val command = change.operation.command
                    val outcome = receipt.outcome
                    if (command is SyncCommand.FolderCreate && outcome is SyncOutcome.Folder) folderMappings = folderMappings + (command.key to outcome.folderId)
                    if (command is SyncCommand.FolderRestore && outcome is SyncOutcome.FolderRestored) folderMappings = folderMappings + ("restore:${command.deletionId}" to outcome.folderId)
                }
                pruneConfirmed()
                acknowledgement = SyncAcknowledgement(clientKey, committed.sequence, committed.reply.batchId, committed.digest)
                waiting = null
            }
            is SyncExchange.Pending -> {
                if (exchange.pending.clientKey != clientKey || exchange.pending.sequence != requested.sequence || exchange.pending.batchId != requested.batch.id) throw LibrarySyncFailure.InvalidReceipt
                if (waiting?.matches(exchange.pending) == false) throw LibrarySyncFailure.InvalidReceipt
                adopt(SyncCursor(requested.sequence - 1, SyncOutstanding.Pending(exchange.pending)))
            }
            is SyncExchange.Reconcile -> {
                if (exchange.clientKey != clientKey || exchange.requestedSequence != requested.sequence || exchange.requestedBatchId != requested.batch.id) throw LibrarySyncFailure.InvalidReceipt
                adopt(exchange.cursor)
            }
        }
    }
    fun settlePending(exchange: SyncExchange, requested: SyncPending, now: Double) {
        if (waiting != requested || acknowledgement != null) throw LibrarySyncFailure.InvalidReceipt
        when (exchange) {
            is SyncExchange.Pending -> {
                if (!requested.matches(exchange.pending)) throw LibrarySyncFailure.InvalidReceipt
                adopt(SyncCursor(requested.sequence - 1, SyncOutstanding.Pending(exchange.pending)))
            }
            is SyncExchange.Accepted -> {
                val proof = exchange.committed
                if (proof.clientKey != requested.clientKey || proof.sequence != requested.sequence || proof.reply.batchId != requested.batchId || proof.digest != requested.digest) throw LibrarySyncFailure.InvalidReceipt
                val original = frozen
                if (original != null && original.batch.id == requested.batchId && runCatching { original.batch.intentDigest() }.getOrNull() == requested.intentDigest) settle(exchange, SyncFrame(clientKey, requested.sequence, original.batch), now)
                else adopt(SyncCursor(requested.sequence - 1, SyncOutstanding.Committed(proof)))
            }
            is SyncExchange.Reconcile -> {
                if (exchange.clientKey != requested.clientKey || exchange.requestedSequence != requested.sequence || exchange.requestedBatchId != requested.batchId) throw LibrarySyncFailure.InvalidReceipt
                adopt(exchange.cursor)
            }
        }
    }

    fun pollRequest(): SyncPending? {
        val value = waiting ?: return null
        if (acknowledgement != null || value.sequence != nextSequence) throw LibrarySyncFailure.InvalidReceipt
        checkCursor(SyncCursor(nextSequence - 1, SyncOutstanding.Pending(value)))
        return value
    }
    fun settleRetirement(reply: SyncAckReply, requested: SyncFrame) {
        if (reply.clientKey != clientKey || requested.clientKey != clientKey || requested.sequence != nextSequence || frozen?.batch != requested.batch || acknowledgement != null) throw LibrarySyncFailure.InvalidReceipt
        adopt(reply.cursor)
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
    data object InvalidChange : LibrarySyncFailure()
    data object SessionChanged : LibrarySyncFailure()
    data object AccountDeleting : LibrarySyncFailure()
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
    suspend fun retireInvalid(capability: String, frame: SyncFrame): SyncAckReply = throw LibrarySyncFailure.InvalidChange
    suspend fun poll(capability: String, pending: SyncPending): SyncExchange = throw LibrarySyncFailure.InvalidChange
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
    var onPartitionChange: (LibrarySyncOwner) -> Unit = {}
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
        if (!LibrarySyncAdmission.accepts(change.operation.command, change.operation.at) || Json.encodeToString(SyncBatch("admission", listOf(change.operation))).toByteArray(Charsets.UTF_8).size > LibrarySyncLimits.bytes) throw LibrarySyncFailure.InvalidChange
        store.enqueueSyncChange(change, context.owner)
        onPartitionChange(context.owner)
        wake()
    }
    @androidx.annotation.MainThread
    fun capability(context: LibraryWriteContext): String {
        if (generation != context.generation || session != context.session || currentSession() != context.session || mutableOwner.value != context.owner || (binding?.validUntil ?: 0.0) <= now()) throw LibrarySyncFailure.SessionChanged
        return binding?.capability ?: throw LibrarySyncFailure.SessionChanged
    }
    suspend fun portableState(context: LibraryWriteContext): kotlinx.serialization.json.JsonElement = withContext(Dispatchers.Main.immediate) {
        capability(context)
        val state = store.syncPartition(context.owner) ?: throw LibrarySyncFailure.SessionChanged
        capability(context)
        Json.encodeToJsonElement(LibraryPartitionState.serializer(), state).withoutProviderPassages()
    }

    private fun checkSession(session: LibrarySyncSession, epoch: String) {
        if (generation != epoch || currentSession() != session) throw LibrarySyncFailure.SessionChanged
    }
    private suspend fun run(session: LibrarySyncSession, epoch: String) {
        try {
            checkSession(session, epoch)
            val deletion = store.deletionPhase(session.subject, transport.namespace)
            checkSession(session, epoch)
            if (deletion != null) throw LibrarySyncFailure.AccountDeleting
            if (binding == null || (binding?.validUntil ?: 0.0) <= now() + 1_000) {
                val opened = transport.open()
                checkSession(session, epoch)
                if (opened.subject != session.subject || !opened.validUntil.isFinite() || opened.validUntil <= now()) throw LibrarySyncFailure.OwnerMismatch
                binding = opened
                val owner = LibrarySyncOwner(opened.ownerKey, opened.subject, transport.namespace)
                store.claimGuestForSync(owner)
                checkSession(session, epoch)
                mutableOwner.value = owner
                onOwnerChange(owner)
            }
            val binding = binding ?: throw LibrarySyncFailure.OwnerMismatch
            val owner = mutableOwner.value ?: throw LibrarySyncFailure.OwnerMismatch
            repeat(8) {
                checkSession(session, epoch)
                store.claimGuestForSync(owner)
                onPartitionChange(owner)
                checkSession(session, epoch)
                val waiting = store.syncPartition(owner)?.pollRequest()
                checkSession(session, epoch)
                if (waiting != null) {
                    val reply = transport.poll(binding.capability, waiting)
                    store.settleSyncPending(reply, waiting, owner, now())
                    onPartitionChange(owner)
                    checkSession(session, epoch)
                    val pending = store.syncPartition(owner)?.pollRequest()
                    checkSession(session, epoch)
                    if (pending != null) { schedule(session, epoch, pending.retryAfterMs.toLong()); return }
                    return@repeat
                }
                val acknowledgement = store.syncPartition(owner)?.acknowledgement
                checkSession(session, epoch)
                if (acknowledgement != null) {
                    val reply = transport.acknowledge(binding.capability, acknowledgement)
                    store.settleSyncAcknowledgement(reply, acknowledgement, owner)
                    onPartitionChange(owner)
                    checkSession(session, epoch)
                    return@repeat
                }
                val frame = store.freezeSyncFrame(owner)
                if (frame == null) {
                    val state = store.syncPartition(owner)
                    onPartitionChange(owner)
                    checkSession(session, epoch)
                    if (state?.pending?.isNotEmpty() == true) return@repeat
                    mutableStatus.value = Status.Ready(state?.recovery?.size ?: 0)
                    retryDelay = 1_000
                    return
                }
                val frozen = store.syncPartition(owner)?.frozen ?: throw LibrarySyncFailure.SessionChanged
                checkSession(session, epoch)
                if (!LibrarySyncAdmission.accepts(frozen, now())) {
                    val reply = transport.retireInvalid(binding.capability, frame)
                    store.settleSyncRetirement(reply, frame, owner)
                    onPartitionChange(owner)
                    checkSession(session, epoch)
                    return@repeat
                }
                val reply = transport.send(binding.capability, frame)
                store.settleSyncExchange(reply, frame, owner, now())
                onPartitionChange(owner)
                checkSession(session, epoch)
                val pending = store.syncPartition(owner)?.pollRequest()
                checkSession(session, epoch)
                if (pending != null) { schedule(session, epoch, pending.retryAfterMs.toLong()); return }
            }
            schedule(session, epoch, 250)
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (_: LibrarySyncFailure.SessionChanged) { }
        catch (_: LibrarySyncFailure.AccountDeleting) {
            if (generation == epoch && currentSession() == session) mutableStatus.value = Status.Failed
        }
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


@Serializable
enum class LibraryDeletionPhase { SERVER_PENDING, IDENTITY_PENDING }
@Serializable
data class LibraryDeletionIntent(val subject: String, val namespace: String, val phase: LibraryDeletionPhase)

class LibraryAccountDeletion(
    private val store: GuestDataStore,
    private val namespace: String,
    private val currentSession: () -> LibrarySyncSession?,
    private val invalidate: () -> Unit,
    private val prepare: suspend () -> SyncDeletionAuthorization,
    private val erase: suspend (String) -> SyncDeletionResult,
    private val cleanup: (String) -> Unit,
    private val deleteIdentity: suspend (LibrarySyncSession) -> Unit,
) {
    suspend fun run(captured: LibrarySyncSession) = withContext(Dispatchers.Main.immediate) {
        if (currentSession() != captured) throw LibrarySyncFailure.SessionChanged
        invalidate()
        store.beginDeletion(captured.subject, namespace)
        if (store.deletionPhase(captured.subject, namespace) == LibraryDeletionPhase.SERVER_PENDING) {
            if (currentSession() != captured) throw LibrarySyncFailure.SessionChanged
            val grant = prepare()
            if (currentSession() != captured || grant.subject != captured.subject || !grant.validUntil.isFinite() || grant.validUntil <= System.currentTimeMillis()) throw LibrarySyncFailure.OwnerMismatch
            val result = erase(grant.authorization)
            if (result.subject != captured.subject) throw LibrarySyncFailure.OwnerMismatch
            store.markDeletionBackendComplete(captured.subject, namespace)
        }
        cleanup(captured.subject)
        if (currentSession() != captured) throw LibrarySyncFailure.SessionChanged
        deleteIdentity(captured)
        store.clearDeletion(captured.subject, namespace)
    }
}
