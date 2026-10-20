import XCTest
import Combine
import SwiftData
import SQLite3
@testable import Hadithly

final class GuestMergePlannerTests: XCTestCase {
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
        try store.markDeletionBackendComplete(subject: owner.subject, namespace: owner.namespace)
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.directory.path))
        XCTAssertThrowsError(try store.validateOutcomeExport(beforeErase))
    }

    @MainActor func testOutcomeExportMutationCancellationSwitchAndErasureDiscardPartialFiles() async throws {
        for mode in ["mutation", "cancel", "switch", "erase"] {
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
            case "cancel": task.cancel()
            case "switch": fixture.session.value = .init(id: "session-b", subject: "subject-b"); fixture.sync.deactivate()
            case "erase":
                try store.beginDeletion(subject: owner.subject, namespace: owner.namespace)
                try store.markDeletionBackendComplete(subject: owner.subject, namespace: owner.namespace)
            default: try await collectExportFacts(taggedOutcomeProof(owner, count: 1, tag: "insert-during-export"), owner: owner, count: 1, store: store)
            }
            do { _ = try await task.value; XCTFail("Changed/canceled export was published") } catch { }
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

    @MainActor func testOutcomeExportArtifactCleanupAndEmptyFenceNeverRecreateDeletedMetadata() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), owner = LibrarySyncOwner(key: "owner-a", subject: "subject-a")
        let store = GuestDataStore(inMemory: true, exportDirectory: root)
        try store.claimGuestForSync(owner)
        let empty = try await store.prepareOutcomeExport(owner, isCurrent: { true })
        XCTAssertEqual(empty.version, .empty)
        let artifact = try store.beginOutcomeExportArtifact(empty)
        try Data("abandoned".utf8).write(to: artifact.directory.appendingPathComponent("document.partial"))
        try store.clearAbandonedOutcomeExports()
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.directory.path))
        try store.beginDeletion(subject: owner.subject, namespace: owner.namespace)
        try store.markDeletionBackendComplete(subject: owner.subject, namespace: owner.namespace)
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
        try state.settle(.accepted(.init(committed: committed)), requested: frame, now: 2_000)
        XCTAssertTrue(LibraryProjection(state).folders.isEmpty)
        XCTAssertTrue(LibraryProjection(state).items.allSatisfy { $0.folderId == nil })
        state.savedSnapshot = .init(ownerKey: "owner-a", version: 2, folders: [.init(_id: "destination", name: "Folder", createdAt: 1)], items: [item(first, folder: "destination"), item(second, folder: nil)])
        let visible = LibraryProjection(state)
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
        try store.markDeletionBackendComplete(subject: owner.subject, namespace: owner.namespace)
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
            try reconciled.settle(.reconcile(.init(ownerKey: "owner-a", clientKey: frame.clientKey, requestedSequence: frame.sequence, requestedBatchId: frame.batch.id, cursor: cursor)), requested: frame, now: 2_000)
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
            try polled.settle(.pending(.init(ownerKey: "owner-a", pending: pending)), requested: frame, now: 2_000)
            let previousRecovery = polled.recovery
            try polled.settlePending(.accepted(.init(committed: committed)), requested: pending, now: 2_000)
            XCTAssertEqual(polled.recovery, previousRecovery); XCTAssertEqual(polled.recovery.count, 1)
            XCTAssertEqual(polled.collectingOutcome?.origin, .historical); XCTAssertNil(polled.acknowledgement)

            var acknowledged = original
            try acknowledged.settle(accepted(frame, reply: .init(ownerKey: "owner-a", batchId: frame.batch.id,
                receipts: [.init(id: operation.id, revision: operation.revision, outcome: .preserved)])), requested: frame, now: 2_000)
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
        try state.settle(accepted(frame, reply: reply), requested: frame, now: 2_000)
        XCTAssertEqual(state.frozen?.batch, frame.batch); XCTAssertEqual(state.nextSequence, 1); XCTAssertNil(state.acknowledgement)
        XCTAssertEqual(state.collectingOutcome?.origin, .matched(intentDigest: try frame.batch.intentDigest()))
        XCTAssertThrowsError(try state.freeze())
        XCTAssertEqual(try JSONDecoder().decode(LibraryPartitionState.self, from: JSONEncoder().encode(state)), state)
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
        try store.markDeletionBackendComplete(subject: replacement.subject, namespace: replacement.namespace)
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
        XCTAssertTrue(base.canPruneOutcome(binding, checkpoint: checkpoint, now: now))
        XCTAssertFalse(base.canPruneOutcome(binding, checkpoint: checkpoint, now: now - 1))
        XCTAssertFalse(base.canPruneOutcome(binding, checkpoint: checkpoint, now: 1_000))
        XCTAssertFalse(base.canPruneOutcome(binding, checkpoint: .init(counts: binding.expected, status: .complete), now: now))
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
        for state in states { XCTAssertFalse(state.canPruneOutcome(binding, checkpoint: checkpoint, now: now)) }
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
        try store.markDeletionBackendComplete(subject: owner.subject, namespace: owner.namespace)
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
                    cursor: .init(closedThrough: 0, outstanding: .committed(.init(committed: proof))))), requested: frame, now: 2_000)
            } else { try state.settle(.accepted(.init(committed: proof)), requested: frame, now: 2_000) }
            let pending = try XCTUnwrap(state.collectingOutcome), binding = try LibraryOutcomeBinding(owner: owner, committed: proof)
            var checkpoint = LibraryOutcomeCheckpoint(counts: binding.expected, status: .complete)
            if mode == "detail" || mode == "proof" { checkpoint = .init(counts: .init(restored: 50), status: .unavailable(mode == "detail" ? .detailUnavailable : .proofUnavailable)) }
            state.savedSnapshot = .init(ownerKey: owner.key, version: 1, folders: [], items: [])
            let before = state
            XCTAssertEqual(try state.settleCollectedOutcome(pending, binding: binding, checkpoint: checkpoint, now: 2_000), mode == "proof" ? .proofUnavailable : .awaitingSaved)
            XCTAssertEqual(state, before)
            state.savedSnapshot = .init(ownerKey: owner.key, version: 3, folders: [], items: [])
            if mode == "proof" {
                let blocked = state
                XCTAssertEqual(try state.settleCollectedOutcome(pending, binding: binding, checkpoint: checkpoint, now: 2_000), .proofUnavailable)
                XCTAssertEqual(state, blocked); continue
            }
            if mode == "delete" {
                var late = state
                XCTAssertEqual(try late.settleCollectedOutcome(pending, binding: binding, checkpoint: checkpoint, now: 7_000), .settled)
                XCTAssertTrue(late.recent.isEmpty)
            }
            if mode == "partial" {
                for status in [LibraryOutcomeStatus.collecting, .verifying(.init())] {
                    var unfinished = state; let unfinishedBefore = unfinished
                    XCTAssertEqual(try unfinished.settleCollectedOutcome(pending, binding: binding, checkpoint: .init(counts: binding.expected, status: status), now: 2_000), .collecting)
                    XCTAssertEqual(unfinished, unfinishedBefore)
                }
                var incomplete = state; let incompleteBefore = incomplete
                XCTAssertThrowsError(try incomplete.settleCollectedOutcome(pending, binding: binding, checkpoint: .init(status: .complete), now: 2_000)); XCTAssertEqual(incomplete, incompleteBefore)
                var missing = state; missing.frozen = nil; let missingBefore = missing
                XCTAssertThrowsError(try missing.settleCollectedOutcome(pending, binding: binding, checkpoint: checkpoint, now: 2_000)); XCTAssertEqual(missing, missingBefore)
                var wrongOwner = state; wrongOwner.savedSnapshot = .init(ownerKey: "owner-b", version: 3, folders: [], items: []); let wrongBefore = wrongOwner
                XCTAssertThrowsError(try wrongOwner.settleCollectedOutcome(pending, binding: binding, checkpoint: checkpoint, now: 2_000)); XCTAssertEqual(wrongOwner, wrongBefore)
                var fork = try JSONDecoder().decode(LibraryPartitionState.self, from: Data(String(decoding: JSONEncoder().encode(state), as: UTF8.self).replacingOccurrences(of: "Original folder", with: "Changed folder").utf8))
                let forkBefore = fork
                XCTAssertThrowsError(try fork.settleCollectedOutcome(pending, binding: binding, checkpoint: checkpoint, now: 2_000)); XCTAssertEqual(fork, forkBefore)
                var conflict = state; conflict.folderMappings["restore:deleted"] = "another-folder"; let conflictBefore = conflict
                XCTAssertThrowsError(try conflict.settleCollectedOutcome(pending, binding: binding, checkpoint: checkpoint, now: 2_000)); XCTAssertEqual(conflict, conflictBefore)
            }
            XCTAssertEqual(try state.settleCollectedOutcome(pending, binding: binding, checkpoint: checkpoint, now: 2_000), .settled)
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
            XCTAssertEqual(try state.settleCollectedOutcome(pending, binding: binding, checkpoint: checkpoint, now: 7_000), .settled)
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
            cursor: .init(closedThrough: 0, outstanding: .committed(.init(committed: bad))))), requested: frame, now: 2_000))
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
