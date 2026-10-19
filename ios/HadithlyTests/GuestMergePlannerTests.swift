import XCTest
import Combine
import SwiftData
@testable import Hadithly

final class GuestMergePlannerTests: XCTestCase {
    @MainActor func testHeldOriginalSurvivesStoreReopenRetirementAndTerminalFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("held.store"), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        let store = GuestDataStore(storeURL: url)
        try store.claimGuestForSync(owner)
        try store.enqueueSyncChange(.init(command: .folderDelete(.init(folder: .server(.init(id: "folder-a")))), at: 1_000, source: .account(nil)), owner: owner)
        let later = LibraryLocalChange(command: .notePut(.init(hadithId: "target", content: "Later original", createdAt: 2_000, updatedAt: 2_000)), at: 2_000, source: .account(nil))
        try store.enqueueSyncChange(later, owner: owner)
        let frame = try XCTUnwrap(store.freezeSyncFrame(owner))
        XCTAssertEqual(frame.batch.operations.count, 1)
        let pending = SyncPending(clientKey: frame.clientKey, sequence: frame.sequence, batchId: frame.batch.id, digest: "fixture-digest", intentDigest: try frame.batch.intentDigest(), manifestId: "manifest", generation: "generation", retryAfterMs: 1_000)
        try store.settleSyncExchange(.pending(.init(ownerKey: owner.key, pending: pending)), requested: frame, owner: owner)
        let reopened = GuestDataStore(storeURL: url)
        let before = try XCTUnwrap(reopened.syncPartition(owner))
        XCTAssertEqual(before.waiting, pending); XCTAssertEqual(before.frozen?.batch, frame.batch)
        XCTAssertEqual(before.pending, [later]); XCTAssertEqual(before.nextSequence, 1); XCTAssertNil(before.acknowledgement)
        XCTAssertThrowsError(try reopened.freezeSyncFrame(owner))
        try reopened.settleSyncRetirement(.init(ownerKey: owner.key, clientKey: frame.clientKey, cursor: .init(closedThrough: 0, outstanding: .pending(.init(pending: pending)))), requested: frame, owner: owner)
        XCTAssertEqual(try reopened.syncPartition(owner)?.frozen?.batch, frame.batch)
        XCTAssertThrowsError(try reopened.settleSyncPending(.pending(.init(ownerKey: "other-owner", pending: pending)), requested: pending, owner: owner))
        let operation = frame.batch.operations[0]
        try reopened.settleSyncPending(accepted(frame, reply: .init(ownerKey: owner.key, batchId: frame.batch.id, receipts: [.init(id: operation.id, revision: operation.revision, outcome: .unresolved(.init(reason: .preparationExpired)))])), requested: pending, owner: owner)
        let terminal = try XCTUnwrap(reopened.syncPartition(owner))
        XCTAssertNil(terminal.waiting); XCTAssertNil(terminal.frozen); XCTAssertEqual(terminal.recovery.count, 1)
        try reopened.settleSyncAcknowledgement(acknowledged(try XCTUnwrap(terminal.acknowledgement)), requested: try XCTUnwrap(terminal.acknowledgement), owner: owner)
        XCTAssertEqual(try reopened.freezeSyncFrame(owner)?.batch.operations, [later.operation])
    }

    @MainActor func testCoordinatorDelaysPendingPollingAndSendsLaterIntentOnlyAfterTerminalAck() async throws {
        let store = GuestDataStore(inMemory: true), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        let session = LibrarySyncSession(id: "session-a", subject: owner.subject)
        try store.claimGuestForSync(owner)
        try store.enqueueSyncChange(.init(command: .folderDelete(.init(folder: .server(.init(id: "folder-a")))), at: 1_000, source: .account(nil)), owner: owner)
        try store.enqueueSyncChange(.init(command: .bookmarkAdd(.init(hadithId: "target", createdAt: 2_000)), at: 2_000, source: .account(nil)), owner: owner)
        var sends: [SyncFrame] = [], polls = 0, acknowledgements = 0
        let sync = LibrarySync(store: store, transport: .init(namespace: "fixture", open: {
            .init(ownerKey: owner.key, subject: owner.subject, capability: "fixture", validUntil: Date.now.millisecondsSinceEpoch + 60_000)
        }, acknowledge: { _, value in acknowledgements += 1; return self.acknowledged(value) }, send: { _, frame in
            sends.append(frame)
            if sends.count == 1 {
                return .pending(.init(ownerKey: owner.key, pending: .init(clientKey: frame.clientKey, sequence: frame.sequence, batchId: frame.batch.id, digest: "fixture-digest", intentDigest: try frame.batch.intentDigest(), manifestId: "manifest", generation: "generation", retryAfterMs: 1_000)))
            }
            return self.accepted(frame, reply: .init(ownerKey: owner.key, batchId: frame.batch.id, receipts: frame.batch.operations.map { .init(id: $0.id, revision: $0.revision, outcome: .preserved) }))
        }, poll: { _, _ in
            polls += 1; let frame = sends[0], operation = frame.batch.operations[0]
            return self.accepted(frame, reply: .init(ownerKey: owner.key, batchId: frame.batch.id, receipts: [.init(id: operation.id, revision: operation.revision, outcome: .unresolved(.init(reason: .preparationExpired)))]))
        }), currentSession: { session })
        defer { sync.deactivate() }
        await sync.activate(session)
        XCTAssertEqual(sends.count, 1); XCTAssertEqual(polls, 0); XCTAssertEqual(acknowledgements, 0)
        try await waitForLibrary { sync.status == .ready(recovered: 1) }
        XCTAssertEqual(polls, 1); XCTAssertEqual(sends.count, 2); XCTAssertEqual(acknowledgements, 2)
    }

    func testIntentFingerprintMatchesBackendUnicodeAndNumberVectors() throws {
        for vector in LibrarySyncIntentVectors.values {
            let batch = try JSONDecoder().decode(SyncBatch.self, from: Data(vector.json.utf8))
            XCTAssertEqual(try batch.intentDigest(), vector.digest)
        }
    }

    func testPendingCloneWithReusedIDsArchivesItsDifferentIntent() throws {
        var state = LibraryPartitionState()
        state.append(.account(nil), command: .folderDelete(.init(folder: .server(.init(id: "folder-a")))), at: 1_000)
        let frame = try XCTUnwrap(state.freeze())
        let original = frame.batch.operations[0]
        let serverBatch = SyncBatch(id: frame.batch.id, operations: [.init(id: original.id, revision: original.revision, at: original.at, command: .folderDelete(.init(folder: .server(.init(id: "folder-b")))))])
        let pending = SyncPending(clientKey: frame.clientKey, sequence: frame.sequence, batchId: frame.batch.id, digest: "fixture-digest", intentDigest: try serverBatch.intentDigest(), manifestId: "manifest", generation: "generation", retryAfterMs: 1_000)
        try state.settle(.reconcile(.init(ownerKey: "owner-a", clientKey: frame.clientKey, requestedSequence: frame.sequence, requestedBatchId: frame.batch.id, cursor: .init(closedThrough: 0, outstanding: .pending(.init(pending: pending))))), requested: frame, now: 2_000)
        XCTAssertNil(state.frozen)
        XCTAssertEqual(state.recovery.count, 1)
        let reply = SyncReply(ownerKey: "owner-a", batchId: frame.batch.id, receipts: [.init(id: original.id, revision: original.revision, outcome: .preserved)])
        try state.settlePending(accepted(frame, reply: reply), requested: pending, now: 2_000)
        XCTAssertTrue(state.confirmed.isEmpty)
        XCTAssertEqual(state.acknowledgement?.digest, pending.digest)
    }

    private func date(_ seconds: Double) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func accepted(_ frame: SyncFrame, reply: SyncReply) -> SyncExchange {
        .accepted(.init(committed: .init(clientKey: frame.clientKey, sequence: frame.sequence, digest: "fixture-digest", revision: .init(saved: frame.sequence, position: frame.sequence), reply: reply)))
    }

    private func acknowledged(_ value: SyncAcknowledgement) -> SyncAckReply {
        .init(ownerKey: "owner-a", clientKey: value.clientKey, cursor: .init(closedThrough: value.sequence, outstanding: nil))
    }

    @MainActor private func settleFixture(_ reply: SyncReply, frame: SyncFrame, store: GuestDataStore, owner: LibrarySyncOwner) throws {
        try store.settleSyncExchange(accepted(frame, reply: reply), requested: frame, owner: owner)
    }

    @MainActor func testDeletionSurvivesResponseLossRestartAndIdentityFailureWithoutBootstrappingOrErasingOtherScopes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("deletion.store")
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        let other = LibrarySyncOwner(key: "owner-b", subject: "subject-b")
        let otherDeployment = LibrarySyncOwner(key: "owner-a", subject: "subject-a", namespace: "other-deployment")
        let session = LibrarySyncSession(id: "session-a", subject: owner.subject)
        var serverCalls = 0, identityCalls = 0
        let store = GuestDataStore(storeURL: url)
        store.addNote(hadithId: "target-a", content: "A original")
        try store.claimGuestForSync(owner)
        store.addNote(hadithId: "target-b", content: "B original")
        try store.claimGuestForSync(other); try store.claimGuestForSync(otherDeployment)
        func flow(_ store: GuestDataStore, loseResponse: Bool, failIdentity: Bool) -> LibraryAccountDeletion {
            .init(store: store, namespace: "fixture", currentSession: { session }, invalidate: {},
                prepare: { .init(subject: session.subject, authorization: "fixture", validUntil: Date.now.millisecondsSinceEpoch + 60_000) },
                erase: { _ in
                    serverCalls += 1
                    if loseResponse { throw NSError(domain: "response-loss-fixture", code: 1) }
                    return .init(subject: session.subject, deleted: false)
                }, cleanup: { _ in }, deleteIdentity: { _ in
                    identityCalls += 1
                    if failIdentity { throw NSError(domain: "identity-offline-fixture", code: 2) }
                })
        }
        do { try await flow(store, loseResponse: true, failIdentity: false).run(session); XCTFail("Lost response must retain pending phase") } catch { }
        XCTAssertEqual(serverCalls, 1); XCTAssertEqual(identityCalls, 0)
        XCTAssertEqual(try store.deletionPhase(subject: session.subject, namespace: "fixture"), .serverPending)
        XCTAssertNotNil(try store.syncPartition(owner))
        try await assertDeletionBlocksBootstrap(store, session: session)
        let reopened = GuestDataStore(storeURL: url)
        do { try await flow(reopened, loseResponse: false, failIdentity: true).run(session); XCTFail("Identity failure must remain retryable") } catch { }
        XCTAssertEqual(serverCalls, 2); XCTAssertEqual(identityCalls, 1)
        XCTAssertEqual(try reopened.deletionPhase(subject: session.subject, namespace: "fixture"), .identityPending)
        XCTAssertNil(try reopened.syncPartition(owner))
        XCTAssertNotNil(try reopened.syncPartition(other))
        XCTAssertNotNil(try reopened.syncPartition(otherDeployment))
        try await assertDeletionBlocksBootstrap(reopened, session: session)
        let final = GuestDataStore(storeURL: url)
        try await flow(final, loseResponse: false, failIdentity: false).run(session)
        XCTAssertEqual(serverCalls, 2, "Identity-only retry must not bootstrap or erase the server again")
        XCTAssertEqual(identityCalls, 2)
        XCTAssertNil(try final.deletionPhase(subject: session.subject, namespace: "fixture"))
        XCTAssertNotNil(try final.syncPartition(other))
    }

    @MainActor private func assertDeletionBlocksBootstrap(_ store: GuestDataStore, session: LibrarySyncSession) async throws {
        var opens = 0
        let transport = LibrarySyncTransport(namespace: "fixture", open: {
            opens += 1; throw NSError(domain: "must-not-bootstrap-fixture", code: 1)
        }, acknowledge: { _, _ in throw LibrarySyncFailure.invalidReceipt }, send: { _, _ in throw LibrarySyncFailure.invalidReceipt })
        let sync = LibrarySync(store: store, transport: transport, currentSession: { session })
        defer { sync.deactivate() }
        await sync.activate(session)
        XCTAssertEqual(opens, 0)
        XCTAssertEqual(sync.status, .failed)
        XCTAssertNil(sync.owner)
    }

    @MainActor func testDeletionRejectsWrongPreparationAndFinishesOnlyCapturedLocalErasureAfterSwitch() async throws {
        let store = GuestDataStore(inMemory: true)
        let a = LibrarySyncSession(id: "session-a", subject: "subject-a")
        let b = LibrarySyncSession(id: "session-b", subject: "subject-b")
        var current = a
        let ownerA = LibrarySyncOwner(key: "owner-a", subject: a.subject), ownerB = LibrarySyncOwner(key: "owner-b", subject: b.subject)
        store.addNote(hadithId: "target-a", content: "A original"); try store.claimGuestForSync(ownerA)
        store.addNote(hadithId: "target-b", content: "B original"); try store.claimGuestForSync(ownerB)
        var erases = 0, identities = 0
        var cleanups: [String] = []
        let wrong = LibraryAccountDeletion(store: store, namespace: "fixture", currentSession: { current }, invalidate: {},
            prepare: { .init(subject: b.subject, authorization: "wrong-owner-fixture", validUntil: Date.now.millisecondsSinceEpoch + 60_000) },
            erase: { _ in erases += 1; return .init(subject: b.subject, deleted: true) }, cleanup: { cleanups.append($0) }, deleteIdentity: { _ in identities += 1 })
        do { try await wrong.run(a); XCTFail("Wrong preparation subject accepted") } catch { }
        XCTAssertEqual(erases, 0); XCTAssertNotNil(try store.syncPartition(ownerA))
        let switched = LibraryAccountDeletion(store: store, namespace: "fixture", currentSession: { current }, invalidate: {},
            prepare: { .init(subject: a.subject, authorization: "owner-a-fixture", validUntil: Date.now.millisecondsSinceEpoch + 60_000) },
            erase: { _ in erases += 1; current = b; return .init(subject: a.subject, deleted: true) }, cleanup: { cleanups.append($0) }, deleteIdentity: { _ in identities += 1 })
        do { try await switched.run(a); XCTFail("Switched session must not delete an identity") } catch { }
        XCTAssertEqual(erases, 1); XCTAssertEqual(identities, 0); XCTAssertEqual(cleanups, [a.subject])
        XCTAssertNil(try store.syncPartition(ownerA)); XCTAssertNotNil(try store.syncPartition(ownerB))
        XCTAssertEqual(try store.deletionPhase(subject: a.subject, namespace: "fixture"), .identityPending)
        do { try await switched.run(a); XCTFail("Stale confirmation accepted") } catch { }
        XCTAssertEqual(erases, 1); XCTAssertEqual(identities, 0)
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

    func testInconsistentFrozenPayloadIsRetainedBeforeDispatchOrRetirement() throws {
        let original = LibraryLocalChange(command: .notePut(.init(hadithId: "target", content: "Original source fixture", createdAt: 1_000, updatedAt: 1_000)), at: 1_000, source: .account(nil))
        let different = SyncOperation(id: original.operation.id, revision: original.operation.revision, at: original.operation.at, command: .notePut(.init(hadithId: "target", content: "Different wire fixture", createdAt: 1_000, updatedAt: 1_000)))
        var state = LibraryPartitionState()
        let frozen = LibraryFrozenBatch(batch: .init(id: "inconsistent-payload", operations: [different]), changes: [original])
        state.frozen = frozen
        XCTAssertThrowsError(try state.freeze())
        XCTAssertEqual(state.frozen, frozen)
        let json = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        XCTAssertTrue(json.contains("Original source fixture")); XCTAssertTrue(json.contains("Different wire fixture"))
    }

    func testPreviouslyGuessedFrozenGuestMembershipClockRequiresFencedRecovery() {
        let draft = GuestSavedMembershipDraft(hadithId: "target", folderLocalId: "old-folder", updatedAt: nil)
        let guessed = LibraryLocalChange(command: .membershipPut(.init(hadithId: "target", folder: .local(.init(key: "old-folder")), mode: nil)), at: 9_000, source: .membership(draft))
        let old = LibraryFrozenBatch(batch: .init(id: "old-guessed", operations: [guessed.operation]), changes: [guessed])
        XCTAssertTrue(LibrarySyncAdmission.accepts(old.batch))
        XCTAssertFalse(LibrarySyncAdmission.accepts(old))
        let claim = LibraryLocalChange(command: .membershipPut(.init(hadithId: "target", folder: .local(.init(key: "old-folder")), mode: "claim_if_unset")), at: 0, source: .membership(draft))
        XCTAssertTrue(LibrarySyncAdmission.accepts(LibraryFrozenBatch(batch: .init(id: "new-claim", operations: [claim.operation]), changes: [claim])))
    }

    func testLegacyPayloadKeepsFolderClockSeparateFromLaterNoteEdits() {
        let id = "jn7fxd3z54153q9j13kmhgzkv18df2zd"
        let payload = GuestMergePlanner.makePayload(bookmarks: [], notes: [.init(hadithId: id, content: "Later note", createdAt: date(1), updatedAt: date(9))],
            folders: [.init(localId: "guest-folder", name: "Guest fixture", createdAt: date(1))],
            memberships: [.init(hadithId: id, folderLocalId: "guest-folder", updatedAt: date(2))])
        XCTAssertEqual(payload.savedItems.first?.updatedAt, 9_000)
        XCTAssertEqual(payload.savedItems.first?.folderUpdatedAt, 2_000)
    }

    @MainActor func testUndatedGuestMembershipUsesClaimOnlyAndDoesNotOptimisticallyReplaceCloudFolder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("undated-membership.store")
        let id = "jn7fxd3z54153q9j13kmhgzkv18df2zd"
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        do {
            let schema = Schema([GuestBookmark.self, GuestNote.self, GuestFavorite.self, GuestSavedFolder.self, GuestSavedMembership.self, GuestReadingProgress.self, GuestLibraryPartition.self, GuestAccountDeletion.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let context = ModelContext(container)
            context.insert(GuestBookmark(hadithId: id, createdAt: date(1)))
            context.insert(GuestSavedFolder(localId: "old-guest-folder", name: "Old guest folder", createdAt: date(9)))
            context.insert(GuestSavedMembership(hadithId: id, folderLocalId: "old-guest-folder", updatedAt: nil))
            try context.save()
        }
        let store = GuestDataStore(storeURL: url)
        try store.claimGuestForSync(owner)
        var state = try XCTUnwrap(store.syncPartition(owner))
        let change = try XCTUnwrap(state.pending.first { if case .membershipPut = $0.operation.command { true } else { false } })
        guard case .membershipPut(let value) = change.operation.command else { return XCTFail("Missing membership claim") }
        XCTAssertEqual(value.mode, "claim_if_unset")
        XCTAssertEqual(change.operation.at, 0)
        let hadith = SyncHadithSummary(_id: id, providerHadithId: "1", collectionSlug: "bukhari", collectionName: "Bukhari", volumeId: "1", arabicText: "نص", englishText: nil, referenceDisplay: "Bukhari 1")
        state.savedSnapshot = .init(ownerKey: owner.key, version: 1, folders: [.init(_id: "cloud-folder", name: "Cloud folder", createdAt: 1_000)], items: [.init(hadithId: id, createdAt: 1_000, updatedAt: 3_000, bookmarkCreatedAt: 1_000, favoriteCreatedAt: nil, noteContent: nil, noteCreatedAt: nil, noteUpdatedAt: nil, folderId: "cloud-folder", hadith: hadith)])
        XCTAssertEqual(LibraryProjection(state).items.first?.folderId, "cloud-folder")
        state.pending = []
        state.confirmed = [.init(change: change, outcome: .preserved, version: 2)]
        state.folderMappings["old-guest-folder"] = "accepted-guest-folder"
        XCTAssertEqual(LibraryProjection(state).items.first?.folderId, "accepted-guest-folder")
        state.confirmed = []
        XCTAssertEqual(LibraryProjection(state).items.first?.folderId, "cloud-folder")
        let batch = SyncBatch(id: "unversioned-rejected", operations: [change.operation])
        state.frozen = .init(batch: batch, changes: [change])
        let frame = SyncFrame(clientKey: state.clientKey, sequence: Double(state.nextSequence), batch: batch)
        let outcome = SyncOutcome.superseded(.init(reason: .unversionedCloud))
        try state.settle(accepted(frame, reply: .init(ownerKey: owner.key, batchId: batch.id, receipts: [.init(id: change.operation.id, revision: change.operation.revision, outcome: outcome)])), requested: frame, now: Date.now.millisecondsSinceEpoch)
        XCTAssertEqual(state.recovery, [.server(change, outcome)])
        XCTAssertEqual(LibraryProjection(state).items.first?.folderId, "cloud-folder")
        let reopened = try JSONDecoder().decode(LibraryPartitionState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(reopened.recovery, state.recovery)
    }

    @MainActor private func seedPartitionFixture(_ state: LibraryPartitionState, owner: LibrarySyncOwner, url: URL) throws {
        let schema = Schema([GuestBookmark.self, GuestNote.self, GuestFavorite.self, GuestSavedFolder.self, GuestSavedMembership.self, GuestReadingProgress.self, GuestLibraryPartition.self, GuestAccountDeletion.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let context = ModelContext(container)
        context.insert(GuestLibraryPartition(ownerKey: owner.storageKey, subject: owner.subject, stateData: try JSONEncoder().encode(state)))
        try context.save()
    }

    @MainActor func testCoordinatorContinuesAfterItsQuarantinePassBudgetWithoutSendingInvalidIntent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("quarantine.store")
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        let session = LibrarySyncSession(id: "session-a", subject: owner.subject)
        let rejected = (0..<401).map { _ in LibraryLocalChange(command: .notePut(.init(hadithId: "target", content: "", createdAt: 1_000, updatedAt: 1_000)), at: 1_000, source: .account(nil)) }
        let valid = LibraryLocalChange(command: .bookmarkAdd(.init(hadithId: "target", createdAt: 1_000)), at: 1_000, source: .account(nil))
        var state = LibraryPartitionState(); state.pending = rejected + [valid]
        try seedPartitionFixture(state, owner: owner, url: url)
        let store = GuestDataStore(storeURL: url)
        var sent: [SyncFrame] = []
        let transport = LibrarySyncTransport(namespace: "fixture", open: {
            .init(ownerKey: owner.key, subject: owner.subject, capability: "fixture", validUntil: Date.now.millisecondsSinceEpoch + 60_000)
        }, acknowledge: { _, proof in self.acknowledged(proof) }, send: { _, frame in
            sent.append(frame); XCTAssertEqual(frame.batch.operations, [valid.operation])
            return self.accepted(frame, reply: .init(ownerKey: owner.key, batchId: frame.batch.id, receipts: [.init(id: valid.operation.id, revision: valid.operation.revision, outcome: .preserved)]))
        })
        let sync = LibrarySync(store: store, transport: transport, currentSession: { session })
        defer { sync.deactivate() }
        await sync.activate(session)
        try await waitForLibrary { sync.status == .ready(recovered: 401) }
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(try store.syncPartition(owner)?.recovery, rejected.map { .rejected($0) })
        XCTAssertTrue(try store.syncPartition(owner)?.pending.isEmpty == true)
        XCTAssertNil(try store.syncPartition(owner)?.acknowledgement)
    }

    @MainActor func testLegacyFrozenInvalidFrameSurvivesLostRetirementResponseAndAllowsLaterIntent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("old-frozen.store")
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        let session = LibrarySyncSession(id: "session-a", subject: owner.subject)
        let invalid = LibraryLocalChange(command: .notePut(.init(hadithId: "target", content: String(repeating: "界", count: 8_001), createdAt: 1_000, updatedAt: 1_000)), at: 1_000, source: .account(nil))
        let valid = LibraryLocalChange(command: .bookmarkAdd(.init(hadithId: "target", createdAt: 1_000)), at: 1_000, source: .account(nil))
        var state = LibraryPartitionState()
        state.frozen = .init(batch: .init(id: "legacy-frozen", operations: [invalid.operation]), changes: [invalid])
        state.pending = [valid]
        try seedPartitionFixture(state, owner: owner, url: url)
        let store = GuestDataStore(storeURL: url)
        var retirements = 0
        var sent: [SyncFrame] = []
        let transport = LibrarySyncTransport(namespace: "fixture", open: {
            .init(ownerKey: owner.key, subject: owner.subject, capability: "fixture", validUntil: Date.now.millisecondsSinceEpoch + 60_000)
        }, acknowledge: { _, proof in self.acknowledged(proof) }, send: { _, frame in
            sent.append(frame)
            XCTAssertEqual(frame.batch.operations, [valid.operation])
            return self.accepted(frame, reply: .init(ownerKey: owner.key, batchId: frame.batch.id, receipts: frame.batch.operations.map { .init(id: $0.id, revision: $0.revision, outcome: .preserved) }))
        }, retireInvalid: { _, frame in
            retirements += 1
            XCTAssertEqual(frame.batch.id, "legacy-frozen")
            if retirements == 1 { throw NSError(domain: "lost-retirement-response-fixture", code: 1) }
            return .init(ownerKey: owner.key, clientKey: frame.clientKey, cursor: .init(closedThrough: frame.sequence, outstanding: nil))
        })
        let sync = LibrarySync(store: store, transport: transport, currentSession: { session })
        defer { sync.deactivate() }
        await sync.activate(session)
        XCTAssertEqual(retirements, 1); XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(try store.syncPartition(owner)?.frozen?.batch.id, "legacy-frozen")
        await sync.activate(session)
        try await waitForLibrary { (try? store.syncPartition(owner)?.frozen) == nil && sent.count == 1 }
        XCTAssertEqual(retirements, 2); XCTAssertEqual(sent.first?.sequence, 2)
        XCTAssertEqual(try store.syncPartition(owner)?.recovery, [.historical(invalid)])
        XCTAssertTrue(try store.syncPartition(owner)?.pending.isEmpty == true)
        XCTAssertNil(try store.syncPartition(owner)?.acknowledgement)
        let reopened = GuestDataStore(storeURL: url)
        XCTAssertEqual(try reopened.syncPartition(owner)?.recovery, [.historical(invalid)])
    }

    @MainActor func testRetirementCannotClearANewerFrozenFrameOrLoseAnOccupiedReceipt() throws {
        let invalid = LibraryLocalChange(command: .notePut(.init(hadithId: "target", content: "", createdAt: 1_000, updatedAt: 1_000)), at: 1_000, source: .account(nil))
        var state = LibraryPartitionState()
        state.frozen = .init(batch: .init(id: "invalid-frozen", operations: [invalid.operation]), changes: [invalid])
        let requested = try XCTUnwrap(state.freeze())
        let wrong = SyncAckReply(ownerKey: "owner-a", clientKey: "other-installation", cursor: .init(closedThrough: 1, outstanding: nil))
        XCTAssertThrowsError(try state.settleRetirement(wrong, requested: requested))
        let active = SyncCommitted(clientKey: state.clientKey, sequence: 1, digest: "committed-proof", revision: .init(saved: 1, position: 0), reply: .init(ownerKey: "owner-a", batchId: "other-committed-batch", receipts: []))
        try state.settleRetirement(.init(ownerKey: "owner-a", clientKey: state.clientKey, cursor: .init(closedThrough: 0, outstanding: .committed(.init(committed: active)))), requested: requested)
        XCTAssertEqual(state.recovery, [.historical(invalid)])
        XCTAssertEqual(state.acknowledgement?.digest, "committed-proof")
        let proof = try XCTUnwrap(state.acknowledgement)
        try state.settleAcknowledgement(.init(ownerKey: "owner-a", clientKey: state.clientKey, cursor: .init(closedThrough: 1, outstanding: nil)), requested: proof)
        state.pending = [.init(command: .bookmarkAdd(.init(hadithId: "target", createdAt: 1_000)), at: 1_000, source: .account(nil))]
        let next = try XCTUnwrap(state.freeze())
        XCTAssertEqual(next.sequence, 2)
        XCTAssertThrowsError(try state.settleRetirement(.init(ownerKey: "owner-a", clientKey: state.clientKey, cursor: .init(closedThrough: 1, outstanding: nil)), requested: requested))
        XCTAssertEqual(try state.freeze(), next)
    }

    @MainActor func testOneFreezeBoundsQuarantineWorkBeforeAValidLaterChange() throws {
        let rejected = (0..<101).map { _ in LibraryLocalChange(command: .notePut(.init(hadithId: "target", content: "", createdAt: 1_000, updatedAt: 1_000)), at: 1_000, source: .account(nil)) }
        let valid = LibraryLocalChange(command: .bookmarkAdd(.init(hadithId: "target", createdAt: 1_000)), at: 1_000, source: .account(nil))
        var state = LibraryPartitionState(); state.pending = rejected + [valid]
        XCTAssertNil(try state.freeze())
        XCTAssertEqual(state.recovery.count, LibrarySyncLimits.operations)
        XCTAssertEqual(state.pending.count, 52)
        XCTAssertNil(try state.freeze())
        let frame = try XCTUnwrap(state.freeze())
        XCTAssertEqual(frame.batch.operations, [valid.operation])
        XCTAssertEqual(state.recovery, rejected.map { .rejected($0) })
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
        let exchange = SyncExchange.reconcile(.init(ownerKey: owner.key, clientKey: frame.clientKey, requestedSequence: frame.sequence, requestedBatchId: frame.batch.id, cursor: .init(closedThrough: 5, outstanding: nil)))
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
                cursor: .init(closedThrough: 0, outstanding: .committed(.init(committed: .init(clientKey: frame.clientKey, sequence: 1, digest: "server-proof", revision: .init(saved: 1, position: 1), reply: .init(ownerKey: replyOwner, batchId: "other-batch", receipts: [.init(id: "other-intent", revision: "r1", outcome: .preserved)])))))))
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
            .init(ownerKey: String(capability.dropFirst("fixture:".count)), clientKey: value.clientKey, cursor: .init(closedThrough: value.sequence, outstanding: nil))
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
