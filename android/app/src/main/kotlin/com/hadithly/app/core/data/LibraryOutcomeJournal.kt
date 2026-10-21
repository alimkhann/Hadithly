package com.hadithly.app.core.data

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.security.MessageDigest
import java.io.File
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.encodeToJsonElement

@Serializable
data class LibraryOutcomeCounts(val deleted: Long = 0, val restored: Long = 0, val superseded: Long = 0, val missing: Long = 0) {
    val valid: Boolean get() = listOf(deleted, restored, superseded, missing).all { it >= 0 && it < 9_007_199_254_740_991L }
    val total: Long get() = deleted + restored + superseded + missing
    fun fits(other: LibraryOutcomeCounts) = deleted <= other.deleted && restored <= other.restored && superseded <= other.superseded && missing <= other.missing
    fun adding(rows: List<SyncOutcomeMember>) = copy(
        deleted = deleted + rows.count { it.disposition == SyncOutcomeMemberDisposition.DELETED },
        restored = restored + rows.count { it.disposition == SyncOutcomeMemberDisposition.RESTORED },
        superseded = superseded + rows.count { it.disposition == SyncOutcomeMemberDisposition.SUPERSEDED },
        missing = missing + rows.count { it.disposition == SyncOutcomeMemberDisposition.MISSING },
    )
}
@Serializable
sealed interface LibraryOutcomeStatus {
    @Serializable data object Collecting : LibraryOutcomeStatus
    @Serializable data class Verifying(val counts: LibraryOutcomeCounts) : LibraryOutcomeStatus
    @Serializable data object Complete : LibraryOutcomeStatus
    @Serializable data class Unavailable(val reason: SyncOutcomePageUnavailableReason) : LibraryOutcomeStatus
}
@Serializable
data class LibraryOutcomeRetention(val acknowledgedAt: Double, val removed: Long? = null) {
    fun valid(total: Long) = acknowledgedAt.isFinite() && acknowledgedAt >= 0 && (removed == null || removed in 0..total)
    companion object { const val duration: Double = 30 * 24 * 60 * 60 * 1_000.0 }
}
@Serializable
data class LibraryOutcomeCheckpoint(val counts: LibraryOutcomeCounts = LibraryOutcomeCounts(), val status: LibraryOutcomeStatus = LibraryOutcomeStatus.Collecting, val retention: LibraryOutcomeRetention? = null) {
    val next: Long get() = counts.total
}
@Serializable
data class LibraryOutcomeAuthority(val owner: LibrarySyncOwner, val committed: SyncCommitted)

val SyncCommitted.needsOutcomeCollection: Boolean get() = reply.receipts.any { it.outcome is SyncOutcome.FolderDeletedManifest || it.outcome is SyncOutcome.FolderRestoredManifest }

class LibraryManifestProof(committed: SyncCommitted) {
    val request: SyncOutcomePageRequest
    val expected: LibraryOutcomeCounts
    val receipt: SyncReceipt
    init {
        fun identifier(value: String) = value.isNotEmpty() && value.toByteArray(Charsets.UTF_8).size <= 128
        fun count(value: Double): Long {
            if (!value.isFinite() || value < 0 || kotlin.math.floor(value) != value || value >= 9_007_199_254_740_991.0) throw LibrarySyncFailure.InvalidReceipt
            return value.toLong()
        }
        if (!listOf(committed.clientKey, committed.digest, committed.reply.batchId).all(::identifier) ||
            count(committed.sequence) < 1 || count(committed.revision.saved) < 0 || committed.reply.receipts.size != 1) throw LibrarySyncFailure.InvalidReceipt
        receipt = committed.reply.receipts.single()
        if (!listOf(receipt.id, receipt.revision).all(::identifier)) throw LibrarySyncFailure.InvalidReceipt
        val manifest: String; val generation: String; val phase: SyncOutcomePageRequestPhase
        when (val outcome = receipt.outcome) {
            is SyncOutcome.FolderDeletedManifest -> {
                if (!outcome.deletedAt.isFinite() || outcome.deletedAt < 0) throw LibrarySyncFailure.InvalidReceipt
                manifest = outcome.manifestId; generation = outcome.generation; phase = SyncOutcomePageRequestPhase.DELETE
                expected = LibraryOutcomeCounts(deleted = count(outcome.count))
            }
            is SyncOutcome.FolderRestoredManifest -> {
                if (!identifier(outcome.folderId)) throw LibrarySyncFailure.InvalidReceipt
                manifest = outcome.manifestId; generation = outcome.generation; phase = SyncOutcomePageRequestPhase.RESTORE
                expected = LibraryOutcomeCounts(restored = count(outcome.restored), superseded = count(outcome.superseded), missing = count(outcome.missing))
            }
            else -> throw LibrarySyncFailure.InvalidReceipt
        }
        if (!identifier(manifest) || !identifier(generation) || expected.total >= 9_007_199_254_740_991L) throw LibrarySyncFailure.InvalidReceipt
        request = SyncOutcomePageRequest(SyncAcknowledgement(committed.clientKey, committed.sequence, committed.reply.batchId, committed.digest), receipt.id, manifest, generation, phase, 0.0)
    }
}
@Serializable
sealed interface LibraryOutcomeOrigin {
    @Serializable data class Matched(val intentDigest: String) : LibraryOutcomeOrigin
    @Serializable data object Historical : LibraryOutcomeOrigin
}
@Serializable
data class LibraryPendingOutcome(val committed: SyncCommitted, val origin: LibraryOutcomeOrigin)

class LibraryOutcomeBinding(val owner: LibrarySyncOwner, val committed: SyncCommitted) {
    val request: SyncOutcomePageRequest
    val expected: LibraryOutcomeCounts
    val key: String
    val scopeKey: String get() = hash(listOf(owner.namespace, owner.subject, owner.key))
    val authority: LibraryOutcomeAuthority get() = LibraryOutcomeAuthority(owner, committed)
    init {
        if (committed.reply.ownerKey != owner.key) throw LibrarySyncFailure.OwnerMismatch
        if (listOf(owner.key, owner.subject, owner.namespace).any { it.isEmpty() }) throw LibrarySyncFailure.InvalidReceipt
        val proof = LibraryManifestProof(committed)
        request = proof.request; expected = proof.expected
        key = hash(listOf(owner.namespace, owner.subject, owner.key, committed.clientKey, committed.sequence.toLong().toString(), committed.reply.batchId,
            committed.digest, proof.receipt.id, proof.receipt.revision, request.manifestId, request.generation, request.phase.name.lowercase()))
    }
    fun pageRequest(start: Long) = request.copy(start = start.toDouble())
    fun validate(page: SyncOutcomePage, requested: SyncOutcomePageRequest): List<SyncOutcomeMember> {
        if (!requested.start.isFinite() || requested.start < 0 || kotlin.math.floor(requested.start) != requested.start || requested.start > expected.total.toDouble() ||
            requested != pageRequest(requested.start.toLong()) || Json.encodeToString(page).toByteArray(Charsets.UTF_8).size > LibrarySyncLimits.outcomeBytes) throw LibrarySyncFailure.InvalidReceipt
        when (page) {
            is SyncOutcomePage.Unavailable -> {
                if (page.ownerKey != owner.key || page.request != requested) throw LibrarySyncFailure.InvalidReceipt
                return emptyList()
            }
            is SyncOutcomePage.Page -> {
                if (page.ownerKey != owner.key || page.request != requested || page.rows.size.toLong() != minOf(LibrarySyncLimits.outcomePage.toLong(), expected.total - requested.start.toLong()) ||
                    page.next != requested.start + page.rows.size || page.done != (page.next == expected.total.toDouble()) ||
                    page.rows.map { it.memberId }.toSet().size != page.rows.size || page.rows.map { it.hadithId }.toSet().size != page.rows.size) throw LibrarySyncFailure.InvalidReceipt
                page.rows.forEachIndexed { index, row ->
                    if (row.ordinal != requested.start + index || listOf(row.memberId, row.hadithId).any { it.isEmpty() || it.toByteArray(Charsets.UTF_8).size > 128 } ||
                        (request.phase == SyncOutcomePageRequestPhase.DELETE) != (row.disposition == SyncOutcomeMemberDisposition.DELETED)) throw LibrarySyncFailure.InvalidReceipt
                }
                return page.rows
            }
        }
    }
    companion object {
        fun hash(values: List<String>): String = MessageDigest.getInstance("SHA-256").digest(values.joinToString("") { "${it.toByteArray(Charsets.UTF_8).size}:$it" }.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it.toInt() and 255) }
    }
}
@Serializable
data class LibraryOutcomeEvidencePage(val authority: LibraryOutcomeAuthority, val checkpoint: LibraryOutcomeCheckpoint, val rows: List<SyncOutcomeMember>, val next: Long, val endOfCollectedPrefix: Boolean)

sealed interface LibraryOutcomeExportVersion {
    data object Empty : LibraryOutcomeExportVersion
    data class Present(val epoch: String, val revision: Long) : LibraryOutcomeExportVersion
}
data class LibraryOutcomeExportFence(val owner: LibrarySyncOwner, val version: LibraryOutcomeExportVersion)
data class LibraryOutcomeExportEntry(val binding: LibraryOutcomeBinding, val checkpoint: LibraryOutcomeCheckpoint)
data class LibraryExportArtifact(val id: String, val directory: File)

/** Owns page identity, row transactions and erase fences. Never writes ACK intent. */
private val savedJournalJson = Json { encodeDefaults = true; explicitNulls = false }

internal class LibraryOutcomeJournal(context: Context) : SQLiteOpenHelper(context, File(context.filesDir, "library_outcomes.db").absolutePath, null, 3) {
    override fun onConfigure(db: SQLiteDatabase) { db.setForeignKeyConstraintsEnabled(true) }
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE scopes (scope_key TEXT PRIMARY KEY NOT NULL, subject TEXT NOT NULL, namespace TEXT NOT NULL, owner_key TEXT NOT NULL, generation TEXT NOT NULL)")
        db.execSQL("CREATE INDEX scopes_owner ON scopes(subject,namespace,owner_key)")
        db.execSQL("CREATE TABLE headers (collection_key TEXT PRIMARY KEY NOT NULL, owner_key TEXT NOT NULL, subject TEXT NOT NULL, namespace TEXT NOT NULL, generation TEXT NOT NULL, authority TEXT NOT NULL, checkpoint TEXT NOT NULL)")
        db.execSQL("CREATE INDEX headers_owner ON headers(subject,namespace,owner_key,collection_key)")
        db.execSQL("CREATE TABLE members (collection_key TEXT NOT NULL REFERENCES headers(collection_key) ON DELETE CASCADE, ordinal INTEGER NOT NULL, member_id TEXT NOT NULL, hadith_id TEXT NOT NULL, disposition TEXT NOT NULL, row_data TEXT NOT NULL, PRIMARY KEY(collection_key,ordinal), UNIQUE(collection_key,member_id), UNIQUE(collection_key,hadith_id))")
        db.execSQL("CREATE INDEX members_category ON members(collection_key,disposition)")
        createExportSchema(db, ready = true)
        createSavedSchema(db)
    }
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion !in 1..2 || newVersion != 3) throw LibrarySyncFailure.StoreUnavailable
        if (oldVersion == 1) createExportSchema(db, ready = false)
        createSavedSchema(db)
    }
    private fun createSavedSchema(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE saved_assemblies (scope_key TEXT PRIMARY KEY NOT NULL, subject TEXT NOT NULL, namespace TEXT NOT NULL, owner_key TEXT NOT NULL, lease TEXT NOT NULL, checkpoint TEXT NOT NULL, erasing INTEGER NOT NULL)")
        db.execSQL("CREATE TABLE saved_facts (row_key TEXT NOT NULL UNIQUE, collection_key TEXT NOT NULL, ordinal INTEGER NOT NULL, source_key TEXT NOT NULL UNIQUE, subject TEXT NOT NULL, namespace TEXT NOT NULL, owner_key TEXT NOT NULL, fingerprint TEXT NOT NULL, data TEXT NOT NULL, PRIMARY KEY(collection_key,ordinal))")
        db.execSQL("CREATE TABLE saved_pages (collection_key TEXT NOT NULL, input_key TEXT NOT NULL UNIQUE, sequence INTEGER NOT NULL, subject TEXT NOT NULL, namespace TEXT NOT NULL, owner_key TEXT NOT NULL, data TEXT NOT NULL, PRIMARY KEY(collection_key,sequence))")
        db.execSQL("CREATE TABLE saved_projection (row_key TEXT PRIMARY KEY NOT NULL, collection_key TEXT NOT NULL, subject TEXT NOT NULL, namespace TEXT NOT NULL, owner_key TEXT NOT NULL, fingerprint TEXT NOT NULL, data TEXT NOT NULL)")
        db.execSQL("CREATE INDEX saved_projection_collection ON saved_projection(collection_key,row_key)")
        for (table in listOf("saved_assemblies", "saved_facts", "saved_pages", "saved_projection")) db.execSQL("CREATE INDEX ${table}_owner ON $table(subject,namespace,owner_key)")
    }
    private fun createExportSchema(db: SQLiteDatabase, ready: Boolean) {
        db.execSQL("CREATE TABLE export_clocks (scope_key TEXT PRIMARY KEY NOT NULL, subject TEXT NOT NULL, namespace TEXT NOT NULL, epoch TEXT NOT NULL, revision INTEGER NOT NULL, erasing INTEGER NOT NULL)")
        db.execSQL("CREATE TABLE export_migration (id INTEGER PRIMARY KEY CHECK(id=1), phase TEXT NOT NULL, cursor TEXT NOT NULL)")
        db.execSQL("INSERT INTO export_migration(id,phase,cursor) VALUES(1,?,?)", arrayOf(if (ready) "ready" else "scan", ""))
        db.execSQL("CREATE INDEX headers_export ON headers(subject,namespace,collection_key)")
        db.execSQL("CREATE TABLE export_artifacts (artifact_id TEXT PRIMARY KEY NOT NULL, subject TEXT NOT NULL, namespace TEXT NOT NULL)")
        db.execSQL("CREATE INDEX artifacts_owner ON export_artifacts(subject,namespace,artifact_id)")
    }
    private data class Clock(val epoch: String, val revision: Long, val erasing: Boolean)
    private fun clock(db: SQLiteDatabase, subject: String, namespace: String): Clock? =
        db.rawQuery("SELECT subject,namespace,epoch,revision,erasing FROM export_clocks WHERE scope_key=?", arrayOf(LibraryOutcomeBinding.hash(listOf(namespace, subject)))).use {
            if (!it.moveToFirst()) null else {
                if (it.getString(0) != subject || it.getString(1) != namespace || it.getString(2).isEmpty() || it.getLong(3) < 0 || it.getLong(3) >= 9_007_199_254_740_991L) throw LibrarySyncFailure.StoreUnavailable
                Clock(it.getString(2), it.getLong(3), it.getInt(4) != 0)
            }
        }
    private fun bumpClock(db: SQLiteDatabase, subject: String, namespace: String, erasing: Boolean = false) {
        val key = LibraryOutcomeBinding.hash(listOf(namespace, subject)); val old = clock(db, subject, namespace)
        if (old?.erasing == true && !erasing) throw LibrarySyncFailure.AccountDeleting
        if ((old?.revision ?: 0) >= 9_007_199_254_740_990L) throw LibrarySyncFailure.StoreUnavailable
        val values = ContentValues().apply {
            put("scope_key", key); put("subject", subject); put("namespace", namespace); put("epoch", old?.epoch ?: UUID.randomUUID().toString())
            put("revision", (old?.revision ?: 0) + 1); put("erasing", if (erasing || old?.erasing == true) 1 else 0)
        }
        if (old == null) db.insertOrThrow("export_clocks", null, values)
        else db.update("export_clocks", values, "scope_key=?", arrayOf(key))
    }
    fun beginErase(subject: String, namespace: String, full: Boolean) = transaction { db -> bumpClock(db, subject, namespace, erasing = full) }
    fun prepareExportStep(blockedScopes: Set<String>): Boolean = transaction { db ->
        val phase: String; val after: String
        db.rawQuery("SELECT phase,cursor FROM export_migration WHERE id=1", null).use {
            if (!it.moveToFirst()) throw LibrarySyncFailure.StoreUnavailable
            phase = it.getString(0); after = it.getString(1)
        }
        if (phase == "ready") return@transaction true
        if (phase != "scan" && phase != "check") throw LibrarySyncFailure.StoreUnavailable
        var last: String? = null
        db.rawQuery("SELECT collection_key,authority FROM headers WHERE collection_key>? ORDER BY collection_key LIMIT 50", arrayOf(after)).use { cursor ->
            while (cursor.moveToNext()) {
                last = cursor.getString(0)
                val value = Json.decodeFromString<LibraryOutcomeAuthority>(cursor.getString(1)); val binding = LibraryOutcomeBinding(value.owner, value.committed)
                if (last != binding.key) throw LibrarySyncFailure.StoreUnavailable
                header(db, binding) ?: throw LibrarySyncFailure.StoreUnavailable
                val key = LibraryOutcomeBinding.hash(listOf(binding.owner.namespace, binding.owner.subject))
                if (key !in blockedScopes && clock(db, binding.owner.subject, binding.owner.namespace) == null) bumpClock(db, binding.owner.subject, binding.owner.namespace)
            }
        }
        val nextPhase = if (last != null) phase else if (phase == "scan") "check" else "ready"
        db.update("export_migration", ContentValues().apply { put("phase", nextPhase); put("cursor", last ?: "") }, "id=1", null)
        nextPhase == "ready"
    }
    private fun checkFence(db: SQLiteDatabase, fence: LibraryOutcomeExportFence) {
        val current = clock(db, fence.owner.subject, fence.owner.namespace)
        when (val expected = fence.version) {
            LibraryOutcomeExportVersion.Empty -> if (current != null || hasSavedRows(db, fence.owner.subject, fence.owner.namespace)) throw LibrarySyncFailure.StoreUnavailable
            is LibraryOutcomeExportVersion.Present -> if (current == null || current.erasing || current.epoch != expected.epoch || current.revision != expected.revision) throw LibrarySyncFailure.StoreUnavailable
        }
    }
    fun captureExportFence(owner: LibrarySyncOwner): LibraryOutcomeExportFence = transaction { db ->
        db.rawQuery("SELECT phase FROM export_migration WHERE id=1", null).use { if (!it.moveToFirst() || it.getString(0) != "ready") throw LibrarySyncFailure.StoreUnavailable }
        val value = clock(db, owner.subject, owner.namespace)
        val version = if (value == null) {
            db.rawQuery("SELECT collection_key FROM headers WHERE subject=? AND namespace=? LIMIT 1", arrayOf(owner.subject, owner.namespace)).use { if (it.moveToFirst()) throw LibrarySyncFailure.StoreUnavailable }
            if (hasSavedRows(db, owner.subject, owner.namespace)) throw LibrarySyncFailure.StoreUnavailable
            LibraryOutcomeExportVersion.Empty
        } else {
            if (value.erasing) throw LibrarySyncFailure.AccountDeleting
            LibraryOutcomeExportVersion.Present(value.epoch, value.revision)
        }
        LibraryOutcomeExportFence(owner, version)
    }
    fun validateExport(fence: LibraryOutcomeExportFence) = transaction { db -> checkFence(db, fence) }
    fun exportEntries(fence: LibraryOutcomeExportFence, after: String?): List<LibraryOutcomeExportEntry> = transaction { db ->
        checkFence(db, fence)
        val values = mutableListOf<LibraryOutcomeExportEntry>()
        db.rawQuery("SELECT collection_key,authority FROM headers WHERE subject=? AND namespace=? AND collection_key>? ORDER BY collection_key LIMIT 50", arrayOf(fence.owner.subject, fence.owner.namespace, after ?: "")).use {
            while (it.moveToNext()) {
                val authority = Json.decodeFromString<LibraryOutcomeAuthority>(it.getString(1)); val binding = LibraryOutcomeBinding(authority.owner, authority.committed)
                if (binding.key != it.getString(0) || binding.owner.subject != fence.owner.subject || binding.owner.namespace != fence.owner.namespace) throw LibrarySyncFailure.OwnerMismatch
                values.add(LibraryOutcomeExportEntry(binding, header(db, binding) ?: throw LibrarySyncFailure.StoreUnavailable))
            }
        }
        checkFence(db, fence)
        values
    }
    fun exportPage(fence: LibraryOutcomeExportFence, entry: LibraryOutcomeExportEntry, start: Long): LibraryOutcomeEvidencePage = transaction { db ->
        checkFence(db, fence)
        if (entry.binding.owner.subject != fence.owner.subject || entry.binding.owner.namespace != fence.owner.namespace) throw LibrarySyncFailure.OwnerMismatch
        val checkpoint = header(db, entry.binding) ?: throw LibrarySyncFailure.StoreUnavailable
        if (checkpoint.retention?.removed != null || checkpoint != entry.checkpoint || start < 0 || start > checkpoint.next) throw LibrarySyncFailure.StoreUnavailable
        val rows = rows(db, entry.binding, start, checkpoint.next); val next = start + rows.size
        checkFence(db, fence)
        LibraryOutcomeEvidencePage(entry.binding.authority, checkpoint, rows, next, next == checkpoint.next)
    }
    fun registerArtifact(fence: LibraryOutcomeExportFence): String = transaction { db ->
        checkFence(db, fence)
        UUID.randomUUID().toString().also { id -> db.insertOrThrow("export_artifacts", null, ContentValues().apply { put("artifact_id", id); put("subject", fence.owner.subject); put("namespace", fence.owner.namespace) }) }
    }
    fun artifactIds(subject: String? = null, namespace: String? = null): List<String> = transaction { db ->
        val query = if (subject == null) "SELECT artifact_id FROM export_artifacts ORDER BY artifact_id LIMIT 50" else "SELECT artifact_id FROM export_artifacts WHERE subject=? AND namespace=? ORDER BY artifact_id LIMIT 50"
        val args = if (subject == null) null else arrayOf(subject, namespace ?: throw LibrarySyncFailure.InvalidReceipt)
        val result = mutableListOf<String>()
        db.rawQuery(query, args).use { while (it.moveToNext()) result.add(it.getString(0)) }
        result
    }
    fun validateArtifact(id: String, owner: LibrarySyncOwner) = transaction { db ->
        db.rawQuery("SELECT subject,namespace FROM export_artifacts WHERE artifact_id=?", arrayOf(id)).use {
            if (!it.moveToFirst() || it.getString(0) != owner.subject || it.getString(1) != owner.namespace) throw LibrarySyncFailure.SessionChanged
        }
    }
    fun <T> sealExport(fence: LibraryOutcomeExportFence, artifactID: String, publish: () -> T): T = transaction { db ->
        checkFence(db, fence)
        db.rawQuery("SELECT subject,namespace FROM export_artifacts WHERE artifact_id=?", arrayOf(artifactID)).use {
            if (!it.moveToFirst() || it.getString(0) != fence.owner.subject || it.getString(1) != fence.owner.namespace) throw LibrarySyncFailure.SessionChanged
        }
        val value = publish()
        checkFence(db, fence)
        value
    }
    fun discardArtifact(id: String) = transaction { db -> db.delete("export_artifacts", "artifact_id=?", arrayOf(id)); Unit }
    private fun <T> transaction(block: (SQLiteDatabase) -> T): T {
        val db = writableDatabase
        db.beginTransaction()
        try { val result = block(db); db.setTransactionSuccessful(); return result }
        finally { db.endTransaction() }
    }
    private fun generation(db: SQLiteDatabase, key: String): String? = db.rawQuery("SELECT generation FROM scopes WHERE scope_key=?", arrayOf(key)).use { if (it.moveToFirst()) it.getString(0) else null }
    fun captureGeneration(binding: LibraryOutcomeBinding): String = transaction { db ->
        generation(db, binding.scopeKey) ?: UUID.randomUUID().toString().also { value ->
            db.insertOrThrow("scopes", null, ContentValues().apply {
                put("scope_key", binding.scopeKey); put("generation", value); put("subject", binding.owner.subject)
                put("namespace", binding.owner.namespace); put("owner_key", binding.owner.storageKey)
            })
            bumpClock(db, binding.owner.subject, binding.owner.namespace)
        }
    }
    private fun header(db: SQLiteDatabase, binding: LibraryOutcomeBinding, expectedGeneration: String? = null): LibraryOutcomeCheckpoint? =
        db.rawQuery("SELECT owner_key,subject,namespace,generation,authority,checkpoint FROM headers WHERE collection_key=?", arrayOf(binding.key)).use { cursor ->
            if (!cursor.moveToFirst()) null else {
                val authority = Json.decodeFromString<LibraryOutcomeAuthority>(cursor.getString(4))
                // Reconstructing also validates persisted authority instead of trusting its JSON shape.
                val parsed = LibraryOutcomeBinding(authority.owner, authority.committed)
                if (cursor.getString(0) != binding.owner.storageKey || cursor.getString(1) != binding.owner.subject || cursor.getString(2) != binding.owner.namespace || parsed.authority != binding.authority) throw LibrarySyncFailure.OwnerMismatch
                if (expectedGeneration != null && cursor.getString(3) != expectedGeneration) throw LibrarySyncFailure.SessionChanged
                Json.decodeFromString<LibraryOutcomeCheckpoint>(cursor.getString(5)).also {
                    if (!it.counts.valid || !it.counts.fits(binding.expected) || it.status == LibraryOutcomeStatus.Complete && it.counts != binding.expected) throw LibrarySyncFailure.StoreUnavailable
                    if (it.retention != null && (!it.retention.valid(it.next) || it.status != LibraryOutcomeStatus.Complete || binding.expected.superseded != 0L || binding.expected.missing != 0L)) throw LibrarySyncFailure.StoreUnavailable
                    val status = it.status
                    if (status is LibraryOutcomeStatus.Verifying && (!status.counts.valid || !status.counts.fits(it.counts) || it.counts != binding.expected)) throw LibrarySyncFailure.StoreUnavailable
                }
            }
        }
    fun open(binding: LibraryOutcomeBinding, expectedGeneration: String): LibraryOutcomeCheckpoint = transaction { db ->
        if (generation(db, binding.scopeKey) != expectedGeneration) throw LibrarySyncFailure.SessionChanged
        val stored = header(db, binding, expectedGeneration)
        if (stored != null) {
            if (stored.retention?.removed != null) throw LibrarySyncFailure.StoreUnavailable
            verifyStep(db, binding, stored)
        }
        else LibraryOutcomeCheckpoint().also { checkpoint ->
            db.insertOrThrow("headers", null, ContentValues().apply {
                put("collection_key", binding.key); put("owner_key", binding.owner.storageKey); put("subject", binding.owner.subject); put("namespace", binding.owner.namespace)
                put("generation", expectedGeneration); put("authority", Json.encodeToString(binding.authority)); put("checkpoint", Json.encodeToString(checkpoint))
            })
            bumpClock(db, binding.owner.subject, binding.owner.namespace)
        }
    }
    private fun rows(db: SQLiteDatabase, binding: LibraryOutcomeBinding, start: Long, limit: Long): List<SyncOutcomeMember> {
        val result = mutableListOf<SyncOutcomeMember>()
        db.rawQuery("SELECT ordinal,member_id,hadith_id,disposition,row_data FROM members WHERE collection_key=? AND ordinal>=? ORDER BY ordinal LIMIT ?", arrayOf(binding.key, start.toString(), LibrarySyncLimits.outcomePage.toString())).use { cursor ->
            while (cursor.moveToNext()) {
                val row = Json.decodeFromString<SyncOutcomeMember>(cursor.getString(4))
                if (row.ordinal != (start + result.size).toDouble() || row.ordinal != cursor.getLong(0).toDouble() || row.memberId != cursor.getString(1) ||
                    row.hadithId != cursor.getString(2) || row.disposition.name != cursor.getString(3)) throw LibrarySyncFailure.StoreUnavailable
                result.add(row)
            }
        }
        if (result.size.toLong() != minOf(LibrarySyncLimits.outcomePage.toLong(), limit - start)) throw LibrarySyncFailure.StoreUnavailable
        return result
    }
    private fun verifyStep(db: SQLiteDatabase, binding: LibraryOutcomeBinding, checkpoint: LibraryOutcomeCheckpoint): LibraryOutcomeCheckpoint {
        val status = checkpoint.status
        if (status !is LibraryOutcomeStatus.Verifying) return checkpoint
        if (!status.counts.valid || !status.counts.fits(checkpoint.counts) || checkpoint.counts != binding.expected) throw LibrarySyncFailure.StoreUnavailable
        val verified = status.counts.adding(rows(db, binding, status.counts.total, checkpoint.next))
        if (!verified.fits(binding.expected)) throw LibrarySyncFailure.StoreUnavailable
        val nextStatus = if (verified.total == checkpoint.next) {
            if (verified != binding.expected) throw LibrarySyncFailure.StoreUnavailable
            LibraryOutcomeStatus.Complete
        } else LibraryOutcomeStatus.Verifying(verified)
        val next = checkpoint.copy(status = nextStatus)
        db.update("headers", ContentValues().apply { put("checkpoint", Json.encodeToString(next)) }, "collection_key=?", arrayOf(binding.key))
        bumpClock(db, binding.owner.subject, binding.owner.namespace)
        return next
    }
    fun persist(binding: LibraryOutcomeBinding, expectedGeneration: String, requested: SyncOutcomePageRequest, page: SyncOutcomePage): LibraryOutcomeCheckpoint {
        val rows = binding.validate(page, requested)
        return transaction { db ->
            if (generation(db, binding.scopeKey) != expectedGeneration) throw LibrarySyncFailure.SessionChanged
            val checkpoint = header(db, binding, expectedGeneration) ?: throw LibrarySyncFailure.SessionChanged
            if (requested.start > checkpoint.next.toDouble()) throw LibrarySyncFailure.InvalidReceipt
            if (checkpoint.status is LibraryOutcomeStatus.Unavailable) {
                if (page !is SyncOutcomePage.Unavailable || page.reason != checkpoint.status.reason || requested.start != checkpoint.next.toDouble()) throw LibrarySyncFailure.InvalidReceipt
                return@transaction checkpoint
            }
            if (page is SyncOutcomePage.Unavailable && (requested.start != checkpoint.next.toDouble() || checkpoint.status != LibraryOutcomeStatus.Collecting)) throw LibrarySyncFailure.InvalidReceipt
            if (requested.start < checkpoint.next || checkpoint.status != LibraryOutcomeStatus.Collecting) {
                rows.forEach { row ->
                    val same = db.rawQuery("SELECT row_data FROM members WHERE collection_key=? AND ordinal=?", arrayOf(binding.key, row.ordinal.toLong().toString())).use {
                        it.moveToFirst() && Json.decodeFromString<SyncOutcomeMember>(it.getString(0)) == row
                    }
                    if (!same) throw LibrarySyncFailure.InvalidReceipt
                }
                if (page is SyncOutcomePage.Page && page.next > checkpoint.next) throw LibrarySyncFailure.InvalidReceipt
                checkpoint
            } else {
                if (checkpoint.status != LibraryOutcomeStatus.Collecting) throw LibrarySyncFailure.InvalidReceipt
                rows.forEach { row ->
                    // INSERT never replaces conflicting evidence. The transaction rolls back all earlier rows.
                    db.insertOrThrow("members", null, ContentValues().apply {
                        put("collection_key", binding.key); put("ordinal", row.ordinal.toLong()); put("member_id", row.memberId); put("hadith_id", row.hadithId)
                        put("disposition", row.disposition.name); put("row_data", Json.encodeToString(row))
                    })
                }
                val next = when (page) {
                    is SyncOutcomePage.Unavailable -> checkpoint.copy(status = LibraryOutcomeStatus.Unavailable(page.reason))
                    is SyncOutcomePage.Page -> {
                        val counts = checkpoint.counts.adding(rows)
                        if (!counts.fits(binding.expected) || page.done && counts != binding.expected) throw LibrarySyncFailure.InvalidReceipt
                        LibraryOutcomeCheckpoint(counts, if (page.done) LibraryOutcomeStatus.Verifying(LibraryOutcomeCounts()) else LibraryOutcomeStatus.Collecting)
                    }
                }
                db.update("headers", ContentValues().apply { put("checkpoint", Json.encodeToString(next)) }, "collection_key=?", arrayOf(binding.key))
                bumpClock(db, binding.owner.subject, binding.owner.namespace)
                next
            }
        }
    }
    fun acknowledge(binding: LibraryOutcomeBinding, now: Double) = transaction { db ->
        val current = generation(db, binding.scopeKey) ?: throw LibrarySyncFailure.StoreUnavailable
        val checkpoint = header(db, binding, current) ?: throw LibrarySyncFailure.StoreUnavailable
        if (!now.isFinite() || now < 0 || checkpoint.status != LibraryOutcomeStatus.Complete || binding.expected.superseded != 0L || binding.expected.missing != 0L || checkpoint.retention?.removed != null) throw LibrarySyncFailure.InvalidReceipt
        if (checkpoint.retention == null) {
            db.update("headers", ContentValues().apply { put("checkpoint", Json.encodeToString(checkpoint.copy(retention = LibraryOutcomeRetention(now)))) }, "collection_key=?", arrayOf(binding.key))
            bumpClock(db, binding.owner.subject, binding.owner.namespace)
        }
    }
    fun retentionEntries(owner: LibrarySyncOwner, after: String?): List<LibraryOutcomeExportEntry> = transaction { db ->
        val entries = mutableListOf<LibraryOutcomeExportEntry>()
        db.rawQuery("SELECT collection_key,authority FROM headers WHERE subject=? AND namespace=? AND collection_key>? ORDER BY collection_key LIMIT 50", arrayOf(owner.subject, owner.namespace, after ?: "")).use {
            while (it.moveToNext()) {
                val authority = Json.decodeFromString<LibraryOutcomeAuthority>(it.getString(1)); val binding = LibraryOutcomeBinding(authority.owner, authority.committed)
                if (binding.key != it.getString(0) || binding.owner.subject != owner.subject || binding.owner.namespace != owner.namespace) throw LibrarySyncFailure.OwnerMismatch
                entries.add(LibraryOutcomeExportEntry(binding, header(db, binding) ?: throw LibrarySyncFailure.StoreUnavailable))
            }
        }
        entries
    }
    fun prune(binding: LibraryOutcomeBinding, expected: LibraryOutcomeCheckpoint): Boolean = transaction { db ->
        val current = generation(db, binding.scopeKey) ?: throw LibrarySyncFailure.StoreUnavailable
        val checkpoint = header(db, binding, current) ?: throw LibrarySyncFailure.StoreUnavailable
        if (checkpoint != expected || checkpoint.status != LibraryOutcomeStatus.Complete) throw LibrarySyncFailure.StoreUnavailable
        val retention = checkpoint.retention ?: throw LibrarySyncFailure.StoreUnavailable
        val start = retention.removed ?: 0
        val members = rows(db, binding, start, checkpoint.next)
        members.forEach { row ->
            if (db.delete("members", "collection_key=? AND ordinal=?", arrayOf(binding.key, row.ordinal.toLong().toString())) != 1) throw LibrarySyncFailure.StoreUnavailable
        }
        val next = start + members.size
        val done = next == checkpoint.next
        if (done) {
            db.rawQuery("SELECT ordinal FROM members WHERE collection_key=? LIMIT 1", arrayOf(binding.key)).use { if (it.moveToFirst()) throw LibrarySyncFailure.StoreUnavailable }
            db.delete("headers", "collection_key=?", arrayOf(binding.key))
            val otherHeader = db.rawQuery("SELECT collection_key FROM headers WHERE owner_key=? AND subject=? AND namespace=? LIMIT 1", arrayOf(binding.owner.storageKey, binding.owner.subject, binding.owner.namespace)).use { it.moveToFirst() }
            if (!otherHeader) db.delete("scopes", "scope_key=?", arrayOf(binding.scopeKey))
        }
        else db.update("headers", ContentValues().apply { put("checkpoint", Json.encodeToString(checkpoint.copy(retention = retention.copy(removed = next)))) }, "collection_key=?", arrayOf(binding.key))
        bumpClock(db, binding.owner.subject, binding.owner.namespace)
        done
    }

    fun settlementCheckpoint(binding: LibraryOutcomeBinding): LibraryOutcomeCheckpoint = transaction { db ->
        val current = generation(db, binding.scopeKey) ?: throw LibrarySyncFailure.StoreUnavailable
        header(db, binding, current) ?: throw LibrarySyncFailure.StoreUnavailable
    }

    fun evidence(binding: LibraryOutcomeBinding, start: Long): LibraryOutcomeEvidencePage = transaction { db ->
        val checkpoint = header(db, binding) ?: throw LibrarySyncFailure.StoreUnavailable
        if (checkpoint.retention?.removed != null) throw LibrarySyncFailure.StoreUnavailable
        if (start < 0 || start > checkpoint.next) throw LibrarySyncFailure.InvalidReceipt
        val rows = rows(db, binding, start, checkpoint.next)
        val next = start + rows.size
        LibraryOutcomeEvidencePage(binding.authority, checkpoint, rows, next, next == checkpoint.next)
    }
    fun erase(subject: String, namespace: String, ownerKey: String? = null) {
        beginErase(subject, namespace, full = ownerKey == null)
        val selection = if (ownerKey == null) "subject=? AND namespace=?" else "subject=? AND namespace=? AND owner_key=?"
        val joined = if (ownerKey == null) "h.subject=? AND h.namespace=?" else "h.subject=? AND h.namespace=? AND h.owner_key=?"
        val args = if (ownerKey == null) arrayOf(subject, namespace) else arrayOf(subject, namespace, ownerKey)
        var after = ""
        while (true) {
            val keys = transaction { db ->
                val values = mutableListOf<String>()
                db.rawQuery("SELECT scope_key FROM scopes WHERE $selection AND scope_key>? ORDER BY scope_key LIMIT 50", args + after).use { while (it.moveToNext()) values.add(it.getString(0)) }
                values.forEach { key -> db.update("scopes", ContentValues().apply { put("generation", UUID.randomUUID().toString()) }, "scope_key=?", arrayOf(key)) }
                if (values.isNotEmpty()) bumpClock(db, subject, namespace, erasing = ownerKey == null)
                values
            }
            if (keys.isEmpty()) break
            after = keys.last()
        }
        while (transaction { db ->
            val deleted = db.delete("members", "rowid IN (SELECT m.rowid FROM members m JOIN headers h ON h.collection_key=m.collection_key WHERE $joined ORDER BY m.collection_key,m.ordinal LIMIT 50)", args)
            if (deleted > 0) bumpClock(db, subject, namespace, erasing = ownerKey == null)
            deleted
        } > 0) { }
        for ((table, key) in listOf("headers" to "collection_key", "scopes" to "scope_key")) {
            while (transaction { db ->
                val deleted = db.delete(table, "$key IN (SELECT $key FROM $table WHERE $selection LIMIT 50)", args)
                if (deleted > 0) bumpClock(db, subject, namespace, erasing = ownerKey == null)
                deleted
            } > 0) { }
        }
        transaction { db ->
            val remaining = db.rawQuery("SELECT 1 FROM headers WHERE subject=? AND namespace=? UNION ALL SELECT 1 FROM scopes WHERE subject=? AND namespace=? LIMIT 1", arrayOf(subject, namespace, subject, namespace)).use { it.moveToFirst() }
            val artifacts = db.rawQuery("SELECT 1 FROM export_artifacts WHERE subject=? AND namespace=? LIMIT 1", arrayOf(subject, namespace)).use { it.moveToFirst() }
            if (!remaining && !artifacts && !hasSavedRows(db, subject, namespace)) db.delete("export_clocks", "scope_key=?", arrayOf(LibraryOutcomeBinding.hash(listOf(namespace, subject))))
            else if (ownerKey == null) throw LibrarySyncFailure.StoreUnavailable
        }
    }
    companion object { const val savedStepLimit = 8 }
    private fun savedCheckClock(db: SQLiteDatabase, owner: LibrarySyncOwner) { if (clock(db, owner.subject, owner.namespace)?.erasing == true) throw LibrarySyncFailure.AccountDeleting }
    private fun savedHeader(db: SQLiteDatabase, lease: LibrarySavedLease): LibrarySavedCheckpoint {
        lease.validate()
        return db.rawQuery("SELECT subject,namespace,owner_key,lease,checkpoint,erasing FROM saved_assemblies WHERE scope_key=?", arrayOf(lease.key)).use {
            if (!it.moveToFirst() || it.getInt(5) != 0 || it.getString(0) != lease.owner.subject || it.getString(1) != lease.owner.namespace || it.getString(2) != lease.owner.storageKey || it.getString(3).toByteArray().size > 16_384 || it.getString(4).toByteArray().size > 256 * 1024 || Json.decodeFromString<LibrarySavedLease>(it.getString(3)) != lease) throw LibrarySyncFailure.SessionChanged
            Json.decodeFromString<LibrarySavedCheckpoint>(it.getString(4)).also { value -> value.validate(lease.owner) }
        }
    }
    private fun savedSave(db: SQLiteDatabase, lease: LibrarySavedLease, checkpoint: LibrarySavedCheckpoint) {
        checkpoint.validate(lease.owner); val data = Json.encodeToString(checkpoint)
        if (data.toByteArray().size > 256 * 1024) throw LibrarySyncFailure.StoreUnavailable
        if (db.update("saved_assemblies", ContentValues().apply { put("checkpoint", data) }, "scope_key=?", arrayOf(lease.key)) != 1) throw LibrarySyncFailure.SessionChanged
        bumpClock(db, lease.owner.subject, lease.owner.namespace)
    }
    fun beginSaved(owner: LibrarySyncOwner): LibrarySavedLease = transaction { db ->
        savedCheckClock(db, owner)
        val candidate = LibrarySavedLease(owner, UUID.randomUUID().toString(), UUID.randomUUID().toString()); candidate.validate()
        val existing = db.rawQuery("SELECT lease FROM saved_assemblies WHERE scope_key=?", arrayOf(candidate.key)).use { if (it.moveToFirst()) { if (it.getString(0).toByteArray().size > 16_384) throw LibrarySyncFailure.StoreUnavailable; Json.decodeFromString<LibrarySavedLease>(it.getString(0)) } else null }
        if (existing != null) { if (existing.owner != owner) throw LibrarySyncFailure.OwnerMismatch; savedHeader(db, existing); existing }
        else {
            for (table in listOf("saved_facts", "saved_pages", "saved_projection")) db.rawQuery("SELECT 1 FROM $table WHERE subject=? AND namespace=? AND owner_key=? LIMIT 1", arrayOf(owner.subject, owner.namespace, owner.storageKey)).use { if (it.moveToFirst()) throw LibrarySyncFailure.StoreUnavailable }
            db.insertOrThrow("saved_assemblies", null, ContentValues().apply {
                put("scope_key", candidate.key); put("subject", owner.subject); put("namespace", owner.namespace); put("owner_key", owner.storageKey)
                put("lease", Json.encodeToString(candidate)); put("checkpoint", Json.encodeToString(LibrarySavedCheckpoint())); put("erasing", 0)
            }); bumpClock(db, owner.subject, owner.namespace); candidate
        }
    }
    fun savedCheckpoint(lease: LibrarySavedLease): LibrarySavedCheckpoint = transaction { db -> savedCheckClock(db, lease.owner); savedHeader(db, lease) }
    private fun savedFacts(db: SQLiteDatabase, lease: LibrarySavedLease, start: Long, end: Long): List<SavedFact> {
        if (start < 0 || start > end) throw LibrarySyncFailure.InvalidReceipt
        val values = mutableListOf<SavedFact>()
        db.rawQuery("SELECT ordinal,source_key,subject,namespace,owner_key,fingerprint,data FROM saved_facts WHERE collection_key=? AND ordinal>=? AND ordinal<? ORDER BY ordinal LIMIT 8", arrayOf(lease.collection, start.toString(), end.toString())).use {
            while (it.moveToNext()) {
                if (it.getString(6).toByteArray().size > LibrarySyncLimits.savedFactPageBytes) throw LibrarySyncFailure.StoreUnavailable
                val fact = Json.decodeFromString<SavedFact>(it.getString(6)); LibrarySavedPolicy.validate(fact)
                if (it.getLong(0) != start + values.size || fact.ordinalValue != (start + values.size).toDouble() || it.getString(1) != lease.sourceKey(fact) || it.getString(2) != lease.owner.subject || it.getString(3) != lease.owner.namespace || it.getString(4) != lease.owner.storageKey || it.getString(5) != fact.savedFingerprint()) throw LibrarySyncFailure.StoreUnavailable
                values.add(fact)
            }
        }
        if (values.size.toLong() != minOf(savedStepLimit.toLong(), end - start)) throw LibrarySyncFailure.StoreUnavailable
        return values
    }
    private fun savedNoExtraFacts(db: SQLiteDatabase, lease: LibrarySavedLease, end: Long) {
        db.rawQuery("SELECT 1 FROM saved_facts WHERE collection_key=? AND ordinal>=? LIMIT 1", arrayOf(lease.collection, end.toString())).use { if (it.moveToFirst()) throw LibrarySyncFailure.StoreUnavailable }
    }
    fun savedRawPage(lease: LibrarySavedLease, start: Long): LibrarySavedRawPage = transaction { db ->
        savedCheckClock(db, lease.owner); val checkpoint = savedHeader(db, lease)
        val rows = savedFacts(db, lease, start, checkpoint.next)
        if (start + rows.size == checkpoint.next) savedNoExtraFacts(db, lease, checkpoint.next)
        LibrarySavedRawPage(lease, checkpoint, rows, start + rows.size)
    }
    private fun savedReceipt(db: SQLiteDatabase, lease: LibrarySavedLease, input: String?): LibrarySavedPageReceipt? =
        db.rawQuery("SELECT sequence,subject,namespace,owner_key,data FROM saved_pages WHERE collection_key=? AND input_key=?", arrayOf(lease.collection, lease.inputKey(input))).use {
            if (!it.moveToFirst()) null else {
                if (it.getString(4).toByteArray().size > 256 * 1024) throw LibrarySyncFailure.StoreUnavailable
                val receipt = Json.decodeFromString<LibrarySavedPageReceipt>(it.getString(4))
                LibrarySavedPolicy.integer(receipt.sequence.toDouble()); LibrarySavedPolicy.integer(receipt.start.toDouble())
                if (receipt.start.toDouble() > LibrarySavedPolicy.maxInteger - receipt.count) throw LibrarySyncFailure.StoreUnavailable
                if (receipt.input != input || receipt.sequence < 0 || receipt.sequence != it.getLong(0) || it.getString(1) != lease.owner.subject || it.getString(2) != lease.owner.namespace || it.getString(3) != lease.owner.storageKey || receipt.start < 0 || receipt.count !in 0..LibrarySyncLimits.savedFactRows) throw LibrarySyncFailure.StoreUnavailable
                receipt
            }
        }
    fun persistSaved(lease: LibrarySavedLease, requested: String?, reply: SavedFactsReply): LibrarySavedCheckpoint = transaction { db ->
        savedCheckClock(db, lease.owner); val checkpoint = savedHeader(db, lease)
        val replay = savedReceipt(db, lease, requested)
        if (replay != null) {
            if (replay.sequence >= checkpoint.pages || replay.start + replay.count > checkpoint.next) throw LibrarySyncFailure.StoreUnavailable
            replay.validate(reply, lease.owner, savedFacts(db, lease, replay.start, replay.start + replay.count)); return@transaction checkpoint
        }
        if (checkpoint.stage != LibrarySavedStage.Collecting) throw LibrarySyncFailure.InvalidReceipt
        val decision = LibrarySavedPolicy.inspect(reply, lease.owner, checkpoint.position, requested)
        var next = checkpoint; val result: LibrarySavedReceiptResult; val count: Int
        when (decision) {
            LibrarySavedPageDecision.Restart -> { next = next.copy(stage = LibrarySavedStage.Restart); result = LibrarySavedReceiptResult.Restart; count = 0 }
            is LibrarySavedPageDecision.Unavailable -> { next = next.copy(stage = LibrarySavedStage.Unavailable(decision.reason)); result = LibrarySavedReceiptResult.Unavailable(decision.reason); count = 0 }
            is LibrarySavedPageDecision.Append -> {
                val plan = decision.plan
                if (plan.position.continuation is LibrarySavedContinuation.Next && savedReceipt(db, lease, plan.position.continuation.token) != null) throw LibrarySyncFailure.InvalidReceipt
                for (fact in plan.facts) {
                    db.rawQuery("SELECT 1 FROM saved_facts WHERE collection_key=? AND ordinal=? OR source_key=? LIMIT 1", arrayOf(lease.collection, LibrarySavedPolicy.integer(fact.ordinalValue).toString(), lease.sourceKey(fact))).use { if (it.moveToFirst()) throw LibrarySyncFailure.InvalidReceipt }
                    db.insertOrThrow("saved_facts", null, ContentValues().apply {
                        put("row_key", lease.ordinalKey(LibrarySavedPolicy.integer(fact.ordinalValue))); put("collection_key", lease.collection); put("ordinal", LibrarySavedPolicy.integer(fact.ordinalValue)); put("source_key", lease.sourceKey(fact)); put("subject", lease.owner.subject); put("namespace", lease.owner.namespace); put("owner_key", lease.owner.storageKey)
                        put("fingerprint", fact.savedFingerprint()); put("data", Json.encodeToString(fact))
                    }); next = next.copy(digest = LibraryOutcomeBinding.hash(listOf(next.digest, fact.savedFingerprint())))
                }
                next = next.copy(position = plan.position)
                if (plan.position.continuation is LibrarySavedContinuation.Complete) next = next.copy(stage = LibrarySavedStage.Folding(0, -1, LibraryOutcomeBinding.hash(listOf("saved-raw-v1"))))
                result = LibrarySavedReceiptResult.Advanced(plan.position); count = plan.facts.size
            }
        }
        val receipt = LibrarySavedPageReceipt(checkpoint.pages, requested, checkpoint.position, checkpoint.next, count, librarySemanticDigest(savedJournalJson.encodeToJsonElement(reply), "library-saved-page-v1:"), result)
        db.insertOrThrow("saved_pages", null, ContentValues().apply {
            put("collection_key", lease.collection); put("input_key", lease.inputKey(requested)); put("sequence", receipt.sequence); put("subject", lease.owner.subject); put("namespace", lease.owner.namespace); put("owner_key", lease.owner.storageKey); put("data", Json.encodeToString(receipt))
        }); next = next.copy(pages = next.pages + 1); savedSave(db, lease, next); next
    }
    private fun savedProjectionValue(lease: LibrarySavedLease, key: String, subject: String, namespace: String, owner: String, fingerprint: String, data: String): LibrarySavedProjection {
        if (data.toByteArray().size > 256 * 1024) throw LibrarySyncFailure.StoreUnavailable
        val value = Json.decodeFromString<LibrarySavedProjection>(data); value.validateProjection()
        if (key != lease.projectionKey(value) || subject != lease.owner.subject || namespace != lease.owner.namespace || owner != lease.owner.storageKey || fingerprint != value.savedFingerprint()) throw LibrarySyncFailure.StoreUnavailable
        return value
    }
    private fun savedProjection(db: SQLiteDatabase, lease: LibrarySavedLease, key: String): LibrarySavedProjection? =
        db.rawQuery("SELECT subject,namespace,owner_key,fingerprint,data FROM saved_projection WHERE collection_key=? AND row_key=?", arrayOf(lease.collection, key)).use {
            if (it.moveToFirst()) savedProjectionValue(lease, key, it.getString(0), it.getString(1), it.getString(2), it.getString(3), it.getString(4)) else null
        }
    private fun savedProjectionRows(db: SQLiteDatabase, lease: LibrarySavedLease, after: String?): List<Pair<String, LibrarySavedProjection>> {
        val values = mutableListOf<Pair<String, LibrarySavedProjection>>()
        val prefix = lease.collection + ":r:"
        if (after != null && !after.startsWith(prefix)) throw LibrarySyncFailure.InvalidReceipt
        db.rawQuery("SELECT row_key,subject,namespace,owner_key,fingerprint,data FROM saved_projection WHERE collection_key=? AND row_key>? AND row_key<? ORDER BY row_key LIMIT 8", arrayOf(lease.collection, after ?: prefix, prefix + "~")).use {
            while (it.moveToNext()) values.add(it.getString(0) to savedProjectionValue(lease, it.getString(0), it.getString(1), it.getString(2), it.getString(3), it.getString(4), it.getString(5)))
        }; return values
    }
    private fun savedPageReceipts(db: SQLiteDatabase, lease: LibrarySavedLease, start: Long, total: Long): List<LibrarySavedPageReceipt> {
        if (start !in 0..total) throw LibrarySyncFailure.StoreUnavailable
        val receipts = mutableListOf<LibrarySavedPageReceipt>()
        db.rawQuery("SELECT sequence,input_key,subject,namespace,owner_key,data FROM saved_pages WHERE collection_key=? AND sequence>=? ORDER BY sequence LIMIT 8", arrayOf(lease.collection, start.toString())).use {
            while (it.moveToNext()) {
                if (it.getString(5).toByteArray().size > 256 * 1024) throw LibrarySyncFailure.StoreUnavailable
                val receipt = Json.decodeFromString<LibrarySavedPageReceipt>(it.getString(5))
                LibrarySavedPolicy.integer(receipt.sequence.toDouble()); LibrarySavedPolicy.integer(receipt.start.toDouble())
                if (receipt.start.toDouble() > LibrarySavedPolicy.maxInteger - receipt.count) throw LibrarySyncFailure.StoreUnavailable
                if (receipt.sequence != start + receipts.size || it.getLong(0) != receipt.sequence || it.getString(1) != lease.inputKey(receipt.input) || it.getString(2) != lease.owner.subject || it.getString(3) != lease.owner.namespace || it.getString(4) != lease.owner.storageKey || receipt.start < 0 || receipt.count !in 0..LibrarySyncLimits.savedFactRows) throw LibrarySyncFailure.StoreUnavailable
                val facts = savedFacts(db, lease, receipt.start, receipt.start + receipt.count)
                receipt.validate(receipt.reply(facts, lease.owner), lease.owner, facts); receipts.add(receipt)
            }
        }
        if (receipts.size.toLong() != minOf(savedStepLimit.toLong(), total - start)) throw LibrarySyncFailure.StoreUnavailable
        return receipts
    }
    fun advanceSaved(lease: LibrarySavedLease): LibrarySavedCheckpoint = transaction { db ->
        savedCheckClock(db, lease.owner); val checkpoint = savedHeader(db, lease); var next = checkpoint
        when (val phase = checkpoint.stage) {
            is LibrarySavedStage.Folding -> {
                val rows = savedFacts(db, lease, phase.next, checkpoint.next); var rank = phase.phase; var checksum = phase.digest
                for (fact in rows) {
                    if (fact.sourcePhase < rank) throw LibrarySyncFailure.StoreUnavailable; rank = fact.sourcePhase
                    val kind = if (fact.sourcePhase == 0) "folder" else "item"; val key = lease.collection + ":r:" + LibraryOutcomeBinding.hash(listOf(kind, fact.targetID))
                    val previous = savedProjection(db, lease, key); val value = LibrarySavedPolicy.fold(fact, previous)
                    if (previous == null) next = next.copy(counts = next.counts.adding(value))
                    val data = ContentValues().apply { put("row_key", key); put("collection_key", lease.collection); put("subject", lease.owner.subject); put("namespace", lease.owner.namespace); put("owner_key", lease.owner.storageKey); put("fingerprint", value.savedFingerprint()); put("data", Json.encodeToString(value)) }
                    if (previous == null) db.insertOrThrow("saved_projection", null, data) else if (db.update("saved_projection", data, "row_key=?", arrayOf(key)) != 1) throw LibrarySyncFailure.StoreUnavailable
                    checksum = LibraryOutcomeBinding.hash(listOf(checksum, fact.savedFingerprint()))
                }
                val end = phase.next + rows.size
                next = if (end == checkpoint.next) {
                    savedNoExtraFacts(db, lease, end)
                    if (checksum != checkpoint.digest) throw LibrarySyncFailure.StoreUnavailable
                    next.copy(stage = LibrarySavedStage.CheckingPages(0, null, null))
                } else next.copy(stage = LibrarySavedStage.Folding(end, rank, checksum))
            }
            is LibrarySavedStage.CheckingPages -> {
                val rows = savedPageReceipts(db, lease, phase.next, checkpoint.pages); var input = phase.input; var position = phase.position
                for (receipt in rows) {
                    if (receipt.input != input || receipt.before != position || receipt.result !is LibrarySavedReceiptResult.Advanced) throw LibrarySyncFailure.StoreUnavailable
                    position = receipt.result.position; input = position.continuation.token
                }
                val end = phase.next + rows.size
                next = if (end == checkpoint.pages) {
                    if (position != checkpoint.position) throw LibrarySyncFailure.StoreUnavailable
                    next.copy(stage = LibrarySavedStage.Verifying(null, LibrarySavedCounts()))
                } else next.copy(stage = LibrarySavedStage.CheckingPages(end, input, position))
            }
            is LibrarySavedStage.Verifying -> {
                val rows = savedProjectionRows(db, lease, phase.after); var seen = phase.seen
                for (row in rows) seen = seen.adding(row.second)
                if (seen.items > checkpoint.counts.items || seen.folders > checkpoint.counts.folders) throw LibrarySyncFailure.StoreUnavailable
                next = if (rows.size < savedStepLimit) {
                    if (seen != checkpoint.counts) throw LibrarySyncFailure.StoreUnavailable
                    next.copy(stage = LibrarySavedStage.Prepared)
                } else next.copy(stage = LibrarySavedStage.Verifying(rows.last().first, seen))
            }
            else -> return@transaction checkpoint
        }; savedSave(db, lease, next); next
    }
    fun savedPreparedPage(lease: LibrarySavedLease, after: String?): LibrarySavedProjectionPage = transaction { db ->
        savedCheckClock(db, lease.owner); if (savedHeader(db, lease).stage != LibrarySavedStage.Prepared) throw LibrarySyncFailure.StoreUnavailable
        val rows = savedProjectionRows(db, lease, after); LibrarySavedProjectionPage(rows.map { it.second }, rows.lastOrNull()?.first, rows.size < savedStepLimit)
    }

    private fun hasSavedRows(db: SQLiteDatabase, subject: String, namespace: String): Boolean {
        for (table in listOf("saved_assemblies", "saved_facts", "saved_pages", "saved_projection")) db.rawQuery("SELECT 1 FROM $table WHERE subject=? AND namespace=? LIMIT 1", arrayOf(subject, namespace)).use { if (it.moveToFirst()) return true }
        return false
    }
    fun beginSavedErase(subject: String, namespace: String, ownerKey: String?) = transaction { db ->
        if (ownerKey != null) {
            val key = LibraryOutcomeBinding.hash(listOf(namespace, subject)) + ":" + LibraryOutcomeBinding.hash(listOf(ownerKey, subject))
            db.rawQuery("SELECT subject,namespace,owner_key FROM saved_assemblies WHERE scope_key=?", arrayOf(key)).use {
                if (it.moveToFirst() && (it.getString(0) != subject || it.getString(1) != namespace || it.getString(2) != ownerKey)) throw LibrarySyncFailure.OwnerMismatch
            }
            db.update("saved_assemblies", ContentValues().apply { put("erasing", 1) }, "scope_key=?", arrayOf(key))
        }
        bumpClock(db, subject, namespace, erasing = ownerKey == null)
    }
    fun eraseSavedStep(subject: String, namespace: String, ownerKey: String?): Boolean = transaction { db ->
        if (ownerKey == null && clock(db, subject, namespace)?.erasing != true) throw LibrarySyncFailure.AccountDeleting
        if (ownerKey != null) db.rawQuery("SELECT erasing FROM saved_assemblies WHERE subject=? AND namespace=? AND owner_key=? LIMIT 1", arrayOf(subject, namespace, ownerKey)).use { if (it.moveToFirst() && it.getInt(0) == 0) throw LibrarySyncFailure.InvalidChange }
        val selection = if (ownerKey == null) "subject=? AND namespace=?" else "subject=? AND namespace=? AND owner_key=?"
        val args = if (ownerKey == null) arrayOf(subject, namespace) else arrayOf(subject, namespace, ownerKey)
        for (table in listOf("saved_facts", "saved_pages", "saved_projection", "saved_assemblies")) {
            val deleted = db.delete(table, "rowid IN (SELECT rowid FROM $table WHERE $selection LIMIT 8)", args)
            if (deleted > 0) { bumpClock(db, subject, namespace, erasing = ownerKey == null); return@transaction true }
        }; false
    }
    fun savedExportRecords(fence: LibraryOutcomeExportFence, section: Int, after: String?): Triple<List<kotlinx.serialization.json.JsonElement>, String?, Boolean> = transaction { db ->
        checkFence(db, fence)
        val subject = fence.owner.subject; val namespace = fence.owner.namespace
        val prefix = LibraryOutcomeBinding.hash(listOf(namespace, subject)) + ":"; val lower = after ?: prefix; val upper = prefix + "~"
        val (table, key) = when (section) { 0 -> "saved_assemblies" to "scope_key"; 1 -> "saved_facts" to "row_key"; 2 -> "saved_pages" to "input_key"; 3 -> "saved_projection" to "row_key"; else -> throw LibrarySyncFailure.InvalidReceipt }
        val values = mutableListOf<kotlinx.serialization.json.JsonElement>(); var last: String? = null
        fun metadata(s: String, n: String, owner: String, collection: String): MutableMap<String, kotlinx.serialization.json.JsonElement> {
            val scope = LibraryOutcomeBinding.hash(listOf(namespace, subject)) + ":" + LibraryOutcomeBinding.hash(listOf(owner, subject))
            if (s != subject || n != namespace || !owner.startsWith("$namespace|") || !collection.startsWith("$scope:")) throw LibrarySyncFailure.OwnerMismatch
            return mutableMapOf("ownerStorageKey" to kotlinx.serialization.json.JsonPrimitive(owner), "subject" to kotlinx.serialization.json.JsonPrimitive(s), "namespace" to kotlinx.serialization.json.JsonPrimitive(n), "collection" to kotlinx.serialization.json.JsonPrimitive(collection), "coverage" to kotlinx.serialization.json.JsonPrimitive("retained_local_rows"))
        }
        if (section == 0) db.rawQuery("SELECT scope_key,lease FROM saved_assemblies WHERE scope_key>? AND scope_key<? ORDER BY scope_key LIMIT 8", arrayOf(lower, upper)).use {
            while (it.moveToNext()) {
                if (it.getString(1).toByteArray().size > 16_384) throw LibrarySyncFailure.StoreUnavailable
                val lease = Json.decodeFromString<LibrarySavedLease>(it.getString(1))
                if (lease.owner.subject != subject || lease.owner.namespace != namespace || lease.key != it.getString(0)) throw LibrarySyncFailure.OwnerMismatch
                val data = LibrarySavedExportEntry(lease, savedHeader(db, lease)).exportMetadata().toMutableMap()
                data["kind"] = kotlinx.serialization.json.JsonPrimitive("assembly"); data["coverage"] = kotlinx.serialization.json.JsonPrimitive("retained_local_rows")
                values.add(kotlinx.serialization.json.JsonObject(data)); last = it.getString(0)
            }
        } else {
            val columns = when (section) { 1 -> "ordinal,source_key,fingerprint,data"; 2 -> "sequence,data"; else -> "fingerprint,data" }
            db.rawQuery("SELECT $key,collection_key,subject,namespace,owner_key,$columns FROM $table WHERE $key>? AND $key<? ORDER BY $key LIMIT 8", arrayOf(lower, upper)).use {
                while (it.moveToNext()) {
                    val rowKey = it.getString(0); val collection = it.getString(1); val data = metadata(it.getString(2), it.getString(3), it.getString(4), collection)
                    val record: LibrarySavedExportRecord = when (section) {
                        1 -> {
                            if (it.getString(8).toByteArray().size > LibrarySyncLimits.savedFactPageBytes) throw LibrarySyncFailure.StoreUnavailable
                            val fact = Json.decodeFromString<SavedFact>(it.getString(8)); LibrarySavedPolicy.validate(fact); val ordinal = LibrarySavedPolicy.integer(fact.ordinalValue)
                            if (it.getLong(5) != ordinal || rowKey != collection + ":f:" + ordinal.toString(16).padStart(16, '0') || it.getString(6) != collection + ":i:" + LibraryOutcomeBinding.hash(listOf(fact.sourcePhase.toString(), fact.sourceID)) || it.getString(7) != fact.savedFingerprint()) throw LibrarySyncFailure.StoreUnavailable
                            LibrarySavedExportRecord.Fact(fact)
                        }
                        2 -> {
                            if (it.getString(6).toByteArray().size > 256 * 1024) throw LibrarySyncFailure.StoreUnavailable
                            val receipt = Json.decodeFromString<LibrarySavedPageReceipt>(it.getString(6))
                            if (receipt.sequence < 0 || receipt.sequence != it.getLong(5) || receipt.start < 0 || receipt.count < 0 || rowKey != collection + ":p:" + LibraryOutcomeBinding.hash(listOf(if (receipt.input == null) "absent" else "present", receipt.input ?: ""))) throw LibrarySyncFailure.StoreUnavailable
                            val positions = listOfNotNull(receipt.before, when (val result = receipt.result) { is LibrarySavedReceiptResult.Advanced -> result.position; else -> null })
                            if (positions.any { p -> p.owner.subject != subject || p.owner.namespace != namespace || p.owner.storageKey != it.getString(4) }) throw LibrarySyncFailure.OwnerMismatch
                            LibrarySavedExportRecord.Page(receipt)
                        }
                        else -> LibrarySavedExportRecord.Projection(savedProjectionValueFromExport(collection, rowKey, it.getString(5), it.getString(6)))
                    }
                    data["record"] = record.exportValue(); values.add(kotlinx.serialization.json.JsonObject(data)); last = rowKey
                }
            }
        }; checkFence(db, fence); Triple(values, last, values.size < savedStepLimit)
    }
    private fun savedProjectionValueFromExport(collection: String, key: String, fingerprint: String, data: String): LibrarySavedProjection {
        if (data.toByteArray().size > 256 * 1024) throw LibrarySyncFailure.StoreUnavailable
        val value = Json.decodeFromString<LibrarySavedProjection>(data); value.validateProjection()
        if (key != collection + ":r:" + LibraryOutcomeBinding.hash(listOf(value.kind, value.targetID)) || fingerprint != value.savedFingerprint()) throw LibrarySyncFailure.StoreUnavailable
        return value
    }

}
