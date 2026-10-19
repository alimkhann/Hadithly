import XCTest
import Combine
@testable import Hadithly

final class GuestMergePlannerTests: XCTestCase {
    private func date(_ seconds: Double) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func accepted(_ frame: SyncFrame, reply: SyncReply) -> SyncExchange {
        .accepted(.init(committed: .init(clientKey: frame.clientKey, sequence: frame.sequence, digest: "fixture-digest", revision: .init(saved: frame.sequence, position: frame.sequence), reply: reply)))
    }

    private func acknowledged(_ value: SyncAcknowledgement) -> SyncAckReply {
        .init(ownerKey: "owner-a", clientKey: value.clientKey, cursor: .init(closedThrough: value.sequence, active: nil))
    }

    @MainActor private func settleFixture(_ reply: SyncReply, frame: SyncFrame, store: GuestDataStore, owner: LibrarySyncOwner) throws {
        try store.settleSyncExchange(accepted(frame, reply: reply), requested: frame, owner: owner)
    }

    @MainActor func testPortableExportIncludesOfflineAndRecoveryTextWithoutProviderPassagesAndRejectsSwitchedOwner() async throws {
        let store = GuestDataStore(inMemory: true)
        let recovered = "Recovery fixture " + String(repeating: "界", count: 8_001)
        store.addNote(hadithId: "target-recovery", content: recovered)
        let fixture = LibraryFacadeFixture(store: store)
        defer { fixture.stop() }
        await fixture.start()
        XCTAssertTrue(fixture.model.saveNote(fixture.reference, content: "Private draft mentions arabicText and pushTokens"))
        let captured = try fixture.sync.captureWriteContext()
        let local = try fixture.sync.portableState(for: captured)
        XCTAssertFalse(local.containsAnyKey(["arabicText", "englishText", "capability"]))
        let json = String(decoding: try JSONEncoder().encode(local), as: UTF8.self)
        XCTAssertTrue(json.contains("Private draft mentions arabicText and pushTokens"))
        XCTAssertTrue(json.contains("Recovery fixture"))
        let server = LibraryExportValue.object(["sync": .object(["streams": .array([])]), "evidenceItems": .array([])])
        let document = try server.includingLocalLibrary(local)
        XCTAssertFalse(document.containsAnyKey(Set(SettingsExport.forbiddenFragments)))
        guard case .object(let fields) = document else { return XCTFail("Export root must be an object") }
        XCTAssertNotNil(fields["sync"])
        XCTAssertNotNil(fields["evidenceItems"])
        XCTAssertEqual(try JSONDecoder().decode(LibraryExportValue.self, from: JSONEncoder().encode(document)), document)
        fixture.session.value = .init(id: "session-b", subject: "subject-b")
        fixture.sync.deactivate(); fixture.model.refresh()
        await fixture.sync.activate(try XCTUnwrap(fixture.session.value))
        XCTAssertThrowsError(try fixture.sync.portableState(for: captured))
        let other = try fixture.sync.portableState(for: fixture.sync.captureWriteContext())
        let otherJSON = String(decoding: try JSONEncoder().encode(other), as: UTF8.self)
        XCTAssertFalse(otherJSON.contains("Private draft"))
        XCTAssertFalse(otherJSON.contains("Recovery fixture"))
    }

    @MainActor func testInvalidPendingNoteRetainsItsOriginalWithoutBlockingTheNextChange() throws {
        let invalid = LibraryLocalChange(command: .notePut(.init(hadithId: "target", content: String(repeating: "界", count: 8_001), createdAt: 1_000, updatedAt: 1_000)), at: 1_000, source: .account(nil))
        let next = LibraryLocalChange(command: .bookmarkAdd(.init(hadithId: "target", createdAt: 1_000)), at: 1_000, source: .account(nil))
        var state = LibraryPartitionState()
        state.pending = [invalid, next]
        let frame = try XCTUnwrap(state.freeze())
        XCTAssertEqual(frame.batch.operations, [next.operation])
        XCTAssertEqual(state.recovery, [.rejected(invalid)])
        XCTAssertTrue(state.pending.isEmpty)
    }

    @MainActor func testActualFacadeRejectsOversizedNoteAndExplicitRemoveNeverAddsAnAbsentBookmark() async throws {
        let fixture = LibraryFacadeFixture(store: GuestDataStore(inMemory: true))
        defer { fixture.stop() }
        await fixture.start()
        let scope = fixture.model.actionScope
        XCTAssertFalse(fixture.model.saveNote(fixture.reference, content: String(repeating: "界", count: 8_001)))
        XCTAssertTrue(fixture.model.lastWriteFailed)
        XCTAssertTrue(fixture.model.notes.isEmpty)
        _ = fixture.model.removeBookmark(fixture.reference, scope: scope)
        XCTAssertFalse(fixture.model.isBookmarked(hadithId: fixture.reference.hadithId))
        fixture.session.value = nil
        fixture.sync.deactivate(); fixture.model.refresh()
        XCTAssertFalse(fixture.model.removeBookmark(fixture.reference, scope: scope))
        XCTAssertTrue(fixture.store.bookmarkDrafts().isEmpty)
    }

    @MainActor func testSignInCleanupPreservesChangesMadeAfterTheSentSnapshot() async throws {
        let store = GuestDataStore(inMemory: true)
        let id = "jn7fxd3z54153q9j13kmhgzkv18df2zd"
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        let session = LibrarySyncSession(id: "session-a", subject: owner.subject)
        store.addNote(hadithId: id, content: "Sent note", createdAt: date(1), updatedAt: date(1))
        store.saveProgress(draft: .init(collectionSlug: "bukhari", collectionName: "Bukhari", hadithId: id, volumeId: "1", hadithNumber: "1", updatedAt: date(1)))
        var batches: [SyncBatch] = []
        let transport = LibrarySyncTransport(namespace: "fixture", open: {
            SyncBinding(ownerKey: owner.key, subject: owner.subject, capability: "local-fixture", validUntil: .greatestFiniteMagnitude)
        }, acknowledge: { _, value in self.acknowledged(value) }, send: { _, batch in
            batches.append(batch.batch)
            if batches.count == 1 {
                XCTAssertTrue(store.noteDrafts().isEmpty, "The old snapshot is durably owned before network work")
                store.saveNote(hadithId: id, content: "New local edit during merge", collectionName: nil, referenceDisplay: nil, volumeId: nil, hadithNumber: nil)
                store.saveProgress(draft: .init(collectionSlug: "bukhari", collectionName: "Bukhari", hadithId: id, volumeId: "1", hadithNumber: "2", updatedAt: self.date(2)))
            }
            return self.accepted(batch, reply: SyncReply(ownerKey: owner.key, batchId: batch.batch.id, receipts: batch.batch.operations.map { .init(id: $0.id, revision: $0.revision, outcome: .preserved) }))
        })
        let sync = LibrarySync(store: store, transport: transport, currentSession: { session })
        defer { sync.deactivate() }
        await sync.activate(session)
        let notes = batches.flatMap(\.operations).compactMap { operation -> String? in
            if case .notePut(let value) = operation.command { return value.content }; return nil
        }
        XCTAssertEqual(notes, ["Sent note", "New local edit during merge"])
        let positions = batches.flatMap(\.operations).compactMap { operation -> String? in
            if case .positionPut(let value) = operation.command { return value.position.anchor.providerHadithId }; return nil
        }
        XCTAssertEqual(positions, ["1", "2"])
        XCTAssertTrue(try store.syncPartition(owner)?.pending.isEmpty == true)
        XCTAssertNil(try store.syncPartition(owner)?.frozen)
    }

    @MainActor func testFrozenClaimSurvivesReopenAndCannotSettleAnotherOwnerOrNewEdits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("guest.store")
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        let id = "jn7fxd3z54153q9j13kmhgzkv18df2zd"
        let batch: SyncFrame
        do {
            let store = GuestDataStore(storeURL: url)
            store.addNote(hadithId: id, content: "Durable claimed note", createdAt: date(1), updatedAt: date(1))
            try store.claimGuestForSync(owner)
            batch = try XCTUnwrap(store.freezeSyncFrame(owner))
            store.addNote(hadithId: id, content: "Unclaimed later guest note", createdAt: date(2), updatedAt: date(2))
        }
        let reopened = GuestDataStore(storeURL: url)
        XCTAssertEqual(try reopened.freezeSyncFrame(owner), batch)
        XCTAssertEqual(reopened.noteDrafts().map(\.content), ["Unclaimed later guest note"])
        let receipt = SyncReply(ownerKey: owner.key, batchId: batch.batch.id, receipts: batch.batch.operations.map { .init(id: $0.id, revision: $0.revision, outcome: .preserved) })
        XCTAssertThrowsError(try settleFixture(receipt, frame: batch, store: reopened, owner: .init(key: "owner-b", subject: "subject-b")))
        try settleFixture(receipt, frame: batch, store: reopened, owner: owner)
        XCTAssertEqual(reopened.noteDrafts().map(\.content), ["Unclaimed later guest note"])
        XCTAssertNil(try reopened.syncPartition(owner)?.frozen)
    }

    @MainActor func testInvalidReceiptsKeepFrozenDataAndConflictsKeepRecoverableContent() throws {
        let store = GuestDataStore(inMemory: true)
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        store.addNote(hadithId: "jn7fxd3z54153q9j13kmhgzkv18df2zd", content: "Recoverable fixture", createdAt: date(1), updatedAt: date(1))
        try store.claimGuestForSync(owner)
        let batch = try XCTUnwrap(store.freezeSyncFrame(owner))
        let operation = try XCTUnwrap(batch.batch.operations.first)
        XCTAssertThrowsError(try settleFixture(.init(ownerKey: owner.key, batchId: batch.batch.id, receipts: []), frame: batch, store: store, owner: owner))
        XCTAssertEqual(try store.freezeSyncFrame(owner), batch)
        try settleFixture(.init(ownerKey: owner.key, batchId: batch.batch.id, receipts: [.init(id: operation.id, revision: operation.revision, outcome: .superseded(.init(reason: .newerCloud)))]), frame: batch, store: store, owner: owner)
        let recovery = try XCTUnwrap(store.syncPartition(owner)?.recovery)
        XCTAssertEqual(recovery.count, 1)
        guard case .server(let change, _) = recovery[0], case .note(let note) = change.source else { return XCTFail("Lost original recovery data") }
        XCTAssertEqual(note.content, "Recoverable fixture")
    }

    @MainActor func testPartialFolderReceiptRetainsOriginalRestoreIntent() throws {
        let store = GuestDataStore(inMemory: true)
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        try store.claimGuestForSync(owner)
        let command = SyncCommand.folderRestore(.init(deletionId: "deleted-folder", name: "Fixture", hadithIds: ["restored", "changed", "missing"]))
        let change = LibraryLocalChange(command: command, at: 1_000, source: .account(nil))
        try store.enqueueSyncChange(change, owner: owner)
        let batch = try XCTUnwrap(store.freezeSyncFrame(owner))
        let outcome = SyncOutcome.folderRestored(.init(folderId: "folder", restored: ["restored"], superseded: ["changed"], missing: ["missing"]))
        try settleFixture(.init(ownerKey: owner.key, batchId: batch.batch.id, receipts: [.init(id: change.operation.id, revision: change.operation.revision, outcome: outcome)]), frame: batch, store: store, owner: owner)
        let recovery = try XCTUnwrap(store.syncPartition(owner)?.recovery)
        XCTAssertEqual(recovery, [.server(change, outcome)])
        XCTAssertNil(try store.syncPartition(owner)?.frozen)
    }

    @MainActor func testVerifiedSubjectMismatchLeavesGuestDataUnclaimed() async throws {
        let store = GuestDataStore(inMemory: true)
        store.addNote(hadithId: "target", content: "Guest fixture", createdAt: date(1), updatedAt: date(1))
        let session = LibrarySyncSession(id: "session-a", subject: "subject-a")
        let transport = LibrarySyncTransport(namespace: "fixture", open: {
            SyncBinding(ownerKey: "owner-b", subject: "subject-b", capability: "fixture", validUntil: .greatestFiniteMagnitude)
        }, acknowledge: { _, value in self.acknowledged(value) }, send: { _, _ in XCTFail("Mismatched account must never send"); throw LibrarySyncFailure.ownerMismatch })
        let sync = LibrarySync(store: store, transport: transport, currentSession: { session })
        defer { sync.deactivate() }
        await sync.activate(session)
        XCTAssertEqual(sync.status, .failed)
        XCTAssertNil(sync.owner)
        XCTAssertEqual(store.noteDrafts().map(\.content), ["Guest fixture"])
        XCTAssertNil(try store.syncPartition(.init(key: "owner-b", subject: "subject-b")))
    }

    @MainActor func testCapturedWritesCannotFollowAccountSwitchOrRecreateErasedPartition() async throws {
        let store = GuestDataStore(inMemory: true)
        var current = LibrarySyncSession(id: "session-a", subject: "subject-a")
        let transport = LibrarySyncTransport(namespace: "fixture", open: {
            SyncBinding(ownerKey: current.subject, subject: current.subject, capability: "fixture", validUntil: .greatestFiniteMagnitude)
        }, acknowledge: { _, value in self.acknowledged(value) }, send: { _, _ in XCTFail("Rejected write must never send"); throw LibrarySyncFailure.sessionChanged })
        let sync = LibrarySync(store: store, transport: transport, currentSession: { current })
        defer { sync.deactivate() }
        await sync.activate(current)
        let oldContext = try sync.captureWriteContext()
        sync.deactivate()
        current = .init(id: "session-b", subject: "subject-b")
        await sync.activate(current)
        let change = LibraryLocalChange(command: .notePut(.init(hadithId: "target", content: "Account A fixture", createdAt: 1_000, updatedAt: 1_000)), at: 1_000, source: .account(nil))
        XCTAssertThrowsError(try sync.enqueue(change, context: oldContext))
        let ownerB = try XCTUnwrap(sync.owner)
        XCTAssertTrue(try store.syncPartition(ownerB)?.pending.isEmpty == true)
        let currentContext = try sync.captureWriteContext()
        try store.eraseSyncPartition(ownerB)
        XCTAssertThrowsError(try sync.enqueue(change, context: currentContext))
        XCTAssertNil(try store.syncPartition(ownerB))
    }

    @MainActor func testDurableAcknowledgementSurvivesReopenAndFencesNewFreezeAndLateAck() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("ack.store")
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        let acknowledgement: SyncAcknowledgement
        do {
            let store = GuestDataStore(storeURL: url)
            store.addNote(hadithId: "target", content: "First fixture", createdAt: date(1), updatedAt: date(1))
            try store.claimGuestForSync(owner)
            let frame = try XCTUnwrap(store.freezeSyncFrame(owner))
            try settleFixture(.init(ownerKey: owner.key, batchId: frame.batch.id, receipts: frame.batch.operations.map { .init(id: $0.id, revision: $0.revision, outcome: .preserved) }), frame: frame, store: store, owner: owner)
            acknowledgement = try XCTUnwrap(store.syncPartition(owner)?.acknowledgement)
            try store.enqueueSyncChange(.init(command: .noteRemove(.init(hadithId: "target")), at: 2_000, source: .account(nil)), owner: owner)
            XCTAssertThrowsError(try store.freezeSyncFrame(owner))
        }
        let reopened = GuestDataStore(storeURL: url)
        XCTAssertEqual(try reopened.syncPartition(owner)?.acknowledgement, acknowledgement)
        try reopened.settleSyncAcknowledgement(acknowledged(acknowledgement), requested: acknowledgement, owner: owner)
        let next = try XCTUnwrap(reopened.freezeSyncFrame(owner))
        XCTAssertEqual(next.sequence, 2)
        XCTAssertThrowsError(try reopened.settleSyncAcknowledgement(acknowledged(acknowledgement), requested: acknowledgement, owner: owner))
        XCTAssertEqual(try reopened.freezeSyncFrame(owner), next)
    }

    @MainActor func testClosedBackupFrameArchivesOriginalAndKeepsNeverSentPendingIntent() throws {
        let store = GuestDataStore(inMemory: true)
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        store.addNote(hadithId: "target", content: "Unknown old fixture", createdAt: date(1), updatedAt: date(1))
        try store.claimGuestForSync(owner)
        let frame = try XCTUnwrap(store.freezeSyncFrame(owner))
        let pending = LibraryLocalChange(command: .notePut(.init(hadithId: "target", content: "Never sent fixture", createdAt: 2_000, updatedAt: 2_000)), at: 2_000, source: .account(nil))
        try store.enqueueSyncChange(pending, owner: owner)
        let exchange = SyncExchange.reconcile(.init(ownerKey: owner.key, clientKey: frame.clientKey, requestedSequence: frame.sequence, requestedBatchId: frame.batch.id, cursor: .init(closedThrough: 5, active: nil)))
        try store.settleSyncExchange(exchange, requested: frame, owner: owner)
        let state = try XCTUnwrap(store.syncPartition(owner))
        guard case .historical(let original) = state.recovery.first, case .note(let note) = original.source else { return XCTFail("Original intent disappeared") }
        XCTAssertEqual(note.content, "Unknown old fixture")
        XCTAssertEqual(state.pending, [pending])
        let next = try XCTUnwrap(store.freezeSyncFrame(owner))
        XCTAssertEqual(next.sequence, 6)
        XCTAssertEqual(next.batch.operations, [pending.operation])
    }

    @MainActor func testOccupiedBackupFrameChecksNestedOwnerAndPersistsOtherReceiptProof() throws {
        let store = GuestDataStore(inMemory: true)
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        store.addNote(hadithId: "target", content: "Available backup fixture", createdAt: date(1), updatedAt: date(1))
        try store.claimGuestForSync(owner)
        let frame = try XCTUnwrap(store.freezeSyncFrame(owner))
        func exchange(_ replyOwner: String) -> SyncExchange {
            .reconcile(.init(ownerKey: owner.key, clientKey: frame.clientKey, requestedSequence: frame.sequence, requestedBatchId: frame.batch.id,
                cursor: .init(closedThrough: 0, active: .init(clientKey: frame.clientKey, sequence: 1, digest: "server-proof", revision: .init(saved: 1, position: 1), reply: .init(ownerKey: replyOwner, batchId: "other-batch", receipts: [.init(id: "other-intent", revision: "r1", outcome: .preserved)])))))
        }
        XCTAssertThrowsError(try store.settleSyncExchange(exchange("owner-b"), requested: frame, owner: owner))
        XCTAssertEqual(try store.freezeSyncFrame(owner), frame)
        try store.settleSyncExchange(exchange(owner.key), requested: frame, owner: owner)
        let state = try XCTUnwrap(store.syncPartition(owner))
        XCTAssertNil(state.frozen)
        XCTAssertEqual(state.recovery.count, 1)
        XCTAssertEqual(state.acknowledgement?.batchId, "other-batch")
        XCTAssertEqual(state.acknowledgement?.digest, "server-proof")
        XCTAssertThrowsError(try store.freezeSyncFrame(owner))
    }

    @MainActor func testFrozenFrameIncludesOnlyOneFolderFanoutAndKeepsTheRestPending() throws {
        let store = GuestDataStore(inMemory: true)
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        try store.claimGuestForSync(owner)
        for index in 1...2 {
            try store.enqueueSyncChange(.init(command: .folderDelete(.init(folder: .local(.init(key: "folder-\(index)")))), at: 1_000, source: .account(nil)), owner: owner)
        }
        let frame = try XCTUnwrap(store.freezeSyncFrame(owner))
        XCTAssertEqual(frame.batch.operations.count, 1)
        XCTAssertEqual(try store.syncPartition(owner)?.pending.count, 1)
    }

    @MainActor func testActualLibraryFacadePersistsOfflineIntentsAndRestoresProjectionAfterReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("facade.store")
        let first = LibraryFacadeFixture(store: GuestDataStore(storeURL: url))
        await first.start()
        first.saved.send(.init(ownerKey: "owner-a", version: 0, folders: [], items: []))
        try await waitForLibrary { first.model.loadState == .ready }
        let ref = first.reference
        first.model.toggleBookmark(ref)
        first.model.toggleFavorite(ref)
        first.model.saveNote(ref, content: "Offline private fixture")
        first.model.createFolder(name: "Private folder", scope: first.model.actionScope)
        let folder = try XCTUnwrap(first.model.folders.first)
        first.model.assignFolder(hadithId: ref.hadithId, folderId: folder.id, scope: first.model.actionScope)
        let position = try XCTUnwrap(ReadingPosition.legacy(collectionSlug: "bukhari", providerHadithId: "1", volumeId: "1", updatedAt: Date.now.millisecondsSinceEpoch))
        first.model.saveProgress(position, ref: ref)
        first.model.toggleBookmark(ref)
        first.model.restoreBookmark(ref, createdAt: .now)
        let note = try XCTUnwrap(first.model.notes.first)
        first.model.deleteNote(ref, scope: first.model.actionScope)
        first.model.restoreNote(ref, content: "Offline private fixture", createdAt: note.createdAt, updatedAt: note.sortDate)
        first.model.deleteFolder(folder, scope: first.model.actionScope)
        first.model.undoDeleteFolder()
        XCTAssertTrue(first.model.isBookmarked(hadithId: ref.hadithId))
        XCTAssertTrue(first.model.isFavorite(hadithId: ref.hadithId))
        XCTAssertEqual(first.model.notes.first?.noteContent, "Offline private fixture")
        XCTAssertEqual(first.model.folders.first?.name, "Private folder")
        XCTAssertEqual(first.model.savedItems.first?.folderId, first.model.folders.first?.id)
        XCTAssertEqual(first.model.continueReading?.position?.anchor.providerHadithId, "1")
        try await waitForLibrary { !first.server.frames.isEmpty }
        let owner = try XCTUnwrap(first.sync.owner)
        let state = try XCTUnwrap(first.store.syncPartition(owner))
        XCTAssertFalse(state.pending.isEmpty)
        XCTAssertNotNil(state.frozen)
        first.stop()
        let reopened = LibraryFacadeFixture(store: GuestDataStore(storeURL: url))
        defer { reopened.stop() }
        await reopened.start()
        XCTAssertTrue(reopened.model.isBookmarked(hadithId: ref.hadithId))
        XCTAssertTrue(reopened.model.isFavorite(hadithId: ref.hadithId))
        XCTAssertEqual(reopened.model.notes.first?.noteContent, "Offline private fixture")
        XCTAssertEqual(reopened.model.savedItems.first?.folderId, reopened.model.folders.first?.id)
        XCTAssertEqual(reopened.model.continueReading?.position?.anchor.providerHadithId, "1")
    }

    @MainActor func testActualLibraryFacadeKeepsAcceptedNoteUntilOwnedQueryRevisionCatchesUp() async throws {
        let fixture = LibraryFacadeFixture(store: GuestDataStore(inMemory: true))
        defer { fixture.stop() }
        await fixture.start()
        fixture.saved.send(.init(ownerKey: "owner-a", version: 0, folders: [], items: []))
        try await waitForLibrary { fixture.model.loadState == .ready }
        fixture.model.saveNote(fixture.reference, content: "Accepted private fixture")
        try await waitForLibrary { !fixture.server.frames.isEmpty }
        fixture.server.failSends = false
        await fixture.sync.activate(try XCTUnwrap(fixture.session.value))
        let owner = try XCTUnwrap(fixture.sync.owner)
        try await waitForLibrary {
            guard let state = try? fixture.store.syncPartition(owner) else { return false }
            return state.frozen == nil && state.acknowledgement == nil && state.confirmed.count == 1
        }
        XCTAssertTrue(try fixture.store.syncPartition(owner)?.pending.isEmpty == true)
        XCTAssertNil(try fixture.store.syncPartition(owner)?.frozen)
        XCTAssertNil(try fixture.store.syncPartition(owner)?.acknowledgement)
        XCTAssertEqual(fixture.model.notes.first?.noteContent, "Accepted private fixture")
        XCTAssertEqual(try fixture.store.syncPartition(owner)?.confirmed.count, 1)
        fixture.saved.send(.init(ownerKey: "owner-a", version: 0, folders: [], items: []))
        fixture.positions.send(.init(ownerKey: "owner-a", version: 50, rows: []))
        try await waitForLibrary { (try? fixture.store.syncPartition(owner)?.positionsSnapshot?.version) == 50 }
        XCTAssertEqual(fixture.model.notes.first?.noteContent, "Accepted private fixture")
        XCTAssertEqual(try fixture.store.syncPartition(owner)?.confirmed.count, 1)
        fixture.saved.send(fixture.snapshot(version: 2, note: "Later cloud fixture"))
        try await waitForLibrary { fixture.model.notes.first?.noteContent == "Later cloud fixture" }
        XCTAssertTrue(try fixture.store.syncPartition(owner)?.confirmed.isEmpty == true)
        fixture.saved.send(fixture.snapshot(version: 1, note: "Older delayed fixture"))
        fixture.positions.send(.init(ownerKey: "owner-a", version: 99, rows: []))
        try await waitForLibrary { (try? fixture.store.syncPartition(owner)?.positionsSnapshot?.version) == 99 }
        XCTAssertEqual(fixture.model.notes.first?.noteContent, "Later cloud fixture")
    }

    @MainActor func testActualLibraryFacadeRejectsLateAccountReadsAndUndoAfterSwitchAndSignOut() async throws {
        let fixture = LibraryFacadeFixture(store: GuestDataStore(inMemory: true))
        defer { fixture.stop() }
        await fixture.start()
        fixture.saved.send(fixture.snapshot(version: 0, note: "Account A fixture"))
        try await waitForLibrary { fixture.model.notes.first?.noteContent == "Account A fixture" }
        fixture.model.toggleBookmark(fixture.reference)
        fixture.model.toggleBookmark(fixture.reference)
        fixture.model.deleteNote(fixture.reference, scope: fixture.model.actionScope)
        fixture.saved.send(fixture.snapshot(version: 1, note: "Queued late A fixture"))
        fixture.session.value = .init(id: "session-b", subject: "subject-b")
        fixture.sync.deactivate(); fixture.model.refresh()
        await fixture.sync.activate(try XCTUnwrap(fixture.session.value))
        fixture.saved.send(fixture.snapshot(version: 20, note: "Wrong owner fixture"))
        fixture.saved.send(.init(ownerKey: "owner-b", version: 0, folders: [], items: []))
        try await waitForLibrary { fixture.model.loadState == .ready }
        fixture.model.restoreBookmark(fixture.reference, createdAt: .now)
        fixture.model.restoreNote(fixture.reference, content: "A undo fixture", createdAt: .now, updatedAt: .now)
        let ownerB = try XCTUnwrap(fixture.sync.owner)
        XCTAssertTrue(fixture.model.savedItems.isEmpty)
        XCTAssertTrue(try fixture.store.syncPartition(ownerB)?.pending.isEmpty == true)
        XCTAssertNil(try fixture.store.syncPartition(ownerB)?.frozen)
        XCTAssertEqual(try fixture.store.syncPartition(ownerB)?.savedSnapshot?.ownerKey, "owner-b")
        fixture.session.value = nil; fixture.sync.deactivate(); fixture.model.refresh()
        fixture.model.restoreBookmark(fixture.reference, createdAt: .now)
        fixture.model.restoreNote(fixture.reference, content: "A undo fixture", createdAt: .now, updatedAt: .now)
        XCTAssertTrue(fixture.store.bookmarkDrafts().isEmpty)
        XCTAssertTrue(fixture.store.noteDrafts().isEmpty)
        XCTAssertTrue(fixture.model.savedItems.isEmpty)
    }

    @MainActor private func waitForLibrary(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), "Library state did not converge")
    }

    // MARK: - Valid hadith id filtering

    func testValidHadithIdsPass() {
        XCTAssertTrue(GuestMergePlanner.isValidHadithId("jn7fxd3z54153q9j13kmhgzkv18df2zd"))
    }

    func testEmptyAndShortIdsAreRejected() {
        XCTAssertFalse(GuestMergePlanner.isValidHadithId(""))
        XCTAssertFalse(GuestMergePlanner.isValidHadithId("short"))
    }

    func testUppercaseIdsAreRejected() {
        XCTAssertFalse(GuestMergePlanner.isValidHadithId("JN7FXD3Z54153Q9J13KMHGZKV18DF2ZD"))
    }

    func testIdsWithSymbolsAreRejected() {
        XCTAssertFalse(GuestMergePlanner.isValidHadithId("jn7fxd3z54153q9j13kmhgzkv18df2z!"))
    }

    // MARK: - Payload building

    func testPayloadIsEmptyWhenNoGuestData() {
        let payload = GuestMergePlanner.makePayload(bookmarks: [], notes: [])
        XCTAssertTrue(payload.isEmpty)
    }

    func testInvalidHadithIdsAreDropped() {
        let payload = GuestMergePlanner.makePayload(
            bookmarks: [
                GuestBookmarkDraft(hadithId: "not-a-real-id", createdAt: date(100)),
                GuestBookmarkDraft(hadithId: "jn7fxd3z54153q9j13kmhgzkv18df2zd", createdAt: date(200)),
            ],
            notes: [
                GuestNoteDraft(hadithId: "", content: "orphan", createdAt: date(1), updatedAt: date(1)),
            ]
        )
        XCTAssertEqual(payload.bookmarks.count, 1)
        XCTAssertEqual(payload.bookmarks.first?.hadithId, "jn7fxd3z54153q9j13kmhgzkv18df2zd")
        XCTAssertTrue(payload.notes.isEmpty)
    }

    func testDuplicateBookmarksKeepEarliestCreation() {
        let payload = GuestMergePlanner.makePayload(
            bookmarks: [
                GuestBookmarkDraft(hadithId: "jn7fxd3z54153q9j13kmhgzkv18df2zd", createdAt: date(500)),
                GuestBookmarkDraft(hadithId: "jn7fxd3z54153q9j13kmhgzkv18df2zd", createdAt: date(100)),
            ],
            notes: []
        )
        XCTAssertEqual(payload.bookmarks.count, 1)
        XCTAssertEqual(payload.bookmarks.first?.createdAt, 100_000)
    }

    func testDuplicateNotesKeepLatestEdit() {
        let payload = GuestMergePlanner.makePayload(
            bookmarks: [],
            notes: [
                GuestNoteDraft(hadithId: "jn7fxd3z54153q9j13kmhgzkv18df2zd", content: "old", createdAt: date(10), updatedAt: date(20)),
                GuestNoteDraft(hadithId: "jn7fxd3z54153q9j13kmhgzkv18df2zd", content: "newer", createdAt: date(10), updatedAt: date(30)),
                GuestNoteDraft(hadithId: "jn7fxd3z54153q9j13kmhgzkv18df2zd", content: "stale", createdAt: date(10), updatedAt: date(15)),
            ]
        )
        XCTAssertEqual(payload.notes.count, 1)
        XCTAssertEqual(payload.notes.first?.content, "newer")
        XCTAssertEqual(payload.notes.first?.updatedAt, 30_000)
    }

    func testTimestampsAreMillisecondsSinceEpoch() {
        let payload = GuestMergePlanner.makePayload(
            bookmarks: [GuestBookmarkDraft(hadithId: "jn7fxd3z54153q9j13kmhgzkv18df2zd", createdAt: date(1.5))],
            notes: []
        )
        XCTAssertEqual(payload.bookmarks.first?.createdAt, 1500)
    }

    func testItemsAreSortedByTimestamp() {
        let payload = GuestMergePlanner.makePayload(
            bookmarks: [
                GuestBookmarkDraft(hadithId: "baaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1", createdAt: date(300)),
                GuestBookmarkDraft(hadithId: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", createdAt: date(100)),
                GuestBookmarkDraft(hadithId: "caaaaaaaaaaaaaaaaaaaaaaaaaaaaaa2", createdAt: date(200)),
            ],
            notes: []
        )
        XCTAssertEqual(payload.bookmarks.map(\.createdAt), [100_000, 200_000, 300_000])
    }

    // MARK: - Favorites and reading progress (Phase 3)

    func testDuplicateFavoritesKeepEarliestCreation() {
        let payload = GuestMergePlanner.makePayload(
            bookmarks: [],
            notes: [],
            favorites: [
                GuestFavoriteDraft(hadithId: "jn7fxd3z54153q9j13kmhgzkv18df2zd", createdAt: date(900)),
                GuestFavoriteDraft(hadithId: "jn7fxd3z54153q9j13kmhgzkv18df2zd", createdAt: date(100)),
            ]
        )
        XCTAssertEqual(payload.favorites.count, 1)
        XCTAssertEqual(payload.favorites.first?.createdAt, 100_000)
    }

    func testProgressKeepsNewestPositionPerCollection() {
        let payload = GuestMergePlanner.makePayload(
            bookmarks: [],
            notes: [],
            progress: [
                GuestReadingProgressDraft(
                    collectionSlug: "bukhari",
                    collectionName: "Sahih al-Bukhari",
                    hadithId: "jn7fxd3z54153q9j13kmhgzkv18df2zd",
                    updatedAt: date(100)
                ),
                GuestReadingProgressDraft(
                    collectionSlug: "bukhari",
                    collectionName: "Sahih al-Bukhari",
                    hadithId: "baaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1",
                    updatedAt: date(500)
                ),
                GuestReadingProgressDraft(
                    collectionSlug: "muslim",
                    collectionName: "Sahih Muslim",
                    hadithId: "caaaaaaaaaaaaaaaaaaaaaaaaaaaaaa2",
                    updatedAt: date(300)
                ),
            ]
        )
        XCTAssertEqual(payload.readingProgress.count, 2)
        let bukhari = payload.readingProgress.first { $0.collectionSlug == "bukhari" }
        XCTAssertEqual(bukhari?.hadithId, "baaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1")
    }

    func testEmptyStateIncludesNewCollections() {
        let payload = GuestMergePlanner.makePayload(bookmarks: [], notes: [])
        XCTAssertTrue(payload.isEmpty)
        let withFavorite = GuestMergePlanner.makePayload(
            bookmarks: [],
            notes: [],
            favorites: [
                GuestFavoriteDraft(hadithId: "jn7fxd3z54153q9j13kmhgzkv18df2zd", createdAt: date(1)),
            ]
        )
        XCTAssertFalse(withFavorite.isEmpty)
    }
}

@MainActor private final class LibraryFixtureSession {
    var value: LibrarySyncSession? = .init(id: "session-a", subject: "subject-a")
}

@MainActor private final class LibraryFixtureServer {
    enum Failure: Error { case offline }
    var frames: [SyncFrame] = []
    var failSends = true
    var revisions: [String: SyncRevision] = [:]
    func send(_ capability: String, _ frame: SyncFrame) throws -> SyncExchange {
        frames.append(frame)
        if failSends { throw Failure.offline }
        let owner = String(capability.dropFirst("fixture:".count))
        let old = revisions[owner] ?? .init(saved: 0, position: 0)
        let saved = frame.batch.operations.contains { !$0.command.isPositionChange }
        let position = frame.batch.operations.contains { $0.command.isPositionChange }
        let revision = SyncRevision(saved: old.saved + (saved ? 1 : 0), position: old.position + (position ? 1 : 0))
        revisions[owner] = revision
        let receipts = frame.batch.operations.map { SyncReceipt(id: $0.id, revision: $0.revision, outcome: .preserved) }
        return .accepted(.init(committed: .init(clientKey: frame.clientKey, sequence: frame.sequence, digest: "fixture-proof", revision: revision,
            reply: .init(ownerKey: owner, batchId: frame.batch.id, receipts: receipts))))
    }
}

@MainActor private final class LibraryFacadeFixture {
    let store: GuestDataStore
    let session = LibraryFixtureSession()
    let server = LibraryFixtureServer()
    let saved = PassthroughSubject<SyncSavedSnapshot, Error>()
    let positions = PassthroughSubject<SyncPositionsSnapshot, Error>()
    let sync: LibrarySync
    let model: UserLibraryModel
    let reference = HadithRef(hadithId: "jn7fxd3z54153q9j13kmhgzkv18df2zd", collectionSlug: "bukhari", collectionName: "Bukhari", volumeId: "1", hadithNumber: "1", arabicText: "نص", englishText: "Fixture", referenceDisplay: "Bukhari 1")
    init(store: GuestDataStore) {
        self.store = store
        let session = self.session, server = self.server, saved = self.saved, positions = self.positions
        sync = LibrarySync(store: store, transport: .init(namespace: "fixture", open: {
            guard let current = session.value else { throw LibrarySyncFailure.sessionChanged }
            let owner = current.subject == "subject-a" ? "owner-a" : "owner-b"
            return .init(ownerKey: owner, subject: current.subject, capability: "fixture:" + owner, validUntil: Date.now.millisecondsSinceEpoch + 900_000)
        }, acknowledge: { capability, value in
            .init(ownerKey: String(capability.dropFirst("fixture:".count)), clientKey: value.clientKey, cursor: .init(closedThrough: value.sequence, active: nil))
        }, send: { capability, frame in try server.send(capability, frame) }), currentSession: { session.value })
        model = UserLibraryModel(reads: .init(saved: { saved.eraseToAnyPublisher() }, positions: { positions.eraseToAnyPublisher() }), guestData: store, sync: sync, currentSession: { session.value })
        let model = self.model
        sync.onOwnerChange = { [weak model] _ in model?.refresh() }
        sync.onPartitionChange = { [weak model] owner in model?.partitionChanged(owner) }
    }
    func start() async { if let current = session.value { await sync.activate(current) }; model.refresh() }
    func stop() { sync.deactivate(); session.value = nil; model.refresh() }
    func snapshot(version: Double, note: String) -> SyncSavedSnapshot {
        .init(ownerKey: "owner-a", version: version, folders: [], items: [.init(hadithId: reference.hadithId, createdAt: 1_000, updatedAt: 2_000,
            bookmarkCreatedAt: nil, favoriteCreatedAt: nil, noteContent: note, noteCreatedAt: 1_000, noteUpdatedAt: 2_000, folderId: nil,
            hadith: .init(_id: reference.hadithId, providerHadithId: "1", collectionSlug: "bukhari", collectionName: "Bukhari", volumeId: "1", arabicText: "نص", englishText: "Fixture", referenceDisplay: "Bukhari 1"))])
    }
}
