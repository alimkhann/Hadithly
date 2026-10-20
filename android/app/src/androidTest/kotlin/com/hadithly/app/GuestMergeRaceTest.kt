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
                    assertEquals(2, db.version)
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
        for (mode in listOf("mutation", "cancel", "switch", "erase")) isolated { store, _, directory ->
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
                            "cancel" -> task.cancel()
                            "switch" -> { fixture.session.value = LibrarySyncSession("session-b", "subject-b"); fixture.sync.deactivate() }
                            "erase" -> { store.beginDeletion(owner.subject, owner.namespace); store.markDeletionBackendComplete(owner.subject, owner.namespace) }
                            else -> collectExportFacts(taggedOutcomeProof(owner, 1, "insert-during-export"), owner, 1, store)
                        }
                        try { task.await(); fail("Changed/canceled export was published") } catch (_: Exception) { }
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
    @Test fun outcomeExportArtifactCleanupAndEmptyFenceNeverRecreateDeletedMetadata() = runBlocking {
        isolated { store, reopen, _ ->
            val owner = LibrarySyncOwner("owner-a", "subject-a"); store.claimGuestForSync(owner)
            val empty = store.prepareOutcomeExport(owner) { true }; assertEquals(LibraryOutcomeExportVersion.Empty, empty.version)
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
        state.settle(SyncExchange.Accepted(committed), frame, 2_000.0)
        assertTrue(LibraryProjection(state).folders.isEmpty())
        assertTrue(LibraryProjection(state).items.all { it.folderId == null })
        state.savedSnapshot = SyncSavedSnapshot("owner-a", 2.0, listOf(SyncFolderRow("destination", "Folder", 1.0)), listOf(item(first, "destination"), item(second, null)))
        val visible = LibraryProjection(state)
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
            val original = File(directory, "guest_store.json").readText()
            var checkpoint = LibraryOutcomeCheckpoint(); val requests = mutableListOf<Double>()
            for (index in 0 until 30) {
                checkpoint = store.collectOutcomeStep(proof, owner, { true }) { request -> requests.add(request.start); outcomePage(request, owner, count) }
                assertEquals(original, File(directory, "guest_store.json").readText())
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
            assertEquals(original, File(directory, "guest_store.json").readText())
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
            val file = File(directory, "guest_store.json"); val json = Json { ignoreUnknownKeys = true; encodeDefaults = true; explicitNulls = false }
            val state = json.decodeFromString<GuestStoreFile>(file.readText())
            file.writeText(json.encodeToString(state.copy(syncPartitions = state.syncPartitions.filterNot { it.ownerKey == owner.storageKey })))
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
            reconciled.settle(SyncExchange.Reconcile("owner-a", frame.clientKey, frame.sequence, frame.batch.id, cursor), frame, 2_000.0)
            assertEquals(LibraryPendingOutcome(committed, LibraryOutcomeOrigin.Historical), reconciled.collectingOutcome)
            assertEquals(original.frozen!!.changes.map(LibraryRecovery::Historical), reconciled.recovery); assertNull(reconciled.acknowledgement)
            try { reconciled.freeze(); fail("Froze past collection") } catch (_: LibrarySyncFailure.InvalidReceipt) { }
            val retired = copied(original)
            retired.settleRetirement(SyncAckReply("owner-a", frame.clientKey, cursor), frame)
            assertEquals(reconciled, retired)
            val different = frame.batch.copy(operations = listOf(operation.copy(command = SyncCommand.FolderDelete(SyncFolderReference.Server("folder-b")))))
            val pending = SyncPending(frame.clientKey, frame.sequence, frame.batch.id, committed.digest, different.intentDigest(), "manifest", "generation", 1_000.0)
            val polled = copied(original)
            polled.settle(SyncExchange.Pending("owner-a", pending), frame, 2_000.0)
            val previousRecovery = polled.recovery
            polled.settlePending(SyncExchange.Accepted(committed), pending, 2_000.0)
            assertEquals(previousRecovery, polled.recovery); assertEquals(1, polled.recovery.size)
            assertEquals(LibraryOutcomeOrigin.Historical, polled.collectingOutcome!!.origin); assertNull(polled.acknowledgement)
            val acknowledged = copied(original)
            acknowledged.settle(accepted(frame, SyncReply("owner-a", frame.batch.id, listOf(SyncReceipt(operation.id, operation.revision, SyncOutcome.Preserved)))), frame, 2_000.0)
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
        state.settle(accepted(frame, reply), frame, 2_000.0)
        assertEquals(frame.batch, state.frozen!!.batch); assertEquals(1.0, state.nextSequence, 0.0); assertNull(state.acknowledgement)
        assertEquals(LibraryOutcomeOrigin.Matched(frame.batch.intentDigest()), state.collectingOutcome!!.origin)
        try { state.freeze(); fail("Froze past collection") } catch (_: LibrarySyncFailure.InvalidReceipt) { }
        assertEquals(state, Json.decodeFromString<LibraryPartitionState>(Json.encodeToString(state)))
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
            assertTrue(directory.setWritable(false, false))
            try {
                try { store.settleCollectedOutcome(pending, owner, 2_000.0); fail("Failed AtomicFile write settled") } catch (_: java.io.IOException) { }
            } finally { assertTrue(directory.setWritable(true, true)) }
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
            if (mode == "historical") state.settle(SyncExchange.Reconcile(owner.key, frame.clientKey, frame.sequence, frame.batch.id, SyncCursor(0.0, SyncOutstanding.Committed(proof))), frame, 2_000.0)
            else state.settle(SyncExchange.Accepted(proof), frame, 2_000.0)
            val pending = state.collectingOutcome!!; val binding = LibraryOutcomeBinding(owner, proof)
            val checkpoint = if (mode == "detail" || mode == "proof") LibraryOutcomeCheckpoint(LibraryOutcomeCounts(restored = 50), LibraryOutcomeStatus.Unavailable(if (mode == "detail") SyncOutcomePageUnavailableReason.DETAIL_UNAVAILABLE else SyncOutcomePageUnavailableReason.PROOF_UNAVAILABLE))
                else LibraryOutcomeCheckpoint(binding.expected, LibraryOutcomeStatus.Complete)
            state.savedSnapshot = SyncSavedSnapshot(owner.key, 1.0, emptyList(), emptyList())
            val before = Json.encodeToString(state)
            assertEquals(if (mode == "proof") LibraryOutcomeSettlement.ProofUnavailable else LibraryOutcomeSettlement.AwaitingSaved, state.settleCollectedOutcome(pending, binding, checkpoint, 2_000.0))
            assertEquals(before, Json.encodeToString(state))
            state.savedSnapshot = SyncSavedSnapshot(owner.key, 3.0, emptyList(), emptyList())
            if (mode == "proof") {
                val blocked = Json.encodeToString(state)
                assertEquals(LibraryOutcomeSettlement.ProofUnavailable, state.settleCollectedOutcome(pending, binding, checkpoint, 2_000.0)); assertEquals(blocked, Json.encodeToString(state)); continue
            }
            val original = state.frozen?.changes?.single()
            if (mode == "delete") {
                val late = state.copy()
                assertEquals(LibraryOutcomeSettlement.Settled, late.settleCollectedOutcome(pending, binding, checkpoint, 7_000.0)); assertTrue(late.recent.isEmpty())
            }
            if (mode == "partial") {
                for (status in listOf(LibraryOutcomeStatus.Collecting, LibraryOutcomeStatus.Verifying(LibraryOutcomeCounts()))) {
                    val unfinished = state.copy(); val unfinishedBefore = Json.encodeToString(unfinished)
                    assertEquals(LibraryOutcomeSettlement.Collecting, unfinished.settleCollectedOutcome(pending, binding, LibraryOutcomeCheckpoint(binding.expected, status), 2_000.0)); assertEquals(unfinishedBefore, Json.encodeToString(unfinished))
                }
                val incomplete = state.copy(); val incompleteBefore = Json.encodeToString(incomplete)
                try { incomplete.settleCollectedOutcome(pending, binding, LibraryOutcomeCheckpoint(status = LibraryOutcomeStatus.Complete), 2_000.0); fail("Incomplete totals accepted") } catch (_: LibrarySyncFailure.InvalidReceipt) { }; assertEquals(incompleteBefore, Json.encodeToString(incomplete))
                val missing = state.copy(frozen = null); val missingBefore = Json.encodeToString(missing)
                try { missing.settleCollectedOutcome(pending, binding, checkpoint, 2_000.0); fail("Missing original accepted") } catch (_: LibrarySyncFailure.InvalidReceipt) { }; assertEquals(missingBefore, Json.encodeToString(missing))
                val wrongOwner = state.copy(savedSnapshot = SyncSavedSnapshot("owner-b", 3.0, emptyList(), emptyList())); val wrongBefore = Json.encodeToString(wrongOwner)
                try { wrongOwner.settleCollectedOutcome(pending, binding, checkpoint, 2_000.0); fail("Foreign snapshot accepted") } catch (_: LibrarySyncFailure.OwnerMismatch) { }; assertEquals(wrongBefore, Json.encodeToString(wrongOwner))
                val fork = Json.decodeFromString<LibraryPartitionState>(Json.encodeToString(state).replace("Original folder", "Changed folder")); val forkBefore = Json.encodeToString(fork)
                try { fork.settleCollectedOutcome(pending, binding, checkpoint, 2_000.0); fail("Changed original accepted") } catch (_: LibrarySyncFailure.InvalidReceipt) { }; assertEquals(forkBefore, Json.encodeToString(fork))
                val conflict = state.copy(folderMappings = mapOf("restore:deleted" to "another-folder")); val conflictBefore = Json.encodeToString(conflict)
                try { conflict.settleCollectedOutcome(pending, binding, checkpoint, 2_000.0); fail("Alias collision replaced") } catch (_: LibrarySyncFailure.InvalidReceipt) { }; assertEquals(conflictBefore, Json.encodeToString(conflict))
            }
            assertEquals(LibraryOutcomeSettlement.Settled, state.settleCollectedOutcome(pending, binding, checkpoint, 2_000.0))
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
            assertEquals(LibraryOutcomeSettlement.Settled, state.settleCollectedOutcome(pending, binding, checkpoint, 7_000.0)); assertEquals(settled, Json.encodeToString(state))
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
        try { state.settle(SyncExchange.Reconcile("owner-a", frame.clientKey, frame.sequence, frame.batch.id, SyncCursor(0.0, SyncOutstanding.Committed(bad))), frame, 2_000.0); fail("Malformed manifest accepted") } catch (_: LibrarySyncFailure.InvalidReceipt) { }
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
        state.settle(SyncExchange.Reconcile("owner-a", frame.clientKey, frame.sequence, frame.batch.id, SyncCursor(0.0, SyncOutstanding.Pending(pending))), frame, 2_000.0)
        assertNull(state.frozen)
        assertEquals(1, state.recovery.size)
        state.settlePending(accepted(frame, SyncReply("owner-a", frame.batch.id, listOf(SyncReceipt(original.id, original.revision, SyncOutcome.Preserved)))), pending, 2_000.0)
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
            assertEquals("cloud-folder", LibraryProjection(state).items.single().folderId)
            state.pending = emptyList()
            state.confirmed = listOf(LibraryConfirmedChange(change, SyncOutcome.Preserved, 2.0))
            state.folderMappings = mapOf("old-guest-folder" to "accepted-guest-folder")
            assertEquals("accepted-guest-folder", LibraryProjection(state).items.single().folderId)
            state.confirmed = emptyList()
            assertEquals("cloud-folder", LibraryProjection(state).items.single().folderId)
            val batch = SyncBatch("unversioned-rejected", listOf(change.operation))
            state.frozen = LibraryFrozenBatch(batch, listOf(change))
            val frame = SyncFrame(state.clientKey, state.nextSequence, batch)
            val outcome = SyncOutcome.Superseded(SyncOutcomeSupersededReason.UNVERSIONED_CLOUD)
            state.settle(accepted(frame, SyncReply(owner.key, batch.id, listOf(SyncReceipt(change.operation.id, change.operation.revision, outcome)))), frame, System.currentTimeMillis().toDouble())
            assertEquals(listOf(LibraryRecovery.Server(change, outcome)), state.recovery)
            assertEquals("cloud-folder", LibraryProjection(state).items.single().folderId)
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
