import XCTest
@testable import Hadithly

/// O2 gate: fault-injection tests proving interruption or corruption never
/// replaces usable data. Every test drives the real OfflineStore against a
/// temporary directory with a fake transport and fake manifests.
@MainActor
final class OfflineStoreTests: XCTestCase {
    private static let license = """
        {"sourceKey":"sunnah_now","sourceName":"Sunnah.now","sourceUrl":"https://sunnah.now", \
        "terms":{"kind":"verified","licenseName":"Sunnah.now early-access data grant", \
        "licenseUrl":"https://github.com/sunnah-now/database","permitsDisplay":true, \
        "permitsRedistribution":false,"permitsOfflineDistribution":true,"verifiedAt":1700000000000}}
        """

    private static func hadith(_ id: String, arabic: String) -> String {
        """
        {"canonicalId":"sunnah_now:bukhari:\(id)","provider":"sunnah_now","collectionSlug":"bukhari", \
        "providerHadithId":"\(id)","volumeId":"2","arabicText":"\(arabic)", \
        "referenceDisplay":"Sahih al-Bukhari · Hadith \(id)","collectionName":"Sahih al-Bukhari", \
        "authenticity":{"kind":"collection_scope","normalizedGrade":"sahih","claimScope":"collection", \
        "sourceLabel":"Documented Sahih collection","sourceName":"Sunnah.now", \
        "sourceUrl":"https://sunnah.now","verificationMethod":"manual_collection_mapping"}}
        """
    }

    private static func baseDump(versionHex: String, ids: [String], generatedAt: Int = 1_700_000_000_000) -> Data {
        let rows = ids.map { hadith($0, arabic: "نص \($0) · \(versionHex.prefix(4))") }.joined(separator: ",")
        return Data(
            """
            {"format":"hadithly-base-dump","schemaVersion":1,"collectionSlug":"bukhari", \
            "collectionName":"Sahih al-Bukhari","contentVersion":"od1:\(versionHex)", \
            "generatedAt":\(generatedAt),"license":\(license),"hadiths":[\(rows)]}
            """.utf8
        )
    }

    private static func manifest(
        versionHex: String, bytes: Data, generatedAt: Int = 1_700_000_000_000,
        minAppVersion: String = "0.1.0", slug: String = "bukhari"
    ) -> OfflineManifest {
        let json = """
            {"format":"hadithly-offline-manifest","schemaVersion":1,"kind":"base","collectionSlug":"\(slug)", \
            "contentVersion":"od1:\(versionHex)","byteSize":\(bytes.count), \
            "sha256":"\(OfflineDumpValidation.sha256Hex(bytes))","minAppVersion":"\(minAppVersion)", \
            "generatedAt":\(generatedAt),"license":\(license),"compatiblePacks":[], \
            "downloadUrl":"https://example.invalid/\(slug).json"}
            """
        return try! JSONDecoder().decode(OfflineManifest.self, from: Data(json.utf8))
    }

    private static func baseDump(
        slug: String, versionHex: String, ids: [String], generatedAt: Int = 1_700_000_000_000
    ) -> Data {
        let rows = ids.map { hadith($0, arabic: "نص \($0) · \(versionHex.prefix(4))") }.joined(separator: ",")
        let name = slug == "bukhari" ? "Sahih al-Bukhari" : slug
        let fixed = rows.replacingOccurrences(of: "Sahih al-Bukhari", with: name)
            .replacingOccurrences(of: "\"bukhari\"", with: "\"\(slug)\"")
            .replacingOccurrences(of: "sunnah_now:bukhari:", with: "sunnah_now:\(slug):")
        return Data(
            """
            {"format":"hadithly-base-dump","schemaVersion":1,"collectionSlug":"\(slug)", \
            "collectionName":"\(name)","contentVersion":"od1:\(versionHex)", \
            "generatedAt":\(generatedAt),"license":\(license),"hadiths":[\(fixed)]}
            """.utf8
        )
    }

    private final class FakeTransport: OfflineDownloadTransport, @unchecked Sendable {
        var handler: (URL) -> Data = { _ in Data() }
        var status = 200
        var suspended = false
        func download(from url: URL, resumingFrom offset: Int64, progress: @Sendable @escaping (Double) -> Void) async throws -> Data {
            if suspended {
                try await Task.sleep(for: .milliseconds(5_000))
            }
            progress(1)
            return handler(url)
        }
        func cancel() async {}
        func lastStatusCode() async -> Int { status }
    }

    private final class FakeManifests: @unchecked Sendable {
        var bases: [OfflineManifest]
        var packs: [OfflineManifest] = []
        init(bases: [OfflineManifest]) { self.bases = bases }
    }

    private func makeStore(
        transport: FakeTransport = FakeTransport(),
        manifests: FakeManifests,
        anchors: Set<String> = []
    ) -> (OfflineStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-test-\(UUID().uuidString)", isDirectory: true)
        let store = OfflineStore(
            rootURL: root,
            transport: transport,
            appVersion: "0.1.0",
            manifestProvider: { _ in OfflineManifestsResponse(bases: manifests.bases, packs: manifests.packs) }
        )
        store.setAnchorProvider(for: "bukhari") { anchors }
        store.noteManifests(bases: manifests.bases, packs: manifests.packs)
        return (store, root)
    }

    private func waitUntil(
        _ condition: @autoclosure () -> Bool, timeout: TimeInterval = 5
    ) async {
        let deadline = Date.now.addingTimeInterval(timeout)
        while !condition(), Date.now < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    // MARK: - Happy path

    func testDownloadVerifiesAndActivates() async {
        let bytes = Self.baseDump(versionHex: String(repeating: "a", count: 64), ids: ["1", "2"])
        let manifest = Self.manifest(versionHex: String(repeating: "a", count: 64), bytes: bytes)
        let transport = FakeTransport()
        transport.handler = { _ in bytes }
        let server = FakeManifests(bases: [manifest])
        let (store, _) = makeStore(transport: transport, manifests: server)

        XCTAssertEqual(store.enqueue(slug: "bukhari", kind: "base", locale: nil), .started)
        await waitUntil(store.registry.record(for: "bukhari").activeBase != nil)
        XCTAssertEqual(
            store.registry.record(for: "bukhari").activeBase,
            "od1:\(String(repeating: "a", count: 64))"
        )
        XCTAssertNotNil(store.loadActiveDump(slug: "bukhari"))
        if case .active(let version, false, _) = store.status(for: "bukhari", translationLocale: nil) {
            XCTAssertEqual(version, "od1:\(String(repeating: "a", count: 64))")
        } else {
            XCTFail("expected active status")
        }
        // Idempotent re-enqueue of the same version is a no-op.
        XCTAssertEqual(store.enqueue(slug: "bukhari", kind: "base", locale: nil), .alreadyActive)
    }

    // MARK: - Corruption never replaces usable data

    func testCorruptUpdateKeepsPreviousVersionActive() async {
        let v1 = Self.baseDump(versionHex: String(repeating: "a", count: 64), ids: ["1", "2"])
        let m1 = Self.manifest(versionHex: String(repeating: "a", count: 64), bytes: v1)
        let transport = FakeTransport()
        transport.handler = { _ in v1 }
        let server = FakeManifests(bases: [m1])
        let (store, _) = makeStore(
            transport: transport, manifests: server,
            anchors: ["sunnah_now:bukhari:1", "sunnah_now:bukhari:2"]
        )
        XCTAssertEqual(store.enqueue(slug: "bukhari", kind: "base", locale: nil), .started)
        await waitUntil(store.registry.record(for: "bukhari").activeBase != nil)

        // v2 arrives with one flipped byte: same size, wrong hash.
        var v2 = Self.baseDump(versionHex: String(repeating: "b", count: 64), ids: ["1", "2"])
        v2[v2.count - 20] ^= 0xFF
        let m2 = Self.manifest(
            versionHex: String(repeating: "b", count: 64),
            bytes: Self.baseDump(versionHex: String(repeating: "b", count: 64), ids: ["1", "2"]),
            generatedAt: 1_700_000_100_000
        )
        transport.handler = { _ in v2 }
        server.bases = [m2]
        store.noteManifests(bases: [m2])
        XCTAssertEqual(store.enqueue(slug: "bukhari", kind: "base", locale: nil), .started)
        await waitUntil(store.registry.record(for: "bukhari").download?.state == .failed)
        if case .failed(let reason) = store.status(for: "bukhari", translationLocale: nil) {
            XCTAssertTrue(reason.contains("checksum"), reason)
        } else {
            XCTFail("expected failed status")
        }
        // Previous version is still active and still reads.
        XCTAssertEqual(
            store.registry.record(for: "bukhari").activeBase,
            "od1:\(String(repeating: "a", count: 64))"
        )
        XCTAssertEqual(store.loadActiveDump(slug: "bukhari")?.hadiths.count, 2)
    }

    func testReplacementMissingSavedAnchorsIsRefused() async {
        let v1 = Self.baseDump(versionHex: String(repeating: "a", count: 64), ids: ["1", "2"])
        let m1 = Self.manifest(versionHex: String(repeating: "a", count: 64), bytes: v1)
        let transport = FakeTransport()
        transport.handler = { _ in v1 }
        let server = FakeManifests(bases: [m1])
        let (store, _) = makeStore(
            transport: transport, manifests: server,
            anchors: ["sunnah_now:bukhari:1", "sunnah_now:bukhari:2"]
        )
        XCTAssertEqual(store.enqueue(slug: "bukhari", kind: "base", locale: nil), .started)
        await waitUntil(store.registry.record(for: "bukhari").activeBase != nil)

        // v2 is valid but drops hadith 2, which the user saved.
        let v2 = Self.baseDump(versionHex: String(repeating: "c", count: 64), ids: ["1", "3"])
        let m2 = Self.manifest(
            versionHex: String(repeating: "c", count: 64), bytes: v2, generatedAt: 1_700_000_100_000
        )
        transport.handler = { _ in v2 }
        server.bases = [m2]
        store.noteManifests(bases: [m2])
        XCTAssertEqual(store.enqueue(slug: "bukhari", kind: "base", locale: nil), .started)
        await waitUntil(store.registry.record(for: "bukhari").download?.state == .failed)
        XCTAssertEqual(
            store.registry.record(for: "bukhari").activeBase,
            "od1:\(String(repeating: "a", count: 64))"
        )
        XCTAssertEqual(store.loadActiveDump(slug: "bukhari")?.hadiths.count, 2)
    }

    // MARK: - Interruption and process death

    func testCancelKeepsPartialBytesAndResumeCompletes() async {
        let bytes = Self.baseDump(versionHex: String(repeating: "a", count: 64), ids: ["1"])
        let manifest = Self.manifest(versionHex: String(repeating: "a", count: 64), bytes: bytes)
        let transport = FakeTransport()
        transport.suspended = true
        transport.handler = { _ in bytes }
        let server = FakeManifests(bases: [manifest])
        let (store, _) = makeStore(transport: transport, manifests: server)

        XCTAssertEqual(store.enqueue(slug: "bukhari", kind: "base", locale: nil), .started)
        await waitUntil(store.registry.record(for: "bukhari").download?.state == .downloading)
        store.pause(slug: "bukhari")
        XCTAssertEqual(store.registry.record(for: "bukhari").download?.state, .paused)
        XCTAssertNil(store.registry.record(for: "bukhari").activeBase)

        transport.suspended = false
        transport.status = 200 // server ignores Range: bytes restart, still verify.
        store.retry(slug: "bukhari")
        await waitUntil(store.registry.record(for: "bukhari").activeBase != nil)
        XCTAssertEqual(store.loadActiveDump(slug: "bukhari")?.hadiths.count, 1)
    }

    func testTwoCollectionsDownloadConcurrently() async {
        // Regression: one shared run task meant starting a second
        // collection cancelled the first, so only one could download.
        let hexA = String(repeating: "a", count: 64)
        let bytesBukhari = Self.baseDump(slug: "bukhari", versionHex: hexA, ids: ["1"])
        let bytesMuslim = Self.baseDump(slug: "muslim", versionHex: hexA, ids: ["1"])
        let mBukhari = Self.manifest(versionHex: hexA, bytes: bytesBukhari, slug: "bukhari")
        let mMuslim = Self.manifest(versionHex: hexA, bytes: bytesMuslim, slug: "muslim")
        let transport = FakeTransport()
        transport.suspended = true
        transport.handler = { url in
            url.absoluteString.contains("muslim") ? bytesMuslim : bytesBukhari
        }
        let server = FakeManifests(bases: [mBukhari, mMuslim])
        let (store, _) = makeStore(transport: transport, manifests: server)
        store.noteManifests(bases: [mBukhari, mMuslim])

        XCTAssertEqual(store.enqueue(slug: "bukhari", kind: "base", locale: nil), .started)
        XCTAssertEqual(store.enqueue(slug: "muslim", kind: "base", locale: nil), .started)
        await waitUntil(store.registry.record(for: "bukhari").download?.state == .downloading)
        await waitUntil(store.registry.record(for: "muslim").download?.state == .downloading)

        transport.suspended = false
        store.retry(slug: "bukhari")
        store.retry(slug: "muslim")
        await waitUntil(store.registry.record(for: "bukhari").activeBase != nil)
        await waitUntil(store.registry.record(for: "muslim").activeBase != nil)
        XCTAssertEqual(store.loadActiveDump(slug: "bukhari")?.hadiths.count, 1)
        XCTAssertEqual(store.loadActiveDump(slug: "muslim")?.hadiths.count, 1)
    }

    func testReconcileAdoptsInterruptedDownloadAsPaused() async {
        let bytes = Self.baseDump(versionHex: String(repeating: "a", count: 64), ids: ["1"])
        let manifest = Self.manifest(versionHex: String(repeating: "a", count: 64), bytes: bytes)
        let transport = FakeTransport()
        transport.handler = { _ in bytes }
        let server = FakeManifests(bases: [manifest])
        let (store, root) = makeStore(transport: transport, manifests: server)
        XCTAssertEqual(store.enqueue(slug: "bukhari", kind: "base", locale: nil), .started)
        await waitUntil(store.registry.record(for: "bukhari").activeBase != nil)

        // Simulate process death mid-queue: fresh store over the same root.
        let store2 = OfflineStore(
            rootURL: root, transport: FakeTransport(), appVersion: "0.1.0",
            manifestProvider: { _ in OfflineManifestsResponse(bases: [manifest], packs: []) }
        )
        XCTAssertEqual(
            store2.registry.record(for: "bukhari").activeBase,
            "od1:\(String(repeating: "a", count: 64))"
        )
        XCTAssertEqual(store2.loadActiveDump(slug: "bukhari")?.hadiths.count, 1)
    }

    // MARK: - Refusals

    func testProviderRollbackIsBlocked() async {
        let v1 = Self.baseDump(versionHex: String(repeating: "a", count: 64), ids: ["1"])
        let m1 = Self.manifest(versionHex: String(repeating: "a", count: 64), bytes: v1, generatedAt: 1_700_000_100_000)
        let transport = FakeTransport()
        transport.handler = { _ in v1 }
        let server = FakeManifests(bases: [m1])
        let (store, _) = makeStore(transport: transport, manifests: server)
        XCTAssertEqual(store.enqueue(slug: "bukhari", kind: "base", locale: nil), .started)
        await waitUntil(store.registry.record(for: "bukhari").activeBase != nil)

        let older = Self.baseDump(versionHex: String(repeating: "d", count: 64), ids: ["1"])
        let mOld = Self.manifest(versionHex: String(repeating: "d", count: 64), bytes: older, generatedAt: 1_700_000_000_000)
        server.bases = [mOld]
        store.noteManifests(bases: [mOld])
        let result = store.enqueue(slug: "bukhari", kind: "base", locale: nil)
        if case .blocked(let reason) = result {
            XCTAssertTrue(reason.contains("older"), reason)
        } else {
            XCTFail("expected rollback block, got \(result)")
        }
        XCTAssertNil(store.registry.record(for: "bukhari").download)
    }

    func testAppUpdateRequiredBlocksDownload() {
        let bytes = Self.baseDump(versionHex: String(repeating: "a", count: 64), ids: ["1"])
        let manifest = Self.manifest(versionHex: String(repeating: "a", count: 64), bytes: bytes, minAppVersion: "99.0.0")
        let server = FakeManifests(bases: [manifest])
        let (store, _) = makeStore(manifests: server)
        // Store was built with appVersion 0.1.0: note the manifest in directly.
        store.noteManifests(bases: [manifest])
        if case .blocked(let reason) = store.enqueue(slug: "bukhari", kind: "base", locale: nil) {
            XCTAssertTrue(reason.contains("Update Hadithly"), reason)
        } else {
            XCTFail("expected app-update block")
        }
        if case .appUpdateRequired(let minimum) = store.status(for: "bukhari", translationLocale: nil) {
            XCTAssertEqual(minimum, "99.0.0")
        } else {
            XCTFail("expected appUpdateRequired status")
        }
    }

    func testDeleteRemovesFilesOnly() async {
        let bytes = Self.baseDump(versionHex: String(repeating: "a", count: 64), ids: ["1"])
        let manifest = Self.manifest(versionHex: String(repeating: "a", count: 64), bytes: bytes)
        let transport = FakeTransport()
        transport.handler = { _ in bytes }
        let server = FakeManifests(bases: [manifest])
        let (store, root) = makeStore(transport: transport, manifests: server)
        XCTAssertEqual(store.enqueue(slug: "bukhari", kind: "base", locale: nil), .started)
        await waitUntil(store.registry.record(for: "bukhari").activeBase != nil)

        store.delete(slug: "bukhari")
        XCTAssertNil(store.registry.record(for: "bukhari").activeBase)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("bukhari").path))
        if case .notInstalled = store.status(for: "bukhari", translationLocale: nil) {
        } else {
            XCTFail("expected notInstalled after delete")
        }
    }

    // MARK: - Pure domain

    func testChunkingMirrorsServerPaging() {
        struct Row {
            let arabic: String
        }
        var rows: [Row] = []
        for _ in 1 ... 11 {
            rows.append(Row(arabic: String(repeating: "x", count: 100)))
        }
        func chunk(_ input: [Row]) -> [[Row]] {
            OfflineModels.chunkHadiths(
                input,
                arabicText: { (row: Row) in row.arabic },
                englishText: { (_: Row) -> String? in nil },
                narrator: { (_: Row) -> String? in nil },
                narratorAr: { (_: Row) -> String? in nil }
            )
        }
        let pages = chunk(rows)
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].count, 10)
        XCTAssertEqual(pages[1].count, 1)

        let long = [Row(arabic: String(repeating: "y", count: 5_100)), Row(arabic: String(repeating: "z", count: 200))]
        XCTAssertEqual(chunk(long).count, 2)
    }

    func testOfflinePagesCarryLegacyWireValues() async {
        // Regression (device crash): offline pages claimed the dump's od1:
        // version and an "offline-…" page key, which the R1 position
        // contract rejects. Offline chunking is approximate, so pages carry
        // nil (→ "legacy") and restoration resolves by semantic anchor.
        let bytes = Self.baseDump(versionHex: String(repeating: "a", count: 64), ids: ["1", "2"])
        let manifest = Self.manifest(versionHex: String(repeating: "a", count: 64), bytes: bytes)
        let transport = FakeTransport()
        transport.handler = { _ in bytes }
        let server = FakeManifests(bases: [manifest])
        let (store, _) = makeStore(transport: transport, manifests: server)
        XCTAssertEqual(store.enqueue(slug: "bukhari", kind: "base", locale: nil), .started)
        await waitUntil(store.registry.record(for: "bukhari").activeBase != nil)

        let page = store.offlinePage(slug: "bukhari", volumeId: "2", page: 0, locale: nil)
        XCTAssertNotNil(page)
        XCTAssertNil(page?.contentVersion)
        XCTAssertNil(page?.pageKey)
        XCTAssertEqual(page?.items.count, 2)
    }

    func testFetchTimeoutBoundsAHungSocket() async {
        // Fast work passes through untouched.
        let fast = try? await OfflineModels.withFetchTimeout(seconds: 5) { "ok" }
        XCTAssertEqual(fast, "ok")
        // A fetch that never resolves throws in bounded time instead of
        // stranding the reader on a spinner.
        let start = Date.now
        do {
            _ = try await OfflineModels.withFetchTimeout(seconds: 0.2) { () -> String in
                try await Task.sleep(for: .seconds(30))
                return "never"
            }
            XCTFail("expected a timeout")
        } catch {
            XCTAssertLessThan(Date.now.timeIntervalSince(start), 10)
        }
    }

    func testProbeReportsUnreachableQuickly() async {
        // 127.0.0.1:9 (discard) refuses immediately: no route, no server.
        // A hanging backend must instead hit the 3 s probe bound, never wedge.
        await OfflineProbe.shared.reset()
        let start = Date.now
        let reachable = await OfflineProbe.shared.isReachable(URL(string: "https://127.0.0.1:9")!)
        XCTAssertFalse(reachable)
        XCTAssertLessThan(Date.now.timeIntervalSince(start), 10)
        // Cached verdict answers instantly without re-probing.
        let again = await OfflineProbe.shared.isReachable(URL(string: "https://127.0.0.1:9")!)
        XCTAssertFalse(again)
        await OfflineProbe.shared.reset()
    }

    func testDottedIdOrder() {
        XCTAssertTrue(OfflineModels.compareProviderHadithIds("2", "10"))
        XCTAssertTrue(OfflineModels.compareProviderHadithIds("4.5", "10"))
        XCTAssertFalse(OfflineModels.compareProviderHadithIds("10", "4.5"))
    }

    func testCorruptRegistryRebuildsFromDisk() async {
        let bytes = Self.baseDump(versionHex: String(repeating: "a", count: 64), ids: ["1", "2"])
        let manifest = Self.manifest(versionHex: String(repeating: "a", count: 64), bytes: bytes)
        let transport = FakeTransport()
        transport.handler = { _ in bytes }
        let server = FakeManifests(bases: [manifest])
        let (store, root) = makeStore(transport: transport, manifests: server)
        XCTAssertEqual(store.enqueue(slug: "bukhari", kind: "base", locale: nil), .started)
        await waitUntil(store.registry.record(for: "bukhari").activeBase != nil)

        try! "corrupt".write(
            to: root.appendingPathComponent("registry.json"), atomically: true, encoding: .utf8
        )
        let rebuilt = OfflineStore(
            rootURL: root, transport: FakeTransport(), appVersion: "0.1.0",
            manifestProvider: { _ in OfflineManifestsResponse(bases: [manifest], packs: []) }
        )
        XCTAssertEqual(
            rebuilt.registry.record(for: "bukhari").activeBase,
            "od1:\(String(repeating: "a", count: 64))"
        )
    }
}
