package com.hadithly.app

import android.content.ContextWrapper
import androidx.test.platform.app.InstrumentationRegistry
import com.hadithly.app.core.data.*
import java.io.File
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import org.junit.Assert.*
import org.junit.Test
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class GuestMergeRaceTest {
    private fun <T> sql(directory: File, block: (android.database.sqlite.SQLiteDatabase) -> T): T =
        android.database.sqlite.SQLiteDatabase.openDatabase(File(directory, "library_outcomes.db").path, null, 0).use(block)

    @Test fun clonedGuestWritersPreserveAllAcceptedNotes() = runBlocking {
        isolated { store, reopen, _ ->
            // Establish existing storage before launching independently opened writers.
            store.snapshots()
            val writers = (0 until 16).map { reopen() }; val ready = java.util.concurrent.atomic.AtomicInteger(); val start = CompletableDeferred<Unit>()
            val results = writers.mapIndexed { index, writer -> async(Dispatchers.Default) {
                if (ready.incrementAndGet() == writers.size) start.complete(Unit)
                start.await()
                runCatching { writer.saveNote("guest-$index", "Accepted note $index", null, null, null, null, null, "", null) }
            } }.awaitAll()
            assertTrue("Concurrent accepted guest writes must not conflict", results.all { it.isSuccess })
            assertEquals((0 until 16).map { "guest-$it" }.toSet(), reopen().snapshots().notes.map { it.hadithId }.toSet())
        }
    }
    @Test fun clonedAccountWritersPreserveAllAcceptedCommands() = runBlocking {
        isolated { store, reopen, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); store.claimGuestForSync(owner)
            val writers = (0 until 16).map { reopen() }; val ready = java.util.concurrent.atomic.AtomicInteger(); val start = CompletableDeferred<Unit>()
            val changes = (0 until 16).map { LibraryLocalChange(SyncCommand.NotePut("target-$it", "Accepted command $it", 1_000.0, 1_000.0), 1_000.0, LibraryLocalSource.Account(null)) }
            val results = writers.mapIndexed { index, writer -> async(Dispatchers.Default) {
                if (ready.incrementAndGet() == writers.size) start.complete(Unit)
                start.await(); runCatching { writer.enqueueSyncChange(changes[index], owner) }
            } }.awaitAll()
            assertTrue("Concurrent accepted account writes must not conflict", results.all { it.isSuccess })
            assertEquals(changes.map { it.operation.id }.toSet(), reopen().syncPartition(owner)?.pending?.map { it.operation.id }?.toSet())
        }
    }
    private fun journal(directory: File): LibraryOutcomeJournal {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        return LibraryOutcomeJournal(object : ContextWrapper(context) { override fun getFilesDir(): File = directory })
    }
    private fun phase(directory: File): String = sql(directory) { db -> db.rawQuery("SELECT phase FROM local_import WHERE id=1", null).use { assertTrue(it.moveToFirst()); it.getString(0) } }
    private fun count(directory: File, table: String): Int = sql(directory) { db -> db.rawQuery("SELECT count(*) FROM $table", null).use { it.moveToFirst(); it.getInt(0) } }
    private fun unavailable(block: () -> Unit) {
        try { block(); fail("Unavailable local authority was admitted") } catch (_: LibrarySyncFailure) { }
    }
    @Test fun localImportStagesBoundedRowsAndRollbackKeepsCanonicalDefaultsAcrossReopen() = runBlocking {
        isolated { store, _, directory ->
            val sourceFile = File(directory, "guest_store.json")
            val owner = LibrarySyncOwner("owner-0", "subject-0")
            val partitions = (0 until 19).map { LibrarySyncPartition(LibrarySyncOwner("owner-$it", "subject-$it").storageKey, "subject-$it", LibraryPartitionState(nextSequence = it + 1.0)) }
            val json = Json { encodeDefaults = true; explicitNulls = false }
            val legacy = GuestStoreFile(notes = listOf(GuestNoteDraft("guest", "مرحبا Қазақша", 1.0, 2.0)), syncPartitions = partitions)
            // Old installed JSON can omit the UUID default. Normalize it only once.
            val tree = json.parseToJsonElement(json.encodeToString(legacy)) as kotlinx.serialization.json.JsonObject
            val rows = tree.getValue("syncPartitions") as kotlinx.serialization.json.JsonArray
            val raw = kotlinx.serialization.json.JsonObject(tree + ("syncPartitions" to kotlinx.serialization.json.JsonArray(rows.map { row ->
                val obj = row as kotlinx.serialization.json.JsonObject
                val state = obj.getValue("state") as kotlinx.serialization.json.JsonObject
                kotlinx.serialization.json.JsonObject(obj + ("state" to kotlinx.serialization.json.JsonObject(state - "clientKey")))
            }))).toString().toByteArray()
            sourceFile.writeBytes(raw)
            val first = journal(directory); val captured = first.localImportSource { sourceFile.readBytes() }!!
            val client = captured.accounts.getValue(owner.storageKey).second.clientKey
            unavailable { first.localGuest() }; unavailable { first.captureExportFence(owner) }
            sql(directory) { it.execSQL("CREATE TRIGGER fail_import_checkpoint BEFORE UPDATE ON local_import BEGIN SELECT RAISE(ABORT,'injected'); END") }
            try { first.advanceLocalImport(captured) { raw }; fail("Partial staging committed") } catch (_: android.database.sqlite.SQLiteException) { }
            assertEquals(0, count(directory, "local_import_rows")); assertEquals(0, count(directory, "local_accounts")); assertEquals(0, count(directory, "local_guest"))
            sql(directory) { it.execSQL("DROP TRIGGER fail_import_checkpoint") }; first.close()
            var steps = 0
            while (true) {
                val reopened = journal(directory)
                val resumed = reopened.localImportSource { fail("Captured source was reloaded"); raw }!!
                assertEquals(client, resumed.accounts.getValue(owner.storageKey).second.clientKey)
                val before = count(directory, "local_import_rows")
                if (phase(directory) == "publish") {
                    sql(directory) { it.execSQL("CREATE TRIGGER fail_ready BEFORE UPDATE ON local_import WHEN NEW.phase='ready' BEGIN SELECT RAISE(ABORT,'injected'); END") }
                    try { reopened.advanceLocalImport(resumed) { raw }; fail("Failed Ready publication committed") } catch (_: android.database.sqlite.SQLiteException) { }
                    assertEquals("publish", phase(directory)); unavailable { reopened.localGuest() }; unavailable { reopened.savedActive(owner) }
                    sql(directory) { db ->
                        db.rawQuery("SELECT source,original FROM local_import", null).use { assertTrue(it.moveToFirst()); assertFalse(it.isNull(0)); assertFalse(it.isNull(1)) }
                        db.execSQL("DROP TRIGGER fail_ready")
                    }
                }
                val more = reopened.advanceLocalImport(resumed) { raw }
                assertTrue(count(directory, "local_import_rows") - before <= 8)
                reopened.close(); steps++
                if (!more) break
                assertTrue(steps < 40)
            }
            assertEquals("ready", phase(directory)); assertTrue(steps > 6)
            assertEquals(client, store.syncPartition(owner)!!.clientKey)
            assertEquals(legacy.notes, store.snapshots().notes)
            for (partition in partitions.drop(1)) {
                val target = LibrarySyncOwner(partition.ownerKey.substringAfter('|'), partition.subject)
                assertEquals(partition.state.nextSequence, store.syncPartition(target)!!.nextSequence, 0.0)
            }
            sql(directory) { db -> db.rawQuery("SELECT source,original,source_size FROM local_import", null).use { assertTrue(it.moveToFirst()); assertTrue(it.isNull(0)); assertTrue(it.isNull(1)); assertEquals(0, it.getInt(2)) } }
        }
    }
    @Test fun localImportRejectsUnknownConflictingAndAmbiguousSourceWithoutReplacingIt() = runBlocking {
        val owner = LibrarySyncOwner("owner", "subject")
        val original = LibrarySyncPartition(owner.storageKey, owner.subject, LibraryPartitionState(clientKey = "stable"))
        val changed = original.copy(state = original.state.copy(nextSequence = 2.0))
        val ambiguous = original.copy(ownerKey = "ambiguous|owner|key")
        val conflicts = listOf(
            """{"futureField":true}""",
            Json.encodeToString(GuestStoreFile(syncPartitions = listOf(original, changed))),
            Json.encodeToString(GuestStoreFile(syncPartitions = listOf(ambiguous))),
        )
        for (text in conflicts) isolated { store, _, directory ->
            val file = File(directory, "guest_store.json"); file.writeText(text)
            try { store.snapshots(); fail("Invalid migration became empty") } catch (_: LibrarySyncFailure) { }
            assertEquals(text, file.readText()); assertEquals(0, count(directory, "local_import")); assertEquals(0, count(directory, "local_accounts"))
        }
    }
    @Test fun localImportIdenticalDuplicateRecordsAreAccountedAndChangedSourceBlocksPublication() = runBlocking {
        isolated { store, _, directory ->
            val owner = LibrarySyncOwner("owner", "subject")
            val partition = LibrarySyncPartition(owner.storageKey, owner.subject, LibraryPartitionState(clientKey = "stable", nextSequence = 7.0, folderMappings = mapOf("local" to "server")))
            val intent = LibraryDeletionIntent("deleted-subject", owner.namespace, LibraryDeletionPhase.SERVER_PENDING)
            val file = File(directory, "guest_store.json")
            val raw = Json.encodeToString(GuestStoreFile(syncPartitions = listOf(partition, partition), deletions = listOf(intent, intent))).toByteArray(); file.writeBytes(raw)
            journal(directory).use { journal ->
                val source = journal.localImportSource { raw }!!
                while (phase(directory) != "publish") journal.advanceLocalImport(source) { raw }
                assertEquals(5, count(directory, "local_import_rows")); assertEquals(1, count(directory, "local_accounts")); assertEquals(1, count(directory, "local_deletions"))
                file.writeText("{}")
                unavailable { journal.advanceLocalImport(source) { file.readBytes() } }; assertEquals("publish", phase(directory))
                sql(directory) { db -> db.rawQuery("SELECT original FROM local_import", null).use { assertTrue(it.moveToFirst()); assertArrayEquals(raw, it.getBlob(0)) } }
                file.writeBytes(raw); assertFalse(journal.advanceLocalImport(source) { raw })
            }
            assertEquals(partition.state, store.syncPartition(owner)); assertEquals(intent.phase, store.deletionPhase(intent.subject, intent.namespace))
        }
    }
    @Test fun localClaimRollsBackAccountAndGuestTogetherAndRetainsInvalidOriginalsExactlyOnce() = runBlocking {
        isolated { store, reopen, directory ->
            val owner = LibrarySyncOwner("owner", "subject")
            val drafts = listOf(GuestNoteDraft("same", "First original", 1.0, 2.0), GuestNoteDraft("same", "Second original", 3.0, 4.0), GuestNoteDraft("invalid", "", 1.0, 2.0))
            val legacy = GuestStoreFile(notes = drafts)
            File(directory, "guest_store.json").writeText(Json.encodeToString(legacy)); store.snapshots()
            sql(directory) { it.execSQL("CREATE TRIGGER fail_guest_clear BEFORE UPDATE ON local_guest BEGIN SELECT RAISE(ABORT,'injected'); END") }
            try { store.claimGuestForSync(owner); fail("Guest claim partially committed") } catch (_: android.database.sqlite.SQLiteException) { }
            assertNull(reopen().syncPartition(owner)); assertEquals(drafts, reopen().snapshots().notes)
            sql(directory) { it.execSQL("DROP TRIGGER fail_guest_clear") }
            val recovered = reopen(); recovered.claimGuestForSync(owner)
            val claimed = recovered.syncPartition(owner)!!
            assertEquals(drafts.take(2), claimed.pending.map { (it.source as LibraryLocalSource.Note).value })
            assertEquals(LibraryRecovery.Invalid(LibraryLocalSource.Note(drafts.last())), claimed.recovery.single())
            assertTrue(recovered.snapshots().notes.isEmpty()); recovered.claimGuestForSync(owner); assertEquals(claimed, recovered.syncPartition(owner))
            // A restored legacy copy is never authoritative after Ready or claim.
            File(directory, "guest_store.json").writeText(Json.encodeToString(legacy))
            assertTrue(reopen().snapshots().notes.isEmpty()); assertEquals(claimed, reopen().syncPartition(owner))
        }
    }
    @Test fun localAccountWindowedPayloadAndForeignIsolationAndSharedExportClock() = runBlocking {
        isolated { store, reopen, directory ->
            val owner = LibrarySyncOwner("owner", "subject"); val other = LibrarySyncOwner("foreign", "other")
            val original = GuestNoteDraft("large", "x".repeat(2_300_000) + " النهاية", 1.0, 2.0)
            val huge = LibraryPartitionState(clientKey = "stable-large", recovery = listOf(LibraryRecovery.Invalid(LibraryLocalSource.Note(original))))
            File(directory, "guest_store.json").writeText(Json.encodeToString(GuestStoreFile(syncPartitions = listOf(LibrarySyncPartition(owner.storageKey, owner.subject, huge), LibrarySyncPartition(other.storageKey, other.subject, LibraryPartitionState())))))
            assertEquals(huge, store.syncPartition(owner))
            sql(directory) { it.execSQL("UPDATE local_accounts SET payload=X'00' WHERE key=?", arrayOf(other.storageKey)) }
            val fence = store.prepareOutcomeExport(owner) { true }
            note(reopen(), "Guest-only accepted note"); store.validateOutcomeExport(fence)
            val change = LibraryLocalChange(SyncCommand.NoteRemove("one"), 3.0, LibraryLocalSource.Account(null)); reopen().enqueueSyncChange(change, owner)
            try { store.validateOutcomeExport(fence); fail("Account-only mutation escaped export clock") } catch (_: LibrarySyncFailure.StoreUnavailable) { }
            assertEquals(huge.recovery, reopen().syncPartition(owner)!!.recovery)
            assertEquals(listOf(change), reopen().syncPartition(owner)!!.pending)
            try { store.syncPartition(other); fail("Corrupt selected payload became empty") } catch (_: LibrarySyncFailure.StoreUnavailable) { }
            assertEquals(1, store.snapshots().notes.size)
            sql(directory) { db ->
                db.rawQuery("EXPLAIN QUERY PLAN SELECT 1 FROM local_accounts WHERE subject=? AND namespace=? LIMIT 1", arrayOf(owner.subject, owner.namespace)).use { assertTrue(it.moveToFirst()); assertTrue(it.getString(3).contains("local_accounts_scope")); assertTrue(it.getString(3).contains("SEARCH")) }
                db.rawQuery("SELECT payload FROM local_accounts WHERE key=?", arrayOf(other.storageKey)).use { assertTrue(it.moveToFirst()); assertArrayEquals(byteArrayOf(0), it.getBlob(0)) }
            }
        }
    }
    @Test fun localDeletionIntentClockRollbackAndStrictLegacyCleanupPreserveSiblingAndGuest() = runBlocking {
        isolated { store, reopen, directory ->
            val owner = LibrarySyncOwner("owner", "subject"); val sibling = LibrarySyncOwner("other", "sibling")
            store.claimGuestForSync(owner); store.claimGuestForSync(sibling); note(store, "Unclaimed newer guest note")
            val before = store.syncPartition(sibling); val fence = store.prepareOutcomeExport(owner) { true }
            sql(directory) { it.execSQL("CREATE TRIGGER fail_erase_clock BEFORE UPDATE ON export_clocks BEGIN SELECT RAISE(ABORT,'injected'); END") }
            try { store.beginDeletion(owner.subject, owner.namespace); fail("Deletion intent committed without clock") } catch (_: android.database.sqlite.SQLiteException) { }
            sql(directory) { it.execSQL("DROP TRIGGER fail_erase_clock") }
            assertNull(store.deletionPhase(owner.subject, owner.namespace)); store.validateOutcomeExport(fence)
            store.beginDeletion(owner.subject, owner.namespace)
            val legacy = File(directory, "guest_store.json").apply { mkdirs() }; File(legacy, "blocked").writeText("fixture")
            try { store.markDeletionBackendComplete(owner.subject, owner.namespace); fail("Identity cleanup admitted retained legacy path") } catch (_: LibrarySyncFailure.StoreUnavailable) { }
            assertEquals(LibraryDeletionPhase.SERVER_PENDING, reopen().deletionPhase(owner.subject, owner.namespace))
            assertNull(reopen().syncPartition(owner)); assertEquals(before, reopen().syncPartition(sibling)); assertEquals(1, reopen().snapshots().notes.size)
            legacy.deleteRecursively(); reopen().markDeletionBackendComplete(owner.subject, owner.namespace)
            assertEquals(LibraryDeletionPhase.IDENTITY_PENDING, reopen().deletionPhase(owner.subject, owner.namespace)); reopen().clearDeletion(owner.subject, owner.namespace)
            assertNull(reopen().deletionPhase(owner.subject, owner.namespace)); assertEquals(before, reopen().syncPartition(sibling)); assertEquals(1, reopen().snapshots().notes.size)
        }
    }
    @Test fun localJournalAdmissionRechecksLiveAccountInsideItsOwnTransaction() = runBlocking {
        isolated { store, _, directory ->
            val owner = LibrarySyncOwner("owner", "subject"); store.claimGuestForSync(owner)
            val fence = store.prepareOutcomeExport(owner) { true }; val proof = outcomeProof(owner, 1)
            sql(directory) { it.delete("local_accounts", "key=?", arrayOf(owner.storageKey)) }
            journal(directory).use { journal ->
                unavailable { journal.captureGeneration(LibraryOutcomeBinding(owner, proof)) }
                unavailable { journal.beginSaved(owner) }; unavailable { journal.captureExportFence(owner) }
                unavailable { journal.registerArtifact(fence) }; unavailable { journal.sealExport(fence, "late") { fail("Late publication") } }
            }
            assertEquals(0, count(directory, "scopes")); assertEquals(0, count(directory, "headers")); assertEquals(0, count(directory, "saved_assemblies")); assertEquals(0, count(directory, "export_artifacts"))
        }
    }
    @Test fun localArtifactValidationRechecksDeletionInsideJournalTransaction() = runBlocking {
        isolated { store, _, directory ->
            val owner = LibrarySyncOwner("owner", "subject"); store.claimGuestForSync(owner)
            val fence = store.prepareOutcomeExport(owner) { true }; val artifact = store.beginOutcomeExportArtifact(fence)
            store.beginDeletion(owner.subject, owner.namespace)
            assertEquals(1, count(directory, "export_artifacts"))
            journal(directory).use { journal -> unavailable { journal.validateArtifact(artifact.id, owner) } }
            assertEquals(1, count(directory, "export_artifacts"))
        }
    }
    @Test fun localMigrationFromActualV4PreservesActiveRetiringAndFrozenAccountState() = runBlocking {
        isolated { store, reopen, directory ->
            val owner = LibrarySyncOwner("owner", "subject"); store.claimGuestForSync(owner)
            val first = store.beginSavedAssembly(owner); prepareSaved(store, first, emptyList(), 8.0); activateSaved(store, first)
            val second = store.beginSavedAssembly(owner); prepareSaved(store, second, emptyList(), 9.0); val active = activateSaved(store, second)
            val change = LibraryLocalChange(SyncCommand.NotePut("target", "Frozen private original", 1.0, 2.0), 2.0, LibraryLocalSource.Account(null))
            store.enqueueSyncChange(change, owner); val frame = store.freezeSyncFrame(owner)!!
            val state = store.syncPartition(owner)!!; val fence = store.prepareOutcomeExport(owner) { true }
            val artifact = store.beginOutcomeExportArtifact(fence)
            val before = sql(directory) { db -> db.rawQuery("SELECT active,retiring FROM saved_assemblies", null).use { assertTrue(it.moveToFirst()); listOf(it.getString(0), it.getString(1)) } }
            assertTrue(before.all { !it.isNullOrEmpty() })
            File(directory, "guest_store.json").writeText(Json.encodeToString(GuestStoreFile(syncPartitions = listOf(LibrarySyncPartition(owner.storageKey, owner.subject, state)))))
            sql(directory) { db ->
                db.beginTransaction()
                try {
                    for (table in listOf("local_import_rows", "local_import", "local_guest", "local_accounts", "local_deletions")) db.execSQL("DROP TABLE $table")
                    db.execSQL("ALTER TABLE saved_assemblies RENAME TO saved_assemblies_v6")
                    db.execSQL("CREATE TABLE saved_assemblies (scope_key TEXT PRIMARY KEY NOT NULL, subject TEXT NOT NULL, namespace TEXT NOT NULL, owner_key TEXT NOT NULL, lease TEXT NOT NULL, checkpoint TEXT NOT NULL, erasing INTEGER NOT NULL, active TEXT, retiring TEXT)")
                    db.execSQL("INSERT INTO saved_assemblies SELECT scope_key,subject,namespace,owner_key,lease,checkpoint,erasing,active,retiring FROM saved_assemblies_v6")
                    db.execSQL("DROP TABLE saved_assemblies_v6")
                    db.execSQL("CREATE INDEX saved_assemblies_owner ON saved_assemblies(subject,namespace,owner_key)")
                    for (viewTable in listOf("saved_view_heads", "saved_view_rows", "saved_view_indexes")) db.execSQL("DROP TABLE $viewTable")
                    db.version = 4; db.setTransactionSuccessful()
                } finally { db.endTransaction() }
            }
            val recovered = reopen(); assertEquals(state, recovered.syncPartition(owner)); assertEquals(frame, recovered.freezeSyncFrame(owner))
            assertEquals(active, recovered.activeSavedGeneration(owner)); assertTrue(recovered.activeSavedPage(active, null).done)
            recovered.validateOutcomeExport(fence)
            sql(directory) { db ->
                assertEquals(8, db.version)
                db.rawQuery("SELECT active,retiring FROM saved_assemblies", null).use { assertTrue(it.moveToFirst()); assertEquals(before, listOf(it.getString(0), it.getString(1))) }
                db.rawQuery("SELECT artifact_id FROM export_artifacts", null).use { assertTrue(it.moveToFirst()); assertEquals(artifact.id, it.getString(0)) }
            }
        }
    }
    @Test fun clonedOwnersClaimEachOriginalOnceAndLateGuestNoteSurvives() = runBlocking {
        isolated { store, reopen, _ ->
            note(store, "Original before either claim")
            val owners = listOf(LibrarySyncOwner("a", "subject-a"), LibrarySyncOwner("b", "subject-b"))
            val release = CompletableDeferred<Unit>(); val entered = java.util.concurrent.atomic.AtomicInteger()
            val writers = owners.map { owner -> async(Dispatchers.Default) {
                val clone = reopen(); if (entered.incrementAndGet() == 2) release.complete(Unit); release.await(); clone.claimGuestForSync(owner)
            } }
            writers.awaitAll()
            assertEquals(1, owners.sumOf { reopen().syncPartition(it)!!.pending.size })
            note(reopen(), "Late guest original")
            assertEquals("Late guest original", reopen().snapshots().notes.single().content)
            assertEquals(1, owners.sumOf { reopen().syncPartition(it)!!.pending.size })
        }
    }
    @Test fun rowObservationBlocksLegacyHighVersionsAcrossAllFourConsumers() = runBlocking {
        isolated { store, reopen, directory ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); store.claimGuestForSync(owner); val lease = store.beginSavedAssembly(owner)
            sql(directory) { it.execSQL("UPDATE saved_assemblies SET row_mode=1") }
            store.enqueueSyncChange(LibraryLocalChange(SyncCommand.NoteRemove("note-target"), 1_000.0, LibraryLocalSource.Account(null)), owner)
            val note = store.freezeSyncFrame(owner)!!; val operation = note.batch.operations.single()
            val noteProof = SyncCommitted(note.clientKey, note.sequence, "note-proof", SyncRevision(2.0, 0.0), SyncReply(owner.key, note.batch.id, listOf(SyncReceipt(operation.id, operation.revision, SyncOutcome.Preserved))))
            store.settleSyncExchange(SyncExchange.Accepted(noteProof), note, owner)
            store.cacheSavedSnapshot(SyncSavedSnapshot(owner.key, 999.0, emptyList(), emptyList()), owner)
            store.cachePositionsSnapshot(SyncPositionsSnapshot(owner.key, 999.0, emptyList()), owner)
            assertEquals(1, store.syncPartition(owner)!!.confirmed.size)
            val noteAck = store.syncPartition(owner)!!.acknowledgement!!
            store.settleSyncAcknowledgement(SyncAckReply(owner.key, noteAck.clientKey, SyncCursor(noteAck.sequence)), noteAck, owner)
            store.enqueueSyncChange(LibraryLocalChange(SyncCommand.FolderDelete(SyncFolderReference.Server("folder")), 1_000.0, LibraryLocalSource.Account(null)), owner)
            val frame = store.freezeSyncFrame(owner)!!; val deletion = frame.batch.operations.single()
            val proof = SyncCommitted(frame.clientKey, frame.sequence, "delete-proof", SyncRevision(3.0, 0.0), SyncReply(owner.key, frame.batch.id, listOf(SyncReceipt(deletion.id, deletion.revision, SyncOutcome.FolderDeletedManifest("manifest", "generation", 1.0, 1_000.0)))))
            store.settleSyncExchange(SyncExchange.Accepted(proof), frame, owner); collectExportFacts(proof, owner, 1, store)
            val hadith = SyncHadithSummary("hadith-0", "1", "bukhari", "Bukhari", "1", "نص", null, "Bukhari 1")
            store.cacheSavedSnapshot(SyncSavedSnapshot(owner.key, 1_000.0, listOf(SyncFolderRow("folder", "Old joined folder", 1_000.0)), listOf(SyncSavedItem("hadith-0", 1_000.0, 1_000.0, bookmarkCreatedAt = 1_000.0, folderId = "folder", hadith = hadith))), owner)
            val pending = store.syncPartition(owner)!!.collectingOutcome!!
            assertEquals(LibraryOutcomeSettlement.AwaitingSaved, store.settleCollectedOutcome(pending, owner, 2_000.0))
            assertTrue(store.libraryProjection(owner).folders.isEmpty()); assertNull(store.libraryProjection(owner).items.first().folderId)
            prepareSaved(store, lease, emptyList(), 2.0); activateSaved(store, lease)
            store.cachePositionsSnapshot(SyncPositionsSnapshot(owner.key, 1_000.0, emptyList()), owner)
            assertTrue(store.syncPartition(owner)!!.confirmed.isEmpty())
            assertEquals(LibraryOutcomeSettlement.AwaitingSaved, store.settleCollectedOutcome(pending, owner, 2_000.0)); assertTrue(store.libraryProjection(owner).folders.isEmpty())
            val next = store.beginSavedAssembly(owner); prepareSaved(store, next, emptyList(), 3.0); activateSaved(store, next)
            assertEquals(LibraryOutcomeSettlement.Settled, store.settleCollectedOutcome(pending, owner, 2_000.0)); assertNotNull(reopen().syncPartition(owner)!!.acknowledgement)
        }
    }
    @Test fun rowObservationUnavailablePreservesAcknowledgedEvidenceUntilActive() = runBlocking {
        isolated { _, _, directory ->
            val initial = GuestDataStore(object : ContextWrapper(InstrumentationRegistry.getInstrumentation().targetContext) { override fun getFilesDir() = directory })
            val (proof, _) = acknowledgedRetentionFixture(initial, directory, 1)
            val owner = LibrarySyncOwner("owner-a", "subject-a"); val lease = initial.beginSavedAssembly(owner)
            sql(directory) { it.execSQL("UPDATE saved_assemblies SET row_mode=1") }
            val now = 2_000 + LibraryOutcomeRetention.duration
            initial.pruneOutcomeSuccessStep(owner, now); assertEquals(1, initial.outcomeEvidencePage(proof, owner, 0).rows.size)
            prepareSaved(initial, lease, emptyList(), 2.0); activateSaved(initial, lease)
            repeat(4) { initial.pruneOutcomeSuccessStep(owner, now) }
            try { initial.outcomeEvidencePage(proof, owner, 0); fail("Observed success was not pruned") } catch (_: LibrarySyncFailure.StoreUnavailable) { }
        }
    }
    @Test fun everySavedConsumerRejectsForeignObservationWithoutMutation() {
        val owner = LibrarySyncOwner("owner-a", "subject-a"); val proof = outcomeProof(owner, 1); val binding = LibraryOutcomeBinding(owner, proof)
        val pending = LibraryPendingOutcome(proof, LibraryOutcomeOrigin.Historical)
        val checkpoint = LibraryOutcomeCheckpoint(binding.expected, LibraryOutcomeStatus.Complete, LibraryOutcomeRetention(2_000.0))
        val state = LibraryPartitionState(clientKey = proof.clientKey, collectingOutcome = pending, savedSnapshot = SyncSavedSnapshot(owner.key, 999.0, emptyList(), emptyList()))
        val before = Json.encodeToString(state)
        for (peer in listOf(owner.copy(subject = "another-subject"), owner.copy(namespace = "another-deployment"))) {
            val foreign = LibrarySavedObservation.legacy(peer, SyncSavedSnapshot(peer.key, 999.0, emptyList(), emptyList()))
            try { state.projectedFrozenChanges(owner, foreign); fail("Foreign projection authority") } catch (_: LibrarySyncFailure.OwnerMismatch) { }
            try { state.pruneConfirmed(owner, foreign); fail("Foreign confirmation authority") } catch (_: LibrarySyncFailure.OwnerMismatch) { }; assertEquals(before, Json.encodeToString(state))
            try { state.settleCollectedOutcome(pending, binding, checkpoint, foreign, 2_000.0); fail("Foreign settlement authority") } catch (_: LibrarySyncFailure.OwnerMismatch) { }; assertEquals(before, Json.encodeToString(state))
            try { state.canPruneOutcome(binding, checkpoint, foreign, 2_000 + LibraryOutcomeRetention.duration); fail("Foreign retention authority") } catch (_: LibrarySyncFailure.OwnerMismatch) { }
        }
    }
    @Test fun rowObservationV5UpgradePreservesReadyAccountsDeletionClockAndActiveGeneration() = runBlocking {
        isolated { store, reopen, directory ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); store.claimGuestForSync(owner)
            store.enqueueSyncChange(LibraryLocalChange(SyncCommand.NoteRemove("accepted"), 1_000.0, LibraryLocalSource.Account(null)), owner)
            val lease = store.beginSavedAssembly(owner); prepareSaved(store, lease, emptyList()); val active = activateSaved(store, lease)
            store.beginDeletion("deleted-subject", owner.namespace)
            val state = store.syncPartition(owner); val fence = store.prepareOutcomeExport(owner) { true }
            sql(directory) { db ->
                db.beginTransaction()
                try {
                    db.execSQL("ALTER TABLE saved_assemblies RENAME TO saved_assemblies_v6")
                    db.execSQL("CREATE TABLE saved_assemblies (scope_key TEXT PRIMARY KEY NOT NULL, subject TEXT NOT NULL, namespace TEXT NOT NULL, owner_key TEXT NOT NULL, lease TEXT NOT NULL, checkpoint TEXT NOT NULL, erasing INTEGER NOT NULL, active TEXT, retiring TEXT)")
                    db.execSQL("INSERT INTO saved_assemblies SELECT scope_key,subject,namespace,owner_key,lease,checkpoint,erasing,active,retiring FROM saved_assemblies_v6")
                    db.execSQL("DROP TABLE saved_assemblies_v6"); db.execSQL("CREATE INDEX saved_assemblies_owner ON saved_assemblies(subject,namespace,owner_key)")
                    for (viewTable in listOf("saved_view_heads", "saved_view_rows", "saved_view_indexes")) db.execSQL("DROP TABLE $viewTable")
                    db.version = 5; db.setTransactionSuccessful()
                } finally { db.endTransaction() }
            }
            File(directory, "guest_store.json").writeText("{stale-invalid-source")
            val recovered = reopen(); assertEquals(state, recovered.syncPartition(owner)); assertEquals(active, recovered.activeSavedGeneration(owner)); recovered.validateOutcomeExport(fence)
            assertEquals(LibraryDeletionPhase.SERVER_PENDING, recovered.deletionPhase("deleted-subject", owner.namespace)); assertEquals("ready", phase(directory))
            sql(directory) { db ->
                assertEquals(8, db.version)
                db.rawQuery("SELECT row_mode FROM saved_assemblies", null).use { assertTrue(it.moveToFirst()); assertEquals(0, it.getInt(0)) }
                db.rawQuery("SELECT erasing FROM export_clocks WHERE subject=?", arrayOf("deleted-subject")).use { assertTrue(it.moveToFirst()); assertEquals(1, it.getInt(0)) }
            }
        }
    }
    @Test fun viewAuditResumesVerifiesWholeCompiledSnapshotAndInvalidatesOnWrite() = runBlocking {
        isolated { store, _, directory ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); store.claimGuestForSync(owner); val scope = store.beginSavedAssembly(owner)
            val state = viewState(owner, 2_001); val source = LibrarySavedViewPolicy.captureLegacy(state, owner, observation(state))
            var db = journal(directory); var stamp = db.createSavedViewRows(scope)
            source.items.chunked(8).forEach { stamp = db.writeSavedViewRows(stamp, it) }
            source.folders.chunked(8).forEach { stamp = db.writeSavedViewRows(stamp, emptyList(), it) }
            db.close()
            // Actual v7 head migration keeps all already-built rows and indexes.
            sql(directory) { old ->
                old.beginTransaction()
                try {
                    old.execSQL("ALTER TABLE saved_view_heads RENAME TO saved_view_heads_v8")
                    old.execSQL("CREATE TABLE saved_view_heads (key TEXT PRIMARY KEY NOT NULL, scope_key TEXT NOT NULL, subject TEXT NOT NULL, namespace TEXT NOT NULL, owner_key TEXT NOT NULL, identity_data TEXT NOT NULL, serial INTEGER NOT NULL)")
                    old.execSQL("INSERT INTO saved_view_heads SELECT key,scope_key,subject,namespace,owner_key,identity_data,serial FROM saved_view_heads_v8")
                    old.execSQL("DROP TABLE saved_view_heads_v8"); old.execSQL("CREATE INDEX saved_view_heads_scope ON saved_view_heads(scope_key,key)")
                    old.execSQL("CREATE INDEX saved_view_heads_owner ON saved_view_heads(subject,namespace,owner_key,key)")
                    old.version = 7; old.setTransactionSuccessful()
                } finally { old.endTransaction() }
            }
            db = journal(directory); assertEquals(stamp, db.draftSavedViewStamp(stamp.identity)); assertNull(db.savedViewAudit(stamp))
            val manifest = LibrarySavedViewManifest.make(stamp.identity, source)
            var audit = db.beginSavedViewAudit(stamp, manifest); var steps = 0
            while (audit.phase != LibrarySavedViewAuditPhase.Verified) {
                val previous = audit; audit = db.savedViewAuditStep(stamp)
                assertTrue(audit.items + audit.folders - previous.items - previous.folders <= 8)
                assertTrue(audit.indexes - previous.indexes <= 128); steps++
                if (steps % 17 == 0) { db.close(); db = journal(directory); assertEquals(audit, db.savedViewAudit(stamp)) }
                assertTrue(steps < 1_000)
            }
            assertEquals(2_001, audit.items.toInt()); assertEquals(70, audit.folders.toInt()); assertEquals(manifest.indexes, audit.indexes); assertEquals(manifest.digest, audit.digest)
            assertEquals(audit, db.beginSavedViewAudit(stamp, manifest))
            val fence = store.prepareOutcomeExport(owner) { true }; assertEquals(audit, db.savedViewAuditStep(stamp)); store.validateOutcomeExport(fence)
            val old = stamp; stamp = db.writeSavedViewRows(stamp, listOf(source.items.first()))
            assertNull(db.savedViewAudit(stamp)); try { db.savedViewAudit(old); fail("Stale integrity proof survived write") } catch (_: LibrarySavedViewChanged) { }
            // Integrity never publishes a private generation or changes production mode.
            assertNull(store.activeSavedGeneration(owner))
            sql(directory) { sql -> sql.rawQuery("SELECT row_mode FROM saved_assemblies", null).use { assertTrue(it.moveToFirst()); assertEquals(0, it.getInt(0)) } }
            db.close()
        }
    }
    @Test fun viewAuditRejectsMissingRowsIndexesExtraIndexesWrongTargetsAndPayloadChanges() = runBlocking {
        for (damage in listOf("missing-row", "missing-index", "extra-index", "wrong-target", "payload", "empty")) isolated { store, _, directory ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); store.claimGuestForSync(owner); val scope = store.beginSavedAssembly(owner)
            val state = viewState(owner, 2); val source = LibrarySavedViewPolicy.captureLegacy(state, owner, observation(state)).copy(folders = emptyList())
            val db = journal(directory); var stamp = db.createSavedViewRows(scope)
            if (damage != "empty") stamp = db.writeSavedViewRows(stamp, source.items)
            val identity = stamp.identity; val manifest = LibrarySavedViewManifest.make(identity, source)
            db.beginSavedViewAudit(stamp, manifest)
            sql(directory) { sql ->
                when (damage) {
                    "missing-row" -> sql.delete("saved_view_rows", "key=?", arrayOf(identity.itemKey(source.items.first().value.hadithId)))
                    "missing-index" -> sql.execSQL("DELETE FROM saved_view_indexes WHERE key=(SELECT MIN(key) FROM saved_view_indexes)")
                    "extra-index" -> sql.execSQL("INSERT INTO saved_view_indexes SELECT ? ,view_key,subject,namespace,owner_key,target_key FROM saved_view_indexes LIMIT 1", arrayOf(identity.key + ":extra"))
                    "wrong-target" -> sql.execSQL("UPDATE saved_view_indexes SET target_key='wrong'")
                    "payload" -> {
                        val item = source.items.first(); val changed = item.copy(value = item.value.copy(createdAt = 999.0))
                        val json = Json { encodeDefaults = true; explicitNulls = false }; val data = json.encodeToString(changed)
                        sql.execSQL("UPDATE saved_view_rows SET data=?,fingerprint=? WHERE key=?", arrayOf(data, librarySemanticDigest(json.parseToJsonElement(data), "saved-view-row-v1:"), identity.itemKey(item.value.hadithId)))
                    }
                }
            }
            var rejected = false
            try { repeat(20) { if (db.savedViewAuditStep(stamp).phase == LibrarySavedViewAuditPhase.Verified) fail("Corrupt $damage draft verified") } }
            catch (_: LibrarySyncFailure) { rejected = true }
            assertTrue("Corrupt $damage draft did not reject", rejected); assertTrue(db.savedViewAudit(stamp)?.phase != LibrarySavedViewAuditPhase.Verified)
            db.close()
        }
    }
    @Test fun viewDiscardIsBoundedDurableAndCannotExposePartialEmptyOrConsumeAnotherDraft() = runBlocking {
        isolated { store, _, directory ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); store.claimGuestForSync(owner); val scope = store.beginSavedAssembly(owner)
            val state = viewState(owner, 97); val source = LibrarySavedViewPolicy.captureLegacy(state, owner, observation(state)).copy(folders = emptyList())
            var db = journal(directory); var stamp = db.createSavedViewRows(scope)
            source.items.chunked(8).forEach { stamp = db.writeSavedViewRows(stamp, it) }
            val peer = db.writeSavedViewRows(db.createSavedViewRows(scope), listOf(source.items.first())); db.createSavedViewRows(scope)
            try { db.createSavedViewRows(scope); fail("Draft capacity exceeded") } catch (_: LibrarySyncFailure) { }
            val initialAudit = db.beginSavedViewAudit(stamp, LibrarySavedViewManifest.make(stamp.identity, source))
            // A real statement failure rolls back the persisted audit and its export clock.
            val fence = store.prepareOutcomeExport(owner) { true }
            sql(directory) { it.execSQL("CREATE TRIGGER refuse_view_audit BEFORE UPDATE ON saved_view_heads BEGIN SELECT RAISE(ABORT, 'injected audit failure'); END") }
            try { db.savedViewAuditStep(stamp); fail("Aborted audit advanced") } catch (_: android.database.sqlite.SQLiteException) { }
            assertEquals(initialAudit, db.savedViewAudit(stamp)); store.validateOutcomeExport(fence)
            sql(directory) { it.execSQL("DROP TRIGGER refuse_view_audit") }
            // Failure after the retiring mark also rolls back admission and child deletion.
            sql(directory) { it.execSQL("CREATE TRIGGER refuse_view_discard BEFORE DELETE ON saved_view_indexes BEGIN SELECT RAISE(ABORT, 'injected discard failure'); END") }
            try { db.discardSavedViewStep(stamp); fail("Aborted discard succeeded") } catch (_: android.database.sqlite.SQLiteException) { }
            assertEquals(stamp, db.draftSavedViewStamp(stamp.identity)); store.validateOutcomeExport(fence)
            sql(directory) { it.execSQL("DROP TRIGGER refuse_view_discard") }
            var steps = 0; var more: Boolean
            do {
                val oldIndexes = count(directory, "saved_view_indexes"); val oldRows = count(directory, "saved_view_rows")
                more = db.discardSavedViewStep(stamp)
                assertTrue(oldIndexes - count(directory, "saved_view_indexes") <= 128); assertTrue(oldRows - count(directory, "saved_view_rows") <= 8)
                if (more) {
                    try { db.draftSavedViewPage(stamp, LibrarySavedViewSelection()); fail("Retiring draft read as empty") } catch (_: LibrarySavedViewChanged) { }
                    try { db.writeSavedViewRows(stamp, listOf(source.items.first())); fail("Retiring draft accepted write") } catch (_: LibrarySavedViewChanged) { }
                }
                assertEquals(source.items.first(), db.draftSavedViewItem(peer, source.items.first().value.hadithId))
                db.close(); db = journal(directory); steps++; assertTrue(steps < 100)
            } while (more)
            val after = store.prepareOutcomeExport(owner) { true }; assertFalse(db.discardSavedViewStep(stamp)); store.validateOutcomeExport(after)
            val empty = db.createSavedViewRows(scope); assertNotEquals(stamp.identity, empty.identity)
            db.beginSavedViewAudit(empty, LibrarySavedViewManifest.make(empty.identity, LibrarySavedViewSnapshot(emptyList(), emptyList())))
            assertEquals(LibrarySavedViewAuditPhase.Indexes, db.savedViewAuditStep(empty).phase)
            assertEquals(LibrarySavedViewAuditPhase.Verified, db.savedViewAuditStep(empty).phase)
            assertEquals(1, count(directory, "saved_view_rows")); db.close()
        }
    }
    private fun viewState(owner: LibrarySyncOwner, count: Int): LibraryPartitionState {
        val folders = (0 until 70).map { SyncFolderRow("folder-$it", "Folder $it", 1_000.0 + it) }
        val items = (0 until count).map { i ->
            val mask = i % 7 + 1; val at = 1_000.0 + i % 3
            val hadith = SyncHadithSummary(if (i % 13 == 0) "mismatched-public-id" else "target-$i", "$i", if (i % 2 == 0) "bukhari" else "muslim", "Collection", "1", "Provider passage", "Provider translation", "Reference")
            SyncSavedItem("target-$i", 1_000.0, at, if (mask and 1 != 0) 1_000.0 else null, if (mask and 2 != 0) 1_000.0 else null, if (mask and 4 != 0) "Private note $i" else null, if (mask and 4 != 0) 1_000.0 else null, if (mask and 4 != 0) at else null, if (i % 6 == 5) null else "folder-${i % 5}", hadith)
        }
        return LibraryPartitionState(savedSnapshot = SyncSavedSnapshot(owner.key, 9.0, folders, items))
    }
    @Test fun viewCompilerMatchesLegacyOracleAndPreservesBulkProvenanceAndTimeFloors() {
        val owner = LibrarySyncOwner("owner-a", "subject-a"); val state = viewState(owner, 2_001)
        val deletion = LibraryLocalChange(SyncCommand.FolderDelete(SyncFolderReference.Server("folder-1")), 5_000.0, LibraryLocalSource.Account(null))
        state.folderMappings = mapOf("restore:${deletion.operation.id}" to "restored-folder")
        state.pending = listOf(deletion,
            LibraryLocalChange(SyncCommand.MembershipPut("target-1999", SyncFolderReference.Server("folder-4")), 6_000.0, LibraryLocalSource.Account(null)),
            LibraryLocalChange(SyncCommand.FolderRestore(deletion.operation.id, "Folder 1", emptyList()), 7_000.0, LibraryLocalSource.Account(null)),
            LibraryLocalChange(SyncCommand.BookmarkRemove("target-0"), 8_000.0, LibraryLocalSource.Account(null)),
            LibraryLocalChange(SyncCommand.FacetRestore("target-0", "removed", SyncCommandFacetRestoreValue.Bookmark(1_000.0)), 9_000.0, LibraryLocalSource.Account(null)))
        val source = LibrarySavedViewPolicy.captureLegacy(state, owner, observation(state)); val oracle = legacyProjection(state)
        assertEquals(2_001, source.items.size); assertEquals(oracle.items.map { it.hadithId }.toSet(), source.items.map { it.value.hadithId }.toSet())
        val expected = oracle.items.associateBy { it.hadithId }
        for (item in source.items) {
            val old = expected.getValue(item.value.hadithId); val value = item.value
            assertEquals(old.createdAt, value.createdAt, 0.0); assertEquals(old.updatedAt, value.updatedAt, 0.0); assertEquals(old.folderId, value.folderId)
            assertEquals(old.bookmarkCreatedAt, value.bookmarkCreatedAt); assertEquals(old.favoriteCreatedAt, value.favoriteCreatedAt); assertEquals(old.noteContent, value.noteContent)
        }
        assertEquals("folder-4", source.items.first { it.value.hadithId == "target-1999" }.value.folderId)
        assertEquals(1_000.0, source.items.first { it.value.hadithId == "target-0" }.value.createdAt, 0.0)
        assertTrue(source.items.filter { it.value.folderId == "restored-folder" }.all { it.value.updatedAt >= 7_000 && it.removedBy == null })
        val deleted = LibrarySavedViewPolicy.deleted(source.items.first(), deletion.operation.id, 10_000.0)
        assertEquals(deletion.operation.id, deleted.removedBy); assertEquals(10_000.0, deleted.value.updatedAt, 0.0)
        val data = Json.encodeToString(source); assertFalse(data.contains("arabicText")); assertFalse(data.contains("englishText"))
    }
    @Test fun viewNamingAndTechnicalKeysMatchBackendAndPortableVectors() {
        val vectors = Json.parseToJsonElement(InstrumentationRegistry.getInstrumentation().context.assets.open("saved-view-vectors.json").bufferedReader().use { it.readText() }) as kotlinx.serialization.json.JsonObject
        for (entry in vectors.getValue("names") as kotlinx.serialization.json.JsonArray) {
            val value = entry as kotlinx.serialization.json.JsonObject
            assertEquals((value.getValue("expected") as kotlinx.serialization.json.JsonPrimitive).content, LibrarySavedViewPolicy.nameKey((value.getValue("input") as kotlinx.serialization.json.JsonPrimitive).content))
        }
        val identity = LibrarySavedViewIdentity(LibrarySyncOwner("owner-a", "subject-a"), "epoch", "generation")
        assertEquals((vectors.getValue("identity") as kotlinx.serialization.json.JsonPrimitive).content, identity.key)
        val source = Json.decodeFromString<LibrarySavedViewSnapshot>(vectors.getValue("manifestSource").toString())
        assertEquals(Json.decodeFromString<LibrarySavedViewManifest>(vectors.getValue("manifest").toString()), LibrarySavedViewManifest.make(identity, source))
        assertEquals((vectors.getValue("rank") as kotlinx.serialization.json.JsonPrimitive).content, LibrarySavedViewPolicy.rank(SavedPrivateItem("target-Ω", 1.0, 4500.5)))
        assertEquals((vectors.getValue("prefix") as kotlinx.serialization.json.JsonPrimitive).content, identity.queryPrefix(LibrarySavedViewSelection(LibrarySavedViewFacet.Bookmarks, LibrarySavedViewFolderSelection.Folder("folder"), "bukhari")))
    }
    @Test fun viewRowsPageByIndexedSelectionAndReadOffscreenTargetsAcrossReopen() = runBlocking {
        isolated { store, _, directory ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); store.claimGuestForSync(owner); val privateLease = store.beginSavedAssembly(owner)
            val state = viewState(owner, 2_001); val source = LibrarySavedViewPolicy.captureLegacy(state, owner, observation(state))
            // The immediate predecessor schema has private/local state but no view tables.
            sql(directory) { db -> for (table in listOf("saved_view_heads", "saved_view_rows", "saved_view_indexes")) db.execSQL("DROP TABLE $table"); db.version = 6 }
            var db = journal(directory)
            var stamp = db.createSavedViewRows(privateLease); val identity = stamp.identity
            source.items.chunked(8).forEach { stamp = db.writeSavedViewRows(stamp, it) }
            source.folders.chunked(8).forEach { stamp = db.writeSavedViewRows(stamp, emptyList(), it) }
            db.close(); db = journal(directory); assertEquals(stamp, db.draftSavedViewStamp(identity))
            val selections = LibrarySavedViewFacet.entries.map { LibrarySavedViewSelection(it) } + listOf(
                LibrarySavedViewSelection(LibrarySavedViewFacet.Notes, LibrarySavedViewFolderSelection.Folder("folder-1"), "bukhari"),
                LibrarySavedViewSelection(LibrarySavedViewFacet.Bookmarks, LibrarySavedViewFolderSelection.Unfiled, "muslim"),
                LibrarySavedViewSelection(collection = "unavailable-collection"))
            for (selection in selections) {
                val all = mutableListOf<LibrarySavedViewItem>(); var ticket: LibrarySavedViewTicket? = null
                do { val page = db.draftSavedViewPage(stamp, selection, ticket); assertTrue(page.items.size <= 32); all.addAll(page.items); ticket = page.next } while (ticket != null)
                val expected = source.items.filter { LibrarySavedViewPolicy.matches(it, selection) }
                assertEquals(expected, all)
            }
            val empty = db.draftSavedViewPage(stamp, LibrarySavedViewSelection(collection = "unavailable-collection")); assertTrue(empty.items.isEmpty()); assertTrue(empty.unresolvedCoverage)
            assertEquals(source.items.first { it.value.hadithId == "target-1999" }, db.draftSavedViewItem(stamp, "target-1999"))
            val first = db.draftSavedViewPage(stamp, LibrarySavedViewSelection()); val old = stamp
            val target = db.draftSavedViewItem(stamp, "target-1999")!!
            stamp = db.writeSavedViewRows(stamp, listOf(target.copy(value = target.value.copy(noteContent = "Offscreen accepted note", noteCreatedAt = 1_000.0, noteUpdatedAt = 20_000.0, updatedAt = 20_000.0))))
            try { db.draftSavedViewPage(old, LibrarySavedViewSelection(), first.next); fail("Stale view continued") } catch (_: LibrarySavedViewChanged) { }
            assertEquals("Offscreen accepted note", db.draftSavedViewPage(stamp, LibrarySavedViewSelection(LibrarySavedViewFacet.Notes)).items.first().value.noteContent)
            val duplicateNames = listOf(SyncFolderRow("\uE000", " ΟΣ ", 1_000.0), SyncFolderRow("\uD800\uDC00", "ος", 1_000.0))
            stamp = db.writeSavedViewRows(stamp, emptyList(), duplicateNames)
            assertEquals("\uE000", db.draftSavedViewFolders(stamp, name = "ΟΣ").folders.first()._id)
            var folders = 0; var folderTicket: LibrarySavedViewFolderTicket? = null
            do { val page = db.draftSavedViewFolders(stamp, folderTicket); folders += page.folders.size; folderTicket = page.next } while (folderTicket != null)
            assertEquals(72, folders); assertEquals("Folder 69", db.draftSavedViewFolder(stamp, "folder-69")!!.name)
            sql(directory) { sqlite ->
                val prefix = identity.queryPrefix(LibrarySavedViewSelection(collection = "empty"))
                sqlite.rawQuery("EXPLAIN QUERY PLAN SELECT key,target_key FROM saved_view_indexes WHERE key>? AND key<? ORDER BY key LIMIT 33", arrayOf(prefix, prefix + "~")).use { assertTrue(it.moveToFirst()); assertTrue(it.getString(3).contains("SEARCH")); assertFalse(it.getString(3).contains("SCAN")) }
            }
            val fixture = AndroidLibraryFacadeFixture(store)
            try {
                fixture.start()
                val prepared = withContext(Dispatchers.Main) { fixture.sync.preparePortableExport(kotlinx.serialization.json.JsonObject(emptyMap()), fixture.sync.captureWriteContext(), "views.json") }
                val document = Json.parseToJsonElement(prepared.file.readText()) as kotlinx.serialization.json.JsonObject
                val records = document.getValue("localSavedEvidence") as kotlinx.serialization.json.JsonArray
                assertEquals(2_001, records.count { (it as? kotlinx.serialization.json.JsonObject)?.get("kind") == kotlinx.serialization.json.JsonPrimitive("viewItem") })
                assertTrue(exportContains(records, "Offscreen accepted note")); assertFalse(document.containsExportKey(setOf("arabicText", "englishText")))
                fixture.sync.discardPreparedExport(prepared)
            } finally { fixture.stop() }
            db.close()
            store.beginDeletion(owner.subject, owner.namespace); store.markDeletionBackendComplete(owner.subject, owner.namespace)
            for (table in listOf("saved_view_heads", "saved_view_rows", "saved_view_indexes")) assertEquals(0, count(directory, table))
        }
    }
    @Test fun viewDraftAllocationNeverRevivesMissingHeadsAndScopedExportRetainsOrphans() = runBlocking {
        isolated { store, _, directory ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); store.claimGuestForSync(owner); val scope = store.beginSavedAssembly(owner)
            journal(directory).use { db ->
                val empty = db.createSavedViewRows(scope)
                sql(directory) { it.delete("saved_view_heads", "key=?", arrayOf(empty.identity.key)) }
                try { db.draftSavedViewStamp(empty.identity); fail("Missing empty head revived") } catch (_: LibrarySyncFailure) { }
                val allocated = db.createSavedViewRows(scope); assertNotEquals(empty.identity, allocated.identity)
                val item = LibrarySavedViewItem(SavedPrivateItem("private-target", 1.0, 1.0, noteContent = "Orphan retained note", noteCreatedAt = 1.0, noteUpdatedAt = 1.0))
                val orphan = db.writeSavedViewRows(allocated, listOf(item))
                sql(directory) { it.delete("saved_view_heads", "key=?", arrayOf(orphan.identity.key)) }
                try { db.draftSavedViewItem(orphan, "private-target"); fail("Orphan was current") } catch (_: LibrarySyncFailure) { }
                val replacement = db.createSavedViewRows(scope); assertNotEquals(orphan.identity, replacement.identity); assertNull(db.draftSavedViewItem(replacement, "private-target"))
                val oldOwner = owner.copy(key = "old-owner"); store.claimGuestForSync(oldOwner); val oldScope = store.beginSavedAssembly(oldOwner)
                val old = db.writeSavedViewRows(db.createSavedViewRows(oldScope), listOf(item.copy(value = item.value.copy(noteContent = "Old owner retained note"))))
                sql(directory) { it.delete("local_accounts", "key=?", arrayOf(oldOwner.storageKey)) }
                try { db.draftSavedViewItem(old, "private-target"); fail("Partitionless owner admitted") } catch (_: LibrarySyncFailure.SessionChanged) { }
                val peer = owner.copy(key = "foreign-owner", subject = "foreign-subject"); store.claimGuestForSync(peer); val peerScope = store.beginSavedAssembly(peer)
                val foreign = db.writeSavedViewRows(db.createSavedViewRows(peerScope), listOf(item.copy(value = item.value.copy(noteContent = "Foreign private note"))))
                val fence = store.prepareOutcomeExport(owner) { true }; val records = mutableListOf<kotlinx.serialization.json.JsonElement>(); var after: String? = null
                do { val page = store.savedExportRecords(fence, 5, after); records.addAll(page.first); after = page.second; if (page.third) break } while (true)
                val values = kotlinx.serialization.json.JsonArray(records)
                assertTrue(exportContains(values, "Orphan retained note")); assertTrue(exportContains(values, "Old owner retained note")); assertFalse(exportContains(values, "Foreign private note"))
                note(store, "Unclaimed guest original")
                store.beginDeletion(owner.subject, owner.namespace); store.markDeletionBackendComplete(owner.subject, owner.namespace)
                assertEquals("Foreign private note", db.draftSavedViewItem(foreign, "private-target")!!.value.noteContent)
                assertEquals("Unclaimed guest original", store.snapshots().notes.single().content)
            }
        }
    }
    @Test fun viewDraftSerialLimitsAndActualSqliteAbortPreserveRowsIndexesAndFence() = runBlocking {
        isolated { store, _, directory ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); store.claimGuestForSync(owner); val scope = store.beginSavedAssembly(owner)
            journal(directory).use { db ->
                val initial = db.createSavedViewRows(scope)
                val item = LibrarySavedViewItem(SavedPrivateItem("target", 1.0, 1.0, bookmarkCreatedAt = 1.0))
                sql(directory) { it.execSQL("UPDATE saved_view_heads SET serial=9007199254740990 WHERE key=?", arrayOf(initial.identity.key)) }
                val terminal = db.draftSavedViewStamp(initial.identity); assertTrue(db.draftSavedViewPage(terminal, LibrarySavedViewSelection()).items.isEmpty())
                val fence = store.prepareOutcomeExport(owner) { true }
                try { db.writeSavedViewRows(terminal, listOf(item)); fail("Terminal serial accepted write") } catch (_: LibrarySyncFailure.StoreUnavailable) { }
                assertNull(db.draftSavedViewItem(terminal, "target")); store.validateOutcomeExport(fence)
                assertEquals(1, store.savedExportRecords(fence, 4, null).first.size)
                sql(directory) { it.execSQL("UPDATE saved_view_heads SET serial=0 WHERE key=?", arrayOf(initial.identity.key)); it.execSQL("CREATE TRIGGER fail_view_serial BEFORE UPDATE OF serial ON saved_view_heads BEGIN SELECT RAISE(ABORT,'injected'); END") }
                try { db.writeSavedViewRows(initial, listOf(item)); fail("Failed serial committed child rows") } catch (_: android.database.sqlite.SQLiteException) { }
                assertNull(db.draftSavedViewItem(initial, "target")); assertEquals(0, count(directory, "saved_view_indexes")); store.validateOutcomeExport(fence)
                sql(directory) { it.execSQL("DROP TRIGGER fail_view_serial") }
                val accepted = db.writeSavedViewRows(initial, listOf(item)); assertEquals(item, db.draftSavedViewItem(accepted, "target"))
                val captured = store.prepareOutcomeExport(owner) { true }
                sql(directory) { it.execSQL("UPDATE saved_view_heads SET serial=0.5 WHERE key=?", arrayOf(initial.identity.key)) }
                try { db.draftSavedViewStamp(initial.identity); fail("Fractional serial read") } catch (_: LibrarySyncFailure) { }
                try { store.savedExportRecords(captured, 4, null); fail("Fractional serial exported") } catch (_: LibrarySyncFailure) { }
                sql(directory) { it.execSQL("UPDATE saved_view_heads SET serial=? WHERE key=?", arrayOf<Any>(accepted.serial, initial.identity.key)); it.execSQL("UPDATE saved_view_rows SET kind=4294967297") }
                try { db.draftSavedViewItem(accepted, "target"); fail("Overflow kind read") } catch (_: LibrarySyncFailure) { }
                try { store.savedExportRecords(captured, 5, null); fail("Overflow kind exported") } catch (_: LibrarySyncFailure) { }
            }
        }
    }
    private fun observationOwner(state: LibraryPartitionState) = LibrarySyncOwner(state.savedSnapshot?.ownerKey ?: "owner-a", "subject-a")
    private fun observation(state: LibraryPartitionState, owner: LibrarySyncOwner = observationOwner(state)) = LibrarySavedObservation.legacy(owner, state.savedSnapshot)
    private fun legacyProjection(state: LibraryPartitionState) = LibraryProjection(state, observationOwner(state), observation(state))
    private fun savedPlan(reply: SavedFactsReply, owner: LibrarySyncOwner, previous: LibrarySavedReadPosition? = null, requested: String? = null): LibrarySavedPagePlan =
        when (val value = LibrarySavedPolicy.inspect(reply, owner, previous, requested)) {
            is LibrarySavedPageDecision.Append -> value.plan
            else -> throw LibrarySyncFailure.InvalidReceipt
        }
    private fun rejectsSaved(block: () -> Unit) { try { block(); fail("Malformed Saved input accepted") } catch (_: LibrarySyncFailure) { } }
    @Test fun savedFoldMatchesActualBackendParityAndFingerprints() {
        val facts = Json.decodeFromString<List<SavedFact>>(LibrarySavedParityVector.factsJSON)
        val expected = Json.decodeFromString<SavedPrivateItem>(LibrarySavedParityVector.expectedJSON)
        var result: LibrarySavedProjection? = null
        facts.forEachIndexed { index, fact ->
            assertEquals(LibrarySavedParityVector.digests[index], fact.savedFingerprint())
            result = LibrarySavedPolicy.fold(fact, result)
        }
        val row = result
        assertTrue(row is LibrarySavedProjection.Item)
        if (row !is LibrarySavedProjection.Item) return
        assertEquals(expected, row.value); assertEquals(0L, row.firstOrdinal)
    }
    @Test fun savedCanonicalReplacementClearsFieldsAndPreservesFirstEncounter() {
        val original = SavedPrivateItem("missing-public-target", 1.0, 30.0, 1.0, 2.0, "Original", 3.0, 4.0, "old-folder", 30.0)
        val first = LibrarySavedPolicy.fold(SavedFact.Item("source-a", 0.0, original), null)
        val replacement = SavedPrivateItem(original.hadithId, 5.0, 5.0)
        assertEquals(LibrarySavedProjection.Item(replacement, 0L), LibrarySavedPolicy.fold(SavedFact.Item("source-b", 1.0, replacement), first))
    }
    @Test fun savedLegacyOnlyClockAndEqualNotePrecedence() {
        val facts = listOf(SavedFact.Bookmark("b1", 0.0, "h", 100.0), SavedFact.Bookmark("b2", 1.0, "h", 20.0),
            SavedFact.Favorite("f1", 2.0, "h", 200.0), SavedFact.Note("n1", 3.0, "h", "First note", 10.0, 50.0), SavedFact.Note("n2", 4.0, "h", "Equal note loses", 5.0, 50.0))
        var result: LibrarySavedProjection? = null
        facts.forEach { result = LibrarySavedPolicy.fold(it, result) }
        val row = result
        assertTrue(row is LibrarySavedProjection.Item)
        if (row !is LibrarySavedProjection.Item) return
        assertEquals(20.0, row.value.bookmarkCreatedAt); assertEquals(200.0, row.value.favoriteCreatedAt)
        assertEquals(5.0, row.value.createdAt, 0.0); assertEquals(100.0, row.value.updatedAt, 0.0); assertEquals(0L, row.firstOrdinal)
        assertEquals("First note", row.value.noteContent); assertEquals(10.0, row.value.noteCreatedAt)
    }
    @Test fun savedEmptyPageAndCheckpointRoundtripThenTerminalRecheck() {
        val owner = LibrarySyncOwner("owner", "subject")
        val first = savedPlan(SavedFactsReply.Page(owner.key, 3.0, "root", null, 0.0, emptyList(), "next"), owner)
        val reopened = Json.decodeFromString<LibrarySavedReadPosition>(Json.encodeToString(first.position))
        assertEquals(first.position, reopened); assertEquals(0L, reopened.nextOrdinal)
        val terminal = savedPlan(SavedFactsReply.Complete(owner.key, 3.0, "root", "next", 0.0, emptyList(), 0.0, "finish"), owner, reopened, "next")
        LibrarySavedPolicy.confirm(SavedFactsReply.Complete(owner.key, 3.0, "root", "finish", 0.0, emptyList(), 0.0, "finish"), terminal.position)
        rejectsSaved { LibrarySavedPolicy.confirm(SavedFactsReply.Complete(owner.key, 4.0, "root", "finish", 0.0, emptyList(), 0.0, "finish"), terminal.position) }
        rejectsSaved { LibrarySavedPolicy.confirm(SavedFactsReply.Restart("saved_changed"), terminal.position) }
        rejectsSaved { LibrarySavedPolicy.inspect(SavedFactsReply.Page(owner.key, 3.0, "root", "finish", 0.0, emptyList(), "again"), owner, terminal.position, "finish") }
    }
    @Test fun savedPageRejectsOwnerRootInputRevisionOrdinalAndCycleMismatch() {
        val owner = LibrarySyncOwner("owner", "subject")
        val first = savedPlan(SavedFactsReply.Page(owner.key, 1.0, "root", null, 0.0, emptyList(), "next"), owner)
        val invalid = listOf(SavedFactsReply.Page("other", 1.0, "root", "next", 0.0, emptyList(), "new"),
            SavedFactsReply.Page(owner.key, 2.0, "root", "next", 0.0, emptyList(), "new"), SavedFactsReply.Page(owner.key, 1.0, "other-root", "next", 0.0, emptyList(), "new"),
            SavedFactsReply.Page(owner.key, 1.0, "root", "wrong", 0.0, emptyList(), "new"), SavedFactsReply.Page(owner.key, 1.0, "root", "next", 1.0, emptyList(), "new"),
            SavedFactsReply.Page(owner.key, 1.0, "root", "next", 0.0, emptyList(), "next"), SavedFactsReply.Complete(owner.key, 1.0, "root", "next", 0.0, emptyList(), 1.0, "finish"), SavedFactsReply.Restart("unrecognized"))
        invalid.forEach { reply -> rejectsSaved { LibrarySavedPolicy.inspect(reply, owner, first.position, "next") } }
        assertEquals(0L, first.position.nextOrdinal)
    }
    @Test fun savedPhaseAndWireBoundsRejectMalformedFacts() {
        val owner = LibrarySyncOwner("owner", "subject")
        val note = SavedFact.Note("n", 0.0, "h", " \nعربى ", 1.0, 2.0)
        val first = savedPlan(SavedFactsReply.Page(owner.key, 1.0, "root", null, 0.0, listOf(note), "next"), owner)
        val backwards = SavedFact.Item("i", 1.0, SavedPrivateItem("h", 1.0, 1.0))
        rejectsSaved { LibrarySavedPolicy.inspect(SavedFactsReply.Page(owner.key, 1.0, "root", "next", 1.0, listOf(backwards), "new"), owner, first.position, "next") }
        listOf(-1.0, 0.5, Double.POSITIVE_INFINITY, Double.NaN, 9_007_199_254_740_992.0).forEach { number -> rejectsSaved { LibrarySavedPolicy.integer(number) } }
        rejectsSaved { LibrarySavedPolicy.validate(SavedFact.Note("n", 0.0, "h", "ع".repeat(20_000), 1.0, 2.0)) }
        val result = LibrarySavedPolicy.fold(note, null)
        assertTrue(result is LibrarySavedProjection.Item)
        if (result is LibrarySavedProjection.Item) { assertEquals("h", result.value.hadithId); assertEquals(" \nعربى ", result.value.noteContent) }
    }

    @Test fun savedReadBoundaryUsesActualBackendWireAndPreservesCompleteText() {
        val head = Json.decodeFromString<SavedReadHead>(LibrarySavedReadsParityVector.headJSON)
        val owner = LibrarySyncOwner(head.ownerKey, "subject-a"); val target = "10002;hadiths"
        assertEquals(1.0, LibrarySavedReadPolicy.invalidation(head, owner).version, 0.0)
        val metadata = LibrarySavedReadPolicy.reference(Json.decodeFromString(LibrarySavedReadsParityVector.referenceJSON), owner, target)
        assertTrue(metadata is LibrarySavedReferenceState.Available)
        if (metadata is LibrarySavedReferenceState.Available) { assertEquals(target, metadata.reference.hadithID); assertEquals("bukhari", metadata.reference.collectionSlug) }
        val text = LibrarySavedReadPolicy.text(Json.decodeFromString(LibrarySavedReadsParityVector.textJSON), owner, target)
        assertTrue(text is LibrarySavedTextState.Available)
        if (text is LibrarySavedTextState.Available) { assertEquals("  إِنَّمَا\n", text.text.reference.arabicText); assertEquals("Actions \"by intentions\".\n", text.text.reference.englishText) }
        val arabic = "ع\n".repeat(100_000); val english = "\"\\\u0000".repeat(30_000)
        val large = LibrarySavedReadPolicy.text(SavedTextReply.Available(owner.key, target, SyncHadithSummary(target, "1", "bukhari", "Bukhari", "1", arabic, english, "Bukhari 1")), owner, target)
        assertTrue(large is LibrarySavedTextState.Available)
        if (large is LibrarySavedTextState.Available) { assertEquals(arabic, large.text.reference.arabicText); assertEquals(english, large.text.reference.englishText) }
    }
    @Test fun savedReadBoundaryRejectsForeignWrongTargetInvalidHeadAndUnknownUnavailable() {
        val owner = LibrarySyncOwner("owner-a", "subject-a"); val target = "target"
        listOf(-1.0, 0.5, Double.POSITIVE_INFINITY, 9_007_199_254_740_992.0).forEach { rejectsSaved { LibrarySavedReadPolicy.invalidation(SavedReadHead(owner.key, it), owner) } }
        rejectsSaved { LibrarySavedReadPolicy.invalidation(SavedReadHead("other", 1.0), owner) }
        assertEquals(LibrarySavedReferenceState.Missing, LibrarySavedReadPolicy.reference(SavedReferenceReply.Missing(owner.key, target), owner, target))
        assertEquals(LibrarySavedTextState.Unavailable, LibrarySavedReadPolicy.text(SavedTextReply.Unavailable(owner.key, target, "text_too_large"), owner, target))
        rejectsSaved { LibrarySavedReadPolicy.reference(SavedReferenceReply.Missing("other", target), owner, target) }
        rejectsSaved { LibrarySavedReadPolicy.text(SavedTextReply.Missing(owner.key, "other"), owner, target) }
        rejectsSaved { LibrarySavedReadPolicy.reference(SavedReferenceReply.Unavailable(owner.key, target, "invented"), owner, target) }
        rejectsSaved { LibrarySavedReadPolicy.reference(SavedReferenceReply.Available(owner.key, target, SavedHadithReference("other", "1", "bukhari", "Bukhari", null, "")), owner, target) }
        rejectsSaved { LibrarySavedReadPolicy.reference(SavedReferenceReply.Available(owner.key, target, SavedHadithReference(target, "1", "bukhari", "ع".repeat(LibrarySyncLimits.savedReferenceBytes), null, "")), owner, target) }
    }
    @Test fun savedReadTransportInvalidationNeverObservesPrivateRevisionAndQuietBindingExpires() = runBlocking {
        isolated { store, _, _ ->
            val fixture = AndroidSavedReadFixture(store)
            try {
                fixture.start(); val context = fixture.sync.captureSavedReadContext(); val before = store.syncPartition(context.owner)
                val invalidation = async { fixture.sync.savedInvalidations(context).first() }
                fixture.heads.subscriptionCount.first { it > 0 }; fixture.heads.emit(SavedReadHead(context.owner.key, 999.0))
                assertEquals(999.0, invalidation.await().version, 0.0); assertEquals(before, store.syncPartition(context.owner)); assertNull(store.activeSavedGeneration(context.owner))
                assertTrue(fixture.sync.savedReference(fixture.target, context) is LibrarySavedReferenceState.Available)
                fixture.now = context.validUntil + 1; fixture.start()
                try { fixture.sync.savedInvalidations(context).first(); fail("Old binding remained current") } catch (_: LibrarySyncFailure) { }
            } finally { fixture.stop() }
            val quiet = AndroidSavedReadFixture(store); quiet.bindingTTL = 100.0
            try {
                quiet.start(); val context = quiet.sync.captureSavedReadContext()
                try { withTimeout(2_000) { quiet.sync.savedInvalidations(context).first() }; fail("Quiet expired binding remained open") } catch (_: LibrarySyncFailure) { }
            } finally { quiet.stop() }
        }
    }
    @Test fun savedReadTransportDelayedCollectionKeepsAbsoluteExpiryAndRejectsStaleScopeBeforeTransport() = runBlocking {
        isolated { store, _, _ ->
            val fixture = AndroidSavedReadFixture(store)
            try {
                fixture.start(); val context = fixture.sync.captureSavedReadContext(); val flow = fixture.sync.savedInvalidations(context)
                assertEquals(0, fixture.headStarts); fixture.now = context.validUntil - 100
                try { withTimeout(1_000) { flow.first() }; fail("Delayed collection extended expiry") } catch (_: LibrarySyncFailure) { }
                assertEquals(1, fixture.headStarts)
                val stale = fixture.sync.savedInvalidations(context); fixture.session.value = null
                try { withTimeout(1_000) { stale.first() }; fail("Delayed stale collection started") } catch (_: LibrarySyncFailure) { }
                assertEquals(1, fixture.headStarts)
            } finally { fixture.stop() }
        }
    }
    @Test fun savedReadTransportClosedHeadStreamFailsWithoutWaitingForBindingExpiry() = runBlocking {
        isolated { store, _, _ ->
            val fixture = AndroidSavedReadFixture(store)
            try {
                fixture.start(); fixture.headFetch = { kotlinx.coroutines.flow.emptyFlow() }
                try { withTimeout(1_000) { fixture.sync.savedInvalidations(fixture.sync.captureSavedReadContext()).collect { fail("Empty transport emitted a head") } }; fail("Closed head stream silently finished") } catch (_: LibrarySyncFailure) { }
            } finally { fixture.stop() }
        }
    }
    @Test fun savedReadTransportRejectsLateHydrationAfterBindingRenewalAndAccountSwitch() = runBlocking {
        isolated { store, _, _ ->
            val fixture = AndroidSavedReadFixture(store)
            try {
                fixture.start(); val context = fixture.sync.captureSavedReadContext(); val started = CompletableDeferred<Unit>(); val release = CompletableDeferred<SavedReferenceReply>()
                fixture.referenceFetch = { _, _ -> started.complete(Unit); release.await() }
                val late = async { runCatching { fixture.sync.savedReference(fixture.target, context) } }
                started.await(); fixture.now = context.validUntil + 1; fixture.start(); release.complete(fixture.referenceReply)
                assertTrue(late.await().isFailure); fixture.referenceFetch = null
                val renewed = fixture.sync.captureSavedReadContext(); assertTrue(fixture.sync.savedReference(fixture.target, renewed) is LibrarySavedReferenceState.Available)
                val textStarted = CompletableDeferred<Unit>(); val textRelease = CompletableDeferred<SavedTextReply>()
                fixture.textFetch = { _, _ -> textStarted.complete(Unit); textRelease.await() }
                val text = async { runCatching { fixture.sync.savedText(fixture.target, renewed) } }
                textStarted.await(); fixture.session.value = LibrarySyncSession("session-b", "subject-b"); fixture.start(); textRelease.complete(fixture.textReply)
                assertTrue(text.await().isFailure); assertEquals("subject-b", fixture.sync.owner.value?.subject)
            } finally { fixture.stop() }
        }
    }

    private fun savedReply(input: String?, owner: LibrarySyncOwner, facts: List<SavedFact>, version: Double = 9.0): SavedFactsReply {
        if (input == null) return SavedFactsReply.Page(owner.key, version, "private-root-proof", null, 0.0, emptyList(), "cursor:0")
        val index = if (input.startsWith("cursor:")) input.removePrefix("cursor:").toIntOrNull() else null
        if (index == null || index !in 0..facts.size) throw LibrarySyncFailure.InvalidReceipt
        val rows = if (index < facts.size) listOf(facts[index]) else emptyList()
        if (index + rows.size == facts.size) return SavedFactsReply.Complete(owner.key, version, "private-root-proof", input, index.toDouble(), rows, facts.size.toDouble(), "private-completion-proof")
        return SavedFactsReply.Page(owner.key, version, "private-root-proof", input, index.toDouble(), rows, "cursor:${index + rows.size}")
    }
    private fun savedLargeFacts(): List<SavedFact> = buildList {
        add(SavedFact.Folder("empty-folder", 0.0, SyncFolderRow("empty-folder", "Empty folder", 1.0)))
        repeat(502) { index -> add(SavedFact.Item("canonical-$index", size.toDouble(), SavedPrivateItem("private-target-$index", 10.0, 11.0,
            if (index == 0) 1_000.0 else 1.0, null, if (index == 0) "Private original mentions capability" else null, if (index == 0) 10.0 else null, if (index == 0) 10.0 else null, null, 11.0))) }
        repeat(502) { index -> add(SavedFact.Bookmark("legacy-$index", size.toDouble(), "private-target-0", (1_000 - index).toDouble())) }
    }
    private fun savedStage(stage: LibrarySavedStage): String = when (stage) {
        LibrarySavedStage.Collecting -> "collecting"; is LibrarySavedStage.Folding -> "folding"; is LibrarySavedStage.CheckingPages -> "checking_pages"; is LibrarySavedStage.Verifying -> "verifying"; LibrarySavedStage.Prepared -> "prepared"; LibrarySavedStage.Restart -> "restart"; is LibrarySavedStage.Unavailable -> "unavailable"
    }
    @Test fun savedDiskCollectionFoldAndVerificationMatchBackendAfterReopen() = runBlocking {
        isolated { initial, reopen, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); var store = initial
            store.claimGuestForSync(owner); store.cacheSavedSnapshot(SyncSavedSnapshot(owner.key, 1.0, emptyList(), emptyList()), owner)
            val original = store.syncPartition(owner); val lease = store.beginSavedAssembly(owner)
            val facts = Json.decodeFromString<List<SavedFact>>(LibrarySavedParityVector.factsJSON)
            var previous = ""; val seen = mutableSetOf<String>()
            for (step in 0 until 100) {
                val checkpoint = store.collectSavedStep(lease, { true }) { savedReply(it, owner, facts) }
                val phase = savedStage(checkpoint.stage); seen.add(phase)
                if (phase != previous) { store = reopen(); assertEquals(lease, store.beginSavedAssembly(owner)); assertEquals(checkpoint, store.savedCheckpoint(lease)); previous = phase }
                if (checkpoint.stage == LibrarySavedStage.Prepared) break
            }
            assertEquals(LibrarySavedStage.Prepared, store.savedCheckpoint(lease).stage)
            assertTrue(seen.containsAll(listOf("collecting", "folding", "checking_pages", "verifying", "prepared")))
            val page = store.preparedSavedPage(lease, null)
            val expected = Json.decodeFromString<SavedPrivateItem>(LibrarySavedParityVector.expectedJSON)
            assertEquals(listOf(LibrarySavedProjection.Item(expected, 0L)), page.rows); assertTrue(page.done)
            assertEquals(original, store.syncPartition(owner))
        }
    }
    @Test fun savedLargeJournalHasBoundedPagesPreservesDuplicatesAndNeverAdvancesJoinedBase() = runBlocking {
        isolated { initial, reopen, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); var store = initial
            store.claimGuestForSync(owner); store.cacheSavedSnapshot(SyncSavedSnapshot(owner.key, 1.0, emptyList(), emptyList()), owner)
            val original = store.syncPartition(owner); val lease = store.beginSavedAssembly(owner); val facts = savedLargeFacts(); val phases = mutableSetOf<String>()
            for (step in 0 until 2_000) {
                val checkpoint = store.collectSavedStep(lease, { true }) { savedReply(it, owner, facts) }
                val phase = savedStage(checkpoint.stage)
                if (phase !in phases || step == 17) { phases.add(phase); store = reopen(); assertEquals(checkpoint, store.savedCheckpoint(lease)) }
                if (checkpoint.stage == LibrarySavedStage.Prepared) break
                if (step == 20) { try { store.preparedSavedPage(lease, null); fail("Partial data exposed as prepared") } catch (_: LibrarySyncFailure) { } }
            }
            val checkpoint = store.savedCheckpoint(lease)
            assertEquals(LibrarySavedStage.Prepared, checkpoint.stage); assertEquals(1_005L, checkpoint.next); assertEquals(LibrarySavedCounts(502, 1), checkpoint.counts)
            var cursor: String? = null; val values = mutableListOf<LibrarySavedProjection>()
            while (true) {
                val page = store.preparedSavedPage(lease, cursor); assertTrue(page.rows.size <= 8); values.addAll(page.rows); cursor = page.next
                if (page.done) break
            }
            assertEquals(503, values.size)
            val rows = values.filterIsInstance<LibrarySavedProjection.Item>().map { it.value }
            assertEquals(502, rows.map { it.hadithId }.toSet().size)
            assertEquals(499.0, rows.first { it.hadithId == "private-target-0" }.bookmarkCreatedAt)
            assertEquals("Private original mentions capability", rows.first { it.hadithId == "private-target-0" }.noteContent)
            var start = 0L; var raw = 0
            while (true) { val page = store.savedRawPage(lease, start); assertTrue(page.facts.size <= 8); raw += page.facts.size; start = page.next; if (start == checkpoint.next) break }
            assertEquals(facts.size, raw); assertEquals(original, store.syncPartition(owner))
        }
    }

    private suspend fun prepareSaved(store: GuestDataStore, lease: LibrarySavedLease, facts: List<SavedFact>, version: Double = 9.0) {
        repeat(facts.size * 3 + 100) {
            if (store.collectSavedStep(lease, { true }) { input -> savedReply(input, lease.owner, facts, version) }.stage == LibrarySavedStage.Prepared) return
        }; fail("Saved preparation did not finish")
    }
    private fun terminalSavedReply(checkpoint: LibrarySavedCheckpoint): SavedFactsReply.Complete {
        val position = checkpoint.position ?: throw LibrarySyncFailure.InvalidReceipt
        return SavedFactsReply.Complete(position.owner.key, position.version, position.assemblyID, position.continuation.token, position.nextOrdinal.toDouble(), emptyList(), position.nextOrdinal.toDouble(), position.continuation.token)
    }
    private suspend fun activateSaved(store: GuestDataStore, lease: LibrarySavedLease): LibrarySavedActiveGeneration {
        val reply = terminalSavedReply(store.savedCheckpoint(lease))
        return when (val result = store.activateSavedGeneration(lease, { true }) { reply }) {
            is LibrarySavedActivation.Active -> result.handle
            else -> throw LibrarySyncFailure.InvalidReceipt
        }
    }
    @Test fun savedActivationRequiresExactFinalCheckAndReplaysWithoutClockChange() = runBlocking {
        isolated { store, reopen, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); store.claimGuestForSync(owner)
            val original = store.syncPartition(owner); val lease = store.beginSavedAssembly(owner)
            assertNull(store.activeSavedGeneration(owner))
            try { store.activateSavedGeneration(lease, { true }) { fail("Incomplete candidate queried completion"); throw LibrarySyncFailure.InvalidReceipt }; fail("Incomplete activated") } catch (_: LibrarySyncFailure) { }
            val facts = Json.decodeFromString<List<SavedFact>>(LibrarySavedParityVector.factsJSON); prepareSaved(store, lease, facts)
            val prepared = store.savedCheckpoint(lease); val reply = terminalSavedReply(prepared)
            try { store.activateSavedGeneration(lease, { true }) { reply.copy(version = 10.0) }; fail("Changed version activated") } catch (_: LibrarySyncFailure) { }
            try { store.activateSavedGeneration(lease, { true }) { throw LibrarySyncFailure.StoreUnavailable }; fail("Network failure activated") } catch (_: LibrarySyncFailure) { }
            assertEquals(prepared, store.savedCheckpoint(lease)); assertNull(store.activeSavedGeneration(owner))
            val fence = store.prepareOutcomeExport(owner) { true }; val active = activateSaved(store, lease)
            try { store.validateOutcomeExport(fence); fail("Activation did not invalidate export") } catch (_: LibrarySyncFailure) { }
            assertEquals(9.0, active.version, 0.0)
            val stable = store.prepareOutcomeExport(owner) { true }
            assertEquals(LibrarySavedActivation.Active(active), store.activateSavedGeneration(lease, { true }) { fail("Replay queried completion"); throw LibrarySyncFailure.InvalidReceipt })
            store.validateOutcomeExport(stable)
            val recovered = reopen(); assertEquals(active, recovered.activeSavedGeneration(owner)); assertEquals(store.preparedSavedPage(lease, null).rows, recovered.activeSavedPage(active, null).rows)
            assertEquals(original, recovered.syncPartition(owner))
        }
    }
    @Test fun savedThreeGenerationsKeepOldActiveUntilCommitAndCleanRetiredRowsInBatches() = runBlocking {
        isolated { initial, reopen, directory ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); var store = initial; store.claimGuestForSync(owner)
            val facts = (0 until 17).map { SavedFact.Note("note-$it", it.toDouble(), "target-$it", "Retained private note", 1.0, 2.0) }
            val first = store.beginSavedAssembly(owner); prepareSaved(store, first, facts); val old = activateSaved(store, first)
            val second = store.beginSavedAssembly(owner); assertEquals(first.epoch, second.epoch); assertNotEquals(first.generation, second.generation)
            assertEquals(8, store.activeSavedPage(old, null).rows.size)
            prepareSaved(store, second, facts, 10.0); val active = activateSaved(store, second)
            try { store.activeSavedPage(old, null); fail("Retired handle read") } catch (_: LibrarySyncFailure) { }
            try { store.beginSavedAssembly(owner); fail("Retirement overwritten") } catch (_: LibrarySyncFailure) { }
            val fence = store.prepareOutcomeExport(owner) { true }; val exported = store.savedExportRecords(fence, 0, null).first.toString()
            assertTrue(exported.contains("retiringGeneration")); assertTrue(exported.contains(first.generation)); assertTrue(exported.contains(second.generation)); assertFalse(exported.contains("private-completion-proof"))
            assertTrue(store.cleanupSavedGenerationStep(owner))
            android.database.sqlite.SQLiteDatabase.openDatabase(File(directory, "library_outcomes.db").path, null, 0).use { db ->
                db.rawQuery("SELECT COUNT(*) FROM saved_facts WHERE collection_key=?", arrayOf(first.collection)).use { it.moveToFirst(); assertEquals(9, it.getInt(0)) }
            }
            store = reopen()
            for (step in 0 until 100) { if (!store.cleanupSavedGenerationStep(owner)) break }
            android.database.sqlite.SQLiteDatabase.openDatabase(File(directory, "library_outcomes.db").path, null, 0).use { db ->
                for (table in listOf("saved_facts", "saved_pages", "saved_projection")) db.rawQuery("SELECT COUNT(*) FROM $table WHERE collection_key=?", arrayOf(first.collection)).use { it.moveToFirst(); assertEquals(0, it.getInt(0)) }
            }
            assertEquals(active, store.activeSavedGeneration(owner))
            val third = store.beginSavedAssembly(owner); prepareSaved(store, third, emptyList(), 11.0); val newest = activateSaved(store, third)
            assertEquals(11.0, newest.version, 0.0); assertTrue(store.activeSavedPage(newest, null).rows.isEmpty())
            try { store.activeSavedPage(active, null); fail("Old handle read newer generation") } catch (_: LibrarySyncFailure) { }
            store.beginDeletion(owner.subject, owner.namespace)
            try { store.activeSavedPage(newest, null); fail("Erasing generation remained visible") } catch (_: LibrarySyncFailure) { }
        }
    }
    @Test fun savedStoppedRefreshAndOccupiedRetirementPreserveActiveAndPreparedData() = runBlocking {
        isolated { store, _, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); store.claimGuestForSync(owner)
            val first = store.beginSavedAssembly(owner); prepareSaved(store, first, emptyList()); val old = activateSaved(store, first)
            val second = store.beginSavedAssembly(owner); prepareSaved(store, second, emptyList(), 10.0)
            assertEquals(LibrarySavedActivation.Restart, store.activateSavedGeneration(second, { true }) { SavedFactsReply.Restart("saved_changed") })
            assertEquals(old, store.activeSavedGeneration(owner))
            val third = store.replaceSavedCandidate(second)
            try { store.replaceSavedCandidate(third); fail("Retirement overwritten") } catch (_: LibrarySyncFailure) { }
            try { store.savedCheckpoint(second); fail("Replaced candidate remained current") } catch (_: LibrarySyncFailure) { }
            prepareSaved(store, third, emptyList(), 11.0); val prepared = store.savedCheckpoint(third)
            try { activateSaved(store, third); fail("Activation overwrote retirement") } catch (_: LibrarySyncFailure) { }
            assertEquals(prepared, store.savedCheckpoint(third)); assertEquals(old, store.activeSavedGeneration(owner))
            for (step in 0 until 100) { if (!store.cleanupSavedGenerationStep(owner)) break }
            val active = activateSaved(store, third)
            for (step in 0 until 100) { if (!store.cleanupSavedGenerationStep(owner)) break }
            val fourth = store.beginSavedAssembly(owner); prepareSaved(store, fourth, emptyList(), 12.0)
            assertEquals(LibrarySavedActivation.Unavailable(SavedFactsReplyUnavailableReason.PAGE_TOO_LARGE), store.activateSavedGeneration(fourth, { true }) { SavedFactsReply.Unavailable(SavedFactsReplyUnavailableReason.PAGE_TOO_LARGE) })
            assertEquals(active, store.activeSavedGeneration(owner))
        }
    }
    @Test fun savedFinalCheckCannotActivateAfterCandidateReplacementSessionChangeOrErase() = runBlocking {
        isolated { store, reopen, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); store.claimGuestForSync(owner)
            for (mode in 0 until 3) {
                val lease = store.beginSavedAssembly(owner); prepareSaved(store, lease, emptyList())
                val reply = terminalSavedReply(store.savedCheckpoint(lease)); val clone = reopen(); var current = true
                val started = CompletableDeferred<Unit>(); val release = CompletableDeferred<SavedFactsReply>()
                val late = async { runCatching { clone.activateSavedGeneration(lease, { current }) { started.complete(Unit); release.await() } } }
                started.await()
                when (mode) { 0 -> store.replaceSavedCandidate(lease); 1 -> current = false; else -> store.beginDeletion(owner.subject, owner.namespace) }
                release.complete(reply); assertTrue(late.await().isFailure)
                if (mode < 2) {
                    assertNull(store.activeSavedGeneration(owner)); if (mode == 1) store.replaceSavedCandidate(lease)
                    for (step in 0 until 100) { if (!store.cleanupSavedGenerationStep(owner)) break }
                }
            }
        }
    }
    @Test fun savedActivationPointerAndExportClockRollBackOnActualSqliteCheckpointAbort() = runBlocking {
        isolated { store, reopen, directory ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); store.claimGuestForSync(owner)
            val lease = store.beginSavedAssembly(owner); prepareSaved(store, lease, emptyList()); val before = store.savedCheckpoint(lease)
            val fence = store.prepareOutcomeExport(owner) { true }
            android.database.sqlite.SQLiteDatabase.openDatabase(File(directory, "library_outcomes.db").path, null, 0).use { it.execSQL("CREATE TRIGGER fail_saved_activation BEFORE UPDATE OF checkpoint ON saved_assemblies BEGIN SELECT RAISE(ABORT,'injected'); END") }
            try { activateSaved(store, lease); fail("Failed checkpoint left pointer") } catch (_: android.database.sqlite.SQLiteException) { }
            val recovered = reopen(); assertNull(recovered.activeSavedGeneration(owner)); assertEquals(before, recovered.savedCheckpoint(lease)); recovered.validateOutcomeExport(fence)
            android.database.sqlite.SQLiteDatabase.openDatabase(File(directory, "library_outcomes.db").path, null, 0).use { it.execSQL("DROP TRIGGER fail_saved_activation") }
            assertEquals(lease, activateSaved(recovered, lease).lease)
        }
    }
    @Test fun savedOverlappingCloneActivationsCommitOnePointerAndOneClockTransition() = runBlocking {
        isolated { store, reopen, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); store.claimGuestForSync(owner)
            val lease = store.beginSavedAssembly(owner); prepareSaved(store, lease, emptyList()); val reply = terminalSavedReply(store.savedCheckpoint(lease))
            val first = reopen(); val second = reopen(); val startedA = CompletableDeferred<Unit>(); val startedB = CompletableDeferred<Unit>()
            val releaseA = CompletableDeferred<SavedFactsReply>(); val releaseB = CompletableDeferred<SavedFactsReply>()
            val a = async { first.activateSavedGeneration(lease, { true }) { startedA.complete(Unit); releaseA.await() } }
            val b = async { second.activateSavedGeneration(lease, { true }) { startedB.complete(Unit); releaseB.await() } }
            startedA.await(); startedB.await(); releaseA.complete(reply); val accepted = a.await()
            val fence = store.prepareOutcomeExport(owner) { true }; releaseB.complete(reply)
            assertEquals(accepted, b.await()); store.validateOutcomeExport(fence)
            assertTrue(accepted is LibrarySavedActivation.Active)
            if (accepted is LibrarySavedActivation.Active) assertEquals(accepted.handle, reopen().activeSavedGeneration(owner))
        }
    }
    @Test fun savedOlderVerifiedRefreshCannotRegressActiveRevision() = runBlocking {
        isolated { store, _, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); store.claimGuestForSync(owner)
            val first = store.beginSavedAssembly(owner); prepareSaved(store, first, emptyList(), 10.0); val active = activateSaved(store, first)
            val second = store.beginSavedAssembly(owner); prepareSaved(store, second, emptyList(), 9.0)
            val prepared = store.savedCheckpoint(second); val fence = store.prepareOutcomeExport(owner) { true }
            try { activateSaved(store, second); fail("Older private revision activated") } catch (_: LibrarySyncFailure) { }
            assertEquals(active, store.activeSavedGeneration(owner)); assertEquals(prepared, store.savedCheckpoint(second)); store.validateOutcomeExport(fence)
        }
    }
    @Test fun savedActivationMigratesActualPriorSavedV3DiskWithoutLosingPreparedData() = runBlocking {
        isolated { store, reopen, directory ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); store.claimGuestForSync(owner)
            val lease = store.beginSavedAssembly(owner); val facts = Json.decodeFromString<List<SavedFact>>(LibrarySavedParityVector.factsJSON); prepareSaved(store, lease, facts)
            val before = store.savedCheckpoint(lease); val expected = store.preparedSavedPage(lease, null)
            File(directory, "guest_store.json").writeText(Json.encodeToString(GuestStoreFile(syncPartitions = listOf(LibrarySyncPartition(owner.storageKey, owner.subject, store.syncPartition(owner)!!)))))
            android.database.sqlite.SQLiteDatabase.openDatabase(File(directory, "library_outcomes.db").path, null, 0).use { db ->
                db.beginTransaction()
                try {
                    db.execSQL("ALTER TABLE saved_assemblies RENAME TO saved_assemblies_v4")
                    db.execSQL("CREATE TABLE saved_assemblies (scope_key TEXT PRIMARY KEY NOT NULL, subject TEXT NOT NULL, namespace TEXT NOT NULL, owner_key TEXT NOT NULL, lease TEXT NOT NULL, checkpoint TEXT NOT NULL, erasing INTEGER NOT NULL)")
                    db.execSQL("INSERT INTO saved_assemblies SELECT scope_key,subject,namespace,owner_key,lease,checkpoint,erasing FROM saved_assemblies_v4")
                    db.execSQL("DROP TABLE saved_assemblies_v4"); db.execSQL("CREATE INDEX saved_assemblies_owner ON saved_assemblies(subject,namespace,owner_key)")
                    for (table in listOf("local_import_rows", "local_import", "local_guest", "local_accounts", "local_deletions")) db.execSQL("DROP TABLE $table")
                    for (viewTable in listOf("saved_view_heads", "saved_view_rows", "saved_view_indexes")) db.execSQL("DROP TABLE $viewTable")
                    db.version = 3; db.setTransactionSuccessful()
                } finally { db.endTransaction() }
            }
            val recovered = reopen(); assertEquals(before, recovered.savedCheckpoint(lease)); assertEquals(expected, recovered.preparedSavedPage(lease, null)); assertNull(recovered.activeSavedGeneration(owner))
            val active = activateSaved(recovered, lease); assertEquals(expected.rows, recovered.activeSavedPage(active, null).rows)
            assertEquals(active, reopen().activeSavedGeneration(owner))
            android.database.sqlite.SQLiteDatabase.openDatabase(File(directory, "library_outcomes.db").path, null, 0).use { assertEquals(8, it.version) }
        }
    }
    @Test fun savedRawAndReceiptWritesRollBackTogetherOnActualSqliteAbort() = runBlocking {
        isolated { store, reopen, directory ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); store.claimGuestForSync(owner)
            val lease = store.beginSavedAssembly(owner); val facts = Json.decodeFromString<List<SavedFact>>(LibrarySavedParityVector.factsJSON)
            store.collectSavedStep(lease, { true }) { savedReply(it, owner, facts) }; val before = store.savedCheckpoint(lease)
            android.database.sqlite.SQLiteDatabase.openDatabase(File(directory, "library_outcomes.db").path, null, 0).use { it.execSQL("CREATE TRIGGER fail_saved_checkpoint BEFORE UPDATE OF checkpoint ON saved_assemblies BEGIN SELECT RAISE(ABORT,'injected'); END") }
            try { store.collectSavedStep(lease, { true }) { savedReply(it, owner, facts) }; fail("Failed checkpoint write committed") } catch (_: android.database.sqlite.SQLiteException) { }
            val recovered = reopen(); assertEquals(before, recovered.savedCheckpoint(lease)); assertTrue(recovered.savedRawPage(lease, 0).facts.isEmpty())
            android.database.sqlite.SQLiteDatabase.openDatabase(File(directory, "library_outcomes.db").path, null, 0).use { db ->
                db.rawQuery("SELECT COUNT(*) FROM saved_pages WHERE collection_key=?", arrayOf(lease.collection)).use { it.moveToFirst(); assertEquals(1, it.getInt(0)) }
                db.execSQL("DROP TRIGGER fail_saved_checkpoint")
            }
            prepareSaved(recovered, lease, facts); assertEquals(LibrarySavedStage.Prepared, recovered.savedCheckpoint(lease).stage)
        }
    }
    @Test fun savedHistoricalReplayIsExactAndDuplicateSourceOrChangedRetryCannotOverwrite() = runBlocking {
        isolated { store, reopen, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); store.claimGuestForSync(owner)
            val lease = store.beginSavedAssembly(owner); val facts = Json.decodeFromString<List<SavedFact>>(LibrarySavedParityVector.factsJSON).take(2)
            store.collectSavedStep(lease, { true }) { savedReply(it, owner, facts) }
            val clone = reopen(); val captured = CompletableDeferred<String?>(); val release = CompletableDeferred<SavedFactsReply>()
            val replay = async { clone.collectSavedStep(lease, { true }) { captured.complete(it); release.await() } }
            val input = captured.await(); store.collectSavedStep(lease, { true }) { savedReply(it, owner, facts) }
            val before = store.savedCheckpoint(lease); val fence = store.prepareOutcomeExport(owner) { true }
            release.complete(savedReply(input, owner, facts)); assertEquals(before, replay.await()); store.validateOutcomeExport(fence)
            val first = facts[0]
            if (first !is SavedFact.Item) error("Fixture lacks canonical row")
            try {
                store.collectSavedStep(lease, { true }) { requested -> SavedFactsReply.Complete(owner.key, 9.0, "private-root-proof", requested, 1.0, listOf(SavedFact.Item(first.sourceId, 1.0, first.value.copy(hadithId = "other-target"))), 2.0, "private-completion-proof") }
                fail("Reused source identity accepted")
            } catch (_: LibrarySyncFailure) { }
            assertEquals(before, store.savedCheckpoint(lease)); assertEquals(1, store.savedRawPage(lease, 0).facts.size)
            val changedClone = reopen(); val captured2 = CompletableDeferred<String?>(); val release2 = CompletableDeferred<SavedFactsReply>()
            val changed = async { runCatching { changedClone.collectSavedStep(lease, { true }) { captured2.complete(it); release2.await() } } }
            val input2 = captured2.await(); store.collectSavedStep(lease, { true }) { savedReply(it, owner, facts) }; val terminal = store.savedCheckpoint(lease)
            val second = facts[1]; if (second !is SavedFact.Bookmark) error("Fixture lacks bookmark")
            release2.complete(SavedFactsReply.Complete(owner.key, 9.0, "private-root-proof", input2, 1.0, listOf(second.copy(createdAt = second.createdAt + 1)), 2.0, "private-completion-proof"))
            assertTrue(changed.await().isFailure); assertEquals(terminal, store.savedCheckpoint(lease))
            prepareSaved(store, lease, facts)
        }
    }
    @Test fun savedRowsStreamInRealPortableExportAndSharedFenceRejectsLaterMutation() = runBlocking {
        isolated { store, _, directory ->
            val fixture = AndroidLibraryFacadeFixture(store)
            try {
                fixture.start(); val owner = LibrarySyncOwner("owner-a", "subject-a")
                val own = store.beginSavedAssembly(owner)
                val ownFacts = listOf(SavedFact.Note("own-source", 0.0, "own-target", "Own note says capability", 1.0, 2.0))
                prepareSaved(store, own, ownFacts)
                val others = listOf(LibrarySyncOwner("old-owner", owner.subject) to "Old owner retained note", LibrarySyncOwner("foreign-owner", "foreign-subject") to "Foreign private note", LibrarySyncOwner("old-owner", owner.subject, "other-deployment") to "Other deployment private note")
                for ((peer, text) in others) {
                    store.claimGuestForSync(peer); val lease = store.beginSavedAssembly(peer)
                    val facts = listOf(SavedFact.Note("peer-source", 0.0, "peer-target", text, 1.0, 2.0))
                    repeat(2) { store.collectSavedStep(lease, { true }) { savedReply(it, peer, facts) } }
                }
                sql(directory) { db -> db.delete("local_accounts", "key=?", arrayOf(others[0].first.storageKey)) }
                val captured = withContext(Dispatchers.Main) { fixture.sync.captureWriteContext() }
                val prepared = fixture.sync.preparePortableExport(kotlinx.serialization.json.JsonObject(emptyMap()), captured, "saved.json")
                try {
                    val json = Json.parseToJsonElement(prepared.file.readText())
                    assertTrue(json is kotlinx.serialization.json.JsonObject && json.containsKey("localSavedEvidence"))
                    assertTrue(exportContains(json, "Own note says capability")); assertTrue(exportContains(json, "Old owner retained note"))
                    assertFalse(exportContains(json, "Foreign private note")); assertFalse(exportContains(json, "Other deployment private note"))
                    assertFalse(prepared.file.readText().contains("private-completion-proof")); assertFalse(prepared.file.readText().contains("private-root-proof"))
                    val another = LibrarySyncOwner("another-old-owner", owner.subject); store.claimGuestForSync(another); store.beginSavedAssembly(another)
                    try { fixture.sync.copyPreparedExport(prepared, java.io.ByteArrayOutputStream()); fail("Stale combined export accepted") } catch (_: Exception) { }
                } finally { fixture.sync.discardPreparedExport(prepared) }
            } finally { fixture.stop() }
        }
    }
    @Test fun savedErasureFencesSuspendedReplyAndResumesBoundedCleanupAcrossReopen() = runBlocking {
        isolated { store, reopen, directory ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); val other = LibrarySyncOwner("owner-b", "subject-b")
            store.claimGuestForSync(owner); store.claimGuestForSync(other)
            val lease = store.beginSavedAssembly(owner); val peer = store.beginSavedAssembly(other); val facts = savedLargeFacts().take(32)
            repeat(18) { store.collectSavedStep(lease, { true }) { savedReply(it, owner, facts) } }
            val peerBefore = store.savedCheckpoint(peer); val captured = CompletableDeferred<String?>(); val release = CompletableDeferred<SavedFactsReply>(); val clone = reopen()
            val late = async { runCatching { clone.collectSavedStep(lease, { true }) { captured.complete(it); release.await() } } }
            val input = captured.await(); store.beginDeletion(owner.subject, owner.namespace)
            assertTrue(store.eraseSavedStep(owner.subject, owner.namespace, null))
            android.database.sqlite.SQLiteDatabase.openDatabase(File(directory, "library_outcomes.db").path, null, 0).use { db ->
                db.rawQuery("SELECT COUNT(*) FROM saved_facts WHERE subject=?", arrayOf(owner.subject)).use { it.moveToFirst(); assertEquals(9, it.getInt(0)) }
            }
            release.complete(savedReply(input, owner, facts)); assertTrue(late.await().isFailure)
            val recovered = reopen(); recovered.markDeletionBackendComplete(owner.subject, owner.namespace)
            assertEquals(peerBefore, recovered.savedCheckpoint(peer)); assertEquals(LibraryDeletionPhase.IDENTITY_PENDING, recovered.deletionPhase(owner.subject, owner.namespace))
            android.database.sqlite.SQLiteDatabase.openDatabase(File(directory, "library_outcomes.db").path, null, 0).use { db ->
                for (table in listOf("saved_facts", "saved_pages", "saved_projection", "saved_assemblies")) db.rawQuery("SELECT COUNT(*) FROM $table WHERE subject=?", arrayOf(owner.subject)).use { it.moveToFirst(); assertEquals(0, it.getInt(0)) }
            }
        }
    }
    @Test fun savedOwnerOnlyResetKeepsOtherOwnerDataAndSharedClock() = runBlocking {
        isolated { store, _, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); val old = LibrarySyncOwner("older-owner", owner.subject)
            store.claimGuestForSync(owner); store.claimGuestForSync(old)
            store.beginSavedAssembly(owner); val lease = store.beginSavedAssembly(old)
            val facts = listOf(SavedFact.Note("old-source", 0.0, "old-target", "Retained old owner", 1.0, 2.0))
            repeat(2) { store.collectSavedStep(lease, { true }) { savedReply(it, old, facts) } }
            val checkpoint = store.savedCheckpoint(lease); val before = store.prepareOutcomeExport(old) { true }
            store.resetSyncPartitionForTesting(owner)
            assertEquals(checkpoint, store.savedCheckpoint(lease)); assertEquals(1, store.savedRawPage(lease, 0).facts.size)
            val after = store.prepareOutcomeExport(old) { true }
            assertTrue(after.version is LibraryOutcomeExportVersion.Present); assertNotEquals(before, after)
        }
    }
    @Test fun savedSchemaUpgradePreservesActualInstalledV1AndV2OutcomeData() = runBlocking {
        for (version in listOf(1, 2)) isolated { store, _, directory ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); legacyJournal(directory, listOf(owner))
            if (version == 2) android.database.sqlite.SQLiteDatabase.openDatabase(File(directory, "library_outcomes.db").path, null, 0).use { db ->
                db.execSQL("CREATE TABLE export_clocks (scope_key TEXT PRIMARY KEY NOT NULL, subject TEXT NOT NULL, namespace TEXT NOT NULL, epoch TEXT NOT NULL, revision INTEGER NOT NULL, erasing INTEGER NOT NULL)")
                db.execSQL("CREATE TABLE export_migration (id INTEGER PRIMARY KEY CHECK(id=1), phase TEXT NOT NULL, cursor TEXT NOT NULL)")
                db.execSQL("INSERT INTO export_migration VALUES(1,'scan','')")
                db.execSQL("CREATE INDEX headers_export ON headers(subject,namespace,collection_key)")
                db.execSQL("CREATE TABLE export_artifacts (artifact_id TEXT PRIMARY KEY NOT NULL, subject TEXT NOT NULL, namespace TEXT NOT NULL)")
                db.execSQL("CREATE INDEX artifacts_owner ON export_artifacts(subject,namespace,artifact_id)")
                db.execSQL("INSERT INTO export_clocks VALUES(?,?,?,?,?,?)", arrayOf<Any>(LibraryOutcomeBinding.hash(listOf(owner.namespace, owner.subject)), owner.subject, owner.namespace, "v2-clock", 7, 0))
                db.version = 2
            }
            store.claimGuestForSync(owner); val lease = store.beginSavedAssembly(owner)
            android.database.sqlite.SQLiteDatabase.openDatabase(File(directory, "library_outcomes.db").path, null, 0).use { db ->
                assertEquals(8, db.version)
                db.rawQuery("EXPLAIN QUERY PLAN SELECT row_key FROM saved_projection WHERE collection_key=? AND row_key>? AND row_key<? ORDER BY row_key LIMIT 8", arrayOf(lease.collection, lease.collection + ":r:", lease.collection + ":r:~")).use {
                    assertTrue(it.moveToFirst()); assertTrue(it.getString(3).contains("saved_projection_collection")); assertTrue(it.getString(3).contains("SEARCH"))
                }
                db.rawQuery("SELECT COUNT(*) FROM members", null).use { it.moveToFirst(); assertEquals(1, it.getInt(0)) }
                if (version == 2) db.rawQuery("SELECT epoch,revision FROM export_clocks WHERE subject=?", arrayOf(owner.subject)).use { it.moveToFirst(); assertEquals("v2-clock", it.getString(0)); assertTrue(it.getLong(1) > 7) }
            }
            val proof = taggedOutcomeProof(owner, 1, owner.key)
            assertEquals(1, store.outcomeEvidencePage(proof, owner, 0).rows.size)
            store.prepareOutcomeExport(owner) { true }
        }
    }

    @Test fun savedTokenCyclesStoppedReadsAndFreshGenerationRemainNonactivating() = runBlocking {
        isolated { store, _, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); store.claimGuestForSync(owner)
            val original = store.syncPartition(owner); val lease = store.beginSavedAssembly(owner)
            try { store.eraseSavedStep(owner.subject, owner.namespace, owner.storageKey); fail("Unfenced erase accepted") } catch (_: LibrarySyncFailure) { }
            store.collectSavedStep(lease, { true }) { savedReply(it, owner, emptyList()) }
            store.collectSavedStep(lease, { true }) { SavedFactsReply.Page(owner.key, 9.0, "private-root-proof", it, 0.0, emptyList(), "cursor:1") }
            val before = store.savedCheckpoint(lease)
            try { store.collectSavedStep(lease, { true }) { SavedFactsReply.Page(owner.key, 9.0, "private-root-proof", it, 0.0, emptyList(), "cursor:0") }; fail("Historical cycle accepted") } catch (_: LibrarySyncFailure) { }
            assertEquals(before, store.savedCheckpoint(lease))
            val stopped = store.collectSavedStep(lease, { true }) { SavedFactsReply.Unavailable(SavedFactsReplyUnavailableReason.SOURCE_TOO_LARGE) }
            assertEquals(LibrarySavedStage.Unavailable(SavedFactsReplyUnavailableReason.SOURCE_TOO_LARGE), stopped.stage)
            try { store.preparedSavedPage(lease, null); fail("Stopped generation exposed as prepared") } catch (_: LibrarySyncFailure) { }
            assertEquals(stopped, store.collectSavedStep(lease, { true }) { error("Stopped collector fetched again") })
            store.beginSavedErase(owner.subject, owner.namespace, owner.storageKey)
            for (step in 0 until 20) if (!store.eraseSavedStep(owner.subject, owner.namespace, owner.storageKey)) break
            val next = store.beginSavedAssembly(owner); assertNotEquals(lease, next)
            try { store.savedCheckpoint(lease); fail("Old incarnation revived") } catch (_: LibrarySyncFailure) { }
            var current = true
            try { store.collectSavedStep(next, { current }) { current = false; savedReply(it, owner, emptyList()) }; fail("Stale session reply committed") } catch (_: LibrarySyncFailure) { }
            assertEquals(0L, store.savedCheckpoint(next).pages); assertEquals(original, store.syncPartition(owner))
        }
    }
    @Test fun savedMissingRawFactCannotBecomePreparedAfterReopen() = runBlocking {
        isolated { store, reopen, directory ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); store.claimGuestForSync(owner)
            val lease = store.beginSavedAssembly(owner); val facts = savedLargeFacts().take(32)
            repeat(facts.size + 1) { store.collectSavedStep(lease, { true }) { savedReply(it, owner, facts) } }
            android.database.sqlite.SQLiteDatabase.openDatabase(File(directory, "library_outcomes.db").path, null, 0).use { it.delete("saved_facts", "collection_key=? AND ordinal=8", arrayOf(lease.collection)) }
            val recovered = reopen(); recovered.collectSavedStep(lease, { true }) { error("Local fold fetched") }; val before = recovered.savedCheckpoint(lease)
            try { recovered.collectSavedStep(lease, { true }) { error("Local fold fetched") }; fail("Missing fact silently skipped") } catch (_: LibrarySyncFailure) { }
            assertEquals(before, recovered.savedCheckpoint(lease))
            try { recovered.preparedSavedPage(lease, null); fail("Broken data became prepared") } catch (_: LibrarySyncFailure) { }
        }
    }

    @Test fun outcomeExportSafMidCopyFailuresRemoveActualPartialDocuments() = runBlocking {
        isolated { store, _, _ ->
            val fixture = AndroidLibraryFacadeFixture(store)
            try {
                fixture.start(); val owner = LibrarySyncOwner("owner-a", "subject-a")
                collectExportFacts(taggedOutcomeProof(owner, 501, "copy-source"), owner, 501, store)
                val captured = withContext(Dispatchers.Main) { fixture.sync.captureWriteContext() }
                val context = InstrumentationRegistry.getInstrumentation().targetContext; val resolver = context.contentResolver
                val root = android.provider.DocumentsContract.buildDocumentUri(context.packageName + ".verification.exports", "root")
                for (mode in listOf("mutation", "io", "cancel", "switch")) {
                    val prepared = fixture.sync.preparePortableExport(kotlinx.serialization.json.JsonObject(emptyMap()), captured, "export.json")
                    val uri = android.provider.DocumentsContract.createDocument(resolver, root, "application/json", "export.json")!!
                    try {
                        val destination = resolver.openOutputStream(uri)!!
                        var injected = false
                        val failing = object : java.io.OutputStream() {
                            override fun write(value: Int) = destination.write(value)
                            override fun write(bytes: ByteArray, offset: Int, length: Int) {
                                destination.write(bytes, offset, minOf(length, 1_024)); destination.flush()
                                if (!injected) {
                                    injected = true
                                    when (mode) {
                                        "mutation" -> runBlocking { collectExportFacts(taggedOutcomeProof(owner, 1, "mid-copy"), owner, 1, store) }
                                        "io" -> throw java.io.IOException("Controlled destination failure")
                                        "cancel" -> throw CancellationException("Controlled copy cancellation")
                                        "switch" -> runBlocking { withContext(Dispatchers.Main) { fixture.session.value = LibrarySyncSession("session-b", "subject-b"); fixture.sync.deactivate() } }
                                    }
                                }
                            }
                            override fun flush() = destination.flush()
                            override fun close() = destination.close()
                        }
                        try { failing.use { fixture.sync.copyPreparedExport(prepared, it) }; fail("Failed copy reported success") } catch (_: Exception) { }
                        assertTrue(injected)
                        assertTrue(resolver.openInputStream(uri)!!.use { it.readBytes() }.isNotEmpty())
                        assertTrue(com.hadithly.app.features.settings.SettingsExport.removeFailedDocument(resolver, uri))
                        try { resolver.openInputStream(uri)?.close(); fail("Partial destination retained") } catch (_: java.io.FileNotFoundException) { }
                    } finally { fixture.sync.discardPreparedExport(prepared) }
                    assertFalse(prepared.file.exists())
                }
            } finally { fixture.stop() }
        }
    }


    private fun taggedOutcomeProof(owner: LibrarySyncOwner, count: Int, tag: String): SyncCommitted {
        val base = outcomeProof(owner, count)
        return base.copy(clientKey = tag, digest = "$tag-digest", reply = base.reply.copy(batchId = "$tag-batch", receipts = base.reply.receipts.map { it.copy(id = "$tag-operation") }))
    }
    private suspend fun collectExportFacts(proof: SyncCommitted, owner: LibrarySyncOwner, count: Int, store: GuestDataStore, complete: Boolean = true) {
        repeat(50) {
            val value = store.collectOutcomeStep(proof, owner, { true }) { outcomePage(it, owner, count) }
            if (value.status == LibraryOutcomeStatus.Complete || !complete) return
        }
        fail("Export fixture did not finish bounded collection")
    }
    private fun exportContains(value: kotlinx.serialization.json.JsonElement, text: String): Boolean = when (value) {
        is kotlinx.serialization.json.JsonPrimitive -> value.isString && value.content == text
        is kotlinx.serialization.json.JsonObject -> value.values.any { exportContains(it, text) }
        is kotlinx.serialization.json.JsonArray -> value.any { exportContains(it, text) }
        else -> false
    }
    private fun legacyJournal(directory: File, owners: List<LibrarySyncOwner>) {
        android.database.sqlite.SQLiteDatabase.openOrCreateDatabase(File(directory, "library_outcomes.db"), null).use { db ->
            db.execSQL("CREATE TABLE scopes (scope_key TEXT PRIMARY KEY NOT NULL, subject TEXT NOT NULL, namespace TEXT NOT NULL, owner_key TEXT NOT NULL, generation TEXT NOT NULL)")
            db.execSQL("CREATE INDEX scopes_owner ON scopes(subject,namespace,owner_key)")
            db.execSQL("CREATE TABLE headers (collection_key TEXT PRIMARY KEY NOT NULL, owner_key TEXT NOT NULL, subject TEXT NOT NULL, namespace TEXT NOT NULL, generation TEXT NOT NULL, authority TEXT NOT NULL, checkpoint TEXT NOT NULL)")
            db.execSQL("CREATE INDEX headers_owner ON headers(subject,namespace,owner_key,collection_key)")
            db.execSQL("CREATE TABLE members (collection_key TEXT NOT NULL REFERENCES headers(collection_key) ON DELETE CASCADE, ordinal INTEGER NOT NULL, member_id TEXT NOT NULL, hadith_id TEXT NOT NULL, disposition TEXT NOT NULL, row_data TEXT NOT NULL, PRIMARY KEY(collection_key,ordinal), UNIQUE(collection_key,member_id), UNIQUE(collection_key,hadith_id))")
            db.execSQL("CREATE INDEX members_category ON members(collection_key,disposition)")
            for (owner in owners) {
                val binding = LibraryOutcomeBinding(owner, taggedOutcomeProof(owner, 1, owner.key)); val generation = "legacy-generation"
                db.insertOrThrow("scopes", null, android.content.ContentValues().apply { put("scope_key", binding.scopeKey); put("subject", owner.subject); put("namespace", owner.namespace); put("owner_key", owner.storageKey); put("generation", generation) })
                db.insertOrThrow("headers", null, android.content.ContentValues().apply {
                    put("collection_key", binding.key); put("owner_key", owner.storageKey); put("subject", owner.subject); put("namespace", owner.namespace); put("generation", generation)
                    put("authority", Json.encodeToString(binding.authority)); put("checkpoint", Json.encodeToString(LibraryOutcomeCheckpoint(LibraryOutcomeCounts(deleted = 1), LibraryOutcomeStatus.Complete)))
                })
                val row = SyncOutcomeMember(0.0, "${owner.key}-member", "${owner.key}-hadith", SyncOutcomeMemberDisposition.DELETED)
                db.insertOrThrow("members", null, android.content.ContentValues().apply {
                    put("collection_key", binding.key); put("ordinal", 0); put("member_id", row.memberId); put("hadith_id", row.hadithId); put("disposition", row.disposition.name); put("row_data", Json.encodeToString(row))
                })
            }
            db.version = 1
        }
    }
    @Test fun outcomeExportPreservesFieldsAndIncludesOldOwnerOrphansOnlyForCapturedSubject() = runBlocking {
        isolated { store, reopen, directory ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); val old = LibrarySyncOwner("older-owner", owner.subject)
            val foreign = LibrarySyncOwner("foreign-owner", "subject-b"); val deployment = LibrarySyncOwner("older-owner", owner.subject, "other-deployment")
            legacyJournal(directory, listOf(old, foreign, deployment))
            val fixture = AndroidLibraryFacadeFixture(store)
            try {
                fixture.start()
                val text = "Private \"quote\" — عربى mentions arabicText, capability and pushTokens"
                assertTrue(withContext(Dispatchers.Main) { fixture.model.saveNote(fixture.reference, text) }.await())
                val partial = taggedOutcomeProof(owner, 51, "partial")
                collectExportFacts(partial, owner, 51, store, complete = false)
                store.collectOutcomeStep(partial, owner, { true }) { SyncOutcomePage.Unavailable(owner.key, it, SyncOutcomePageUnavailableReason.DETAIL_UNAVAILABLE) }
                val captured = withContext(Dispatchers.Main) { fixture.sync.captureWriteContext() }
                val server = kotlinx.serialization.json.JsonObject(mapOf("sync" to kotlinx.serialization.json.JsonObject(emptyMap()), "evidenceItems" to kotlinx.serialization.json.JsonArray(emptyList()), "custom" to kotlinx.serialization.json.JsonPrimitive("server-kept")))
                val prepared = fixture.sync.preparePortableExport(server, captured, "export.json")
                try {
                    val document = Json.parseToJsonElement(prepared.file.readText()); require(document is kotlinx.serialization.json.JsonObject)
                    val entries = document["localOutcomeEvidence"]; require(entries is kotlinx.serialization.json.JsonArray)
                    assertEquals(2, entries.size)
                    val owners = entries.map { entry -> require(entry is kotlinx.serialization.json.JsonObject); Json.decodeFromString<LibraryOutcomeAuthority>(entry.getValue("authority").toString()).owner }
                    assertTrue(owners.all { it.subject == owner.subject && it.namespace == owner.namespace }); assertTrue(owners.any { it.key == old.key })
                    val retained = entries.filterIsInstance<kotlinx.serialization.json.JsonObject>().first { it["status"] == kotlinx.serialization.json.JsonPrimitive("unavailable") }
                    assertEquals(kotlinx.serialization.json.JsonPrimitive(false), retained["detailComplete"])
                    assertEquals(kotlinx.serialization.json.JsonPrimitive("detail_unavailable"), retained["unavailableReason"])
                    val rows = retained["rows"]; require(rows is kotlinx.serialization.json.JsonArray); assertEquals(50, rows.size)
                    assertTrue(exportContains(document, text)); assertTrue(exportContains(document, "server-kept"))
                    assertFalse(document.containsExportKey(setOf("arabicText", "englishText", "capability", "pushTokens", "adminAuditLog", "revenueCatAppUserId")))
                } finally { fixture.sync.discardPreparedExport(prepared) }
                assertFalse(prepared.file.exists())
                android.database.sqlite.SQLiteDatabase.openDatabase(File(directory, "library_outcomes.db").path, null, android.database.sqlite.SQLiteDatabase.OPEN_READONLY).use { db ->
                    assertEquals(8, db.version)
                    db.rawQuery("EXPLAIN QUERY PLAN SELECT collection_key FROM headers WHERE subject=? AND namespace=? AND collection_key>? ORDER BY collection_key LIMIT 50", arrayOf(owner.subject, owner.namespace, "")).use {
                        assertTrue(it.moveToFirst()); assertTrue(it.getString(3).contains("headers_export"))
                    }
                }
                val reopened = reopen(); val fence = reopened.prepareOutcomeExport(owner) { true }
                assertEquals(2, reopened.outcomeExportEntries(fence, null).size)
            } finally { fixture.stop() }
        }
    }
    @Test fun outcomeExportFenceRejectsInsertBeforeCursorVerificationAndErasure() = runBlocking {
        isolated { store, _, directory ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); store.claimGuestForSync(owner)
            val proofs = (0 until 4).map { taggedOutcomeProof(owner, 1, "clock-$it") }.sortedBy { LibraryOutcomeBinding(owner, it).key }
            collectExportFacts(proofs[2], owner, 1, store)
            val first = store.prepareOutcomeExport(owner) { true }; val after = store.outcomeExportEntries(first, null).first().binding.key
            collectExportFacts(proofs[0], owner, 1, store)
            try { store.outcomeExportEntries(first, after); fail("Insert before cursor escaped fence") } catch (_: LibrarySyncFailure.StoreUnavailable) { }
            collectExportFacts(proofs[3], owner, 1, store, complete = false)
            val beforeVerify = store.prepareOutcomeExport(owner) { true }
            store.collectOutcomeStep(proofs[3], owner, { true }) { fail("Local verification fetched"); throw LibrarySyncFailure.InvalidReceipt }
            try { store.validateOutcomeExport(beforeVerify); fail("Verification escaped fence") } catch (_: LibrarySyncFailure.StoreUnavailable) { }
            val beforeErase = store.prepareOutcomeExport(owner) { true }; val artifact = store.beginOutcomeExportArtifact(beforeErase)
            File(artifact.directory, "document.partial").writeText("private-prefix")
            store.beginDeletion(owner.subject, owner.namespace); store.markDeletionBackendComplete(owner.subject, owner.namespace)
            assertFalse(artifact.directory.exists())
            try { store.validateOutcomeExport(beforeErase); fail("Erasure escaped fence") } catch (_: LibrarySyncFailure.AccountDeleting) { }
            android.database.sqlite.SQLiteDatabase.openDatabase(File(directory, "library_outcomes.db").path, null, android.database.sqlite.SQLiteDatabase.OPEN_READONLY).use { db ->
                for (table in listOf("export_clocks", "export_artifacts")) db.rawQuery("SELECT count(*) FROM $table", null).use { assertTrue(it.moveToFirst()); assertEquals(0L, it.getLong(0)) }
            }
        }
    }
    @Test fun outcomeExportMutationCancellationSwitchAndErasureDiscardPartialFiles() = runBlocking {
        for (mode in listOf("mutation", "persistent", "cancel", "switch", "erase")) isolated { store, _, directory ->
            val fixture = AndroidLibraryFacadeFixture(store)
            try {
                fixture.start(); val owner = LibrarySyncOwner("owner-a", "subject-a")
                collectExportFacts(taggedOutcomeProof(owner, 501, "large"), owner, 501, store)
                withContext(Dispatchers.Main) {
                    supervisorScope {
                        val captured = fixture.sync.captureWriteContext()
                        val task = async { fixture.sync.preparePortableExport(kotlinx.serialization.json.JsonObject(emptyMap()), captured, "export.json") }
                        val root = File(directory, "cache/LibraryExports")
                        withTimeout(8_000) { while (root.listFiles().orEmpty().none { File(it, "document.partial").exists() }) yield() }
                        when (mode) {
                            "persistent" -> {
                                val invalidated = mutableSetOf<File>()
                                repeat(3) { attempt ->
                                    val next = withTimeout(8_000) {
                                        var found: File? = null
                                        while (found == null) { found = root.listFiles().orEmpty().firstOrNull { it !in invalidated && File(it, "document.partial").exists() }; if (found == null) yield() }
                                        found
                                    }
                                    invalidated.add(next)
                                    store.enqueueSyncChange(LibraryLocalChange(SyncCommand.NoteRemove("changed-$attempt"), 1_000.0, LibraryLocalSource.Account(null)), owner)
                                    yield()
                                }
                                assertEquals(3, invalidated.size)
                            }
                            "cancel" -> task.cancel()
                            "switch" -> { fixture.session.value = LibrarySyncSession("session-b", "subject-b"); fixture.sync.deactivate() }
                            "erase" -> { store.beginDeletion(owner.subject, owner.namespace); store.markDeletionBackendComplete(owner.subject, owner.namespace) }
                            else -> collectExportFacts(taggedOutcomeProof(owner, 1, "insert-during-export"), owner, 1, store)
                        }
                        if (mode == "mutation") {
                            val prepared = task.await()
                            val document = Json.parseToJsonElement(prepared.file.readText()) as kotlinx.serialization.json.JsonObject
                            val entries = document.getValue("localOutcomeEvidence") as kotlinx.serialization.json.JsonArray
                            assertEquals(2, entries.size); assertTrue(exportContains(entries, "insert-during-export"))
                            fixture.sync.discardPreparedExport(prepared)
                        } else {
                            try { task.await(); fail("Canceled, erased or repeatedly changed export was published") } catch (_: Exception) { }
                        }
                        assertTrue(root.listFiles().orEmpty().isEmpty())
                    }
                }
            } finally { fixture.stop() }
        }
    }
    @Test fun outcomeExportRejectsMissingFactAfterCompletedVerification() = runBlocking {
        isolated { store, _, directory ->
            val fixture = AndroidLibraryFacadeFixture(store)
            try {
                fixture.start(); val owner = LibrarySyncOwner("owner-a", "subject-a")
                val proof = taggedOutcomeProof(owner, 51, "corrupt-export")
                collectExportFacts(proof, owner, 51, store)
                android.database.sqlite.SQLiteDatabase.openDatabase(File(directory, "library_outcomes.db").path, null, android.database.sqlite.SQLiteDatabase.OPEN_READWRITE).use {
                    it.delete("members", "collection_key=? AND ordinal=?", arrayOf(LibraryOutcomeBinding(owner, proof).key, "50"))
                }
                withContext(Dispatchers.Main) {
                    val captured = fixture.sync.captureWriteContext()
                    try { fixture.sync.preparePortableExport(kotlinx.serialization.json.JsonObject(emptyMap()), captured, "export.json"); fail("Corrupt journal exported as complete") }
                    catch (_: LibrarySyncFailure.StoreUnavailable) { }
                    assertTrue(File(directory, "cache/LibraryExports").listFiles().orEmpty().isEmpty())
                }
            } finally { fixture.stop() }
        }
    }
    @Test fun outcomeExportArtifactCleanupAndAccountFenceNeverRecreateDeletedMetadata() = runBlocking {
        isolated { store, reopen, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); store.claimGuestForSync(owner)
            val empty = store.prepareOutcomeExport(owner) { true }; assertTrue(empty.version is LibraryOutcomeExportVersion.Present)
            val artifact = store.beginOutcomeExportArtifact(empty); File(artifact.directory, "document.partial").writeText("abandoned")
            reopen().clearAbandonedOutcomeExports()
            assertFalse(artifact.directory.exists())
            store.beginDeletion(owner.subject, owner.namespace); store.markDeletionBackendComplete(owner.subject, owner.namespace)
            try { store.prepareOutcomeExport(owner) { true }; fail("Deleted export recreated metadata") } catch (_: LibrarySyncFailure.AccountDeleting) { }
        }
    }
    @Test fun outcomeExportSafCopyRechecksFenceAndRollsBackNewDocument() = runBlocking {
        isolated { store, _, _ ->
            val fixture = AndroidLibraryFacadeFixture(store)
            try {
                fixture.start(); val owner = LibrarySyncOwner("owner-a", "subject-a")
                collectExportFacts(taggedOutcomeProof(owner, 51, "source"), owner, 51, store)
                val captured = withContext(Dispatchers.Main) { fixture.sync.captureWriteContext() }
                val prepared = fixture.sync.preparePortableExport(kotlinx.serialization.json.JsonObject(emptyMap()), captured, "export.json")
                val context = InstrumentationRegistry.getInstrumentation().targetContext; val resolver = context.contentResolver
                val root = android.provider.DocumentsContract.buildDocumentUri(context.packageName + ".verification.exports", "root")
                val uri = android.provider.DocumentsContract.createDocument(resolver, root, "application/json", "export.json")!!
                try {
                    collectExportFacts(taggedOutcomeProof(owner, 1, "after-seal"), owner, 1, store)
                    try { resolver.openOutputStream(uri)!!.use { fixture.sync.copyPreparedExport(prepared, it) }; fail("Changed snapshot copied") } catch (_: LibrarySyncFailure.StoreUnavailable) { }
                    assertTrue(com.hadithly.app.features.settings.SettingsExport.removeFailedDocument(resolver, uri))
                    try { resolver.openInputStream(uri)?.use { it.read() }; fail("Failed document still exists") } catch (_: java.io.FileNotFoundException) { }
                } finally { fixture.sync.discardPreparedExport(prepared) }
            } finally { fixture.stop() }
        }
    }

    @Test fun manifestRestoreUsesOwnedSnapshotWithoutGuessingMembers() {
        val first = "jn7fxd3z54153q9j13kmhgzkv18df2zd"; val second = "an7fxd3z54153q9j13kmhgzkv18df2zd"
        fun item(id: String, folder: String?) = SyncSavedItem(id, 1.0, 1.0, bookmarkCreatedAt = 1.0, folderId = folder,
            hadith = SyncHadithSummary(id, "1", "bukhari", "Bukhari", "1", "نص", null, "Bukhari 1"))
        val state = LibraryPartitionState(savedSnapshot = SyncSavedSnapshot("owner-a", 1.0, emptyList(), listOf(item(first, null), item(second, null))))
        state.append(LibraryLocalSource.Account(null), SyncCommand.FolderRestore("deleted", "Folder", listOf(first, second)), 1_000.0)
        val frame = state.freeze()!!; val operation = frame.batch.operations[0]
        val reply = SyncReply("owner-a", frame.batch.id, listOf(SyncReceipt(operation.id, operation.revision,
            SyncOutcome.FolderRestoredManifest("manifest", "generation", "destination", 1.0, 0.0, 1.0))))
        val committed = SyncCommitted(frame.clientKey, frame.sequence, "fixture-digest", SyncRevision(2.0, 0.0), reply)
        state.settle(SyncExchange.Accepted(committed), frame, observationOwner(state), observation(state), 2_000.0)
        assertTrue(legacyProjection(state).folders.isEmpty())
        assertTrue(legacyProjection(state).items.all { it.folderId == null })
        state.savedSnapshot = SyncSavedSnapshot("owner-a", 2.0, listOf(SyncFolderRow("destination", "Folder", 1.0)), listOf(item(first, "destination"), item(second, null)))
        val visible = legacyProjection(state)
        assertEquals(listOf("destination"), visible.folders.map { it.id })
        assertEquals("destination", visible.items.first { it.hadithId == first }.folderId)
        assertNull(visible.items.first { it.hadithId == second }.folderId)
        assertNull(state.acknowledgement); assertNotNull(state.frozen)
    }


    @Test fun outcomeJournalVerificationResumesAndRejectsMissingPersistedMember() = runBlocking {
        isolated { store, reopen, directory ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); val proof = outcomeProof(owner, 100)
            store.claimGuestForSync(owner)
            repeat(2) { store.collectOutcomeStep(proof, owner, { true }) { outcomePage(it, owner, 100) } }
            val first = store.collectOutcomeStep(proof, owner, { true }) { fail("Verification fetched"); throw LibrarySyncFailure.InvalidReceipt }
            assertEquals(LibraryOutcomeStatus.Verifying(LibraryOutcomeCounts(deleted = 50)), first.status)
            android.database.sqlite.SQLiteDatabase.openDatabase(File(directory, "library_outcomes.db").path, null, android.database.sqlite.SQLiteDatabase.OPEN_READWRITE).use {
                it.delete("members", "collection_key=? AND ordinal=?", arrayOf(LibraryOutcomeBinding(owner, proof).key, "80"))
            }
            val reopened = reopen()
            try { reopened.collectOutcomeStep(proof, owner, { true }) { fail("Verification fetched"); throw LibrarySyncFailure.InvalidReceipt }; fail("Missing fact became complete") } catch (_: LibrarySyncFailure.StoreUnavailable) { }
            assertEquals(first.status, reopened.outcomeEvidencePage(proof, owner, 0).checkpoint.status)
            try { reopened.outcomeEvidencePage(proof, owner, 50); fail("Missing fact exported") } catch (_: LibrarySyncFailure.StoreUnavailable) { }
            assertNull(reopened.syncPartition(owner)!!.acknowledgement)
        }
    }
    @Test fun outcomeJournalInterruptedEraseRetainsIntentAndResumesCommittedBatches() = runBlocking {
        isolated { store, reopen, directory ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); val proof = outcomeProof(owner, 100)
            store.claimGuestForSync(owner)
            repeat(2) { store.collectOutcomeStep(proof, owner, { true }) { outcomePage(it, owner, 100) } }
            val database = File(directory, "library_outcomes.db").path
            android.database.sqlite.SQLiteDatabase.openDatabase(database, null, android.database.sqlite.SQLiteDatabase.OPEN_READWRITE).use {
                it.execSQL("CREATE TRIGGER stop_second_erase_batch BEFORE DELETE ON members WHEN OLD.ordinal>=50 BEGIN SELECT RAISE(ABORT,'controlled-erase-failure'); END")
            }
            store.beginDeletion(owner.subject, owner.namespace)
            try { store.markDeletionBackendComplete(owner.subject, owner.namespace); fail("Interrupted sweep completed") } catch (_: android.database.sqlite.SQLiteException) { }
            assertEquals(LibraryDeletionPhase.SERVER_PENDING, reopen().deletionPhase(owner.subject, owner.namespace))
            android.database.sqlite.SQLiteDatabase.openDatabase(database, null, android.database.sqlite.SQLiteDatabase.OPEN_READWRITE).use { db ->
                db.rawQuery("SELECT count(*) FROM members", null).use { assertTrue(it.moveToFirst()); assertEquals(50L, it.getLong(0)) }
                db.execSQL("DROP TRIGGER stop_second_erase_batch")
            }
            reopen().markDeletionBackendComplete(owner.subject, owner.namespace)
            assertEquals(LibraryDeletionPhase.IDENTITY_PENDING, reopen().deletionPhase(owner.subject, owner.namespace))
            android.database.sqlite.SQLiteDatabase.openDatabase(database, null, android.database.sqlite.SQLiteDatabase.OPEN_READONLY).use { db ->
                for (table in listOf("members", "headers", "scopes")) db.rawQuery("SELECT count(*) FROM $table", null).use { assertTrue(it.moveToFirst()); assertEquals(0L, it.getLong(0)) }
            }
        }
    }


    private fun outcomeProof(owner: LibrarySyncOwner, count: Int, restore: Boolean = false): SyncCommitted {
        val outcome: SyncOutcome = if (restore) SyncOutcome.FolderRestoredManifest("manifest", "generation", "restored-folder", maxOf(0, count - 1).toDouble(), 0.0, minOf(count, 1).toDouble())
            else SyncOutcome.FolderDeletedManifest("manifest", "generation", count.toDouble(), 1_000.0)
        return SyncCommitted("outcome-device", 1.0, "outcome-digest", SyncRevision(2.0, 0.0), SyncReply(owner.key, "outcome-batch", listOf(SyncReceipt("outcome-operation", "r1", outcome))))
    }
    private fun outcomePage(request: SyncOutcomePageRequest, owner: LibrarySyncOwner, count: Int, restore: Boolean = false): SyncOutcomePage {
        val start = request.start.toInt(); val end = minOf(start + LibrarySyncLimits.outcomePage, count)
        val rows = (start until end).map { SyncOutcomeMember(it.toDouble(), "member-$it", "hadith-$it", if (!restore) SyncOutcomeMemberDisposition.DELETED else if (it == count - 1) SyncOutcomeMemberDisposition.MISSING else SyncOutcomeMemberDisposition.RESTORED) }
        return SyncOutcomePage.Page(owner.key, request, rows, end.toDouble(), end == count)
    }
    private suspend fun finishOutcomeVerification(proof: SyncCommitted, owner: LibrarySyncOwner, store: GuestDataStore): LibraryOutcomeCheckpoint {
        repeat(30) {
            val checkpoint = store.collectOutcomeStep(proof, owner, { true }) { fail("Verification fetched a server page"); throw LibrarySyncFailure.InvalidReceipt }
            if (checkpoint.status == LibraryOutcomeStatus.Complete) return checkpoint
        }
        throw LibrarySyncFailure.InvalidReceipt
    }
    @Test fun outcomeJournalCollectsBoundedPagesAcrossReopensWithoutChangingPartition() = runBlocking {
        for (count in listOf(0, 1, 50, 51, 501)) isolated { initial, reopen, directory ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); val proof = outcomeProof(owner, count)
            var store = initial
            store.claimGuestForSync(owner)
            store.enqueueSyncChange(LibraryLocalChange(SyncCommand.FolderDelete(SyncFolderReference.Server("folder")), 1_000.0, LibraryLocalSource.Account(null)), owner)
            store.freezeSyncFrame(owner)
            val original = store.syncPartition(owner)
            var checkpoint = LibraryOutcomeCheckpoint(); val requests = mutableListOf<Double>()
            for (index in 0 until 30) {
                checkpoint = store.collectOutcomeStep(proof, owner, { true }) { request -> requests.add(request.start); outcomePage(request, owner, count) }
                assertEquals(original, store.syncPartition(owner))
                store = reopen()
                if (checkpoint.status == LibraryOutcomeStatus.Complete) break
            }
            assertEquals(LibraryOutcomeStatus.Complete, checkpoint.status); assertEquals(count.toLong(), checkpoint.next)
            assertEquals((0 until maxOf(1, count) step 50).map { it.toDouble() }, requests)
            var start = 0L; val members = mutableSetOf<String>()
            do {
                val evidence = store.outcomeEvidencePage(proof, owner, start)
                assertEquals(checkpoint, evidence.checkpoint); assertTrue(evidence.rows.size <= 50)
                members.addAll(evidence.rows.map { it.memberId }); start = evidence.next
                if (evidence.endOfCollectedPrefix) break
            } while (start <= count)
            assertEquals(count, members.size)
            store.collectOutcomeStep(proof, owner, { true }) { fail("Fetched complete journal"); throw LibrarySyncFailure.InvalidReceipt }
            assertEquals(original, store.syncPartition(owner))
        }
    }
    @Test fun outcomeJournalDuplicateAndConflictingReopenedContextCannotReplaceEvidence() = runBlocking {
        isolated { store, reopen, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); val proof = outcomeProof(owner, 100)
            store.claimGuestForSync(owner)
            val first = store.collectOutcomeStep(proof, owner, { true }) { request ->
                reopen().collectOutcomeStep(proof, owner, { true }) { outcomePage(it, owner, 100) }
                outcomePage(request, owner, 100)
            }
            assertEquals(50L, first.next)
            try {
                store.collectOutcomeStep(proof, owner, { true }) { request ->
                    reopen().collectOutcomeStep(proof, owner, { true }) { outcomePage(it, owner, 100) }
                    val page = outcomePage(request, owner, 100) as SyncOutcomePage.Page
                    page.copy(rows = page.rows.mapIndexed { index, row -> if (index == 0) row.copy(memberId = "conflicting-member", hadithId = "conflicting-hadith") else row })
                }
                fail("Conflicting duplicate replaced evidence")
            } catch (_: LibrarySyncFailure.InvalidReceipt) { }
            finishOutcomeVerification(proof, owner, reopen())
            val evidence = reopen().outcomeEvidencePage(proof, owner, 50)
            assertEquals(LibraryOutcomeStatus.Complete, evidence.checkpoint.status)
            assertEquals("member-50", evidence.rows.first().memberId); assertEquals("hadith-50", evidence.rows.first().hadithId)
        }
    }
    @Test fun outcomeJournalRollsBackEarlierRowsWhenLaterMemberConflicts() = runBlocking {
        isolated { store, reopen, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); val proof = outcomeProof(owner, 100)
            store.claimGuestForSync(owner)
            store.collectOutcomeStep(proof, owner, { true }) { outcomePage(it, owner, 100) }
            try {
                store.collectOutcomeStep(proof, owner, { true }) { request ->
                    val page = outcomePage(request, owner, 100) as SyncOutcomePage.Page
                    page.copy(rows = page.rows.mapIndexed { index, row -> if (index == 10) row.copy(memberId = "member-0") else row })
                }
                fail("Repeated member accepted")
            } catch (_: android.database.sqlite.SQLiteConstraintException) { }
            val partial = reopen().outcomeEvidencePage(proof, owner, 50)
            assertEquals(50L, partial.checkpoint.next); assertTrue(partial.rows.isEmpty())
            store.collectOutcomeStep(proof, owner, { true }) { outcomePage(it, owner, 100) }
            val complete = finishOutcomeVerification(proof, owner, reopen())
            assertEquals(LibraryOutcomeStatus.Complete, complete.status)
        }
    }
    @Test fun outcomeJournalUnavailableRetainsPartialFactsAndNeverAcknowledges() = runBlocking {
        for (reason in listOf(SyncOutcomePageUnavailableReason.DETAIL_UNAVAILABLE, SyncOutcomePageUnavailableReason.PROOF_UNAVAILABLE)) isolated { store, reopen, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); val proof = outcomeProof(owner, 51)
            store.claimGuestForSync(owner)
            store.collectOutcomeStep(proof, owner, { true }) { outcomePage(it, owner, 51) }
            val result = store.collectOutcomeStep(proof, owner, { true }) { SyncOutcomePage.Unavailable(owner.key, it, reason) }
            assertEquals(LibraryOutcomeStatus.Unavailable(reason), result.status); assertEquals(50L, result.next)
            val reopened = reopen(); val evidence = reopened.outcomeEvidencePage(proof, owner, 0)
            assertEquals(50, evidence.rows.size); assertEquals(result.status, evidence.checkpoint.status)
            assertNull(reopened.syncPartition(owner)!!.acknowledgement)
        }
    }
    @Test fun outcomeJournalRejectsWrongCategoriesAndOwnerWithoutAdvancing() = runBlocking {
        isolated { store, reopen, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); val proof = outcomeProof(owner, 51, true)
            store.claimGuestForSync(owner)
            store.collectOutcomeStep(proof, owner, { true }) { outcomePage(it, owner, 51, true) }
            for (wrongOwner in listOf(false, true)) {
                try {
                    store.collectOutcomeStep(proof, owner, { true }) { request ->
                        SyncOutcomePage.Page(if (wrongOwner) "other-owner" else owner.key, request, listOf(SyncOutcomeMember(request.start, "member-50", "hadith-50", SyncOutcomeMemberDisposition.RESTORED)), 51.0, true)
                    }
                    fail("Invalid page accepted")
                } catch (_: LibrarySyncFailure.InvalidReceipt) { }
                assertEquals(50L, reopen().outcomeEvidencePage(proof, owner, 50).checkpoint.next)
            }
            val terminal = store.collectOutcomeStep(proof, owner, { true }) { outcomePage(it, owner, 51, true) }
            assertEquals(LibraryOutcomeCounts(restored = 50, missing = 1), terminal.counts)
        }
    }
    @Test fun outcomeJournalErasureFenceRejectsLatePageAfterPartitionRecreation() = runBlocking {
        isolated { store, reopen, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); val proof = outcomeProof(owner, 1)
            store.claimGuestForSync(owner)
            try {
                store.collectOutcomeStep(proof, owner, { true }) { request ->
                    store.resetSyncPartitionForTesting(owner); store.claimGuestForSync(owner)
                    outcomePage(request, owner, 1)
                }
                fail("Late page recreated erased evidence")
            } catch (_: LibrarySyncFailure.SessionChanged) { }
            try { reopen().outcomeEvidencePage(proof, owner, 0); fail("Erased evidence returned") } catch (_: LibrarySyncFailure.StoreUnavailable) { }
            store.collectOutcomeStep(proof, owner, { true }) { outcomePage(it, owner, 1) }
            assertEquals(LibraryOutcomeStatus.Complete, finishOutcomeVerification(proof, owner, reopen()).status)
        }
    }
    @Test fun outcomeJournalAccountErasureFindsOrphansAndPreservesOtherScopes() = runBlocking {
        isolated { store, reopen, directory ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); val other = LibrarySyncOwner("owner-b", "subject-b"); val deployment = LibrarySyncOwner("owner-a", "subject-a", "other-deployment")
            for (target in listOf(owner, other, deployment)) {
                store.claimGuestForSync(target)
                val count = if (target == owner) 501 else 1
                for (index in 0 until 12) {
                    val checkpoint = store.collectOutcomeStep(outcomeProof(target, count), target, { true }) { outcomePage(it, target, count) }
                    if (checkpoint.status != LibraryOutcomeStatus.Collecting) break
                }
            }
            sql(directory) { db -> db.delete("local_accounts", "key=?", arrayOf(owner.storageKey)) }
            assertEquals(50, store.outcomeEvidencePage(outcomeProof(owner, 501), owner, 0).rows.size)
            store.beginDeletion(owner.subject, owner.namespace); store.markDeletionBackendComplete(owner.subject, owner.namespace)
            try { reopen().outcomeEvidencePage(outcomeProof(owner, 501), owner, 0); fail("Orphan evidence retained") } catch (_: LibrarySyncFailure.StoreUnavailable) { }
            try { reopen().collectOutcomeStep(outcomeProof(owner, 501), owner, { true }) { fail("Erased owner fetched"); throw LibrarySyncFailure.InvalidReceipt }; fail("Stale erased owner recreated metadata") } catch (_: LibrarySyncFailure.AccountDeleting) { }
            android.database.sqlite.SQLiteDatabase.openDatabase(File(directory, "library_outcomes.db").path, null, android.database.sqlite.SQLiteDatabase.OPEN_READONLY).use { db ->
                for (table in listOf("scopes", "headers")) db.rawQuery("SELECT count(*) FROM $table WHERE subject=? AND namespace=?", arrayOf(owner.subject, owner.namespace)).use { assertTrue(it.moveToFirst()); assertEquals(0L, it.getLong(0)) }
                db.rawQuery("SELECT count(*) FROM members", null).use { assertTrue(it.moveToFirst()); assertEquals(2L, it.getLong(0)) }
            }
            for (target in listOf(other, deployment)) assertEquals(1, reopen().outcomeEvidencePage(outcomeProof(target, 1), target, 0).rows.size)
        }
    }

    @Test fun reconciledManifestStagesCollectionWithoutAcknowledging() {
        val outcomes = listOf(SyncOutcome.FolderDeletedManifest("manifest", "generation", 501.0, 1_000.0), SyncOutcome.FolderRestoredManifest("manifest", "generation", "folder", 499.0, 1.0, 1.0))
        fun copied(state: LibraryPartitionState) = Json.decodeFromString<LibraryPartitionState>(Json.encodeToString(state))
        for (outcome in outcomes) {
            val original = LibraryPartitionState()
            original.append(LibraryLocalSource.Account(null), SyncCommand.FolderDelete(SyncFolderReference.Server("folder-a")), 1_000.0)
            val frame = original.freeze()!!; val operation = frame.batch.operations[0]
            val committed = SyncCommitted(frame.clientKey, frame.sequence, "fixture-digest", SyncRevision(1.0, 0.0), SyncReply("owner-a", frame.batch.id, listOf(SyncReceipt(operation.id, operation.revision, outcome))))
            val cursor = SyncCursor(0.0, SyncOutstanding.Committed(committed))
            val reconciled = copied(original)
            reconciled.settle(SyncExchange.Reconcile("owner-a", frame.clientKey, frame.sequence, frame.batch.id, cursor), frame, observationOwner(reconciled), observation(reconciled), 2_000.0)
            assertEquals(LibraryPendingOutcome(committed, LibraryOutcomeOrigin.Historical), reconciled.collectingOutcome)
            assertEquals(original.frozen!!.changes.map(LibraryRecovery::Historical), reconciled.recovery); assertNull(reconciled.acknowledgement)
            try { reconciled.freeze(); fail("Froze past collection") } catch (_: LibrarySyncFailure.InvalidReceipt) { }
            val retired = copied(original)
            retired.settleRetirement(SyncAckReply("owner-a", frame.clientKey, cursor), frame)
            assertEquals(reconciled, retired)
            val different = frame.batch.copy(operations = listOf(operation.copy(command = SyncCommand.FolderDelete(SyncFolderReference.Server("folder-b")))))
            val pending = SyncPending(frame.clientKey, frame.sequence, frame.batch.id, committed.digest, different.intentDigest(), "manifest", "generation", 1_000.0)
            val polled = copied(original)
            polled.settle(SyncExchange.Pending("owner-a", pending), frame, observationOwner(polled), observation(polled), 2_000.0)
            val previousRecovery = polled.recovery
            polled.settlePending(SyncExchange.Accepted(committed), pending, observationOwner(polled), observation(polled), 2_000.0)
            assertEquals(previousRecovery, polled.recovery); assertEquals(1, polled.recovery.size)
            assertEquals(LibraryOutcomeOrigin.Historical, polled.collectingOutcome!!.origin); assertNull(polled.acknowledgement)
            val acknowledged = copied(original)
            acknowledged.settle(accepted(frame, SyncReply("owner-a", frame.batch.id, listOf(SyncReceipt(operation.id, operation.revision, SyncOutcome.Preserved)))), frame, observationOwner(acknowledged), observation(acknowledged), 2_000.0)
            val ack = acknowledged.acknowledgement!!; val beforeAck = copied(acknowledged)
            val next = committed.copy(sequence = 2.0, digest = "next-digest", reply = committed.reply.copy(batchId = "next-batch"))
            acknowledged.settleAcknowledgement(SyncAckReply("owner-a", frame.clientKey, SyncCursor(1.0, SyncOutstanding.Committed(next))), ack)
            assertEquals(LibraryPendingOutcome(next, LibraryOutcomeOrigin.Historical), acknowledged.collectingOutcome); assertNull(acknowledged.acknowledgement)
            assertEquals(beforeAck.confirmed, acknowledged.confirmed)
        }
    }
    @Test fun manifestReceiptStagesOriginalUntilOutcomeCollection() {
        val state = LibraryPartitionState()
        state.append(LibraryLocalSource.Account(null), SyncCommand.FolderDelete(SyncFolderReference.Server("folder")), 1_000.0)
        val frame = state.freeze()!!; val operation = frame.batch.operations[0]
        val reply = SyncReply("owner-a", frame.batch.id, listOf(SyncReceipt(operation.id, operation.revision, SyncOutcome.FolderDeletedManifest("manifest", "generation", 501.0, 1_000.0))))
        state.settle(accepted(frame, reply), frame, observationOwner(state), observation(state), 2_000.0)
        assertEquals(frame.batch, state.frozen!!.batch); assertEquals(1.0, state.nextSequence, 0.0); assertNull(state.acknowledgement)
        assertEquals(LibraryOutcomeOrigin.Matched(frame.batch.intentDigest()), state.collectingOutcome!!.origin)
        try { state.freeze(); fail("Froze past collection") } catch (_: LibrarySyncFailure.InvalidReceipt) { }
        assertEquals(state, Json.decodeFromString<LibraryPartitionState>(Json.encodeToString(state)))
    }
    private fun mixedFolderFixture(): Triple<LibraryPartitionState, List<LibraryLocalChange>, LibraryLocalChange> {
        val before = LibraryLocalChange(SyncCommand.NotePut("before", "Unsent original A", 1_000.0, 1_000.0), 1_000.0, LibraryLocalSource.Note(GuestNoteDraft("before", "Unsent original A", 1_000.0, 1_000.0)))
        val folder = LibraryLocalChange(SyncCommand.FolderDelete(SyncFolderReference.Server("folder")), 1_000.0, LibraryLocalSource.Account(null))
        val after = LibraryLocalChange(SyncCommand.NotePut("after", "Unsent original B", 1_000.0, 1_000.0), 1_000.0, LibraryLocalSource.Account(null))
        val later = LibraryLocalChange(SyncCommand.BookmarkAdd("later", 2_000.0), 2_000.0, LibraryLocalSource.Account(null)); val original = listOf(before, folder, after)
        return Triple(LibraryPartitionState(frozen = LibraryFrozenBatch(SyncBatch("old-mixed", original.map { it.operation }), original), pending = listOf(later)), original, later)
    }
    @Test fun mixedSplitPersistsExactOriginalsAcrossFailedAckAndReopenBeforeIsolatedSends() = runBlocking {
        isolated { store, reopen, directory ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); val session = LibrarySyncSession("session-a", owner.subject)
            val (state, original, later) = mixedFolderFixture()
            File(directory, "guest_store.json").writeText(Json.encodeToString(GuestStoreFile(syncPartitions = listOf(LibrarySyncPartition(owner.storageKey, owner.subject, state)))))
            var failAck = true; val frames = mutableListOf<SyncFrame>(); val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
            val transport = object : LibrarySyncTransport {
                override val namespace = owner.namespace
                override suspend fun open() = SyncBinding(owner.key, owner.subject, "fixture", System.currentTimeMillis() + 60_000.0)
                override suspend fun acknowledge(capability: String, acknowledgement: SyncAcknowledgement): SyncAckReply {
                    if (acknowledgement.sequence == 1.0 && failAck) throw LibrarySyncFailure.StoreUnavailable
                    return SyncAckReply(owner.key, acknowledgement.clientKey, SyncCursor(acknowledgement.sequence))
                }
                override suspend fun send(capability: String, frame: SyncFrame): SyncExchange {
                    frames.add(frame)
                    return SyncExchange.Accepted(SyncCommitted(frame.clientKey, frame.sequence, "fixture-proof", SyncRevision(1.0, 0.0), SyncReply(owner.key, frame.batch.id, frame.batch.operations.map {
                        SyncReceipt(it.id, it.revision, if (frame.batch.id == "old-mixed") SyncOutcome.BatchRequiresSplit else if (it.command is SyncCommand.FolderDelete) SyncOutcome.Unresolved(SyncOutcomeUnresolvedReason.MISSING_FOLDER) else SyncOutcome.Preserved)
                    })))
                }
            }
            val sync = LibrarySync(store, transport, scope, { session })
            try {
                sync.activate(session); sync.deactivate()
                val saved = store.syncPartition(owner)!!
                assertNull(saved.frozen); assertEquals(original + later, saved.pending); assertEquals(2.0, saved.nextSequence, 0.0)
                assertEquals(1.0, saved.acknowledgement!!.sequence, 0.0); assertTrue(saved.recovery.isEmpty())
                try { store.freezeSyncFrame(owner); fail("Split requeue escaped ACK fence") } catch (_: LibrarySyncFailure.InvalidReceipt) { }
                failAck = false; val reopened = reopen(); val resumed = LibrarySync(reopened, transport, scope, { session })
                try {
                    resumed.activate(session); withTimeout(5_000) { resumed.status.first { it is LibrarySync.Status.Ready } }
                    assertEquals((original + later).map { it.operation }, frames.drop(1).flatMap { it.batch.operations })
                    assertEquals(1, frames.count { it.batch.id == "old-mixed" })
                    assertEquals(listOf(1), frames.drop(1).filter { it.batch.operations.any { it.command is SyncCommand.FolderDelete } }.map { it.batch.operations.size })
                    assertNull(reopened.syncPartition(owner)!!.acknowledgement); assertEquals(1, reopened.syncPartition(owner)!!.recovery.size)
                } finally { resumed.deactivate() }
            } finally { sync.deactivate(); scope.cancel() }
        }
    }
    @Test fun mixedSplitExactPollingRequeuesButHistoricalAndPartialRepliesDoNot() {
        val (base, original, later) = mixedFolderFixture(); val frame = SyncFrame(base.clientKey, 1.0, base.frozen!!.batch)
        val receipts = frame.batch.operations.map { SyncReceipt(it.id, it.revision, SyncOutcome.BatchRequiresSplit) }
        val proof = SyncCommitted(frame.clientKey, 1.0, "mixed-proof", SyncRevision(0.0, 0.0), SyncReply("owner-a", frame.batch.id, receipts))
        val waiting = base.copy(); val pending = SyncPending(frame.clientKey, 1.0, frame.batch.id, proof.digest, frame.batch.intentDigest(), "pending", "generation", 250.0)
        waiting.settle(SyncExchange.Pending("owner-a", pending), frame, observationOwner(waiting), observation(waiting), 2_000.0); waiting.settlePending(SyncExchange.Accepted(proof), pending, observationOwner(waiting), observation(waiting), 2_000.0)
        assertEquals(original + later, waiting.pending); assertNotNull(waiting.acknowledgement)
        val unknown = base.copy()
        unknown.settle(SyncExchange.Reconcile("owner-a", frame.clientKey, 1.0, frame.batch.id, SyncCursor(0.0, SyncOutstanding.Committed(proof))), frame, observationOwner(unknown), observation(unknown), 2_000.0)
        assertEquals(listOf(later), unknown.pending); assertEquals(original.map(LibraryRecovery::Historical), unknown.recovery)
        for (malformed in listOf(receipts.dropLast(1), listOf(receipts[0], receipts[0], receipts[2]), listOf(receipts[0], receipts[1].copy(outcome = SyncOutcome.Preserved), receipts[2]))) {
            val state = base.copy(); val before = Json.encodeToString(state)
            try { state.settle(SyncExchange.Accepted(proof.copy(reply = proof.reply.copy(receipts = malformed))), frame, observationOwner(state), observation(state), 2_000.0); fail("Malformed split changed original") } catch (_: LibrarySyncFailure.InvalidReceipt) { }
            assertEquals(before, Json.encodeToString(state))
        }
    }
    @Test fun compactFolderUndoCannotOverrideNewerMovesRemovalOrLaterDeletion() {
        val state = LibraryPartitionState(savedSnapshot = SyncSavedSnapshot("owner-a", 1.0, listOf(SyncFolderRow("folder", "Original", 1_000.0), SyncFolderRow("other", "Other", 1_000.0)), (0 until 3).map { index ->
            SyncSavedItem("item-$index", 1_000.0, 1_000.0, bookmarkCreatedAt = 1_000.0, folderId = "folder", hadith = SyncHadithSummary("item-$index", index.toString(), "bukhari", "Bukhari", "1", "نص", null, "Fixture"))
        }))
        val deletion = LibraryLocalChange(SyncCommand.FolderDelete(SyncFolderReference.Server("folder")), 2_000.0, LibraryLocalSource.Account(null)); state.pending = listOf(deletion)
        state.append(LibraryLocalSource.Account(null), SyncCommand.MembershipPut("item-0", SyncFolderReference.None), 3_000.0)
        state.append(LibraryLocalSource.Account(null), SyncCommand.BookmarkRemove("item-1"), 3_000.0); state.append(LibraryLocalSource.Account(null), SyncCommand.BookmarkAdd("item-1", 4_000.0), 4_000.0)
        state.append(LibraryLocalSource.Account(null), SyncCommand.FolderRestore(deletion.operation.id, "Original", emptyList()), 5_000.0)
        val restored = legacyProjection(state)
        assertNull(restored.items.first { it.hadithId == "item-0" }.folderId); assertNull(restored.items.first { it.hadithId == "item-1" }.folderId); assertNotNull(restored.items.first { it.hadithId == "item-2" }.folderId)
        state.append(LibraryLocalSource.Account(null), SyncCommand.FolderDelete(SyncFolderReference.Local("restore:${deletion.operation.id}")), 6_000.0)
        state.append(LibraryLocalSource.Account(null), SyncCommand.FolderRestore(deletion.operation.id, "Original", emptyList()), 7_000.0)
        assertTrue(legacyProjection(state).items.all { it.folderId == null })
        val advanced = state.copy(pending = listOf(state.pending.first { it.operation.command is SyncCommand.FolderRestore }), savedSnapshot = state.savedSnapshot!!.copy(version = 2.0, folders = emptyList(), items = state.savedSnapshot!!.items.map { it.copy(folderId = null) }))
        assertTrue(legacyProjection(advanced).items.all { it.folderId == null })
    }

    @Test fun accountFolderUndoIsCompactAndRestores501OfflineMembers() = runBlocking {
        isolated { store, reopen, _ ->
            val fixture = AndroidLibraryFacadeFixture(store)
            try {
                fixture.start()
                val rows = (0 until 501).map { index ->
                    val id = "item-$index"
                    SyncSavedItem(id, 1_000.0, 1_000.0, bookmarkCreatedAt = 1_000.0, folderId = "folder",
                        hadith = SyncHadithSummary(id, (index + 1).toString(), "bukhari", "Bukhari", "1", "نص", null, "Bukhari ${index + 1}"))
                }
                fixture.saved.emit(SyncSavedSnapshot("owner-a", 1.0, listOf(SyncFolderRow("folder", "Original folder", 1_000.0)), rows))
                waitForLibrary { fixture.model.savedItems.value.size == 501 }
                withContext(Dispatchers.Main) {
                    fixture.model.deleteFolder(fixture.model.folders.value.single(), "Folder deleted", fixture.model.actionScope)
                }
                waitForLibrary { fixture.model.undo.notice.value != null }
                withContext(Dispatchers.Main) { fixture.model.undo.undo() }
                withTimeout(3_000) {
                    while (true) {
                        val state = store.syncPartition(LibrarySyncOwner("owner-a", "subject-a"))!!
                        if ((state.frozen?.changes.orEmpty() + state.pending).any { it.operation.command is SyncCommand.FolderRestore }) break
                        if (fixture.model.lastWriteFailed.value) fail("Undo was rejected instead of queued")
                        delay(10)
                    }
                }
                val state = store.syncPartition(LibrarySyncOwner("owner-a", "subject-a"))!!
                val undo = (state.frozen?.changes.orEmpty() + state.pending).first { it.operation.command is SyncCommand.FolderRestore }
                assertTrue((undo.operation.command as SyncCommand.FolderRestore).hadithIds.isEmpty())
                waitForLibrary { fixture.model.savedItems.value.count { it.folderId != null } == 501 }
                assertEquals("Original folder", fixture.model.folders.value.single().name)
                assertTrue(Json.encodeToString(undo.operation).toByteArray().size < 1_024)
                fixture.stop()
                val reopened = AndroidLibraryFacadeFixture(reopen())
                try {
                    reopened.start(); waitForLibrary { reopened.model.savedItems.value.count { it.folderId != null } == 501 }
                    assertEquals("Original folder", reopened.model.folders.value.single().name)
                    assertNull(reopened.model.undo.notice.value)
                } finally { reopened.stop() }
            } finally { fixture.stop() }
        }
    }

    private suspend fun acknowledgedRetentionFixture(store: GuestDataStore, directory: File, count: Int, acknowledge: Boolean = true, acknowledgedAt: Double = 2_000.0): Pair<SyncCommitted, SyncAcknowledgement> {
        val owner = LibrarySyncOwner("owner-a", "subject-a"); var state = LibraryPartitionState()
        state.append(LibraryLocalSource.Account(null), SyncCommand.FolderDelete(SyncFolderReference.Server("folder")), 1_000.0)
        val original = state.freeze()!!; val operation = original.batch.operations.single()
        var encoded = Json.encodeToString(state)
        for ((from, to) in listOf(state.clientKey to "retention-device", original.batch.id to "retention-batch", operation.id to "retention-operation", operation.revision to "retention-revision")) encoded = encoded.replace(from, to)
        state = Json.decodeFromString(encoded)
        File(directory, "guest_store.json").writeText(Json.encodeToString(GuestStoreFile(syncPartitions = listOf(LibrarySyncPartition(owner.storageKey, owner.subject, state)))))
        val frame = store.freezeSyncFrame(owner)!!; val sent = frame.batch.operations.single()
        val proof = SyncCommitted(frame.clientKey, frame.sequence, "retention-proof", SyncRevision(2.0, 0.0), SyncReply(owner.key, frame.batch.id, listOf(
            SyncReceipt(sent.id, sent.revision, SyncOutcome.FolderDeletedManifest("manifest", "generation", count.toDouble(), 1_000.0)))))
        store.settleSyncExchange(SyncExchange.Accepted(proof), frame, owner); collectExportFacts(proof, owner, count, store)
        store.cacheSavedSnapshot(SyncSavedSnapshot(owner.key, 2.0, emptyList(), emptyList()), owner)
        assertEquals(LibraryOutcomeSettlement.Settled, store.settleCollectedOutcome(store.syncPartition(owner)!!.collectingOutcome!!, owner, acknowledgedAt))
        val ack = store.syncPartition(owner)!!.acknowledgement!!
        if (acknowledge) store.settleSyncAcknowledgement(SyncAckReply(owner.key, ack.clientKey, SyncCursor(ack.sequence)), ack, owner, acknowledgedAt)
        return proof to ack
    }

    @Test fun outcomeAckAndPartitionRollbackTogetherAndAcceptLaterCursorWithoutRenewal() = runBlocking {
        isolated { store, reopen, directory ->
            val (proof, ack) = acknowledgedRetentionFixture(store, directory, 1, acknowledge = false)
            val owner = LibrarySyncOwner("owner-a", "subject-a"); val before = store.syncPartition(owner)!!
            assertNotNull(before.manifestAckLink)
            val wrong = ack.copy(digest = "wrong")
            try { store.settleSyncAcknowledgement(SyncAckReply(owner.key, wrong.clientKey, SyncCursor(wrong.sequence)), wrong, owner, 2_000.0); fail("Wrong proof marked") } catch (_: LibrarySyncFailure.InvalidReceipt) { }
            assertNull(store.outcomeEvidencePage(proof, owner, 0).checkpoint.retention)
            val fence = store.prepareOutcomeExport(owner) { true }
            sql(directory) { it.execSQL("CREATE TRIGGER fail_account_write BEFORE UPDATE OF payload ON local_accounts BEGIN SELECT RAISE(ABORT,'injected'); END") }
            try {
                try { store.settleSyncAcknowledgement(SyncAckReply(owner.key, ack.clientKey, SyncCursor(ack.sequence)), ack, owner, 2_000.0); fail("Failed partition ACK save succeeded") } catch (_: android.database.sqlite.SQLiteException) { }
            } finally { sql(directory) { it.execSQL("DROP TRIGGER fail_account_write") } }
            val reopened = reopen(); assertEquals(before, reopened.syncPartition(owner))
            assertNull(reopened.outcomeEvidencePage(proof, owner, 0).checkpoint.retention)
            reopened.validateOutcomeExport(fence)
            val pending = SyncPending(ack.clientKey, 4.0, "next-batch", "next-proof", "a".repeat(64), "next-manifest", "next-generation", 250.0)
            reopened.settleSyncAcknowledgement(SyncAckReply(owner.key, ack.clientKey, SyncCursor(3.0, SyncOutstanding.Pending(pending))), ack, owner, 9_000.0)
            assertEquals(4.0, reopened.syncPartition(owner)!!.nextSequence, 0.0); assertEquals(pending, reopened.syncPartition(owner)!!.waiting)
            assertNull(reopened.syncPartition(owner)!!.manifestAckLink)
            assertEquals(9_000.0, reopened.outcomeEvidencePage(proof, owner, 0).checkpoint.retention!!.acknowledgedAt, 0.0)
            try { reopened.settleSyncAcknowledgement(SyncAckReply(owner.key, ack.clientKey, SyncCursor(ack.sequence)), ack, owner, 12_000.0); fail("Stale ACK renewed marker") } catch (_: LibrarySyncFailure.InvalidReceipt) { }
            assertEquals(9_000.0, reopened.outcomeEvidencePage(proof, owner, 0).checkpoint.retention!!.acknowledgedAt, 0.0)
        }
    }

    @Test fun outcomeRetentionPreservesPartitionlessEvidenceUntilScopedErasure() = runBlocking {
        isolated { store, reopen, directory ->
            val (proof, _) = acknowledgedRetentionFixture(store, directory, 1)
            val owner = LibrarySyncOwner("owner-a", "subject-a"); val replacement = LibrarySyncOwner("replacement", owner.subject)
            android.database.sqlite.SQLiteDatabase.openDatabase(File(directory, "library_outcomes.db").path, null, 0).use { db ->
                assertEquals(1, db.delete("local_accounts", "key=? AND subject=?", arrayOf(owner.storageKey, owner.subject)))
            }
            val reopened = reopen(); reopened.claimGuestForSync(replacement)
            reopened.cacheSavedSnapshot(SyncSavedSnapshot(replacement.key, 2.0, emptyList(), emptyList()), replacement)
            for (step in 0 until 10) { if (!reopened.pruneOutcomeSuccessStep(replacement, 2_000 + LibraryOutcomeRetention.duration)) break }
            assertEquals(1, reopened.outcomeEvidencePage(proof, owner, 0).rows.size); assertNull(reopened.syncPartition(owner))
            reopened.beginDeletion(replacement.subject, replacement.namespace); reopened.markDeletionBackendComplete(replacement.subject, replacement.namespace)
            try { reopened.outcomeEvidencePage(proof, owner, 0); fail("Orphan evidence not erased") } catch (_: LibrarySyncFailure.StoreUnavailable) { }
            try { reopened.pruneOutcomeSuccessStep(replacement, 2_000 + LibraryOutcomeRetention.duration); fail("Erased cleanup recreated owner") } catch (_: LibrarySyncFailure.AccountDeleting) { }
            assertNull(reopened.syncPartition(replacement))
        }
    }

    @Test fun outcomeRetentionResumesBoundedPruneRejectsPartialExportAndAdmitsLateRestore() = runBlocking {
        isolated { store, reopen, directory ->
            val acknowledgedAt = System.currentTimeMillis().toDouble(); val (proof, _) = acknowledgedRetentionFixture(store, directory, 501, acknowledgedAt = acknowledgedAt)
            val owner = LibrarySyncOwner("owner-a", "subject-a"); val oldFence = store.prepareOutcomeExport(owner) { true }
            val fixture = AndroidLibraryFacadeFixture(store); fixture.start()
            try {
                withContext(Dispatchers.Main) {
                    val captured = fixture.sync.captureWriteContext()
                    assertTrue(store.pruneOutcomeSuccessStep(owner, acknowledgedAt + LibraryOutcomeRetention.duration - 1)); store.pruneOutcomeSuccessStep(owner, acknowledgedAt + LibraryOutcomeRetention.duration - 1)
                    assertEquals(1, store.outcomeEvidencePage(proof, owner, 500).rows.size)
                    assertTrue(store.pruneOutcomeSuccessStep(owner, acknowledgedAt + LibraryOutcomeRetention.duration))
                    try { store.validateOutcomeExport(oldFence); fail("Pruning escaped export fence") } catch (_: LibrarySyncFailure.StoreUnavailable) { }
                    try { store.outcomeEvidencePage(proof, owner, 0); fail("Partial prune exported complete") } catch (_: LibrarySyncFailure.StoreUnavailable) { }
                    val current = store.prepareOutcomeExport(owner) { true }
                    assertEquals(50L, store.outcomeExportEntries(current, null).single().checkpoint.retention!!.removed)
                    try { fixture.sync.preparePortableExport(kotlinx.serialization.json.JsonObject(emptyMap()), captured, "export.json"); fail("Half-pruned journal exported") } catch (_: LibrarySyncFailure.StoreUnavailable) { }
                }
                fixture.stop()
                val reopened = reopen()
                val database = File(directory, "library_outcomes.db").path
                android.database.sqlite.SQLiteDatabase.openDatabase(database, null, android.database.sqlite.SQLiteDatabase.OPEN_READWRITE).use {
                    it.execSQL("CREATE TRIGGER stop_prune BEFORE DELETE ON members WHEN OLD.ordinal>=50 BEGIN SELECT RAISE(ABORT,'controlled-prune-failure'); END")
                }
                try { reopened.pruneOutcomeSuccessStep(owner, acknowledgedAt + LibraryOutcomeRetention.duration); fail("Failed prune page advanced") } catch (_: android.database.sqlite.SQLiteException) { }
                android.database.sqlite.SQLiteDatabase.openDatabase(database, null, android.database.sqlite.SQLiteDatabase.OPEN_READWRITE).use { db ->
                    db.rawQuery("SELECT count(*) FROM members", null).use { assertTrue(it.moveToFirst()); assertEquals(451L, it.getLong(0)) }
                    db.execSQL("DROP TRIGGER stop_prune")
                }
                val retainedFence = reopened.prepareOutcomeExport(owner) { true }
                assertEquals(50L, reopened.outcomeExportEntries(retainedFence, null).single().checkpoint.retention!!.removed)
                val late = LibraryLocalChange(SyncCommand.FolderRestore(proof.reply.receipts.single().id, "Late restore original", emptyList()), System.currentTimeMillis().toDouble(), LibraryLocalSource.Account(null))
                reopened.enqueueSyncChange(late, owner)
                var steps = 0
                while (reopened.pruneOutcomeSuccessStep(owner, acknowledgedAt + LibraryOutcomeRetention.duration)) { steps++; assertTrue(steps < 30) }
                try { reopened.outcomeEvidencePage(proof, owner, 0); fail("Prune did not finish") } catch (_: LibrarySyncFailure.StoreUnavailable) { }
                assertEquals(listOf(late), reopened.syncPartition(owner)!!.pending)
                android.database.sqlite.SQLiteDatabase.openDatabase(database, null, android.database.sqlite.SQLiteDatabase.OPEN_READONLY).use { db ->
                    for (table in listOf("members", "headers", "scopes")) db.rawQuery("SELECT count(*) FROM $table", null).use { assertTrue(it.moveToFirst()); assertEquals(0L, it.getLong(0)) }
                }
                val resumed = AndroidLibraryFacadeFixture(reopened); resumed.server.failSends = false; resumed.server.nextOutcome = SyncOutcome.Unresolved(SyncOutcomeUnresolvedReason.MISSING_FOLDER)
                try {
                    resumed.start(); assertEquals(listOf(late.operation), resumed.server.frames.first().batch.operations)
                    assertEquals(late, (reopened.syncPartition(owner)!!.recovery.last() as LibraryRecovery.Server).change)
                } finally { resumed.stop() }
            } finally { fixture.stop() }
        }
    }

    @Test fun outcomeRetentionCursorPassesFiftyRetainedHeadersAndResumesAfterReopen() = runBlocking {
        isolated { store, reopen, directory ->
            val (proof, _) = acknowledgedRetentionFixture(store, directory, 1)
            val owner = LibrarySyncOwner("owner-a", "subject-a"); val key = LibraryOutcomeBinding(owner, proof).key
            val retained = (0 until 1_000).map { taggedOutcomeProof(owner, 0, "retained-$it") }.filter { LibraryOutcomeBinding(owner, it).key < key }.take(51)
            assertEquals(51, retained.size)
            retained.forEach { collectExportFacts(it, owner, 0, store) }
            store.prepareOutcomeExport(owner) { true }
            assertTrue(store.pruneOutcomeSuccessStep(owner, 2_000 + LibraryOutcomeRetention.duration)); assertNotNull(store.syncPartition(owner)!!.outcomeRetentionCursor)
            assertEquals(1, store.outcomeEvidencePage(proof, owner, 0).rows.size)
            val reopened = reopen()
            assertTrue(reopened.pruneOutcomeSuccessStep(owner, 2_000 + LibraryOutcomeRetention.duration))
            try { reopened.outcomeEvidencePage(proof, owner, 0); fail("Eligible tail starved") } catch (_: LibrarySyncFailure.StoreUnavailable) { }
            retained.forEach { assertNull(reopened.outcomeEvidencePage(it, owner, 0).checkpoint.retention) }
            assertFalse(reopened.pruneOutcomeSuccessStep(owner, 2_000 + LibraryOutcomeRetention.duration)); assertNull(reopened.syncPartition(owner)!!.outcomeRetentionCursor)
        }
    }

    @Test fun outcomeRetentionPolicyPreservesEachDurableDependencyAndOldProoflessData() {
        val owner = LibrarySyncOwner("owner-a", "subject-a"); val proof = taggedOutcomeProof(owner, 1, "policy"); val binding = LibraryOutcomeBinding(owner, proof)
        val now = 2_000 + LibraryOutcomeRetention.duration; val checkpoint = LibraryOutcomeCheckpoint(binding.expected, LibraryOutcomeStatus.Complete, LibraryOutcomeRetention(2_000.0))
        val base = LibraryPartitionState(savedSnapshot = SyncSavedSnapshot(owner.key, 2.0, emptyList(), emptyList()))
        assertTrue(base.canPruneOutcome(binding, checkpoint, observation(base, binding.owner), now)); assertFalse(base.canPruneOutcome(binding, checkpoint, observation(base, binding.owner), now - 1)); assertFalse(base.canPruneOutcome(binding, checkpoint, observation(base, binding.owner), 1_000.0))
        assertFalse(base.canPruneOutcome(binding, LibraryOutcomeCheckpoint(binding.expected, LibraryOutcomeStatus.Complete), observation(base, binding.owner), now))
        val undo = LibraryLocalChange(SyncCommand.FolderRestore(binding.request.receiptId, "Offline Undo", emptyList()), 1_000.0, LibraryLocalSource.Account(null))
        val states = mutableListOf(base.copy(pending = listOf(undo)), base.copy(frozen = LibraryFrozenBatch(SyncBatch("frozen", listOf(undo.operation)), listOf(undo))),
            base.copy(manifestAckLink = binding.authority), base.copy(collectingOutcome = LibraryPendingOutcome(proof, LibraryOutcomeOrigin.Historical)),
            base.copy(recent = listOf(LibraryRecentReceipt(proof.reply.receipts.single(), now + 1))))
        for (entry in listOf(LibraryRecovery.Server(undo, SyncOutcome.Unresolved(SyncOutcomeUnresolvedReason.MISSING_FOLDER)), LibraryRecovery.Historical(undo), LibraryRecovery.Rejected(undo), LibraryRecovery.Outcome(binding.authority, checkpoint, null))) states.add(base.copy(recovery = listOf(entry)))
        states.forEach { assertFalse(it.canPruneOutcome(binding, checkpoint, observation(it, binding.owner), now)) }
    }

    @Test fun outcomeRetentionDependenciesDoNotBlockUnrelatedJournals() {
        val owner = LibrarySyncOwner("owner-a", "subject-a")
        val deleteA = LibraryOutcomeBinding(owner, taggedOutcomeProof(owner, 1, "a")); val deleteB = LibraryOutcomeBinding(owner, taggedOutcomeProof(owner, 1, "b"))
        fun restore(tag: String): LibraryOutcomeBinding {
            val base = taggedOutcomeProof(owner, 1, tag)
            return LibraryOutcomeBinding(owner, base.copy(reply = base.reply.copy(receipts = listOf(SyncReceipt("$tag-restore", "r1", SyncOutcome.FolderRestoredManifest(tag, "generation", "destination-$tag", 1.0, 0.0, 0.0))))))
        }
        val restoreA = restore("a"); val restoreB = restore("b"); val state = LibraryPartitionState()
        val undo = LibraryLocalChange(SyncCommand.FolderRestore(deleteA.request.receiptId, "Undo A", emptyList()), 1_000.0, LibraryLocalSource.Account(null))
        for (recovery in listOf(false, true)) {
            state.pending = if (recovery) emptyList() else listOf(undo); state.recovery = if (recovery) listOf(LibraryRecovery.Historical(undo)) else emptyList()
            assertTrue(state.retainsOutcome(deleteA, 99_000.0)); assertFalse(state.retainsOutcome(deleteB, 99_000.0)); assertFalse(state.retainsOutcome(restoreB, 99_000.0))
        }
        state.recovery = emptyList(); state.folderMappings = mapOf("alias-a" to "destination-a")
        for (command in listOf(SyncCommand.MembershipPut("hadith", SyncFolderReference.Local("alias-a")), SyncCommand.FolderDelete(SyncFolderReference.Local("alias-a")))) {
            state.pending = listOf(LibraryLocalChange(command, 1_000.0, LibraryLocalSource.Account(null)))
            assertTrue(state.retainsOutcome(restoreA, 99_000.0)); assertFalse(state.retainsOutcome(restoreB, 99_000.0)); assertFalse(state.retainsOutcome(deleteA, 99_000.0))
        }
    }

    @Test fun coordinatorPrunesAcknowledgedSuccessfulOutcomeAfterRetention() = runBlocking {
        isolated { store, _, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); val session = LibrarySyncSession("session-a", owner.subject)
            var clock = 1_000.0; var proof: SyncCommitted? = null; var acknowledgements = 0
            store.claimGuestForSync(owner)
            store.enqueueSyncChange(LibraryLocalChange(SyncCommand.FolderDelete(SyncFolderReference.Server("folder")), clock, LibraryLocalSource.Account(null)), owner)
            store.cacheSavedSnapshot(SyncSavedSnapshot(owner.key, 1.0, emptyList(), emptyList()), owner)
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
            val transport = object : LibrarySyncTransport {
                override val namespace = owner.namespace
                override suspend fun open() = SyncBinding(owner.key, owner.subject, "fixture", clock + 60_000)
                override suspend fun acknowledge(capability: String, acknowledgement: SyncAcknowledgement): SyncAckReply {
                    acknowledgements++; return SyncAckReply(owner.key, acknowledgement.clientKey, SyncCursor(acknowledgement.sequence))
                }
                override suspend fun send(capability: String, frame: SyncFrame): SyncExchange {
                    val operation = frame.batch.operations.single()
                    val committed = SyncCommitted(frame.clientKey, frame.sequence, "fixture-proof", SyncRevision(1.0, 0.0), SyncReply(owner.key, frame.batch.id, listOf(
                        SyncReceipt(operation.id, operation.revision, SyncOutcome.FolderDeletedManifest("manifest", "generation", 1.0, clock)))))
                    proof = committed; return SyncExchange.Accepted(committed)
                }
                override suspend fun outcomePage(capability: String, request: SyncOutcomePageRequest) = outcomePage(request, owner, 1)
            }
            val sync = LibrarySync(store, transport, scope, { session }, { clock })
            try {
                sync.activate(session); val committed = proof!!
                assertEquals(1, acknowledgements); assertEquals(1, store.outcomeEvidencePage(committed, owner, 0).rows.size)
                withTimeout(3_000) { while (store.syncPartition(owner)?.outcomeRetentionCursor != null) delay(10) }
                clock += 31 * 24 * 60 * 60 * 1_000.0
                sync.activate(session)
                withTimeout(3_000) {
                    while (true) {
                        try { store.outcomeEvidencePage(committed, owner, 0) } catch (_: LibrarySyncFailure.StoreUnavailable) { break }
                        delay(10)
                    }
                }
                try { store.outcomeEvidencePage(committed, owner, 0); fail("Successful acknowledged journal remained forever") } catch (_: LibrarySyncFailure.StoreUnavailable) { }
                val fence = store.prepareOutcomeExport(owner) { true }; assertTrue(store.outcomeExportEntries(fence, null).isEmpty())
            } finally { sync.deactivate(); scope.cancel() }
        }
    }

    @Test fun outcomeSettlementUnavailablePolicySurvivesReopenAndExport() = runBlocking {
        for (reason in listOf(SyncOutcomePageUnavailableReason.DETAIL_UNAVAILABLE, SyncOutcomePageUnavailableReason.PROOF_UNAVAILABLE)) isolated { store, reopen, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); store.claimGuestForSync(owner)
            val original = LibraryLocalChange(SyncCommand.FolderRestore("deleted", "Original unavailable", listOf("hadith-0")), 1_000.0, LibraryLocalSource.Account(null))
            store.enqueueSyncChange(original, owner)
            val frame = store.freezeSyncFrame(owner)!!; val operation = frame.batch.operations.single()
            val proof = SyncCommitted(frame.clientKey, frame.sequence, "fixture-digest", SyncRevision(2.0, 0.0), SyncReply(owner.key, frame.batch.id, listOf(
                SyncReceipt(operation.id, operation.revision, SyncOutcome.FolderRestoredManifest("manifest", "generation", "destination", 50.0, 0.0, 1.0)))))
            store.settleSyncExchange(SyncExchange.Accepted(proof), frame, owner)
            store.collectOutcomeStep(proof, owner, { true }) { outcomePage(it, owner, 51, restore = true) }
            store.collectOutcomeStep(proof, owner, { true }) { SyncOutcomePage.Unavailable(owner.key, it, reason) }
            store.cacheSavedSnapshot(SyncSavedSnapshot(owner.key, 2.0, emptyList(), emptyList()), owner)
            val before = store.syncPartition(owner)!!; val pending = before.collectingOutcome!!; val reopened = reopen()
            assertEquals(if (reason == SyncOutcomePageUnavailableReason.DETAIL_UNAVAILABLE) LibraryOutcomeSettlement.Settled else LibraryOutcomeSettlement.ProofUnavailable, reopened.settleCollectedOutcome(pending, owner, 2_000.0))
            if (reason == SyncOutcomePageUnavailableReason.PROOF_UNAVAILABLE) assertEquals(before, reopened.syncPartition(owner)) else assertNotNull(reopened.syncPartition(owner)!!.acknowledgement)
            val fixture = AndroidLibraryFacadeFixture(reopened)
            try {
                fixture.start(); assertEquals(if (reason == SyncOutcomePageUnavailableReason.DETAIL_UNAVAILABLE) 1 else 0, fixture.server.acknowledgements)
                withContext(Dispatchers.Main) {
                    val captured = fixture.sync.captureWriteContext(); val export = fixture.sync.preparePortableExport(kotlinx.serialization.json.JsonObject(emptyMap()), captured, "export.json")
                    try {
                        val data = export.file.readText(); val document = Json.parseToJsonElement(data) as kotlinx.serialization.json.JsonObject
                        val entry = (document["localOutcomeEvidence"] as kotlinx.serialization.json.JsonArray).single() as kotlinx.serialization.json.JsonObject
                        assertEquals(50, (entry["rows"] as kotlinx.serialization.json.JsonArray).size)
                        assertEquals(kotlinx.serialization.json.JsonPrimitive(false), entry["detailComplete"])
                        assertTrue(data.contains("Original unavailable"))
                    } finally { fixture.sync.discardPreparedExport(export) }
                }
            } finally { fixture.stop() }
        }
    }

    @Test fun outcomeSettlementRejectsForeignScopeAndErasedOwnerWithoutRecreation() = runBlocking {
        isolated { store, reopen, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); store.claimGuestForSync(owner)
            store.enqueueSyncChange(LibraryLocalChange(SyncCommand.FolderDelete(SyncFolderReference.Server("folder")), 1_000.0, LibraryLocalSource.Account(null)), owner)
            val frame = store.freezeSyncFrame(owner)!!; val operation = frame.batch.operations.single()
            val proof = SyncCommitted(frame.clientKey, frame.sequence, "fixture-digest", SyncRevision(2.0, 0.0), SyncReply(owner.key, frame.batch.id, listOf(
                SyncReceipt(operation.id, operation.revision, SyncOutcome.FolderDeletedManifest("manifest", "generation", 1.0, 1_000.0)))))
            store.settleSyncExchange(SyncExchange.Accepted(proof), frame, owner); collectExportFacts(proof, owner, 1, store)
            store.cacheSavedSnapshot(SyncSavedSnapshot(owner.key, 2.0, emptyList(), emptyList()), owner)
            val before = store.syncPartition(owner)!!; val pending = before.collectingOutcome!!
            val foreign = LibrarySyncOwner(owner.key, owner.subject, "other-deployment")
            try { store.settleCollectedOutcome(pending, foreign, 2_000.0); fail("Foreign scope settled") } catch (_: LibrarySyncFailure.SessionChanged) { }
            assertEquals(before, store.syncPartition(owner)); assertNull(store.syncPartition(foreign))
            store.beginDeletion(owner.subject, owner.namespace); store.markDeletionBackendComplete(owner.subject, owner.namespace)
            val reopened = reopen()
            try { reopened.settleCollectedOutcome(pending, owner, 2_000.0); fail("Erased owner settled") } catch (_: LibrarySyncFailure.AccountDeleting) { }
            assertNull(reopened.syncPartition(owner))
            try { reopened.outcomeEvidencePage(proof, owner, 0); fail("Erased evidence recreated") } catch (_: LibrarySyncFailure.StoreUnavailable) { }
        }
    }

    @Test fun outcomeSettlementWriteFailureKeepsFrozenAndRetryAdvancesOnce() = runBlocking {
        isolated { store, reopen, directory ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); store.claimGuestForSync(owner)
            store.enqueueSyncChange(LibraryLocalChange(SyncCommand.FolderDelete(SyncFolderReference.Server("folder")), 1_000.0, LibraryLocalSource.Account(null)), owner)
            val frame = store.freezeSyncFrame(owner)!!; val operation = frame.batch.operations.single()
            val proof = SyncCommitted(frame.clientKey, frame.sequence, "fixture-digest", SyncRevision(2.0, 0.0), SyncReply(owner.key, frame.batch.id, listOf(
                SyncReceipt(operation.id, operation.revision, SyncOutcome.FolderDeletedManifest("manifest", "generation", 1.0, 1_000.0)))))
            store.settleSyncExchange(SyncExchange.Accepted(proof), frame, owner)
            collectExportFacts(proof, owner, 1, store)
            store.cacheSavedSnapshot(SyncSavedSnapshot(owner.key, 2.0, emptyList(), emptyList()), owner)
            val before = store.syncPartition(owner)!!; val pending = before.collectingOutcome!!
            sql(directory) { it.execSQL("CREATE TRIGGER fail_account_write BEFORE UPDATE OF payload ON local_accounts BEGIN SELECT RAISE(ABORT,'injected'); END") }
            try {
                try { store.settleCollectedOutcome(pending, owner, 2_000.0); fail("Failed SQLite write settled") } catch (_: android.database.sqlite.SQLiteException) { }
            } finally { sql(directory) { it.execSQL("DROP TRIGGER fail_account_write") } }
            val reopened = reopen(); assertEquals(before, reopened.syncPartition(owner))
            assertEquals(LibraryOutcomeSettlement.Settled, reopened.settleCollectedOutcome(pending, owner, 7_000.0))
            val settled = reopened.syncPartition(owner)
            assertEquals(LibraryOutcomeSettlement.Settled, reopened.settleCollectedOutcome(pending, owner, 8_000.0)); assertEquals(settled, reopened.syncPartition(owner))
            assertTrue(settled!!.recent.isEmpty()); assertEquals(1, reopened.outcomeEvidencePage(proof, owner, 0).rows.size)
        }
    }

    @Test fun outcomeSettlementTerminalPoliciesAndExactIntent() {
        val owner = LibrarySyncOwner("owner-a", "subject-a")
        for (mode in listOf("delete", "restore", "partial", "detail", "proof", "historical")) {
            val state = LibraryPartitionState()
            val command = if (mode == "delete") SyncCommand.FolderDelete(SyncFolderReference.Server("folder")) else SyncCommand.FolderRestore("deleted", "Original folder", listOf("hadith-0", "hadith-1"))
            state.append(LibraryLocalSource.Account(null), command, 1_000.0)
            val frame = state.freeze()!!; val operation = frame.batch.operations.single()
            val outcome = if (mode == "delete") SyncOutcome.FolderDeletedManifest("manifest", "generation", 51.0, 1_000.0)
                else SyncOutcome.FolderRestoredManifest("manifest", "generation", "destination", 50.0, 0.0, if (mode == "restore") 0.0 else 1.0)
            val proof = SyncCommitted(frame.clientKey, frame.sequence, "fixture-digest", SyncRevision(2.0, 0.0), SyncReply(owner.key, frame.batch.id, listOf(SyncReceipt(operation.id, operation.revision, outcome))))
            if (mode == "historical") state.settle(SyncExchange.Reconcile(owner.key, frame.clientKey, frame.sequence, frame.batch.id, SyncCursor(0.0, SyncOutstanding.Committed(proof))), frame, observationOwner(state), observation(state), 2_000.0)
            else state.settle(SyncExchange.Accepted(proof), frame, observationOwner(state), observation(state), 2_000.0)
            val pending = state.collectingOutcome!!; val binding = LibraryOutcomeBinding(owner, proof)
            val checkpoint = if (mode == "detail" || mode == "proof") LibraryOutcomeCheckpoint(LibraryOutcomeCounts(restored = 50), LibraryOutcomeStatus.Unavailable(if (mode == "detail") SyncOutcomePageUnavailableReason.DETAIL_UNAVAILABLE else SyncOutcomePageUnavailableReason.PROOF_UNAVAILABLE))
                else LibraryOutcomeCheckpoint(binding.expected, LibraryOutcomeStatus.Complete)
            state.savedSnapshot = SyncSavedSnapshot(owner.key, 1.0, emptyList(), emptyList())
            val before = Json.encodeToString(state)
            assertEquals(if (mode == "proof") LibraryOutcomeSettlement.ProofUnavailable else LibraryOutcomeSettlement.AwaitingSaved, state.settleCollectedOutcome(pending, binding, checkpoint, observation(state, binding.owner), 2_000.0))
            assertEquals(before, Json.encodeToString(state))
            state.savedSnapshot = SyncSavedSnapshot(owner.key, 3.0, emptyList(), emptyList())
            if (mode == "proof") {
                val blocked = Json.encodeToString(state)
                assertEquals(LibraryOutcomeSettlement.ProofUnavailable, state.settleCollectedOutcome(pending, binding, checkpoint, observation(state, binding.owner), 2_000.0)); assertEquals(blocked, Json.encodeToString(state)); continue
            }
            val original = state.frozen?.changes?.single()
            if (mode == "delete") {
                val late = state.copy()
                assertEquals(LibraryOutcomeSettlement.Settled, late.settleCollectedOutcome(pending, binding, checkpoint, observation(late, binding.owner), 7_000.0)); assertTrue(late.recent.isEmpty())
            }
            if (mode == "partial") {
                for (status in listOf(LibraryOutcomeStatus.Collecting, LibraryOutcomeStatus.Verifying(LibraryOutcomeCounts()))) {
                    val unfinished = state.copy(); val unfinishedBefore = Json.encodeToString(unfinished)
                    assertEquals(LibraryOutcomeSettlement.Collecting, unfinished.settleCollectedOutcome(pending, binding, LibraryOutcomeCheckpoint(binding.expected, status), observation(unfinished, binding.owner), 2_000.0)); assertEquals(unfinishedBefore, Json.encodeToString(unfinished))
                }
                val incomplete = state.copy(); val incompleteBefore = Json.encodeToString(incomplete)
                try { incomplete.settleCollectedOutcome(pending, binding, LibraryOutcomeCheckpoint(status = LibraryOutcomeStatus.Complete), observation(incomplete, binding.owner), 2_000.0); fail("Incomplete totals accepted") } catch (_: LibrarySyncFailure.InvalidReceipt) { }; assertEquals(incompleteBefore, Json.encodeToString(incomplete))
                val missing = state.copy(frozen = null); val missingBefore = Json.encodeToString(missing)
                try { missing.settleCollectedOutcome(pending, binding, checkpoint, observation(missing, binding.owner), 2_000.0); fail("Missing original accepted") } catch (_: LibrarySyncFailure.InvalidReceipt) { }; assertEquals(missingBefore, Json.encodeToString(missing))
                val wrongOwner = state.copy(savedSnapshot = SyncSavedSnapshot("owner-b", 3.0, emptyList(), emptyList())); val wrongBefore = Json.encodeToString(wrongOwner)
                try { wrongOwner.settleCollectedOutcome(pending, binding, checkpoint, observation(wrongOwner, binding.owner), 2_000.0); fail("Foreign snapshot accepted") } catch (_: LibrarySyncFailure.OwnerMismatch) { }; assertEquals(wrongBefore, Json.encodeToString(wrongOwner))
                val fork = Json.decodeFromString<LibraryPartitionState>(Json.encodeToString(state).replace("Original folder", "Changed folder")); val forkBefore = Json.encodeToString(fork)
                try { fork.settleCollectedOutcome(pending, binding, checkpoint, observation(fork, binding.owner), 2_000.0); fail("Changed original accepted") } catch (_: LibrarySyncFailure.InvalidReceipt) { }; assertEquals(forkBefore, Json.encodeToString(fork))
                val conflict = state.copy(folderMappings = mapOf("restore:deleted" to "another-folder")); val conflictBefore = Json.encodeToString(conflict)
                try { conflict.settleCollectedOutcome(pending, binding, checkpoint, observation(conflict, binding.owner), 2_000.0); fail("Alias collision replaced") } catch (_: LibrarySyncFailure.InvalidReceipt) { }; assertEquals(conflictBefore, Json.encodeToString(conflict))
            }
            assertEquals(LibraryOutcomeSettlement.Settled, state.settleCollectedOutcome(pending, binding, checkpoint, observation(state, binding.owner), 2_000.0))
            assertEquals(2.0, state.nextSequence, 0.0); assertNull(state.collectingOutcome); assertNull(state.frozen)
            if (mode == "delete") { assertEquals(listOf(6_000.0), state.recent.map { it.expiresAt }); assertTrue(state.recovery.isEmpty()) }
            else if (mode == "restore") { assertEquals("destination", state.folderMappings["restore:deleted"]); assertTrue(state.recovery.isEmpty()) }
            else {
                val retained = state.recovery.last() as LibraryRecovery.Outcome
                assertEquals(binding.authority, retained.authority); assertEquals(checkpoint, retained.checkpoint)
                assertEquals(if (mode == "historical") null else original, retained.original)
                if (mode == "historical") assertEquals(2, state.recovery.size)
            }
            val settled = Json.encodeToString(state)
            assertEquals(LibraryOutcomeSettlement.Settled, state.settleCollectedOutcome(pending, binding, checkpoint, observation(state, binding.owner), 7_000.0)); assertEquals(settled, Json.encodeToString(state))
        }
    }

    @Test fun manifestSettlementWaitsForOwnedSavedThenPersistsRecoveryBeforeRetryableAck() = runBlocking {
        isolated { store, reopen, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); store.claimGuestForSync(owner)
            val original = LibraryLocalChange(SyncCommand.FolderRestore("deleted", "Original folder", listOf("hadith-0", "hadith-1")), 1_000.0, LibraryLocalSource.Account(null))
            store.enqueueSyncChange(original, owner)
            val frame = store.freezeSyncFrame(owner)!!; val operation = frame.batch.operations.single()
            val proof = SyncCommitted(frame.clientKey, frame.sequence, "fixture-digest", SyncRevision(2.0, 0.0), SyncReply(owner.key, frame.batch.id, listOf(
                SyncReceipt(operation.id, operation.revision, SyncOutcome.FolderRestoredManifest("manifest", "generation", "restored-folder", 1.0, 0.0, 1.0)))))
            store.settleSyncExchange(SyncExchange.Accepted(proof), frame, owner)
            repeat(2) { store.collectOutcomeStep(proof, owner, { true }) { outcomePage(it, owner, 2, restore = true) } }
            val later = LibraryLocalChange(SyncCommand.NotePut("later", "Later original", 2_000.0, 2_000.0), 2_000.0, LibraryLocalSource.Account(null))
            store.enqueueSyncChange(later, owner)
            val fixture = AndroidLibraryFacadeFixture(store); fixture.server.failAcknowledgements = true
            try {
                fixture.start(); fixture.saved.emit(fixture.snapshot(1.0, "Before barrier"))
                withTimeout(3_000) { while (store.syncPartition(owner)?.savedSnapshot?.version != 1.0) delay(10) }
                assertEquals(0, fixture.server.acknowledgements); assertNotNull(store.syncPartition(owner)!!.frozen)
                fixture.saved.emit(fixture.snapshot(2.0, "Authoritative"))
                waitForLibrary { fixture.server.acknowledgements > 0 }
                val settled = store.syncPartition(owner)!!
                assertNull(settled.collectingOutcome); assertNull(settled.frozen)
                assertEquals(listOf(later), settled.pending); assertEquals(2.0, settled.nextSequence, 0.0)
                assertNotNull(settled.acknowledgement); assertEquals(1, settled.recovery.size)
                assertEquals("restored-folder", settled.folderMappings["restore:deleted"])
                assertTrue(Json.encodeToString(settled.recovery).contains("Original folder"))
                fixture.stop()
                val reopened = reopen(); val resumed = AndroidLibraryFacadeFixture(reopened)
                try {
                    resumed.start()
                    assertEquals(1, resumed.server.acknowledgements)
                    assertNull(reopened.syncPartition(owner)!!.acknowledgement)
                    assertEquals(settled.recovery, reopened.syncPartition(owner)!!.recovery)
                    assertEquals(listOf(later), reopened.syncPartition(owner)!!.frozen!!.changes)
                    assertEquals(2, reopened.outcomeEvidencePage(proof, owner, 0).rows.size)
                } finally { resumed.stop() }
            } finally { fixture.stop() }
        }
    }
    @Test fun coordinatorResumesManifestPagesAfterReopenWithoutAcknowledgingOrSendingLaterChanges() = runBlocking {
        isolated { store, reopen, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); val session = LibrarySyncSession("session-a", "subject-a")
            store.claimGuestForSync(owner)
            store.enqueueSyncChange(LibraryLocalChange(SyncCommand.FolderDelete(SyncFolderReference.Server("folder")), 1_000.0, LibraryLocalSource.Account(null)), owner)
            val later = LibraryLocalChange(SyncCommand.BookmarkAdd("later", 2_000.0), 2_000.0, LibraryLocalSource.Account(null))
            store.enqueueSyncChange(later, owner)
            var proof: SyncCommitted? = null; var sends = 0; var acknowledgements = 0; val starts = mutableListOf<Double>()
            fun transport(failAt100: Boolean) = object : LibrarySyncTransport {
                override val namespace = "fixture"
                override suspend fun open() = SyncBinding(owner.key, owner.subject, "fixture", System.currentTimeMillis() + 60_000.0)
                override suspend fun acknowledge(capability: String, acknowledgement: SyncAcknowledgement): SyncAckReply { acknowledgements++; return SyncAckReply(owner.key, acknowledgement.clientKey, SyncCursor(acknowledgement.sequence)) }
                override suspend fun send(capability: String, frame: SyncFrame): SyncExchange {
                    sends++; val operation = frame.batch.operations[0]
                    val committed = SyncCommitted(frame.clientKey, frame.sequence, "fixture-digest", SyncRevision(2.0, 0.0), SyncReply(owner.key, frame.batch.id,
                        listOf(SyncReceipt(operation.id, operation.revision, SyncOutcome.FolderDeletedManifest("manifest", "generation", 501.0, 1_000.0)))))
                    proof = committed
                    return SyncExchange.Accepted(committed)
                }
                override suspend fun outcomePage(capability: String, request: SyncOutcomePageRequest): SyncOutcomePage {
                    starts.add(request.start)
                    if (failAt100 && request.start == 100.0) throw LibrarySyncFailure.StoreUnavailable
                    return outcomePage(request, owner, 501)
                }
            }
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
            val sync = LibrarySync(store, transport(true), scope, { session })
            try {
                sync.activate(session)
                assertEquals(LibrarySync.Status.Failed, sync.status.value); sync.deactivate()
                val committed = proof!!; val original = store.syncPartition(owner)!!
                assertEquals(committed, original.collectingOutcome!!.committed); assertEquals(listOf(later), original.pending)
                assertNotNull(original.frozen); assertNull(original.acknowledgement)
                assertEquals(100L, store.outcomeEvidencePage(committed, owner, 0).checkpoint.next)
                starts.clear()
                val reopened = reopen(); val resumed = LibrarySync(reopened, transport(false), scope, { session })
                try {
                    resumed.activate(session)
                    withTimeout(8_000) { resumed.status.first { it == LibrarySync.Status.WaitingForSaved } }
                    assertEquals((100..500 step 50).map { it.toDouble() }, starts)
                    assertEquals(LibraryOutcomeStatus.Complete, reopened.outcomeEvidencePage(committed, owner, 500).checkpoint.status)
                    assertEquals(original, reopened.syncPartition(owner)); assertEquals(1, sends); assertEquals(0, acknowledgements)
                } finally { resumed.deactivate() }
            } finally { sync.deactivate(); scope.cancel() }
        }
    }
    @Test fun malformedManifestCannotArchiveOriginalBeforeValidation() {
        val state = LibraryPartitionState()
        state.append(LibraryLocalSource.Account(null), SyncCommand.FolderDelete(SyncFolderReference.Server("folder")), 1_000.0)
        val frame = state.freeze()!!; val before = Json.encodeToString(state); val operation = frame.batch.operations[0]
        val bad = SyncCommitted(frame.clientKey, frame.sequence, "digest", SyncRevision(2.0, 0.0), SyncReply("owner-a", frame.batch.id,
            listOf(SyncReceipt(operation.id, operation.revision, SyncOutcome.FolderRestoredManifest("manifest", "generation", "folder", 2.0, 0.0, -1.0)))))
        try { state.settle(SyncExchange.Reconcile("owner-a", frame.clientKey, frame.sequence, frame.batch.id, SyncCursor(0.0, SyncOutstanding.Committed(bad))), frame, observationOwner(state), observation(state), 2_000.0); fail("Malformed manifest accepted") } catch (_: LibrarySyncFailure.InvalidReceipt) { }
        assertEquals(before, Json.encodeToString(state))
    }

    @Test fun heldOriginalSurvivesStoreReopenRetirementAndTerminalFailure() = runBlocking {
        isolated { store, reopen, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a")
            store.claimGuestForSync(owner)
            store.enqueueSyncChange(LibraryLocalChange(SyncCommand.FolderDelete(SyncFolderReference.Server("folder-a")), 1_000.0, LibraryLocalSource.Account(null)), owner)
            val later = LibraryLocalChange(SyncCommand.NotePut("target", "Later original", 2_000.0, 2_000.0), 2_000.0, LibraryLocalSource.Account(null))
            store.enqueueSyncChange(later, owner)
            val frame = store.freezeSyncFrame(owner)!!
            assertEquals(1, frame.batch.operations.size)
            val pending = SyncPending(frame.clientKey, frame.sequence, frame.batch.id, "fixture-digest", frame.batch.intentDigest(), "manifest", "generation", 1_000.0)
            store.settleSyncExchange(SyncExchange.Pending(owner.key, pending), frame, owner)
            val reopened = reopen(); val before = reopened.syncPartition(owner)!!
            assertEquals(pending, before.waiting); assertEquals(frame.batch, before.frozen!!.batch)
            assertEquals(listOf(later), before.pending); assertEquals(1.0, before.nextSequence, 0.0); assertNull(before.acknowledgement)
            try { reopened.freezeSyncFrame(owner); fail("Froze while pending") } catch (_: LibrarySyncFailure.InvalidReceipt) { }
            reopened.settleSyncRetirement(SyncAckReply(owner.key, frame.clientKey, SyncCursor(0.0, SyncOutstanding.Pending(pending))), frame, owner)
            assertEquals(frame.batch, reopened.syncPartition(owner)!!.frozen!!.batch)
            try { reopened.settleSyncPending(SyncExchange.Pending("other-owner", pending), pending, owner); fail("Wrong owner accepted") } catch (_: LibrarySyncFailure.OwnerMismatch) { }
            val operation = frame.batch.operations[0]
            reopened.settleSyncPending(accepted(frame, SyncReply(owner.key, frame.batch.id, listOf(SyncReceipt(operation.id, operation.revision, SyncOutcome.Unresolved(SyncOutcomeUnresolvedReason.PREPARATION_EXPIRED))))), pending, owner)
            val terminal = reopened.syncPartition(owner)!!
            assertNull(terminal.waiting); assertNull(terminal.frozen); assertEquals(1, terminal.recovery.size)
            val proof = terminal.acknowledgement!!
            reopened.settleSyncAcknowledgement(SyncAckReply(owner.key, proof.clientKey, SyncCursor(proof.sequence)), proof, owner)
            assertEquals(listOf(later.operation), reopened.freezeSyncFrame(owner)!!.batch.operations)
        }
    }

    @Test fun coordinatorDelaysPendingPollingAndSendsLaterIntentOnlyAfterTerminalAck() = runBlocking {
        isolated { store, _, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); val session = LibrarySyncSession("session-a", "subject-a")
            store.claimGuestForSync(owner)
            store.enqueueSyncChange(LibraryLocalChange(SyncCommand.FolderDelete(SyncFolderReference.Server("folder-a")), 1_000.0, LibraryLocalSource.Account(null)), owner)
            store.enqueueSyncChange(LibraryLocalChange(SyncCommand.BookmarkAdd("target", 2_000.0), 2_000.0, LibraryLocalSource.Account(null)), owner)
            val sends = mutableListOf<SyncFrame>(); var polls = 0; var acknowledgements = 0
            val transport = object : LibrarySyncTransport {
                override val namespace = "fixture"
                override suspend fun open() = SyncBinding(owner.key, owner.subject, "fixture", System.currentTimeMillis() + 60_000.0)
                override suspend fun acknowledge(capability: String, acknowledgement: SyncAcknowledgement): SyncAckReply { acknowledgements++; return SyncAckReply(owner.key, acknowledgement.clientKey, SyncCursor(acknowledgement.sequence)) }
                override suspend fun send(capability: String, frame: SyncFrame): SyncExchange {
                    sends.add(frame)
                    if (sends.size == 1) return SyncExchange.Pending(owner.key, SyncPending(frame.clientKey, frame.sequence, frame.batch.id, "fixture-digest", frame.batch.intentDigest(), "manifest", "generation", 1_000.0))
                    return accepted(frame, SyncReply(owner.key, frame.batch.id, frame.batch.operations.map { SyncReceipt(it.id, it.revision, SyncOutcome.Preserved) }))
                }
                override suspend fun poll(capability: String, pending: SyncPending): SyncExchange {
                    polls++; val frame = sends[0]; val operation = frame.batch.operations[0]
                    return accepted(frame, SyncReply(owner.key, frame.batch.id, listOf(SyncReceipt(operation.id, operation.revision, SyncOutcome.Unresolved(SyncOutcomeUnresolvedReason.PREPARATION_EXPIRED)))))
                }
            }
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
            val sync = LibrarySync(store, transport, scope, { session })
            try {
                sync.activate(session)
                assertEquals(1, sends.size); assertEquals(0, polls); assertEquals(0, acknowledgements)
                withTimeout(4_000) { sync.status.first { it == LibrarySync.Status.Ready(1) } }
                assertEquals(1, polls); assertEquals(2, sends.size); assertEquals(2, acknowledgements)
            } finally { sync.deactivate(); scope.cancel() }
        }
    }

    @Test fun intentFingerprintMatchesBackendUnicodeAndNumberVectors() {
        for ((encoded, digest) in LibrarySyncIntentVectors.values) assertEquals(digest, Json.decodeFromString<SyncBatch>(encoded).intentDigest())
    }

    @Test fun pendingCloneWithReusedIDsArchivesItsDifferentIntent() {
        val state = LibraryPartitionState()
        state.append(LibraryLocalSource.Account(null), SyncCommand.FolderDelete(SyncFolderReference.Server("folder-a")), 1_000.0)
        val frame = state.freeze()!!
        val original = frame.batch.operations[0]
        val serverBatch = frame.batch.copy(operations = listOf(original.copy(command = SyncCommand.FolderDelete(SyncFolderReference.Server("folder-b")))))
        val pending = SyncPending(frame.clientKey, frame.sequence, frame.batch.id, "fixture-digest", serverBatch.intentDigest(), "manifest", "generation", 1_000.0)
        state.settle(SyncExchange.Reconcile("owner-a", frame.clientKey, frame.sequence, frame.batch.id, SyncCursor(0.0, SyncOutstanding.Pending(pending))), frame, observationOwner(state), observation(state), 2_000.0)
        assertNull(state.frozen)
        assertEquals(1, state.recovery.size)
        state.settlePending(accepted(frame, SyncReply("owner-a", frame.batch.id, listOf(SyncReceipt(original.id, original.revision, SyncOutcome.Preserved)))), pending, observationOwner(state), observation(state), 2_000.0)
        assertTrue(state.confirmed.isEmpty())
        assertEquals(pending.digest, state.acknowledgement!!.digest)
    }

    private fun accepted(frame: SyncFrame, reply: SyncReply) = SyncExchange.Accepted(SyncCommitted(frame.clientKey, frame.sequence, "fixture-digest", SyncRevision(frame.sequence, frame.sequence), reply))
    private suspend fun GuestDataStore.settleFixture(reply: SyncReply, frame: SyncFrame, owner: LibrarySyncOwner) = settleSyncExchange(accepted(frame, reply), frame, owner)

    private suspend fun isolated(block: suspend (GuestDataStore, () -> GuestDataStore, File) -> Unit) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.cacheDir, "guest-merge-race-${System.nanoTime()}").apply { mkdirs() }
        val wrapper = object : ContextWrapper(context) {
            override fun getFilesDir(): File = directory
            override fun getCacheDir(): File = File(directory, "cache").apply { mkdirs() }
        }
        try { block(GuestDataStore(wrapper), { GuestDataStore(wrapper) }, directory) }
        finally { directory.deleteRecursively() }
    }
    private suspend fun note(store: GuestDataStore, content: String) = store.saveNote("jn7fxd3z54153q9j13kmhgzkv18df2zd", content, null, null, null, null, null, "", null)

    @Test fun deletionDoesNotContactCloudOrReplaceDamagedLocalState() = runBlocking {
        isolated { store, _, directory ->
            val file = File(directory, "guest_store.json")
            val damaged = "{interrupted-private-deletion-fixture"
            file.writeText(damaged)
            val session = LibrarySyncSession("session-a", "subject-a")
            var cloudCalls = 0; var identityCalls = 0
            val flow = LibraryAccountDeletion(store, "fixture", { session }, {},
                prepare = { cloudCalls++; SyncDeletionAuthorization(session.subject, "fixture", System.currentTimeMillis() + 60_000.0) },
                erase = { cloudCalls++; SyncDeletionResult(session.subject, true) }, cleanup = {}, deleteIdentity = { identityCalls++ })
            try { flow.run(session); fail("Damaged local state admitted deletion") } catch (_: LibrarySyncFailure.StoreUnavailable) { }
            assertEquals(0, cloudCalls); assertEquals(0, identityCalls); assertEquals(damaged, file.readText())
        }
    }

    @Test fun deletionSurvivesResponseLossRestartAndIdentityFailureWithoutBootstrappingOrErasingOtherScopes() = runBlocking {
        isolated { store, reopen, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a")
            val other = LibrarySyncOwner("owner-b", "subject-b")
            val otherDeployment = LibrarySyncOwner("owner-a", "subject-a", "other-deployment")
            val session = LibrarySyncSession("session-a", owner.subject)
            var serverCalls = 0; var identityCalls = 0
            note(store, "A original"); store.claimGuestForSync(owner)
            note(store, "B original"); store.claimGuestForSync(other); store.claimGuestForSync(otherDeployment)
            fun flow(target: GuestDataStore, loseResponse: Boolean, failIdentity: Boolean) = LibraryAccountDeletion(target, "fixture", { session }, {},
                prepare = { SyncDeletionAuthorization(session.subject, "fixture", System.currentTimeMillis() + 60_000.0) },
                erase = { serverCalls++; if (loseResponse) throw java.io.IOException("Lost response fixture"); SyncDeletionResult(session.subject, false) },
                cleanup = {}, deleteIdentity = { identityCalls++; if (failIdentity) throw java.io.IOException("Identity offline fixture") })
            try { flow(store, true, false).run(session); fail("Lost response accepted") } catch (_: java.io.IOException) { }
            assertEquals(1, serverCalls); assertEquals(0, identityCalls)
            assertEquals(LibraryDeletionPhase.SERVER_PENDING, store.deletionPhase(session.subject, "fixture"))
            assertNotNull(store.syncPartition(owner))
            assertDeletionBlocksBootstrap(store, session)
            val reopened = reopen()
            try { flow(reopened, false, true).run(session); fail("Identity failure accepted") } catch (_: java.io.IOException) { }
            assertEquals(2, serverCalls); assertEquals(1, identityCalls)
            assertEquals(LibraryDeletionPhase.IDENTITY_PENDING, reopened.deletionPhase(session.subject, "fixture"))
            assertNull(reopened.syncPartition(owner)); assertNotNull(reopened.syncPartition(other)); assertNotNull(reopened.syncPartition(otherDeployment))
            assertDeletionBlocksBootstrap(reopened, session)
            val final = reopen()
            flow(final, false, false).run(session)
            assertEquals(2, serverCalls); assertEquals(2, identityCalls)
            assertNull(final.deletionPhase(session.subject, "fixture")); assertNotNull(final.syncPartition(other))
        }
    }

    private suspend fun assertDeletionBlocksBootstrap(store: GuestDataStore, session: LibrarySyncSession) {
        var opens = 0
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val transport = object : LibrarySyncTransport {
            override val namespace = "fixture"
            override suspend fun open(): SyncBinding { opens++; throw java.io.IOException("Must not bootstrap fixture") }
            override suspend fun acknowledge(capability: String, acknowledgement: SyncAcknowledgement): SyncAckReply = throw LibrarySyncFailure.InvalidReceipt
            override suspend fun send(capability: String, frame: SyncFrame): SyncExchange = throw LibrarySyncFailure.InvalidReceipt
        }
        val sync = LibrarySync(store, transport, scope, { session })
        try {
            sync.activate(session)
            assertEquals(0, opens); assertEquals(LibrarySync.Status.Failed, sync.status.value); assertNull(sync.owner.value)
        } finally { withContext(Dispatchers.Main) { sync.deactivate() }; scope.cancel() }
    }

    @Test fun deletionRejectsWrongPreparationAndFinishesOnlyCapturedLocalErasureAfterSwitch() = runBlocking {
        isolated { store, _, _ ->
            val a = LibrarySyncSession("session-a", "subject-a"); val b = LibrarySyncSession("session-b", "subject-b")
            val current = MutableStateFlow(a)
            val ownerA = LibrarySyncOwner("owner-a", a.subject); val ownerB = LibrarySyncOwner("owner-b", b.subject)
            note(store, "A original"); store.claimGuestForSync(ownerA)
            note(store, "B original"); store.claimGuestForSync(ownerB)
            var erases = 0; var identities = 0
            val cleanups = mutableListOf<String>()
            val wrong = LibraryAccountDeletion(store, "fixture", { current.value }, {},
                prepare = { SyncDeletionAuthorization(b.subject, "wrong-owner-fixture", System.currentTimeMillis() + 60_000.0) },
                erase = { erases++; SyncDeletionResult(b.subject, true) }, cleanup = { cleanups.add(it) }, deleteIdentity = { identities++ })
            try { wrong.run(a); fail("Wrong preparation accepted") } catch (_: LibrarySyncFailure.OwnerMismatch) { }
            assertEquals(0, erases); assertNotNull(store.syncPartition(ownerA))
            val switched = LibraryAccountDeletion(store, "fixture", { current.value }, {},
                prepare = { SyncDeletionAuthorization(a.subject, "owner-a-fixture", System.currentTimeMillis() + 60_000.0) },
                erase = { erases++; current.value = b; SyncDeletionResult(a.subject, true) }, cleanup = { cleanups.add(it) }, deleteIdentity = { identities++ })
            try { switched.run(a); fail("Switched identity deletion accepted") } catch (_: LibrarySyncFailure.SessionChanged) { }
            assertEquals(1, erases); assertEquals(0, identities); assertEquals(listOf(a.subject), cleanups)
            assertNull(store.syncPartition(ownerA)); assertNotNull(store.syncPartition(ownerB))
            assertEquals(LibraryDeletionPhase.IDENTITY_PENDING, store.deletionPhase(a.subject, "fixture"))
            try { switched.run(a); fail("Stale confirmation accepted") } catch (_: LibrarySyncFailure.SessionChanged) { }
            assertEquals(1, erases); assertEquals(0, identities)
        }
    }

    @Test fun portableExportIncludesDurableOutcomeJournal() = runBlocking {
        isolated { store, _, _ ->
            val fixture = AndroidLibraryFacadeFixture(store)
            try {
                fixture.start()
                val owner = LibrarySyncOwner("owner-a", "subject-a"); val proof = outcomeProof(owner, 51)
                repeat(4) { store.collectOutcomeStep(proof, owner, { true }) { outcomePage(it, owner, 51) } }
                val captured = withContext(Dispatchers.Main) { fixture.sync.captureWriteContext() }
                val prepared = fixture.sync.preparePortableExport(kotlinx.serialization.json.JsonObject(mapOf("sync" to kotlinx.serialization.json.JsonObject(emptyMap()))), captured, "export.json")
                try {
                    val document = Json.parseToJsonElement(prepared.file.readText())
                    assertTrue("Retained journal facts must be in the private export", document.toString().contains("member-50"))
                    val output = java.io.ByteArrayOutputStream()
                    fixture.sync.copyPreparedExport(prepared, output)
                    assertEquals(document, Json.parseToJsonElement(output.toString(Charsets.UTF_8.name())))
                } finally { fixture.sync.discardPreparedExport(prepared) }
            } finally { fixture.stop() }
        }
    }

    @Test fun portableExportIncludesOfflineAndRecoveryTextWithoutProviderPassagesAndRejectsSwitchedOwner() = runBlocking {
        isolated { store, _, _ ->
            note(store, "Recovery fixture " + "界".repeat(8_001))
            val fixture = AndroidLibraryFacadeFixture(store)
            try {
                fixture.start()
                val text = "Private draft mentions arabicText and pushTokens"
                assertTrue(withContext(Dispatchers.Main) { fixture.model.saveNote(fixture.reference, text) }.await())
                val captured = withContext(Dispatchers.Main) { fixture.sync.captureWriteContext() }
                val local = withContext(Dispatchers.Main) { fixture.sync.portableState(captured) }
                assertFalse(local.containsExportKey(setOf("arabicText", "englishText", "capability")))
                assertTrue(local.toString().contains(text))
                assertTrue(local.toString().contains("Recovery fixture"))
                val server = kotlinx.serialization.json.JsonObject(mapOf("sync" to kotlinx.serialization.json.JsonObject(mapOf("streams" to kotlinx.serialization.json.JsonArray(emptyList()))), "evidenceItems" to kotlinx.serialization.json.JsonArray(emptyList())))
                val document = kotlinx.serialization.json.JsonObject(server + ("localLibrary" to local))
                assertFalse(document.containsExportKey(setOf("pushTokens", "adminAuditLog", "revenueCatAppUserId")))
                assertTrue(document.containsKey("sync"))
                assertTrue(document.containsKey("evidenceItems"))
                assertEquals(document, kotlinx.serialization.json.Json.parseToJsonElement(document.toString()))
                withContext(Dispatchers.Main) {
                    fixture.session.value = LibrarySyncSession("session-b", "subject-b")
                    fixture.sync.deactivate(); fixture.model.refresh()
                    fixture.sync.activate(fixture.session.value!!)
                    try { fixture.sync.portableState(captured); fail("Switched owner exported") }
                    catch (_: LibrarySyncFailure.SessionChanged) { }
                    val other = fixture.sync.portableState(fixture.sync.captureWriteContext()).toString()
                    assertFalse(other.contains("Private draft"))
                    assertFalse(other.contains("Recovery fixture"))
                }
            } finally { fixture.stop() }
        }
    }

    @Test fun inconsistentFrozenPayloadIsRetainedBeforeDispatchOrRetirement() {
        val original = LibraryLocalChange(SyncCommand.NotePut("target", "Original source fixture", 1_000.0, 1_000.0), 1_000.0, LibraryLocalSource.Account(null))
        val different = original.operation.copy(command = SyncCommand.NotePut("target", "Different wire fixture", 1_000.0, 1_000.0))
        val frozen = LibraryFrozenBatch(SyncBatch("inconsistent-payload", listOf(different)), listOf(original))
        val state = LibraryPartitionState(frozen = frozen)
        try { state.freeze(); fail("Inconsistent frozen payload admitted") } catch (_: LibrarySyncFailure.InvalidReceipt) { }
        assertEquals(frozen, state.frozen)
        val json = Json.encodeToString(state)
        assertTrue(json.contains("Original source fixture")); assertTrue(json.contains("Different wire fixture"))
    }

    @Test fun previouslyGuessedFrozenGuestMembershipClockRequiresFencedRecovery() {
        val draft = GuestSavedMembership("target", "old-folder")
        val guessed = LibraryLocalChange(SyncCommand.MembershipPut("target", SyncFolderReference.Local("old-folder")), 9_000.0, LibraryLocalSource.Membership(draft))
        val old = LibraryFrozenBatch(SyncBatch("old-guessed", listOf(guessed.operation)), listOf(guessed))
        assertTrue(LibrarySyncAdmission.accepts(old.batch))
        assertFalse(LibrarySyncAdmission.accepts(old))
        val claim = LibraryLocalChange(SyncCommand.MembershipPut("target", SyncFolderReference.Local("old-folder"), "claim_if_unset"), 0.0, LibraryLocalSource.Membership(draft))
        assertTrue(LibrarySyncAdmission.accepts(LibraryFrozenBatch(SyncBatch("new-claim", listOf(claim.operation)), listOf(claim))))
    }

    @Test fun legacyPayloadKeepsFolderClockSeparateFromLaterNoteEdits() {
        val id = "jn7fxd3z54153q9j13kmhgzkv18df2zd"
        val payload = GuestMergePlanner.makePayload(bookmarks = emptyList(), notes = listOf(GuestNoteDraft(id, "Later note", 1_000.0, 9_000.0)),
            folders = listOf(GuestSavedFolderDraft("guest-folder", "Guest fixture", 1_000.0)), memberships = listOf(GuestSavedMembership(id, "guest-folder", 2_000.0)))
        assertEquals(9_000.0, payload.savedItems.single().updatedAt, 0.0)
        assertEquals(2_000.0, payload.savedItems.single().folderUpdatedAt!!, 0.0)
    }

    @Test fun undatedGuestMembershipUsesClaimOnlyAndDoesNotOptimisticallyReplaceCloudFolder() = runBlocking {
        isolated { store, _, directory ->
            val id = "jn7fxd3z54153q9j13kmhgzkv18df2zd"
            val owner = LibrarySyncOwner("owner-a", "subject-a")
            File(directory, "guest_store.json").writeText(Json.encodeToString(GuestStoreFile(bookmarks = listOf(GuestBookmarkDraft(id, 1_000.0)),
                savedFolders = listOf(GuestSavedFolderDraft("old-guest-folder", "Old guest folder", 9_000.0)), savedMemberships = listOf(GuestSavedMembership(id, "old-guest-folder")))))
            store.claimGuestForSync(owner)
            val state = store.syncPartition(owner)!!
            val change = state.pending.first { it.operation.command is SyncCommand.MembershipPut }
            val command = change.operation.command
            assertTrue(command is SyncCommand.MembershipPut)
            if (command !is SyncCommand.MembershipPut) return@isolated
            assertEquals("claim_if_unset", command.mode); assertEquals(0.0, change.operation.at, 0.0)
            val hadith = SyncHadithSummary(id, "1", "bukhari", "Bukhari", "1", "نص", null, "Bukhari 1")
            state.savedSnapshot = SyncSavedSnapshot(owner.key, 1.0, listOf(SyncFolderRow("cloud-folder", "Cloud folder", 1_000.0)), listOf(SyncSavedItem(id, 1_000.0, 3_000.0, bookmarkCreatedAt = 1_000.0, folderId = "cloud-folder", hadith = hadith)))
            assertEquals("cloud-folder", legacyProjection(state).items.single().folderId)
            state.pending = emptyList()
            state.confirmed = listOf(LibraryConfirmedChange(change, SyncOutcome.Preserved, 2.0))
            state.folderMappings = mapOf("old-guest-folder" to "accepted-guest-folder")
            assertEquals("accepted-guest-folder", legacyProjection(state).items.single().folderId)
            state.confirmed = emptyList()
            assertEquals("cloud-folder", legacyProjection(state).items.single().folderId)
            val batch = SyncBatch("unversioned-rejected", listOf(change.operation))
            state.frozen = LibraryFrozenBatch(batch, listOf(change))
            val frame = SyncFrame(state.clientKey, state.nextSequence, batch)
            val outcome = SyncOutcome.Superseded(SyncOutcomeSupersededReason.UNVERSIONED_CLOUD)
            state.settle(accepted(frame, SyncReply(owner.key, batch.id, listOf(SyncReceipt(change.operation.id, change.operation.revision, outcome)))), frame, observationOwner(state), observation(state), System.currentTimeMillis().toDouble())
            assertEquals(listOf(LibraryRecovery.Server(change, outcome)), state.recovery)
            assertEquals("cloud-folder", legacyProjection(state).items.single().folderId)
            val reopened = Json.decodeFromString(LibraryPartitionState.serializer(), Json.encodeToString(state))
            assertEquals(state.recovery, reopened.recovery)
        }
    }

    @Test fun coordinatorContinuesAfterItsQuarantinePassBudgetWithoutSendingInvalidIntent() = runBlocking {
        isolated { store, _, directory ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); val session = LibrarySyncSession("session-a", owner.subject)
            val rejected = (0 until 401).map { LibraryLocalChange(SyncCommand.NotePut("target", "", 1_000.0, 1_000.0), 1_000.0, LibraryLocalSource.Account(null)) }
            val valid = LibraryLocalChange(SyncCommand.BookmarkAdd("target", 1_000.0), 1_000.0, LibraryLocalSource.Account(null))
            val state = LibraryPartitionState(pending = rejected + valid)
            File(directory, "guest_store.json").writeText(Json.encodeToString(GuestStoreFile(syncPartitions = listOf(LibrarySyncPartition(owner.storageKey, owner.subject, state)))))
            val sent = mutableListOf<SyncFrame>()
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
            val transport = object : LibrarySyncTransport {
                override val namespace = "fixture"
                override suspend fun open() = SyncBinding(owner.key, owner.subject, "fixture", System.currentTimeMillis() + 60_000.0)
                override suspend fun acknowledge(capability: String, acknowledgement: SyncAcknowledgement) = SyncAckReply(owner.key, acknowledgement.clientKey, SyncCursor(acknowledgement.sequence))
                override suspend fun send(capability: String, frame: SyncFrame): SyncExchange {
                    sent.add(frame); assertEquals(listOf(valid.operation), frame.batch.operations)
                    return accepted(frame, SyncReply(owner.key, frame.batch.id, listOf(SyncReceipt(valid.operation.id, valid.operation.revision, SyncOutcome.Preserved))))
                }
            }
            val sync = LibrarySync(store, transport, scope, { session })
            try {
                sync.activate(session)
                withTimeout(3_000) { sync.status.first { it == LibrarySync.Status.Ready(401) } }
                assertEquals(1, sent.size)
                assertEquals(rejected.map { LibraryRecovery.Rejected(it) }, store.syncPartition(owner)!!.recovery)
                assertTrue(store.syncPartition(owner)!!.pending.isEmpty()); assertNull(store.syncPartition(owner)!!.acknowledgement)
            } finally { withContext(Dispatchers.Main) { sync.deactivate() }; scope.cancel() }
        }
    }

    @Test fun legacyFrozenInvalidFrameSurvivesLostRetirementResponseAndAllowsLaterIntent() = runBlocking {
        isolated { store, reopen, directory ->
            val owner = LibrarySyncOwner("owner-a", "subject-a")
            val session = LibrarySyncSession("session-a", owner.subject)
            val invalid = LibraryLocalChange(SyncCommand.NotePut("target", "界".repeat(8_001), 1_000.0, 1_000.0), 1_000.0, LibraryLocalSource.Account(null))
            val valid = LibraryLocalChange(SyncCommand.BookmarkAdd("target", 1_000.0), 1_000.0, LibraryLocalSource.Account(null))
            val state = LibraryPartitionState(pending = listOf(valid), frozen = LibraryFrozenBatch(SyncBatch("legacy-frozen", listOf(invalid.operation)), listOf(invalid)))
            File(directory, "guest_store.json").writeText(Json.encodeToString(GuestStoreFile(syncPartitions = listOf(LibrarySyncPartition(owner.storageKey, owner.subject, state)))))
            var retirements = 0
            val sent = mutableListOf<SyncFrame>()
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
            val transport = object : LibrarySyncTransport {
                override val namespace = "fixture"
                override suspend fun open() = SyncBinding(owner.key, owner.subject, "fixture", System.currentTimeMillis() + 60_000.0)
                override suspend fun acknowledge(capability: String, acknowledgement: SyncAcknowledgement) = SyncAckReply(owner.key, acknowledgement.clientKey, SyncCursor(acknowledgement.sequence))
                override suspend fun send(capability: String, frame: SyncFrame): SyncExchange {
                    sent.add(frame); assertEquals(listOf(valid.operation), frame.batch.operations)
                    return accepted(frame, SyncReply(owner.key, frame.batch.id, frame.batch.operations.map { SyncReceipt(it.id, it.revision, SyncOutcome.Preserved) }))
                }
                override suspend fun retireInvalid(capability: String, frame: SyncFrame): SyncAckReply {
                    retirements++; assertEquals("legacy-frozen", frame.batch.id)
                    if (retirements == 1) throw java.io.IOException("Lost retirement response fixture")
                    return SyncAckReply(owner.key, frame.clientKey, SyncCursor(frame.sequence))
                }
            }
            val sync = LibrarySync(store, transport, scope, { session })
            try {
                sync.activate(session)
                assertEquals(1, retirements); assertTrue(sent.isEmpty())
                assertEquals("legacy-frozen", store.syncPartition(owner)!!.frozen!!.batch.id)
                sync.activate(session)
                withTimeout(3_000) { while (store.syncPartition(owner)?.frozen != null || sent.isEmpty()) delay(10) }
                assertEquals(2, retirements); assertEquals(2.0, sent.single().sequence, 0.0)
                assertEquals(listOf(LibraryRecovery.Historical(invalid)), store.syncPartition(owner)!!.recovery)
                assertTrue(store.syncPartition(owner)!!.pending.isEmpty()); assertNull(store.syncPartition(owner)!!.acknowledgement)
                assertEquals(listOf(LibraryRecovery.Historical(invalid)), reopen().syncPartition(owner)!!.recovery)
            } finally { withContext(Dispatchers.Main) { sync.deactivate() }; scope.cancel() }
        }
    }

    @Test fun retirementCannotClearANewerFrozenFrameOrLoseAnOccupiedReceipt() {
        val invalid = LibraryLocalChange(SyncCommand.NotePut("target", "", 1_000.0, 1_000.0), 1_000.0, LibraryLocalSource.Account(null))
        val state = LibraryPartitionState(frozen = LibraryFrozenBatch(SyncBatch("invalid-frozen", listOf(invalid.operation)), listOf(invalid)))
        val requested = requireNotNull(state.freeze())
        try { state.settleRetirement(SyncAckReply("owner-a", "other-installation", SyncCursor(1.0)), requested); fail("Wrong installation accepted") } catch (_: LibrarySyncFailure.InvalidReceipt) { }
        val active = SyncCommitted(state.clientKey, 1.0, "committed-proof", SyncRevision(1.0, 0.0), SyncReply("owner-a", "other-committed-batch", emptyList()))
        state.settleRetirement(SyncAckReply("owner-a", state.clientKey, SyncCursor(0.0, SyncOutstanding.Committed(active))), requested)
        assertEquals(listOf(LibraryRecovery.Historical(invalid)), state.recovery)
        val proof = requireNotNull(state.acknowledgement)
        assertEquals("committed-proof", proof.digest)
        state.settleAcknowledgement(SyncAckReply("owner-a", state.clientKey, SyncCursor(1.0)), proof)
        state.pending = listOf(LibraryLocalChange(SyncCommand.BookmarkAdd("target", 1_000.0), 1_000.0, LibraryLocalSource.Account(null)))
        val next = requireNotNull(state.freeze()); assertEquals(2.0, next.sequence, 0.0)
        try { state.settleRetirement(SyncAckReply("owner-a", state.clientKey, SyncCursor(1.0)), requested); fail("Stale retirement accepted") } catch (_: LibrarySyncFailure.InvalidReceipt) { }
        assertEquals(next, state.freeze())
    }

    @Test fun oneFreezeBoundsQuarantineWorkBeforeAValidLaterChange() {
        val rejected = (0 until 101).map { LibraryLocalChange(SyncCommand.NotePut("target", "", 1_000.0, 1_000.0), 1_000.0, LibraryLocalSource.Account(null)) }
        val valid = LibraryLocalChange(SyncCommand.BookmarkAdd("target", 1_000.0), 1_000.0, LibraryLocalSource.Account(null))
        val state = LibraryPartitionState(pending = rejected + valid)
        assertNull(state.freeze())
        assertEquals(LibrarySyncLimits.operations, state.recovery.size)
        assertEquals(52, state.pending.size)
        assertNull(state.freeze())
        assertEquals(listOf(valid.operation), requireNotNull(state.freeze()).batch.operations)
        assertEquals(rejected.map { LibraryRecovery.Rejected(it) }, state.recovery)
    }

    @Test fun invalidPendingNoteRetainsItsOriginalWithoutBlockingTheNextChange() {
        val invalid = LibraryLocalChange(SyncCommand.NotePut("target", "界".repeat(8_001), 1_000.0, 1_000.0), 1_000.0, LibraryLocalSource.Account(null))
        val next = LibraryLocalChange(SyncCommand.BookmarkAdd("target", 1_000.0), 1_000.0, LibraryLocalSource.Account(null))
        val state = LibraryPartitionState(pending = listOf(invalid, next))
        val frame = requireNotNull(state.freeze())
        assertEquals(listOf(next.operation), frame.batch.operations)
        assertEquals(listOf(LibraryRecovery.Rejected(invalid)), state.recovery)
        assertTrue(state.pending.isEmpty())
    }

    @Test fun actualFacadeRejectsOversizedNoteAndExplicitRemoveNeverAddsAnAbsentBookmark() = runBlocking {
        isolated { store, _, _ ->
            val fixture = AndroidLibraryFacadeFixture(store)
            try {
                fixture.start()
                val captured = withContext(Dispatchers.Main) { fixture.model.actionScope }
                val saved = withContext(Dispatchers.Main) { fixture.model.saveNote(fixture.reference, "界".repeat(8_001)) }.await()
                assertFalse(saved)
                withContext(Dispatchers.Main) {
                    assertTrue(fixture.model.lastWriteFailed.value)
                    assertTrue(fixture.model.notes.value.isEmpty())
                }
                withContext(Dispatchers.Main) { fixture.model.removeBookmark(fixture.reference, captured) }.await()
                withContext(Dispatchers.Main) {
                    assertFalse(fixture.model.isBookmarked(fixture.reference.hadithId))
                    fixture.session.value = null; fixture.sync.deactivate(); fixture.model.refresh()
                }
                assertFalse(withContext(Dispatchers.Main) { fixture.model.removeBookmark(fixture.reference, captured) }.await())
                assertTrue(store.snapshots().bookmarks.isEmpty())
            } finally { fixture.stop() }
        }
    }

    @Test fun signInCleanupPreservesChangesMadeAfterTheSentSnapshot() = runBlocking {
        isolated { store, _, _ ->
            val id = "jn7fxd3z54153q9j13kmhgzkv18df2zd"
            val owner = LibrarySyncOwner("owner-a", "subject-a")
            val session = LibrarySyncSession("session-a", owner.subject)
            val current = MutableStateFlow<LibrarySyncSession?>(session)
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
            note(store, "Sent note")
            store.saveProgress(GuestReadingProgressDraft("bukhari", "Bukhari", id, volumeId = "1", hadithNumber = "1", updatedAt = 1_000.0))
            val batches = mutableListOf<SyncBatch>()
            val transport = object : LibrarySyncTransport {
                override val namespace = "fixture"
                override suspend fun open() = SyncBinding(owner.key, owner.subject, "local-fixture", Double.MAX_VALUE)
                override suspend fun acknowledge(capability: String, acknowledgement: SyncAcknowledgement) = SyncAckReply("owner-a", acknowledgement.clientKey, SyncCursor(acknowledgement.sequence))
                override suspend fun send(capability: String, frame: SyncFrame): SyncExchange {
                    batches.add(frame.batch)
                    if (batches.size == 1) {
                        assertTrue(store.snapshots().notes.isEmpty())
                        note(store, "New local edit during merge")
                        store.saveProgress(GuestReadingProgressDraft("bukhari", "Bukhari", id, volumeId = "1", hadithNumber = "2", updatedAt = 2_000.0))
                    }
                    return accepted(frame, SyncReply(owner.key, frame.batch.id, frame.batch.operations.map { SyncReceipt(it.id, it.revision, SyncOutcome.Preserved) }))
                }
            }
            val sync = LibrarySync(store, transport, scope, { current.value })
            try {
                sync.activate(session)
                assertEquals(listOf("Sent note", "New local edit during merge"), batches.flatMap { it.operations }.mapNotNull { (it.command as? SyncCommand.NotePut)?.content })
                assertEquals(listOf("1", "2"), batches.flatMap { it.operations }.mapNotNull { (it.command as? SyncCommand.PositionPut)?.position?.anchor?.providerHadithId })
                assertTrue(store.syncPartition(owner)!!.pending.isEmpty())
                assertNull(store.syncPartition(owner)!!.frozen)
            } finally { withContext(Dispatchers.Main) { sync.deactivate() }; scope.cancel() }
        }
    }

    @Test fun frozenClaimSurvivesReopenWithoutClearingOtherOwnerOrNewEdits() = runBlocking {
        isolated { store, reopen, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a")
            note(store, "Durable claimed note")
            store.claimGuestForSync(owner)
            val batch = store.freezeSyncFrame(owner)!!
            note(store, "Unclaimed later guest note")
            val reopened = reopen()
            assertEquals(batch, reopened.freezeSyncFrame(owner))
            val reply = SyncReply(owner.key, batch.batch.id, batch.batch.operations.map { SyncReceipt(it.id, it.revision, SyncOutcome.Preserved) })
            try { reopened.settleFixture(reply, batch, LibrarySyncOwner("owner-b", "subject-b")); fail("Wrong owner accepted") }
            catch (_: LibrarySyncFailure.OwnerMismatch) { }
            reopened.settleFixture(reply, batch, owner)
            assertEquals("Unclaimed later guest note", reopened.snapshots().notes.single().content)
            assertNull(reopened.syncPartition(owner)!!.frozen)
        }
    }

    @Test fun partialFolderReceiptRetainsOriginalRestoreIntent() = runBlocking {
        isolated { store, _, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a")
            store.claimGuestForSync(owner)
            val change = LibraryLocalChange(SyncCommand.FolderRestore("deleted-folder", "Fixture", listOf("restored", "changed", "missing")), 1_000.0, LibraryLocalSource.Account(null))
            store.enqueueSyncChange(change, owner)
            val batch = store.freezeSyncFrame(owner)!!
            val outcome = SyncOutcome.FolderRestored("folder", listOf("restored"), listOf("changed"), listOf("missing"))
            store.settleFixture(SyncReply(owner.key, batch.batch.id, listOf(SyncReceipt(change.operation.id, change.operation.revision, outcome))), batch, owner)
            assertEquals(listOf(LibraryRecovery.Server(change, outcome)), store.syncPartition(owner)!!.recovery)
            assertNull(store.syncPartition(owner)!!.frozen)
        }
    }

    @Test fun verifiedSubjectMismatchLeavesGuestDataUnclaimed() = runBlocking {
        isolated { store, _, _ ->
            note(store, "Guest fixture")
            val session = LibrarySyncSession("session-a", "subject-a")
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
            val transport = object : LibrarySyncTransport {
                override val namespace = "fixture"
                override suspend fun open() = SyncBinding("owner-b", "subject-b", "fixture", Double.MAX_VALUE)
                override suspend fun acknowledge(capability: String, acknowledgement: SyncAcknowledgement) = SyncAckReply("owner-a", acknowledgement.clientKey, SyncCursor(acknowledgement.sequence))
                override suspend fun send(capability: String, frame: SyncFrame): SyncExchange = error("Mismatched account must never send")
            }
            val sync = LibrarySync(store, transport, scope, { session })
            try {
                sync.activate(session)
                assertEquals(LibrarySync.Status.Failed, sync.status.value)
                assertNull(sync.owner.value)
                assertEquals("Guest fixture", store.snapshots().notes.single().content)
                assertNull(store.syncPartition(LibrarySyncOwner("owner-b", "subject-b")))
            } finally { withContext(Dispatchers.Main) { sync.deactivate() }; scope.cancel() }
        }
    }

    @Test fun capturedWritesCannotFollowAccountSwitchOrRecreateErasedPartition() = runBlocking {
        isolated { store, _, _ ->
            val current = MutableStateFlow(LibrarySyncSession("session-a", "subject-a"))
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
            val transport = object : LibrarySyncTransport {
                override val namespace = "fixture"
                override suspend fun open() = SyncBinding(current.value.subject, current.value.subject, "fixture", Double.MAX_VALUE)
                override suspend fun acknowledge(capability: String, acknowledgement: SyncAcknowledgement) = SyncAckReply("owner-a", acknowledgement.clientKey, SyncCursor(acknowledgement.sequence))
                override suspend fun send(capability: String, frame: SyncFrame): SyncExchange = error("Rejected write must never send")
            }
            val sync = LibrarySync(store, transport, scope, { current.value })
            try {
                sync.activate(current.value)
                val oldContext = withContext(Dispatchers.Main) { sync.captureWriteContext() }
                withContext(Dispatchers.Main) { sync.deactivate() }
                current.value = LibrarySyncSession("session-b", "subject-b")
                sync.activate(current.value)
                val change = LibraryLocalChange(SyncCommand.NotePut("target", "Account A fixture", 1_000.0, 1_000.0), 1_000.0, LibraryLocalSource.Account(null))
                try { sync.enqueue(change, oldContext); fail("Old account intent accepted") } catch (_: LibrarySyncFailure.SessionChanged) { }
                val ownerB = sync.owner.value!!
                assertTrue(store.syncPartition(ownerB)!!.pending.isEmpty())
                val currentContext = withContext(Dispatchers.Main) { sync.captureWriteContext() }
                store.resetSyncPartitionForTesting(ownerB)
                try { sync.enqueue(change, currentContext); fail("Erased partition recreated") } catch (_: LibrarySyncFailure.SessionChanged) { }
                assertNull(store.syncPartition(ownerB))
            } finally { withContext(Dispatchers.Main) { sync.deactivate() }; scope.cancel() }
        }
    }

    @Test fun corruptStoreIsRetainedAndReportedThroughExistingSavedErrorState() = runBlocking {
        isolated { store, _, directory ->
            val file = File(directory, "guest_store.json")
            val damaged = "{interrupted-private-fixture"
            file.writeText(damaged)
            try { store.snapshots(); fail("Corrupt file reported as empty") }
            catch (_: LibrarySyncFailure.StoreUnavailable) { }
            try { note(store, "Must not replace damaged data"); fail("Corrupt file overwritten") }
            catch (_: LibrarySyncFailure.StoreUnavailable) { }
            assertEquals(damaged, file.readText())
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
            val library = UserLibraryModel(store, scope)
            try {
                withContext(Dispatchers.Main) { library.refresh() }
                withTimeout(2_000) { library.loadState.first { it == UserLibraryModel.LoadState.Failed } }
                assertEquals(damaged, file.readText())
                val writeLibrary = UserLibraryModel(store, scope)
                withContext(Dispatchers.Main) {
                    writeLibrary.saveNote(HadithRef("target", "bukhari", "Bukhari", "1", "1", "", null, "Fixture"), "Must not overwrite")
                }
                withTimeout(2_000) { writeLibrary.loadState.first { it == UserLibraryModel.LoadState.Failed } }
                assertEquals(damaged, file.readText())
            } finally { scope.cancel() }
        }
    }

    @Test fun legacyFileWithoutPartitionsMigratesAndKeepsExactPrivateText() = runBlocking {
        isolated { store, reopen, directory ->
            File(directory, "guest_store.json").writeText("""{"notes":[{"hadithId":"target","content":"Legacy private fixture","createdAt":1000.0,"updatedAt":2000.0}]}""")
            assertEquals("Legacy private fixture", store.snapshots().notes.single().content)
            val owner = LibrarySyncOwner("owner-a", "subject-a")
            store.claimGuestForSync(owner)
            val batch = store.freezeSyncFrame(owner)!!
            assertEquals("Legacy private fixture", (batch.batch.operations.single().command as SyncCommand.NotePut).content)
            assertEquals(batch, reopen().freezeSyncFrame(owner))
            assertTrue(reopen().snapshots().notes.isEmpty())
        }
    }

    @Test fun durableAcknowledgementSurvivesReopenAndFencesNewFreezeAndLateAck() = runBlocking {
        isolated { store, reopen, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a")
            note(store, "First fixture")
            store.claimGuestForSync(owner)
            val frame = store.freezeSyncFrame(owner)!!
            store.settleFixture(SyncReply(owner.key, frame.batch.id, frame.batch.operations.map { SyncReceipt(it.id, it.revision, SyncOutcome.Preserved) }), frame, owner)
            val acknowledgement = store.syncPartition(owner)!!.acknowledgement!!
            store.enqueueSyncChange(LibraryLocalChange(SyncCommand.NoteRemove("target"), 2_000.0, LibraryLocalSource.Account(null)), owner)
            try { store.freezeSyncFrame(owner); fail("New batch froze before acknowledgement") } catch (_: LibrarySyncFailure.InvalidReceipt) { }
            val reopened = reopen()
            assertEquals(acknowledgement, reopened.syncPartition(owner)!!.acknowledgement)
            val reply = SyncAckReply(owner.key, frame.clientKey, SyncCursor(1.0))
            reopened.settleSyncAcknowledgement(reply, acknowledgement, owner)
            val next = reopened.freezeSyncFrame(owner)!!
            assertEquals(2.0, next.sequence, 0.0)
            try { reopened.settleSyncAcknowledgement(reply, acknowledgement, owner); fail("Late ack changed current batch") } catch (_: LibrarySyncFailure.InvalidReceipt) { }
            assertEquals(next, reopened.freezeSyncFrame(owner))
        }
    }

    @Test fun closedBackupFrameArchivesOriginalAndKeepsNeverSentPendingIntent() = runBlocking {
        isolated { store, _, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a")
            note(store, "Unknown old fixture")
            store.claimGuestForSync(owner)
            val frame = store.freezeSyncFrame(owner)!!
            val pending = LibraryLocalChange(SyncCommand.NotePut("target", "Never sent fixture", 2_000.0, 2_000.0), 2_000.0, LibraryLocalSource.Account(null))
            store.enqueueSyncChange(pending, owner)
            val exchange = SyncExchange.Reconcile(owner.key, frame.clientKey, frame.sequence, frame.batch.id, SyncCursor(5.0))
            store.settleSyncExchange(exchange, frame, owner)
            val state = store.syncPartition(owner)!!
            val original = (state.recovery.single() as LibraryRecovery.Historical).change
            assertEquals("Unknown old fixture", (original.source as LibraryLocalSource.Note).value.content)
            assertEquals(listOf(pending), state.pending)
            val next = store.freezeSyncFrame(owner)!!
            assertEquals(6.0, next.sequence, 0.0)
            assertEquals(listOf(pending.operation), next.batch.operations)
        }
    }

    @Test fun occupiedBackupFrameChecksNestedOwnerAndPersistsOtherReceiptProof() = runBlocking {
        isolated { store, _, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a")
            note(store, "Available backup fixture")
            store.claimGuestForSync(owner)
            val frame = store.freezeSyncFrame(owner)!!
            fun exchange(replyOwner: String) = SyncExchange.Reconcile(owner.key, frame.clientKey, frame.sequence, frame.batch.id,
                SyncCursor(0.0, SyncOutstanding.Committed(SyncCommitted(frame.clientKey, 1.0, "server-proof", SyncRevision(1.0, 1.0), SyncReply(replyOwner, "other-batch", listOf(SyncReceipt("other-intent", "r1", SyncOutcome.Preserved)))))))
            try { store.settleSyncExchange(exchange("owner-b"), frame, owner); fail("Nested wrong owner accepted") } catch (_: LibrarySyncFailure.OwnerMismatch) { }
            assertEquals(frame, store.freezeSyncFrame(owner))
            store.settleSyncExchange(exchange(owner.key), frame, owner)
            val state = store.syncPartition(owner)!!
            assertNull(state.frozen)
            assertEquals(1, state.recovery.size)
            assertEquals("other-batch", state.acknowledgement!!.batchId)
            assertEquals("server-proof", state.acknowledgement!!.digest)
            try { store.freezeSyncFrame(owner); fail("Unacknowledged server proof skipped") } catch (_: LibrarySyncFailure.InvalidReceipt) { }
        }
    }

    @Test fun frozenFrameIncludesOnlyOneFolderFanoutAndKeepsTheRestPending() = runBlocking {
        isolated { store, _, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a")
            store.claimGuestForSync(owner)
            for (index in 1..2) store.enqueueSyncChange(LibraryLocalChange(SyncCommand.FolderDelete(SyncFolderReference.Local("folder-$index")), 1_000.0, LibraryLocalSource.Account(null)), owner)
            val frame = store.freezeSyncFrame(owner)!!
            assertEquals(1, frame.batch.operations.size)
            assertEquals(1, store.syncPartition(owner)!!.pending.size)
        }
    }

    @Test fun actualLibraryFacadePersistsOfflineIntentsAndRestoresProjectionAfterReopen() = runBlocking {
        isolated { store, reopen, _ ->
            val fixture = AndroidLibraryFacadeFixture(store)
            try {
                fixture.start()
                fixture.saved.emit(SyncSavedSnapshot("owner-a", 0.0, emptyList(), emptyList()))
                waitForLibrary { fixture.model.loadState.value == UserLibraryModel.LoadState.Ready }
                val ref = fixture.reference
                withContext(Dispatchers.Main) {
                    assertTrue(fixture.model.toggleBookmark(ref).await())
                    assertTrue(fixture.model.toggleFavorite(ref).await())
                    assertTrue(fixture.model.saveNote(ref, "Offline private fixture").await())
                    fixture.model.createFolder("Private folder", fixture.model.actionScope)
                }
                waitForLibrary { fixture.model.folders.value.isNotEmpty() }
                val folder = fixture.model.folders.value.first()
                val position = ReadingPosition.legacy("bukhari", "1", "1", System.currentTimeMillis().toDouble())!!
                withContext(Dispatchers.Main) { fixture.model.assignFolder(ref.hadithId, folder.id, fixture.model.actionScope); fixture.model.saveProgress(position, ref) }
                waitForLibrary { fixture.model.savedItems.value.firstOrNull()?.folderId == folder.id && fixture.model.continueReading?.position != null }
                withContext(Dispatchers.Main) {
                    assertTrue(fixture.model.toggleBookmark(ref).await())
                    fixture.model.restoreBookmark(ref, System.currentTimeMillis().toDouble())
                }
                waitForLibrary { fixture.model.isBookmarked(ref.hadithId) }
                val note = fixture.model.notes.value.first()
                withContext(Dispatchers.Main) {
                    assertTrue(fixture.model.deleteNote(ref, fixture.model.actionScope).await())
                    fixture.model.restoreNote(ref, "Offline private fixture", note.createdAt, note.sortDate)
                }
                waitForLibrary { fixture.model.notes.value.firstOrNull()?.noteContent == "Offline private fixture" }
                withContext(Dispatchers.Main) { fixture.model.deleteFolder(folder, "Removed fixture", fixture.model.actionScope) }
                waitForLibrary { fixture.model.undo.notice.value != null }
                withContext(Dispatchers.Main) { fixture.model.undo.undo() }
                waitForLibrary { fixture.model.folders.value.firstOrNull()?.name == "Private folder" && fixture.model.savedItems.value.firstOrNull()?.folderId == fixture.model.folders.value.firstOrNull()?.id }
                assertTrue(fixture.model.isFavorite(ref.hadithId))
                assertEquals("1", fixture.model.continueReading?.position?.anchor?.providerHadithId)
                waitForLibrary { fixture.server.frames.isNotEmpty() }
                val owner = fixture.sync.owner.value!!
                assertTrue(store.syncPartition(owner)!!.pending.isNotEmpty())
                assertNotNull(store.syncPartition(owner)!!.frozen)
                fixture.stop()
                val reopened = AndroidLibraryFacadeFixture(reopen())
                try {
                    reopened.start()
                    waitForLibrary { reopened.model.notes.value.firstOrNull()?.noteContent == "Offline private fixture" }
                    assertTrue(reopened.model.isBookmarked(ref.hadithId))
                    assertTrue(reopened.model.isFavorite(ref.hadithId))
                    assertEquals(reopened.model.folders.value.first().id, reopened.model.savedItems.value.first().folderId)
                    assertEquals("1", reopened.model.continueReading?.position?.anchor?.providerHadithId)
                } finally { reopened.stop() }
            } finally { fixture.stop() }
        }
    }

    @Test fun actualLibraryFacadeKeepsAcceptedNoteUntilOwnedQueryRevisionCatchesUp() = runBlocking {
        isolated { store, _, _ ->
            val fixture = AndroidLibraryFacadeFixture(store)
            try {
                fixture.start()
                fixture.saved.emit(SyncSavedSnapshot("owner-a", 0.0, emptyList(), emptyList()))
                waitForLibrary { fixture.model.loadState.value == UserLibraryModel.LoadState.Ready }
                withContext(Dispatchers.Main) { assertTrue(fixture.model.saveNote(fixture.reference, "Accepted private fixture").await()) }
                waitForLibrary { fixture.server.frames.isNotEmpty() }
                withContext(Dispatchers.Main) { fixture.server.failSends = false }
                fixture.sync.activate(fixture.session.value!!)
                val owner = fixture.sync.owner.value!!
                assertTrue(store.syncPartition(owner)!!.pending.isEmpty())
                assertNull(store.syncPartition(owner)!!.frozen)
                assertNull(store.syncPartition(owner)!!.acknowledgement)
                assertEquals("Accepted private fixture", fixture.model.notes.value.first().noteContent)
                assertEquals(1, store.syncPartition(owner)!!.confirmed.size)
                fixture.saved.emit(SyncSavedSnapshot("owner-a", 0.0, emptyList(), emptyList()))
                fixture.positions.emit(SyncPositionsSnapshot("owner-a", 50.0, emptyList()))
                withTimeout(3_000) { while (store.syncPartition(owner)!!.positionsSnapshot?.version != 50.0) delay(10) }
                assertEquals("Accepted private fixture", fixture.model.notes.value.first().noteContent)
                assertEquals(1, store.syncPartition(owner)!!.confirmed.size)
                fixture.saved.emit(fixture.snapshot(2.0, "Later cloud fixture"))
                waitForLibrary { fixture.model.notes.value.firstOrNull()?.noteContent == "Later cloud fixture" }
                assertTrue(store.syncPartition(owner)!!.confirmed.isEmpty())
                fixture.saved.emit(fixture.snapshot(1.0, "Older delayed fixture"))
                fixture.positions.emit(SyncPositionsSnapshot("owner-a", 99.0, emptyList()))
                withTimeout(3_000) { while (store.syncPartition(owner)!!.positionsSnapshot?.version != 99.0) delay(10) }
                assertEquals("Later cloud fixture", fixture.model.notes.value.first().noteContent)
            } finally { fixture.stop() }
        }
    }

    @Test fun actualLibraryFacadeRejectsLateAccountReadsAndUndoAfterSwitchAndSignOut() = runBlocking {
        isolated { store, _, _ ->
            val fixture = AndroidLibraryFacadeFixture(store)
            try {
                fixture.start()
                fixture.saved.emit(fixture.snapshot(0.0, "Account A fixture"))
                waitForLibrary { fixture.model.notes.value.firstOrNull()?.noteContent == "Account A fixture" }
                val scopeA = fixture.model.actionScope
                withContext(Dispatchers.Main) {
                    assertTrue(fixture.model.toggleBookmark(fixture.reference).await())
                    assertTrue(fixture.model.toggleBookmark(fixture.reference).await())
                    assertTrue(fixture.model.deleteNote(fixture.reference, fixture.model.actionScope).await())
                    fixture.saved.tryEmit(fixture.snapshot(1.0, "Queued late A fixture"))
                    fixture.session.value = LibrarySyncSession("session-b", "subject-b")
                    fixture.sync.deactivate(); fixture.model.refresh()
                }
                fixture.sync.activate(fixture.session.value!!)
                fixture.saved.emit(fixture.snapshot(20.0, "Wrong owner fixture"))
                fixture.saved.emit(SyncSavedSnapshot("owner-b", 0.0, emptyList(), emptyList()))
                waitForLibrary { fixture.model.loadState.value == UserLibraryModel.LoadState.Ready }
                withContext(Dispatchers.Main) {
                    assertFalse(fixture.model.isActionCurrent(scopeA))
                    fixture.model.restoreBookmark(fixture.reference, System.currentTimeMillis().toDouble())
                    fixture.model.restoreNote(fixture.reference, "A undo fixture", 1_000.0, 2_000.0)
                }
                val ownerB = fixture.sync.owner.value!!
                assertTrue(fixture.model.savedItems.value.isEmpty())
                assertTrue(store.syncPartition(ownerB)!!.pending.isEmpty())
                assertNull(store.syncPartition(ownerB)!!.frozen)
                assertEquals("owner-b", store.syncPartition(ownerB)!!.savedSnapshot!!.ownerKey)
                withContext(Dispatchers.Main) {
                    fixture.session.value = null; fixture.sync.deactivate(); fixture.model.refresh()
                    fixture.model.restoreBookmark(fixture.reference, 1_000.0)
                    fixture.model.restoreNote(fixture.reference, "A undo fixture", 1_000.0, 2_000.0)
                }
                assertTrue(store.snapshots().bookmarks.isEmpty())
                assertTrue(store.snapshots().notes.isEmpty())
            } finally { fixture.stop() }
        }
    }

    @Test fun productionWireAdapterUsesDoubleNumbersAndPreservesPrivateFixtureText() {
        val position = ReadingPosition.legacy("bukhari", "1", "1", 1_000.0)!!
        val frame = SyncFrame("client-fixture", 1.0, SyncBatch("wire-fixture", listOf(SyncOperation("position", "r1", 1_000.0, SyncCommand.PositionPut(position)))))
        val text = "Private fixture: қазақша \"quoted\"\nالعربية"
        val noteFrame = frame.copy(batch = SyncBatch("note-wire-fixture", listOf(SyncOperation("note", "r1", 1_000.0, SyncCommand.NotePut("target", text, 1_000.0, 1_000.0)))))
        val noteArgument = noteFrame.toConvexArgument()
        assertTrue(noteArgument.toString().contains(text))
        val argument = frame.toConvexArgument()
        assertTrue(argument is Map<*, *>)
        if (argument !is Map<*, *>) return
        assertTrue(argument["sequence"] is Double)
        val batch = argument["batch"]
        assertTrue(batch is Map<*, *>)
        if (batch !is Map<*, *>) return
        val operations = batch["operations"]
        assertTrue(operations is List<*>)
        if (operations !is List<*>) return
        val operation = operations.first()
        assertTrue(operation is Map<*, *>)
        if (operation !is Map<*, *>) return
        val command = operation["command"]
        assertTrue(command is Map<*, *>)
        if (command !is Map<*, *>) return
        assertEquals("position_put", command["kind"])
        val encoded = command["position"]
        assertTrue(encoded is Map<*, *>)
        if (encoded !is Map<*, *>) return
        assertTrue(encoded["schemaVersion"] is Double)
        assertFalse(encoded.containsKey("chapterId"))
    }

    private suspend fun waitForLibrary(condition: () -> Boolean) {
        withTimeout(3_000) { while (!withContext(Dispatchers.Main) { condition() }) delay(10) }
    }

    @Test fun invalidReceiptsKeepFrozenDataAndConflictsKeepRecoverableContent() = runBlocking {
        isolated { store, _, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a")
            note(store, "Recoverable fixture")
            store.claimGuestForSync(owner)
            val batch = store.freezeSyncFrame(owner)!!
            try { store.settleFixture(SyncReply(owner.key, batch.batch.id, emptyList()), batch, owner); fail("Incomplete receipt accepted") }
            catch (_: LibrarySyncFailure.InvalidReceipt) { }
            assertEquals(batch, store.freezeSyncFrame(owner))
            val operation = batch.batch.operations.single()
            store.settleFixture(SyncReply(owner.key, batch.batch.id, listOf(SyncReceipt(operation.id, operation.revision, SyncOutcome.Superseded(SyncOutcomeSupersededReason.NEWER_CLOUD)))), batch, owner)
            val recovered = store.syncPartition(owner)!!.recovery.single() as LibraryRecovery.Server
            assertEquals("Recoverable fixture", (recovered.change.source as LibraryLocalSource.Note).value.content)
        }
    }
}

private class AndroidLibraryFixtureServer {
    val frames = mutableListOf<SyncFrame>()
    var failSends = true
    var nextOutcome: SyncOutcome? = null
    var failAcknowledgements = false
    var acknowledgements = 0
    val revisions = mutableMapOf<String, SyncRevision>()
    fun send(capability: String, frame: SyncFrame): SyncExchange {
        frames.add(frame)
        if (failSends) throw java.io.IOException("Fixture offline")
        val owner = capability.removePrefix("fixture:")
        val old = revisions[owner] ?: SyncRevision(0.0, 0.0)
        val saved = frame.batch.operations.any { !it.command.isPositionChange }
        val position = frame.batch.operations.any { it.command.isPositionChange }
        val revision = SyncRevision(old.saved + if (saved) 1 else 0, old.position + if (position) 1 else 0)
        revisions[owner] = revision
        val outcome = nextOutcome ?: SyncOutcome.Preserved; nextOutcome = null
        return SyncExchange.Accepted(SyncCommitted(frame.clientKey, frame.sequence, "fixture-proof", revision,
            SyncReply(owner, frame.batch.id, frame.batch.operations.map { SyncReceipt(it.id, it.revision, outcome) })))
    }
}

private class AndroidLibraryFacadeFixture(val store: GuestDataStore) {
    val session = MutableStateFlow<LibrarySyncSession?>(LibrarySyncSession("session-a", "subject-a"))
    val server = AndroidLibraryFixtureServer()
    val saved = kotlinx.coroutines.flow.MutableSharedFlow<SyncSavedSnapshot>(replay = 1)
    val positions = kotlinx.coroutines.flow.MutableSharedFlow<SyncPositionsSnapshot>(replay = 1)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    val sync: LibrarySync
    val model: UserLibraryModel
    val reference = HadithRef("jn7fxd3z54153q9j13kmhgzkv18df2zd", "bukhari", "Bukhari", "1", "1", "نص", "Fixture", "Bukhari 1")
    init {
        val transport = object : LibrarySyncTransport {
            override val namespace = "fixture"
            override suspend fun open(): SyncBinding {
                val current = session.value ?: throw LibrarySyncFailure.SessionChanged
                val owner = if (current.subject == "subject-a") "owner-a" else "owner-b"
                return SyncBinding(owner, current.subject, "fixture:$owner", System.currentTimeMillis() + 900_000.0)
            }
            override suspend fun send(capability: String, frame: SyncFrame) = server.send(capability, frame)
            override suspend fun acknowledge(capability: String, acknowledgement: SyncAcknowledgement): SyncAckReply {
                server.acknowledgements++
                if (server.failAcknowledgements) throw java.io.IOException("Fixture ACK offline")
                return SyncAckReply(capability.removePrefix("fixture:"), acknowledgement.clientKey, SyncCursor(acknowledgement.sequence))
            }
        }
        sync = LibrarySync(store, transport, scope, { session.value })
        val reads = object : LibraryReadTransport {
            override fun savedSnapshot() = saved
            override fun positionsSnapshot() = positions
        }
        model = UserLibraryModel(reads, store, scope, sync) { session.value }
        sync.onOwnerChange = { model.refresh() }
        sync.onPartitionChange = model::partitionChanged
    }
    suspend fun start() = withContext(Dispatchers.Main) { session.value?.let { sync.activate(it) }; model.refresh() }
    suspend fun stop() = withContext(Dispatchers.Main) { sync.deactivate(); session.value = null; model.refresh(); scope.cancel() }
    fun snapshot(version: Double, note: String) = SyncSavedSnapshot("owner-a", version, emptyList(), listOf(SyncSavedItem(reference.hadithId, 1_000.0, 2_000.0,
        noteContent = note, noteCreatedAt = 1_000.0, noteUpdatedAt = 2_000.0, hadith = SyncHadithSummary(reference.hadithId, "1", "bukhari", "Bukhari", "1", "نص", "Fixture", "Bukhari 1"))))
}

private class AndroidSavedReadFixture(val store: GuestDataStore) {
    val session = MutableStateFlow<LibrarySyncSession?>(LibrarySyncSession("session-a", "subject-a"))
    var now = 1_000.0
    var bindingTTL = 900_000.0
    var opens = 0
    val heads = kotlinx.coroutines.flow.MutableSharedFlow<SavedReadHead>()
    val referenceReply = Json.decodeFromString<SavedReferenceReply>(LibrarySavedReadsParityVector.referenceJSON)
    val textReply = Json.decodeFromString<SavedTextReply>(LibrarySavedReadsParityVector.textJSON)
    val target = "10002;hadiths"
    var headStarts = 0
    var headFetch: ((String) -> kotlinx.coroutines.flow.Flow<SavedReadHead>)? = null
    var referenceFetch: (suspend (String, String) -> SavedReferenceReply)? = null
    var textFetch: (suspend (String, String) -> SavedTextReply)? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    val sync = LibrarySync(store, object : LibrarySyncTransport {
        override val namespace = "fixture"
        override suspend fun open(): SyncBinding {
            val current = session.value ?: throw LibrarySyncFailure.SessionChanged; opens++
            return SyncBinding(if (current.subject == "subject-a") "10000;users" else "owner-b", current.subject, "fixture-read-$opens", now + bindingTTL)
        }
        override suspend fun send(capability: String, frame: SyncFrame): SyncExchange = throw LibrarySyncFailure.InvalidChange
        override suspend fun acknowledge(capability: String, acknowledgement: SyncAcknowledgement): SyncAckReply = throw LibrarySyncFailure.InvalidChange
        override fun savedHeads(capability: String): kotlinx.coroutines.flow.Flow<SavedReadHead> { headStarts++; return headFetch?.invoke(capability) ?: heads }
        override suspend fun savedReference(capability: String, hadithID: String) = referenceFetch?.invoke(capability, hadithID) ?: referenceReply
        override suspend fun savedText(capability: String, hadithID: String) = textFetch?.invoke(capability, hadithID) ?: textReply
    }, scope, { session.value }, { now })
    suspend fun start() { session.value?.let { sync.activate(it) } }
    fun stop() { sync.deactivate(); scope.cancel() }
}
