package com.hadithly.app.core.data

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest
import java.util.UUID

@Serializable
data class GuestSnapshot(
    val bookmarks: List<GuestBookmarkDraft> = emptyList(),
    val favorites: List<GuestFavoriteDraft> = emptyList(),
    val notes: List<GuestNoteDraft> = emptyList(),
    val progress: List<GuestReadingProgressDraft> = emptyList(),
    val savedFolders: List<GuestSavedFolderDraft> = emptyList(),
    val savedMemberships: List<GuestSavedMembership> = emptyList(),
)

private val localJson = Json { encodeDefaults = true; explicitNulls = false }
internal const val LOCAL_STORE_BATCH = 8
private const val PAYLOAD_WINDOW = 32 * 1024
private fun digest(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
private fun utf8(bytes: ByteArray): String = try {
    Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
} catch (_: Exception) { throw LibrarySyncFailure.StoreUnavailable }
private inline fun <reified T> encoded(value: T) = localJson.encodeToString(value).toByteArray(Charsets.UTF_8)
private inline fun <reified T> decoded(bytes: ByteArray): T = try { localJson.decodeFromString(utf8(bytes)) } catch (_: Exception) { throw LibrarySyncFailure.StoreUnavailable }
private fun ownerFromLegacy(partition: LibrarySyncPartition): LibrarySyncOwner {
    val cut = partition.ownerKey.indexOf('|')
    if (cut <= 0 || cut == partition.ownerKey.lastIndex || partition.ownerKey.indexOf('|', cut + 1) >= 0) throw LibrarySyncFailure.StoreUnavailable
    return LibrarySyncOwner(partition.ownerKey.substring(cut + 1), partition.subject, partition.ownerKey.substring(0, cut)).also(::validateOwner)
}
private fun validateOwner(owner: LibrarySyncOwner) {
    if (listOf(owner.key, owner.subject, owner.namespace).any { it.isEmpty() || it.toByteArray().size > 1_024 } || '|' in owner.key || '|' in owner.namespace) throw LibrarySyncFailure.OwnerMismatch
}
internal fun localDeletionKey(subject: String, namespace: String) = LibraryOutcomeBinding.hash(listOf(namespace, subject))
internal fun createLocalStoreSchema(db: SQLiteDatabase) {
    db.execSQL("CREATE TABLE local_import (id INTEGER PRIMARY KEY CHECK(id=1), import_id TEXT NOT NULL, source_hash TEXT NOT NULL, source_present INTEGER NOT NULL, source_size INTEGER NOT NULL, source BLOB, original BLOB, original_hash TEXT NOT NULL, phase TEXT NOT NULL, next INTEGER NOT NULL, table_index INTEGER NOT NULL, after_key TEXT NOT NULL, seen INTEGER NOT NULL)")
    db.execSQL("CREATE TABLE local_import_rows (ordinal INTEGER PRIMARY KEY CHECK(ordinal>=0), kind TEXT NOT NULL, key_hash TEXT NOT NULL, fingerprint TEXT NOT NULL)")
    db.execSQL("CREATE TABLE local_guest (key TEXT PRIMARY KEY CHECK(key='guest'), revision INTEGER NOT NULL, size INTEGER NOT NULL, digest TEXT NOT NULL, payload BLOB NOT NULL)")
    db.execSQL("CREATE TABLE local_accounts (key TEXT PRIMARY KEY NOT NULL, subject TEXT NOT NULL, namespace TEXT NOT NULL, owner_key TEXT NOT NULL, revision INTEGER NOT NULL, size INTEGER NOT NULL, digest TEXT NOT NULL, payload BLOB NOT NULL)")
    db.execSQL("CREATE INDEX local_accounts_scope ON local_accounts(subject,namespace,key)")
    db.execSQL("CREATE TABLE local_deletions (key TEXT PRIMARY KEY NOT NULL, subject TEXT NOT NULL, namespace TEXT NOT NULL, phase TEXT NOT NULL)")
}
internal fun requireLocalReady(db: SQLiteDatabase) {
    db.rawQuery("SELECT phase FROM local_import WHERE id=1", null).use { if (!it.moveToFirst() || it.getString(0) != "ready") throw LibrarySyncFailure.StoreUnavailable }
}
internal fun localScopeDeleting(db: SQLiteDatabase, subject: String, namespace: String): Boolean =
    db.rawQuery("SELECT subject,namespace FROM local_deletions WHERE key=?", arrayOf(localDeletionKey(subject, namespace))).use {
        if (!it.moveToFirst()) false else { if (it.getString(0) != subject || it.getString(1) != namespace) throw LibrarySyncFailure.OwnerMismatch; true }
    }
internal fun hasLocalAccountRows(db: SQLiteDatabase, subject: String, namespace: String): Boolean =
    db.rawQuery("SELECT 1 FROM local_accounts WHERE subject=? AND namespace=? LIMIT 1", arrayOf(subject, namespace)).use { it.moveToFirst() }

// BLOB substr windows avoid Android's CursorWindow row-size ceiling. An owned
// payload is still decoded as a whole; queue/guest byte scalability is separate.
private fun readPayload(db: SQLiteDatabase, table: String, key: String): Pair<Long, ByteArray>? {
    val metadata = db.rawQuery("SELECT revision,size,digest,length(payload) FROM $table WHERE key=?", arrayOf(key)).use {
        if (!it.moveToFirst()) null else {
            val revision = it.getLong(0); val size = it.getLong(1)
            if (revision !in 0 until 9_007_199_254_740_991L || size !in 0..Int.MAX_VALUE.toLong() || size != it.getLong(3)) throw LibrarySyncFailure.StoreUnavailable
            Triple(revision, size.toInt(), it.getString(2))
        }
    } ?: return null
    val output = ByteArrayOutputStream(minOf(metadata.second, PAYLOAD_WINDOW)); var offset = 0
    while (offset < metadata.second) {
        val expected = minOf(PAYLOAD_WINDOW, metadata.second - offset)
        db.rawQuery("SELECT substr(payload,?,?) FROM $table WHERE key=?", arrayOf((offset + 1).toString(), expected.toString(), key)).use {
            if (!it.moveToFirst()) throw LibrarySyncFailure.StoreUnavailable
            val bytes = it.getBlob(0); if (bytes.size != expected) throw LibrarySyncFailure.StoreUnavailable; output.write(bytes)
        }; offset += expected
    }
    val value = output.toByteArray(); if (digest(value) != metadata.third) throw LibrarySyncFailure.StoreUnavailable
    return metadata.first to value
}
private fun writePayload(db: SQLiteDatabase, table: String, key: String, revision: Long, bytes: ByteArray, owner: LibrarySyncOwner? = null) {
    if (revision !in 0 until 9_007_199_254_740_991L) throw LibrarySyncFailure.StoreUnavailable
    val values = ContentValues().apply {
        put("key", key); put("revision", revision); put("size", bytes.size); put("digest", digest(bytes)); put("payload", bytes)
        if (owner != null) { put("subject", owner.subject); put("namespace", owner.namespace); put("owner_key", owner.key) }
    }
    if (db.update(table, values, "key=?", arrayOf(key)) == 0) db.insertOrThrow(table, null, values)
}
private fun guest(db: SQLiteDatabase): Pair<Long, GuestSnapshot> {
    val stored = readPayload(db, "local_guest", "guest") ?: throw LibrarySyncFailure.StoreUnavailable
    return stored.first to decoded<GuestSnapshot>(stored.second)
}
internal fun readLocalAccount(db: SQLiteDatabase, owner: LibrarySyncOwner): LibraryPartitionState? {
    validateOwner(owner)
    val exists = db.rawQuery("SELECT subject,namespace,owner_key FROM local_accounts WHERE key=?", arrayOf(owner.storageKey)).use {
        if (!it.moveToFirst()) false else {
            if (it.getString(0) != owner.subject || it.getString(1) != owner.namespace || it.getString(2) != owner.key) throw LibrarySyncFailure.OwnerMismatch
            true
        }
    }
    if (!exists) return null
    return decoded((readPayload(db, "local_accounts", owner.storageKey) ?: throw LibrarySyncFailure.StoreUnavailable).second)
}
internal fun assertLocalOwner(db: SQLiteDatabase, owner: LibrarySyncOwner) {
    validateOwner(owner)
    if (localScopeDeleting(db, owner.subject, owner.namespace)) throw LibrarySyncFailure.AccountDeleting
    db.rawQuery("SELECT subject,namespace,owner_key FROM local_accounts WHERE key=?", arrayOf(owner.storageKey)).use {
        if (!it.moveToFirst()) throw LibrarySyncFailure.SessionChanged
        if (it.getString(0) != owner.subject || it.getString(1) != owner.namespace || it.getString(2) != owner.key) throw LibrarySyncFailure.OwnerMismatch
    }
}
private fun LibraryOutcomeJournal.writeAccount(db: SQLiteDatabase, owner: LibrarySyncOwner, state: LibraryPartitionState, create: Boolean = false) {
    val old = readPayload(db, "local_accounts", owner.storageKey); val bytes = encoded(state)
    if (old == null && !create) throw LibrarySyncFailure.SessionChanged
    if (old != null && bytes.contentEquals(old.second)) return
    writePayload(db, "local_accounts", owner.storageKey, (old?.first ?: -1) + 1, bytes, owner)
    bumpClock(db, owner.subject, owner.namespace)
}
internal fun LibraryOutcomeJournal.localGuest(): GuestSnapshot = transaction { guest(it).second }
internal fun LibraryOutcomeJournal.updateLocalGuest(transform: (GuestSnapshot) -> GuestSnapshot): Boolean = transaction { db ->
    val (revision, current) = guest(db); val next = transform(current)
    if (next == current) false else { writePayload(db, "local_guest", "guest", revision + 1, encoded(next)); true }
}
internal fun LibraryOutcomeJournal.localAccount(owner: LibrarySyncOwner): LibraryPartitionState? = transaction { readLocalAccount(it, owner) }
internal fun <T> LibraryOutcomeJournal.mutateLocalAccount(owner: LibrarySyncOwner, block: (SQLiteDatabase, LibraryPartitionState) -> T): T = transaction { db ->
    assertLocalOwner(db, owner)
    val state = readLocalAccount(db, owner) ?: throw LibrarySyncFailure.SessionChanged
    val result = block(db, state); writeAccount(db, owner, state); result
}
private fun appendGuest(guest: GuestSnapshot, state: LibraryPartitionState) {
    for (draft in guest.savedFolders) {
        val name = draft.name.trim()
        state.append(LibraryLocalSource.Folder(draft), if (name.isNotEmpty() && name.codePointCount(0, name.length) <= LibrarySyncLimits.folderLength && name.none { Character.isISOControl(it) }) SyncCommand.FolderCreate(draft.localId, draft.name, SyncCommandFolderCreatePurpose.GUEST_CLAIM) else null, draft.createdAt)
    }
    for (draft in guest.bookmarks) state.append(LibraryLocalSource.Bookmark(draft), SyncCommand.BookmarkAdd(draft.hadithId, draft.createdAt), draft.createdAt)
    for (draft in guest.favorites) state.append(LibraryLocalSource.Favorite(draft), SyncCommand.FavoriteAdd(draft.hadithId, draft.createdAt), draft.createdAt)
    for (draft in guest.notes) state.append(LibraryLocalSource.Note(draft), if (draft.content.isNotEmpty() && draft.content.toByteArray().size <= LibrarySyncLimits.noteBytes) SyncCommand.NotePut(draft.hadithId, draft.content, draft.createdAt, draft.updatedAt) else null, draft.updatedAt)
    for (draft in guest.savedMemberships) state.append(LibraryLocalSource.Membership(draft), SyncCommand.MembershipPut(draft.hadithId, SyncFolderReference.Local(draft.folderLocalId), if (draft.updatedAt == null) "claim_if_unset" else null), draft.updatedAt ?: 0.0)
    for (draft in guest.progress) state.append(LibraryLocalSource.Position(draft), draft.readingPosition?.let { SyncCommand.PositionPut(it) } ?: SyncCommand.LegacyPositionPut(draft.hadithId, draft.updatedAt), draft.effectiveUpdatedAt)
}
internal fun LibraryOutcomeJournal.claimLocalGuest(owner: LibrarySyncOwner) = transaction { db ->
    validateOwner(owner); if (localScopeDeleting(db, owner.subject, owner.namespace)) throw LibrarySyncFailure.AccountDeleting
    val current = readLocalAccount(db, owner); val state = current ?: LibraryPartitionState(); val (revision, snapshot) = guest(db)
    appendGuest(snapshot, state); writeAccount(db, owner, state, create = current == null)
    if (snapshot != GuestSnapshot()) writePayload(db, "local_guest", "guest", revision + 1, encoded(GuestSnapshot()))
}
internal fun LibraryOutcomeJournal.localDeletion(subject: String, namespace: String): LibraryDeletionPhase? = transaction { db ->
    db.rawQuery("SELECT subject,namespace,phase FROM local_deletions WHERE key=?", arrayOf(localDeletionKey(subject, namespace))).use {
        if (!it.moveToFirst()) null else {
            if (it.getString(0) != subject || it.getString(1) != namespace) throw LibrarySyncFailure.OwnerMismatch
            val phase = try { LibraryDeletionPhase.valueOf(it.getString(2)) } catch (_: Exception) { throw LibrarySyncFailure.StoreUnavailable }
            if (phase == LibraryDeletionPhase.IDENTITY_PENDING) assertErasedScope(db, subject, namespace)
            phase
        }
    }
}
private fun putDeletion(db: SQLiteDatabase, intent: LibraryDeletionIntent) {
    db.insertOrThrow("local_deletions", null, ContentValues().apply { put("key", localDeletionKey(intent.subject, intent.namespace)); put("subject", intent.subject); put("namespace", intent.namespace); put("phase", intent.phase.name) })
}
internal fun LibraryOutcomeJournal.beginLocalDeletion(subject: String, namespace: String) = transaction { db ->
    if (!localScopeDeleting(db, subject, namespace)) putDeletion(db, LibraryDeletionIntent(subject, namespace, LibraryDeletionPhase.SERVER_PENDING))
    bumpClock(db, subject, namespace, erasing = true)
}
internal fun LibraryOutcomeJournal.eraseLocalAccountsStep(subject: String, namespace: String): Boolean = transaction { db ->
    if (!localScopeDeleting(db, subject, namespace)) throw LibrarySyncFailure.SessionChanged
    val count = db.delete("local_accounts", "key IN (SELECT key FROM local_accounts WHERE subject=? AND namespace=? ORDER BY key LIMIT 8)", arrayOf(subject, namespace))
    if (count > 0) bumpClock(db, subject, namespace, erasing = true)
    count > 0
}
private fun assertErasedScope(db: SQLiteDatabase, subject: String, namespace: String) {
    for (table in listOf("local_accounts", "saved_assemblies", "saved_facts", "saved_pages", "saved_projection", "scopes", "headers", "export_artifacts")) {
        db.rawQuery("SELECT 1 FROM $table WHERE subject=? AND namespace=? LIMIT 1", arrayOf(subject, namespace)).use { if (it.moveToFirst()) throw LibrarySyncFailure.StoreUnavailable }
    }
}
internal fun LibraryOutcomeJournal.finishLocalDeletion(subject: String, namespace: String) = transaction { db ->
    if (!localScopeDeleting(db, subject, namespace)) throw LibrarySyncFailure.SessionChanged
    assertErasedScope(db, subject, namespace)
    db.update("local_deletions", ContentValues().apply { put("phase", LibraryDeletionPhase.IDENTITY_PENDING.name) }, "key=?", arrayOf(localDeletionKey(subject, namespace)))
}
internal fun LibraryOutcomeJournal.clearLocalDeletion(subject: String, namespace: String) = transaction { db ->
    val key = localDeletionKey(subject, namespace)
    db.rawQuery("SELECT phase FROM local_deletions WHERE key=?", arrayOf(key)).use {
        if (!it.moveToFirst()) return@transaction
        if (it.getString(0) != LibraryDeletionPhase.IDENTITY_PENDING.name) throw LibrarySyncFailure.AccountDeleting
    }
    assertErasedScope(db, subject, namespace)
    db.delete("local_deletions", "key=?", arrayOf(key)); db.delete("export_clocks", "scope_key=?", arrayOf(key)); Unit
}
internal fun LibraryOutcomeJournal.removeLocalAccountForTesting(owner: LibrarySyncOwner) = transaction { db ->
    val state = readLocalAccount(db, owner)
    if (state != null) { db.delete("local_accounts", "key=?", arrayOf(owner.storageKey)); bumpClock(db, owner.subject, owner.namespace) }
}

internal class LocalImportSource(val id: String, val bytes: ByteArray, val present: Boolean, val originalHash: String, initial: GuestStoreFile? = null) {
    val fingerprint = digest(bytes)
    val legacy = initial ?: decoded<GuestStoreFile>(bytes)
    val guest = GuestSnapshot(legacy.bookmarks, legacy.favorites, legacy.notes, legacy.progress, legacy.savedFolders, legacy.savedMemberships)
    val accounts = linkedMapOf<String, Pair<LibrarySyncOwner, LibraryPartitionState>>()
    val deletions = linkedMapOf<String, LibraryDeletionIntent>()
    val count get() = 1 + legacy.deletions.size + legacy.syncPartitions.size
    val uniqueCount get() = 1 + accounts.size + deletions.size
    init {
        for (partition in legacy.syncPartitions) {
            val owner = ownerFromLegacy(partition); val previous = accounts.putIfAbsent(owner.storageKey, owner to partition.state)
            if (previous != null && previous != (owner to partition.state)) throw LibrarySyncFailure.StoreUnavailable
        }
        for (intent in legacy.deletions) {
            if (intent.subject.isEmpty() || intent.namespace.isEmpty()) throw LibrarySyncFailure.StoreUnavailable
            val previous = deletions.putIfAbsent(localDeletionKey(intent.subject, intent.namespace), intent)
            if (previous != null && previous != intent) throw LibrarySyncFailure.StoreUnavailable
        }
    }
    fun entry(ordinal: Int): LocalImportEntry = when {
        ordinal == 0 -> LocalImportEntry("guest", "guest", encoded(guest))
        ordinal <= legacy.deletions.size -> legacy.deletions[ordinal - 1].let { LocalImportEntry("deletion", localDeletionKey(it.subject, it.namespace), encoded(it)) }
        ordinal < count -> legacy.syncPartitions[ordinal - 1 - legacy.deletions.size].let { LocalImportEntry("account", it.ownerKey, encoded(it)) }
        else -> throw LibrarySyncFailure.StoreUnavailable
    }
}
internal data class LocalImportEntry(val kind: String, val key: String, val payload: ByteArray) { val fingerprint get() = digest(payload) }
private fun importSourceBytes(db: SQLiteDatabase, size: Int): ByteArray {
    val output = ByteArrayOutputStream(minOf(size, PAYLOAD_WINDOW)); var offset = 0
    while (offset < size) {
        val length = minOf(PAYLOAD_WINDOW, size - offset)
        db.rawQuery("SELECT substr(source,?,?) FROM local_import WHERE id=1", arrayOf((offset + 1).toString(), length.toString())).use {
            if (!it.moveToFirst()) throw LibrarySyncFailure.StoreUnavailable
            val bytes = it.getBlob(0); if (bytes.size != length) throw LibrarySyncFailure.StoreUnavailable; output.write(bytes)
        }; offset += length
    }; return output.toByteArray()
}
internal fun LibraryOutcomeJournal.localImportSource(load: () -> ByteArray?): LocalImportSource? = transaction(allowUnready = true) { db ->
    val existing = db.rawQuery("SELECT phase,import_id,source_hash,source_present,source_size,original_hash,length(source) FROM local_import WHERE id=1", null).use {
        if (!it.moveToFirst()) null else {
            if (it.getString(0) == "ready") return@transaction null
            val size = it.getLong(4); if (size !in 0..Int.MAX_VALUE.toLong() || size != it.getLong(6)) throw LibrarySyncFailure.StoreUnavailable
            arrayOf(it.getString(1), it.getString(2), it.getString(3), size.toString(), it.getString(5))
        }
    }
    if (existing != null) {
        val source = LocalImportSource(existing[0], importSourceBytes(db, existing[3].toInt()), existing[2] == "1", existing[4])
        if (source.fingerprint != existing[1]) throw LibrarySyncFailure.StoreUnavailable
        source
    } else {
        val raw = load(); val original = raw ?: "{}".toByteArray(); val legacy = decoded<GuestStoreFile>(original)
        val source = LocalImportSource(UUID.randomUUID().toString(), encoded(legacy), raw != null, digest(original), legacy)
        db.insertOrThrow("local_import", null, ContentValues().apply {
            put("id", 1); put("import_id", source.id); put("source_hash", source.fingerprint); put("source_present", if (source.present) 1 else 0); put("source_size", source.bytes.size); put("source", source.bytes); put("original", original); put("original_hash", source.originalHash)
            put("phase", "staging"); put("next", 0); put("table_index", 0); put("after_key", ""); put("seen", 0)
        }); source
    }
}
private fun checkImportEntry(db: SQLiteDatabase, source: LocalImportSource, entry: LocalImportEntry) {
    when (entry.kind) {
        "guest" -> if (guest(db).second != source.guest) throw LibrarySyncFailure.StoreUnavailable
        "deletion" -> {
            val expected = source.deletions[entry.key] ?: throw LibrarySyncFailure.StoreUnavailable
            db.rawQuery("SELECT subject,namespace,phase FROM local_deletions WHERE key=?", arrayOf(entry.key)).use {
                if (!it.moveToFirst() || it.getString(0) != expected.subject || it.getString(1) != expected.namespace || it.getString(2) != expected.phase.name) throw LibrarySyncFailure.StoreUnavailable
            }
            db.rawQuery("SELECT erasing FROM export_clocks WHERE scope_key=?", arrayOf(entry.key)).use { if (!it.moveToFirst() || it.getInt(0) != 1) throw LibrarySyncFailure.StoreUnavailable }
        }
        "account" -> {
            val expected = source.accounts[entry.key] ?: throw LibrarySyncFailure.StoreUnavailable
            if (readLocalAccount(db, expected.first) != expected.second) throw LibrarySyncFailure.StoreUnavailable
        }
        else -> throw LibrarySyncFailure.StoreUnavailable
    }
}
internal fun LibraryOutcomeJournal.advanceLocalImport(source: LocalImportSource, load: () -> ByteArray?): Boolean = transaction(allowUnready = true) { db ->
    val phase: String; val next: Int; val table: Int; val after: String; val seen: Int
    db.rawQuery("SELECT import_id,source_hash,phase,next,table_index,after_key,seen FROM local_import WHERE id=1", null).use {
        if (!it.moveToFirst()) throw LibrarySyncFailure.StoreUnavailable
        phase = it.getString(2); if (phase == "ready") return@transaction false
        if (it.getString(0) != source.id || it.getString(1) != source.fingerprint) throw LibrarySyncFailure.StoreUnavailable
        next = it.getInt(3); table = it.getInt(4); after = it.getString(5); seen = it.getInt(6)
    }
    val update = ContentValues()
    when (phase) {
        "staging" -> {
            if (next !in 0..source.count) throw LibrarySyncFailure.StoreUnavailable
            val end = minOf(source.count, next + LOCAL_STORE_BATCH)
            for (ordinal in next until end) {
                val entry = source.entry(ordinal)
                when (entry.kind) {
                    "guest" -> writePayload(db, "local_guest", "guest", 0, entry.payload)
                    "deletion" -> {
                        val intent = source.deletions[entry.key] ?: throw LibrarySyncFailure.StoreUnavailable
                        if (!localScopeDeleting(db, intent.subject, intent.namespace)) putDeletion(db, intent)
                        val fenced = db.rawQuery("SELECT erasing FROM export_clocks WHERE scope_key=?", arrayOf(entry.key)).use { it.moveToFirst() && it.getInt(0) == 1 }
                        if (!fenced) bumpClock(db, intent.subject, intent.namespace, erasing = true)
                    }
                    "account" -> {
                        val expected = source.accounts[entry.key] ?: throw LibrarySyncFailure.StoreUnavailable
                        val old = readLocalAccount(db, expected.first)
                        if (old == null) writePayload(db, "local_accounts", entry.key, 0, encoded(expected.second), expected.first)
                        else if (old != expected.second) throw LibrarySyncFailure.StoreUnavailable
                        val scope = localDeletionKey(expected.first.subject, expected.first.namespace)
                        val hasClock = db.rawQuery("SELECT 1 FROM export_clocks WHERE scope_key=?", arrayOf(scope)).use { it.moveToFirst() }
                        if (!hasClock) bumpClock(db, expected.first.subject, expected.first.namespace)
                    }
                }
                db.insertOrThrow("local_import_rows", null, ContentValues().apply { put("ordinal", ordinal); put("kind", entry.kind); put("key_hash", digest(entry.key.toByteArray())); put("fingerprint", entry.fingerprint) })
            }
            update.put("next", if (end == source.count) 0 else end); if (end == source.count) update.put("phase", "verify")
        }
        "verify" -> {
            if (next !in 0..source.count) throw LibrarySyncFailure.StoreUnavailable
            val end = minOf(source.count, next + LOCAL_STORE_BATCH)
            for (ordinal in next until end) {
                val entry = source.entry(ordinal)
                db.rawQuery("SELECT kind,key_hash,fingerprint FROM local_import_rows WHERE ordinal=?", arrayOf(ordinal.toString())).use {
                    if (!it.moveToFirst() || it.getString(0) != entry.kind || it.getString(1) != digest(entry.key.toByteArray()) || it.getString(2) != entry.fingerprint) throw LibrarySyncFailure.StoreUnavailable
                }; checkImportEntry(db, source, entry)
            }
            update.put("next", end); if (end == source.count) { update.put("phase", "scan"); update.put("table_index", 0); update.put("after_key", "") }
        }
        "scan" -> {
            val definition = when (table) { 0 -> "local_guest" to "guest"; 1 -> "local_deletions" to "deletion"; 2 -> "local_accounts" to "account"; else -> throw LibrarySyncFailure.StoreUnavailable }
            val keys = mutableListOf<String>()
            db.rawQuery("SELECT key FROM ${definition.first} WHERE key>? ORDER BY key LIMIT 8", arrayOf(after)).use { while (it.moveToNext()) keys.add(it.getString(0)) }
            for (key in keys) checkImportEntry(db, source, LocalImportEntry(definition.second, key, byteArrayOf()))
            val total = seen + keys.size; if (total > source.uniqueCount) throw LibrarySyncFailure.StoreUnavailable
            update.put("seen", total); update.put("after_key", keys.lastOrNull() ?: after)
            if (keys.size < LOCAL_STORE_BATCH) {
                if (table < 2) { update.put("table_index", table + 1); update.put("after_key", "") }
                else { if (total != source.uniqueCount) throw LibrarySyncFailure.StoreUnavailable; update.put("phase", "publish") }
            }
        }
        "publish" -> {
            if (seen != source.uniqueCount) throw LibrarySyncFailure.StoreUnavailable
            db.rawQuery("SELECT ordinal FROM local_import_rows WHERE ordinal>=? LIMIT 1", arrayOf(source.count.toString())).use { if (it.moveToFirst()) throw LibrarySyncFailure.StoreUnavailable }
            val current = load()
            if ((current != null) != source.present || digest(current ?: "{}".toByteArray()) != source.originalHash) throw LibrarySyncFailure.StoreUnavailable
            update.put("phase", "ready"); update.putNull("source"); update.putNull("original"); update.put("source_size", 0)
        }
        else -> throw LibrarySyncFailure.StoreUnavailable
    }
    db.update("local_import", update, "id=1", null); phase != "publish"
}
internal fun LibraryOutcomeJournal.cleanupLocalImportStep(): Boolean = transaction { db ->
    db.delete("local_import_rows", "ordinal IN (SELECT ordinal FROM local_import_rows ORDER BY ordinal LIMIT 8)", null) > 0
}
