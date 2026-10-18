import XCTest
@testable import Hadithly

final class GuestMergePlannerTests: XCTestCase {
    private func date(_ seconds: Double) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func accepted(_ frame: SyncFrame, reply: SyncReply) -> SyncExchange {
        .accepted(.init(committed: .init(clientKey: frame.clientKey, sequence: frame.sequence, digest: "fixture-digest", reply: reply)))
    }

    private func acknowledged(_ value: SyncAcknowledgement) -> SyncAckReply {
        .init(ownerKey: "owner-a", clientKey: value.clientKey, cursor: .init(closedThrough: value.sequence, active: nil))
    }

    @MainActor private func settleFixture(_ reply: SyncReply, frame: SyncFrame, store: GuestDataStore, owner: LibrarySyncOwner) throws {
        try store.settleSyncExchange(accepted(frame, reply: reply), requested: frame, owner: owner)
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
                cursor: .init(closedThrough: 0, active: .init(clientKey: frame.clientKey, sequence: 1, digest: "server-proof", reply: .init(ownerKey: replyOwner, batchId: "other-batch", receipts: [.init(id: "other-intent", revision: "r1", outcome: .preserved)])))))
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
