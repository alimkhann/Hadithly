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

private val savedJournalJson = Json { encodeDefaults = true; explicitNulls = false }

/** Shared transaction boundary for account state, retained page evidence and erase fences. */
internal class LibraryOutcomeJournal(context: Context) : SQLiteOpenHelper(context, File(context.filesDir, "library_outcomes.db").absolutePath, null, 9) {
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
        createLocalStoreSchema(db)
        createSavedViewSchema(db)
    }
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion !in 1..8 || newVersion != 9) throw LibrarySyncFailure.StoreUnavailable
        if (oldVersion == 1) createExportSchema(db, ready = false)
        if (oldVersion <= 2) createSavedSchema(db)
        else if (oldVersion <= 5) {
            if (oldVersion == 3) {
                db.execSQL("ALTER TABLE saved_assemblies ADD COLUMN active TEXT")
                db.execSQL("ALTER TABLE saved_assemblies ADD COLUMN retiring TEXT")
            }
            db.execSQL("ALTER TABLE saved_assemblies ADD COLUMN row_mode INTEGER NOT NULL DEFAULT 0")
        }
        if (oldVersion <= 4) createLocalStoreSchema(db)
        if (oldVersion <= 6) createSavedViewSchema(db)
        else {
            if (oldVersion == 7) {
                db.execSQL("ALTER TABLE saved_view_heads ADD COLUMN audit TEXT")
                db.execSQL("ALTER TABLE saved_view_heads ADD COLUMN retiring INTEGER NOT NULL DEFAULT 0")
            }
            db.execSQL("ALTER TABLE saved_view_heads ADD COLUMN build TEXT")
        }
    }
    private fun createSavedSchema(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE saved_assemblies (scope_key TEXT PRIMARY KEY NOT NULL, subject TEXT NOT NULL, namespace TEXT NOT NULL, owner_key TEXT NOT NULL, lease TEXT NOT NULL, checkpoint TEXT NOT NULL, erasing INTEGER NOT NULL, active TEXT, retiring TEXT, row_mode INTEGER NOT NULL DEFAULT 0)")
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
    internal fun bumpClock(db: SQLiteDatabase, subject: String, namespace: String, erasing: Boolean = false) {
        if (!erasing && localScopeDeleting(db, subject, namespace)) throw LibrarySyncFailure.AccountDeleting
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
    fun prepareExportStep(): Boolean = transaction { db -> prepareExportStepIn(db) }
    internal fun prepareExportStepIn(db: SQLiteDatabase): Boolean {
        val phase: String; val after: String
        db.rawQuery("SELECT phase,cursor FROM export_migration WHERE id=1", null).use {
            if (!it.moveToFirst()) throw LibrarySyncFailure.StoreUnavailable
            phase = it.getString(0); after = it.getString(1)
        }
        if (phase == "ready") return true
        if (phase != "scan" && phase != "check") throw LibrarySyncFailure.StoreUnavailable
        var last: String? = null
        db.rawQuery("SELECT collection_key,authority FROM headers WHERE collection_key>? ORDER BY collection_key LIMIT 50", arrayOf(after)).use { cursor ->
            while (cursor.moveToNext()) {
                last = cursor.getString(0)
                val value = Json.decodeFromString<LibraryOutcomeAuthority>(cursor.getString(1)); val binding = LibraryOutcomeBinding(value.owner, value.committed)
                if (last != binding.key) throw LibrarySyncFailure.StoreUnavailable
                header(db, binding) ?: throw LibrarySyncFailure.StoreUnavailable
                if (!localScopeDeleting(db, binding.owner.subject, binding.owner.namespace) && clock(db, binding.owner.subject, binding.owner.namespace) == null) bumpClock(db, binding.owner.subject, binding.owner.namespace)
            }
        }
        val nextPhase = if (last != null) phase else if (phase == "scan") "check" else "ready"
        db.update("export_migration", ContentValues().apply { put("phase", nextPhase); put("cursor", last ?: "") }, "id=1", null)
        return nextPhase == "ready"
    }
    private fun checkFence(db: SQLiteDatabase, fence: LibraryOutcomeExportFence) {
        assertLocalOwner(db, fence.owner)
        val current = clock(db, fence.owner.subject, fence.owner.namespace)
        when (val expected = fence.version) {
            LibraryOutcomeExportVersion.Empty -> if (current != null || hasSavedRows(db, fence.owner.subject, fence.owner.namespace) || hasLocalAccountRows(db, fence.owner.subject, fence.owner.namespace)) throw LibrarySyncFailure.StoreUnavailable
            is LibraryOutcomeExportVersion.Present -> if (current == null || current.erasing || current.epoch != expected.epoch || current.revision != expected.revision) throw LibrarySyncFailure.StoreUnavailable
        }
    }
    fun captureExportFence(owner: LibrarySyncOwner): LibraryOutcomeExportFence = transaction { db ->
        assertLocalOwner(db, owner)
        db.rawQuery("SELECT phase FROM export_migration WHERE id=1", null).use { if (!it.moveToFirst() || it.getString(0) != "ready") throw LibrarySyncFailure.StoreUnavailable }
        val value = clock(db, owner.subject, owner.namespace)
        val version = if (value == null) {
            db.rawQuery("SELECT collection_key FROM headers WHERE subject=? AND namespace=? LIMIT 1", arrayOf(owner.subject, owner.namespace)).use { if (it.moveToFirst()) throw LibrarySyncFailure.StoreUnavailable }
            if (hasSavedRows(db, owner.subject, owner.namespace) || hasLocalAccountRows(db, owner.subject, owner.namespace)) throw LibrarySyncFailure.StoreUnavailable
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
        assertLocalOwner(db, owner)
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
    internal fun <T> transaction(allowUnready: Boolean = false, block: (SQLiteDatabase) -> T): T {
        val db = writableDatabase
        db.beginTransaction()
        try { if (!allowUnready) requireLocalReady(db); val result = block(db); db.setTransactionSuccessful(); return result }
        finally { db.endTransaction() }
    }
    private fun generation(db: SQLiteDatabase, key: String): String? = db.rawQuery("SELECT generation FROM scopes WHERE scope_key=?", arrayOf(key)).use { if (it.moveToFirst()) it.getString(0) else null }
    fun captureGeneration(binding: LibraryOutcomeBinding): String = transaction { db ->
        assertLocalOwner(db, binding.owner)
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
        assertLocalOwner(db, binding.owner)
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
            assertLocalOwner(db, binding.owner)
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
    internal fun acknowledgeIn(db: SQLiteDatabase, binding: LibraryOutcomeBinding, now: Double) {
        val current = generation(db, binding.scopeKey) ?: throw LibrarySyncFailure.StoreUnavailable
        val checkpoint = header(db, binding, current) ?: throw LibrarySyncFailure.StoreUnavailable
        if (!now.isFinite() || now < 0 || checkpoint.status != LibraryOutcomeStatus.Complete || binding.expected.superseded != 0L || binding.expected.missing != 0L || checkpoint.retention?.removed != null) throw LibrarySyncFailure.InvalidReceipt
        if (checkpoint.retention == null) {
            db.update("headers", ContentValues().apply { put("checkpoint", Json.encodeToString(checkpoint.copy(retention = LibraryOutcomeRetention(now)))) }, "collection_key=?", arrayOf(binding.key))
            bumpClock(db, binding.owner.subject, binding.owner.namespace)
        }
    }
    internal fun retentionEntriesIn(db: SQLiteDatabase, owner: LibrarySyncOwner, after: String?): List<LibraryOutcomeExportEntry> {
        val entries = mutableListOf<LibraryOutcomeExportEntry>()
        db.rawQuery("SELECT collection_key,authority FROM headers WHERE subject=? AND namespace=? AND collection_key>? ORDER BY collection_key LIMIT 50", arrayOf(owner.subject, owner.namespace, after ?: "")).use {
            while (it.moveToNext()) {
                val authority = Json.decodeFromString<LibraryOutcomeAuthority>(it.getString(1)); val binding = LibraryOutcomeBinding(authority.owner, authority.committed)
                if (binding.key != it.getString(0) || binding.owner.subject != owner.subject || binding.owner.namespace != owner.namespace) throw LibrarySyncFailure.OwnerMismatch
                entries.add(LibraryOutcomeExportEntry(binding, header(db, binding) ?: throw LibrarySyncFailure.StoreUnavailable))
            }
        }
        return entries
    }
    internal fun pruneIn(db: SQLiteDatabase, binding: LibraryOutcomeBinding, expected: LibraryOutcomeCheckpoint): Boolean {
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
        return done
    }

    internal fun settlementCheckpointIn(db: SQLiteDatabase, binding: LibraryOutcomeBinding): LibraryOutcomeCheckpoint {
        val current = generation(db, binding.scopeKey) ?: throw LibrarySyncFailure.StoreUnavailable
        return header(db, binding, current) ?: throw LibrarySyncFailure.StoreUnavailable
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
            if (!remaining && !artifacts && !hasSavedRows(db, subject, namespace) && !hasLocalAccountRows(db, subject, namespace)) db.delete("export_clocks", "scope_key=?", arrayOf(LibraryOutcomeBinding.hash(listOf(namespace, subject))))
            else if (ownerKey == null) throw LibrarySyncFailure.StoreUnavailable
        }
    }
    companion object { const val savedStepLimit = 8 }
    private fun savedCheckClock(db: SQLiteDatabase, owner: LibrarySyncOwner) { if (clock(db, owner.subject, owner.namespace)?.erasing == true) throw LibrarySyncFailure.AccountDeleting }
    private fun savedHeader(db: SQLiteDatabase, lease: LibrarySavedLease): LibrarySavedCheckpoint {
        lease.validate()
        return db.rawQuery("SELECT subject,namespace,owner_key,lease,checkpoint,erasing FROM saved_assemblies WHERE scope_key=?", arrayOf(lease.key)).use {
            if (!it.moveToFirst() || it.getInt(5) != 0 || it.getString(0) != lease.owner.subject || it.getString(1) != lease.owner.namespace || it.getString(2) != lease.owner.storageKey || it.getString(3).toByteArray().size > 16_384 || it.getString(4).toByteArray().size > 256 * 1024 || Json.decodeFromString<LibrarySavedLease>(it.getString(3)) != lease) throw LibrarySyncFailure.SessionChanged
            Json.decodeFromString<LibrarySavedCheckpoint>(it.getString(4)).also { value -> value.validate(lease.owner); savedGenerations(db, lease, value) }
        }
    }
    private fun savedSave(db: SQLiteDatabase, lease: LibrarySavedLease, checkpoint: LibrarySavedCheckpoint) {
        checkpoint.validate(lease.owner); val data = Json.encodeToString(checkpoint)
        if (data.toByteArray().size > 256 * 1024) throw LibrarySyncFailure.StoreUnavailable
        if (db.update("saved_assemblies", ContentValues().apply { put("checkpoint", data) }, "scope_key=?", arrayOf(lease.key)) != 1) throw LibrarySyncFailure.SessionChanged
        bumpClock(db, lease.owner.subject, lease.owner.namespace)
    }
    fun beginSaved(owner: LibrarySyncOwner): LibrarySavedLease = transaction { db ->
        assertLocalOwner(db, owner)
        savedCheckClock(db, owner)
        val candidate = LibrarySavedLease(owner, UUID.randomUUID().toString(), UUID.randomUUID().toString()); candidate.validate()
        val existing = db.rawQuery("SELECT lease FROM saved_assemblies WHERE scope_key=?", arrayOf(candidate.key)).use { if (it.moveToFirst()) { if (it.getString(0).toByteArray().size > 16_384) throw LibrarySyncFailure.StoreUnavailable; Json.decodeFromString<LibrarySavedLease>(it.getString(0)) } else null }
        if (existing != null) {
            if (existing.owner != owner) throw LibrarySyncFailure.OwnerMismatch
            val checkpoint = savedHeader(db, existing); val generations = savedGenerations(db, existing, checkpoint)
            if (generations.first?.lease != existing) existing
            else {
                if (generations.second != null) throw LibrarySyncFailure.StoreUnavailable
                val next = LibrarySavedLease(owner, existing.epoch, UUID.randomUUID().toString())
                db.update("saved_assemblies", ContentValues().apply { put("lease", Json.encodeToString(next)) }, "scope_key=?", arrayOf(existing.key))
                savedSave(db, next, LibrarySavedCheckpoint()); next
            }
        }
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
        assertLocalOwner(db, lease.owner)
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
        assertLocalOwner(db, lease.owner)
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
    private fun savedGeneration(data: String?, scope: LibrarySavedLease, prepared: Boolean): LibrarySavedGenerationRecord? {
        if (data == null) return null
        if (data.toByteArray().size > 256 * 1024) throw LibrarySyncFailure.StoreUnavailable
        return Json.decodeFromString<LibrarySavedGenerationRecord>(data).also { it.validate(scope, prepared) }
    }
    private fun savedGenerations(db: SQLiteDatabase, lease: LibrarySavedLease, checkpoint: LibrarySavedCheckpoint): Pair<LibrarySavedGenerationRecord?, LibrarySavedGenerationRecord?> =
        db.rawQuery("SELECT active,retiring FROM saved_assemblies WHERE scope_key=?", arrayOf(lease.key)).use {
            if (!it.moveToFirst()) throw LibrarySyncFailure.SessionChanged
            val active = savedGeneration(if (it.isNull(0)) null else it.getString(0), lease, true)
            val retiring = savedGeneration(if (it.isNull(1)) null else it.getString(1), lease, false)
            if ((active?.lease == lease && active.checkpoint != checkpoint) || (retiring != null && (retiring.lease == lease || retiring.lease == active?.lease))) throw LibrarySyncFailure.StoreUnavailable
            active to retiring
        }
    private fun currentSavedScope(db: SQLiteDatabase, owner: LibrarySyncOwner): Pair<LibrarySavedLease, LibrarySavedCheckpoint>? {
        savedCheckClock(db, owner)
        val key = LibrarySavedLease(owner, "lookup", "lookup").key
        val lease = db.rawQuery("SELECT lease FROM saved_assemblies WHERE scope_key=?", arrayOf(key)).use {
            if (!it.moveToFirst()) null else {
                if (it.getString(0).toByteArray().size > 16_384) throw LibrarySyncFailure.StoreUnavailable
                Json.decodeFromString<LibrarySavedLease>(it.getString(0))
            }
        } ?: return null
        if (lease.owner != owner) throw LibrarySyncFailure.OwnerMismatch
        return lease to savedHeader(db, lease)
    }
    internal fun savedObservationIn(db: SQLiteDatabase, owner: LibrarySyncOwner, state: LibraryPartitionState): LibrarySavedObservation {
        assertLocalOwner(db, owner)
        val scope = currentSavedScope(db, owner) ?: return LibrarySavedObservation.legacy(owner, state.savedSnapshot)
        val mode = db.rawQuery("SELECT row_mode FROM saved_assemblies WHERE scope_key=?", arrayOf(scope.first.key)).use {
            if (!it.moveToFirst()) throw LibrarySyncFailure.SessionChanged
            if (it.getType(0) != android.database.Cursor.FIELD_TYPE_INTEGER) throw LibrarySyncFailure.StoreUnavailable
            it.getLong(0)
        }
        return when (mode) {
            0L -> LibrarySavedObservation.legacy(owner, state.savedSnapshot)
            1L -> savedGenerations(db, scope.first, scope.second).first?.let(LibrarySavedObservation::active) ?: LibrarySavedObservation.unavailable(owner)
            else -> throw LibrarySyncFailure.StoreUnavailable
        }
    }
    fun savedActive(owner: LibrarySyncOwner): LibrarySavedActiveGeneration? = transaction { db ->
        assertLocalOwner(db, owner)
        val scope = currentSavedScope(db, owner) ?: return@transaction null
        savedGenerations(db, scope.first, scope.second).first?.let { LibrarySavedActiveGeneration(it) }
    }
    fun savedActivePage(handle: LibrarySavedActiveGeneration, after: String?): LibrarySavedProjectionPage = transaction { db ->
        assertLocalOwner(db, handle.lease.owner)
        val scope = currentSavedScope(db, handle.lease.owner) ?: throw LibrarySyncFailure.SessionChanged
        val active = savedGenerations(db, scope.first, scope.second).first ?: throw LibrarySyncFailure.SessionChanged
        if (LibrarySavedActiveGeneration(active) != handle) throw LibrarySyncFailure.SessionChanged
        val rows = savedProjectionRows(db, handle.lease, after)
        LibrarySavedProjectionPage(rows.map { it.second }, rows.lastOrNull()?.first, rows.size < savedStepLimit)
    }
    fun activateSaved(lease: LibrarySavedLease, captured: LibrarySavedCheckpoint, reply: SavedFactsReply): LibrarySavedActivation = transaction { db ->
        assertLocalOwner(db, lease.owner)
        savedCheckClock(db, lease.owner); val checkpoint = savedHeader(db, lease)
        if (checkpoint != captured || checkpoint.stage != LibrarySavedStage.Prepared) throw LibrarySyncFailure.SessionChanged
        val position = checkpoint.position ?: throw LibrarySyncFailure.InvalidReceipt
        val generations = savedGenerations(db, lease, checkpoint)
        generations.first?.let { if (it.lease == lease) return@transaction LibrarySavedActivation.Active(LibrarySavedActiveGeneration(it)) }
        when (reply) {
            is SavedFactsReply.Restart -> {
                if (reply.reason != "saved_changed") throw LibrarySyncFailure.InvalidReceipt
                savedSave(db, lease, checkpoint.copy(stage = LibrarySavedStage.Restart)); return@transaction LibrarySavedActivation.Restart
            }
            is SavedFactsReply.Unavailable -> {
                savedSave(db, lease, checkpoint.copy(stage = LibrarySavedStage.Unavailable(reply.reason))); return@transaction LibrarySavedActivation.Unavailable(reply.reason)
            }
            else -> LibrarySavedPolicy.confirm(reply, position)
        }
        if (generations.second != null || (generations.first?.checkpoint?.position?.version ?: -1.0) > position.version) throw LibrarySyncFailure.InvalidReceipt
        val active = LibrarySavedGenerationRecord(lease, checkpoint)
        val values = ContentValues().apply { put("active", Json.encodeToString(active)); put("retiring", generations.first?.let { Json.encodeToString(it) }) }
        if (db.update("saved_assemblies", values, "scope_key=?", arrayOf(lease.key)) != 1) throw LibrarySyncFailure.SessionChanged
        savedSave(db, lease, checkpoint); LibrarySavedActivation.Active(LibrarySavedActiveGeneration(active))
    }
    fun replaceSavedCandidate(lease: LibrarySavedLease): LibrarySavedLease = transaction { db ->
        assertLocalOwner(db, lease.owner)
        savedCheckClock(db, lease.owner); val checkpoint = savedHeader(db, lease)
        val generations = savedGenerations(db, lease, checkpoint)
        if (generations.first?.lease == lease || generations.second != null) throw LibrarySyncFailure.InvalidChange
        val next = LibrarySavedLease(lease.owner, lease.epoch, UUID.randomUUID().toString())
        val values = ContentValues().apply { put("lease", Json.encodeToString(next)); put("retiring", Json.encodeToString(LibrarySavedGenerationRecord(lease, checkpoint))) }
        if (db.update("saved_assemblies", values, "scope_key=?", arrayOf(lease.key)) != 1) throw LibrarySyncFailure.SessionChanged
        savedSave(db, next, LibrarySavedCheckpoint()); next
    }
    fun cleanupSavedGenerationStep(owner: LibrarySyncOwner): Boolean = transaction { db ->
        val scope = currentSavedScope(db, owner) ?: return@transaction false
        val retiring = savedGenerations(db, scope.first, scope.second).second ?: return@transaction false
        for (table in listOf("saved_facts", "saved_pages", "saved_projection")) {
            val deleted = db.delete(table, "rowid IN (SELECT rowid FROM $table WHERE collection_key=? LIMIT 8)", arrayOf(retiring.lease.collection))
            if (deleted > 0) { savedSave(db, scope.first, scope.second); return@transaction true }
        }
        db.update("saved_assemblies", ContentValues().apply { putNull("retiring") }, "scope_key=?", arrayOf(scope.first.key))
        savedSave(db, scope.first, scope.second); true
    }
    fun savedPreparedPage(lease: LibrarySavedLease, after: String?): LibrarySavedProjectionPage = transaction { db ->
        savedCheckClock(db, lease.owner); if (savedHeader(db, lease).stage != LibrarySavedStage.Prepared) throw LibrarySyncFailure.StoreUnavailable
        val rows = savedProjectionRows(db, lease, after); LibrarySavedProjectionPage(rows.map { it.second }, rows.lastOrNull()?.first, rows.size < savedStepLimit)
    }

    private fun hasSavedRows(db: SQLiteDatabase, subject: String, namespace: String): Boolean {
        for (table in listOf("saved_assemblies", "saved_facts", "saved_pages", "saved_projection", "saved_view_heads", "saved_view_rows", "saved_view_indexes")) db.rawQuery("SELECT 1 FROM $table WHERE subject=? AND namespace=? LIMIT 1", arrayOf(subject, namespace)).use { if (it.moveToFirst()) return true }
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
        for (table in listOf("saved_view_indexes", "saved_view_rows", "saved_view_heads", "saved_facts", "saved_pages", "saved_projection", "saved_assemblies")) {
            val limit = if (table == "saved_view_indexes") 128 else 8
            val deleted = db.delete(table, "rowid IN (SELECT rowid FROM $table WHERE $selection LIMIT $limit)", args)
            if (deleted > 0) { bumpClock(db, subject, namespace, erasing = ownerKey == null); return@transaction true }
        }; false
    }
    fun savedExportRecords(fence: LibraryOutcomeExportFence, section: Int, after: String?): Triple<List<kotlinx.serialization.json.JsonElement>, String?, Boolean> = transaction { db ->
        checkFence(db, fence)
        val subject = fence.owner.subject; val namespace = fence.owner.namespace
        val prefix = LibraryOutcomeBinding.hash(listOf(namespace, subject)) + ":"; val lower = after ?: prefix; val upper = prefix + "~"
        if (section == 4 || section == 5) {
            val table = if (section == 4) "saved_view_heads" else "saved_view_rows"
            val columns = if (section == 4) "identity_data,serial" else "view_key,kind,data,fingerprint"
            val result = mutableListOf<kotlinx.serialization.json.JsonElement>(); var lastKey: String? = null
            db.rawQuery("SELECT key,subject,namespace,owner_key,$columns FROM $table WHERE key>? AND key<? ORDER BY key LIMIT 8", arrayOf(lower, upper)).use { cursor ->
                while (cursor.moveToNext()) {
                    val rowKey = cursor.getString(0); val ownerKey = cursor.getString(3)
                    val scope = prefix + LibraryOutcomeBinding.hash(listOf(ownerKey, subject))
                    if (cursor.getString(1) != subject || cursor.getString(2) != namespace || !ownerKey.startsWith(namespace + "|") || !rowKey.startsWith(scope + ":")) throw LibrarySyncFailure.OwnerMismatch
                    val value = mutableMapOf<String, kotlinx.serialization.json.JsonElement>("ownerStorageKey" to kotlinx.serialization.json.JsonPrimitive(ownerKey), "subject" to kotlinx.serialization.json.JsonPrimitive(subject), "namespace" to kotlinx.serialization.json.JsonPrimitive(namespace), "coverage" to kotlinx.serialization.json.JsonPrimitive("retained_local_rows"))
                    if (section == 4) {
                        if (cursor.getString(4).toByteArray().size > 16_384 || cursor.getType(5) != android.database.Cursor.FIELD_TYPE_INTEGER || cursor.getLong(5) !in 0..9_007_199_254_740_990L) throw LibrarySyncFailure.StoreUnavailable
                        val identity = viewJson.decodeFromString<LibrarySavedViewIdentity>(cursor.getString(4))
                        if (identity.key != rowKey || identity.owner.storageKey != ownerKey || identity.owner.subject != subject || identity.owner.namespace != namespace) throw LibrarySyncFailure.OwnerMismatch
                        value["kind"] = kotlinx.serialization.json.JsonPrimitive("viewHead"); value["identity"] = viewJson.encodeToJsonElement(LibrarySavedViewIdentity.serializer(), identity); value["serial"] = kotlinx.serialization.json.JsonPrimitive(cursor.getLong(5))
                    } else {
                        val view = cursor.getString(4)
                        if (cursor.getType(5) != android.database.Cursor.FIELD_TYPE_INTEGER || cursor.getLong(5) !in 0..1L) throw LibrarySyncFailure.StoreUnavailable
                        val kind = cursor.getLong(5).toInt(); val data = cursor.getString(6)
                        if (data.toByteArray().size > 256 * 1024 || !view.startsWith(scope + ":") || librarySemanticDigest(viewJson.parseToJsonElement(data), "saved-view-row-v1:") != cursor.getString(7)) throw LibrarySyncFailure.StoreUnavailable
                        val expected = if (kind == 1) {
                            val item = viewJson.decodeFromString<LibrarySavedViewItem>(data); item.validate(); view + ":i:" + LibraryOutcomeBinding.hash(listOf(item.value.hadithId))
                        } else {
                            if (kind != 0) throw LibrarySyncFailure.StoreUnavailable
                            val folder = viewJson.decodeFromString<SyncFolderRow>(data); LibrarySavedPolicy.validate(SavedFact.Folder(folder._id, 0.0, folder)); view + ":f:" + LibraryOutcomeBinding.hash(listOf(folder._id))
                        }
                        if (rowKey != expected) throw LibrarySyncFailure.StoreUnavailable
                        value["kind"] = kotlinx.serialization.json.JsonPrimitive(if (kind == 1) "viewItem" else "viewFolder"); value["view"] = kotlinx.serialization.json.JsonPrimitive(view); value["value"] = viewJson.parseToJsonElement(data)
                    }
                    result.add(kotlinx.serialization.json.JsonObject(value)); lastKey = rowKey
                }
            }; return@transaction Triple(result, lastKey, result.size < 8)
        }
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
                val checkpoint = savedHeader(db, lease); val generations = savedGenerations(db, lease, checkpoint)
                val data = LibrarySavedGenerationRecord(lease, checkpoint).exportMetadata(generations.first?.lease == lease).toMutableMap()
                generations.first?.takeIf { active -> active.lease != lease }?.let { data["activeGeneration"] = kotlinx.serialization.json.JsonObject(it.exportMetadata(true)) }
                generations.second?.let { data["retiringGeneration"] = kotlinx.serialization.json.JsonObject(it.exportMetadata()) }
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

    // Derived draft storage. These reads do not certify completeness or publish a user library.
    private fun createSavedViewSchema(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE saved_view_heads (key TEXT PRIMARY KEY NOT NULL, scope_key TEXT NOT NULL, subject TEXT NOT NULL, namespace TEXT NOT NULL, owner_key TEXT NOT NULL, identity_data TEXT NOT NULL, serial INTEGER NOT NULL, audit TEXT, retiring INTEGER NOT NULL DEFAULT 0, build TEXT)")
        db.execSQL("CREATE INDEX saved_view_heads_scope ON saved_view_heads(scope_key,key)")
        db.execSQL("CREATE TABLE saved_view_rows (key TEXT PRIMARY KEY NOT NULL, view_key TEXT NOT NULL, subject TEXT NOT NULL, namespace TEXT NOT NULL, owner_key TEXT NOT NULL, kind INTEGER NOT NULL, data TEXT NOT NULL, fingerprint TEXT NOT NULL)")
        db.execSQL("CREATE TABLE saved_view_indexes (key TEXT PRIMARY KEY NOT NULL, view_key TEXT NOT NULL, subject TEXT NOT NULL, namespace TEXT NOT NULL, owner_key TEXT NOT NULL, target_key TEXT NOT NULL)")
        for (table in listOf("saved_view_heads", "saved_view_rows", "saved_view_indexes")) db.execSQL("CREATE INDEX ${table}_owner ON $table(subject,namespace,owner_key,key)")
    }
    private val viewJson = Json { encodeDefaults = true; explicitNulls = false }
    private fun viewHead(db: SQLiteDatabase, identity: LibrarySavedViewIdentity, allowRetiring: Boolean = false): LibrarySavedViewStamp {
        assertLocalOwner(db, identity.owner); LibrarySavedLease(identity.owner, identity.epoch, identity.generation).validate()
        val scope = currentSavedScope(db, identity.owner) ?: throw LibrarySyncFailure.SessionChanged
        if (scope.first.epoch != identity.epoch) throw LibrarySyncFailure.SessionChanged
        db.rawQuery("SELECT identity_data,serial,scope_key,subject,namespace,owner_key,retiring FROM saved_view_heads WHERE key=?", arrayOf(identity.key)).use {
            if (!it.moveToFirst() || it.getString(0).toByteArray().size > 16_384 || viewJson.decodeFromString<LibrarySavedViewIdentity>(it.getString(0)) != identity || it.getLong(1) !in 0..9_007_199_254_740_990L) throw LibrarySyncFailure.StoreUnavailable
            if (it.getType(1) != android.database.Cursor.FIELD_TYPE_INTEGER || it.getString(2) != identity.scope || it.getString(3) != identity.owner.subject || it.getString(4) != identity.owner.namespace || it.getString(5) != identity.owner.storageKey) throw LibrarySyncFailure.OwnerMismatch
            if (it.getType(6) != android.database.Cursor.FIELD_TYPE_INTEGER || it.getLong(6) !in 0..1L) throw LibrarySyncFailure.StoreUnavailable
            if (!allowRetiring && it.getLong(6) != 0L) throw LibrarySavedViewChanged()
            return LibrarySavedViewStamp(identity, it.getLong(1))
        }
    }
    internal fun draftSavedViewStamp(identity: LibrarySavedViewIdentity): LibrarySavedViewStamp = transaction { viewHead(it, identity) }
    internal fun createSavedViewRows(privateScope: LibrarySavedLease): LibrarySavedViewStamp = transaction { createViewRows(it, privateScope) }
    private fun createViewRows(db: SQLiteDatabase, privateScope: LibrarySavedLease): LibrarySavedViewStamp {
        val identity = LibrarySavedViewIdentity(privateScope.owner, privateScope.epoch, java.util.UUID.randomUUID().toString())
        assertLocalOwner(db, identity.owner); LibrarySavedLease(identity.owner, identity.epoch, identity.generation).validate()
        val scope = currentSavedScope(db, identity.owner) ?: throw LibrarySyncFailure.StoreUnavailable
        if (scope.first.epoch != identity.epoch) throw LibrarySyncFailure.SessionChanged
        for (table in listOf("saved_view_heads", "saved_view_rows", "saved_view_indexes")) db.rawQuery("SELECT key FROM $table WHERE key>=? AND key<? LIMIT 1", arrayOf(identity.key, identity.key + "~")).use { if (it.moveToFirst()) throw LibrarySyncFailure.StoreUnavailable }
        db.rawQuery("SELECT key FROM saved_view_heads WHERE scope_key=? LIMIT 3", arrayOf(identity.scope)).use { if (it.count >= 3) throw LibrarySyncFailure.StoreUnavailable }
        db.insertOrThrow("saved_view_heads", null, ContentValues().apply {
            put("key", identity.key); put("scope_key", identity.scope); put("subject", identity.owner.subject); put("namespace", identity.owner.namespace); put("owner_key", identity.owner.storageKey); put("identity_data", viewJson.encodeToString(identity)); put("serial", 0)
        }); bumpClock(db, identity.owner.subject, identity.owner.namespace); return LibrarySavedViewStamp(identity, 0)
    }
    private fun viewRow(db: SQLiteDatabase, identity: LibrarySavedViewIdentity, key: String, kind: Int): String? =
        db.rawQuery("SELECT view_key,subject,namespace,owner_key,kind,data,fingerprint FROM saved_view_rows WHERE key=?", arrayOf(key)).use {
            if (!it.moveToFirst()) null else {
                if (it.getString(0) != identity.key || it.getString(1) != identity.owner.subject || it.getString(2) != identity.owner.namespace || it.getString(3) != identity.owner.storageKey || it.getType(4) != android.database.Cursor.FIELD_TYPE_INTEGER || it.getLong(4) != kind.toLong() || it.getString(5).toByteArray().size > 256 * 1024) throw LibrarySyncFailure.StoreUnavailable
                val data = it.getString(5)
                if (librarySemanticDigest(viewJson.parseToJsonElement(data), "saved-view-row-v1:") != it.getString(6)) throw LibrarySyncFailure.StoreUnavailable
                if (kind == 1) {
                    val row = viewJson.decodeFromString<LibrarySavedViewItem>(data); row.validate()
                    if (key != identity.itemKey(row.value.hadithId)) throw LibrarySyncFailure.StoreUnavailable
                } else {
                    val row = viewJson.decodeFromString<SyncFolderRow>(data); LibrarySavedPolicy.validate(SavedFact.Folder(row._id, 0.0, row))
                    if (kind != 0 || key != identity.folderKey(row._id)) throw LibrarySyncFailure.StoreUnavailable
                }
                data
            }
        }
    private fun viewIndex(db: SQLiteDatabase, identity: LibrarySavedViewIdentity, key: String, target: String) {
        db.insertWithOnConflict("saved_view_indexes", null, ContentValues().apply {
            put("key", key); put("view_key", identity.key); put("subject", identity.owner.subject); put("namespace", identity.owner.namespace); put("owner_key", identity.owner.storageKey); put("target_key", target)
        }, SQLiteDatabase.CONFLICT_REPLACE).also { if (it == -1L) throw LibrarySyncFailure.StoreUnavailable }
    }
    internal fun writeSavedViewRows(stamp: LibrarySavedViewStamp, items: List<LibrarySavedViewItem>, folders: List<SyncFolderRow> = emptyList()): LibrarySavedViewStamp = transaction { writeViewRows(it, stamp, items, folders) }
    private fun writeViewRows(db: SQLiteDatabase, stamp: LibrarySavedViewStamp, items: List<LibrarySavedViewItem>, folders: List<SyncFolderRow> = emptyList(), preserveBuild: Boolean = false): LibrarySavedViewStamp {
        val identity = stamp.identity
        if (viewHead(db, identity) != stamp) throw LibrarySavedViewChanged()
        if (stamp.serial >= 9_007_199_254_740_990L) throw LibrarySyncFailure.StoreUnavailable
        if (items.size + folders.size !in 1..8 || items.map { it.value.hadithId }.toSet().size != items.size || folders.map { it._id }.toSet().size != folders.size) throw LibrarySyncFailure.InvalidChange
        fun write(key: String, kind: Int, data: String) {
            if (data.toByteArray().size > 256 * 1024) throw LibrarySyncFailure.StoreUnavailable
            db.insertWithOnConflict("saved_view_rows", null, ContentValues().apply {
                put("key", key); put("view_key", identity.key); put("subject", identity.owner.subject); put("namespace", identity.owner.namespace); put("owner_key", identity.owner.storageKey); put("kind", kind); put("data", data); put("fingerprint", librarySemanticDigest(viewJson.parseToJsonElement(data), "saved-view-row-v1:"))
            }, SQLiteDatabase.CONFLICT_REPLACE).also { if (it == -1L) throw LibrarySyncFailure.StoreUnavailable }
        }
        for (item in items) {
            item.validate(); val key = identity.itemKey(item.value.hadithId)
            val old = viewRow(db, identity, key, 1)?.let { viewJson.decodeFromString<LibrarySavedViewItem>(it) }
            if (old != null) for (index in LibrarySavedViewPolicy.indexKeys(identity, old)) db.delete("saved_view_indexes", "key=?", arrayOf(index))
            if (item.mask == 0) db.delete("saved_view_rows", "key=?", arrayOf(key))
            else { write(key, 1, viewJson.encodeToString(item)); for (index in LibrarySavedViewPolicy.indexKeys(identity, item)) viewIndex(db, identity, index, key) }
        }
        for (folder in folders) {
            LibrarySavedPolicy.validate(SavedFact.Folder(folder._id, 0.0, folder)); val key = identity.folderKey(folder._id)
            val old = viewRow(db, identity, key, 0)?.let { viewJson.decodeFromString<SyncFolderRow>(it) }
            if (old != null) for (prefix in listOf(identity.folderPrefix, identity.namePrefix(old.name))) db.delete("saved_view_indexes", "key=?", arrayOf(prefix + LibrarySavedViewPolicy.folderRank(old)))
            write(key, 0, viewJson.encodeToString(folder))
            for (prefix in listOf(identity.folderPrefix, identity.namePrefix(folder.name))) viewIndex(db, identity, prefix + LibrarySavedViewPolicy.folderRank(folder), key)
        }
        val next = stamp.copy(serial = stamp.serial + 1)
        db.execSQL("UPDATE saved_view_heads SET serial=?,audit=NULL" + (if (preserveBuild) "" else ",build=NULL") + " WHERE key=?", arrayOf<Any>(next.serial, identity.key)); bumpClock(db, identity.owner.subject, identity.owner.namespace); return next
    }
    private fun buildRevision(db: SQLiteDatabase, owner: LibrarySyncOwner): Long {
        assertLocalOwner(db, owner)
        return db.rawQuery("SELECT revision FROM local_accounts WHERE key=?", arrayOf(owner.storageKey)).use {
            if (!it.moveToFirst() || it.getType(0) != android.database.Cursor.FIELD_TYPE_INTEGER || it.getLong(0) !in 0..9_007_199_254_740_990L) throw LibrarySyncFailure.StoreUnavailable
            it.getLong(0)
        }
    }
    private fun buildSource(db: SQLiteDatabase, requested: LibrarySavedLease): LibrarySavedGenerationRecord {
        assertLocalOwner(db, requested.owner)
        val scope = currentSavedScope(db, requested.owner) ?: throw LibrarySavedBuildChanged()
        if (scope.first == requested && scope.second.stage == LibrarySavedStage.Prepared) return LibrarySavedGenerationRecord(requested, scope.second)
        val active = savedGenerations(db, scope.first, scope.second).first
        if (active?.lease != requested) throw LibrarySavedBuildChanged()
        return active
    }
    private fun buildRecord(db: SQLiteDatabase, identity: LibrarySavedViewIdentity): Pair<LibrarySavedViewStamp, LibrarySavedBuildRecord> {
        val stamp = viewHead(db, identity)
        val value = db.rawQuery("SELECT build FROM saved_view_heads WHERE key=?", arrayOf(identity.key)).use {
            if (!it.moveToFirst() || it.isNull(0) || it.getString(0).toByteArray().size > 512 * 1024) throw LibrarySavedBuildChanged()
            viewJson.decodeFromString<LibrarySavedBuildRecord>(it.getString(0))
        }
        value.validate(identity)
        if (value.phase == LibrarySavedBuildPhase.Prepared) {
            val audit = viewAudit(db, stamp) ?: throw LibrarySyncFailure.InvalidReceipt
            if (audit.phase != LibrarySavedViewAuditPhase.Verified || audit.manifest != value.manifest) throw LibrarySyncFailure.InvalidReceipt
        }
        if (buildSource(db, value.source.lease) != value.source) throw LibrarySavedBuildChanged()
        return stamp to value
    }
    private fun saveBuild(db: SQLiteDatabase, identity: LibrarySavedViewIdentity, value: LibrarySavedBuildRecord) {
        value.validate(identity); val data = viewJson.encodeToString(value)
        if (data.toByteArray().size > 512 * 1024) throw LibrarySyncFailure.StoreUnavailable
        if (db.update("saved_view_heads", ContentValues().apply { put("build", data) }, "key=?", arrayOf(identity.key)) != 1) throw LibrarySyncFailure.SessionChanged
        bumpClock(db, identity.owner.subject, identity.owner.namespace)
    }
    internal fun beginSavedViewBuild(source: LibrarySavedLease): LibrarySavedBuildSession = transaction { db ->
        val record = buildSource(db, source); record.validate(source, true)
        val revision = buildRevision(db, source.owner); val state = readLocalAccount(db, source.owner) ?: throw LibrarySyncFailure.SessionChanged
        val cut = LibrarySavedReplayCut.capture(state, record); val stamp = createViewRows(db, source)
        saveBuild(db, stamp.identity, LibrarySavedBuildRecord(record, revision, cut.entries.size, cut.prefixes.last()))
        LibrarySavedBuildSession(stamp.identity, revision, cut, mutableMapOf())
    }
    internal fun captureSavedViewBuild(identity: LibrarySavedViewIdentity): LibrarySavedBuildSession = transaction { db ->
        val (stamp, previous) = buildRecord(db, identity); val revision = buildRevision(db, identity.owner)
        val cut = LibrarySavedReplayCut.capture(readLocalAccount(db, identity.owner) ?: throw LibrarySyncFailure.SessionChanged, previous.source)
        if (previous.commandCount > cut.entries.size || cut.prefixes[previous.commandCount] != previous.cutDigest) throw LibrarySavedBuildChanged()
        var next = previous.copy(accountRevision = revision, commandCount = cut.entries.size, cutDigest = cut.prefixes.last())
        if (previous.commandCount != cut.entries.size && previous.phase !in listOf(LibrarySavedBuildPhase.Folders, LibrarySavedBuildPhase.FolderCommands)) {
            next = next.copy(phase = LibrarySavedBuildPhase.FolderCommands, commandNext = previous.commandCount, after = null, seen = LibrarySavedCounts(), manifest = null)
            db.execSQL("UPDATE saved_view_heads SET audit=NULL WHERE key=?", arrayOf(identity.key))
        }
        if (next != previous) saveBuild(db, identity, next)
        val prefix = identity.key + ":b:"; var after: String? = null; val bindings = mutableMapOf<Int, String>()
        while (true) {
            val rows = viewIndexPage(db, identity, prefix, after, 128)
            for ((key, target) in rows) {
                val index = key.removePrefix(prefix).toIntOrNull(16) ?: throw LibrarySyncFailure.InvalidReceipt
                if (index !in cut.entries.indices || key != bindingKey(identity, index) || LibrarySavedViewPolicy.target(cut.entries[index].operation.command) != null || cut.entries[index].operation.command.isPositionChange) throw LibrarySyncFailure.InvalidReceipt
                if (target.toByteArray().size > 1024) throw LibrarySyncFailure.InvalidReceipt
                val binding = viewJson.decodeFromString<LibrarySavedBuildBinding>(target); binding.validate(identity, index, cut)
                bindings[index] = binding.folder
            }
            if (rows.size < 128) break
            after = rows.last().first
        }
        if (bindings.size.toLong() != previous.bindings) throw LibrarySyncFailure.InvalidReceipt
        LibrarySavedBuildSession(stamp.identity, revision, cut, bindings)
    }
    private fun bindingKey(identity: LibrarySavedViewIdentity, index: Int) = identity.key + ":b:" + index.toString(16).padStart(16, '0')
    private fun checkBuild(db: SQLiteDatabase, session: LibrarySavedBuildSession): Pair<LibrarySavedViewStamp, LibrarySavedBuildRecord> {
        val value = buildRecord(db, session.identity)
        if (buildRevision(db, session.identity.owner) != session.revision || value.second.accountRevision != session.revision || value.second.commandCount != session.cut.entries.size || value.second.bindings != session.bindings.size.toLong() || value.second.cutDigest != session.cut.prefixes.last()) throw LibrarySavedBuildChanged()
        return value
    }
    internal fun savedViewBuildProgress(session: LibrarySavedBuildSession): Pair<LibrarySavedViewStamp, LibrarySavedBuildRecord> = transaction { checkBuild(it, session) }
    internal fun advanceSavedViewBuild(session: LibrarySavedBuildSession): LibrarySavedBuildRecord {
        synchronized(session) {
            val initial = transaction { checkBuild(it, session) }
            if (initial.second.phase == LibrarySavedBuildPhase.Prepared) return initial.second
            if (initial.second.phase == LibrarySavedBuildPhase.Audit) {
                beginSavedViewAudit(initial.first, initial.second.manifest ?: throw LibrarySyncFailure.InvalidReceipt)
                val audit = savedViewAuditStep(initial.first)
                return transaction { db ->
                    val (stamp, record) = checkBuild(db, session)
                    if (stamp != initial.first) throw LibrarySavedBuildChanged()
                    if (audit.phase != LibrarySavedViewAuditPhase.Verified) record else record.copy(phase = LibrarySavedBuildPhase.Prepared).also { saveBuild(db, session.identity, it) }
                }
            }
            val updates = mutableMapOf<Int, String>()
            val result = transaction { db ->
                var (stamp, record) = checkBuild(db, session); val identity = session.identity; val cut = session.cut
                fun put(item: LibrarySavedViewItem? = null, folder: SyncFolderRow? = null) {
                    var expected = record.expected
                    if (item != null) {
                        val old = viewRow(db, identity, identity.itemKey(item.value.hadithId), 1)
                        expected = expected.copy(items = expected.items + (if (item.mask != 0) 1 else 0) - (if (old != null) 1 else 0))
                        stamp = writeViewRows(db, stamp, listOf(item), preserveBuild = true)
                    } else if (folder != null) {
                        if (viewRow(db, identity, identity.folderKey(folder._id), 0) == null) expected = expected.copy(folders = expected.folders + 1)
                        stamp = writeViewRows(db, stamp, emptyList(), listOf(folder), preserveBuild = true)
                    }
                    record = record.copy(expected = expected)
                }
                fun folder(id: String): SyncFolderRow? = viewRow(db, identity, identity.folderKey(id), 0)?.let { viewJson.decodeFromString<SyncFolderRow>(it) }
                when (record.phase) {
                    LibrarySavedBuildPhase.Folders, LibrarySavedBuildPhase.Items -> {
                        val phase = record.phase; val rows = savedProjectionRows(db, record.source.lease, record.after)
                        for ((_, value) in rows) {
                            record = record.copy(seen = record.seen.adding(value))
                            if (phase == LibrarySavedBuildPhase.Folders && value is LibrarySavedProjection.Folder) put(folder = value.value)
                            if (phase == LibrarySavedBuildPhase.Items && value is LibrarySavedProjection.Item) put(item = cut.item(value.value, value.value.hadithId, session.bindings))
                        }
                        record = record.copy(after = rows.lastOrNull()?.first ?: record.after)
                        if (rows.size < savedStepLimit) {
                            if (record.seen != record.source.checkpoint.counts) throw LibrarySyncFailure.InvalidReceipt
                            record = record.copy(phase = if (phase == LibrarySavedBuildPhase.Folders) LibrarySavedBuildPhase.FolderCommands else LibrarySavedBuildPhase.PointTargets, after = null, commandNext = 0, seen = LibrarySavedCounts())
                        }
                    }
                    LibrarySavedBuildPhase.FolderCommands -> {
                        val end = record.commandNext + minOf(8, cut.entries.size - record.commandNext)
                        for (index in record.commandNext until end) {
                            val entry = cut.entries[index]; val command = entry.operation.command; val at = entry.operation.at
                            val resolved: String = when (command) {
                                is SyncCommand.FolderCreate -> {
                                    val id = cut.mappings[command.key] ?: "local:${command.key}"; if (folder(id) == null) put(folder = SyncFolderRow(id, command.name, at)); id
                                }
                                is SyncCommand.FolderDelete -> {
                                    val id = when (val ref = command.folder) { SyncFolderReference.None -> ""; is SyncFolderReference.Server -> ref.id; is SyncFolderReference.Local -> cut.mappings[ref.key] ?: "local:${ref.key}" }
                                    if (id.isNotEmpty()) folder(id)?.let { old ->
                                        for (prefix in listOf(identity.folderPrefix, identity.namePrefix(old.name))) db.delete("saved_view_indexes", "key=?", arrayOf(prefix + LibrarySavedViewPolicy.folderRank(old)))
                                        db.delete("saved_view_rows", "key=?", arrayOf(identity.folderKey(id))); record = record.copy(expected = record.expected.copy(folders = record.expected.folders - 1))
                                        if (stamp.serial >= 9_007_199_254_740_990L) throw LibrarySyncFailure.StoreUnavailable
                                        stamp = stamp.copy(serial = stamp.serial + 1); db.execSQL("UPDATE saved_view_heads SET serial=?,audit=NULL WHERE key=?", arrayOf<Any>(stamp.serial, identity.key))
                                    }; id
                                }
                                is SyncCommand.FolderRestore -> {
                                    val result = entry.outcome as? SyncOutcome.FolderRestored
                                    val match = viewIndexPage(db, identity, identity.namePrefix(command.name), null, 1).firstOrNull()?.second?.let { key -> viewRow(db, identity, key, 0)?.let { viewJson.decodeFromString<SyncFolderRow>(it) } }
                                    val id = result?.folderId ?: match?._id ?: cut.mappings["restore:${command.deletionId}"] ?: "local:restore:${command.deletionId}"
                                    if (folder(id) == null) put(folder = SyncFolderRow(id, command.name, at)); id
                                }
                                else -> continue
                            }
                            if (db.rawQuery("SELECT key FROM saved_view_indexes WHERE key=?", arrayOf(bindingKey(identity, index))).use { it.moveToFirst() }) throw LibrarySyncFailure.InvalidReceipt
                            val binding = LibrarySavedBuildBinding.make(identity, index, cut, resolved); binding.validate(identity, index, cut)
                            viewIndex(db, identity, bindingKey(identity, index), viewJson.encodeToString(binding)); updates[index] = resolved; record = record.copy(bindings = record.bindings + 1)
                        }
                        record = record.copy(commandNext = end)
                        if (end == cut.entries.size) record = record.copy(phase = LibrarySavedBuildPhase.Items, commandNext = 0, after = null, seen = LibrarySavedCounts())
                    }
                    LibrarySavedBuildPhase.PointTargets -> {
                        val end = record.commandNext + minOf(8, cut.entries.size - record.commandNext)
                        for (index in record.commandNext until end) {
                            val target = LibrarySavedViewPolicy.target(cut.entries[index].operation.command) ?: continue
                            val base = savedProjection(db, record.source.lease, record.source.lease.collection + ":r:" + LibraryOutcomeBinding.hash(listOf("item", target)))
                            if (base != null && base !is LibrarySavedProjection.Item) throw LibrarySyncFailure.InvalidReceipt
                            put(item = cut.item((base as? LibrarySavedProjection.Item)?.value, target, session.bindings))
                        }
                        record = record.copy(commandNext = end)
                        if (end == cut.entries.size) record = record.copy(phase = LibrarySavedBuildPhase.Manifest, after = null, manifest = LibrarySavedViewManifest(0, 0, record.bindings, LibrarySavedViewManifest.initialDigest, record.bindings))
                    }
                    LibrarySavedBuildPhase.Manifest -> {
                        var manifest = record.manifest ?: throw LibrarySyncFailure.InvalidReceipt
                        val prefix = identity.key + ":"; val rows = db.rawQuery("SELECT key,kind FROM saved_view_rows WHERE key>? AND key<? ORDER BY key LIMIT 8", arrayOf(record.after ?: prefix, prefix + "~")).use { cursor ->
                            buildList { while (cursor.moveToNext()) { if (cursor.getType(1) != android.database.Cursor.FIELD_TYPE_INTEGER || cursor.getLong(1) !in 0..1L) throw LibrarySyncFailure.StoreUnavailable; add(cursor.getString(0) to cursor.getInt(1)) } }
                        }
                        for ((key, kind) in rows) {
                            val data = viewRow(db, identity, key, kind) ?: throw LibrarySyncFailure.StoreUnavailable
                            val indexes = if (kind == 1) LibrarySavedViewPolicy.indexKeys(identity, viewJson.decodeFromString<LibrarySavedViewItem>(data)).size else 2
                            manifest = manifest.copy(items = manifest.items + if (kind == 1) 1 else 0, folders = manifest.folders + if (kind == 0) 1 else 0, indexes = manifest.indexes + indexes, digest = LibraryOutcomeBinding.hash(listOf(manifest.digest, key, librarySemanticDigest(viewJson.parseToJsonElement(data), "saved-view-row-v1:"))))
                        }
                        record = record.copy(after = rows.lastOrNull()?.first ?: record.after, manifest = manifest)
                        if (rows.size < 8) {
                            if (manifest.items != record.expected.items || manifest.folders != record.expected.folders) throw LibrarySyncFailure.InvalidReceipt
                            record = record.copy(phase = LibrarySavedBuildPhase.Audit, after = null)
                        }
                    }
                    else -> throw LibrarySyncFailure.InvalidChange
                }
                saveBuild(db, identity, record); record
            }
            session.bindings.putAll(updates); return result
        }
    }
    private fun viewAudit(db: SQLiteDatabase, stamp: LibrarySavedViewStamp): LibrarySavedViewAudit? {
        if (viewHead(db, stamp.identity) != stamp) throw LibrarySavedViewChanged()
        return db.rawQuery("SELECT audit FROM saved_view_heads WHERE key=?", arrayOf(stamp.identity.key)).use {
            if (!it.moveToFirst()) throw LibrarySyncFailure.StoreUnavailable
            if (it.isNull(0)) null else {
                if (it.getString(0).toByteArray().size > 16_384) throw LibrarySyncFailure.StoreUnavailable
                viewJson.decodeFromString<LibrarySavedViewAudit>(it.getString(0)).also { audit -> audit.validate(stamp) }
            }
        }
    }
    internal fun savedViewAudit(stamp: LibrarySavedViewStamp): LibrarySavedViewAudit? = transaction { viewAudit(it, stamp) }
    private fun saveViewAudit(db: SQLiteDatabase, stamp: LibrarySavedViewStamp, audit: LibrarySavedViewAudit): LibrarySavedViewAudit {
        audit.validate(stamp)
        if (db.update("saved_view_heads", ContentValues().apply { put("audit", viewJson.encodeToString(audit)) }, "key=?", arrayOf(stamp.identity.key)) != 1) throw LibrarySyncFailure.StoreUnavailable
        bumpClock(db, stamp.identity.owner.subject, stamp.identity.owner.namespace); return audit
    }
    internal fun beginSavedViewAudit(stamp: LibrarySavedViewStamp, manifest: LibrarySavedViewManifest): LibrarySavedViewAudit = transaction { db ->
        manifest.validate()
        val existing = viewAudit(db, stamp)
        if (existing != null) {
            if (existing.manifest != manifest) throw LibrarySyncFailure.InvalidChange
            existing
        } else saveViewAudit(db, stamp, LibrarySavedViewAudit(stamp.serial, manifest))
    }
    /** Each transaction checks at most eight private rows or 128 small index entries. */
    internal fun savedViewAuditStep(stamp: LibrarySavedViewStamp): LibrarySavedViewAudit = transaction { db ->
        var audit = viewAudit(db, stamp) ?: throw LibrarySyncFailure.InvalidChange
        if (audit.phase == LibrarySavedViewAuditPhase.Verified) return@transaction audit
        val identity = stamp.identity; val prefix = identity.key + ":"; val upper = prefix + "~"
        if (audit.phase == LibrarySavedViewAuditPhase.Rows) {
            val rows = db.rawQuery("SELECT key,kind FROM saved_view_rows WHERE key>? AND key<? ORDER BY key LIMIT 8", arrayOf(audit.after ?: prefix, upper)).use { cursor ->
                buildList { while (cursor.moveToNext()) {
                    if (cursor.getType(1) != android.database.Cursor.FIELD_TYPE_INTEGER || cursor.getLong(1) !in 0..1L) throw LibrarySyncFailure.StoreUnavailable
                    add(cursor.getString(0) to cursor.getInt(1))
                } }
            }
            for ((key, kind) in rows) {
                val data = viewRow(db, identity, key, kind) ?: throw LibrarySyncFailure.StoreUnavailable
                val keys = if (kind == 1) {
                    val item = viewJson.decodeFromString<LibrarySavedViewItem>(data)
                    if (item.mask == 0) throw LibrarySyncFailure.StoreUnavailable
                    audit = audit.copy(items = audit.items + 1)
                    LibrarySavedViewPolicy.indexKeys(identity, item)
                } else {
                    val folder = viewJson.decodeFromString<SyncFolderRow>(data); audit = audit.copy(folders = audit.folders + 1)
                    setOf(identity.folderPrefix + LibrarySavedViewPolicy.folderRank(folder), identity.namePrefix(folder.name) + LibrarySavedViewPolicy.folderRank(folder))
                }
                for (index in keys) db.rawQuery("SELECT view_key,subject,namespace,owner_key,target_key FROM saved_view_indexes WHERE key=?", arrayOf(index)).use {
                    if (!it.moveToFirst() || it.getString(0) != identity.key || it.getString(1) != identity.owner.subject || it.getString(2) != identity.owner.namespace || it.getString(3) != identity.owner.storageKey || it.getString(4) != key) throw LibrarySyncFailure.StoreUnavailable
                }
                audit = audit.copy(after = key, digest = LibraryOutcomeBinding.hash(listOf(audit.digest, key, librarySemanticDigest(viewJson.parseToJsonElement(data), "saved-view-row-v1:"))))
            }
            if (rows.size < 8) audit = audit.copy(phase = LibrarySavedViewAuditPhase.Indexes, after = null)
        } else {
            val keys = db.rawQuery("SELECT key,view_key,subject,namespace,owner_key FROM saved_view_indexes WHERE key>? AND key<? ORDER BY key LIMIT 128", arrayOf(audit.after ?: prefix, upper)).use { cursor ->
                buildList { while (cursor.moveToNext()) {
                    if (cursor.getString(1) != identity.key || cursor.getString(2) != identity.owner.subject || cursor.getString(3) != identity.owner.namespace || cursor.getString(4) != identity.owner.storageKey) throw LibrarySyncFailure.OwnerMismatch
                    add(cursor.getString(0))
                } }
            }
            audit = audit.copy(indexes = audit.indexes + keys.size, after = keys.lastOrNull() ?: audit.after)
            if (keys.size < 128) audit = audit.copy(phase = LibrarySavedViewAuditPhase.Verified, after = null)
        }
        saveViewAudit(db, stamp, audit)
    }
    /** Draft-only discard. Mark first so interrupted cleanup can never be read as empty. */
    internal fun discardSavedViewStep(stamp: LibrarySavedViewStamp): Boolean = transaction { db ->
        val identity = stamp.identity
        assertLocalOwner(db, identity.owner)
        if (currentSavedScope(db, identity.owner)?.first?.epoch != identity.epoch) throw LibrarySyncFailure.SessionChanged
        val present = db.rawQuery("SELECT key FROM saved_view_heads WHERE key=?", arrayOf(identity.key)).use { it.moveToFirst() }
        if (!present) return@transaction false
        if (viewHead(db, identity, allowRetiring = true) != stamp) throw LibrarySavedViewChanged()
        db.execSQL("UPDATE saved_view_heads SET retiring=1,audit=NULL WHERE key=?", arrayOf(identity.key))
        val prefix = identity.key + ":"; val upper = prefix + "~"
        for ((table, limit) in listOf("saved_view_indexes" to 128, "saved_view_rows" to 8)) {
            val removed = db.delete(table, "key IN (SELECT key FROM $table WHERE key>? AND key<? ORDER BY key LIMIT $limit)", arrayOf(prefix, upper))
            if (removed > 0) { bumpClock(db, identity.owner.subject, identity.owner.namespace); return@transaction true }
        }
        db.delete("saved_view_heads", "key=?", arrayOf(identity.key)); bumpClock(db, identity.owner.subject, identity.owner.namespace); false
    }
    internal fun draftSavedViewItem(stamp: LibrarySavedViewStamp, target: String): LibrarySavedViewItem? = transaction { db ->
        if (viewHead(db, stamp.identity) != stamp) throw LibrarySavedViewChanged()
        viewRow(db, stamp.identity, stamp.identity.itemKey(target), 1)?.let { viewJson.decodeFromString<LibrarySavedViewItem>(it).also { row -> row.validate(); if (row.value.hadithId != target) throw LibrarySyncFailure.StoreUnavailable } }
    }
    internal fun draftSavedViewFolder(stamp: LibrarySavedViewStamp, target: String): SyncFolderRow? = transaction { db ->
        if (viewHead(db, stamp.identity) != stamp) throw LibrarySavedViewChanged()
        viewRow(db, stamp.identity, stamp.identity.folderKey(target), 0)?.let { viewJson.decodeFromString<SyncFolderRow>(it).also { row -> if (row._id != target) throw LibrarySyncFailure.StoreUnavailable; LibrarySavedPolicy.validate(SavedFact.Folder(row._id, 0.0, row)) } }
    }
    private fun viewIndexPage(db: SQLiteDatabase, identity: LibrarySavedViewIdentity, prefix: String, after: String?, limit: Int): List<Pair<String, String>> {
        if (after != null && !after.startsWith(prefix)) throw LibrarySavedViewChanged()
        val values = mutableListOf<Pair<String, String>>()
        db.rawQuery("SELECT key,view_key,subject,namespace,owner_key,target_key FROM saved_view_indexes WHERE key>? AND key<? ORDER BY key LIMIT ?", arrayOf(after ?: prefix, prefix + "~", limit.toString())).use {
            while (it.moveToNext()) {
                if (it.getString(1) != identity.key || it.getString(2) != identity.owner.subject || it.getString(3) != identity.owner.namespace || it.getString(4) != identity.owner.storageKey) throw LibrarySyncFailure.StoreUnavailable
                values.add(it.getString(0) to it.getString(5))
            }
        }; return values
    }
    internal fun draftSavedViewPage(stamp: LibrarySavedViewStamp, selection: LibrarySavedViewSelection, ticket: LibrarySavedViewTicket? = null, limit: Int = 32): LibrarySavedViewPage = transaction { db ->
        selection.validate()
        if (limit !in 1..32) throw LibrarySyncFailure.InvalidChange
        if (ticket != null && ticket.stamp.identity.owner != stamp.identity.owner) throw LibrarySyncFailure.OwnerMismatch
        if (viewHead(db, stamp.identity) != stamp || ticket != null && (ticket.stamp != stamp || ticket.selection != selection)) throw LibrarySavedViewChanged()
        val prefix = stamp.identity.queryPrefix(selection)
        val entries = viewIndexPage(db, stamp.identity, prefix, ticket?.after, limit + 1)
        val values = entries.take(limit).map { (key, target) ->
            val row = viewJson.decodeFromString<LibrarySavedViewItem>(viewRow(db, stamp.identity, target, 1) ?: throw LibrarySyncFailure.StoreUnavailable)
            if (target != stamp.identity.itemKey(row.value.hadithId) || key != prefix + LibrarySavedViewPolicy.rank(row.value) || !LibrarySavedViewPolicy.matches(row, selection)) throw LibrarySyncFailure.StoreUnavailable
            row
        }
        val unknown = selection.collection != null && viewIndexPage(db, stamp.identity, stamp.identity.queryPrefix(selection.copy(collection = null), true), null, 1).isNotEmpty()
        LibrarySavedViewPage(stamp, values, if (entries.size > limit) LibrarySavedViewTicket(stamp, selection, entries[limit - 1].first) else null, unknown)
    }
    internal fun draftSavedViewFolders(stamp: LibrarySavedViewStamp, ticket: LibrarySavedViewFolderTicket? = null, limit: Int = 32, name: String? = null): LibrarySavedViewFolderPage = transaction { db ->
        if (limit !in 1..32) throw LibrarySyncFailure.InvalidChange
        if (ticket != null && ticket.stamp.identity.owner != stamp.identity.owner) throw LibrarySyncFailure.OwnerMismatch
        if (viewHead(db, stamp.identity) != stamp || ticket != null && (ticket.stamp != stamp || ticket.name != name)) throw LibrarySavedViewChanged()
        val entries = viewIndexPage(db, stamp.identity, name?.let(stamp.identity::namePrefix) ?: stamp.identity.folderPrefix, ticket?.after, limit + 1)
        val rows = entries.take(limit).map { (key, target) ->
            val row = viewJson.decodeFromString<SyncFolderRow>(viewRow(db, stamp.identity, target, 0) ?: throw LibrarySyncFailure.StoreUnavailable)
            LibrarySavedPolicy.validate(SavedFact.Folder(row._id, 0.0, row))
            if (target != stamp.identity.folderKey(row._id) || key != (name?.let(stamp.identity::namePrefix) ?: stamp.identity.folderPrefix) + LibrarySavedViewPolicy.folderRank(row) || name != null && LibrarySavedViewPolicy.nameKey(row.name) != LibrarySavedViewPolicy.nameKey(name)) throw LibrarySyncFailure.StoreUnavailable
            row
        }
        LibrarySavedViewFolderPage(stamp, rows, if (entries.size > limit) LibrarySavedViewFolderTicket(stamp, name, entries[limit - 1].first) else null)
    }

}

@ConsistentCopyVisibility
data class LibrarySavedActiveGeneration internal constructor(val lease: LibrarySavedLease, val version: Double) {
    internal constructor(record: LibrarySavedGenerationRecord) : this(record.lease, record.checkpoint.position?.version ?: throw LibrarySyncFailure.StoreUnavailable) {
        if (record.checkpoint.stage != LibrarySavedStage.Prepared) throw LibrarySyncFailure.StoreUnavailable
    }
}
sealed interface LibrarySavedActivation {
    data class Active(val handle: LibrarySavedActiveGeneration) : LibrarySavedActivation
    data object Restart : LibrarySavedActivation
    data class Unavailable(val reason: SavedFactsReplyUnavailableReason) : LibrarySavedActivation

}
