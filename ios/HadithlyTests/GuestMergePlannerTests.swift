import XCTest
import ConvexMobile
import ClerkConvex
import ClerkKit
import Combine
import SwiftData
import SQLite3
import zlib
@testable import Hadithly

final class GuestMergePlannerTests: XCTestCase {
    @MainActor func testReaderScrollCoalescesAccountWritesAndFlushesExactFinalPosition() async throws {
        let fixture = LibraryFacadeFixture(store: GuestDataStore(inMemory: true))
        await fixture.start()
        defer { fixture.stop() }
        let reader = scrollingReader(library: fixture.model)
        defer { reader.stop() }
        var writes = 0
        fixture.sync.onPartitionChange = { owner in
            writes += 1
            fixture.model.partitionChanged(owner)
        }
        for step in 0...30 {
            reader.captureStableScroll(hadiths: reader.currentPageHadiths, leadingIndex: 0,
                rawPageOffset: Double(step * 30), normalizedOffset: Double(step) * 0.03)
        }
        XCTAssertLessThanOrEqual(writes, 1, "A single scrolling burst must not synchronously decode and persist the account partition for every capture")
        reader.saveCurrentProgress()
        XCTAssertLessThanOrEqual(writes, 2)
        let position = try XCTUnwrap(fixture.model.progress(for: "bukhari")?.position)
        XCTAssertEqual(position.rawPageOffset, 900)
        XCTAssertEqual(position.normalizedOffset, 0.9, accuracy: 0.00001)
        XCTAssertEqual(position.anchor.providerHadithId, "57")
        XCTAssertEqual(position.pageKey, "pg1:scroll-page")
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(fixture.model.progress(for: "bukhari")?.position, position, "A delayed capture must not overwrite the explicit final save")
    }

    @MainActor func testReaderScrollFlushesDuringContinuousReadingAndStop() async throws {
        let fixture = LibraryFacadeFixture(store: GuestDataStore(inMemory: true))
        await fixture.start()
        defer { fixture.stop() }
        let reader = scrollingReader(library: fixture.model)
        reader.captureStableScroll(hadiths: reader.currentPageHadiths, leadingIndex: 0, rawPageOffset: 0, normalizedOffset: 0)
        reader.captureStableScroll(hadiths: reader.currentPageHadiths, leadingIndex: 0, rawPageOffset: 400, normalizedOffset: 0.4)
        XCTAssertEqual(fixture.model.progress(for: "bukhari")?.position?.rawPageOffset, 0)
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(fixture.model.progress(for: "bukhari")?.position?.rawPageOffset, 400)
        reader.captureStableScroll(hadiths: reader.currentPageHadiths, leadingIndex: 0, rawPageOffset: 600, normalizedOffset: 0.6)
        reader.stop()
        XCTAssertEqual(fixture.model.progress(for: "bukhari")?.position?.rawPageOffset, 600)
    }

    @MainActor func testPendingReaderScrollCannotFollowAnAccountSwitch() async throws {
        let fixture = LibraryFacadeFixture(store: GuestDataStore(inMemory: true))
        await fixture.start()
        defer { fixture.stop() }
        let reader = scrollingReader(library: fixture.model)
        defer { reader.stop() }
        reader.captureStableScroll(hadiths: reader.currentPageHadiths, leadingIndex: 0, rawPageOffset: 0, normalizedOffset: 0)
        reader.captureStableScroll(hadiths: reader.currentPageHadiths, leadingIndex: 0, rawPageOffset: 700, normalizedOffset: 0.7)
        fixture.stop()
        fixture.session.value = .init(id: "session-b", subject: "subject-b")
        await fixture.start()
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertNil(fixture.model.progress(for: "bukhari"), "Deferred account A scroll must never enter account B")
    }

    @MainActor func testGuestScrollFlushesWhenReaderStops() throws {
        let library = UserLibraryModel(guestData: GuestDataStore(inMemory: true))
        library.refresh()
        let reader = scrollingReader(library: library)
        reader.captureStableScroll(hadiths: reader.currentPageHadiths, leadingIndex: 0, rawPageOffset: 0, normalizedOffset: 0)
        reader.captureStableScroll(hadiths: reader.currentPageHadiths, leadingIndex: 0, rawPageOffset: 500, normalizedOffset: 0.5)
        reader.stop()
        XCTAssertEqual(try XCTUnwrap(library.progress(for: "bukhari")?.position).rawPageOffset, 500)
    }

    @MainActor private func scrollingReader(library: UserLibraryModel) -> ReaderModel {
        let reader = ReaderModel(convex: ConvexClientWithAuth(deploymentUrl: "https://example.invalid", authProvider: ClerkConvexAuthProvider()),
            collectionSlug: "bukhari", collectionName: "Bukhari", language: "en", isSignedIn: { true }, library: library)
        let hadith = ReaderR6Round3FixtureHadith.hadith57
        reader.seedForUITest(volumes: [], selectedVolumeId: hadith.volumeId ?? "1")
        reader.seedPagesForUITest([ReaderPageResult(items: [hadith], page: 1, pageSize: 1, totalPages: 1, hasMore: false,
            contentVersion: "cv1:scroll-content", paginationVersion: 1, pageKey: "pg1:scroll-page")])
        return reader
    }

    @MainActor func testReopenedAccountWritersPreserveEachAcceptedCommand() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("clones.store"), owner = LibrarySyncOwner(key: "owner", subject: "subject")
        let initial = GuestDataStore(storeURL: url); try initial.claimGuestForSync(owner)
        let clones = (0..<8).map { _ in GuestDataStore(storeURL: url) }
        for clone in clones { XCTAssertNotNil(try clone.syncPartition(owner)) }
        let changes = (0..<8).map { LibraryLocalChange(command: .notePut(.init(hadithId: "target-\($0)", content: "Accepted original \($0)", createdAt: 1_000, updatedAt: 1_000)), at: 1_000, source: .account(nil)) }
        for (clone, change) in zip(clones, changes) { try clone.enqueueSyncChange(change, owner: owner) }
        XCTAssertEqual(try GuestDataStore(storeURL: url).syncPartition(owner)?.pending, changes)
        XCTAssertEqual(try initial.syncPartition(owner)?.pending, changes)
    }
    @MainActor func testAccountOnlyMutationInvalidatesExportFenceAndGuestMutationDoesNot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("clock.store"), owner = LibrarySyncOwner(key: "owner", subject: "subject")
        let store = GuestDataStore(storeURL: url); try store.claimGuestForSync(owner)
        let fence = try await store.prepareOutcomeExport(owner, isCurrent: { true })
        store.addBookmark(hadithId: "unclaimed-guest"); XCTAssertNoThrow(try store.validateOutcomeExport(fence))
        try GuestDataStore(storeURL: url).enqueueSyncChange(.init(command: .noteRemove(.init(hadithId: "target")), at: 1_000, source: .account(nil)), owner: owner)
        XCTAssertThrowsError(try store.validateOutcomeExport(fence))
    }
    @MainActor func testAccountAndAckMarkerRollbackTogetherOnClockExhaustion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("rollback.store")
        let (store, proof, ack) = try await acknowledgedRetentionFixture(count: 1, url: url, acknowledge: false)
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), before = try store.syncPartition(owner)
        let container = try ModelContainer(for: GuestDataStore.schema, configurations: [ModelConfiguration(schema: GuestDataStore.schema, url: url)])
        let setup = ModelContext(container); setup.autosaveEnabled = false
        let key = LibraryOutcomeBinding.hash([owner.namespace, owner.subject])
        let clock = try XCTUnwrap(setup.fetch(FetchDescriptor<GuestOutcomeClock>(predicate: #Predicate { $0.key == key })).first)
        let originalRevision = clock.revision
        // The journal's ACK bump succeeds; the account bump then exhausts this clock.
        clock.revision = 9_007_199_254_740_989; try setup.save()
        let fence = try await store.prepareOutcomeExport(owner, isCurrent: { true })
        XCTAssertThrowsError(try store.settleSyncAcknowledgement(acknowledged(ack), requested: ack, owner: owner, now: 2_000))
        let reopened = GuestDataStore(storeURL: url)
        XCTAssertEqual(try reopened.syncPartition(owner), before)
        XCTAssertNil(try reopened.outcomeEvidencePage(proof, owner: owner, start: 0).checkpoint.retention)
        XCTAssertNoThrow(try reopened.validateOutcomeExport(fence))
        clock.revision = originalRevision; try setup.save()
        try reopened.settleSyncAcknowledgement(acknowledged(ack), requested: ack, owner: owner, now: 9_000)
        XCTAssertEqual(try reopened.outcomeEvidencePage(proof, owner: owner, start: 0).checkpoint.retention?.acknowledgedAt, 9_000)
        XCTAssertNil(try reopened.syncPartition(owner)?.acknowledgement)
    }
    @MainActor func testClaimDoesNotResurrectCachedGuestAndLateOriginalSurvives() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("claim.store"), owner = LibrarySyncOwner(key: "owner", subject: "subject")
        let old = GuestDataStore(storeURL: url); old.addBookmark(hadithId: "before")
        XCTAssertEqual(old.bookmarkDrafts().map(\.hadithId), ["before"])
        try GuestDataStore(storeURL: url).claimGuestForSync(owner)
        XCTAssertTrue(old.bookmarkDrafts().isEmpty)
        old.addBookmark(hadithId: "late")
        let reopened = GuestDataStore(storeURL: url)
        XCTAssertEqual(reopened.bookmarkDrafts().map(\.hadithId), ["late"])
        XCTAssertEqual(try reopened.syncPartition(owner)?.pending.count, 1)
        try reopened.claimGuestForSync(owner); let state = try reopened.syncPartition(owner)
        try reopened.claimGuestForSync(owner); XCTAssertEqual(try reopened.syncPartition(owner), state)
        XCTAssertEqual(state?.pending.count, 2)
    }
    @MainActor func testLegacyAccountWithoutClockGainsPresentFenceAndNoOpDoesNotInvalidateIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.store"), owner = LibrarySyncOwner(key: "legacy", subject: "subject")
        let original = LibraryPartitionState()
        try seedPartitionFixture(original, owner: owner, url: url)
        let store = GuestDataStore(storeURL: url), fence = try await store.prepareOutcomeExport(owner, isCurrent: { true })
        if case .present = fence.version { } else { XCTFail("Existing account exported as empty") }
        XCTAssertNil(try store.freezeSyncFrame(owner)); try store.claimGuestForSync(owner)
        XCTAssertEqual(try store.syncPartition(owner), original); XCTAssertNoThrow(try store.validateOutcomeExport(fence))
    }
    @MainActor func testAmbiguousAccountKeysRejectBeforeCreationAndLateWritesRespectDeletion() throws {
        let store = GuestDataStore(inMemory: true), owner = LibrarySyncOwner(key: "owner", subject: "subject")
        XCTAssertThrowsError(try store.claimGuestForSync(.init(key: "bad|owner", subject: owner.subject)))
        try store.claimGuestForSync(owner); try store.beginDeletion(subject: owner.subject, namespace: owner.namespace)
        XCTAssertThrowsError(try store.enqueueSyncChange(.init(command: .noteRemove(.init(hadithId: "late")), at: 1_000, source: .account(nil)), owner: owner))
        XCTAssertThrowsError(try store.clearDeletion(subject: owner.subject, namespace: owner.namespace))
        XCTAssertEqual(try store.deletionPhase(subject: owner.subject, namespace: owner.namespace), .serverPending)
    }
    @MainActor func testRowObservationBlocksLegacyHighVersionsAcrossAllFourConsumers() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("observation.store"), store = GuestDataStore(storeURL: url)
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        try store.claimGuestForSync(owner); let lease = try store.beginSavedAssembly(owner)
        let container = try ModelContainer(for: GuestDataStore.schema, configurations: [ModelConfiguration(schema: GuestDataStore.schema, url: url)])
        let edit = ModelContext(container); edit.autosaveEnabled = false
        let header = try XCTUnwrap(edit.fetch(FetchDescriptor<GuestSavedAssembly>()).first); header.rowMode = true; try edit.save()
        try store.enqueueSyncChange(.init(command: .noteRemove(.init(hadithId: "note-target")), at: 1_000, source: .account(nil)), owner: owner)
        let note = try XCTUnwrap(store.freezeSyncFrame(owner)), operation = note.batch.operations[0]
        let noteProof = SyncCommitted(clientKey: note.clientKey, sequence: note.sequence, digest: "note-proof", revision: .init(saved: 2, position: 0), reply: .init(ownerKey: owner.key, batchId: note.batch.id, receipts: [.init(id: operation.id, revision: operation.revision, outcome: .preserved)]))
        try store.settleSyncExchange(.accepted(.init(committed: noteProof)), requested: note, owner: owner)
        try store.cacheSavedSnapshot(.init(ownerKey: owner.key, version: 999, folders: [], items: []), owner: owner)
        try store.cachePositionsSnapshot(.init(ownerKey: owner.key, version: 999, rows: []), owner: owner)
        XCTAssertEqual(try store.syncPartition(owner)?.confirmed.count, 1)
        let noteAck = try XCTUnwrap(store.syncPartition(owner)?.acknowledgement)
        try store.settleSyncAcknowledgement(acknowledged(noteAck), requested: noteAck, owner: owner)
        try store.enqueueSyncChange(.init(command: .folderDelete(.init(folder: .server(.init(id: "folder")))), at: 1_000, source: .account(nil)), owner: owner)
        let frame = try XCTUnwrap(store.freezeSyncFrame(owner)), deletion = frame.batch.operations[0]
        let proof = SyncCommitted(clientKey: frame.clientKey, sequence: frame.sequence, digest: "delete-proof", revision: .init(saved: 3, position: 0), reply: .init(ownerKey: owner.key, batchId: frame.batch.id, receipts: [.init(id: deletion.id, revision: deletion.revision, outcome: .folderDeletedManifest(.init(manifestId: "manifest", generation: "generation", count: 1, deletedAt: 1_000)))]))
        try store.settleSyncExchange(.accepted(.init(committed: proof)), requested: frame, owner: owner)
        try await collectExportFacts(proof, owner: owner, count: 1, store: store)
        let hadith = SyncHadithSummary(_id: "hadith-0", providerHadithId: "1", collectionSlug: "bukhari", collectionName: "Bukhari", volumeId: "1", arabicText: "نص", englishText: nil, referenceDisplay: "Bukhari 1")
        try store.cacheSavedSnapshot(.init(ownerKey: owner.key, version: 1_000, folders: [.init(_id: "folder", name: "Old joined folder", createdAt: 1_000)], items: [.init(hadithId: "hadith-0", createdAt: 1_000, updatedAt: 1_000, bookmarkCreatedAt: 1_000, favoriteCreatedAt: nil, noteContent: nil, noteCreatedAt: nil, noteUpdatedAt: nil, folderId: "folder", hadith: hadith)]), owner: owner)
        let pending = try XCTUnwrap(store.syncPartition(owner)?.collectingOutcome)
        XCTAssertEqual(try store.settleCollectedOutcome(pending, owner: owner, now: 2_000), .awaitingSaved)
        XCTAssertTrue(try store.libraryProjection(owner).folders.isEmpty)
        XCTAssertNil(try store.libraryProjection(owner).items.first?.folderId)
        try await prepareSaved(store, lease: lease, facts: [], version: 2); _ = try await activateSaved(store, lease)
        try store.cachePositionsSnapshot(.init(ownerKey: owner.key, version: 1_000, rows: []), owner: owner)
        XCTAssertTrue(try XCTUnwrap(store.syncPartition(owner)).confirmed.isEmpty)
        XCTAssertEqual(try store.settleCollectedOutcome(pending, owner: owner, now: 2_000), .awaitingSaved)
        XCTAssertTrue(try store.libraryProjection(owner).folders.isEmpty)
        let next = try store.beginSavedAssembly(owner); try await prepareSaved(store, lease: next, facts: [], version: 3); _ = try await activateSaved(store, next)
        XCTAssertEqual(try store.settleCollectedOutcome(pending, owner: owner, now: 2_000), .settled)
        XCTAssertNotNil(try GuestDataStore(storeURL: url).syncPartition(owner)?.acknowledgement)
    }
    @MainActor func testRowObservationUnavailablePreservesAcknowledgedEvidenceUntilActive() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("retention.store")
        let (store, proof, _) = try await acknowledgedRetentionFixture(count: 1, url: url)
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), lease = try store.beginSavedAssembly(owner)
        let container = try ModelContainer(for: GuestDataStore.schema, configurations: [ModelConfiguration(schema: GuestDataStore.schema, url: url)])
        let db = ModelContext(container); let header = try XCTUnwrap(db.fetch(FetchDescriptor<GuestSavedAssembly>()).first)
        header.rowMode = true; try db.save()
        let now = 2_000 + LibraryOutcomeRetention.duration
        _ = try store.pruneOutcomeSuccessStep(owner, now: now)
        XCTAssertEqual(try store.outcomeEvidencePage(proof, owner: owner, start: 0).rows.count, 1)
        try await prepareSaved(store, lease: lease, facts: [], version: 2); _ = try await activateSaved(store, lease)
        for _ in 0..<4 { _ = try store.pruneOutcomeSuccessStep(owner, now: now) }
        XCTAssertThrowsError(try store.outcomeEvidencePage(proof, owner: owner, start: 0))
    }
    func testEverySavedConsumerRejectsForeignObservationWithoutMutation() throws {
        var state = LibraryPartitionState()
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), originalProof = outcomeProof(.init(key: "owner-a", subject: "subject-a"), count: 1)
        let proof = SyncCommitted(clientKey: state.clientKey, sequence: originalProof.sequence, digest: originalProof.digest, revision: originalProof.revision, reply: originalProof.reply)
        let binding = try LibraryOutcomeBinding(owner: owner, committed: proof)
        let pending = LibraryPendingOutcome(committed: proof, origin: .historical)
        let checkpoint = LibraryOutcomeCheckpoint(counts: binding.expected, status: .complete, retention: .init(acknowledgedAt: 2_000, removed: nil))
        state.collectingOutcome = pending
        state.savedSnapshot = .init(ownerKey: owner.key, version: 999, folders: [], items: [])
        let before = state
        for peer in [LibrarySyncOwner(key: owner.key, subject: "another-subject"), LibrarySyncOwner(key: owner.key, subject: owner.subject, namespace: "another-deployment")] {
            let foreign = try LibrarySavedObservation.legacy(peer, snapshot: .init(ownerKey: peer.key, version: 999, folders: [], items: []))
            XCTAssertThrowsError(try state.projectedFrozenChanges(owner: owner, observed: foreign))
            XCTAssertThrowsError(try state.pruneConfirmed(owner: owner, observed: foreign)); XCTAssertEqual(state, before)
            XCTAssertThrowsError(try state.settleCollectedOutcome(pending, binding: binding, checkpoint: checkpoint, observed: foreign, now: 2_000)); XCTAssertEqual(state, before)
            XCTAssertThrowsError(try state.canPruneOutcome(binding, checkpoint: checkpoint, observed: foreign, now: 2_000 + LibraryOutcomeRetention.duration))
        }
    }
    @MainActor func testViewAuditResumesVerifiesWholeCompiledSnapshotAndInvalidatesOnWrite() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("audit.store"), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        var store = GuestDataStore(storeURL: url); try store.claimGuestForSync(owner); let scope = try store.beginSavedAssembly(owner), state = viewState(owner, count: 2_001)
        let source = try LibrarySavedViewPolicy.captureLegacy(state, owner: owner, observed: observation(state))
        var stamp = try store.createSavedViewRows(scope)
        for start in stride(from: 0, to: source.items.count, by: 8) { stamp = try store.writeSavedViewRows(stamp, items: Array(source.items[start..<min(start + 8, source.items.count)])) }
        for start in stride(from: 0, to: source.folders.count, by: 8) { stamp = try store.writeSavedViewRows(stamp, items: [], folders: Array(source.folders[start..<min(start + 8, source.folders.count)])) }
        let manifest = try LibrarySavedViewManifest.make(stamp.identity, source: source)
        var audit = try store.beginSavedViewAudit(stamp, manifest: manifest), steps = 0
        while audit.phase != .verified {
            let previous = audit; audit = try autoreleasepool { try store.savedViewAuditStep(stamp) }
            XCTAssertLessThanOrEqual(audit.items + audit.folders - previous.items - previous.folders, 8); XCTAssertLessThanOrEqual(audit.indexes - previous.indexes, 128); steps += 1
            if steps % 17 == 0 { store = GuestDataStore(storeURL: url); XCTAssertEqual(try store.savedViewAudit(stamp), audit) }
            guard steps < 1_000 else { return XCTFail("Audit did not finish") }
        }
        XCTAssertEqual(audit.items, 2_001); XCTAssertEqual(audit.folders, 70); XCTAssertEqual(audit.indexes, manifest.indexes); XCTAssertEqual(audit.digest, manifest.digest)
        XCTAssertEqual(try store.beginSavedViewAudit(stamp, manifest: manifest), audit)
        let fence = try await store.prepareOutcomeExport(owner, isCurrent: { true }); XCTAssertEqual(try store.savedViewAuditStep(stamp), audit); XCTAssertNoThrow(try store.validateOutcomeExport(fence))
        let old = stamp; stamp = try store.writeSavedViewRows(stamp, items: [source.items[0]])
        XCTAssertNil(try store.savedViewAudit(stamp)); XCTAssertThrowsError(try store.savedViewAudit(old)); XCTAssertNil(try store.activeSavedGeneration(owner))
        let container = try ModelContainer(for: GuestDataStore.schema, configurations: [ModelConfiguration(schema: GuestDataStore.schema, url: url)])
        XCTAssertFalse(try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<GuestSavedAssembly>()).first).rowMode)
    }
    @MainActor func testViewAuditRejectsMissingRowsIndexesExtraIndexesWrongTargetsAndPayloadChanges() throws {
        for damage in ["missing-row", "missing-index", "extra-index", "wrong-target", "payload", "empty"] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("damaged.store"), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), store = GuestDataStore(storeURL: url)
            try store.claimGuestForSync(owner); let scope = try store.beginSavedAssembly(owner), state = viewState(owner, count: 2)
            let compiled = try LibrarySavedViewPolicy.captureLegacy(state, owner: owner, observed: observation(state)), source = LibrarySavedViewSnapshot(items: compiled.items, folders: [])
            var stamp = try store.createSavedViewRows(scope)
            if damage != "empty" { stamp = try store.writeSavedViewRows(stamp, items: source.items) }
            let identity = stamp.identity, manifest = try LibrarySavedViewManifest.make(identity, source: source)
            _ = try store.beginSavedViewAudit(stamp, manifest: manifest)
            let container = try ModelContainer(for: GuestDataStore.schema, configurations: [ModelConfiguration(schema: GuestDataStore.schema, url: url)]), setup = ModelContext(container)
            setup.autosaveEnabled = false
            let indexes = try setup.fetch(FetchDescriptor<GuestSavedViewIndex>()), rows = try setup.fetch(FetchDescriptor<GuestSavedViewRow>())
            switch damage {
            case "missing-row": setup.delete(try XCTUnwrap(rows.first))
            case "missing-index": setup.delete(try XCTUnwrap(indexes.first))
            case "extra-index": setup.insert(GuestSavedViewIndex(identity, key: identity.key + ":extra", target: try XCTUnwrap(indexes.first).targetKey))
            case "wrong-target": for index in indexes { index.targetKey = "wrong" }
            case "payload":
                let row = try XCTUnwrap(rows.first); var item = try JSONDecoder().decode(LibrarySavedViewItem.self, from: row.data); let value = item.value
                item.value = .init(hadithId: value.hadithId, createdAt: 999, updatedAt: value.updatedAt, bookmarkCreatedAt: value.bookmarkCreatedAt, favoriteCreatedAt: value.favoriteCreatedAt, noteContent: value.noteContent, noteCreatedAt: value.noteCreatedAt, noteUpdatedAt: value.noteUpdatedAt, folderId: value.folderId, folderUpdatedAt: value.folderUpdatedAt)
                row.data = try JSONEncoder().encode(item); row.fingerprint = try LibrarySemanticFingerprint.digest(JSONDecoder().decode(LibraryExportValue.self, from: row.data), domain: "saved-view-row-v1:")
            default: break
            }
            try setup.save()
            var rejected = false
            do { for _ in 0..<20 { let audit = try store.savedViewAuditStep(stamp); if audit.phase == .verified { XCTFail("Corrupt \(damage) draft verified"); break } } } catch { rejected = true }
            XCTAssertTrue(rejected, "Corrupt \(damage) draft did not reject"); XCTAssertNotEqual(try store.savedViewAudit(stamp)?.phase, .verified)
        }
    }
    @MainActor func testViewDiscardIsBoundedDurableAndCannotExposePartialEmptyOrConsumeAnotherDraft() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("discard.store"), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        var store = GuestDataStore(storeURL: url); try store.claimGuestForSync(owner); let scope = try store.beginSavedAssembly(owner), state = viewState(owner, count: 97)
        let compiled = try LibrarySavedViewPolicy.captureLegacy(state, owner: owner, observed: observation(state)), source = LibrarySavedViewSnapshot(items: compiled.items, folders: [])
        var stamp = try store.createSavedViewRows(scope)
        for start in stride(from: 0, to: source.items.count, by: 8) { stamp = try store.writeSavedViewRows(stamp, items: Array(source.items[start..<min(start + 8, source.items.count)])) }
        let peer = try store.writeSavedViewRows(store.createSavedViewRows(scope), items: [source.items[0]]); _ = try store.createSavedViewRows(scope)
        XCTAssertThrowsError(try store.createSavedViewRows(scope))
        let initialAudit = try store.beginSavedViewAudit(stamp, manifest: LibrarySavedViewManifest.make(stamp.identity, source: source))
        let container = try ModelContainer(for: GuestDataStore.schema, configurations: [ModelConfiguration(schema: GuestDataStore.schema, url: url)]), setup = ModelContext(container)
        setup.autosaveEnabled = false
        let clock = try XCTUnwrap(setup.fetch(FetchDescriptor<GuestOutcomeClock>()).first), revision = clock.revision
        clock.revision = 9_007_199_254_740_990; try setup.save()
        let fence = try await store.prepareOutcomeExport(owner, isCurrent: { true })
        XCTAssertThrowsError(try store.savedViewAuditStep(stamp)); XCTAssertEqual(try store.savedViewAudit(stamp), initialAudit); XCTAssertNoThrow(try store.validateOutcomeExport(fence))
        XCTAssertThrowsError(try store.discardSavedViewStep(stamp)); XCTAssertEqual(try store.draftSavedViewStamp(stamp.identity), stamp); XCTAssertNoThrow(try store.validateOutcomeExport(fence))
        clock.revision = revision; try setup.save()
        var steps = 0, more: Bool
        repeat {
            let before = ModelContext(container), oldIndexes = try before.fetchCount(FetchDescriptor<GuestSavedViewIndex>()), oldRows = try before.fetchCount(FetchDescriptor<GuestSavedViewRow>())
            more = try store.discardSavedViewStep(stamp)
            let after = ModelContext(container)
            XCTAssertLessThanOrEqual(oldIndexes - (try after.fetchCount(FetchDescriptor<GuestSavedViewIndex>())), 128); XCTAssertLessThanOrEqual(oldRows - (try after.fetchCount(FetchDescriptor<GuestSavedViewRow>())), 8)
            if more { XCTAssertThrowsError(try store.draftSavedViewPage(stamp, selection: .init())); XCTAssertThrowsError(try store.writeSavedViewRows(stamp, items: [source.items[0]])) }
            XCTAssertEqual(try store.draftSavedViewItem(peer, target: source.items[0].value.hadithId), source.items[0])
            store = GuestDataStore(storeURL: url); steps += 1; guard steps < 100 else { return XCTFail("Discard did not finish") }
        } while more
        let after = try await store.prepareOutcomeExport(owner, isCurrent: { true }); XCTAssertFalse(try store.discardSavedViewStep(stamp)); XCTAssertNoThrow(try store.validateOutcomeExport(after))
        let empty = try store.createSavedViewRows(scope); XCTAssertNotEqual(empty.identity, stamp.identity)
        _ = try store.beginSavedViewAudit(empty, manifest: LibrarySavedViewManifest.make(empty.identity, source: .init(items: [], folders: [])))
        XCTAssertEqual(try store.savedViewAuditStep(empty).phase, .indexes); XCTAssertEqual(try store.savedViewAuditStep(empty).phase, .verified)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<GuestSavedViewRow>()), 1)
    }
    private func viewFacts(_ state: LibraryPartitionState) throws -> [SavedFact] {
        let snapshot = try XCTUnwrap(state.savedSnapshot)
        return snapshot.folders.enumerated().map { i, folder in .folder(.init(sourceId: folder._id, ordinal: Double(i), value: folder)) } + snapshot.items.enumerated().map { i, row in .item(.init(sourceId: row.hadithId, ordinal: Double(snapshot.folders.count + i), value: .init(hadithId: row.hadithId, createdAt: row.createdAt, updatedAt: row.updatedAt, bookmarkCreatedAt: row.bookmarkCreatedAt, favoriteCreatedAt: row.favoriteCreatedAt, noteContent: row.noteContent, noteCreatedAt: row.noteCreatedAt, noteUpdatedAt: row.noteUpdatedAt, folderId: row.folderId, folderUpdatedAt: nil))) }
    }
    @MainActor func testViewBuildCompilesPrivateGenerationCatchesUpUndoAndResumesWithoutPublishing() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("builder.store"), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        var store = GuestDataStore(storeURL: url); try store.claimGuestForSync(owner); let state = viewState(owner, count: 2_001)
        try store.cacheSavedSnapshot(XCTUnwrap(state.savedSnapshot), owner: owner)
        let lease = try store.beginSavedAssembly(owner); try await prepareSaved(store, lease: lease, facts: viewFacts(state))
        let deletion = LibraryLocalChange(command: .folderDelete(.init(folder: .server(.init(id: "folder-1")))), at: 5_000, source: .account(nil))
        try store.enqueueSyncChange(deletion, owner: owner)
        try store.enqueueSyncChange(.init(command: .membershipPut(.init(hadithId: "target-1999", folder: .server(.init(id: "folder-4")), mode: nil)), at: 6_000, source: .account(nil)), owner: owner)
        var session = try store.beginSavedViewBuild(lease), record = try store.savedViewBuildProgress(session).1
        while record.phase != .items { record = try store.advanceSavedViewBuild(session) }
        for _ in 0..<3 { record = try store.advanceSavedViewBuild(session) }
        try store.enqueueSyncChange(.init(command: .folderRestore(.init(deletionId: deletion.operation.id, name: "Folder 1", hadithIds: [])), at: 7_000, source: .account(nil)), owner: owner)
        try store.enqueueSyncChange(.init(command: .notePut(.init(hadithId: "new-target", content: "Accepted during build", createdAt: 8_000, updatedAt: 8_000)), at: 8_000, source: .account(nil)), owner: owner)
        try store.enqueueSyncChange(.init(command: .bookmarkRemove(.init(hadithId: "target-0")), at: 9_000, source: .account(nil)), owner: owner)
        try store.enqueueSyncChange(.init(command: .facetRestore(.init(hadithId: "target-0", deletionId: "original", value: .bookmark(.init(createdAt: 1_000)))), at: 10_000, source: .account(nil)), owner: owner)
        XCTAssertThrowsError(try store.advanceSavedViewBuild(session))
        session = try store.captureSavedViewBuild(session.identity); record = try store.savedViewBuildProgress(session).1; XCTAssertEqual(record.phase, .folderCommands)
        var steps = 0
        while record.phase != .prepared {
            record = try autoreleasepool { try store.advanceSavedViewBuild(session) }; steps += 1
            if steps % 43 == 0 { store = GuestDataStore(storeURL: url); session = try store.captureSavedViewBuild(session.identity) }
            guard steps < 2_000 else { return XCTFail("Builder did not finish") }
        }
        let stamp = try store.savedViewBuildProgress(session).0, current = try XCTUnwrap(store.syncPartition(owner))
        let expected = try LibrarySavedViewPolicy.captureLegacy(current, owner: owner, observed: observation(current))
        var actual: [LibrarySavedViewItem] = [], ticket: LibrarySavedViewTicket?
        repeat { let page = try store.draftSavedViewPage(stamp, selection: .init(), ticket: ticket); actual.append(contentsOf: page.items); ticket = page.next } while ticket != nil
        XCTAssertEqual(actual, expected.items); XCTAssertEqual(actual.count, 2_002)
        XCTAssertEqual(try store.draftSavedViewItem(stamp, target: "target-1999")?.value.folderId, "folder-4")
        XCTAssertEqual(try store.draftSavedViewItem(stamp, target: "target-0")?.value.createdAt, 1_000)
        XCTAssertEqual(try store.savedViewAudit(stamp)?.phase, .verified); XCTAssertNil(try store.activeSavedGeneration(owner)); XCTAssertEqual(current.pending.count, 6)
    }
    @MainActor func testViewBuildUsesActualPrivateVersionAndRefreshesNeutralQueueChangesButRejectsRebase() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("cut.store"), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), store = GuestDataStore(storeURL: url)
        try store.claimGuestForSync(owner); let legacy = try XCTUnwrap(viewState(owner, count: 1).savedSnapshot)
        try store.cacheSavedSnapshot(.init(ownerKey: owner.key, version: 999, folders: legacy.folders, items: legacy.items), owner: owner)
        let lease = try store.beginSavedAssembly(owner); try await prepareSaved(store, lease: lease, facts: [])
        let container = try ModelContainer(for: GuestDataStore.schema, configurations: [ModelConfiguration(schema: GuestDataStore.schema, url: url)]), setup = ModelContext(container)
        let row = try XCTUnwrap(setup.fetch(FetchDescriptor<GuestLibraryPartition>()).first); var state = try JSONDecoder().decode(LibraryPartitionState.self, from: row.stateData)
        state.confirmed = [
            .init(change: .init(command: .notePut(.init(hadithId: "covered", content: "Already observed", createdAt: 1, updatedAt: 1)), at: 1, source: .account(nil)), outcome: .preserved, version: 9),
            .init(change: .init(command: .notePut(.init(hadithId: "not-covered", content: "Retain me", createdAt: 2, updatedAt: 2)), at: 2, source: .account(nil)), outcome: .preserved, version: 10)]
        row.stateData = try JSONEncoder().encode(state); row.revision += 1; try setup.save()
        try store.enqueueSyncChange(.init(command: .bookmarkAdd(.init(hadithId: "pending", createdAt: 3)), at: 3, source: .account(nil)), owner: owner)
        let old = try store.beginSavedViewBuild(lease); _ = try store.advanceSavedViewBuild(old); _ = try store.freezeSyncFrame(owner)
        XCTAssertThrowsError(try store.advanceSavedViewBuild(old)); let session = try store.captureSavedViewBuild(old.identity)
        var record = try store.savedViewBuildProgress(session).1
        while record.phase != .prepared { record = try store.advanceSavedViewBuild(session) }
        let stamp = try store.savedViewBuildProgress(session).0
        XCTAssertNil(try store.draftSavedViewItem(stamp, target: "covered")); XCTAssertNil(try store.draftSavedViewItem(stamp, target: "target-0"))
        XCTAssertEqual(try store.draftSavedViewItem(stamp, target: "not-covered")?.value.noteContent, "Retain me"); XCTAssertNotNil(try store.draftSavedViewItem(stamp, target: "pending"))
        let fresh = ModelContext(container), partition = try XCTUnwrap(fresh.fetch(FetchDescriptor<GuestLibraryPartition>()).first)
        var changed = try JSONDecoder().decode(LibraryPartitionState.self, from: partition.stateData); changed.folderMappings = ["new-alias": "server-folder"]
        partition.stateData = try JSONEncoder().encode(changed); partition.revision += 1; try fresh.save()
        XCTAssertThrowsError(try store.captureSavedViewBuild(old.identity)); XCTAssertNotNil(try store.draftSavedViewItem(stamp, target: "pending")); XCTAssertEqual(try store.syncPartition(owner)?.frozen?.changes.count, 1)
    }
    @MainActor func testViewBuildCursorRowsIndexesAndClockRollbackTogether() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("rollback-build.store"), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), store = GuestDataStore(storeURL: url)
        try store.claimGuestForSync(owner); let lease = try store.beginSavedAssembly(owner)
        try await prepareSaved(store, lease: lease, facts: [.folder(.init(sourceId: "folder", ordinal: 0, value: .init(_id: "folder", name: "Private folder", createdAt: 1)))])
        let active = try await activateSaved(store, lease); _ = try store.beginSavedAssembly(owner)
        XCTAssertEqual(try store.activeSavedGeneration(owner), active)
        try store.enqueueSyncChange(.init(command: .folderDelete(.init(folder: .server(.init(id: "folder")))), at: 2, source: .account(nil)), owner: owner)
        let session = try store.beginSavedViewBuild(lease), before = try store.savedViewBuildProgress(session)
        let container = try ModelContainer(for: GuestDataStore.schema, configurations: [ModelConfiguration(schema: GuestDataStore.schema, url: url)]), setup = ModelContext(container)
        let clock = try XCTUnwrap(setup.fetch(FetchDescriptor<GuestOutcomeClock>()).first), revision = clock.revision; clock.revision = 9_007_199_254_740_990; try setup.save()
        let fence = try await store.prepareOutcomeExport(owner, isCurrent: { true })
        XCTAssertThrowsError(try store.advanceSavedViewBuild(session)); XCTAssertEqual(try store.savedViewBuildProgress(session).0, before.0); XCTAssertEqual(try store.savedViewBuildProgress(session).1, before.1)
        let read = ModelContext(container); XCTAssertEqual(try read.fetchCount(FetchDescriptor<GuestSavedViewRow>()), 0); XCTAssertEqual(try read.fetchCount(FetchDescriptor<GuestSavedViewIndex>()), 0); XCTAssertNoThrow(try store.validateOutcomeExport(fence))
        clock.revision = revision; try setup.save(); _ = try store.advanceSavedViewBuild(session)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<GuestSavedViewRow>()), 1)
        let stale = try store.captureSavedViewBuild(session.identity)
        let base = try store.savedViewBuildProgress(session)
        clock.revision = 9_007_199_254_740_990; try setup.save()
        let checkpointFence = try await store.prepareOutcomeExport(owner, isCurrent: { true })
        XCTAssertThrowsError(try store.advanceSavedViewBuild(session)); XCTAssertEqual(try store.savedViewBuildProgress(session).0, base.0); XCTAssertEqual(try store.savedViewBuildProgress(session).1, base.1)
        XCTAssertTrue(session.bindings.isEmpty); XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<GuestSavedViewRow>()), 1); XCTAssertNoThrow(try store.validateOutcomeExport(checkpointFence))
        clock.revision = revision; try setup.save()
        let partition = try XCTUnwrap(setup.fetch(FetchDescriptor<GuestLibraryPartition>()).first), original = partition.stateData
        partition.stateData = Data([0]); try setup.save()
        do { _ = try store.advanceSavedViewBuild(session) } catch { partition.stateData = original; try setup.save(); throw error }
        partition.stateData = original; try setup.save()
        XCTAssertEqual(session.bindings.count, 1); XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<GuestSavedViewRow>()), 0)
        XCTAssertThrowsError(try store.advanceSavedViewBuild(stale)); _ = try store.advanceSavedViewBuild(store.captureSavedViewBuild(stale.identity))
        let revisionBeforePoison = partition.revision; partition.revision = -1; try setup.save()
        XCTAssertThrowsError(try store.enqueueSyncChange(.init(command: .bookmarkRemove(.init(hadithId: "unadmitted")), at: 3, source: .account(nil)), owner: owner))
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<GuestLibraryPartition>()).first?.stateData, original)
        partition.revision = revisionBeforePoison; try setup.save()
    }
    @MainActor private func finishViewBuild(_ store: GuestDataStore, lease: LibrarySavedLease) throws -> LibrarySavedBuildSession {
        let session = try store.beginSavedViewBuild(lease)
        for _ in 0..<2_000 { if try store.advanceSavedViewBuild(session).phase == .prepared { return session } }; throw LibrarySyncFailure.storeUnavailable
    }
    @MainActor private func finishCapturedViewBuild(_ store: GuestDataStore, identity: LibrarySavedViewIdentity) throws -> LibrarySavedBuildSession {
        let session = try store.captureSavedViewBuild(identity)
        for _ in 0..<2_000 { if try store.advanceSavedViewBuild(session).phase == .prepared { return session } }; throw LibrarySyncFailure.storeUnavailable
    }
    private func canonicalNote(_ text: String) -> SavedFact { .item(.init(sourceId: "target", ordinal: 0, value: .init(hadithId: "target", createdAt: 1, updatedAt: 1, bookmarkCreatedAt: nil, favoriteCreatedAt: nil, noteContent: text, noteCreatedAt: 1, noteUpdatedAt: 1, folderId: nil, folderUpdatedAt: nil))) }
    @MainActor private func seedConfirmedForPublication(_ url: URL, owner: LibrarySyncOwner, version: Double) throws {
        let container = try ModelContainer(for: GuestDataStore.schema, configurations: [ModelConfiguration(schema: GuestDataStore.schema, url: url)]), db = ModelContext(container), key = owner.storageKey
        let row = try XCTUnwrap(db.fetch(FetchDescriptor<GuestLibraryPartition>(predicate: #Predicate { $0.ownerKey == key })).first)
        var state = try JSONDecoder().decode(LibraryPartitionState.self, from: row.stateData)
        state.confirmed.append(.init(change: .init(command: .notePut(.init(hadithId: "target", content: "Covered original", createdAt: 1, updatedAt: 1)), at: 1, source: .account(nil)), outcome: .preserved, version: version))
        row.stateData = try JSONEncoder().encode(state); row.revision += 1; try db.save()
    }
    @MainActor func testPublicationSwitchesPrivateViewModeAndQueueTogetherThenRetiresOldViews() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("publication.store"), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), store = GuestDataStore(storeURL: url)
        try store.claimGuestForSync(owner); let state = viewState(owner, count: 67); try store.cacheSavedSnapshot(XCTUnwrap(state.savedSnapshot), owner: owner)
        let source = try store.beginSavedAssembly(owner); try await prepareSaved(store, lease: source, facts: viewFacts(state)); try seedConfirmedForPublication(url, owner: owner, version: 9)
        let deletion = LibraryLocalChange(command: .folderDelete(.init(folder: .server(.init(id: "folder-1")))), at: 5_000, source: .account(nil)); try store.enqueueSyncChange(deletion, owner: owner)
        try store.enqueueSyncChange(.init(command: .notePut(.init(hadithId: "local-only", content: "Accepted local note", createdAt: 6_000, updatedAt: 6_000)), at: 6_000, source: .account(nil)), owner: owner)
        XCTAssertNil(try store.publishedSavedViewItem(owner, target: "missing"))
        let session = try finishViewBuild(store, lease: source), reply = try terminalSavedReply(store.savedCheckpoint(source))
        guard case .published(let first) = try await store.publishSavedViewBuild(session, isCurrent: { true }, fetch: { _ in reply }) else { return XCTFail("Initial publication failed") }
        XCTAssertEqual(try GuestDataStore(storeURL: url).publishedSavedViewStamp(owner), first); XCTAssertEqual(try store.activeSavedGeneration(owner)?.lease, source)
        XCTAssertTrue(try XCTUnwrap(store.syncPartition(owner)).confirmed.isEmpty); XCTAssertEqual(try store.syncPartition(owner)?.pending.count, 2)
        XCTAssertEqual(try store.publishedSavedViewItem(owner, target: "local-only")?.item?.value.noteContent, "Accepted local note")
        XCTAssertNotNil(try store.publishedSavedViewItem(owner, target: "missing")); XCTAssertNil(try store.publishedSavedViewItem(owner, target: "missing")?.item)
        let oldPage = try XCTUnwrap(store.publishedSavedViewPage(owner, selection: .init(), limit: 2)); XCTAssertNotNil(oldPage.next)
        XCTAssertNotNil(try store.publishedSavedViewFolders(owner, limit: 2)?.next); XCTAssertNil(try store.publishedSavedViewFolder(owner, target: "folder-1")?.folder)
        XCTAssertTrue(try XCTUnwrap(store.publishedSavedViewPage(owner, selection: .init(collection: "unknown"))).unresolvedCoverage)
        let fence = try await store.prepareOutcomeExport(owner, isCurrent: { true })
        let repeated = try await store.publishSavedViewBuild(session, isCurrent: { true }, fetch: { _ in XCTFail("Idempotent publication fetched"); return reply })
        XCTAssertEqual(repeated, .published(first)); XCTAssertNoThrow(try store.validateOutcomeExport(fence))
        XCTAssertThrowsError(try store.discardSavedViewStep(first)); XCTAssertThrowsError(try store.writeSavedViewRows(first, items: [XCTUnwrap(store.publishedSavedViewItem(owner, target: "local-only")?.item)])); XCTAssertThrowsError(try store.libraryProjection(owner))
        let next = try store.beginSavedAssembly(owner); try await prepareSaved(store, lease: next, facts: viewFacts(state), version: 10)
        do { _ = try await activateSaved(store, next); XCTFail("Private-only activation bypassed view") } catch { }
        XCTAssertEqual(try store.publishedSavedViewStamp(owner), first)
        let nextSession = try finishViewBuild(store, lease: next), nextReply = try terminalSavedReply(store.savedCheckpoint(next))
        guard case .published(let second) = try await store.publishSavedViewBuild(nextSession, isCurrent: { true }, fetch: { _ in nextReply }) else { return XCTFail("Refresh publication failed") }
        XCTAssertNotEqual(second.identity, first.identity); XCTAssertThrowsError(try store.publishedSavedViewPage(owner, selection: .init(), ticket: oldPage.next, limit: 2))
        var steps = 0
        while try store.cleanupSavedViewStep(owner) { XCTAssertEqual(try store.publishedSavedViewStamp(owner), second); steps += 1; guard steps < 200 else { return XCTFail("View retirement did not finish") } }
        while try store.cleanupSavedGenerationStep(owner) { }
        let container = try ModelContainer(for: GuestDataStore.schema, configurations: [ModelConfiguration(schema: GuestDataStore.schema, url: url)])
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<GuestSavedViewHead>()), 1)
        let collecting = try store.beginSavedAssembly(owner)
        try store.enqueueSyncChange(.init(command: .folderRestore(.init(deletionId: deletion.operation.id, name: "Folder 1", hadithIds: [])), at: 7_000, source: .account(nil)), owner: owner)
        let offline = try finishViewBuild(store, lease: next)
        guard case .published(let third) = try store.publishActiveSavedViewBuild(offline, isCurrent: { true }) else { return XCTFail("Offline local publication failed") }
        XCTAssertEqual(try store.activeSavedGeneration(owner)?.lease, next); XCTAssertEqual(try store.savedCheckpoint(collecting).stage, .collecting); XCTAssertEqual(try store.publishedSavedViewStamp(owner), third)
        XCTAssertFalse(try XCTUnwrap(store.publishedSavedViewFolders(owner, name: "Folder 1")).folders.isEmpty)
    }
    @MainActor func testPublicationRejectsWrongCompletionStaleSessionQueueChangesAndKeepsPriorViewOnRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("invalid-publication.store"), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), store = GuestDataStore(storeURL: url)
        try store.claimGuestForSync(owner); let source = try store.beginSavedAssembly(owner); try await prepareSaved(store, lease: source, facts: [])
        try store.enqueueSyncChange(.init(command: .notePut(.init(hadithId: "local", content: "Accepted original", createdAt: 1, updatedAt: 1)), at: 1, source: .account(nil)), owner: owner)
        var session = try finishViewBuild(store, lease: source); let good = try terminalSavedReply(store.savedCheckpoint(source)), fence = try await store.prepareOutcomeExport(owner, isCurrent: { true })
        for field in ["ownerKey", "version", "assemblyId", "input", "completion", "total", "start"] {
            var value = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(good)) as? [String: Any])
            value[field] = ["version", "total", "start"].contains(field) ? 99 : "foreign"
            let bad = try JSONDecoder().decode(SavedFactsReply.self, from: JSONSerialization.data(withJSONObject: value))
            do { _ = try await store.publishSavedViewBuild(session, isCurrent: { true }, fetch: { _ in bad }); XCTFail("Invalid completion published") } catch { }
            XCTAssertNil(try store.publishedSavedViewStamp(owner)); XCTAssertNil(try store.activeSavedGeneration(owner)); XCTAssertNoThrow(try store.validateOutcomeExport(fence))
        }
        var live = true
        do { _ = try await store.publishSavedViewBuild(session, isCurrent: { live }, fetch: { _ in live = false; return good }); XCTFail("Stale session published") } catch { }
        XCTAssertNil(try store.publishedSavedViewStamp(owner)); XCTAssertNoThrow(try store.validateOutcomeExport(fence))
        do { _ = try await store.publishSavedViewBuild(session, isCurrent: { true }, fetch: { _ in try store.enqueueSyncChange(.init(command: .bookmarkAdd(.init(hadithId: "during-confirmation", createdAt: 2)), at: 2, source: .account(nil)), owner: owner); return good }); XCTFail("Changed account published old cut") } catch { }
        XCTAssertNil(try store.publishedSavedViewStamp(owner)); XCTAssertEqual(try store.syncPartition(owner)?.pending.count, 2)
        session = try finishCapturedViewBuild(store, identity: session.identity)
        guard case .published(let first) = try await store.publishSavedViewBuild(session, isCurrent: { true }, fetch: { _ in good }) else { return XCTFail("Recaptured publication failed") }
        let next = try store.beginSavedAssembly(owner); try await prepareSaved(store, lease: next, facts: [], version: 10); let newer = try finishViewBuild(store, lease: next)
        let restarted = try await store.publishSavedViewBuild(newer, isCurrent: { true }, fetch: { _ in .restart(.init(reason: "saved_changed")) })
        XCTAssertEqual(restarted, .restart)
        XCTAssertEqual(try store.publishedSavedViewStamp(owner), first); XCTAssertEqual(try store.activeSavedGeneration(owner)?.lease, source); XCTAssertEqual(try store.savedCheckpoint(next).stage, .restart)
        let replacement = try store.replaceSavedCandidate(next); while try store.cleanupSavedGenerationStep(owner) { }
        try await prepareSaved(store, lease: replacement, facts: [], version: 11); let unavailable = try finishViewBuild(store, lease: replacement)
        let unavailableResult = try await store.publishSavedViewBuild(unavailable, isCurrent: { true }, fetch: { _ in .unavailable(.init(reason: .sourceTooLarge)) })
        XCTAssertEqual(unavailableResult, .unavailable(.sourceTooLarge))
        XCTAssertEqual(try store.publishedSavedViewStamp(owner), first); XCTAssertEqual(try store.publishedSavedViewItem(owner, target: "local")?.item?.value.noteContent, "Accepted original")
    }
    @MainActor func testPublicationRollbackRestoresBothPointersQueueDraftAndOldReadabilityAndEraseCoversRetainedViews() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("rollback-publication.store"), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), store = GuestDataStore(storeURL: url)
        try store.claimGuestForSync(owner); let source = try store.beginSavedAssembly(owner); try await prepareSaved(store, lease: source, facts: [canonicalNote("Canonical original")], version: 1)
        let firstSession = try finishViewBuild(store, lease: source), firstReply = try terminalSavedReply(store.savedCheckpoint(source))
        guard case .published(let first) = try await store.publishSavedViewBuild(firstSession, isCurrent: { true }, fetch: { _ in firstReply }) else { return XCTFail("Initial publication failed") }
        let next = try store.beginSavedAssembly(owner); try await prepareSaved(store, lease: next, facts: [canonicalNote("New canonical original")], version: 2); try seedConfirmedForPublication(url, owner: owner, version: 2)
        let session = try finishViewBuild(store, lease: next), reply = try terminalSavedReply(store.savedCheckpoint(next)), before = try store.syncPartition(owner), draft = try store.savedViewBuildProgress(session)
        let container = try ModelContainer(for: GuestDataStore.schema, configurations: [ModelConfiguration(schema: GuestDataStore.schema, url: url)]), setup = ModelContext(container)
        let clock = try XCTUnwrap(setup.fetch(FetchDescriptor<GuestOutcomeClock>()).first), revision = clock.revision; clock.revision = 9_007_199_254_740_989; try setup.save()
        let fence = try await store.prepareOutcomeExport(owner, isCurrent: { true })
        do { _ = try await store.publishSavedViewBuild(session, isCurrent: { true }, fetch: { _ in reply }); XCTFail("Failed account publication committed") } catch { }
        XCTAssertEqual(try store.publishedSavedViewStamp(owner), first); XCTAssertEqual(try store.activeSavedGeneration(owner)?.lease, source); XCTAssertEqual(try store.syncPartition(owner), before)
        XCTAssertEqual(try store.savedViewBuildProgress(session).0, draft.0); XCTAssertEqual(try store.savedViewBuildProgress(session).1, draft.1); XCTAssertNoThrow(try store.validateOutcomeExport(fence))
        XCTAssertEqual(try store.publishedSavedViewItem(owner, target: "target")?.item?.value.noteContent, "Canonical original")
        clock.revision = revision; try setup.save(); _ = try await store.publishSavedViewBuild(session, isCurrent: { true }, fetch: { _ in reply })
        let export = try await store.prepareOutcomeExport(owner, isCurrent: { true }); var values: [LibraryExportValue] = [], after: String?
        while true { let page = try store.savedExportRecords(export, section: 5, after: after); values.append(contentsOf: page.values); after = page.next; if page.done { break } }
        XCTAssertTrue(exportContains(.array(values), text: "Canonical original")); XCTAssertTrue(exportContains(.array(values), text: "New canonical original"))
        let peer = LibrarySyncOwner(key: "peer", subject: "foreign-subject"); try store.claimGuestForSync(peer); let peerSource = try store.beginSavedAssembly(peer); try await prepareSaved(store, lease: peerSource, facts: [canonicalNote("Foreign retained original")], version: 1)
        let peerSession = try finishViewBuild(store, lease: peerSource), peerReply = try terminalSavedReply(store.savedCheckpoint(peerSource)); _ = try await store.publishSavedViewBuild(peerSession, isCurrent: { true }, fetch: { _ in peerReply })
        store.addNote(hadithId: "guest", content: "Unclaimed original"); try store.beginDeletion(subject: owner.subject, namespace: owner.namespace); try await store.markDeletionBackendComplete(subject: owner.subject, namespace: owner.namespace)
        XCTAssertEqual(try store.publishedSavedViewItem(peer, target: "target")?.item?.value.noteContent, "Foreign retained original"); XCTAssertEqual(store.noteDrafts().first?.content, "Unclaimed original"); XCTAssertNil(try store.syncPartition(owner))
    }
    private func viewState(_ owner: LibrarySyncOwner, count: Int) -> LibraryPartitionState {
        let folders = (0..<70).map { SyncFolderRow(_id: "folder-\($0)", name: "Folder \($0)", createdAt: 1_000 + Double($0)) }
        let items = (0..<count).map { i -> SyncSavedItem in
            let mask = i % 7 + 1, at = 1_000 + Double(i % 3)
            let hadith = SyncHadithSummary(_id: i % 13 == 0 ? "mismatched-public-id" : "target-\(i)", providerHadithId: "\(i)", collectionSlug: i % 2 == 0 ? "bukhari" : "muslim", collectionName: "Collection", volumeId: "1", arabicText: "Provider passage", englishText: "Provider translation", referenceDisplay: "Reference")
            return .init(hadithId: "target-\(i)", createdAt: 1_000, updatedAt: at, bookmarkCreatedAt: mask & 1 == 0 ? nil : 1_000, favoriteCreatedAt: mask & 2 == 0 ? nil : 1_000, noteContent: mask & 4 == 0 ? nil : "Private note \(i)", noteCreatedAt: mask & 4 == 0 ? nil : 1_000, noteUpdatedAt: mask & 4 == 0 ? nil : at, folderId: i % 6 == 5 ? nil : "folder-\(i % 5)", hadith: hadith)
        }
        var state = LibraryPartitionState(); state.savedSnapshot = .init(ownerKey: owner.key, version: 9, folders: folders, items: items); return state
    }
    @MainActor func testViewCompilerMatchesLegacyOracleAndPreservesBulkProvenanceAndTimeFloors() throws {
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"); var state = viewState(owner, count: 2_001)
        let deletion = LibraryLocalChange(command: .folderDelete(.init(folder: .server(.init(id: "folder-1")))), at: 5_000, source: .account(nil))
        state.folderMappings = ["restore:" + deletion.operation.id: "restored-folder"]
        state.pending = [deletion,
            .init(command: .membershipPut(.init(hadithId: "target-1999", folder: .server(.init(id: "folder-4")), mode: nil)), at: 6_000, source: .account(nil)),
            .init(command: .folderRestore(.init(deletionId: deletion.operation.id, name: "Folder 1", hadithIds: [])), at: 7_000, source: .account(nil)),
            .init(command: .bookmarkRemove(.init(hadithId: "target-0")), at: 8_000, source: .account(nil)),
            .init(command: .facetRestore(.init(hadithId: "target-0", deletionId: "removed", value: .bookmark(.init(createdAt: 1_000)))), at: 9_000, source: .account(nil))]
        let source = try LibrarySavedViewPolicy.captureLegacy(state, owner: owner, observed: observation(state)), oracle = try legacyProjection(state)
        XCTAssertEqual(source.items.count, 2_001); XCTAssertEqual(Set(oracle.items.map(\.hadithId)), Set(source.items.map { $0.value.hadithId }))
        let expected = Dictionary(uniqueKeysWithValues: oracle.items.map { ($0.hadithId, $0) })
        for item in source.items {
            let old = try XCTUnwrap(expected[item.value.hadithId]), value = item.value
            XCTAssertEqual(old.createdAt, Date(timeIntervalSince1970: value.createdAt / 1_000))
            XCTAssertEqual(old.updatedAt, Date(timeIntervalSince1970: value.updatedAt / 1_000))
            XCTAssertEqual(old.folderId, value.folderId); XCTAssertEqual(old.bookmarkCreatedAt?.timeIntervalSince1970, value.bookmarkCreatedAt.map { $0 / 1_000 }); XCTAssertEqual(old.favoriteCreatedAt?.timeIntervalSince1970, value.favoriteCreatedAt.map { $0 / 1_000 }); XCTAssertEqual(old.noteContent, value.noteContent)
        }
        XCTAssertEqual(source.items.first { $0.value.hadithId == "target-1999" }?.value.folderId, "folder-4")
        XCTAssertEqual(source.items.first { $0.value.hadithId == "target-0" }?.value.createdAt, 1_000)
        XCTAssertTrue(source.items.filter { $0.value.folderId == "restored-folder" }.allSatisfy { $0.value.updatedAt >= 7_000 && $0.removedBy == nil })
        let deleted = LibrarySavedViewPolicy.deleted(try XCTUnwrap(source.items.first), operation: deletion.operation.id, at: 10_000)
        XCTAssertEqual(deleted.removedBy, deletion.operation.id); XCTAssertEqual(deleted.value.updatedAt, 10_000)
        let data = try JSONEncoder().encode(source), document = try JSONDecoder().decode(LibraryExportValue.self, from: data)
        XCTAssertFalse(document.containsAnyKey(["arabicText", "englishText"]))
    }
    func testViewNamingAndTechnicalKeysMatchBackendAndPortableVectors() throws {
        struct NameCase: Decodable { let input: String; let expected: String }
        struct Vectors: Decodable { let names: [NameCase]; let identity: String; let rank: String; let prefix: String; let manifestSource: LibrarySavedViewSnapshot; let manifest: LibrarySavedViewManifest }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/SavedViewVectors.json")
        let vectors = try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
        for value in vectors.names { XCTAssertEqual(LibrarySavedViewPolicy.nameKey(value.input), value.expected) }
        let identity = LibrarySavedViewIdentity(owner: .init(key: "owner-a", subject: "subject-a"), epoch: "epoch", generation: "generation")
        XCTAssertEqual(identity.key, vectors.identity)
        XCTAssertEqual(try LibrarySavedViewManifest.make(identity, source: vectors.manifestSource), vectors.manifest)
        XCTAssertThrowsError(try LibrarySavedViewManifest(items: 1, folders: 0, indexes: 1, digest: String(repeating: "0", count: 64), bindings: Int.max).validate())
        let item = SavedPrivateItem(hadithId: "target-Ω", createdAt: 1, updatedAt: 4500.5, bookmarkCreatedAt: nil, favoriteCreatedAt: nil, noteContent: nil, noteCreatedAt: nil, noteUpdatedAt: nil, folderId: nil, folderUpdatedAt: nil)
        XCTAssertEqual(try LibrarySavedViewPolicy.rank(item), vectors.rank)
        XCTAssertEqual(identity.queryPrefix(.init(facet: .bookmarks, folder: .folder("folder"), collection: "bukhari")), vectors.prefix)
    }
    @MainActor func testViewRowsPageByIndexedSelectionAndReadOffscreenTargetsAcrossReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("views.store"), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        var store = GuestDataStore(storeURL: url, exportDirectory: directory.appendingPathComponent("exports")); try store.claimGuestForSync(owner)
        let privateLease = try store.beginSavedAssembly(owner), state = viewState(owner, count: 2_001)
        let source = try LibrarySavedViewPolicy.captureLegacy(state, owner: owner, observed: observation(state))
        var stamp = try store.createSavedViewRows(privateLease); let identity = stamp.identity
        for start in stride(from: 0, to: source.items.count, by: 8) { stamp = try autoreleasepool { try store.writeSavedViewRows(stamp, items: Array(source.items[start..<min(start + 8, source.items.count)])) } }
        for start in stride(from: 0, to: source.folders.count, by: 8) { stamp = try autoreleasepool { try store.writeSavedViewRows(stamp, items: [], folders: Array(source.folders[start..<min(start + 8, source.folders.count)])) } }
        store = GuestDataStore(storeURL: url, exportDirectory: directory.appendingPathComponent("exports")); XCTAssertEqual(try store.draftSavedViewStamp(identity), stamp)
        let selections = LibrarySavedViewFacet.allCases.map { LibrarySavedViewSelection(facet: $0) } + [.init(facet: .notes, folder: .folder("folder-1"), collection: "bukhari"), .init(facet: .bookmarks, folder: .unfiled, collection: "muslim"), .init(collection: "unavailable-collection")]
        for selection in selections {
            var all: [LibrarySavedViewItem] = [], ticket: LibrarySavedViewTicket?
            repeat { let page = try store.draftSavedViewPage(stamp, selection: selection, ticket: ticket); XCTAssertLessThanOrEqual(page.items.count, 32); all.append(contentsOf: page.items); ticket = page.next } while ticket != nil
            let expected = try source.items.filter { try LibrarySavedViewPolicy.matches($0, selection: selection) }
            XCTAssertEqual(all, expected)
        }
        let empty = try store.draftSavedViewPage(stamp, selection: .init(collection: "unavailable-collection")); XCTAssertTrue(empty.items.isEmpty); XCTAssertTrue(empty.unresolvedCoverage)
        XCTAssertEqual(try store.draftSavedViewItem(stamp, target: "target-1999"), source.items.first { $0.value.hadithId == "target-1999" })
        let first = try store.draftSavedViewPage(stamp, selection: .init()), old = stamp
        let current = try XCTUnwrap(store.draftSavedViewItem(stamp, target: "target-1999"))
        let update = LibraryLocalChange(command: .notePut(.init(hadithId: "target-1999", content: "Offscreen accepted note", createdAt: 1_000, updatedAt: 20_000)), at: 20_000, source: .account(nil))
        let changed = try XCTUnwrap(LibrarySavedViewPolicy.point(current, change: update, outcome: nil, mappings: [:], route: nil))
        stamp = try store.writeSavedViewRows(stamp, items: [changed])
        XCTAssertThrowsError(try store.draftSavedViewPage(old, selection: .init(), ticket: first.next))
        XCTAssertEqual(try store.draftSavedViewPage(stamp, selection: .init(facet: .notes)).items.first?.value.noteContent, "Offscreen accepted note")
        stamp = try store.writeSavedViewRows(stamp, items: [], folders: [.init(_id: "\u{E000}", name: " ΟΣ ", createdAt: 1_000), .init(_id: "\u{10000}", name: "ος", createdAt: 1_000)])
        XCTAssertEqual(try store.draftSavedViewFolders(stamp, name: "ΟΣ").folders.first?._id, "\u{E000}")
        var folderCount = 0, ticket: LibrarySavedViewFolderTicket?
        repeat { let page = try store.draftSavedViewFolders(stamp, ticket: ticket); folderCount += page.folders.count; ticket = page.next } while ticket != nil
        XCTAssertEqual(folderCount, 72); XCTAssertEqual(try store.draftSavedViewFolder(stamp, target: "folder-69")?.name, "Folder 69")
        var database: OpaquePointer?; XCTAssertEqual(sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(database, "SELECT ZKEY,ZTARGETKEY FROM ZGUESTSAVEDVIEWINDEX WHERE ZKEY>? AND ZKEY<? ORDER BY ZKEY LIMIT 33", -1, &statement, nil), SQLITE_OK)
        let prefix = identity.queryPrefix(.init(collection: "empty")), upper = prefix + "~"
        prefix.withCString { lowerBytes in upper.withCString { upperBytes in
            sqlite3_bind_text(statement, 1, lowerBytes, -1, nil); sqlite3_bind_text(statement, 2, upperBytes, -1, nil)
            XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
            XCTAssertLessThan(sqlite3_stmt_status(statement, SQLITE_STMTSTATUS_VM_STEP, 0), 100)
        } }; sqlite3_finalize(statement)
        let fixture = LibraryFacadeFixture(store: store); await fixture.start()
        do {
            let prepared = try await fixture.sync.preparePortableExport(server: .object([:]), context: fixture.sync.captureWriteContext(), fileName: "views.json")
            let document = try JSONDecoder().decode(LibraryExportValue.self, from: Data(contentsOf: prepared.url))
            guard case .object(let fields) = document, case .array(let records) = fields["localSavedEvidence"] else { return XCTFail("Missing view export") }
            XCTAssertEqual(records.filter { if case .object(let value) = $0 { value["kind"] == .string("viewItem") } else { false } }.count, 2_001)
            XCTAssertTrue(exportContains(.array(records), text: "Offscreen accepted note")); XCTAssertFalse(document.containsAnyKey(["arabicText", "englishText"]))
            try fixture.sync.discardPreparedExport(prepared)
        }; fixture.stop()
        try store.beginDeletion(subject: owner.subject, namespace: owner.namespace); try await store.markDeletionBackendComplete(subject: owner.subject, namespace: owner.namespace)
        let container = try ModelContainer(for: GuestDataStore.schema, configurations: [ModelConfiguration(schema: GuestDataStore.schema, url: url)]), db = ModelContext(container)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<GuestSavedViewHead>()), 0); XCTAssertEqual(try db.fetchCount(FetchDescriptor<GuestSavedViewRow>()), 0); XCTAssertEqual(try db.fetchCount(FetchDescriptor<GuestSavedViewIndex>()), 0)
    }
    @MainActor func testViewDraftAllocationNeverRevivesMissingHeadsAndScopedExportRetainsOrphans() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("lifecycle.store"), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), store = GuestDataStore(storeURL: url)
        try store.claimGuestForSync(owner); let scope = try store.beginSavedAssembly(owner)
        let container = try ModelContainer(for: GuestDataStore.schema, configurations: [ModelConfiguration(schema: GuestDataStore.schema, url: url)])
        func removeHead(_ identity: LibrarySavedViewIdentity) throws {
            let db = ModelContext(container), key = identity.key
            for row in try db.fetch(FetchDescriptor<GuestSavedViewHead>(predicate: #Predicate { $0.key == key })) { db.delete(row) }; try db.save()
        }
        let empty = try store.createSavedViewRows(scope); try removeHead(empty.identity)
        XCTAssertThrowsError(try store.draftSavedViewStamp(empty.identity))
        let allocated = try store.createSavedViewRows(scope); XCTAssertNotEqual(empty.identity, allocated.identity)
        let item = LibrarySavedViewItem(value: .init(hadithId: "private-target", createdAt: 1, updatedAt: 1, bookmarkCreatedAt: nil, favoriteCreatedAt: nil, noteContent: "Orphan retained note", noteCreatedAt: 1, noteUpdatedAt: 1, folderId: nil, folderUpdatedAt: nil))
        let orphan = try store.writeSavedViewRows(allocated, items: [item]); try removeHead(orphan.identity)
        XCTAssertThrowsError(try store.draftSavedViewItem(orphan, target: "private-target"))
        let replacement = try store.createSavedViewRows(scope); XCTAssertNotEqual(orphan.identity, replacement.identity); XCTAssertNil(try store.draftSavedViewItem(replacement, target: "private-target"))
        let oldOwner = LibrarySyncOwner(key: "old-owner", subject: owner.subject); try store.claimGuestForSync(oldOwner); let oldScope = try store.beginSavedAssembly(oldOwner)
        let oldItem = try XCTUnwrap(LibrarySavedViewPolicy.point(item, change: .init(command: .notePut(.init(hadithId: "private-target", content: "Old owner retained note", createdAt: 1, updatedAt: 2)), at: 2, source: .account(nil)), outcome: nil, mappings: [:], route: nil))
        let old = try store.writeSavedViewRows(store.createSavedViewRows(oldScope), items: [oldItem])
        let db = ModelContext(container), oldKey = oldOwner.storageKey
        for row in try db.fetch(FetchDescriptor<GuestLibraryPartition>(predicate: #Predicate { $0.ownerKey == oldKey })) { db.delete(row) }; try db.save()
        XCTAssertThrowsError(try store.draftSavedViewItem(old, target: "private-target"))
        let peer = LibrarySyncOwner(key: "foreign-owner", subject: "foreign-subject"); try store.claimGuestForSync(peer); let peerScope = try store.beginSavedAssembly(peer)
        let peerItem = try XCTUnwrap(LibrarySavedViewPolicy.point(item, change: .init(command: .notePut(.init(hadithId: "private-target", content: "Foreign private note", createdAt: 1, updatedAt: 2)), at: 2, source: .account(nil)), outcome: nil, mappings: [:], route: nil))
        let foreign = try store.writeSavedViewRows(store.createSavedViewRows(peerScope), items: [peerItem])
        let fence = try await store.prepareOutcomeExport(owner, isCurrent: { true }); var records: [LibraryExportValue] = [], after: String?
        while true { let page = try store.savedExportRecords(fence, section: 5, after: after); records.append(contentsOf: page.values); after = page.next; if page.done { break } }
        XCTAssertTrue(exportContains(.array(records), text: "Orphan retained note")); XCTAssertTrue(exportContains(.array(records), text: "Old owner retained note")); XCTAssertFalse(exportContains(.array(records), text: "Foreign private note"))
        store.addNote(hadithId: "guest", content: "Unclaimed guest original")
        try store.beginDeletion(subject: owner.subject, namespace: owner.namespace); try await store.markDeletionBackendComplete(subject: owner.subject, namespace: owner.namespace)
        XCTAssertEqual(try store.draftSavedViewItem(foreign, target: "private-target")?.value.noteContent, "Foreign private note")
        XCTAssertEqual(store.noteDrafts().first?.content, "Unclaimed guest original")
    }
    @MainActor func testViewDraftSerialLimitsAndLogicalRollbackPreserveRowsIndexesAndFence() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("serial.store"), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), store = GuestDataStore(storeURL: url)
        try store.claimGuestForSync(owner); let scope = try store.beginSavedAssembly(owner), initial = try store.createSavedViewRows(scope)
        let container = try ModelContainer(for: GuestDataStore.schema, configurations: [ModelConfiguration(schema: GuestDataStore.schema, url: url)]), setup = ModelContext(container)
        let head = try XCTUnwrap(setup.fetch(FetchDescriptor<GuestSavedViewHead>()).first)
        head.serial = 9_007_199_254_740_990; try setup.save()
        let terminal = try store.draftSavedViewStamp(initial.identity), fence = try await store.prepareOutcomeExport(owner, isCurrent: { true })
        let item = LibrarySavedViewItem(value: .init(hadithId: "target", createdAt: 1, updatedAt: 1, bookmarkCreatedAt: 1, favoriteCreatedAt: nil, noteContent: nil, noteCreatedAt: nil, noteUpdatedAt: nil, folderId: nil, folderUpdatedAt: nil))
        XCTAssertTrue(try store.draftSavedViewPage(terminal, selection: .init()).items.isEmpty)
        XCTAssertThrowsError(try store.writeSavedViewRows(terminal, items: [item])); XCTAssertNil(try store.draftSavedViewItem(terminal, target: "target")); XCTAssertNoThrow(try store.validateOutcomeExport(fence))
        XCTAssertEqual(try store.savedExportRecords(fence, section: 4, after: nil).values.count, 1)
        head.serial = 0
        let clock = try XCTUnwrap(setup.fetch(FetchDescriptor<GuestOutcomeClock>()).first), revision = clock.revision
        clock.revision = 9_007_199_254_740_990; try setup.save()
        let before = try await store.prepareOutcomeExport(owner, isCurrent: { true })
        XCTAssertThrowsError(try store.writeSavedViewRows(initial, items: [item]))
        XCTAssertNil(try store.draftSavedViewItem(initial, target: "target")); XCTAssertNoThrow(try store.validateOutcomeExport(before))
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<GuestSavedViewIndex>()), 0)
        clock.revision = revision; try setup.save()
        let accepted = try store.writeSavedViewRows(initial, items: [item]); XCTAssertEqual(try store.draftSavedViewItem(accepted, target: "target"), item)
    }
    private func observationOwner(_ state: LibraryPartitionState) -> LibrarySyncOwner { .init(key: state.savedSnapshot?.ownerKey ?? "owner-a", subject: "subject-a") }
    private func observation(_ state: LibraryPartitionState, owner: LibrarySyncOwner? = nil) throws -> LibrarySavedObservation {
        try .legacy(owner ?? observationOwner(state), snapshot: state.savedSnapshot)
    }
    @MainActor private func legacyProjection(_ state: LibraryPartitionState) throws -> LibraryProjection {
        try LibraryProjection(state, owner: observationOwner(state), observed: observation(state))
    }
    private func savedPlan(_ reply: SavedFactsReply, owner: LibrarySyncOwner, previous: LibrarySavedReadPosition? = nil, requested: String? = nil) throws -> LibrarySavedPagePlan {
        guard case .append(let value) = try LibrarySavedPolicy.inspect(reply, owner: owner, previous: previous, requested: requested) else { throw LibrarySyncFailure.invalidReceipt }
        return value
    }
    func testSavedFoldMatchesActualBackendParityAndFingerprints() throws {
        let facts = try JSONDecoder().decode([SavedFact].self, from: Data(LibrarySavedParityVector.factsJSON.utf8))
        let expected = try JSONDecoder().decode(SavedPrivateItem.self, from: Data(LibrarySavedParityVector.expectedJSON.utf8))
        var result: LibrarySavedProjection?
        for (index, fact) in facts.enumerated() {
            XCTAssertEqual(try fact.savedFingerprint(), LibrarySavedParityVector.digests[index])
            result = try LibrarySavedPolicy.fold(fact, previous: result)
        }
        guard case .item(let row, let first) = result else { return XCTFail("Missing private row") }
        XCTAssertEqual(row, expected); XCTAssertEqual(first, 0)
    }
    func testSavedCanonicalReplacementClearsFieldsAndPreservesFirstEncounter() throws {
        let original = SavedPrivateItem(hadithId: "missing-public-target", createdAt: 1, updatedAt: 30, bookmarkCreatedAt: 1, favoriteCreatedAt: 2, noteContent: "Original", noteCreatedAt: 3, noteUpdatedAt: 4, folderId: "old-folder", folderUpdatedAt: 30)
        let first = try LibrarySavedPolicy.fold(.item(.init(sourceId: "source-a", ordinal: 0, value: original)), previous: nil)
        let replacement = SavedPrivateItem(hadithId: original.hadithId, createdAt: 5, updatedAt: 5, bookmarkCreatedAt: nil, favoriteCreatedAt: nil, noteContent: nil, noteCreatedAt: nil, noteUpdatedAt: nil, folderId: nil, folderUpdatedAt: nil)
        let folded = try LibrarySavedPolicy.fold(.item(.init(sourceId: "source-b", ordinal: 1, value: replacement)), previous: first)
        XCTAssertEqual(folded, .item(replacement, firstOrdinal: 0))
    }
    func testSavedLegacyOnlyClockAndEqualNotePrecedence() throws {
        let facts: [SavedFact] = [
            .bookmark(.init(sourceId: "b1", ordinal: 0, hadithId: "h", createdAt: 100)),
            .bookmark(.init(sourceId: "b2", ordinal: 1, hadithId: "h", createdAt: 20)),
            .favorite(.init(sourceId: "f1", ordinal: 2, hadithId: "h", createdAt: 200)),
            .note(.init(sourceId: "n1", ordinal: 3, hadithId: "h", content: "First note", createdAt: 10, updatedAt: 50)),
            .note(.init(sourceId: "n2", ordinal: 4, hadithId: "h", content: "Equal note loses", createdAt: 5, updatedAt: 50))]
        var result: LibrarySavedProjection?
        for fact in facts { result = try LibrarySavedPolicy.fold(fact, previous: result) }
        guard case .item(let row, let first) = result else { return XCTFail("Missing private row") }
        XCTAssertEqual(row.bookmarkCreatedAt, 20); XCTAssertEqual(row.favoriteCreatedAt, 200)
        XCTAssertEqual(row.createdAt, 5); XCTAssertEqual(row.updatedAt, 100); XCTAssertEqual(first, 0)
        XCTAssertEqual(row.noteContent, "First note"); XCTAssertEqual(row.noteCreatedAt, 10)
    }
    func testSavedEmptyPageAndCheckpointRoundtripThenTerminalRecheck() throws {
        let owner = LibrarySyncOwner(key: "owner", subject: "subject")
        let first = try savedPlan(.page(.init(ownerKey: owner.key, version: 3, assemblyId: "root", input: nil, start: 0, facts: [], next: "next")), owner: owner)
        let reopened = try JSONDecoder().decode(LibrarySavedReadPosition.self, from: JSONEncoder().encode(first.position))
        XCTAssertEqual(reopened, first.position); XCTAssertEqual(reopened.nextOrdinal, 0)
        let terminal = try savedPlan(.complete(.init(ownerKey: owner.key, version: 3, assemblyId: "root", input: "next", start: 0, facts: [], total: 0, completion: "finish")), owner: owner, previous: reopened, requested: "next")
        try LibrarySavedPolicy.confirm(.complete(.init(ownerKey: owner.key, version: 3, assemblyId: "root", input: "finish", start: 0, facts: [], total: 0, completion: "finish")), position: terminal.position)
        XCTAssertThrowsError(try LibrarySavedPolicy.confirm(.complete(.init(ownerKey: owner.key, version: 4, assemblyId: "root", input: "finish", start: 0, facts: [], total: 0, completion: "finish")), position: terminal.position))
        XCTAssertThrowsError(try LibrarySavedPolicy.confirm(.restart(.init(reason: "saved_changed")), position: terminal.position))
        XCTAssertThrowsError(try LibrarySavedPolicy.inspect(.page(.init(ownerKey: owner.key, version: 3, assemblyId: "root", input: "finish", start: 0, facts: [], next: "again")), owner: owner, previous: terminal.position, requested: "finish"))
    }
    func testSavedPageRejectsOwnerRootInputRevisionOrdinalAndCycleMismatch() throws {
        let owner = LibrarySyncOwner(key: "owner", subject: "subject")
        let first = try savedPlan(.page(.init(ownerKey: owner.key, version: 1, assemblyId: "root", input: nil, start: 0, facts: [], next: "next")), owner: owner)
        let invalid: [SavedFactsReply] = [
            .page(.init(ownerKey: "other", version: 1, assemblyId: "root", input: "next", start: 0, facts: [], next: "new")),
            .page(.init(ownerKey: owner.key, version: 2, assemblyId: "root", input: "next", start: 0, facts: [], next: "new")),
            .page(.init(ownerKey: owner.key, version: 1, assemblyId: "other-root", input: "next", start: 0, facts: [], next: "new")),
            .page(.init(ownerKey: owner.key, version: 1, assemblyId: "root", input: "wrong", start: 0, facts: [], next: "new")),
            .page(.init(ownerKey: owner.key, version: 1, assemblyId: "root", input: "next", start: 1, facts: [], next: "new")),
            .page(.init(ownerKey: owner.key, version: 1, assemblyId: "root", input: "next", start: 0, facts: [], next: "next")),
            .complete(.init(ownerKey: owner.key, version: 1, assemblyId: "root", input: "next", start: 0, facts: [], total: 1, completion: "finish")),
            .restart(.init(reason: "unrecognized"))]
        for reply in invalid { XCTAssertThrowsError(try LibrarySavedPolicy.inspect(reply, owner: owner, previous: first.position, requested: "next")) }
        XCTAssertEqual(first.position.nextOrdinal, 0)
    }
    func testSavedPhaseAndWireBoundsRejectMalformedFacts() throws {
        let owner = LibrarySyncOwner(key: "owner", subject: "subject")
        let note: SavedFact = .note(.init(sourceId: "n", ordinal: 0, hadithId: "h", content: " \nعربى ", createdAt: 1, updatedAt: 2))
        let first = try savedPlan(.page(.init(ownerKey: owner.key, version: 1, assemblyId: "root", input: nil, start: 0, facts: [note], next: "next")), owner: owner)
        let backwards: SavedFact = .item(.init(sourceId: "i", ordinal: 1, value: .init(hadithId: "h", createdAt: 1, updatedAt: 1, bookmarkCreatedAt: nil, favoriteCreatedAt: nil, noteContent: nil, noteCreatedAt: nil, noteUpdatedAt: nil, folderId: nil, folderUpdatedAt: nil)))
        XCTAssertThrowsError(try LibrarySavedPolicy.inspect(.page(.init(ownerKey: owner.key, version: 1, assemblyId: "root", input: "next", start: 1, facts: [backwards], next: "new")), owner: owner, previous: first.position, requested: "next"))
        for value in [-1.0, 0.5, .infinity, .nan, 9_007_199_254_740_992] { XCTAssertThrowsError(try LibrarySavedPolicy.integer(value)) }
        XCTAssertThrowsError(try LibrarySavedPolicy.validate(SavedFact.note(.init(sourceId: "n", ordinal: 0, hadithId: "h", content: String(repeating: "ع", count: 20_000), createdAt: 1, updatedAt: 2))))
        guard case .item(let row, _) = try LibrarySavedPolicy.fold(note, previous: nil) else { return XCTFail("Missing retained target") }
        XCTAssertEqual(row.hadithId, "h"); XCTAssertEqual(row.noteContent, " \nعربى ")
    }

    func testSavedReadBoundaryUsesActualBackendWireAndPreservesCompleteText() throws {
        let head = try JSONDecoder().decode(SavedReadHead.self, from: Data(LibrarySavedReadsParityVector.headJSON.utf8))
        let owner = LibrarySyncOwner(key: head.ownerKey, subject: "subject-a"), target = "10002;hadiths"
        XCTAssertEqual(try LibrarySavedReadPolicy.invalidation(head, owner: owner).version, 1)
        let metadata = try JSONDecoder().decode(SavedReferenceReply.self, from: Data(LibrarySavedReadsParityVector.referenceJSON.utf8))
        guard case .available(let reference) = try LibrarySavedReadPolicy.reference(metadata, owner: owner, target: target) else { return XCTFail("Missing backend reference") }
        XCTAssertEqual(reference.hadithID, target); XCTAssertEqual(reference.collectionSlug, "bukhari")
        let text = try JSONDecoder().decode(SavedTextReply.self, from: Data(LibrarySavedReadsParityVector.textJSON.utf8))
        guard case .available(let complete) = try LibrarySavedReadPolicy.text(text, owner: owner, target: target) else { return XCTFail("Missing backend text") }
        XCTAssertEqual(complete.reference.arabicText, "  إِنَّمَا\n"); XCTAssertEqual(complete.reference.englishText, "Actions \"by intentions\".\n")
        let arabic = String(repeating: "ع\n", count: 100_000), english = String(repeating: "\"\\\u{0000}", count: 30_000)
        let large = SavedTextReply.available(.init(ownerKey: owner.key, hadithId: target, hadith: .init(_id: target, providerHadithId: "1", collectionSlug: "bukhari", collectionName: "Bukhari", volumeId: "1", arabicText: arabic, englishText: english, referenceDisplay: "Bukhari 1")))
        guard case .available(let full) = try LibrarySavedReadPolicy.text(large, owner: owner, target: target) else { return XCTFail("Large complete passage lost") }
        XCTAssertEqual(full.reference.arabicText, arabic); XCTAssertEqual(full.reference.englishText, english)
    }
    func testSavedReadBoundaryRejectsForeignWrongTargetInvalidHeadAndUnknownUnavailable() throws {
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), target = "target"
        for version in [-1, 0.5, Double.infinity, 9_007_199_254_740_992] { XCTAssertThrowsError(try LibrarySavedReadPolicy.invalidation(.init(ownerKey: owner.key, version: version), owner: owner)) }
        XCTAssertThrowsError(try LibrarySavedReadPolicy.invalidation(.init(ownerKey: "other", version: 1), owner: owner))
        XCTAssertEqual(try LibrarySavedReadPolicy.reference(.missing(.init(ownerKey: owner.key, hadithId: target)), owner: owner, target: target), .missing)
        XCTAssertEqual(try LibrarySavedReadPolicy.text(.unavailable(.init(ownerKey: owner.key, hadithId: target, reason: "text_too_large")), owner: owner, target: target), .unavailable)
        XCTAssertThrowsError(try LibrarySavedReadPolicy.reference(.missing(.init(ownerKey: "other", hadithId: target)), owner: owner, target: target))
        XCTAssertThrowsError(try LibrarySavedReadPolicy.text(.missing(.init(ownerKey: owner.key, hadithId: "other")), owner: owner, target: target))
        XCTAssertThrowsError(try LibrarySavedReadPolicy.reference(.unavailable(.init(ownerKey: owner.key, hadithId: target, reason: "invented")), owner: owner, target: target))
        let row = SavedHadithReference(_id: "other", providerHadithId: "1", collectionSlug: "bukhari", collectionName: "Bukhari", volumeId: nil, referenceDisplay: "")
        XCTAssertThrowsError(try LibrarySavedReadPolicy.reference(.available(.init(ownerKey: owner.key, hadithId: target, reference: row)), owner: owner, target: target))
        let oversized = SavedHadithReference(_id: target, providerHadithId: "1", collectionSlug: "bukhari", collectionName: String(repeating: "ع", count: LibrarySyncLimits.savedReferenceBytes), volumeId: nil, referenceDisplay: "")
        XCTAssertThrowsError(try LibrarySavedReadPolicy.reference(.available(.init(ownerKey: owner.key, hadithId: target, reference: oversized)), owner: owner, target: target))
    }
    @MainActor func testSavedReadTransportInvalidationNeverObservesPrivateRevisionAndQuietBindingExpires() async throws {
        let fixture = try LibrarySavedReadFixture(store: GuestDataStore(inMemory: true)); defer { fixture.sync.deactivate() }
        try await fixture.start()
        let context = try fixture.sync.captureSavedReadContext(), before = try fixture.store.syncPartition(context.owner)
        let observed = expectation(description: "Validated compact invalidation"), ready = expectation(description: "Head transport requests values")
        fixture.onHeadRequest = { ready.fulfill() }
        let subscription = try fixture.sync.savedInvalidations(context).sink(receiveCompletion: { _ in }, receiveValue: { value in XCTAssertEqual(value.version, 999); observed.fulfill() })
        await fulfillment(of: [ready], timeout: 2)
        fixture.heads.send(.init(ownerKey: context.owner.key, version: 999)); await fulfillment(of: [observed], timeout: 2)
        subscription.cancel()
        XCTAssertEqual(try fixture.store.syncPartition(context.owner), before); XCTAssertNil(try fixture.store.activeSavedGeneration(context.owner))
        let ref = try await fixture.sync.savedReference(hadithID: fixture.target, context: context)
        guard case .available = ref else { return XCTFail("Validated metadata unavailable") }
        fixture.now = context.validUntil + 1; await fixture.sync.activate(try XCTUnwrap(fixture.session))
        XCTAssertThrowsError(try fixture.sync.savedInvalidations(context))
        let fresh = try fixture.sync.captureSavedReadContext(); fixture.bindingTTL = 100
        fixture.now = fresh.validUntil + 1; await fixture.sync.activate(try XCTUnwrap(fixture.session))
        let short = try fixture.sync.captureSavedReadContext(), expired = expectation(description: "Quiet binding expires")
        let quiet = try fixture.sync.savedInvalidations(short).sink(receiveCompletion: { result in if case .failure = result { expired.fulfill() } }, receiveValue: { _ in XCTFail("Quiet transport emitted data") })
        await fulfillment(of: [expired], timeout: 2); quiet.cancel()
    }
    @MainActor func testSavedReadTransportDelayedSubscriptionKeepsAbsoluteExpiryAndRejectsStaleScopeBeforeTransport() async throws {
        let fixture = try LibrarySavedReadFixture(store: GuestDataStore(inMemory: true)); defer { fixture.sync.deactivate() }; try await fixture.start()
        let context = try fixture.sync.captureSavedReadContext(), publisher = try fixture.sync.savedInvalidations(context)
        XCTAssertEqual(fixture.headStarts, 0)
        fixture.now = context.validUntil - 100
        let expired = expectation(description: "Remaining absolute lifetime expires")
        let first = publisher.sink(receiveCompletion: { if case .failure = $0 { expired.fulfill() } }, receiveValue: { _ in XCTFail("Quiet transport emitted data") })
        await fulfillment(of: [expired], timeout: 1); first.cancel(); XCTAssertEqual(fixture.headStarts, 1)
        let stale = try fixture.sync.savedInvalidations(context); fixture.session = nil
        let rejected = expectation(description: "Stale delayed subscription rejects")
        let second = stale.sink(receiveCompletion: { if case .failure = $0 { rejected.fulfill() } }, receiveValue: { _ in XCTFail("Stale scope delivered data") })
        await fulfillment(of: [rejected], timeout: 1); second.cancel(); XCTAssertEqual(fixture.headStarts, 1)
    }
    @MainActor func testSavedReadTransportClosedHeadStreamFailsWithoutWaitingForBindingExpiry() async throws {
        let fixture = try LibrarySavedReadFixture(store: GuestDataStore(inMemory: true)); defer { fixture.sync.deactivate() }; try await fixture.start()
        fixture.headFetch = { _ in Empty<SavedReadHead, Error>(completeImmediately: true).eraseToAnyPublisher() }
        let stopped = expectation(description: "Closed transport fails immediately")
        let subscription = try fixture.sync.savedInvalidations(fixture.sync.captureSavedReadContext()).sink(receiveCompletion: { result in
            if case .failure = result { stopped.fulfill() } else { XCTFail("Closed head stream silently finished") }
        }, receiveValue: { _ in XCTFail("Empty transport emitted a head") })
        await fulfillment(of: [stopped], timeout: 1); subscription.cancel()
    }
    @MainActor func testSavedReadTransportRejectsLateHydrationAfterBindingRenewalAndAccountSwitch() async throws {
        let fixture = try LibrarySavedReadFixture(store: GuestDataStore(inMemory: true)); defer { fixture.sync.deactivate() }; try await fixture.start()
        let context = try fixture.sync.captureSavedReadContext(); var release: CheckedContinuation<SavedReferenceReply, Never>?
        fixture.referenceFetch = { _, _ in await withCheckedContinuation { release = $0 } }
        let late = Task { try await fixture.sync.savedReference(hadithID: fixture.target, context: context) }
        for _ in 0..<1_000 { if release != nil { break }; await Task.yield() }; let gate = try XCTUnwrap(release)
        fixture.now = context.validUntil + 1; await fixture.sync.activate(try XCTUnwrap(fixture.session)); gate.resume(returning: fixture.referenceReply)
        do { _ = try await late.value; XCTFail("Renewed binding accepted old callback") } catch { }
        fixture.referenceFetch = nil; let renewed = try fixture.sync.captureSavedReadContext()
        guard case .available = try await fixture.sync.savedReference(hadithID: fixture.target, context: renewed) else { return XCTFail("Renewed read failed") }
        var textRelease: CheckedContinuation<SavedTextReply, Never>?
        fixture.textFetch = { _, _ in await withCheckedContinuation { textRelease = $0 } }
        let text = Task { try await fixture.sync.savedText(hadithID: fixture.target, context: renewed) }
        for _ in 0..<1_000 { if textRelease != nil { break }; await Task.yield() }; let textGate = try XCTUnwrap(textRelease)
        fixture.session = .init(id: "session-b", subject: "subject-b"); await fixture.sync.activate(try XCTUnwrap(fixture.session)); textGate.resume(returning: fixture.textReply)
        do { _ = try await text.value; XCTFail("Account switch accepted old text") } catch { }
        XCTAssertEqual(fixture.sync.owner?.subject, "subject-b")
    }

    private func savedReply(_ input: String?, owner: LibrarySyncOwner, facts: [SavedFact], version: Double = 9) throws -> SavedFactsReply {
        if input == nil { return .page(.init(ownerKey: owner.key, version: version, assemblyId: "private-root-proof", input: nil, start: 0, facts: [], next: "cursor:0")) }
        guard let input, input.hasPrefix("cursor:"), let index = Int(input.dropFirst(7)), index >= 0, index <= facts.count else { throw LibrarySyncFailure.invalidReceipt }
        let rows = index < facts.count ? [facts[index]] : []
        if index + rows.count == facts.count { return .complete(.init(ownerKey: owner.key, version: version, assemblyId: "private-root-proof", input: input, start: Double(index), facts: rows, total: Double(facts.count), completion: "private-completion-proof")) }
        return .page(.init(ownerKey: owner.key, version: version, assemblyId: "private-root-proof", input: input, start: Double(index), facts: rows, next: "cursor:\(index + rows.count)"))
    }
    private func savedLargeFacts() -> [SavedFact] {
        var facts: [SavedFact] = [.folder(.init(sourceId: "empty-folder", ordinal: 0, value: .init(_id: "empty-folder", name: "Empty folder", createdAt: 1)))]
        for index in 0..<502 {
            facts.append(.item(.init(sourceId: "canonical-\(index)", ordinal: Double(facts.count), value: .init(hadithId: "private-target-\(index)", createdAt: 10, updatedAt: 11,
                bookmarkCreatedAt: index == 0 ? 1_000 : 1, favoriteCreatedAt: nil, noteContent: index == 0 ? "Private original mentions capability" : nil,
                noteCreatedAt: index == 0 ? 10 : nil, noteUpdatedAt: index == 0 ? 10 : nil, folderId: nil, folderUpdatedAt: 11))))
        }
        for index in 0..<502 { facts.append(.bookmark(.init(sourceId: "legacy-\(index)", ordinal: Double(facts.count), hadithId: "private-target-0", createdAt: Double(1_000 - index)))) }
        return facts
    }
    @MainActor func testSavedDiskCollectionFoldAndVerificationMatchBackendAfterReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("saved.store"), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        var store = GuestDataStore(storeURL: url); try store.claimGuestForSync(owner)
        try store.cacheSavedSnapshot(.init(ownerKey: owner.key, version: 1, folders: [], items: []), owner: owner)
        let original = try store.syncPartition(owner), lease = try store.beginSavedAssembly(owner)
        let facts = try JSONDecoder().decode([SavedFact].self, from: Data(LibrarySavedParityVector.factsJSON.utf8))
        var previous = "", seen = Set<String>()
        for _ in 0..<100 {
            let checkpoint = try await store.collectSavedStep(lease, isCurrent: { true }) { try self.savedReply($0, owner: owner, facts: facts) }
            let phase = savedStage(checkpoint.stage); seen.insert(phase)
            if phase != previous { store = GuestDataStore(storeURL: url); XCTAssertEqual(try store.beginSavedAssembly(owner), lease); XCTAssertEqual(try store.savedCheckpoint(lease), checkpoint); previous = phase }
            if checkpoint.stage == .prepared { break }
        }
        XCTAssertEqual(try store.savedCheckpoint(lease).stage, .prepared)
        XCTAssertTrue(seen.isSuperset(of: ["collecting", "folding", "checking_pages", "verifying", "prepared"]))
        let page = try store.preparedSavedPage(lease, after: nil)
        let expected = try JSONDecoder().decode(SavedPrivateItem.self, from: Data(LibrarySavedParityVector.expectedJSON.utf8))
        XCTAssertEqual(page.rows, [.item(expected, firstOrdinal: 0)]); XCTAssertTrue(page.done)
        XCTAssertEqual(try store.syncPartition(owner), original)
    }
    private func savedStage(_ stage: LibrarySavedStage) -> String {
        switch stage { case .collecting: "collecting"; case .folding: "folding"; case .checkingPages: "checking_pages"; case .verifying: "verifying"; case .prepared: "prepared"; case .restart: "restart"; case .unavailable: "unavailable" }
    }
    @MainActor func testSavedLargeJournalHasBoundedPagesPreservesDuplicatesAndNeverAdvancesJoinedBase() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("large.store"), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        var store = GuestDataStore(storeURL: url); try store.claimGuestForSync(owner)
        try store.cacheSavedSnapshot(.init(ownerKey: owner.key, version: 1, folders: [], items: []), owner: owner)
        let original = try store.syncPartition(owner), lease = try store.beginSavedAssembly(owner), facts = savedLargeFacts()
        var phases = Set<String>()
        for step in 0..<2_000 {
            let checkpoint: LibrarySavedCheckpoint
            do { checkpoint = try await store.collectSavedStep(lease, isCurrent: { true }) { try self.savedReply($0, owner: owner, facts: facts) } }
            catch { let prior = try store.savedCheckpoint(lease); XCTFail("Saved step \(step), stage \(savedStage(prior.stage)), next \(prior.next): \(error)"); return }
            let phase = savedStage(checkpoint.stage)
            if !phases.contains(phase) || step == 17 {
                phases.insert(phase); store = GuestDataStore(storeURL: url); XCTAssertEqual(try store.savedCheckpoint(lease), checkpoint)
            }
            if checkpoint.stage == .prepared { break }
            if step == 20 { XCTAssertThrowsError(try store.preparedSavedPage(lease, after: nil)) }
        }
        let checkpoint = try store.savedCheckpoint(lease)
        XCTAssertEqual(checkpoint.stage, .prepared); XCTAssertEqual(checkpoint.next, 1_005); XCTAssertEqual(checkpoint.counts, .init(items: 502, folders: 1))
        var cursor: String?, values: [LibrarySavedProjection] = []
        repeat {
            let page = try store.preparedSavedPage(lease, after: cursor); XCTAssertLessThanOrEqual(page.rows.count, GuestDataStore.savedStepLimit); values += page.rows; cursor = page.next
            if page.done { break }
        } while true
        XCTAssertEqual(values.count, 503)
        let rows = values.compactMap { value -> SavedPrivateItem? in if case .item(let row, _) = value { row } else { nil } }
        XCTAssertEqual(Set(rows.map(\.hadithId)).count, 502)
        XCTAssertEqual(rows.first(where: { $0.hadithId == "private-target-0" })?.bookmarkCreatedAt, 499)
        XCTAssertEqual(rows.first(where: { $0.hadithId == "private-target-0" })?.noteContent, "Private original mentions capability")
        var start = 0, raw = 0
        repeat { let page = try store.savedRawPage(lease, start: start); XCTAssertLessThanOrEqual(page.facts.count, GuestDataStore.savedStepLimit); raw += page.facts.count; start = page.next; if start == checkpoint.next { break } } while true
        XCTAssertEqual(raw, facts.count); XCTAssertEqual(try store.syncPartition(owner), original)
    }

    @MainActor func testSavedHexOrdinalDiskOrderingMatchesCursorRanges() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), store = GuestDataStore(storeURL: directory.appendingPathComponent("order.store"))
        try store.claimGuestForSync(owner); let lease = try store.beginSavedAssembly(owner), facts = Array(savedLargeFacts().prefix(32))
        for _ in 0...facts.count { _ = try await store.collectSavedStep(lease, isCurrent: { true }) { try self.savedReply($0, owner: owner, facts: facts) } }
        var start = 0, ordinals: [Int] = []
        while start < facts.count { let page = try store.savedRawPage(lease, start: start); ordinals += page.facts.map { Int($0.ordinalValue) }; start = page.next }
        XCTAssertEqual(ordinals, Array(0..<32))
    }
    @MainActor func testOutcomeTechnicalHashOrderingPreservesEveryExportWindow() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), store = GuestDataStore(storeURL: directory.appendingPathComponent("outcome-order.store"))
        try store.claimGuestForSync(owner)
        var expected = Set<String>()
        for index in 0..<101 {
            let proof = taggedOutcomeProof(owner, count: 0, tag: "technical-order-\(index)")
            expected.insert(try LibraryOutcomeBinding(owner: owner, committed: proof).key)
            try await collectExportFacts(proof, owner: owner, count: 0, store: store)
        }
        let fence = try await store.prepareOutcomeExport(owner, isCurrent: { true }); var after: String?, found = Set<String>()
        for _ in 0..<10 {
            let page = try store.outcomeExportEntries(fence, after: after)
            if page.isEmpty { break }
            for entry in page { XCTAssertTrue(found.insert(entry.binding.key).inserted) }
            after = page.last?.binding.key
        }
        XCTAssertTrue(found == expected, "Technical export windows must preserve all101 unique identities; found \(found.count)")
    }

    @MainActor private func prepareSaved(_ store: GuestDataStore, lease: LibrarySavedLease, facts: [SavedFact], version: Double = 9) async throws {
        for _ in 0..<(facts.count * 3 + 100) {
            if try await store.collectSavedStep(lease, isCurrent: { true }, fetch: { try self.savedReply($0, owner: lease.owner, facts: facts, version: version) }).stage == .prepared { return }
        }; XCTFail("Saved preparation did not finish")
    }
    private func terminalSavedReply(_ checkpoint: LibrarySavedCheckpoint) throws -> SavedFactsReply {
        let position = try XCTUnwrap(checkpoint.position), token = position.continuation.token
        return .complete(.init(ownerKey: position.owner.key, version: position.version, assemblyId: position.assemblyID, input: token, start: Double(position.nextOrdinal), facts: [], total: Double(position.nextOrdinal), completion: token))
    }
    @MainActor private func activateSaved(_ store: GuestDataStore, _ lease: LibrarySavedLease) async throws -> LibrarySavedActiveGeneration {
        let reply = try terminalSavedReply(store.savedCheckpoint(lease))
        guard case .active(let handle) = try await store.activateSavedGeneration(lease, isCurrent: { true }, fetch: { _ in reply }) else { throw LibrarySyncFailure.invalidReceipt }
        return handle
    }
    @MainActor func testSavedActivationRequiresExactFinalCheckAndReplaysWithoutClockChange() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("activation.store"), store = GuestDataStore(storeURL: url), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        try store.claimGuestForSync(owner); let original = try store.syncPartition(owner), lease = try store.beginSavedAssembly(owner)
        XCTAssertNil(try store.activeSavedGeneration(owner))
        do { _ = try await store.activateSavedGeneration(lease, isCurrent: { true }) { _ in XCTFail("Incomplete candidate queried completion"); throw LibrarySyncFailure.invalidReceipt }; XCTFail("Incomplete candidate activated") } catch { }
        let facts = try JSONDecoder().decode([SavedFact].self, from: Data(LibrarySavedParityVector.factsJSON.utf8)); try await prepareSaved(store, lease: lease, facts: facts)
        let prepared = try store.savedCheckpoint(lease)
        do { _ = try await store.activateSavedGeneration(lease, isCurrent: { true }) { _ in .complete(.init(ownerKey: owner.key, version: 10, assemblyId: "private-root-proof", input: "private-completion-proof", start: Double(facts.count), facts: [], total: Double(facts.count), completion: "private-completion-proof")) }; XCTFail("Changed terminal revision activated") } catch { }
        do { _ = try await store.activateSavedGeneration(lease, isCurrent: { true }) { _ in throw LibrarySyncFailure.storeUnavailable }; XCTFail("Failed network activated") } catch { }
        XCTAssertEqual(try store.savedCheckpoint(lease), prepared); XCTAssertNil(try store.activeSavedGeneration(owner))
        let fence = try await store.prepareOutcomeExport(owner, isCurrent: { true }), active = try await activateSaved(store, lease)
        XCTAssertThrowsError(try store.validateOutcomeExport(fence)); XCTAssertEqual(active.version, 9)
        let stable = try await store.prepareOutcomeExport(owner, isCurrent: { true })
        let replay = try await store.activateSavedGeneration(lease, isCurrent: { true }) { _ in XCTFail("Exact activation replay queried server"); throw LibrarySyncFailure.invalidReceipt }
        XCTAssertEqual(replay, .active(active)); XCTAssertNoThrow(try store.validateOutcomeExport(stable))
        let reopened = GuestDataStore(storeURL: url)
        XCTAssertEqual(try reopened.activeSavedGeneration(owner), active); XCTAssertEqual(try reopened.activeSavedPage(active, after: nil).rows, try store.preparedSavedPage(lease, after: nil).rows)
        XCTAssertEqual(try reopened.syncPartition(owner), original)
    }
    @MainActor func testSavedThreeGenerationsKeepOldActiveUntilCommitAndCleanRetiredRowsInBatches() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("generations.store"), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        var store = GuestDataStore(storeURL: url); try store.claimGuestForSync(owner)
        let facts: [SavedFact] = (0..<17).map { .note(.init(sourceId: "note-\($0)", ordinal: Double($0), hadithId: "target-\($0)", content: "Retained private note", createdAt: 1, updatedAt: 2)) }
        let first = try store.beginSavedAssembly(owner); try await prepareSaved(store, lease: first, facts: facts); let old = try await activateSaved(store, first)
        let second = try store.beginSavedAssembly(owner); XCTAssertEqual(second.epoch, first.epoch); XCTAssertNotEqual(second.generation, first.generation)
        XCTAssertEqual(try store.activeSavedPage(old, after: nil).rows.count, 8)
        try await prepareSaved(store, lease: second, facts: facts, version: 10); let active = try await activateSaved(store, second)
        XCTAssertThrowsError(try store.activeSavedPage(old, after: nil)); XCTAssertThrowsError(try store.beginSavedAssembly(owner))
        let fence = try await store.prepareOutcomeExport(owner, isCurrent: { true }), metadata = try store.savedExportRecords(fence, section: 0, after: nil)
        let exported = String(decoding: try JSONEncoder().encode(metadata.values), as: UTF8.self)
        XCTAssertTrue(exported.contains("retiringGeneration")); XCTAssertTrue(exported.contains(first.generation)); XCTAssertTrue(exported.contains(second.generation)); XCTAssertFalse(exported.contains("private-completion-proof"))
        XCTAssertTrue(try store.cleanupSavedGenerationStep(owner))
        let container = try ModelContainer(for: GuestDataStore.schema, configurations: [ModelConfiguration(schema: GuestDataStore.schema, url: url)]), inspection = ModelContext(container), collection = first.collection
        XCTAssertEqual(try inspection.fetchCount(FetchDescriptor<GuestSavedFactRow>(predicate: #Predicate { $0.collectionKey == collection })), 9)
        store = GuestDataStore(storeURL: url)
        for _ in 0..<100 { if try !store.cleanupSavedGenerationStep(owner) { break } }
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<GuestSavedFactRow>(predicate: #Predicate { $0.collectionKey == collection })), 0)
        XCTAssertEqual(try store.activeSavedGeneration(owner), active)
        let third = try store.beginSavedAssembly(owner); try await prepareSaved(store, lease: third, facts: [], version: 11); let newest = try await activateSaved(store, third)
        XCTAssertEqual(newest.version, 11); XCTAssertTrue(try store.activeSavedPage(newest, after: nil).rows.isEmpty); XCTAssertThrowsError(try store.activeSavedPage(active, after: nil))
        try store.beginDeletion(subject: owner.subject, namespace: owner.namespace); XCTAssertThrowsError(try store.activeSavedPage(newest, after: nil))
    }
    @MainActor func testSavedStoppedRefreshAndOccupiedRetirementPreserveActiveAndPreparedData() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), store = GuestDataStore(storeURL: directory.appendingPathComponent("stopped.store"))
        try store.claimGuestForSync(owner); let first = try store.beginSavedAssembly(owner); try await prepareSaved(store, lease: first, facts: []); let old = try await activateSaved(store, first)
        let second = try store.beginSavedAssembly(owner); try await prepareSaved(store, lease: second, facts: [], version: 10)
        let stopped = try await store.activateSavedGeneration(second, isCurrent: { true }) { _ in .restart(.init(reason: "saved_changed")) }
        XCTAssertEqual(stopped, .restart); XCTAssertEqual(try store.activeSavedGeneration(owner), old)
        let third = try store.replaceSavedCandidate(second); XCTAssertThrowsError(try store.replaceSavedCandidate(third)); XCTAssertThrowsError(try store.savedCheckpoint(second))
        try await prepareSaved(store, lease: third, facts: [], version: 11); let prepared = try store.savedCheckpoint(third)
        do { _ = try await activateSaved(store, third); XCTFail("Retirement overwritten") } catch { }
        XCTAssertEqual(try store.savedCheckpoint(third), prepared); XCTAssertEqual(try store.activeSavedGeneration(owner), old)
        for _ in 0..<100 { if try !store.cleanupSavedGenerationStep(owner) { break } }
        let active = try await activateSaved(store, third)
        for _ in 0..<100 { if try !store.cleanupSavedGenerationStep(owner) { break } }
        let fourth = try store.beginSavedAssembly(owner); try await prepareSaved(store, lease: fourth, facts: [], version: 12)
        let unavailable = try await store.activateSavedGeneration(fourth, isCurrent: { true }) { _ in .unavailable(.init(reason: .pageTooLarge)) }
        XCTAssertEqual(unavailable, .unavailable(.pageTooLarge)); XCTAssertEqual(try store.activeSavedGeneration(owner), active)
    }
    @MainActor func testSavedFinalCheckCannotActivateAfterCandidateReplacementSessionChangeOrErase() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("races.store"), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), store = GuestDataStore(storeURL: url)
        try store.claimGuestForSync(owner)
        for mode in 0..<3 {
            let lease = try store.beginSavedAssembly(owner); try await prepareSaved(store, lease: lease, facts: [])
            let reply = try terminalSavedReply(store.savedCheckpoint(lease)), clone = GuestDataStore(storeURL: url)
            var current = true, release: CheckedContinuation<SavedFactsReply, Never>?
            let late = Task { try await clone.activateSavedGeneration(lease, isCurrent: { current }) { _ in await withCheckedContinuation { release = $0 } } }
            for _ in 0..<1_000 { if release != nil { break }; await Task.yield() }; let gate = try XCTUnwrap(release)
            if mode == 0 { _ = try store.replaceSavedCandidate(lease) }
            else if mode == 1 { current = false }
            else { try store.beginDeletion(subject: owner.subject, namespace: owner.namespace) }
            gate.resume(returning: reply)
            do { _ = try await late.value; XCTFail("Stale completion activated") } catch { }
            if mode < 2 {
                XCTAssertNil(try store.activeSavedGeneration(owner))
                if mode == 1 { _ = try store.replaceSavedCandidate(lease) }
                for _ in 0..<100 { if try !store.cleanupSavedGenerationStep(owner) { break } }
            }
        }
    }
    @MainActor func testSavedOverlappingCloneActivationsCommitOnePointerAndOneClockTransition() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("overlap.store"), store = GuestDataStore(storeURL: url), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        try store.claimGuestForSync(owner); let lease = try store.beginSavedAssembly(owner); try await prepareSaved(store, lease: lease, facts: [])
        let reply = try terminalSavedReply(store.savedCheckpoint(lease)), first = GuestDataStore(storeURL: url), second = GuestDataStore(storeURL: url)
        var releaseA: CheckedContinuation<SavedFactsReply, Never>?, releaseB: CheckedContinuation<SavedFactsReply, Never>?
        let a = Task { try await first.activateSavedGeneration(lease, isCurrent: { true }) { _ in await withCheckedContinuation { releaseA = $0 } } }
        let b = Task { try await second.activateSavedGeneration(lease, isCurrent: { true }) { _ in await withCheckedContinuation { releaseB = $0 } } }
        for _ in 0..<1_000 { if releaseA != nil && releaseB != nil { break }; await Task.yield() }
        let gateA = try XCTUnwrap(releaseA), gateB = try XCTUnwrap(releaseB)
        gateA.resume(returning: reply); let accepted = try await a.value
        let fence = try await store.prepareOutcomeExport(owner, isCurrent: { true })
        gateB.resume(returning: reply); let repeated = try await b.value
        XCTAssertEqual(repeated, accepted); XCTAssertNoThrow(try store.validateOutcomeExport(fence))
        guard case .active(let handle) = accepted else { return XCTFail("Valid generation did not activate") }
        XCTAssertEqual(try GuestDataStore(storeURL: url).activeSavedGeneration(owner), handle)
    }
    @MainActor func testSavedOlderVerifiedRefreshCannotRegressActiveRevision() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), store = GuestDataStore(storeURL: directory.appendingPathComponent("revision.store"))
        try store.claimGuestForSync(owner); let first = try store.beginSavedAssembly(owner); try await prepareSaved(store, lease: first, facts: [], version: 10); let active = try await activateSaved(store, first)
        let second = try store.beginSavedAssembly(owner); try await prepareSaved(store, lease: second, facts: [], version: 9)
        let prepared = try store.savedCheckpoint(second), fence = try await store.prepareOutcomeExport(owner, isCurrent: { true })
        do { _ = try await activateSaved(store, second); XCTFail("Older private revision activated") } catch { }
        XCTAssertEqual(try store.activeSavedGeneration(owner), active); XCTAssertEqual(try store.savedCheckpoint(second), prepared); XCTAssertNoThrow(try store.validateOutcomeExport(fence))
    }
    @MainActor func testSavedActivationMigratesActualPriorSavedSchemaDisk() async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/SavedSchemaV3.store.gz")
        let input = try XCTUnwrap(gzopen(fixture.path, "rb")), directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("old-saved.store"); FileManager.default.createFile(atPath: url.path, contents: nil)
        let output = try FileHandle(forWritingTo: url); var bytes = [UInt8](repeating: 0, count: 32_768)
        while true { let count = gzread(input, &bytes, UInt32(bytes.count)); if count == 0 { break }; guard count > 0 else { throw LibrarySyncFailure.storeUnavailable }; try output.write(contentsOf: bytes.prefix(Int(count))) }
        gzclose(input); try output.close()
        var database: OpaquePointer?; XCTAssertEqual(sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        var statement: OpaquePointer?; guard sqlite3_prepare_v2(database, "SELECT ZLEASEDATA FROM ZGUESTSAVEDASSEMBLY LIMIT 1", -1, &statement, nil) == SQLITE_OK, sqlite3_step(statement) == SQLITE_ROW else { sqlite3_close(database); throw LibrarySyncFailure.storeUnavailable }
        let lease = try JSONDecoder().decode(LibrarySavedLease.self, from: Data(bytes: sqlite3_column_blob(statement, 0), count: Int(sqlite3_column_bytes(statement, 0))))
        sqlite3_finalize(statement); sqlite3_close(database)
        let store = GuestDataStore(storeURL: url)
        let migrated = try ModelContainer(for: GuestDataStore.schema, configurations: [ModelConfiguration(schema: GuestDataStore.schema, url: url)])
        let migratedHeader = try XCTUnwrap(ModelContext(migrated).fetch(FetchDescriptor<GuestSavedAssembly>()).first)
        XCTAssertFalse(migratedHeader.rowMode)
        XCTAssertNil(try store.activeSavedGeneration(lease.owner)); XCTAssertEqual(try store.savedCheckpoint(lease).next, 1_005)
        for _ in 0..<1_000 { if try store.advanceSavedAssembly(lease).stage == .prepared { break } }
        let active = try await activateSaved(store, lease)
        XCTAssertEqual(active.version, 9); XCTAssertEqual(try store.savedCheckpoint(lease).counts, .init(items: 502, folders: 1)); XCTAssertEqual(try store.activeSavedPage(active, after: nil).rows.count, 8)
        XCTAssertEqual(try GuestDataStore(storeURL: url).activeSavedGeneration(lease.owner), active)
    }
    @MainActor func testSavedHistoricalReplayAndChangedRetryPreserveExactOriginal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("replay.store"), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), store = GuestDataStore(storeURL: url)
        try store.claimGuestForSync(owner); let lease = try store.beginSavedAssembly(owner)
        let facts = Array(try JSONDecoder().decode([SavedFact].self, from: Data(LibrarySavedParityVector.factsJSON.utf8)).prefix(2))
        _ = try await store.collectSavedStep(lease, isCurrent: { true }) { try self.savedReply($0, owner: owner, facts: facts) }
        let clone = GuestDataStore(storeURL: url); var input: String?, release: CheckedContinuation<SavedFactsReply, Never>?
        let replay = Task { try await clone.collectSavedStep(lease, isCurrent: { true }) { requested in input = requested; return await withCheckedContinuation { release = $0 } } }
        for _ in 0..<1_000 { if release != nil { break }; await Task.yield() }
        let gate = try XCTUnwrap(release)
        _ = try await store.collectSavedStep(lease, isCurrent: { true }) { try self.savedReply($0, owner: owner, facts: facts) }
        let before = try store.savedCheckpoint(lease), fence = try await store.prepareOutcomeExport(owner, isCurrent: { true })
        gate.resume(returning: try savedReply(input, owner: owner, facts: facts)); release = nil
        let replayed = try await replay.value; XCTAssertEqual(replayed, before); try store.validateOutcomeExport(fence)
        guard case .item(let first) = facts[0] else { return XCTFail("Missing canonical fixture") }
        do {
            _ = try await store.collectSavedStep(lease, isCurrent: { true }) { requested in
                .complete(.init(ownerKey: owner.key, version: 9, assemblyId: "private-root-proof", input: requested, start: 1, facts: [.item(.init(sourceId: first.sourceId, ordinal: 1, value: first.value))], total: 2, completion: "private-completion-proof"))
            }; XCTFail("Reused source identity accepted")
        } catch { }
        XCTAssertEqual(try store.savedCheckpoint(lease), before); XCTAssertEqual(try store.savedRawPage(lease, start: 0).facts.count, 1)
        let clone2 = GuestDataStore(storeURL: url); var input2: String?, release2: CheckedContinuation<SavedFactsReply, Never>?
        let changed = Task { try await clone2.collectSavedStep(lease, isCurrent: { true }) { requested in input2 = requested; return await withCheckedContinuation { release2 = $0 } } }
        for _ in 0..<1_000 { if release2 != nil { break }; await Task.yield() }
        let gate2 = try XCTUnwrap(release2)
        _ = try await store.collectSavedStep(lease, isCurrent: { true }) { try self.savedReply($0, owner: owner, facts: facts) }; let terminal = try store.savedCheckpoint(lease)
        guard case .bookmark(let second) = facts[1] else { return XCTFail("Missing bookmark fixture") }
        gate2.resume(returning: .complete(.init(ownerKey: owner.key, version: 9, assemblyId: "private-root-proof", input: input2, start: 1, facts: [.bookmark(.init(sourceId: second.sourceId, ordinal: 1, hadithId: second.hadithId, createdAt: second.createdAt + 1))], total: 2, completion: "private-completion-proof"))); release2 = nil
        do { _ = try await changed.value; XCTFail("Changed retry accepted") } catch { }
        XCTAssertEqual(try store.savedCheckpoint(lease), terminal); try await prepareSaved(store, lease: lease, facts: facts)
    }
    @MainActor func testSavedLogicalFailureRollsBackRowsAndCheckpointTogether() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("rollback.store"), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), store = GuestDataStore(storeURL: url)
        try store.claimGuestForSync(owner); let lease = try store.beginSavedAssembly(owner)
        let facts = try JSONDecoder().decode([SavedFact].self, from: Data(LibrarySavedParityVector.factsJSON.utf8))
        _ = try await store.collectSavedStep(lease, isCurrent: { true }) { try self.savedReply($0, owner: owner, facts: facts) }
        let original = try store.savedCheckpoint(lease), container = try ModelContainer(for: GuestDataStore.schema, configurations: [ModelConfiguration(schema: GuestDataStore.schema, url: url)]), context = ModelContext(container)
        context.autosaveEnabled = false
        let key = lease.key; var query = FetchDescriptor<GuestSavedAssembly>(predicate: #Predicate { $0.key == key }); query.fetchLimit = 2
        let header = try XCTUnwrap(context.fetch(query).first)
        var invalid = original; invalid.pages = Int(LibrarySavedPolicy.maxInteger); header.checkpointData = try JSONEncoder().encode(invalid); try context.save()
        do { _ = try await store.collectSavedStep(lease, isCurrent: { true }) { try self.savedReply($0, owner: owner, facts: facts) }; XCTFail("Invalid checkpoint committed") } catch { }
        let reopened = GuestDataStore(storeURL: url); XCTAssertEqual(try reopened.savedCheckpoint(lease), invalid)
        let inspection = ModelContext(container)
        XCTAssertEqual(try inspection.fetchCount(FetchDescriptor<GuestSavedFactRow>()), 0); XCTAssertEqual(try inspection.fetchCount(FetchDescriptor<GuestSavedPageRow>()), 1)
        header.checkpointData = try JSONEncoder().encode(original); try context.save(); try await prepareSaved(reopened, lease: lease, facts: facts)
    }
    @MainActor func testSavedRowsStreamIntoPortableExportAndShareItsMutationFence() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GuestDataStore(storeURL: directory.appendingPathComponent("export.store"), exportDirectory: directory.appendingPathComponent("exports")), fixture = LibraryFacadeFixture(store: store)
        defer { fixture.stop() }; await fixture.start()
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), lease = try store.beginSavedAssembly(owner)
        let own: [SavedFact] = [.note(.init(sourceId: "own-source", ordinal: 0, hadithId: "own-target", content: "Own note says capability", createdAt: 1, updatedAt: 2))]
        try await prepareSaved(store, lease: lease, facts: own)
        let peers = [(LibrarySyncOwner(key: "old-owner", subject: owner.subject), "Old owner retained note"), (LibrarySyncOwner(key: "foreign-owner", subject: "foreign-subject"), "Foreign private note"), (LibrarySyncOwner(key: "old-owner", subject: owner.subject, namespace: "other-deployment"), "Other deployment private note")]
        for (peer, text) in peers {
            try store.claimGuestForSync(peer); let candidate = try store.beginSavedAssembly(peer)
            let facts: [SavedFact] = [.note(.init(sourceId: "peer-source", ordinal: 0, hadithId: "peer-target", content: text, createdAt: 1, updatedAt: 2))]
            for _ in 0..<2 { _ = try await store.collectSavedStep(candidate, isCurrent: { true }) { try self.savedReply($0, owner: peer, facts: facts) } }
        }
        // Simulate an older owner partition disappearing while its private journal remains.
        let container = try ModelContainer(for: GuestDataStore.schema, configurations: [ModelConfiguration(schema: GuestDataStore.schema, url: directory.appendingPathComponent("export.store"))]), orphanContext = ModelContext(container), oldKey = peers[0].0.storageKey
        var oldPartition = FetchDescriptor<GuestLibraryPartition>(predicate: #Predicate { $0.ownerKey == oldKey }); oldPartition.fetchLimit = 2
        for row in try orphanContext.fetch(oldPartition) { orphanContext.delete(row) }; try orphanContext.save()
        let captured = try fixture.sync.captureWriteContext(), exported = try await fixture.sync.preparePortableExport(server: .object([:]), context: captured, fileName: "saved.json")
        defer { try? fixture.sync.discardPreparedExport(exported) }
        let data = try Data(contentsOf: exported.url), json = try JSONDecoder().decode(LibraryExportValue.self, from: data)
        guard case .object(let fields) = json else { return XCTFail("Export is not an object") }; XCTAssertNotNil(fields["localSavedEvidence"])
        XCTAssertTrue(exportContains(json, text: "Own note says capability")); XCTAssertTrue(exportContains(json, text: "Old owner retained note"))
        XCTAssertFalse(exportContains(json, text: "Foreign private note")); XCTAssertFalse(exportContains(json, text: "Other deployment private note"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("private-root-proof")); XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("private-completion-proof"))
        let fence = try await store.prepareOutcomeExport(owner, isCurrent: { true }), another = LibrarySyncOwner(key: "another-old-owner", subject: owner.subject)
        try store.claimGuestForSync(another); _ = try store.beginSavedAssembly(another)
        XCTAssertThrowsError(try store.validateOutcomeExport(fence))
    }
    @MainActor func testSavedErasureFencesSuspendedReplyAndResumesAfterReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("erase.store"), store = GuestDataStore(storeURL: url), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), other = LibrarySyncOwner(key: "owner-b", subject: "subject-b")
        try store.claimGuestForSync(owner); try store.claimGuestForSync(other)
        let lease = try store.beginSavedAssembly(owner), peer = try store.beginSavedAssembly(other), facts = Array(savedLargeFacts().prefix(32))
        for _ in 0..<18 { _ = try await store.collectSavedStep(lease, isCurrent: { true }) { try self.savedReply($0, owner: owner, facts: facts) } }
        let peerBefore = try store.savedCheckpoint(peer), clone = GuestDataStore(storeURL: url)
        var input: String?, release: CheckedContinuation<SavedFactsReply, Never>?
        let late = Task { try await clone.collectSavedStep(lease, isCurrent: { true }) { requested in input = requested; return await withCheckedContinuation { release = $0 } } }
        for _ in 0..<1_000 { if release != nil { break }; await Task.yield() }; let gate = try XCTUnwrap(release)
        try store.beginDeletion(subject: owner.subject, namespace: owner.namespace); XCTAssertTrue(try store.eraseSavedStep(subject: owner.subject, namespace: owner.namespace))
        let container = try ModelContainer(for: GuestDataStore.schema, configurations: [ModelConfiguration(schema: GuestDataStore.schema, url: url)]), inspection = ModelContext(container), subject = owner.subject
        XCTAssertEqual(try inspection.fetchCount(FetchDescriptor<GuestSavedFactRow>(predicate: #Predicate { $0.subject == subject })), 9)
        gate.resume(returning: try savedReply(input, owner: owner, facts: facts)); release = nil
        do { _ = try await late.value; XCTFail("Erased reply recreated rows") } catch { }
        let reopened = GuestDataStore(storeURL: url); try await reopened.markDeletionBackendComplete(subject: owner.subject, namespace: owner.namespace)
        XCTAssertEqual(try reopened.savedCheckpoint(peer), peerBefore); XCTAssertEqual(try reopened.deletionPhase(subject: owner.subject, namespace: owner.namespace), .identityPending)
        let fresh = ModelContext(container)
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<GuestSavedFactRow>(predicate: #Predicate { $0.subject == subject })), 0)
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<GuestSavedPageRow>(predicate: #Predicate { $0.subject == subject })), 0)
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<GuestSavedAssembly>(predicate: #Predicate { $0.subject == subject })), 0)
    }
    @MainActor func testSavedOwnerResetPreservesOtherOwnerAndSharedClock() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GuestDataStore(storeURL: directory.appendingPathComponent("reset.store")), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), old = LibrarySyncOwner(key: "old-owner", subject: "subject-a")
        try store.claimGuestForSync(owner); try store.claimGuestForSync(old)
        _ = try store.beginSavedAssembly(owner); let lease = try store.beginSavedAssembly(old)
        let facts: [SavedFact] = [.note(.init(sourceId: "source", ordinal: 0, hadithId: "target", content: "Old owner retained note", createdAt: 1, updatedAt: 2))]
        for _ in 0..<2 { _ = try await store.collectSavedStep(lease, isCurrent: { true }) { try self.savedReply($0, owner: old, facts: facts) } }
        let checkpoint = try store.savedCheckpoint(lease), before = try await store.prepareOutcomeExport(old, isCurrent: { true })
        try store.resetSyncPartitionForTesting(owner)
        XCTAssertEqual(try store.savedCheckpoint(lease), checkpoint); XCTAssertEqual(try store.savedRawPage(lease, start: 0).facts.count, 1)
        let after = try await store.prepareOutcomeExport(old, isCurrent: { true }); guard case .present = after.version else { return XCTFail("Shared clock was dropped") }
        XCTAssertNotEqual(before, after)
    }
    @MainActor func testSavedAdditiveSchemaOpensOldDiskWithoutChangingExistingEvidence() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("old.store"), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        var original = LibraryPartitionState(); original.savedSnapshot = .init(ownerKey: owner.key, version: 1, folders: [], items: [])
        let proof = taggedOutcomeProof(owner, count: 1, tag: "old-evidence"), binding = try LibraryOutcomeBinding(owner: owner, committed: proof)
        do {
            let schema = Schema([GuestBookmark.self, GuestNote.self, GuestFavorite.self, GuestSavedFolder.self, GuestSavedMembership.self, GuestReadingProgress.self, GuestLibraryPartition.self, GuestAccountDeletion.self, GuestOutcomeScope.self, GuestOutcomeHeader.self, GuestOutcomeMember.self, GuestOutcomeClock.self, GuestOutcomeInventory.self, GuestOutcomeInventoryMigration.self, GuestLibraryExportArtifact.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)]), context = ModelContext(container)
            context.insert(GuestLibraryPartition(ownerKey: owner.storageKey, subject: owner.subject, stateData: try JSONEncoder().encode(original)))
            let scope = GuestOutcomeScope(binding: binding); context.insert(scope)
            context.insert(try GuestOutcomeHeader(binding: binding, generation: scope.generation, checkpoint: .init(counts: .init(deleted: 1), status: .complete)))
            context.insert(try GuestOutcomeMember(binding: binding, row: .init(ordinal: 0, memberId: "old-member", hadithId: "old-target", disposition: .deleted)))
            context.insert(GuestOutcomeInventory(binding: binding)); context.insert(try GuestOutcomeInventoryMigration())
            let clock = GuestOutcomeClock(subject: owner.subject, namespace: owner.namespace); clock.epoch = "old-clock"; clock.revision = 7; context.insert(clock)
            context.insert(GuestLibraryExportArtifact(id: "old-artifact", owner: owner)); context.insert(GuestAccountDeletion(subject: "other-deleting-subject", namespace: owner.namespace)); try context.save()
        }
        let store = GuestDataStore(storeURL: url); XCTAssertEqual(try store.syncPartition(owner), original)
        let lease = try store.beginSavedAssembly(owner); let facts = try JSONDecoder().decode([SavedFact].self, from: Data(LibrarySavedParityVector.factsJSON.utf8)); try await prepareSaved(store, lease: lease, facts: facts)
        XCTAssertEqual(try store.outcomeEvidencePage(proof, owner: owner, start: 0).rows.count, 1)
        XCTAssertEqual(try store.deletionPhase(subject: "other-deleting-subject", namespace: owner.namespace), .serverPending)
        let container = try ModelContainer(for: GuestDataStore.schema, configurations: [ModelConfiguration(schema: GuestDataStore.schema, url: url)]), inspection = ModelContext(container)
        let clocks = try inspection.fetch(FetchDescriptor<GuestOutcomeClock>())
        XCTAssertEqual(clocks.first?.epoch, "old-clock"); XCTAssertGreaterThan(clocks.first?.revision ?? 0, 7)
        XCTAssertEqual(try inspection.fetchCount(FetchDescriptor<GuestLibraryExportArtifact>()), 1)
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(database) }
        for (table, column) in [("ZGUESTSAVEDFACTROW", "ZKEY"), ("ZGUESTSAVEDPAGEROW", "ZSEQUENCEKEY"), ("ZGUESTSAVEDPROJECTIONROW", "ZKEY")] {
            var statement: OpaquePointer?
            let sql = "EXPLAIN QUERY PLAN SELECT \(column) FROM \(table) WHERE \(column)>'0' AND \(column)<'~' ORDER BY \(column) LIMIT 8"
            XCTAssertEqual(sqlite3_prepare_v2(database, sql, -1, &statement, nil), SQLITE_OK)
            var plans: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW { if let value = sqlite3_column_text(statement, 3) { plans.append(String(cString: value)) } }
            sqlite3_finalize(statement)
            XCTAssertTrue(plans.contains { $0.contains("SEARCH") && $0.contains("INDEX") }, "Technical range query must use its real indexed key: \(plans)")
        }
    }

    @MainActor func testSavedTokenCyclesStoppedReadsAndFreshGenerationRemainNonactivating() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GuestDataStore(storeURL: directory.appendingPathComponent("cycles.store")), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        try store.claimGuestForSync(owner); let original = try store.syncPartition(owner), lease = try store.beginSavedAssembly(owner)
        XCTAssertThrowsError(try store.eraseSavedStep(subject: owner.subject, namespace: owner.namespace, ownerKey: owner.storageKey))
        _ = try await store.collectSavedStep(lease, isCurrent: { true }) { try self.savedReply($0, owner: owner, facts: []) }
        _ = try await store.collectSavedStep(lease, isCurrent: { true }) { input in .page(.init(ownerKey: owner.key, version: 9, assemblyId: "private-root-proof", input: input, start: 0, facts: [], next: "cursor:1")) }
        let before = try store.savedCheckpoint(lease)
        do { _ = try await store.collectSavedStep(lease, isCurrent: { true }) { input in .page(.init(ownerKey: owner.key, version: 9, assemblyId: "private-root-proof", input: input, start: 0, facts: [], next: "cursor:0")) }; XCTFail("Historical cursor cycle accepted") } catch { }
        XCTAssertEqual(try store.savedCheckpoint(lease), before)
        let stopped = try await store.collectSavedStep(lease, isCurrent: { true }) { _ in .unavailable(.init(reason: .sourceTooLarge)) }
        XCTAssertEqual(stopped.stage, .unavailable(.sourceTooLarge)); XCTAssertThrowsError(try store.preparedSavedPage(lease, after: nil))
        let unchanged = try await store.collectSavedStep(lease, isCurrent: { true }) { _ in throw LibrarySyncFailure.invalidReceipt }; XCTAssertEqual(unchanged, stopped)
        try store.beginSavedErase(subject: owner.subject, namespace: owner.namespace, ownerKey: owner.storageKey)
        for _ in 0..<20 { if try !store.eraseSavedStep(subject: owner.subject, namespace: owner.namespace, ownerKey: owner.storageKey) { break } }
        let next = try store.beginSavedAssembly(owner); XCTAssertNotEqual(next, lease); XCTAssertThrowsError(try store.savedCheckpoint(lease))
        var current = true
        do { _ = try await store.collectSavedStep(next, isCurrent: { current }) { input in current = false; return try self.savedReply(input, owner: owner, facts: []) }; XCTFail("Stale session reply committed") } catch { }
        XCTAssertEqual(try store.savedCheckpoint(next).pages, 0); XCTAssertEqual(try store.syncPartition(owner), original)
    }
    @MainActor func testSavedMissingRawFactCannotBecomePreparedAfterReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("missing.store"), store = GuestDataStore(storeURL: url), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        try store.claimGuestForSync(owner); let lease = try store.beginSavedAssembly(owner), facts = Array(savedLargeFacts().prefix(32))
        for _ in 0...facts.count { _ = try await store.collectSavedStep(lease, isCurrent: { true }) { try self.savedReply($0, owner: owner, facts: facts) } }
        let container = try ModelContainer(for: GuestDataStore.schema, configurations: [ModelConfiguration(schema: GuestDataStore.schema, url: url)]), context = ModelContext(container), key = lease.ordinalKey(8)
        var query = FetchDescriptor<GuestSavedFactRow>(predicate: #Predicate { $0.key == key }); query.fetchLimit = 2
        context.delete(try XCTUnwrap(context.fetch(query).first)); try context.save()
        let reopened = GuestDataStore(storeURL: url)
        _ = try await reopened.collectSavedStep(lease, isCurrent: { true }) { _ in throw LibrarySyncFailure.invalidReceipt }
        let before = try reopened.savedCheckpoint(lease)
        do { _ = try await reopened.collectSavedStep(lease, isCurrent: { true }) { _ in throw LibrarySyncFailure.invalidReceipt }; XCTFail("Missing fact silently skipped") } catch { }
        XCTAssertEqual(try reopened.savedCheckpoint(lease), before); XCTAssertThrowsError(try reopened.preparedSavedPage(lease, after: nil))
    }

    private struct OutcomeExportProbe: Decodable {
        struct Entry: Decodable {
            let authority: LibraryOutcomeBinding
            let expected: LibraryOutcomeCounts
            let collected: LibraryOutcomeCounts
            let status: String
            let detailComplete: Bool
            let unavailableReason: String?
            let rows: [SyncOutcomeMember]
        }
        let localOutcomeEvidence: [Entry]
    }
    private func taggedOutcomeProof(_ owner: LibrarySyncOwner, count: Int, tag: String) -> SyncCommitted {
        let base = outcomeProof(owner, count: count)
        return .init(clientKey: tag, sequence: 1, digest: tag + "-digest", revision: base.revision,
            reply: .init(ownerKey: owner.key, batchId: tag + "-batch", receipts: base.reply.receipts.map { .init(id: tag + "-operation", revision: $0.revision, outcome: $0.outcome) }))
    }
    @MainActor private func collectExportFacts(_ proof: SyncCommitted, owner: LibrarySyncOwner, count: Int, store: GuestDataStore, complete: Bool = true) async throws {
        for _ in 0..<50 {
            let value = try await store.collectOutcomeStep(proof, owner: owner, isCurrent: { true }) { self.outcomePage($0, owner: owner, count: count) }
            if value.status == .complete || !complete { return }
        }
        XCTFail("Export fixture did not finish bounded collection")
    }
    private func exportContains(_ value: LibraryExportValue, text: String) -> Bool {
        switch value {
        case .string(let current): current == text
        case .object(let fields): fields.values.contains { exportContains($0, text: text) }
        case .array(let rows): rows.contains { exportContains($0, text: text) }
        default: false
        }
    }
    @MainActor func testOutcomeExportPreservesFieldsAndIncludesOldOwnerOrphansOnlyForCapturedSubject() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("legacy.store"), root = directory.appendingPathComponent("exports")
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        let old = LibrarySyncOwner(key: "older-owner", subject: owner.subject)
        let foreign = LibrarySyncOwner(key: "foreign-owner", subject: "subject-b")
        let deployment = LibrarySyncOwner(key: "older-owner", subject: owner.subject, namespace: "other-deployment")
        // Exact pre-export schema, created before the upgraded store ever opens it.
        do {
            let schema = Schema([GuestBookmark.self, GuestNote.self, GuestFavorite.self, GuestSavedFolder.self, GuestSavedMembership.self, GuestReadingProgress.self, GuestLibraryPartition.self, GuestAccountDeletion.self, GuestOutcomeScope.self, GuestOutcomeHeader.self, GuestOutcomeMember.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)]), context = ModelContext(container)
            for target in [old, foreign, deployment] {
                let proof = taggedOutcomeProof(target, count: 1, tag: target.key), binding = try LibraryOutcomeBinding(owner: target, committed: proof)
                let scope = GuestOutcomeScope(binding: binding); context.insert(scope)
                context.insert(try GuestOutcomeHeader(binding: binding, generation: scope.generation, checkpoint: .init(counts: .init(deleted: 1), status: .complete)))
                context.insert(try GuestOutcomeMember(binding: binding, row: .init(ordinal: 0, memberId: target.key + "-member", hadithId: target.key + "-hadith", disposition: .deleted)))
            }
            try context.save()
        }
        let store = GuestDataStore(storeURL: url, exportDirectory: root), fixture = LibraryFacadeFixture(store: store)
        defer { fixture.stop() }
        await fixture.start()
        let text = "Private \"quote\" — عربى mentions arabicText, capability and pushTokens"
        XCTAssertTrue(fixture.model.saveNote(fixture.reference, content: text))
        let partial = taggedOutcomeProof(owner, count: 51, tag: "partial")
        try await collectExportFacts(partial, owner: owner, count: 51, store: store, complete: false)
        _ = try await store.collectOutcomeStep(partial, owner: owner, isCurrent: { true }) { .unavailable(.init(ownerKey: owner.key, request: $0, reason: .detailUnavailable)) }
        let captured = try fixture.sync.captureWriteContext()
        let server = LibraryExportValue.object(["sync": .object(["streams": .array([])]), "evidenceItems": .array([]), "custom": .string("server-kept")])
        let export = try await fixture.sync.preparePortableExport(server: server, context: captured, fileName: "export.json")
        let data = try Data(contentsOf: export.url), document = try JSONDecoder().decode(LibraryExportValue.self, from: data)
        let probe = try JSONDecoder().decode(OutcomeExportProbe.self, from: data)
        XCTAssertEqual(probe.localOutcomeEvidence.count, 2)
        XCTAssertTrue(probe.localOutcomeEvidence.allSatisfy { $0.authority.owner.subject == owner.subject && $0.authority.owner.namespace == owner.namespace })
        XCTAssertTrue(probe.localOutcomeEvidence.contains { $0.authority.owner.key == old.key && $0.rows.map(\.memberId) == [old.key + "-member"] })
        let retained = try XCTUnwrap(probe.localOutcomeEvidence.first { $0.status == "unavailable" })
        XCTAssertEqual(retained.expected.deleted, 51); XCTAssertEqual(retained.collected.deleted, 50); XCTAssertEqual(retained.rows.count, 50)
        XCTAssertEqual(retained.unavailableReason, "detail_unavailable"); XCTAssertFalse(retained.detailComplete)
        XCTAssertTrue(exportContains(document, text: text)); XCTAssertTrue(exportContains(document, text: "server-kept"))
        XCTAssertFalse(document.containsAnyKey(["arabicText", "englishText", "capability", "pushTokens", "adminAuditLog", "revenueCatAppUserId"]))
        try fixture.sync.discardPreparedExport(export)
        XCTAssertFalse(FileManager.default.fileExists(atPath: export.url.path))
        let reopened = GuestDataStore(storeURL: url, exportDirectory: root)
        let fence = try await reopened.prepareOutcomeExport(owner, isCurrent: { true })
        XCTAssertEqual(try reopened.outcomeExportEntries(fence, after: nil).count, 2)
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(database) }
        var query: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(database, "EXPLAIN QUERY PLAN SELECT ZKEY FROM ZGUESTOUTCOMEINVENTORY WHERE ZKEY >= 'a' AND ZKEY < 'b' ORDER BY ZKEY LIMIT 50", -1, &query, nil), SQLITE_OK)
        defer { sqlite3_finalize(query) }
        XCTAssertEqual(sqlite3_step(query), SQLITE_ROW)
        let plan = String(cString: sqlite3_column_text(query, 3))
        XCTAssertTrue(plan.contains("INDEX")); XCTAssertTrue(plan.contains("SEARCH"))
    }

    @MainActor func testOutcomeExportFenceRejectsInsertBeforeCursorVerificationAndErasure() async throws {
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), store = GuestDataStore(inMemory: true)
        try store.claimGuestForSync(owner)
        let proofs = try (0..<4).map { taggedOutcomeProof(owner, count: 1, tag: "clock-\($0)") }.sorted {
            try LibraryOutcomeBinding(owner: owner, committed: $0).key < LibraryOutcomeBinding(owner: owner, committed: $1).key
        }
        try await collectExportFacts(proofs[2], owner: owner, count: 1, store: store)
        let first = try await store.prepareOutcomeExport(owner, isCurrent: { true })
        let cursor = try XCTUnwrap(store.outcomeExportEntries(first, after: nil).first?.binding.key)
        try await collectExportFacts(proofs[0], owner: owner, count: 1, store: store)
        XCTAssertThrowsError(try store.outcomeExportEntries(first, after: cursor))
        try await collectExportFacts(proofs[3], owner: owner, count: 1, store: store, complete: false)
        let beforeVerify = try await store.prepareOutcomeExport(owner, isCurrent: { true })
        _ = try await store.collectOutcomeStep(proofs[3], owner: owner, isCurrent: { true }) { _ in XCTFail("Local verification fetched"); throw LibrarySyncFailure.invalidReceipt }
        XCTAssertThrowsError(try store.validateOutcomeExport(beforeVerify))
        let beforeErase = try await store.prepareOutcomeExport(owner, isCurrent: { true })
        let artifact = try store.beginOutcomeExportArtifact(beforeErase)
        try Data("private-prefix".utf8).write(to: artifact.directory.appendingPathComponent("document.partial"))
        try store.beginDeletion(subject: owner.subject, namespace: owner.namespace)
        try await store.markDeletionBackendComplete(subject: owner.subject, namespace: owner.namespace)
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.directory.path))
        XCTAssertThrowsError(try store.validateOutcomeExport(beforeErase))
    }

    @MainActor func testOutcomeExportMutationCancellationSwitchAndErasureDiscardPartialFiles() async throws {
        for mode in ["mutation", "persistent", "cancel", "switch", "erase"] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let store = GuestDataStore(inMemory: true, exportDirectory: root), fixture = LibraryFacadeFixture(store: store)
            defer { fixture.stop() }
            await fixture.start()
            let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), proof = taggedOutcomeProof(owner, count: 501, tag: "large")
            try await collectExportFacts(proof, owner: owner, count: 501, store: store)
            let captured = try fixture.sync.captureWriteContext()
            let task = Task { try await fixture.sync.preparePortableExport(server: .object([:]), context: captured, fileName: "export.json") }
            var sawPartial = false
            for _ in 0..<1_000 {
                let directories = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
                if directories.contains(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("document.partial").path) }) { sawPartial = true; break }
                await Task.yield()
            }
            XCTAssertTrue(sawPartial)
            switch mode {
            case "persistent":
                var invalidated = Set<URL>()
                for attempt in 0..<3 {
                    var next: URL?
                    for _ in 0..<1_000 {
                        let directories = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
                        next = directories.first { !invalidated.contains($0) && FileManager.default.fileExists(atPath: $0.appendingPathComponent("document.partial").path) }
                        if next != nil { break }; await Task.yield()
                    }
                    invalidated.insert(try XCTUnwrap(next))
                    try store.enqueueSyncChange(.init(command: .noteRemove(.init(hadithId: "changed-\(attempt)")), at: 1_000, source: .account(nil)), owner: owner)
                    await Task.yield()
                }
                XCTAssertEqual(invalidated.count, 3)
            case "cancel": task.cancel()
            case "switch": fixture.session.value = .init(id: "session-b", subject: "subject-b"); fixture.sync.deactivate()
            case "erase":
                try store.beginDeletion(subject: owner.subject, namespace: owner.namespace)
                try await store.markDeletionBackendComplete(subject: owner.subject, namespace: owner.namespace)
            default: try await collectExportFacts(taggedOutcomeProof(owner, count: 1, tag: "insert-during-export"), owner: owner, count: 1, store: store)
            }
            if mode == "mutation" {
                let prepared = try await task.value
                let probe = try JSONDecoder().decode(OutcomeExportProbe.self, from: Data(contentsOf: prepared.url))
                XCTAssertEqual(probe.localOutcomeEvidence.count, 2)
                XCTAssertTrue(probe.localOutcomeEvidence.contains { $0.authority.committed.clientKey == "insert-during-export" })
                try fixture.sync.discardPreparedExport(prepared)
            } else {
                do { _ = try await task.value; XCTFail("Canceled, erased or repeatedly changed export was published") } catch { }
            }
            let leftovers = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            XCTAssertTrue(leftovers.isEmpty)
        }
    }

    @MainActor func testOutcomeExportRejectsMissingFactAfterCompletedVerification() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("journal.store"), root = directory.appendingPathComponent("exports")
        let store = GuestDataStore(storeURL: url, exportDirectory: root), fixture = LibraryFacadeFixture(store: store)
        defer { fixture.stop() }
        await fixture.start()
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), proof = taggedOutcomeProof(owner, count: 51, tag: "corrupt-export")
        try await collectExportFacts(proof, owner: owner, count: 51, store: store)
        let container = try ModelContainer(for: GuestDataStore.schema, configurations: [ModelConfiguration(schema: GuestDataStore.schema, url: url)])
        let context = ModelContext(container), key = try LibraryOutcomeBinding(owner: owner, committed: proof).ordinalKey(50)
        let row = try XCTUnwrap(context.fetch(FetchDescriptor<GuestOutcomeMember>(predicate: #Predicate { $0.ordinalKey == key })).first)
        context.delete(row); try context.save()
        let captured = try fixture.sync.captureWriteContext()
        do { _ = try await fixture.sync.preparePortableExport(server: .object([:]), context: captured, fileName: "export.json"); XCTFail("Corrupt journal exported as complete") }
        catch LibrarySyncFailure.storeUnavailable { }
        XCTAssertTrue(((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []).isEmpty)
    }

    @MainActor func testOutcomeExportArtifactCleanupAndAccountFenceNeverRecreateDeletedMetadata() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        let store = GuestDataStore(inMemory: true, exportDirectory: root)
        try store.claimGuestForSync(owner)
        let empty = try await store.prepareOutcomeExport(owner, isCurrent: { true })
        if case .present = empty.version { } else { XCTFail("Account state requires a clock") }
        let artifact = try store.beginOutcomeExportArtifact(empty)
        try Data("abandoned".utf8).write(to: artifact.directory.appendingPathComponent("document.partial"))
        try store.clearAbandonedOutcomeExports()
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.directory.path))
        try store.beginDeletion(subject: owner.subject, namespace: owner.namespace)
        try await store.markDeletionBackendComplete(subject: owner.subject, namespace: owner.namespace)
        do { _ = try await store.prepareOutcomeExport(owner, isCurrent: { true }); XCTFail("Deleted export recreated metadata") } catch LibrarySyncFailure.accountDeleting { }
    }


    @MainActor func testManifestRestoreUsesOwnedSnapshotWithoutGuessingMembers() throws {
        let first = "jn7fxd3z54153q9j13kmhgzkv18df2zd", second = "an7fxd3z54153q9j13kmhgzkv18df2zd"
        func item(_ id: String, folder: String?) -> SyncSavedItem {
            .init(hadithId: id, createdAt: 1, updatedAt: 1, bookmarkCreatedAt: 1, favoriteCreatedAt: nil, noteContent: nil, noteCreatedAt: nil,
                noteUpdatedAt: nil, folderId: folder, hadith: .init(_id: id, providerHadithId: "1", collectionSlug: "bukhari", collectionName: "Bukhari", volumeId: "1", arabicText: "نص", englishText: nil, referenceDisplay: "Bukhari 1"))
        }
        var state = LibraryPartitionState()
        state.savedSnapshot = .init(ownerKey: "owner-a", version: 1, folders: [], items: [item(first, folder: nil), item(second, folder: nil)])
        state.append(.account(nil), command: .folderRestore(.init(deletionId: "deleted", name: "Folder", hadithIds: [first, second])), at: 1_000)
        let frame = try XCTUnwrap(state.freeze()), operation = frame.batch.operations[0]
        let reply = SyncReply(ownerKey: "owner-a", batchId: frame.batch.id, receipts: [.init(id: operation.id, revision: operation.revision,
            outcome: .folderRestoredManifest(.init(manifestId: "manifest", generation: "generation", folderId: "destination", restored: 1, superseded: 0, missing: 1)))])
        let committed = SyncCommitted(clientKey: frame.clientKey, sequence: frame.sequence, digest: "fixture-digest", revision: .init(saved: 2, position: 0), reply: reply)
        try state.settle(.accepted(.init(committed: committed)), requested: frame, owner: observationOwner(state), observed: observation(state), now: 2_000)
        XCTAssertTrue(try legacyProjection(state).folders.isEmpty)
        XCTAssertTrue(try legacyProjection(state).items.allSatisfy { $0.folderId == nil })
        state.savedSnapshot = .init(ownerKey: "owner-a", version: 2, folders: [.init(_id: "destination", name: "Folder", createdAt: 1)], items: [item(first, folder: "destination"), item(second, folder: nil)])
        let visible = try legacyProjection(state)
        XCTAssertEqual(visible.folders.map(\.id), ["destination"])
        XCTAssertEqual(visible.items.first { $0.hadithId == first }?.folderId, "destination")
        XCTAssertNil(visible.items.first { $0.hadithId == second }?.folderId)
        XCTAssertNil(state.acknowledgement); XCTAssertNotNil(state.frozen)
    }


    @MainActor func testOutcomeJournalVerificationResumesAndRejectsMissingPersistedMember() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), proof = outcomeProof(owner, count: 100)
        let store = GuestDataStore(storeURL: url); try store.claimGuestForSync(owner)
        for _ in 0..<2 { _ = try await store.collectOutcomeStep(proof, owner: owner, isCurrent: { true }) { self.outcomePage($0, owner: owner, count: 100) } }
        let first = try await store.collectOutcomeStep(proof, owner: owner, isCurrent: { true }) { _ in XCTFail("Verification fetched"); throw LibrarySyncFailure.invalidReceipt }
        XCTAssertEqual(first.status, .verifying(.init(deleted: 50)))
        let schema = GuestDataStore.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)]), context = ModelContext(container)
        let key = try LibraryOutcomeBinding(owner: owner, committed: proof).ordinalKey(80)
        let query = FetchDescriptor<GuestOutcomeMember>(predicate: #Predicate { $0.ordinalKey == key })
        for row in try context.fetch(query) { context.delete(row) }
        try context.save()
        let reopened = GuestDataStore(storeURL: url)
        do {
            _ = try await reopened.collectOutcomeStep(proof, owner: owner, isCurrent: { true }) { _ in XCTFail("Verification fetched"); throw LibrarySyncFailure.invalidReceipt }
            XCTFail("Missing persisted fact became complete")
        } catch LibrarySyncFailure.storeUnavailable { }
        XCTAssertEqual(try reopened.outcomeEvidencePage(proof, owner: owner, start: 0).checkpoint.status, first.status)
        XCTAssertThrowsError(try reopened.outcomeEvidencePage(proof, owner: owner, start: 50))
        XCTAssertNil(try reopened.syncPartition(owner)?.acknowledgement)
    }


    private func outcomeProof(_ owner: LibrarySyncOwner, count: Int, restore: Bool = false) -> SyncCommitted {
        let outcome: SyncOutcome = restore
            ? .folderRestoredManifest(.init(manifestId: "manifest", generation: "generation", folderId: "restored-folder", restored: Double(max(0, count - 1)), superseded: 0, missing: Double(min(count, 1))))
            : .folderDeletedManifest(.init(manifestId: "manifest", generation: "generation", count: Double(count), deletedAt: 1_000))
        return .init(clientKey: "outcome-device", sequence: 1, digest: "outcome-digest", revision: .init(saved: 2, position: 0),
            reply: .init(ownerKey: owner.key, batchId: "outcome-batch", receipts: [.init(id: "outcome-operation", revision: "r1", outcome: outcome)]))
    }
    private func outcomePage(_ request: SyncOutcomePageRequest, owner: LibrarySyncOwner, count: Int, restore: Bool = false) -> SyncOutcomePage {
        let start = Int(request.start), end = min(start + LibrarySyncLimits.outcomePage, count)
        let rows = (start..<end).map { index in
            SyncOutcomeMember(ordinal: Double(index), memberId: "member-\(index)", hadithId: "hadith-\(index)", disposition: restore ? (index == count - 1 ? .missing : .restored) : .deleted)
        }
        return .page(.init(ownerKey: owner.key, request: request, rows: rows, next: Double(end), done: end == count))
    }
    @MainActor private func finishOutcomeVerification(_ proof: SyncCommitted, owner: LibrarySyncOwner, store: GuestDataStore) async throws -> LibraryOutcomeCheckpoint {
        for _ in 0..<30 {
            let checkpoint = try await store.collectOutcomeStep(proof, owner: owner, isCurrent: { true }) { _ in XCTFail("Verification fetched a server page"); throw LibrarySyncFailure.invalidReceipt }
            if checkpoint.status == .complete { return checkpoint }
        }
        throw LibrarySyncFailure.invalidReceipt
    }

    @MainActor func testOutcomeJournalCollectsBoundedPagesAcrossReopensWithoutChangingPartition() async throws {
        for count in [0, 1, 50, 51, 501] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
            let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), proof = outcomeProof(owner, count: count)
            var store = GuestDataStore(storeURL: url)
            try store.claimGuestForSync(owner)
            try store.enqueueSyncChange(.init(command: .folderDelete(.init(folder: .server(.init(id: "folder")))), at: 1_000, source: .account(nil)), owner: owner)
            _ = try store.freezeSyncFrame(owner)
            let original = try XCTUnwrap(store.syncPartition(owner))
            var checkpoint = LibraryOutcomeCheckpoint(), requests: [Double] = []
            for _ in 0..<30 {
                checkpoint = try await store.collectOutcomeStep(proof, owner: owner, isCurrent: { true }) { request in
                    requests.append(request.start)
                    return self.outcomePage(request, owner: owner, count: count)
                }
                XCTAssertEqual(try store.syncPartition(owner), original)
                store = GuestDataStore(storeURL: url)
                if checkpoint.status == .complete { break }
            }
            XCTAssertEqual(checkpoint.status, .complete); XCTAssertEqual(checkpoint.next, count)
            XCTAssertEqual(requests, stride(from: 0, to: max(1, count), by: 50).map(Double.init))
            var start = 0, members = Set<String>()
            repeat {
                let evidence = try store.outcomeEvidencePage(proof, owner: owner, start: start)
                XCTAssertEqual(evidence.checkpoint, checkpoint); XCTAssertLessThanOrEqual(evidence.rows.count, 50)
                members.formUnion(evidence.rows.map(\.memberId)); start = evidence.next
                if evidence.endOfCollectedPrefix { break }
            } while start <= count
            XCTAssertEqual(members.count, count)
            _ = try await store.collectOutcomeStep(proof, owner: owner, isCurrent: { true }) { _ in XCTFail("Fetched complete journal"); throw LibrarySyncFailure.invalidReceipt }
            XCTAssertEqual(try store.syncPartition(owner), original)
        }
    }

    @MainActor func testOutcomeJournalDuplicateAndConflictingReopenedContextCannotUpsertEvidence() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), proof = outcomeProof(owner, count: 100)
        let store = GuestDataStore(storeURL: url); try store.claimGuestForSync(owner)
        let first = try await store.collectOutcomeStep(proof, owner: owner, isCurrent: { true }) { request in
            let reopened = GuestDataStore(storeURL: url)
            _ = try await reopened.collectOutcomeStep(proof, owner: owner, isCurrent: { true }) { self.outcomePage($0, owner: owner, count: 100) }
            return self.outcomePage(request, owner: owner, count: 100)
        }
        XCTAssertEqual(first.next, 50)
        do {
            _ = try await store.collectOutcomeStep(proof, owner: owner, isCurrent: { true }) { request in
                let reopened = GuestDataStore(storeURL: url)
                _ = try await reopened.collectOutcomeStep(proof, owner: owner, isCurrent: { true }) { self.outcomePage($0, owner: owner, count: 100) }
                guard case .page(let page) = self.outcomePage(request, owner: owner, count: 100) else { throw LibrarySyncFailure.invalidReceipt }
                var rows = page.rows
                rows[0] = .init(ordinal: rows[0].ordinal, memberId: "conflicting-member", hadithId: "conflicting-hadith", disposition: .deleted)
                return .page(.init(ownerKey: page.ownerKey, request: request, rows: rows, next: page.next, done: page.done))
            }
            XCTFail("Conflicting duplicate replaced saved evidence")
        } catch LibrarySyncFailure.invalidReceipt { }
        _ = try await finishOutcomeVerification(proof, owner: owner, store: GuestDataStore(storeURL: url))
        let evidence = try GuestDataStore(storeURL: url).outcomeEvidencePage(proof, owner: owner, start: 50)
        XCTAssertEqual(evidence.checkpoint.status, .complete)
        XCTAssertEqual(evidence.rows.first?.memberId, "member-50"); XCTAssertEqual(evidence.rows.first?.hadithId, "hadith-50")
    }

    @MainActor func testOutcomeJournalRollsBackEarlierRowsWhenLaterMemberConflicts() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), proof = outcomeProof(owner, count: 100)
        let store = GuestDataStore(storeURL: url); try store.claimGuestForSync(owner)
        _ = try await store.collectOutcomeStep(proof, owner: owner, isCurrent: { true }) { self.outcomePage($0, owner: owner, count: 100) }
        do {
            _ = try await store.collectOutcomeStep(proof, owner: owner, isCurrent: { true }) { request in
                guard case .page(let page) = self.outcomePage(request, owner: owner, count: 100) else { throw LibrarySyncFailure.invalidReceipt }
                var rows = page.rows
                rows[10] = .init(ordinal: rows[10].ordinal, memberId: "member-0", hadithId: rows[10].hadithId, disposition: .deleted)
                return .page(.init(ownerKey: owner.key, request: request, rows: rows, next: page.next, done: true))
            }
            XCTFail("Repeated member identity accepted")
        } catch LibrarySyncFailure.invalidReceipt { }
        let reopened = GuestDataStore(storeURL: url), partial = try reopened.outcomeEvidencePage(proof, owner: owner, start: 50)
        XCTAssertEqual(partial.checkpoint.next, 50); XCTAssertTrue(partial.rows.isEmpty)
        _ = try await reopened.collectOutcomeStep(proof, owner: owner, isCurrent: { true }) { self.outcomePage($0, owner: owner, count: 100) }
        let complete = try await finishOutcomeVerification(proof, owner: owner, store: reopened)
        XCTAssertEqual(complete.status, .complete)
    }

    @MainActor func testOutcomeJournalUnavailableRetainsPartialFactsAndNeverAcknowledges() async throws {
        for reason in [SyncOutcomePageUnavailableReason.detailUnavailable, .proofUnavailable] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
            let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), proof = outcomeProof(owner, count: 51)
            let store = GuestDataStore(storeURL: url); try store.claimGuestForSync(owner)
            _ = try await store.collectOutcomeStep(proof, owner: owner, isCurrent: { true }) { self.outcomePage($0, owner: owner, count: 51) }
            let result = try await store.collectOutcomeStep(proof, owner: owner, isCurrent: { true }) { .unavailable(.init(ownerKey: owner.key, request: $0, reason: reason)) }
            XCTAssertEqual(result.status, .unavailable(reason)); XCTAssertEqual(result.next, 50)
            let reopened = GuestDataStore(storeURL: url), evidence = try reopened.outcomeEvidencePage(proof, owner: owner, start: 0)
            XCTAssertEqual(evidence.rows.count, 50); XCTAssertEqual(evidence.checkpoint.status, .unavailable(reason))
            XCTAssertNil(try reopened.syncPartition(owner)?.acknowledgement)
        }
    }

    @MainActor func testOutcomeJournalRejectsWrongCategoriesAndOwnerWithoutAdvancing() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), proof = outcomeProof(owner, count: 51, restore: true)
        let store = GuestDataStore(storeURL: url); try store.claimGuestForSync(owner)
        _ = try await store.collectOutcomeStep(proof, owner: owner, isCurrent: { true }) { self.outcomePage($0, owner: owner, count: 51, restore: true) }
        for wrongOwner in [false, true] {
            do {
                _ = try await store.collectOutcomeStep(proof, owner: owner, isCurrent: { true }) { request in
                    let row = SyncOutcomeMember(ordinal: request.start, memberId: "member-50", hadithId: "hadith-50", disposition: .restored)
                    return .page(.init(ownerKey: wrongOwner ? "other-owner" : owner.key, request: request, rows: [row], next: 51, done: true))
                }
                XCTFail("Invalid page accepted")
            } catch LibrarySyncFailure.invalidReceipt { }
            XCTAssertEqual(try GuestDataStore(storeURL: url).outcomeEvidencePage(proof, owner: owner, start: 50).checkpoint.next, 50)
        }
        let terminal = try await store.collectOutcomeStep(proof, owner: owner, isCurrent: { true }) { self.outcomePage($0, owner: owner, count: 51, restore: true) }
        XCTAssertEqual(terminal.counts, .init(restored: 50, missing: 1))
    }

    @MainActor func testOutcomeJournalErasureFenceRejectsLatePageAfterPartitionRecreation() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), proof = outcomeProof(owner, count: 1)
        let store = GuestDataStore(storeURL: url); try store.claimGuestForSync(owner)
        do {
            _ = try await store.collectOutcomeStep(proof, owner: owner, isCurrent: { true }) { request in
                try store.resetSyncPartitionForTesting(owner); try store.claimGuestForSync(owner)
                return self.outcomePage(request, owner: owner, count: 1)
            }
            XCTFail("Late page recreated erased evidence")
        } catch LibrarySyncFailure.sessionChanged { }
        XCTAssertThrowsError(try GuestDataStore(storeURL: url).outcomeEvidencePage(proof, owner: owner, start: 0))
        _ = try await store.collectOutcomeStep(proof, owner: owner, isCurrent: { true }) { self.outcomePage($0, owner: owner, count: 1) }
        let fresh = try await finishOutcomeVerification(proof, owner: owner, store: store)
        XCTAssertEqual(fresh.status, .complete)
    }

    @MainActor func testOutcomeJournalAccountErasureFindsOrphansAndPreservesOtherScopes() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), other = LibrarySyncOwner(key: "owner-b", subject: "subject-b")
        let deployment = LibrarySyncOwner(key: "owner-a", subject: "subject-a", namespace: "other-deployment")
        let store = GuestDataStore(storeURL: url)
        for target in [owner, other, deployment] {
            try store.claimGuestForSync(target)
            let count = target == owner ? 501 : 1
            for _ in 0..<12 {
                let checkpoint = try await store.collectOutcomeStep(outcomeProof(target, count: count), owner: target, isCurrent: { true }) { self.outcomePage($0, owner: target, count: count) }
                if checkpoint.status != .collecting { break }
            }
        }
        let schema = GuestDataStore.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)]), context = ModelContext(container)
        for row in try context.fetch(FetchDescriptor<GuestLibraryPartition>()) where row.ownerKey == owner.storageKey { context.delete(row) }
        try context.save()
        XCTAssertEqual(try store.outcomeEvidencePage(outcomeProof(owner, count: 501), owner: owner, start: 0).rows.count, 50)
        try store.beginDeletion(subject: owner.subject, namespace: owner.namespace)
        try await store.markDeletionBackendComplete(subject: owner.subject, namespace: owner.namespace)
        let reopened = GuestDataStore(storeURL: url)
        XCTAssertThrowsError(try reopened.outcomeEvidencePage(outcomeProof(owner, count: 501), owner: owner, start: 0))
        do {
            _ = try await reopened.collectOutcomeStep(outcomeProof(owner, count: 501), owner: owner, isCurrent: { true }) { _ in XCTFail("Erased owner fetched"); throw LibrarySyncFailure.invalidReceipt }
            XCTFail("Stale erased owner recreated metadata")
        } catch LibrarySyncFailure.accountDeleting { }
        let check = ModelContext(container), subject = owner.subject, namespace = owner.namespace
        XCTAssertEqual(try check.fetchCount(FetchDescriptor<GuestOutcomeScope>(predicate: #Predicate { $0.subject == subject && $0.namespace == namespace })), 0)
        XCTAssertEqual(try check.fetchCount(FetchDescriptor<GuestOutcomeHeader>(predicate: #Predicate { $0.subject == subject && $0.namespace == namespace })), 0)
        XCTAssertEqual(try check.fetchCount(FetchDescriptor<GuestOutcomeMember>(predicate: #Predicate { $0.subject == subject && $0.namespace == namespace })), 0)
        for target in [other, deployment] {
            XCTAssertEqual(try reopened.outcomeEvidencePage(outcomeProof(target, count: 1), owner: target, start: 0).rows.count, 1)
        }
    }


    func testReconciledManifestStagesCollectionWithoutAcknowledging() throws {
        let outcomes: [SyncOutcome] = [
            .folderDeletedManifest(.init(manifestId: "manifest", generation: "generation", count: 501, deletedAt: 1_000)),
            .folderRestoredManifest(.init(manifestId: "manifest", generation: "generation", folderId: "folder", restored: 499, superseded: 1, missing: 1)),
        ]
        for outcome in outcomes {
            var original = LibraryPartitionState()
            original.append(.account(nil), command: .folderDelete(.init(folder: .server(.init(id: "folder-a")))), at: 1_000)
            let frame = try XCTUnwrap(original.freeze()), operation = frame.batch.operations[0]
            let committed = SyncCommitted(clientKey: frame.clientKey, sequence: frame.sequence, digest: "fixture-digest", revision: .init(saved: 1, position: 0),
                reply: .init(ownerKey: "owner-a", batchId: frame.batch.id, receipts: [.init(id: operation.id, revision: operation.revision, outcome: outcome)]))
            let cursor = SyncCursor(closedThrough: 0, outstanding: .committed(.init(committed: committed)))
            var reconciled = original
            try reconciled.settle(.reconcile(.init(ownerKey: "owner-a", clientKey: frame.clientKey, requestedSequence: frame.sequence, requestedBatchId: frame.batch.id, cursor: cursor)), requested: frame, owner: observationOwner(reconciled), observed: observation(reconciled), now: 2_000)
            XCTAssertEqual(reconciled.collectingOutcome, .init(committed: committed, origin: .historical))
            XCTAssertEqual(reconciled.recovery, original.frozen!.changes.map(LibraryRecovery.historical)); XCTAssertNil(reconciled.acknowledgement)
            XCTAssertThrowsError(try reconciled.freeze())
            var retired = original
            try retired.settleRetirement(.init(ownerKey: "owner-a", clientKey: frame.clientKey, cursor: cursor), requested: frame)
            XCTAssertEqual(retired, reconciled)

            let different = SyncBatch(id: frame.batch.id, operations: [.init(id: operation.id, revision: operation.revision, at: operation.at,
                command: .folderDelete(.init(folder: .server(.init(id: "folder-b")))))])
            let pending = SyncPending(clientKey: frame.clientKey, sequence: frame.sequence, batchId: frame.batch.id, digest: committed.digest,
                intentDigest: try different.intentDigest(), manifestId: "manifest", generation: "generation", retryAfterMs: 1_000)
            var polled = original
            try polled.settle(.pending(.init(ownerKey: "owner-a", pending: pending)), requested: frame, owner: observationOwner(polled), observed: observation(polled), now: 2_000)
            let previousRecovery = polled.recovery
            try polled.settlePending(.accepted(.init(committed: committed)), requested: pending, owner: observationOwner(polled), observed: observation(polled), now: 2_000)
            XCTAssertEqual(polled.recovery, previousRecovery); XCTAssertEqual(polled.recovery.count, 1)
            XCTAssertEqual(polled.collectingOutcome?.origin, .historical); XCTAssertNil(polled.acknowledgement)

            var acknowledged = original
            try acknowledged.settle(accepted(frame, reply: .init(ownerKey: "owner-a", batchId: frame.batch.id,
                receipts: [.init(id: operation.id, revision: operation.revision, outcome: .preserved)])), requested: frame, owner: observationOwner(acknowledged), observed: observation(acknowledged), now: 2_000)
            let ack = try XCTUnwrap(acknowledged.acknowledgement), beforeAck = acknowledged
            let next = SyncCommitted(clientKey: frame.clientKey, sequence: 2, digest: "next-digest", revision: committed.revision,
                reply: .init(ownerKey: "owner-a", batchId: "next-batch", receipts: committed.reply.receipts))
            try acknowledged.settleAcknowledgement(.init(ownerKey: "owner-a", clientKey: frame.clientKey,
                cursor: .init(closedThrough: 1, outstanding: .committed(.init(committed: next)))), requested: ack)
            XCTAssertEqual(acknowledged.collectingOutcome, .init(committed: next, origin: .historical)); XCTAssertNil(acknowledged.acknowledgement)
            XCTAssertEqual(acknowledged.confirmed, beforeAck.confirmed)
        }
    }

    func testManifestReceiptStagesOriginalUntilOutcomeCollection() throws {
        var state = LibraryPartitionState()
        state.append(.account(nil), command: .folderDelete(.init(folder: .server(.init(id: "folder")))), at: 1_000)
        let frame = try XCTUnwrap(state.freeze()), operation = frame.batch.operations[0]
        let reply = SyncReply(ownerKey: "owner-a", batchId: frame.batch.id, receipts: [.init(id: operation.id, revision: operation.revision,
            outcome: .folderDeletedManifest(.init(manifestId: "manifest", generation: "generation", count: 501, deletedAt: 1_000)))])
        try state.settle(accepted(frame, reply: reply), requested: frame, owner: observationOwner(state), observed: observation(state), now: 2_000)
        XCTAssertEqual(state.frozen?.batch, frame.batch); XCTAssertEqual(state.nextSequence, 1); XCTAssertNil(state.acknowledgement)
        XCTAssertEqual(state.collectingOutcome?.origin, .matched(intentDigest: try frame.batch.intentDigest()))
        XCTAssertThrowsError(try state.freeze())
        XCTAssertEqual(try JSONDecoder().decode(LibraryPartitionState.self, from: JSONEncoder().encode(state)), state)
    }

    private func mixedFolderFixture() -> (LibraryPartitionState, [LibraryLocalChange], LibraryLocalChange) {
        let before = LibraryLocalChange(command: .notePut(.init(hadithId: "before", content: "Unsent original A", createdAt: 1_000, updatedAt: 1_000)), at: 1_000, source: .note(.init(hadithId: "before", content: "Unsent original A", createdAt: date(1), updatedAt: date(1))))
        let folder = LibraryLocalChange(command: .folderDelete(.init(folder: .server(.init(id: "folder")))), at: 1_000, source: .account(nil))
        let after = LibraryLocalChange(command: .notePut(.init(hadithId: "after", content: "Unsent original B", createdAt: 1_000, updatedAt: 1_000)), at: 1_000, source: .account(nil))
        let later = LibraryLocalChange(command: .bookmarkAdd(.init(hadithId: "later", createdAt: 2_000)), at: 2_000, source: .account(nil))
        let original = [before, folder, after]
        var state = LibraryPartitionState(); state.frozen = .init(batch: .init(id: "old-mixed", operations: original.map(\.operation)), changes: original); state.pending = [later]
        return (state, original, later)
    }
    @MainActor func testMixedSplitPersistsExactOriginalsAcrossFailedAckAndReopenBeforeIsolatedSends() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store"), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), session = LibrarySyncSession(id: "session-a", subject: "subject-a")
        let (state, original, later) = mixedFolderFixture(); try seedPartitionFixture(state, owner: owner, url: url)
        var failAck = true, frames: [SyncFrame] = []
        let transport = LibrarySyncTransport(namespace: owner.namespace, open: { .init(ownerKey: owner.key, subject: owner.subject, capability: "fixture", validUntil: Date.now.millisecondsSinceEpoch + 60_000) }, acknowledge: { _, value in
            if value.sequence == 1 && failAck { throw LibrarySyncFailure.storeUnavailable }
            return self.acknowledged(value)
        }, send: { _, frame in
            frames.append(frame)
            let receipts = frame.batch.operations.map { operation -> SyncReceipt in
                let outcome: SyncOutcome
                if frame.batch.id == "old-mixed" { outcome = .batchRequiresSplit }
                else if case .folderDelete = operation.command { outcome = .unresolved(.init(reason: .missingFolder)) }
                else { outcome = .preserved }
                return .init(id: operation.id, revision: operation.revision, outcome: outcome)
            }
            return self.accepted(frame, reply: .init(ownerKey: owner.key, batchId: frame.batch.id, receipts: receipts))
        })
        let store = GuestDataStore(storeURL: url), sync = LibrarySync(store: store, transport: transport, currentSession: { session })
        await sync.activate(session); sync.deactivate()
        let saved = try XCTUnwrap(store.syncPartition(owner))
        XCTAssertNil(saved.frozen); XCTAssertEqual(saved.pending, original + [later]); XCTAssertEqual(saved.nextSequence, 2)
        XCTAssertEqual(saved.acknowledgement?.sequence, 1); XCTAssertTrue(saved.recovery.isEmpty)
        XCTAssertThrowsError(try store.freezeSyncFrame(owner))
        failAck = false
        let reopened = GuestDataStore(storeURL: url), resumed = LibrarySync(store: reopened, transport: transport, currentSession: { session })
        defer { resumed.deactivate() }; await resumed.activate(session)
        try await waitForLibrary { if case .ready = resumed.status { return true }; return false }
        XCTAssertEqual(frames.dropFirst().flatMap { $0.batch.operations }, (original + [later]).map(\.operation))
        XCTAssertEqual(frames.filter { $0.batch.id == "old-mixed" }.count, 1)
        XCTAssertEqual(frames.dropFirst().filter { $0.batch.operations.contains { if case .folderDelete = $0.command { return true }; return false } }.map { $0.batch.operations.count }, [1])
        XCTAssertNil(try reopened.syncPartition(owner)?.acknowledgement)
        XCTAssertEqual(try reopened.syncPartition(owner)?.recovery.count, 1)
    }
    func testMixedSplitExactPollingRequeuesButHistoricalAndPartialRepliesDoNot() throws {
        let (base, original, later) = mixedFolderFixture(), frame = SyncFrame(clientKey: base.clientKey, sequence: 1, batch: try XCTUnwrap(base.frozen).batch)
        let receipts = frame.batch.operations.map { SyncReceipt(id: $0.id, revision: $0.revision, outcome: .batchRequiresSplit) }
        let proof = SyncCommitted(clientKey: frame.clientKey, sequence: 1, digest: "mixed-proof", revision: .init(saved: 0, position: 0), reply: .init(ownerKey: "owner-a", batchId: frame.batch.id, receipts: receipts))
        var waiting = base
        let pending = SyncPending(clientKey: frame.clientKey, sequence: 1, batchId: frame.batch.id, digest: proof.digest, intentDigest: try frame.batch.intentDigest(), manifestId: "pending", generation: "generation", retryAfterMs: 250)
        try waiting.settle(.pending(.init(ownerKey: "owner-a", pending: pending)), requested: frame, owner: observationOwner(waiting), observed: observation(waiting), now: 2_000)
        try waiting.settlePending(.accepted(.init(committed: proof)), requested: pending, owner: observationOwner(waiting), observed: observation(waiting), now: 2_000)
        XCTAssertEqual(waiting.pending, original + [later]); XCTAssertNotNil(waiting.acknowledgement)
        var unknown = base
        try unknown.settle(.reconcile(.init(ownerKey: "owner-a", clientKey: frame.clientKey, requestedSequence: 1, requestedBatchId: frame.batch.id, cursor: .init(closedThrough: 0, outstanding: .committed(.init(committed: proof))))), requested: frame, owner: observationOwner(unknown), observed: observation(unknown), now: 2_000)
        XCTAssertEqual(unknown.pending, [later]); XCTAssertEqual(unknown.recovery, original.map(LibraryRecovery.historical))
        for malformed in [Array(receipts.dropLast()), [receipts[0], receipts[0], receipts[2]], [receipts[0], .init(id: receipts[1].id, revision: receipts[1].revision, outcome: .preserved), receipts[2]]] {
            var state = base
            let bad = SyncCommitted(clientKey: proof.clientKey, sequence: proof.sequence, digest: proof.digest, revision: proof.revision, reply: .init(ownerKey: "owner-a", batchId: frame.batch.id, receipts: malformed))
            XCTAssertThrowsError(try state.settle(.accepted(.init(committed: bad)), requested: frame, owner: observationOwner(state), observed: observation(state), now: 2_000)); XCTAssertEqual(state, base)
        }
    }
    @MainActor func testCompactFolderUndoCannotOverrideNewerMovesRemovalOrLaterDeletion() throws {
        var state = LibraryPartitionState()
        state.savedSnapshot = .init(ownerKey: "owner-a", version: 1, folders: [.init(_id: "folder", name: "Original", createdAt: 1_000), .init(_id: "other", name: "Other", createdAt: 1_000)], items: (0..<3).map { index in
            .init(hadithId: "item-\(index)", createdAt: 1_000, updatedAt: 1_000, bookmarkCreatedAt: 1_000, favoriteCreatedAt: nil, noteContent: nil, noteCreatedAt: nil, noteUpdatedAt: nil, folderId: "folder", hadith: .init(_id: "item-\(index)", providerHadithId: String(index), collectionSlug: "bukhari", collectionName: "Bukhari", volumeId: "1", arabicText: "نص", englishText: nil, referenceDisplay: "Fixture"))
        })
        let deletion = LibraryLocalChange(command: .folderDelete(.init(folder: .server(.init(id: "folder")))), at: 2_000, source: .account(nil)); state.pending = [deletion]
        state.append(.account(nil), command: .membershipPut(.init(hadithId: "item-0", folder: .none, mode: nil)), at: 3_000)
        state.append(.account(nil), command: .bookmarkRemove(.init(hadithId: "item-1")), at: 3_000)
        state.append(.account(nil), command: .bookmarkAdd(.init(hadithId: "item-1", createdAt: 4_000)), at: 4_000)
        state.append(.account(nil), command: .folderRestore(.init(deletionId: deletion.operation.id, name: "Original", hadithIds: [])), at: 5_000)
        let restored = try legacyProjection(state)
        XCTAssertNil(restored.items.first { $0.hadithId == "item-0" }?.folderId); XCTAssertNil(restored.items.first { $0.hadithId == "item-1" }?.folderId)
        XCTAssertNotNil(restored.items.first { $0.hadithId == "item-2" }?.folderId)
        state.append(.account(nil), command: .folderDelete(.init(folder: .local(.init(key: "restore:" + deletion.operation.id)))), at: 6_000)
        state.append(.account(nil), command: .folderRestore(.init(deletionId: deletion.operation.id, name: "Original", hadithIds: [])), at: 7_000)
        XCTAssertTrue(try legacyProjection(state).items.allSatisfy { $0.folderId == nil })
        var advanced = state; advanced.pending = [try XCTUnwrap(state.pending.first { if case .folderRestore = $0.operation.command { return true }; return false })]
        if let snapshot = advanced.savedSnapshot { advanced.savedSnapshot = .init(ownerKey: snapshot.ownerKey, version: 2, folders: [], items: snapshot.items.map { .init(hadithId: $0.hadithId, createdAt: $0.createdAt, updatedAt: $0.updatedAt, bookmarkCreatedAt: $0.bookmarkCreatedAt, favoriteCreatedAt: $0.favoriteCreatedAt, noteContent: $0.noteContent, noteCreatedAt: $0.noteCreatedAt, noteUpdatedAt: $0.noteUpdatedAt, folderId: nil, hadith: $0.hadith) }) }
        XCTAssertTrue(try legacyProjection(advanced).items.allSatisfy { $0.folderId == nil })
    }

    @MainActor func testAccountFolderUndoIsCompactAndRestores501OfflineMembers() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        let store = GuestDataStore(storeURL: url), fixture = LibraryFacadeFixture(store: store)
        defer { fixture.stop() }; await fixture.start()
        let rows: [SyncSavedItem] = (0..<501).map { index in
            let id = "item-\(index)"
            return .init(hadithId: id, createdAt: 1_000, updatedAt: 1_000, bookmarkCreatedAt: 1_000, favoriteCreatedAt: nil, noteContent: nil, noteCreatedAt: nil, noteUpdatedAt: nil, folderId: "folder",
                hadith: .init(_id: id, providerHadithId: String(index + 1), collectionSlug: "bukhari", collectionName: "Bukhari", volumeId: "1", arabicText: "نص", englishText: nil, referenceDisplay: "Bukhari \(index + 1)"))
        }
        fixture.saved.send(.init(ownerKey: "owner-a", version: 1, folders: [.init(_id: "folder", name: "Original folder", createdAt: 1_000)], items: rows))
        try await waitForLibrary { fixture.model.savedItems.count == 501 }
        let folder = try XCTUnwrap(fixture.model.folders.first), scope = fixture.model.actionScope
        fixture.model.deleteFolder(folder, scope: scope)
        XCTAssertTrue(fixture.model.folders.isEmpty)
        fixture.model.undoDeleteFolder()
        let owner = try XCTUnwrap(fixture.sync.owner), state = try XCTUnwrap(store.syncPartition(owner))
        let commands = (state.frozen?.changes ?? []) + state.pending
        guard let undo = commands.first(where: { if case .folderRestore = $0.operation.command { return true }; return false }), case .folderRestore(let value) = undo.operation.command else { return XCTFail("Undo was not durably queued") }
        XCTAssertTrue(value.hadithIds.isEmpty)
        XCTAssertEqual(fixture.model.savedItems.filter { $0.folderId != nil }.count, 501)
        XCTAssertEqual(fixture.model.folders.first?.name, "Original folder")
        XCTAssertLessThan(try JSONEncoder().encode(undo.operation).count, 1_024)
        fixture.stop()
        let reopened = LibraryFacadeFixture(store: GuestDataStore(storeURL: url)); defer { reopened.stop() }; await reopened.start()
        XCTAssertEqual(reopened.model.savedItems.filter { $0.folderId != nil }.count, 501)
        XCTAssertEqual(reopened.model.folders.first?.name, "Original folder")
        XCTAssertNil(reopened.model.lastFolderDeletion)
    }

    @MainActor private func acknowledgedRetentionFixture(count: Int, url: URL, acknowledge: Bool = true, acknowledgedAt: Double = 2_000) async throws -> (GuestDataStore, SyncCommitted, SyncAcknowledgement) {
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        var state = LibraryPartitionState()
        state.append(.account(nil), command: .folderDelete(.init(folder: .server(.init(id: "folder")))), at: 1_000)
        let original = try XCTUnwrap(state.freeze()), operation = original.batch.operations[0]
        var encoded = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        for (from, to) in [(state.clientKey, "retention-device"), (original.batch.id, "retention-batch"), (operation.id, "retention-operation"), (operation.revision, "retention-revision")] { encoded = encoded.replacingOccurrences(of: from, with: to) }
        state = try JSONDecoder().decode(LibraryPartitionState.self, from: Data(encoded.utf8))
        try seedPartitionFixture(state, owner: owner, url: url)
        let store = GuestDataStore(storeURL: url), frame = try XCTUnwrap(store.freezeSyncFrame(owner)), sent = frame.batch.operations[0]
        let proof = SyncCommitted(clientKey: frame.clientKey, sequence: frame.sequence, digest: "retention-proof", revision: .init(saved: 2, position: 0), reply: .init(ownerKey: owner.key, batchId: frame.batch.id,
            receipts: [.init(id: sent.id, revision: sent.revision, outcome: .folderDeletedManifest(.init(manifestId: "manifest", generation: "generation", count: Double(count), deletedAt: 1_000)))]))
        try store.settleSyncExchange(.accepted(.init(committed: proof)), requested: frame, owner: owner)
        try await collectExportFacts(proof, owner: owner, count: count, store: store)
        try store.cacheSavedSnapshot(.init(ownerKey: owner.key, version: 2, folders: [], items: []), owner: owner)
        let pending = try XCTUnwrap(store.syncPartition(owner)?.collectingOutcome)
        XCTAssertEqual(try store.settleCollectedOutcome(pending, owner: owner, now: acknowledgedAt), .settled)
        let ack = try XCTUnwrap(store.syncPartition(owner)?.acknowledgement)
        if acknowledge { try store.settleSyncAcknowledgement(acknowledged(ack), requested: ack, owner: owner, now: acknowledgedAt) }
        return (store, proof, ack)
    }

    @MainActor func testOutcomeAckMarkerReplaysOldPartitionWithoutRenewalAndAcceptsLaterCursor() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        let (store, proof, ack) = try await acknowledgedRetentionFixture(count: 1, url: url, acknowledge: false)
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), before = try XCTUnwrap(store.syncPartition(owner))
        XCTAssertNotNil(before.manifestAckLink)
        let wrong = SyncAcknowledgement(clientKey: ack.clientKey, sequence: ack.sequence, batchId: ack.batchId, digest: "wrong")
        XCTAssertThrowsError(try store.settleSyncAcknowledgement(acknowledged(wrong), requested: wrong, owner: owner, now: 2_000))
        XCTAssertNil(try store.outcomeEvidencePage(proof, owner: owner, start: 0).checkpoint.retention)
        let fence = try await store.prepareOutcomeExport(owner, isCurrent: { true })
        try store.settleSyncAcknowledgement(acknowledged(ack), requested: ack, owner: owner, now: 2_000)
        XCTAssertThrowsError(try store.validateOutcomeExport(fence))
        XCTAssertEqual(try store.outcomeEvidencePage(proof, owner: owner, start: 0).checkpoint.retention?.acknowledgedAt, 2_000)
        // Reconstruct the durable crash seam after journal commit, before partition save.
        let container = try ModelContainer(for: GuestDataStore.schema, configurations: [ModelConfiguration(schema: GuestDataStore.schema, url: url)]), context = ModelContext(container)
        let storageKey = owner.storageKey
        let row = try XCTUnwrap(context.fetch(FetchDescriptor<GuestLibraryPartition>(predicate: #Predicate { $0.ownerKey == storageKey })).first)
        row.stateData = try JSONEncoder().encode(before); try context.save()
        let reopened = GuestDataStore(storeURL: url)
        let pending = SyncPending(clientKey: ack.clientKey, sequence: 4, batchId: "next-batch", digest: "next-proof", intentDigest: String(repeating: "a", count: 64), manifestId: "next-manifest", generation: "next-generation", retryAfterMs: 250)
        try reopened.settleSyncAcknowledgement(.init(ownerKey: owner.key, clientKey: ack.clientKey, cursor: .init(closedThrough: 3, outstanding: .pending(.init(pending: pending)))), requested: ack, owner: owner, now: 9_000)
        XCTAssertEqual(try reopened.syncPartition(owner)?.nextSequence, 4)
        XCTAssertEqual(try reopened.syncPartition(owner)?.waiting, pending)
        XCTAssertNil(try reopened.syncPartition(owner)?.manifestAckLink)
        XCTAssertEqual(try reopened.outcomeEvidencePage(proof, owner: owner, start: 0).checkpoint.retention?.acknowledgedAt, 2_000)
        XCTAssertThrowsError(try reopened.settleSyncAcknowledgement(acknowledged(ack), requested: ack, owner: owner, now: 12_000))
        XCTAssertEqual(try reopened.outcomeEvidencePage(proof, owner: owner, start: 0).checkpoint.retention?.acknowledgedAt, 2_000)
    }

    @MainActor func testOutcomeRetentionPreservesPartitionlessEvidenceUntilScopedErasure() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        let (_, proof, _) = try await acknowledgedRetentionFixture(count: 1, url: url)
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), replacement = LibrarySyncOwner(key: "replacement", subject: "subject-a")
        let container = try ModelContainer(for: GuestDataStore.schema, configurations: [ModelConfiguration(schema: GuestDataStore.schema, url: url)]), context = ModelContext(container)
        let key = owner.storageKey
        for row in try context.fetch(FetchDescriptor<GuestLibraryPartition>(predicate: #Predicate { $0.ownerKey == key })) { context.delete(row) }; try context.save()
        let store = GuestDataStore(storeURL: url); try store.claimGuestForSync(replacement)
        try store.cacheSavedSnapshot(.init(ownerKey: replacement.key, version: 2, folders: [], items: []), owner: replacement)
        for _ in 0..<10 { if try !store.pruneOutcomeSuccessStep(replacement, now: 2_000 + LibraryOutcomeRetention.duration) { break } }
        XCTAssertEqual(try store.outcomeEvidencePage(proof, owner: owner, start: 0).rows.count, 1)
        XCTAssertNil(try store.syncPartition(owner))
        try store.beginDeletion(subject: replacement.subject, namespace: replacement.namespace)
        try await store.markDeletionBackendComplete(subject: replacement.subject, namespace: replacement.namespace)
        XCTAssertThrowsError(try store.outcomeEvidencePage(proof, owner: owner, start: 0))
        XCTAssertThrowsError(try store.pruneOutcomeSuccessStep(replacement, now: 2_000 + LibraryOutcomeRetention.duration))
        XCTAssertNil(try store.syncPartition(replacement))
    }

    @MainActor func testOutcomeRetentionResumesBoundedPruneRejectsPartialExportAndAdmitsLateRestore() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store"), acknowledgedAt = Date.now.millisecondsSinceEpoch
        let (store, proof, _) = try await acknowledgedRetentionFixture(count: 501, url: url, acknowledgedAt: acknowledgedAt)
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        let oldFence = try await store.prepareOutcomeExport(owner, isCurrent: { true })
        let fixture = LibraryFacadeFixture(store: store); await fixture.start()
        let captured = try fixture.sync.captureWriteContext()
        XCTAssertTrue(try store.pruneOutcomeSuccessStep(owner, now: acknowledgedAt + LibraryOutcomeRetention.duration - 1))
        _ = try store.pruneOutcomeSuccessStep(owner, now: acknowledgedAt + LibraryOutcomeRetention.duration - 1)
        XCTAssertEqual(try store.outcomeEvidencePage(proof, owner: owner, start: 500).rows.count, 1)
        XCTAssertTrue(try store.pruneOutcomeSuccessStep(owner, now: acknowledgedAt + LibraryOutcomeRetention.duration))
        XCTAssertThrowsError(try store.validateOutcomeExport(oldFence))
        XCTAssertThrowsError(try store.outcomeEvidencePage(proof, owner: owner, start: 0))
        let current = try await store.prepareOutcomeExport(owner, isCurrent: { true })
        XCTAssertEqual(try store.outcomeExportEntries(current, after: nil).first?.checkpoint.retention?.removed, 50)
        do { _ = try await fixture.sync.preparePortableExport(server: .object([:]), context: captured, fileName: "export.json"); XCTFail("Half-pruned journal exported as complete") } catch LibrarySyncFailure.storeUnavailable { }
        fixture.stop()
        let reopened = GuestDataStore(storeURL: url)
        let late = LibraryLocalChange(command: .folderRestore(.init(deletionId: proof.reply.receipts[0].id, name: "Late restore original", hadithIds: [])), at: Date.now.millisecondsSinceEpoch, source: .account(nil))
        try reopened.enqueueSyncChange(late, owner: owner)
        var steps = 0
        while try reopened.pruneOutcomeSuccessStep(owner, now: acknowledgedAt + LibraryOutcomeRetention.duration) { steps += 1; XCTAssertLessThan(steps, 30) }
        XCTAssertThrowsError(try reopened.outcomeEvidencePage(proof, owner: owner, start: 0))
        XCTAssertEqual(try reopened.syncPartition(owner)?.pending, [late])
        let inspection = try ModelContainer(for: GuestDataStore.schema, configurations: [ModelConfiguration(schema: GuestDataStore.schema, url: url)]), inspectionContext = ModelContext(inspection)
        XCTAssertEqual(try inspectionContext.fetchCount(FetchDescriptor<GuestOutcomeMember>()), 0)
        XCTAssertEqual(try inspectionContext.fetchCount(FetchDescriptor<GuestOutcomeHeader>()), 0)
        XCTAssertEqual(try inspectionContext.fetchCount(FetchDescriptor<GuestOutcomeInventory>()), 0)
        XCTAssertEqual(try inspectionContext.fetchCount(FetchDescriptor<GuestOutcomeScope>()), 0)
        let resumed = LibraryFacadeFixture(store: reopened); resumed.server.failSends = false; resumed.server.nextOutcome = .unresolved(.init(reason: .missingFolder))
        defer { resumed.stop() }; await resumed.start()
        XCTAssertEqual(resumed.server.frames.first?.batch.operations, [late.operation])
        guard case .server(let original, .unresolved) = try XCTUnwrap(reopened.syncPartition(owner)?.recovery.last) else { return XCTFail("Late server rejection lost original") }
        XCTAssertEqual(original, late)
    }

    @MainActor func testOutcomeRetentionCursorPassesFiftyRetainedHeadersAndResumesAfterReopen() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        let (store, proof, _) = try await acknowledgedRetentionFixture(count: 1, url: url)
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), key = try LibraryOutcomeBinding(owner: owner, committed: proof).key
        let retained = try (0..<1_000).map { taggedOutcomeProof(owner, count: 0, tag: "retained-\($0)") }.filter { try LibraryOutcomeBinding(owner: owner, committed: $0).key < key }.prefix(51)
        XCTAssertEqual(retained.count, 51)
        for item in retained { try await collectExportFacts(item, owner: owner, count: 0, store: store) }
        _ = try await store.prepareOutcomeExport(owner, isCurrent: { true })
        XCTAssertTrue(try store.pruneOutcomeSuccessStep(owner, now: 2_000 + LibraryOutcomeRetention.duration))
        XCTAssertNotNil(try store.syncPartition(owner)?.outcomeRetentionCursor)
        XCTAssertEqual(try store.outcomeEvidencePage(proof, owner: owner, start: 0).rows.count, 1)
        let reopened = GuestDataStore(storeURL: url)
        XCTAssertTrue(try reopened.pruneOutcomeSuccessStep(owner, now: 2_000 + LibraryOutcomeRetention.duration))
        XCTAssertThrowsError(try reopened.outcomeEvidencePage(proof, owner: owner, start: 0))
        for item in retained { XCTAssertEqual(try reopened.outcomeEvidencePage(item, owner: owner, start: 0).checkpoint.retention, nil) }
        XCTAssertFalse(try reopened.pruneOutcomeSuccessStep(owner, now: 2_000 + LibraryOutcomeRetention.duration))
        XCTAssertNil(try reopened.syncPartition(owner)?.outcomeRetentionCursor)
    }

    func testOutcomeRetentionPolicyPreservesEachDurableDependencyAndOldProoflessData() throws {
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), proof = taggedOutcomeProof(owner, count: 1, tag: "policy")
        let binding = try LibraryOutcomeBinding(owner: owner, committed: proof), now = 2_000 + LibraryOutcomeRetention.duration
        let checkpoint = LibraryOutcomeCheckpoint(counts: binding.expected, status: .complete, retention: .init(acknowledgedAt: 2_000, removed: nil))
        var base = LibraryPartitionState(); base.savedSnapshot = .init(ownerKey: owner.key, version: 2, folders: [], items: [])
        XCTAssertTrue(try base.canPruneOutcome(binding, checkpoint: checkpoint, observed: observation(base, owner: binding.owner), now: now))
        XCTAssertFalse(try base.canPruneOutcome(binding, checkpoint: checkpoint, observed: observation(base, owner: binding.owner), now: now - 1))
        XCTAssertFalse(try base.canPruneOutcome(binding, checkpoint: checkpoint, observed: observation(base, owner: binding.owner), now: 1_000))
        XCTAssertFalse(try base.canPruneOutcome(binding, checkpoint: .init(counts: binding.expected, status: .complete), observed: observation(base, owner: binding.owner), now: now))
        let undo = LibraryLocalChange(command: .folderRestore(.init(deletionId: binding.request.receiptId, name: "Offline Undo", hadithIds: [])), at: 1_000, source: .account(nil))
        var states: [LibraryPartitionState] = []
        var pending = base; pending.pending = [undo]; states.append(pending)
        var frozen = base; frozen.frozen = .init(batch: .init(id: "frozen", operations: [undo.operation]), changes: [undo]); states.append(frozen)
        var linked = base; linked.manifestAckLink = binding; states.append(linked)
        var collecting = base; collecting.collectingOutcome = .init(committed: proof, origin: .historical); states.append(collecting)
        var recent = base; recent.recent = [.init(receipt: proof.reply.receipts[0], expiresAt: now + 1)]; states.append(recent)
        for entry: LibraryRecovery in [.server(undo, .unresolved(.init(reason: .missingFolder))), .historical(undo), .rejected(undo), .outcome(authority: binding, checkpoint: checkpoint, original: nil)] {
            var recovered = base; recovered.recovery = [entry]; states.append(recovered)
        }
        for state in states { XCTAssertFalse(try state.canPruneOutcome(binding, checkpoint: checkpoint, observed: observation(state, owner: binding.owner), now: now)) }
    }

    func testOutcomeRetentionDependenciesDoNotBlockUnrelatedJournals() throws {
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        let deleteA = try LibraryOutcomeBinding(owner: owner, committed: taggedOutcomeProof(owner, count: 1, tag: "a"))
        let deleteB = try LibraryOutcomeBinding(owner: owner, committed: taggedOutcomeProof(owner, count: 1, tag: "b"))
        func restore(_ tag: String) throws -> LibraryOutcomeBinding {
            let base = taggedOutcomeProof(owner, count: 1, tag: tag)
            return try .init(owner: owner, committed: .init(clientKey: base.clientKey, sequence: base.sequence, digest: base.digest, revision: base.revision,
                reply: .init(ownerKey: owner.key, batchId: base.reply.batchId, receipts: [.init(id: tag + "-restore", revision: "r1", outcome: .folderRestoredManifest(.init(manifestId: tag, generation: "generation", folderId: "destination-" + tag, restored: 1, superseded: 0, missing: 0)))])))
        }
        let restoreA = try restore("a"), restoreB = try restore("b")
        var state = LibraryPartitionState()
        let undo = LibraryLocalChange(command: .folderRestore(.init(deletionId: deleteA.request.receiptId, name: "Undo A", hadithIds: [])), at: 1_000, source: .account(nil))
        for recovery in [false, true] {
            state.pending = recovery ? [] : [undo]; state.recovery = recovery ? [.historical(undo)] : []
            XCTAssertTrue(state.retainsOutcome(deleteA, now: 99_000))
            XCTAssertFalse(state.retainsOutcome(deleteB, now: 99_000))
            XCTAssertFalse(state.retainsOutcome(restoreB, now: 99_000))
        }
        state.recovery = []; state.folderMappings["alias-a"] = "destination-a"
        for command: SyncCommand in [.membershipPut(.init(hadithId: "hadith", folder: .local(.init(key: "alias-a")), mode: nil)), .folderDelete(.init(folder: .local(.init(key: "alias-a"))))] {
            state.pending = [.init(command: command, at: 1_000, source: .account(nil))]
            XCTAssertTrue(state.retainsOutcome(restoreA, now: 99_000))
            XCTAssertFalse(state.retainsOutcome(restoreB, now: 99_000))
            XCTAssertFalse(state.retainsOutcome(deleteA, now: 99_000))
        }
    }

    @MainActor func testCoordinatorPrunesAcknowledgedSuccessfulOutcomeAfterRetention() async throws {
        let store = GuestDataStore(inMemory: true), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        let session = LibrarySyncSession(id: "session-a", subject: owner.subject)
        var clock = 1_000.0, proof: SyncCommitted?, acknowledgements = 0
        try store.claimGuestForSync(owner)
        try store.enqueueSyncChange(.init(command: .folderDelete(.init(folder: .server(.init(id: "folder")))), at: clock, source: .account(nil)), owner: owner)
        try store.cacheSavedSnapshot(.init(ownerKey: owner.key, version: 1, folders: [], items: []), owner: owner)
        let sync = LibrarySync(store: store, transport: .init(namespace: owner.namespace, open: {
            .init(ownerKey: owner.key, subject: owner.subject, capability: "fixture", validUntil: clock + 60_000)
        }, acknowledge: { _, value in acknowledgements += 1; return self.acknowledged(value) }, send: { _, frame in
            let operation = frame.batch.operations[0]
            let committed = SyncCommitted(clientKey: frame.clientKey, sequence: frame.sequence, digest: "fixture-proof", revision: .init(saved: 1, position: 0), reply: .init(ownerKey: owner.key, batchId: frame.batch.id,
                receipts: [.init(id: operation.id, revision: operation.revision, outcome: .folderDeletedManifest(.init(manifestId: "manifest", generation: "generation", count: 1, deletedAt: clock)))]))
            proof = committed; return .accepted(.init(committed: committed))
        }, outcomePage: { _, request in self.outcomePage(request, owner: owner, count: 1) }), currentSession: { session }, now: { clock })
        defer { sync.deactivate() }
        await sync.activate(session)
        let committed = try XCTUnwrap(proof)
        XCTAssertEqual(acknowledgements, 1)
        XCTAssertEqual(try store.outcomeEvidencePage(committed, owner: owner, start: 0).rows.count, 1)
        try await waitForLibrary { (try? store.syncPartition(owner)?.outcomeRetentionCursor) == nil && sync.status == .ready(recovered: 0) }
        clock += 31 * 24 * 60 * 60 * 1_000
        await sync.activate(session)
        try await waitForLibrary { (try? store.outcomeEvidencePage(committed, owner: owner, start: 0)) == nil }
        XCTAssertThrowsError(try store.outcomeEvidencePage(committed, owner: owner, start: 0), "Successful acknowledged journal remained forever")
        let fence = try await store.prepareOutcomeExport(owner, isCurrent: { true })
        XCTAssertTrue(try store.outcomeExportEntries(fence, after: nil).isEmpty)
    }

    @MainActor func testOutcomeSettlementUnavailablePolicySurvivesReopenAndExport() async throws {
        for reason in [SyncOutcomePageUnavailableReason.detailUnavailable, .proofUnavailable] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
            let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), store = GuestDataStore(storeURL: url)
            try store.claimGuestForSync(owner)
            let original = LibraryLocalChange(command: .folderRestore(.init(deletionId: "deleted", name: "Original unavailable", hadithIds: ["hadith-0"])), at: 1_000, source: .account(nil))
            try store.enqueueSyncChange(original, owner: owner)
            let frame = try XCTUnwrap(store.freezeSyncFrame(owner)), operation = frame.batch.operations[0]
            let proof = SyncCommitted(clientKey: frame.clientKey, sequence: frame.sequence, digest: "fixture-digest", revision: .init(saved: 2, position: 0), reply: .init(ownerKey: owner.key, batchId: frame.batch.id,
                receipts: [.init(id: operation.id, revision: operation.revision, outcome: .folderRestoredManifest(.init(manifestId: "manifest", generation: "generation", folderId: "destination", restored: 50, superseded: 0, missing: 1)))]))
            try store.settleSyncExchange(.accepted(.init(committed: proof)), requested: frame, owner: owner)
            _ = try await store.collectOutcomeStep(proof, owner: owner, isCurrent: { true }) { self.outcomePage($0, owner: owner, count: 51, restore: true) }
            _ = try await store.collectOutcomeStep(proof, owner: owner, isCurrent: { true }) { .unavailable(.init(ownerKey: owner.key, request: $0, reason: reason)) }
            try store.cacheSavedSnapshot(.init(ownerKey: owner.key, version: 2, folders: [], items: []), owner: owner)
            let pending = try XCTUnwrap(store.syncPartition(owner)?.collectingOutcome), before = try store.syncPartition(owner)
            let reopened = GuestDataStore(storeURL: url)
            XCTAssertEqual(try reopened.settleCollectedOutcome(pending, owner: owner, now: 2_000), reason == .detailUnavailable ? .settled : .proofUnavailable)
            if reason == .proofUnavailable { XCTAssertEqual(try reopened.syncPartition(owner), before) }
            else { XCTAssertNotNil(try reopened.syncPartition(owner)?.acknowledgement) }
            let fixture = LibraryFacadeFixture(store: reopened); defer { fixture.stop() }
            await fixture.start()
            XCTAssertEqual(fixture.server.acknowledgements, reason == .detailUnavailable ? 1 : 0)
            let captured = try fixture.sync.captureWriteContext(), export = try await fixture.sync.preparePortableExport(server: .object([:]), context: captured, fileName: "export.json")
            let data = try Data(contentsOf: export.url), probe = try JSONDecoder().decode(OutcomeExportProbe.self, from: data)
            XCTAssertEqual(probe.localOutcomeEvidence.first?.rows.count, 50)
            XCTAssertEqual(probe.localOutcomeEvidence.first?.detailComplete, false)
            XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("Original unavailable"))
            try fixture.sync.discardPreparedExport(export)
        }
    }

    @MainActor func testOutcomeSettlementRejectsForeignScopeAndErasedOwnerWithoutRecreation() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), store = GuestDataStore(storeURL: url)
        try store.claimGuestForSync(owner)
        try store.enqueueSyncChange(.init(command: .folderDelete(.init(folder: .server(.init(id: "folder")))), at: 1_000, source: .account(nil)), owner: owner)
        let frame = try XCTUnwrap(store.freezeSyncFrame(owner)), operation = frame.batch.operations[0]
        let proof = SyncCommitted(clientKey: frame.clientKey, sequence: frame.sequence, digest: "fixture-digest", revision: .init(saved: 2, position: 0), reply: .init(ownerKey: owner.key, batchId: frame.batch.id,
            receipts: [.init(id: operation.id, revision: operation.revision, outcome: .folderDeletedManifest(.init(manifestId: "manifest", generation: "generation", count: 1, deletedAt: 1_000)))]))
        try store.settleSyncExchange(.accepted(.init(committed: proof)), requested: frame, owner: owner)
        try await collectExportFacts(proof, owner: owner, count: 1, store: store)
        try store.cacheSavedSnapshot(.init(ownerKey: owner.key, version: 2, folders: [], items: []), owner: owner)
        let before = try XCTUnwrap(store.syncPartition(owner)), pending = try XCTUnwrap(before.collectingOutcome)
        let foreign = LibrarySyncOwner(key: owner.key, subject: owner.subject, namespace: "other-deployment")
        XCTAssertThrowsError(try store.settleCollectedOutcome(pending, owner: foreign, now: 2_000))
        XCTAssertEqual(try store.syncPartition(owner), before)
        XCTAssertNil(try store.syncPartition(foreign))
        try store.beginDeletion(subject: owner.subject, namespace: owner.namespace)
        try await store.markDeletionBackendComplete(subject: owner.subject, namespace: owner.namespace)
        let reopened = GuestDataStore(storeURL: url)
        XCTAssertThrowsError(try reopened.settleCollectedOutcome(pending, owner: owner, now: 2_000))
        XCTAssertNil(try reopened.syncPartition(owner))
        XCTAssertThrowsError(try reopened.outcomeEvidencePage(proof, owner: owner, start: 0))
    }

    func testOutcomeSettlementTerminalPoliciesAndExactIntent() throws {
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        for mode in ["delete", "restore", "partial", "detail", "proof", "historical"] {
            var state = LibraryPartitionState()
            let command: SyncCommand = mode == "delete" ? .folderDelete(.init(folder: .server(.init(id: "folder"))))
                : .folderRestore(.init(deletionId: "deleted", name: "Original folder", hadithIds: ["hadith-0", "hadith-1"]))
            state.append(.account(nil), command: command, at: 1_000)
            let frame = try XCTUnwrap(state.freeze()), operation = frame.batch.operations[0]
            let outcome: SyncOutcome = mode == "delete" ? .folderDeletedManifest(.init(manifestId: "manifest", generation: "generation", count: 51, deletedAt: 1_000))
                : .folderRestoredManifest(.init(manifestId: "manifest", generation: "generation", folderId: "destination", restored: 50, superseded: 0, missing: mode == "restore" ? 0 : 1))
            let proof = SyncCommitted(clientKey: frame.clientKey, sequence: frame.sequence, digest: "fixture-digest", revision: .init(saved: 2, position: 0), reply: .init(ownerKey: owner.key, batchId: frame.batch.id,
                receipts: [.init(id: operation.id, revision: operation.revision, outcome: outcome)]))
            if mode == "historical" {
                try state.settle(.reconcile(.init(ownerKey: owner.key, clientKey: frame.clientKey, requestedSequence: frame.sequence, requestedBatchId: frame.batch.id,
                    cursor: .init(closedThrough: 0, outstanding: .committed(.init(committed: proof))))), requested: frame, owner: observationOwner(state), observed: observation(state), now: 2_000)
            } else { try state.settle(.accepted(.init(committed: proof)), requested: frame, owner: observationOwner(state), observed: observation(state), now: 2_000) }
            let pending = try XCTUnwrap(state.collectingOutcome), binding = try LibraryOutcomeBinding(owner: owner, committed: proof)
            var checkpoint = LibraryOutcomeCheckpoint(counts: binding.expected, status: .complete)
            if mode == "detail" || mode == "proof" { checkpoint = .init(counts: .init(restored: 50), status: .unavailable(mode == "detail" ? .detailUnavailable : .proofUnavailable)) }
            state.savedSnapshot = .init(ownerKey: owner.key, version: 1, folders: [], items: [])
            let before = state
            XCTAssertEqual(try state.settleCollectedOutcome(pending, binding: binding, checkpoint: checkpoint, observed: observation(state, owner: binding.owner), now: 2_000), mode == "proof" ? .proofUnavailable : .awaitingSaved)
            XCTAssertEqual(state, before)
            state.savedSnapshot = .init(ownerKey: owner.key, version: 3, folders: [], items: [])
            if mode == "proof" {
                let blocked = state
                XCTAssertEqual(try state.settleCollectedOutcome(pending, binding: binding, checkpoint: checkpoint, observed: observation(state, owner: binding.owner), now: 2_000), .proofUnavailable)
                XCTAssertEqual(state, blocked); continue
            }
            if mode == "delete" {
                var late = state
                XCTAssertEqual(try late.settleCollectedOutcome(pending, binding: binding, checkpoint: checkpoint, observed: observation(late, owner: binding.owner), now: 7_000), .settled)
                XCTAssertTrue(late.recent.isEmpty)
            }
            if mode == "partial" {
                for status in [LibraryOutcomeStatus.collecting, .verifying(.init())] {
                    var unfinished = state; let unfinishedBefore = unfinished
                    XCTAssertEqual(try unfinished.settleCollectedOutcome(pending, binding: binding, checkpoint: .init(counts: binding.expected, status: status), observed: observation(unfinished, owner: binding.owner), now: 2_000), .collecting)
                    XCTAssertEqual(unfinished, unfinishedBefore)
                }
                var incomplete = state; let incompleteBefore = incomplete
                XCTAssertThrowsError(try incomplete.settleCollectedOutcome(pending, binding: binding, checkpoint: .init(status: .complete), observed: observation(incomplete, owner: binding.owner), now: 2_000)); XCTAssertEqual(incomplete, incompleteBefore)
                var missing = state; missing.frozen = nil; let missingBefore = missing
                XCTAssertThrowsError(try missing.settleCollectedOutcome(pending, binding: binding, checkpoint: checkpoint, observed: observation(missing, owner: binding.owner), now: 2_000)); XCTAssertEqual(missing, missingBefore)
                var wrongOwner = state; wrongOwner.savedSnapshot = .init(ownerKey: "owner-b", version: 3, folders: [], items: []); let wrongBefore = wrongOwner
                XCTAssertThrowsError(try wrongOwner.settleCollectedOutcome(pending, binding: binding, checkpoint: checkpoint, observed: observation(wrongOwner, owner: binding.owner), now: 2_000)); XCTAssertEqual(wrongOwner, wrongBefore)
                var fork = try JSONDecoder().decode(LibraryPartitionState.self, from: Data(String(decoding: JSONEncoder().encode(state), as: UTF8.self).replacingOccurrences(of: "Original folder", with: "Changed folder").utf8))
                let forkBefore = fork
                XCTAssertThrowsError(try fork.settleCollectedOutcome(pending, binding: binding, checkpoint: checkpoint, observed: observation(fork, owner: binding.owner), now: 2_000)); XCTAssertEqual(fork, forkBefore)
                var conflict = state; conflict.folderMappings["restore:deleted"] = "another-folder"; let conflictBefore = conflict
                XCTAssertThrowsError(try conflict.settleCollectedOutcome(pending, binding: binding, checkpoint: checkpoint, observed: observation(conflict, owner: binding.owner), now: 2_000)); XCTAssertEqual(conflict, conflictBefore)
            }
            XCTAssertEqual(try state.settleCollectedOutcome(pending, binding: binding, checkpoint: checkpoint, observed: observation(state, owner: binding.owner), now: 2_000), .settled)
            XCTAssertEqual(state.nextSequence, 2); XCTAssertNil(state.collectingOutcome); XCTAssertNil(state.frozen)
            if mode == "delete" { XCTAssertEqual(state.recent.map(\.expiresAt), [6_000]); XCTAssertTrue(state.recovery.isEmpty) }
            else if mode == "restore" { XCTAssertEqual(state.folderMappings["restore:deleted"], "destination"); XCTAssertTrue(state.recovery.isEmpty) }
            else {
                guard case .outcome(let authority, let retained, let original) = try XCTUnwrap(state.recovery.last) else { return XCTFail("Missing journal recovery") }
                XCTAssertEqual(authority, binding); XCTAssertEqual(retained, checkpoint)
                XCTAssertEqual(original, mode == "historical" ? nil : before.frozen?.changes.first)
                if mode == "historical" { XCTAssertEqual(state.recovery.count, 2) }
            }
            let settled = state
            XCTAssertEqual(try state.settleCollectedOutcome(pending, binding: binding, checkpoint: checkpoint, observed: observation(state, owner: binding.owner), now: 7_000), .settled)
            XCTAssertEqual(state, settled)
        }
    }

    @MainActor func testManifestSettlementWaitsForOwnedSavedThenPersistsRecoveryBeforeRetryableAck() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), store = GuestDataStore(storeURL: url)
        try store.claimGuestForSync(owner)
        let original = LibraryLocalChange(command: .folderRestore(.init(deletionId: "deleted", name: "Original folder", hadithIds: ["hadith-0", "hadith-1"])), at: 1_000, source: .account(nil))
        try store.enqueueSyncChange(original, owner: owner)
        let frame = try XCTUnwrap(store.freezeSyncFrame(owner)), operation = frame.batch.operations[0]
        let proof = SyncCommitted(clientKey: frame.clientKey, sequence: frame.sequence, digest: "fixture-digest", revision: .init(saved: 2, position: 0),
            reply: .init(ownerKey: owner.key, batchId: frame.batch.id, receipts: [.init(id: operation.id, revision: operation.revision,
                outcome: .folderRestoredManifest(.init(manifestId: "manifest", generation: "generation", folderId: "restored-folder", restored: 1, superseded: 0, missing: 1)))]))
        try store.settleSyncExchange(.accepted(.init(committed: proof)), requested: frame, owner: owner)
        for _ in 0..<2 { _ = try await store.collectOutcomeStep(proof, owner: owner, isCurrent: { true }) { self.outcomePage($0, owner: owner, count: 2, restore: true) } }
        let later = LibraryLocalChange(command: .notePut(.init(hadithId: "later", content: "Later original", createdAt: 2_000, updatedAt: 2_000)), at: 2_000, source: .account(nil))
        try store.enqueueSyncChange(later, owner: owner)
        let fixture = LibraryFacadeFixture(store: store); fixture.server.failAcknowledgements = true
        await fixture.start()
        fixture.saved.send(fixture.snapshot(version: 1, note: "Before barrier"))
        try await waitForLibrary { (try? store.syncPartition(owner)?.savedSnapshot?.version) == 1 }
        XCTAssertEqual(fixture.server.acknowledgements, 0); XCTAssertNotNil(try store.syncPartition(owner)?.frozen)
        fixture.saved.send(fixture.snapshot(version: 2, note: "Authoritative"))
        try await waitForLibrary { fixture.server.acknowledgements > 0 }
        let settled = try XCTUnwrap(store.syncPartition(owner))
        XCTAssertNil(settled.collectingOutcome); XCTAssertNil(settled.frozen)
        XCTAssertEqual(settled.pending, [later]); XCTAssertEqual(settled.nextSequence, 2)
        XCTAssertNotNil(settled.acknowledgement); XCTAssertEqual(settled.recovery.count, 1)
        XCTAssertEqual(settled.folderMappings["restore:deleted"], "restored-folder")
        XCTAssertTrue(String(decoding: try JSONEncoder().encode(settled.recovery), as: UTF8.self).contains("Original folder"))
        fixture.stop()
        let reopened = GuestDataStore(storeURL: url), resumed = LibraryFacadeFixture(store: reopened)
        defer { resumed.stop() }
        await resumed.start()
        XCTAssertEqual(resumed.server.acknowledgements, 1)
        XCTAssertNil(try reopened.syncPartition(owner)?.acknowledgement)
        XCTAssertEqual(try reopened.syncPartition(owner)?.recovery, settled.recovery)
        XCTAssertEqual(try reopened.syncPartition(owner)?.frozen?.changes, [later])
        XCTAssertEqual(try reopened.outcomeEvidencePage(proof, owner: owner, start: 0).rows.count, 2)
    }

    @MainActor func testCoordinatorResumesManifestPagesAfterReopenWithoutAcknowledgingOrSendingLaterChanges() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), session = LibrarySyncSession(id: "session-a", subject: "subject-a")
        let store = GuestDataStore(storeURL: url); try store.claimGuestForSync(owner)
        try store.enqueueSyncChange(.init(command: .folderDelete(.init(folder: .server(.init(id: "folder")))), at: 1_000, source: .account(nil)), owner: owner)
        let later = LibraryLocalChange(command: .bookmarkAdd(.init(hadithId: "later", createdAt: 2_000)), at: 2_000, source: .account(nil))
        try store.enqueueSyncChange(later, owner: owner)
        var proof: SyncCommitted?, sends = 0, acknowledgements = 0, starts: [Double] = []
        func transport(failAt100: Bool) -> LibrarySyncTransport {
            .init(namespace: "fixture", open: { .init(ownerKey: owner.key, subject: owner.subject, capability: "fixture", validUntil: Date.now.millisecondsSinceEpoch + 60_000) },
                acknowledge: { _, value in acknowledgements += 1; return self.acknowledged(value) }, send: { _, frame in
                    sends += 1
                    let operation = frame.batch.operations[0]
                    let committed = SyncCommitted(clientKey: frame.clientKey, sequence: frame.sequence, digest: "fixture-digest", revision: .init(saved: 2, position: 0),
                        reply: .init(ownerKey: owner.key, batchId: frame.batch.id, receipts: [.init(id: operation.id, revision: operation.revision,
                            outcome: .folderDeletedManifest(.init(manifestId: "manifest", generation: "generation", count: 501, deletedAt: 1_000)))]))
                    proof = committed
                    return .accepted(.init(committed: committed))
                }, outcomePage: { _, request in
                    starts.append(request.start)
                    if failAt100 && request.start == 100 { throw LibrarySyncFailure.storeUnavailable }
                    return self.outcomePage(request, owner: owner, count: 501)
                })
        }
        let sync = LibrarySync(store: store, transport: transport(failAt100: true), currentSession: { session })
        await sync.activate(session)
        XCTAssertEqual(sync.status, .failed); sync.deactivate()
        let committed = try XCTUnwrap(proof), original = try XCTUnwrap(store.syncPartition(owner))
        XCTAssertEqual(original.collectingOutcome?.committed, committed); XCTAssertEqual(original.pending, [later])
        XCTAssertNotNil(original.frozen); XCTAssertNil(original.acknowledgement)
        XCTAssertEqual(try store.outcomeEvidencePage(committed, owner: owner, start: 0).checkpoint.next, 100)
        starts = []
        let reopened = GuestDataStore(storeURL: url), resumed = LibrarySync(store: reopened, transport: transport(failAt100: false), currentSession: { session })
        defer { resumed.deactivate() }
        await resumed.activate(session)
        try await waitForLibrary { resumed.status == .waitingForSaved }
        XCTAssertEqual(starts, stride(from: 100, through: 500, by: 50).map(Double.init))
        XCTAssertEqual(try reopened.outcomeEvidencePage(committed, owner: owner, start: 500).checkpoint.status, .complete)
        XCTAssertEqual(try reopened.syncPartition(owner), original)
        XCTAssertEqual(sends, 1); XCTAssertEqual(acknowledgements, 0)
    }

    func testMalformedManifestCannotArchiveOriginalBeforeValidation() throws {
        var state = LibraryPartitionState()
        state.append(.account(nil), command: .folderDelete(.init(folder: .server(.init(id: "folder")))), at: 1_000)
        let frame = try XCTUnwrap(state.freeze()), before = state, operation = frame.batch.operations[0]
        let bad = SyncCommitted(clientKey: frame.clientKey, sequence: frame.sequence, digest: "digest", revision: .init(saved: 2, position: 0),
            reply: .init(ownerKey: "owner-a", batchId: frame.batch.id, receipts: [.init(id: operation.id, revision: operation.revision,
                outcome: .folderRestoredManifest(.init(manifestId: "manifest", generation: "generation", folderId: "folder", restored: 2, superseded: 0, missing: -1)))]))
        XCTAssertThrowsError(try state.settle(.reconcile(.init(ownerKey: "owner-a", clientKey: frame.clientKey, requestedSequence: frame.sequence, requestedBatchId: frame.batch.id,
            cursor: .init(closedThrough: 0, outstanding: .committed(.init(committed: bad))))), requested: frame, owner: observationOwner(state), observed: observation(state), now: 2_000))
        XCTAssertEqual(state, before)
    }

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
        try state.settle(.reconcile(.init(ownerKey: "owner-a", clientKey: frame.clientKey, requestedSequence: frame.sequence, requestedBatchId: frame.batch.id, cursor: .init(closedThrough: 0, outstanding: .pending(.init(pending: pending))))), requested: frame, owner: observationOwner(state), observed: observation(state), now: 2_000)
        XCTAssertNil(state.frozen)
        XCTAssertEqual(state.recovery.count, 1)
        let reply = SyncReply(ownerKey: "owner-a", batchId: frame.batch.id, receipts: [.init(id: original.id, revision: original.revision, outcome: .preserved)])
        try state.settlePending(accepted(frame, reply: reply), requested: pending, owner: observationOwner(state), observed: observation(state), now: 2_000)
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

    @MainActor func testPortableExportIncludesDurableOutcomeJournal() async throws {
        let fixture = LibraryFacadeFixture(store: GuestDataStore(inMemory: true))
        defer { fixture.stop() }
        await fixture.start()
        let owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a"), proof = outcomeProof(owner, count: 51)
        for _ in 0..<4 { _ = try await fixture.store.collectOutcomeStep(proof, owner: owner, isCurrent: { true }) { self.outcomePage($0, owner: owner, count: 51) } }
        let captured = try fixture.sync.captureWriteContext()
        let export = try await fixture.sync.preparePortableExport(server: .object(["sync": .object([:])]), context: captured, fileName: "export.json")
        defer { try? fixture.sync.discardPreparedExport(export) }
        let data = try Data(contentsOf: export.url)
        _ = try JSONDecoder().decode(LibraryExportValue.self, from: data)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("member-50"), "Retained journal facts must be in the private export")
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
        XCTAssertEqual(try legacyProjection(state).items.first?.folderId, "cloud-folder")
        state.pending = []
        state.confirmed = [.init(change: change, outcome: .preserved, version: 2)]
        state.folderMappings["old-guest-folder"] = "accepted-guest-folder"
        XCTAssertEqual(try legacyProjection(state).items.first?.folderId, "accepted-guest-folder")
        state.confirmed = []
        XCTAssertEqual(try legacyProjection(state).items.first?.folderId, "cloud-folder")
        let batch = SyncBatch(id: "unversioned-rejected", operations: [change.operation])
        state.frozen = .init(batch: batch, changes: [change])
        let frame = SyncFrame(clientKey: state.clientKey, sequence: Double(state.nextSequence), batch: batch)
        let outcome = SyncOutcome.superseded(.init(reason: .unversionedCloud))
        try state.settle(accepted(frame, reply: .init(ownerKey: owner.key, batchId: batch.id, receipts: [.init(id: change.operation.id, revision: change.operation.revision, outcome: outcome)])), requested: frame, owner: observationOwner(state), observed: observation(state), now: Date.now.millisecondsSinceEpoch)
        XCTAssertEqual(state.recovery, [.server(change, outcome)])
        XCTAssertEqual(try legacyProjection(state).items.first?.folderId, "cloud-folder")
        let reopened = try JSONDecoder().decode(LibraryPartitionState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(reopened.recovery, state.recovery)
    }

    @MainActor private func seedPartitionFixture(_ state: LibraryPartitionState, owner: LibrarySyncOwner, url: URL) throws {
        let schema = GuestDataStore.schema
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
        try store.resetSyncPartitionForTesting(ownerB)
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
    var nextOutcome: SyncOutcome?
    var failAcknowledgements = false
    var acknowledgements = 0
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
        let outcome = nextOutcome ?? .preserved; nextOutcome = nil
        let receipts = frame.batch.operations.map { SyncReceipt(id: $0.id, revision: $0.revision, outcome: outcome) }
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
            server.acknowledgements += 1
            if server.failAcknowledgements { throw LibraryFixtureServer.Failure.offline }
            return .init(ownerKey: String(capability.dropFirst("fixture:".count)), clientKey: value.clientKey, cursor: .init(closedThrough: value.sequence, outstanding: nil))
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

@MainActor private final class LibrarySavedReadFixture {
    let store: GuestDataStore
    var session: LibrarySyncSession? = .init(id: "session-a", subject: "subject-a")
    var now = 1_000.0, bindingTTL = 900_000.0
    var opens = 0
    let heads = PassthroughSubject<SavedReadHead, Error>()
    let referenceReply: SavedReferenceReply
    let textReply: SavedTextReply
    let target = "10002;hadiths"
    var headStarts = 0
    var onHeadRequest: (() -> Void)?
    var headFetch: ((String) -> AnyPublisher<SavedReadHead, Error>)?
    var referenceFetch: ((String, String) async throws -> SavedReferenceReply)?
    var textFetch: ((String, String) async throws -> SavedTextReply)?
    lazy var sync = LibrarySync(store: store, transport: .init(namespace: "fixture", open: { [unowned self] in
        let current = try XCTUnwrap(session); opens += 1
        return .init(ownerKey: current.subject == "subject-a" ? "10000;users" : "owner-b", subject: current.subject, capability: "fixture-read-\(opens)", validUntil: now + bindingTTL)
    }, acknowledge: { _, _ in throw LibrarySyncFailure.invalidChange }, send: { _, _ in throw LibrarySyncFailure.invalidChange }, savedHeads: { [unowned self] capability in
        headStarts += 1
        return headFetch?(capability) ?? heads.handleEvents(receiveRequest: { [unowned self] demand in
            if demand > .none { let ready = onHeadRequest; onHeadRequest = nil; ready?() }
        }).eraseToAnyPublisher()
    }, savedReference: { [unowned self] capability, target in
        if let referenceFetch { return try await referenceFetch(capability, target) }; return referenceReply
    }, savedText: { [unowned self] capability, target in
        if let textFetch { return try await textFetch(capability, target) }; return textReply
    }), currentSession: { [unowned self] in session }, now: { [unowned self] in now })
    init(store: GuestDataStore) throws {
        self.store = store
        referenceReply = try JSONDecoder().decode(SavedReferenceReply.self, from: Data(LibrarySavedReadsParityVector.referenceJSON.utf8))
        textReply = try JSONDecoder().decode(SavedTextReply.self, from: Data(LibrarySavedReadsParityVector.textJSON.utf8))
    }
    func start() async throws { await sync.activate(try XCTUnwrap(session)) }
}


@MainActor
final class A2LiveLibraryTests: XCTestCase {
    private struct Configuration: Decodable {
        let phase: String, runId: String, email: String, password: String
        let secondEmail: String, secondPassword: String
        let hadithId: String, collectionName: String, referenceDisplay: String, volumeId: String, providerHadithId: String
        let expiresAt: Double
    }

    private func wait(_ label: String, _ condition: () throws -> Bool) async throws {
        print("A2 live check: \(label)")
        for _ in 0..<300 {
            if try condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw NSError(domain: "A2Live", code: 1, userInfo: [NSLocalizedDescriptionKey: label])
    }

    private func authenticate(email: String, password: String, create: Bool) async throws {
        guard email.hasSuffix("+clerk_test@example.com") else { throw NSError(domain: "A2Live", code: 5) }
        if Clerk.shared.session != nil {
            guard Clerk.shared.user?.primaryEmailAddress?.emailAddress == email else {
                throw NSError(domain: "A2Live", code: 2, userInfo: [NSLocalizedDescriptionKey: "Refusing to replace another account session"])
            }
            return
        }
        var stage = "start"
        do {
            let sessionId: String?
            if create {
                stage = "create"
                let signUp = try await Clerk.shared.auth.signUp(emailAddress: email, password: password, username: String(email.prefix(while: { $0 != "+" })))
                if signUp.status == .complete { sessionId = signUp.createdSessionId }
                else {
                    stage = "prepare-code"
                    let prepared = try await signUp.sendEmailCode()
                    stage = "verify-code"
                    sessionId = try await prepared.verifyEmailCode("424242").createdSessionId
                }
            } else {
                stage = "prepare-email-sign-in"
                let pending = try await Clerk.shared.auth.signInWithEmailCode(emailAddress: email)
                stage = "verify-email-sign-in"
                let signIn = try await pending.verifyCode("424242")
                sessionId = signIn.createdSessionId
            }
            guard let sessionId else { throw NSError(domain: "A2Live", code: 3) }
            try await Clerk.shared.auth.setActive(sessionId: sessionId)
        } catch {
            if create, (error as? ClerkAPIError)?.code == "form_identifier_exists" {
                try await authenticate(email: email, password: password, create: false)
                return
            }
            let code = (error as? ClerkAPIError)?.code ?? "sdk_error"
            throw NSError(domain: "A2Live", code: 4, userInfo: [NSLocalizedDescriptionKey: "Development test authentication failed at \(stage): \(code); credentials redacted"])
        }
        try await wait("Development account did not become active") { Clerk.shared.user?.primaryEmailAddress?.emailAddress == email }
    }

    private func activate(_ environment: AppEnvironment) async throws {
        _ = await environment.convex.loginFromCache()
        await environment.completeSignIn()
        try await wait("Authenticated production library did not become ready") {
            environment.librarySync.owner != nil && environment.library.loadState == .ready
        }
    }

    private func settled(_ environment: AppEnvironment, hadithId: String, content: String) async throws {
        try await wait("Actual owned server snapshot did not receive the private note") {
            guard let owner = environment.librarySync.owner,
                  let partition = try environment.guestData.syncPartition(owner) else { return false }
            return partition.pending.isEmpty && partition.frozen == nil && partition.acknowledgement == nil &&
                partition.savedSnapshot?.items.contains(where: { $0.hadithId == hadithId && $0.noteContent == content }) == true
        }
    }

    func testDevelopmentCrossDeviceLibraryPhase() async throws {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("a2-live-config.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("Opt-in A2 live development verification") }
        let config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url))
        guard config.expiresAt > Date.now.timeIntervalSince1970, config.phase.hasPrefix("ios-") else { throw XCTSkip("No current iOS live phase") }
        try await wait("Clerk did not load") { Clerk.shared.isLoaded }
        let environment = try XCTUnwrap(AppEnvironment.activeForStoreVerification)
        guard ["festive-cobra-664.convex.cloud", "festive-cobra-664.eu-west-1.convex.cloud"].contains(URL(string: environment.config.convexURL)?.host ?? ""),
              environment.config.clerkPublishableKey.hasPrefix("pk_test_") else { throw NSError(domain: "A2Live", code: 6) }
        let secondAccountPhase = config.phase == "ios-second-account"
        if !secondAccountPhase, Clerk.shared.user?.primaryEmailAddress?.emailAddress == config.secondEmail {
            try await Clerk.shared.auth.signOut(); environment.handleSignOut()
        }
        try await authenticate(email: secondAccountPhase ? config.secondEmail : config.email, password: secondAccountPhase ? config.secondPassword : config.password, create: config.phase == "ios-write")
        try await activate(environment)
        let model = environment.library
        let ref = HadithRef(hadithId: config.hadithId, collectionSlug: "bukhari", collectionName: config.collectionName,
                            volumeId: config.volumeId, hadithNumber: config.providerHadithId, arabicText: "", englishText: nil, referenceDisplay: config.referenceDisplay)
        if config.phase == "ios-write" {
            XCTAssertFalse(model.isBookmarked(hadithId: ref.hadithId))
            XCTAssertTrue(model.toggleBookmark(ref)); XCTAssertTrue(model.toggleFavorite(ref))
            XCTAssertTrue(model.saveNote(ref, content: "A2 iOS " + config.runId))
            model.createFolder(name: "A2 study " + config.runId, scope: model.actionScope)
            try await wait("New test folder did not appear") { model.folders.contains { $0.name == "A2 study " + config.runId } }
            let folder = try XCTUnwrap(model.folders.first { $0.name == "A2 study " + config.runId })
            model.assignFolder(hadithId: ref.hadithId, folderId: folder.id, scope: model.actionScope)
            let position = try XCTUnwrap(ReadingPosition.legacy(collectionSlug: "bukhari", providerHadithId: config.providerHadithId, volumeId: config.volumeId, updatedAt: Date.now.timeIntervalSince1970 * 1000))
            model.saveProgress(position, ref: ref)
            try await settled(environment, hadithId: ref.hadithId, content: "A2 iOS " + config.runId)
            try await wait("Owned server membership and reading position did not arrive") {
                guard let owner = environment.librarySync.owner, let state = try environment.guestData.syncPartition(owner) else { return false }
                return state.savedSnapshot?.items.first(where: { $0.hadithId == ref.hadithId })?.folderId != nil && state.positionsSnapshot?.rows.isEmpty == false
            }
        } else if config.phase == "ios-read-and-signout" {
            try await settled(environment, hadithId: ref.hadithId, content: "A2 Android " + config.runId)
            try await wait("Android reading position did not reach iOS") {
                guard let owner = environment.librarySync.owner, let state = try environment.guestData.syncPartition(owner) else { return false }
                return state.positionsSnapshot?.rows.first?.position?.normalizedOffset == 0.5
            }
            if !model.isBookmarked(hadithId: ref.hadithId) {
                XCTAssertTrue(model.toggleBookmark(ref))
                try await settled(environment, hadithId: ref.hadithId, content: "A2 Android " + config.runId)
            }
            XCTAssertTrue(model.isBookmarked(hadithId: ref.hadithId)); XCTAssertTrue(model.isFavorite(hadithId: ref.hadithId))
            XCTAssertNotNil(model.savedItems.first { $0.hadithId == ref.hadithId }?.folderId)
            let scope = model.actionScope, created = try XCTUnwrap(model.bookmarks.first?.createdAt)
            XCTAssertTrue(model.removeBookmark(ref, scope: scope))
            try await wait("Bookmark removal did not reach the owned server snapshot") {
                guard let owner = environment.librarySync.owner, let state = try environment.guestData.syncPartition(owner) else { return false }
                return state.savedSnapshot?.items.first(where: { $0.hadithId == ref.hadithId })?.bookmarkCreatedAt == nil && state.pending.isEmpty && state.frozen == nil
            }
            try await Clerk.shared.auth.signOut(); environment.handleSignOut()
            model.restoreBookmark(ref, createdAt: created)
            model.assignFolder(hadithId: ref.hadithId, folderId: nil, scope: scope)
            UserDefaults.standard.set(scope.uuidString, forKey: "a2.live.previousScope")
            XCTAssertTrue(model.savedItems.isEmpty)
        } else if secondAccountPhase {
            let scope = try XCTUnwrap(UserDefaults.standard.string(forKey: "a2.live.previousScope").flatMap(UUID.init(uuidString:)))
            model.assignFolder(hadithId: ref.hadithId, folderId: nil, scope: scope)
            try await Task.sleep(for: .milliseconds(500))
            XCTAssertTrue(model.savedItems.isEmpty)
            let secondOwner = try XCTUnwrap(environment.librarySync.owner)
            let secondState = try XCTUnwrap(environment.guestData.syncPartition(secondOwner))
            XCTAssertTrue(secondState.pending.isEmpty); XCTAssertNil(secondState.frozen)
            XCTAssertTrue(secondState.savedSnapshot?.items.isEmpty == true)
            try await Clerk.shared.auth.signOut(); environment.handleSignOut()
            XCTAssertTrue(model.savedItems.isEmpty)
        } else { XCTFail("Unknown opt-in iOS phase") }
    }
}
