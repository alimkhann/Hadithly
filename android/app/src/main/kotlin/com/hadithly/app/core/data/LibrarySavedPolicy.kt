package com.hadithly.app.core.data

import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.encodeToJsonElement

@Serializable
sealed interface LibrarySavedContinuation {
    val token: String
    @Serializable data class Next(override val token: String) : LibrarySavedContinuation
    @Serializable data class Complete(override val token: String) : LibrarySavedContinuation
}
@Serializable
data class LibrarySavedReadPosition(val owner: LibrarySyncOwner, val version: Double, val assemblyID: String, val nextOrdinal: Long, val phase: Int, val continuation: LibrarySavedContinuation)
data class LibrarySavedPagePlan(val position: LibrarySavedReadPosition, val facts: List<SavedFact>, val input: String?, val start: Long, val fingerprint: String)
sealed interface LibrarySavedPageDecision {
    data class Append(val plan: LibrarySavedPagePlan) : LibrarySavedPageDecision
    data object Restart : LibrarySavedPageDecision
    data class Unavailable(val reason: SavedFactsReplyUnavailableReason) : LibrarySavedPageDecision
}
@Serializable
sealed interface LibrarySavedProjection {
    val firstOrdinal: Long
    @Serializable data class Item(val value: SavedPrivateItem, override val firstOrdinal: Long) : LibrarySavedProjection
    @Serializable data class Folder(val value: SyncFolderRow, override val firstOrdinal: Long) : LibrarySavedProjection
}
val SavedFact.ordinalValue: Double get() = when (this) { is SavedFact.Folder -> ordinal; is SavedFact.Item -> ordinal; is SavedFact.Bookmark -> ordinal; is SavedFact.Favorite -> ordinal; is SavedFact.Note -> ordinal }
val SavedFact.sourceID: String get() = when (this) { is SavedFact.Folder -> sourceId; is SavedFact.Item -> sourceId; is SavedFact.Bookmark -> sourceId; is SavedFact.Favorite -> sourceId; is SavedFact.Note -> sourceId }
val SavedFact.sourcePhase: Int get() = when (this) { is SavedFact.Folder -> 0; is SavedFact.Item -> 1; is SavedFact.Bookmark -> 2; is SavedFact.Favorite -> 3; is SavedFact.Note -> 4 }
val SavedFact.targetID: String get() = when (this) { is SavedFact.Folder -> value._id; is SavedFact.Item -> value.hadithId; is SavedFact.Bookmark -> hadithId; is SavedFact.Favorite -> hadithId; is SavedFact.Note -> hadithId }
@OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
private val savedPolicyJson = Json { encodeDefaults = true; explicitNulls = false }
fun SavedFact.savedFingerprint(): String = librarySemanticDigest(savedPolicyJson.encodeToJsonElement(this), "library-saved-fact-v1:")

/** Pure boundary/reducer kernel. Neither collection nor terminal receipt grants a production Saved barrier. */
object LibrarySavedPolicy {
    const val maxInteger = 9_007_199_254_740_991.0
    fun integer(value: Double): Long {
        if (!value.isFinite() || value < 0 || value > maxInteger || kotlin.math.floor(value) != value) throw LibrarySyncFailure.InvalidReceipt
        return value.toLong()
    }
    private fun text(value: String, limit: Int, empty: Boolean = false) {
        if ((!empty && value.isEmpty()) || value.toByteArray(Charsets.UTF_8).size > limit) throw LibrarySyncFailure.InvalidReceipt
    }
    private fun time(value: Double) { if (!value.isFinite() || value < 0) throw LibrarySyncFailure.InvalidReceipt }
    private inline fun <reified T> size(value: T) = savedPolicyJson.encodeToString(value).toByteArray(Charsets.UTF_8).size
    fun validate(item: SavedPrivateItem) {
        text(item.hadithId, 128); time(item.createdAt); time(item.updatedAt)
        listOfNotNull(item.bookmarkCreatedAt, item.favoriteCreatedAt, item.noteCreatedAt, item.noteUpdatedAt, item.folderUpdatedAt).forEach(::time)
        item.folderId?.let { text(it, 128) }
        if (size(item) > 128 * 1024) throw LibrarySyncFailure.InvalidReceipt
    }
    fun validate(fact: SavedFact) {
        integer(fact.ordinalValue); text(fact.sourceID, 128); text(fact.targetID, 128)
        if (size(fact) > LibrarySyncLimits.savedFactSourceBytes) throw LibrarySyncFailure.InvalidReceipt
        when (fact) {
            is SavedFact.Folder -> { text(fact.value.name, LibrarySyncLimits.savedFactSourceBytes, true); time(fact.value.createdAt) }
            is SavedFact.Item -> validate(fact.value)
            is SavedFact.Bookmark -> time(fact.createdAt)
            is SavedFact.Favorite -> time(fact.createdAt)
            is SavedFact.Note -> { time(fact.createdAt); time(fact.updatedAt) }
        }
    }
    private data class Envelope(val ownerKey: String, val version: Double, val root: String, val input: String?, val start: Double, val facts: List<SavedFact>, val continuation: LibrarySavedContinuation)
    fun inspect(reply: SavedFactsReply, owner: LibrarySyncOwner, previous: LibrarySavedReadPosition?, requested: String?): LibrarySavedPageDecision {
        if (size(reply) > LibrarySyncLimits.savedFactPageBytes) throw LibrarySyncFailure.InvalidReceipt
        requested?.let { text(it, LibrarySyncLimits.savedFactCursorBytes) }
        if (previous != null) {
            if (previous.owner != owner || previous.nextOrdinal < 0 || previous.phase !in -1..4 || previous.continuation !is LibrarySavedContinuation.Next || previous.continuation.token != requested) throw LibrarySyncFailure.InvalidReceipt
            integer(previous.version)
        } else if (requested != null) throw LibrarySyncFailure.InvalidReceipt
        val value = when (reply) {
            is SavedFactsReply.Restart -> { if (reply.reason != "saved_changed") throw LibrarySyncFailure.InvalidReceipt; return LibrarySavedPageDecision.Restart }
            is SavedFactsReply.Unavailable -> return LibrarySavedPageDecision.Unavailable(reply.reason)
            is SavedFactsReply.Page -> Envelope(reply.ownerKey, reply.version, reply.assemblyId, reply.input, reply.start, reply.facts, LibrarySavedContinuation.Next(reply.next))
            is SavedFactsReply.Complete -> {
                if (integer(reply.total) != integer(reply.start) + reply.facts.size) throw LibrarySyncFailure.InvalidReceipt
                Envelope(reply.ownerKey, reply.version, reply.assemblyId, reply.input, reply.start, reply.facts, LibrarySavedContinuation.Complete(reply.completion))
            }
        }
        integer(value.version); val ordinal = integer(value.start)
        text(value.root, LibrarySyncLimits.savedFactCursorBytes); text(value.continuation.token, LibrarySyncLimits.savedFactCursorBytes)
        if (value.ownerKey != owner.key || value.input != requested || ordinal != (previous?.nextOrdinal ?: 0L) || value.facts.size > LibrarySyncLimits.savedFactRows || (ordinal + value.facts.size).toDouble() > maxInteger) throw LibrarySyncFailure.InvalidReceipt
        if (previous != null && (value.version != previous.version || value.root != previous.assemblyID)) throw LibrarySyncFailure.InvalidReceipt
        if (value.continuation is LibrarySavedContinuation.Next && value.continuation.token == requested) throw LibrarySyncFailure.InvalidReceipt
        var phase = previous?.phase ?: -1
        value.facts.forEachIndexed { index, fact ->
            validate(fact)
            if (integer(fact.ordinalValue) != ordinal + index || fact.sourcePhase < phase) throw LibrarySyncFailure.InvalidReceipt
            phase = fact.sourcePhase
        }
        return LibrarySavedPageDecision.Append(LibrarySavedPagePlan(LibrarySavedReadPosition(owner, value.version, value.root, ordinal + value.facts.size, phase, value.continuation), value.facts, value.input, ordinal,
            librarySemanticDigest(savedPolicyJson.encodeToJsonElement(reply), "library-saved-page-v1:")))
    }
    fun confirm(reply: SavedFactsReply, position: LibrarySavedReadPosition) {
        val token = (position.continuation as? LibrarySavedContinuation.Complete)?.token ?: throw LibrarySyncFailure.InvalidReceipt
        if (reply !is SavedFactsReply.Complete || size(reply) > LibrarySyncLimits.savedFactPageBytes || reply.ownerKey != position.owner.key || reply.version != position.version || reply.assemblyId != position.assemblyID || reply.input != token || reply.completion != token || reply.start != position.nextOrdinal.toDouble() || reply.total != reply.start || reply.facts.isNotEmpty()) throw LibrarySyncFailure.InvalidReceipt
        integer(reply.version); integer(reply.start); text(token, LibrarySyncLimits.savedFactCursorBytes); text(reply.assemblyId, LibrarySyncLimits.savedFactCursorBytes)
    }
    fun fold(fact: SavedFact, previous: LibrarySavedProjection?): LibrarySavedProjection {
        validate(fact); val ordinal = integer(fact.ordinalValue); val first = previous?.firstOrdinal ?: ordinal
        if (first < 0 || first > ordinal) throw LibrarySyncFailure.InvalidReceipt
        if (fact is SavedFact.Folder) {
            if (previous != null && (previous !is LibrarySavedProjection.Folder || previous.value._id != fact.value._id)) throw LibrarySyncFailure.InvalidReceipt
            return LibrarySavedProjection.Folder(fact.value, first)
        }
        val prior = when (previous) {
            null -> null
            is LibrarySavedProjection.Item -> previous.value.also { if (it.hadithId != fact.targetID) throw LibrarySyncFailure.InvalidReceipt; validate(it) }
            is LibrarySavedProjection.Folder -> throw LibrarySyncFailure.InvalidReceipt
        }
        if (fact is SavedFact.Item) return LibrarySavedProjection.Item(fact.value, first)
        var bookmark = prior?.bookmarkCreatedAt; var favorite = prior?.favoriteCreatedAt
        var content = prior?.noteContent; var noteCreated = prior?.noteCreatedAt; var noteUpdated = prior?.noteUpdatedAt
        val created: Double; val updated: Double
        when (fact) {
            is SavedFact.Bookmark -> { bookmark = minOf(bookmark ?: fact.createdAt, fact.createdAt); created = minOf(prior?.createdAt ?: fact.createdAt, fact.createdAt); updated = prior?.updatedAt ?: fact.createdAt }
            is SavedFact.Favorite -> { favorite = minOf(favorite ?: fact.createdAt, fact.createdAt); created = minOf(prior?.createdAt ?: fact.createdAt, fact.createdAt); updated = prior?.updatedAt ?: fact.createdAt }
            is SavedFact.Note -> {
                if ((noteUpdated ?: Double.NEGATIVE_INFINITY) < fact.updatedAt) { content = fact.content; noteCreated = fact.createdAt; noteUpdated = fact.updatedAt }
                created = minOf(prior?.createdAt ?: fact.createdAt, fact.createdAt); updated = maxOf(prior?.updatedAt ?: fact.updatedAt, fact.updatedAt)
            }
            else -> throw LibrarySyncFailure.InvalidReceipt
        }
        val row = SavedPrivateItem(fact.targetID, created, updated, bookmark, favorite, content, noteCreated, noteUpdated, prior?.folderId, prior?.folderUpdatedAt)
        validate(row); return LibrarySavedProjection.Item(row, first)
    }
}

@Serializable
data class LibrarySavedLease(val owner: LibrarySyncOwner, val epoch: String, val generation: String) {
    fun validate() {
        if (listOf(owner.key, owner.subject, owner.namespace).any { it.isEmpty() || it.toByteArray().size > 1024 } || listOf(epoch, generation).any { it.isEmpty() || it.toByteArray().size > 128 }) throw LibrarySyncFailure.StoreUnavailable
    }
    val key: String get() = LibraryOutcomeBinding.hash(listOf(owner.namespace, owner.subject)) + ":" + LibraryOutcomeBinding.hash(listOf(owner.storageKey, owner.subject))
    val collection: String get() = key + ":" + LibraryOutcomeBinding.hash(listOf(epoch, generation))
    fun ordinalKey(ordinal: Long) = collection + ":f:" + ordinal.toString(16).padStart(16, '0')
    fun inputKey(input: String?) = collection + ":p:" + LibraryOutcomeBinding.hash(listOf(if (input == null) "absent" else "present", input ?: ""))
    fun sequenceKey(sequence: Long) = collection + ":s:" + sequence.toString(16).padStart(16, '0')
    fun sourceKey(fact: SavedFact) = collection + ":i:" + LibraryOutcomeBinding.hash(listOf(fact.sourcePhase.toString(), fact.sourceID))
    fun projectionKey(value: LibrarySavedProjection) = collection + ":r:" + LibraryOutcomeBinding.hash(listOf(value.kind, value.targetID))
}
@Serializable
data class LibrarySavedCounts(val items: Long = 0, val folders: Long = 0) {
    val total: Long get() = items + folders
    fun adding(value: LibrarySavedProjection) = if (value is LibrarySavedProjection.Item) copy(items = items + 1) else copy(folders = folders + 1)
}
@Serializable
sealed interface LibrarySavedStage {
    @Serializable data object Collecting : LibrarySavedStage
    @Serializable data class Folding(val next: Long, val phase: Int, val digest: String) : LibrarySavedStage
    @Serializable data class CheckingPages(val next: Long, val input: String?, val position: LibrarySavedReadPosition?) : LibrarySavedStage
    @Serializable data class Verifying(val after: String?, val seen: LibrarySavedCounts) : LibrarySavedStage
    @Serializable data object Prepared : LibrarySavedStage
    @Serializable data object Restart : LibrarySavedStage
    @Serializable data class Unavailable(val reason: SavedFactsReplyUnavailableReason) : LibrarySavedStage
}
@Serializable
data class LibrarySavedCheckpoint(val position: LibrarySavedReadPosition? = null, val pages: Long = 0,
    val digest: String = LibraryOutcomeBinding.hash(listOf("saved-raw-v1")), val counts: LibrarySavedCounts = LibrarySavedCounts(), val stage: LibrarySavedStage = LibrarySavedStage.Collecting) {
    val next: Long get() = position?.nextOrdinal ?: 0L
    fun validate(owner: LibrarySyncOwner) {
        if (pages < 0 || pages.toDouble() > LibrarySavedPolicy.maxInteger || counts.items < 0 || counts.folders < 0 || counts.items.toDouble() > LibrarySavedPolicy.maxInteger || counts.folders.toDouble() > LibrarySavedPolicy.maxInteger || counts.total > next || digest.length != 64) throw LibrarySyncFailure.StoreUnavailable
        position?.let {
            if (it.owner != owner || it.nextOrdinal < 0 || it.nextOrdinal.toDouble() > LibrarySavedPolicy.maxInteger || it.phase !in -1..4 || it.assemblyID.isEmpty() || it.assemblyID.toByteArray().size > LibrarySyncLimits.savedFactCursorBytes || it.continuation.token.isEmpty() || it.continuation.token.toByteArray().size > LibrarySyncLimits.savedFactCursorBytes) throw LibrarySyncFailure.StoreUnavailable
            LibrarySavedPolicy.integer(it.version)
        }
        when (val phase = stage) {
            LibrarySavedStage.Collecting -> if (position != null && position.continuation !is LibrarySavedContinuation.Next) throw LibrarySyncFailure.StoreUnavailable
            is LibrarySavedStage.Folding -> if (position?.continuation !is LibrarySavedContinuation.Complete || phase.next !in 0..next || phase.phase !in -1..4 || phase.digest.length != 64) throw LibrarySyncFailure.StoreUnavailable
            is LibrarySavedStage.CheckingPages -> if (position?.continuation !is LibrarySavedContinuation.Complete || phase.next !in 0..pages) throw LibrarySyncFailure.StoreUnavailable
            is LibrarySavedStage.Verifying -> if (position?.continuation !is LibrarySavedContinuation.Complete || phase.seen.items !in 0..counts.items || phase.seen.folders !in 0..counts.folders) throw LibrarySyncFailure.StoreUnavailable
            LibrarySavedStage.Prepared -> if (position?.continuation !is LibrarySavedContinuation.Complete) throw LibrarySyncFailure.StoreUnavailable
            LibrarySavedStage.Restart, is LibrarySavedStage.Unavailable -> Unit
        }
    }
}
@Serializable
sealed interface LibrarySavedReceiptResult {
    @Serializable data class Advanced(val position: LibrarySavedReadPosition) : LibrarySavedReceiptResult
    @Serializable data object Restart : LibrarySavedReceiptResult
    @Serializable data class Unavailable(val reason: SavedFactsReplyUnavailableReason) : LibrarySavedReceiptResult
}
@Serializable
data class LibrarySavedPageReceipt(val sequence: Long, val input: String?, val before: LibrarySavedReadPosition?, val start: Long, val count: Int, val fingerprint: String, val result: LibrarySavedReceiptResult) {
    fun validate(reply: SavedFactsReply, owner: LibrarySyncOwner, facts: List<SavedFact>) {
        val decision = LibrarySavedPolicy.inspect(reply, owner, before, input)
        if (fingerprint != librarySemanticDigest(savedPolicyJson.encodeToJsonElement(reply), "library-saved-page-v1:")) throw LibrarySyncFailure.InvalidReceipt
        when (decision) {
            is LibrarySavedPageDecision.Append -> if (result !is LibrarySavedReceiptResult.Advanced || decision.plan.position != result.position || decision.plan.start != start || decision.plan.facts != facts || facts.size != count) throw LibrarySyncFailure.InvalidReceipt
            LibrarySavedPageDecision.Restart -> if (result != LibrarySavedReceiptResult.Restart || facts.isNotEmpty() || count != 0) throw LibrarySyncFailure.InvalidReceipt
            is LibrarySavedPageDecision.Unavailable -> if (result !is LibrarySavedReceiptResult.Unavailable || result.reason != decision.reason || facts.isNotEmpty() || count != 0) throw LibrarySyncFailure.InvalidReceipt
        }
    }
}
@Serializable
data class LibrarySavedGenerationRecord(val lease: LibrarySavedLease, val checkpoint: LibrarySavedCheckpoint) {
    fun validate(scope: LibrarySavedLease, prepared: Boolean) {
        lease.validate(); checkpoint.validate(lease.owner)
        if (lease.owner != scope.owner || lease.epoch != scope.epoch || (prepared && checkpoint.stage != LibrarySavedStage.Prepared)) throw LibrarySyncFailure.StoreUnavailable
    }
}
@Serializable
sealed interface LibrarySavedExportRecord {
    @Serializable data class Fact(val value: SavedFact) : LibrarySavedExportRecord
    @Serializable data class Page(val value: LibrarySavedPageReceipt) : LibrarySavedExportRecord
    @Serializable data class Projection(val value: LibrarySavedProjection) : LibrarySavedExportRecord
}
data class LibrarySavedRawPage(val lease: LibrarySavedLease, val checkpoint: LibrarySavedCheckpoint, val facts: List<SavedFact>, val next: Long)
data class LibrarySavedProjectionPage(val rows: List<LibrarySavedProjection>, val next: String?, val done: Boolean)
val LibrarySavedProjection.kind: String get() = if (this is LibrarySavedProjection.Item) "item" else "folder"
val LibrarySavedProjection.targetID: String get() = when (this) { is LibrarySavedProjection.Item -> value.hadithId; is LibrarySavedProjection.Folder -> value._id }
fun LibrarySavedProjection.savedFingerprint(): String {
    val payload = when (this) {
        is LibrarySavedProjection.Item -> librarySemanticDigest(savedPolicyJson.encodeToJsonElement(value), "saved-private-value-v1:")
        is LibrarySavedProjection.Folder -> librarySemanticDigest(savedPolicyJson.encodeToJsonElement(value), "saved-private-value-v1:")
    }
    return LibraryOutcomeBinding.hash(listOf(kind, firstOrdinal.toString(), payload))
}
fun LibrarySavedProjection.validateProjection() {
    LibrarySavedPolicy.integer(firstOrdinal.toDouble())
    when (this) {
        is LibrarySavedProjection.Item -> LibrarySavedPolicy.validate(value)
        is LibrarySavedProjection.Folder -> if (value._id.isEmpty() || value._id.toByteArray().size > 128 || value.name.toByteArray().size > LibrarySyncLimits.savedFactSourceBytes || !value.createdAt.isFinite() || value.createdAt < 0) throw LibrarySyncFailure.InvalidReceipt
    }
}

fun LibrarySavedPageReceipt.reply(facts: List<SavedFact>, owner: LibrarySyncOwner): SavedFactsReply = when (val value = result) {
    is LibrarySavedReceiptResult.Advanced -> when (val next = value.position.continuation) {
        is LibrarySavedContinuation.Next -> SavedFactsReply.Page(owner.key, value.position.version, value.position.assemblyID, input, start.toDouble(), facts, next.token)
        is LibrarySavedContinuation.Complete -> SavedFactsReply.Complete(owner.key, value.position.version, value.position.assemblyID, input, start.toDouble(), facts, value.position.nextOrdinal.toDouble(), next.token)
    }
    LibrarySavedReceiptResult.Restart -> SavedFactsReply.Restart("saved_changed")
    is LibrarySavedReceiptResult.Unavailable -> SavedFactsReply.Unavailable(value.reason)
}
data class LibrarySavedExportPage(val records: List<LibrarySavedExportRecord>, val next: Long, val done: Boolean)
fun LibrarySavedGenerationRecord.exportMetadata(active: Boolean = false): Map<String, kotlinx.serialization.json.JsonElement> {
    fun number(value: Long) = kotlinx.serialization.json.JsonPrimitive(value)
    val phase = when (checkpoint.stage) { LibrarySavedStage.Collecting -> "collecting"; is LibrarySavedStage.Folding -> "folding"; is LibrarySavedStage.CheckingPages -> "checking_pages"; is LibrarySavedStage.Verifying -> "verifying"; LibrarySavedStage.Prepared -> "prepared"; LibrarySavedStage.Restart -> "restart"; is LibrarySavedStage.Unavailable -> "unavailable" }
    return mapOf("formatVersion" to number(1), "ownerKey" to kotlinx.serialization.json.JsonPrimitive(lease.owner.key), "subject" to kotlinx.serialization.json.JsonPrimitive(lease.owner.subject), "namespace" to kotlinx.serialization.json.JsonPrimitive(lease.owner.namespace),
        "generation" to kotlinx.serialization.json.JsonPrimitive(lease.generation), "status" to kotlinx.serialization.json.JsonPrimitive(phase), "active" to kotlinx.serialization.json.JsonPrimitive(active), "collectedFacts" to number(checkpoint.next), "pageCount" to number(checkpoint.pages),
        "projectedItems" to number(checkpoint.counts.items), "projectedFolders" to number(checkpoint.counts.folders), "privateVersion" to (checkpoint.position?.let { kotlinx.serialization.json.JsonPrimitive(it.version) } ?: kotlinx.serialization.json.JsonNull))
}
fun LibrarySavedExportRecord.exportValue(): kotlinx.serialization.json.JsonElement = when (this) {
    is LibrarySavedExportRecord.Fact -> kotlinx.serialization.json.buildJsonObject { put("kind", kotlinx.serialization.json.JsonPrimitive("fact")); put("value", savedPolicyJson.encodeToJsonElement(value)) }
    is LibrarySavedExportRecord.Projection -> kotlinx.serialization.json.buildJsonObject {
        put("kind", kotlinx.serialization.json.JsonPrimitive(value.kind)); put("firstOrdinal", kotlinx.serialization.json.JsonPrimitive(value.firstOrdinal))
        put("value", when (val row = value) { is LibrarySavedProjection.Item -> savedPolicyJson.encodeToJsonElement(row.value); is LibrarySavedProjection.Folder -> savedPolicyJson.encodeToJsonElement(row.value) })
    }
    is LibrarySavedExportRecord.Page -> kotlinx.serialization.json.buildJsonObject {
        put("kind", kotlinx.serialization.json.JsonPrimitive("page")); put("sequence", kotlinx.serialization.json.JsonPrimitive(value.sequence)); put("start", kotlinx.serialization.json.JsonPrimitive(value.start)); put("count", kotlinx.serialization.json.JsonPrimitive(value.count))
        put("fingerprint", kotlinx.serialization.json.JsonPrimitive(value.fingerprint)); put("inputFingerprint", kotlinx.serialization.json.JsonPrimitive(LibraryOutcomeBinding.hash(listOf(if (value.input == null) "absent" else "present", value.input ?: ""))))
        when (val result = value.result) {
            is LibrarySavedReceiptResult.Advanced -> { put("status", kotlinx.serialization.json.JsonPrimitive("advanced")); put("outputFingerprint", kotlinx.serialization.json.JsonPrimitive(LibraryOutcomeBinding.hash(listOf(result.position.continuation.token)))) }
            LibrarySavedReceiptResult.Restart -> put("status", kotlinx.serialization.json.JsonPrimitive("restart"))
            is LibrarySavedReceiptResult.Unavailable -> put("status", kotlinx.serialization.json.JsonPrimitive(result.reason.name.lowercase()))
        }
    }
}

class LibrarySavedReadContext internal constructor(internal val write: LibraryWriteContext, internal val capability: String, val validUntil: Double) {
    val owner: LibrarySyncOwner get() = write.owner
}
data class LibrarySavedInvalidation(val version: Double)
data class LibrarySavedReferenceValue(val hadithID: String, val providerHadithID: String, val collectionSlug: String, val collectionName: String, val volumeID: String?, val referenceDisplay: String)
@ConsistentCopyVisibility
data class LibrarySavedCompleteText internal constructor(val reference: HadithRef)
sealed interface LibrarySavedReferenceState {
    data class Available(val reference: LibrarySavedReferenceValue) : LibrarySavedReferenceState
    data object Missing : LibrarySavedReferenceState
    data object Unavailable : LibrarySavedReferenceState
}
sealed interface LibrarySavedTextState {
    data class Available(val text: LibrarySavedCompleteText) : LibrarySavedTextState
    data object Missing : LibrarySavedTextState
    data object Unavailable : LibrarySavedTextState
}
object LibrarySavedReadPolicy {
    fun target(value: String) { if (value.isEmpty() || value.toByteArray().size > 128) throw LibrarySyncFailure.InvalidReceipt }
    private inline fun <reified T> size(value: T, limit: Int) { if (savedPolicyJson.encodeToString(value).toByteArray().size > limit) throw LibrarySyncFailure.InvalidReceipt }
    fun invalidation(value: SavedReadHead, owner: LibrarySyncOwner): LibrarySavedInvalidation {
        if (value.ownerKey != owner.key) throw LibrarySyncFailure.OwnerMismatch
        LibrarySavedPolicy.integer(value.version); return LibrarySavedInvalidation(value.version)
    }
    private fun identity(ownerKey: String, hadithID: String, owner: LibrarySyncOwner, target: String) {
        this.target(target)
        if (ownerKey != owner.key) throw LibrarySyncFailure.OwnerMismatch
        if (hadithID != target) throw LibrarySyncFailure.InvalidReceipt
    }
    private fun referenceValue(value: SavedHadithReference, target: String): LibrarySavedReferenceValue {
        if (value._id != target || value.collectionSlug.isEmpty() || value.providerHadithId.isEmpty()) throw LibrarySyncFailure.InvalidReceipt
        return LibrarySavedReferenceValue(target, value.providerHadithId, value.collectionSlug, value.collectionName, value.volumeId, value.referenceDisplay)
    }
    fun reference(reply: SavedReferenceReply, owner: LibrarySyncOwner, target: String): LibrarySavedReferenceState {
        size(reply, LibrarySyncLimits.savedReferenceBytes)
        return when (reply) {
            is SavedReferenceReply.Available -> { identity(reply.ownerKey, reply.hadithId, owner, target); LibrarySavedReferenceState.Available(referenceValue(reply.reference, target)) }
            is SavedReferenceReply.Missing -> { identity(reply.ownerKey, reply.hadithId, owner, target); LibrarySavedReferenceState.Missing }
            is SavedReferenceReply.Unavailable -> {
                identity(reply.ownerKey, reply.hadithId, owner, target)
                if (reply.reason != "reference_too_large") throw LibrarySyncFailure.InvalidReceipt
                LibrarySavedReferenceState.Unavailable
            }
        }
    }
    fun text(reply: SavedTextReply, owner: LibrarySyncOwner, target: String): LibrarySavedTextState {
        size(reply, LibrarySyncLimits.savedTextBytes)
        return when (reply) {
            is SavedTextReply.Available -> {
                identity(reply.ownerKey, reply.hadithId, owner, target); val row = reply.hadith
                val metadata = referenceValue(SavedHadithReference(row._id, row.providerHadithId, row.collectionSlug, row.collectionName, row.volumeId, row.referenceDisplay), target)
                LibrarySavedTextState.Available(LibrarySavedCompleteText(HadithRef(metadata.hadithID, metadata.collectionSlug, metadata.collectionName, metadata.volumeID, metadata.providerHadithID, row.arabicText, row.englishText, metadata.referenceDisplay)))
            }
            is SavedTextReply.Missing -> { identity(reply.ownerKey, reply.hadithId, owner, target); LibrarySavedTextState.Missing }
            is SavedTextReply.Unavailable -> {
                identity(reply.ownerKey, reply.hadithId, owner, target)
                if (reply.reason != "text_too_large") throw LibrarySyncFailure.InvalidReceipt
                LibrarySavedTextState.Unavailable
            }
        }
    }
}
