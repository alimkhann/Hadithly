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
    private fun accepted(frame: SyncFrame, reply: SyncReply) = SyncExchange.Accepted(SyncCommitted(frame.clientKey, frame.sequence, "fixture-digest", SyncRevision(frame.sequence, frame.sequence), reply))
    private suspend fun GuestDataStore.settleFixture(reply: SyncReply, frame: SyncFrame, owner: LibrarySyncOwner) = settleSyncExchange(accepted(frame, reply), frame, owner)

    private suspend fun isolated(block: suspend (GuestDataStore, () -> GuestDataStore, File) -> Unit) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.cacheDir, "guest-merge-race-${System.nanoTime()}").apply { mkdirs() }
        val wrapper = object : ContextWrapper(context) { override fun getFilesDir(): File = directory }
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
                SyncCursor(0.0, SyncCommitted(frame.clientKey, 1.0, "server-proof", SyncRevision(1.0, 1.0), SyncReply(replyOwner, "other-batch", listOf(SyncReceipt("other-intent", "r1", SyncOutcome.Preserved))))))
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
        return SyncExchange.Accepted(SyncCommitted(frame.clientKey, frame.sequence, "fixture-proof", revision,
            SyncReply(owner, frame.batch.id, frame.batch.operations.map { SyncReceipt(it.id, it.revision, SyncOutcome.Preserved) })))
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
            override suspend fun acknowledge(capability: String, acknowledgement: SyncAcknowledgement) = SyncAckReply(capability.removePrefix("fixture:"), acknowledgement.clientKey, SyncCursor(acknowledgement.sequence))
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
