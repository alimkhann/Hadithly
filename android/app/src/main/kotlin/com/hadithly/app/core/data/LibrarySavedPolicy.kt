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
