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

class GuestMergeRaceTest {
    private fun accepted(frame: SyncFrame, reply: SyncReply) = SyncExchange.Accepted(SyncCommitted(frame.clientKey, frame.sequence, "fixture-digest", reply))
    private suspend fun GuestDataStore.settleFixture(reply: SyncReply, frame: SyncFrame, owner: LibrarySyncOwner) = settleSyncExchange(accepted(frame, reply), frame, owner)

    private suspend fun isolated(block: suspend (GuestDataStore, () -> GuestDataStore, File) -> Unit) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.cacheDir, "guest-merge-race-${System.nanoTime()}").apply { mkdirs() }
        val wrapper = object : ContextWrapper(context) { override fun getFilesDir(): File = directory }
        try { block(GuestDataStore(wrapper), { GuestDataStore(wrapper) }, directory) }
        finally { directory.deleteRecursively() }
    }
    private suspend fun note(store: GuestDataStore, content: String) = store.saveNote("jn7fxd3z54153q9j13kmhgzkv18df2zd", content, null, null, null, null, null, "", null)

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
                store.eraseSyncPartition(ownerB)
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
            val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as HadithlyApplication
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
            val library = UserLibraryModel(app.repository, store, scope) { false }
            try {
                withContext(Dispatchers.Main) { library.refresh() }
                withTimeout(2_000) { library.loadState.first { it == UserLibraryModel.LoadState.Failed } }
                assertEquals(damaged, file.readText())
                val writeLibrary = UserLibraryModel(app.repository, store, scope) { false }
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
                SyncCursor(0.0, SyncCommitted(frame.clientKey, 1.0, "server-proof", SyncReply(replyOwner, "other-batch", listOf(SyncReceipt("other-intent", "r1", SyncOutcome.Preserved))))))
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
