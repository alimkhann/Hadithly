import ClerkConvex
import ConvexMobile
import XCTest
@testable import Hadithly

@MainActor
final class TranslationQ1Tests: XCTestCase {
    private func model() -> ReaderModel {
        ReaderModel(convex: ConvexClientWithAuth(deploymentUrl: "https://example.invalid", authProvider: ClerkConvexAuthProvider()),
            collectionSlug: "bukhari", collectionName: "Bukhari", language: "ru", isSignedIn: { false })
    }

    func testWarmedVolumeIsReusedForFirstEdge() async throws {
        let reader = model()
        let volumes = (1...2).map { OutlineVolume(volumeId: "\($0)", title: "Volume \($0)", hadithCount: 1) }
        reader.seedForUITest(volumes: volumes, selectedVolumeId: "1")
        var requests: [String] = []
        reader.pageFetchForUITest = { index, volume, target in
            requests.append("\(volume):\(index):\(target ?? "-")")
            return ReaderPageResult(items: [], page: 1, pageSize: 1, totalPages: 1,
                hasMore: false, contentVersion: "cv1:content-\(volume)", paginationVersion: 1, pageKey: "pg1:page-\(volume)")
        }
        let start = ContinuousClock.now
        reader.warmAdjacentVolumes()
        for _ in 0..<100 where requests.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(requests, ["2:0:-"])
        reader.switchToVolume("2", edge: .first)
        for _ in 0..<100 where reader.pages.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        print("Unit2 warmed edge elapsed: \(start.duration(to: .now)); reader page calls: \(requests)")
        XCTAssertFalse(reader.pages.isEmpty)
        XCTAssertEqual(requests.filter { $0 == "2:0:-" }.count, 1)
        reader.stop()
    }

    private func reusePage(_ index: Int, version: String = "cv1:fixture", pagination: Double = 1) -> ReaderPageResult {
        let source = ReaderR6Round3FixtureHadith.hadith57
        let number = String(index + 1)
        let hadith = ReaderHadith(_id: "reuse-" + number, provider: source.provider,
            canonicalId: "sunnah_now:bukhari:" + number, providerHadithId: number,
            collectionSlug: "bukhari", volumeId: "2", chapterId: nil, arabicText: source.arabicText,
            englishText: source.englishText, narrator: nil, referenceDisplay: "Bukhari " + number,
            collectionName: "Bukhari", chapterName: nil, authenticity: source.authenticity)
        return ReaderPageResult(items: [hadith], page: index + 1, pageSize: 1, totalPages: 5,
            hasMore: index < 4, contentVersion: version, paginationVersion: pagination, pageKey: "pg1:reuse-" + number)
    }

    func testPageStoreSharesEntryWarmAndTargetResolution() async throws {
        var requests: [ReaderPageContentStore.Request] = []
        let page = reusePage(3)
        let store = ReaderPageContentStore { request in requests.append(request); return page }
        _ = try await store.load(.init(collection: "bukhari", volume: "2", index: 0, target: "4"))
        store.beginReading()
        let ordinal = try await store.load(.init(collection: "bukhari", volume: "2", index: 3))
        let target = try await store.load(.init(collection: "bukhari", volume: "2", index: 0, target: "4"))
        XCTAssertEqual(ordinal.page, 4)
        XCTAssertEqual(target.page, 4)
        XCTAssertEqual(requests.count, 1)
        XCTAssertNil(store.peek(collection: "bukhari", volume: "2", index: 0), "A resolved target cannot alias the requested ordinal")
    }

    func testCachedTargetLoadsBeforeUnreachableProbeWithoutOrdinalAlias() async throws {
        let store = ReaderPageContentStore { request in self.reusePage(request.index) }
        _ = try await store.load(.init(collection: "bukhari", volume: "2", index: 3))
        XCTAssertNil(store.cachedRequest(.init(collection: "bukhari", volume: "2", index: 0)))
        XCTAssertNil(store.cachedRequest(.init(collection: "bukhari", volume: "2", index: 3, target: "1")))
        XCTAssertEqual(store.cachedRequest(.init(collection: "bukhari", volume: "2", index: 0, target: "4"))?.page, 4)
        let reader = ReaderModel(convex: ConvexClientWithAuth(deploymentUrl: "https://example.invalid", authProvider: ClerkConvexAuthProvider()),
            collectionSlug: "bukhari", collectionName: "Bukhari", language: "en", isSignedIn: { false }, pageStore: store)
        reader.seedForUITest(volumes: [OutlineVolume(volumeId: "2", title: "Two", hadithCount: 5)], selectedVolumeId: "2")
        reader.seedPagesForUITest([reusePage(0)])
        reader.offlineProbeBaseURL = URL(string: "http://127.0.0.1:1")
        reader.jumpToHadith(volumeId: "2", hadithNumber: "4")
        for _ in 0..<100 where reader.pageIndex != 3 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(reader.pageIndex, 3)
        XCTAssertEqual(reader.currentPageHadiths.first?.providerHadithId, "4")
        reader.stop()
    }

    func testPageStoreDeduplicatesWithoutSharingCallerCancellation() async throws {
        var release: CheckedContinuation<ReaderPageResult, Never>?
        var calls = 0
        let store = ReaderPageContentStore { _ in
            calls += 1
            return await withCheckedContinuation { release = $0 }
        }
        let request = ReaderPageContentStore.Request(collection: "bukhari", volume: "2", index: 0)
        let warm = Task { try await store.load(request) }
        for _ in 0..<100 where release == nil { await Task.yield() }
        let foreground = Task { try await store.load(request) }
        await Task.yield()
        warm.cancel()
        release?.resume(returning: reusePage(0))
        do { _ = try await warm.value; XCTFail("Canceled caller must not receive a page") } catch is CancellationError { }
        let result = try await foreground.value
        XCTAssertEqual(result.page, 1)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(store.inFlightPageCount, 0)
    }

    func testPageStoreBoundsContentAndRejectsLateClearedWork() async throws {
        var calls = 0
        let store = ReaderPageContentStore(capacity: 2) { request in calls += 1; return self.reusePage(request.index) }
        for index in 0..<3 { _ = try await store.load(.init(collection: "bukhari", volume: "2", index: index)) }
        XCTAssertEqual(store.retainedPageCount, 2)
        XCTAssertNil(store.peek(collection: "bukhari", volume: "2", index: 0))
        _ = try await store.load(.init(collection: "bukhari", volume: "2", index: 0))
        XCTAssertEqual(calls, 4)
        let oldVersion = store.contextVersion
        store.clear()
        do { _ = try await store.load(.init(collection: "bukhari", volume: "2", index: 0), expectedVersion: oldVersion); XCTFail("Cleared entry task must not fetch again") } catch is CancellationError { }
        XCTAssertEqual(calls, 4)
        var release: CheckedContinuation<ReaderPageResult, Never>?
        let delayed = ReaderPageContentStore { _ in await withCheckedContinuation { release = $0 } }
        let task = Task { try await delayed.load(.init(collection: "bukhari", volume: "2", index: 0)) }
        for _ in 0..<100 where release == nil { await Task.yield() }
        delayed.clear()
        release?.resume(returning: reusePage(0))
        do { _ = try await task.value; XCTFail("Cleared response must not publish") } catch is CancellationError { }
        XCTAssertEqual(delayed.retainedPageCount, 0)
    }

    func testNewerObservedPageWinsAcrossDifferentRequestAliases() async throws {
        var release: CheckedContinuation<ReaderPageResult, Never>?
        let store = ReaderPageContentStore { request in
            if request.target != nil { return await withCheckedContinuation { release = $0 } }
            return self.reusePage(0, version: "cv1:new")
        }
        let old = Task { try await store.load(.init(collection: "bukhari", volume: "2", index: 0, target: "1")) }
        for _ in 0..<100 where release == nil { await Task.yield() }
        _ = try await store.load(.init(collection: "bukhari", volume: "2", index: 0))
        release?.resume(returning: reusePage(0, version: "cv1:old"))
        let observed = try await old.value
        XCTAssertEqual(observed.contentVersion, "cv1:new")
        XCTAssertEqual(store.peek(collection: "bukhari", volume: "2", index: 0)?.contentVersion, "cv1:new")
    }

    func testStorePaginationInvalidationRetryAndCoverageAfterEviction() async throws {
        var fail = true
        var pagination = 1.0
        var calls = 0
        let store = ReaderPageContentStore(capacity: 2) { request in
            calls += 1
            if fail { fail = false; throw OfflineFetchTimeout.timedOut }
            return self.reusePage(request.index, version: "cv1:page-\(request.index)", pagination: pagination)
        }
        let request = ReaderPageContentStore.Request(collection: "bukhari", volume: "2", index: 0)
        do { _ = try await store.load(request); XCTFail("First request must fail") } catch { }
        XCTAssertEqual(store.inFlightPageCount, 0)
        for index in 0..<5 { _ = try await store.load(.init(collection: "bukhari", volume: "2", index: index)) }
        XCTAssertEqual(calls, 6)
        XCTAssertEqual(store.retainedPageCount, 2)
        XCTAssertEqual(store.knownRange(collection: "bukhari", volume: "2")?.last, "5")
        pagination = 2
        _ = try await store.load(request)
        XCTAssertNil(store.peek(collection: "bukhari", volume: "2", index: 4))
        XCTAssertNil(store.knownRange(collection: "bukhari", volume: "2"))
        XCTAssertEqual(store.retainedPageCount, 1)
        let callsAtIdle = calls
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(calls, callsAtIdle)
        let offline = ReaderPageContentStore { _ in
            ReaderPageResult(items: [], page: 1, pageSize: 1, totalPages: 1, hasMore: false,
                contentVersion: "legacy", paginationVersion: 1, pageKey: "legacy")
        }
        _ = try await offline.load(request)
        XCTAssertEqual(offline.retainedPageCount, 0)
    }

    func testPendingTurnKeepsPageUntilSuccessAndAccountClearCancels() async throws {
        let reader = model()
        reader.seedForUITest(volumes: [OutlineVolume(volumeId: "1", title: "One", hadithCount: 5), OutlineVolume(volumeId: "2", title: "Two", hadithCount: 5)], selectedVolumeId: "1")
        reader.seedPagesForUITest([reusePage(0)])
        var releases: [CheckedContinuation<ReaderPageResult, Never>] = []
        reader.pageFetchForUITest = { index, _, _ in
            await withCheckedContinuation { releases.append($0) }
        }
        reader.switchToVolume("2", edge: .first)
        for _ in 0..<100 where releases.isEmpty { await Task.yield() }
        XCTAssertEqual(reader.selectedVolumeId, "1")
        XCTAssertEqual(reader.pageIndex, 0)
        reader.clearRecentPositions(restartLoading: true)
        releases.removeFirst().resume(returning: reusePage(0))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(reader.selectedVolumeId, "1")
        XCTAssertNil(reader.pendingTurn)
        reader.switchToVolume("2", edge: .first)
        for _ in 0..<100 where releases.isEmpty { await Task.yield() }
        releases.removeFirst().resume(returning: reusePage(0))
        for _ in 0..<100 where reader.selectedVolumeId != "2" { await Task.yield() }
        XCTAssertEqual(reader.selectedVolumeId, "2")
        XCTAssertNil(reader.pendingTurn)
        reader.stop()
    }

    func testPendingTurnFailureRetryAndExplicitNavigationPriority() async throws {
        let reader = model()
        reader.seedForUITest(volumes: [OutlineVolume(volumeId: "1", title: "One", hadithCount: 5), OutlineVolume(volumeId: "2", title: "Two", hadithCount: 5)], selectedVolumeId: "1")
        reader.seedPagesForUITest([reusePage(0)])
        var fail = true
        reader.pageFetchForUITest = { index, _, _ in
            if fail { fail = false; throw OfflineFetchTimeout.timedOut }
            return self.reusePage(index)
        }
        reader.switchToVolume("2", edge: .last)
        for _ in 0..<100 where reader.pendingTurn?.status != .failed { await Task.yield() }
        XCTAssertEqual(reader.pendingTurn?.status, .failed)
        XCTAssertEqual(reader.selectedVolumeId, "1")
        reader.retryPendingTurn()
        for _ in 0..<100 where reader.selectedVolumeId != "2" { await Task.yield() }
        XCTAssertEqual(reader.pageIndex, 4)
        reader.requestTurn(.page("2", 2))
        reader.selectVolume("2")
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(reader.pageIndex, 4)
        XCTAssertNil(reader.pendingTurn)
        reader.stop()
    }

    func testSupersededTurnCannotReplaceNewerTarget() async throws {
        let reader = model()
        reader.seedForUITest(volumes: [OutlineVolume(volumeId: "1", title: "One", hadithCount: 5), OutlineVolume(volumeId: "2", title: "Two", hadithCount: 5)], selectedVolumeId: "1")
        reader.seedPagesForUITest([reusePage(0)])
        var releases: [Int: CheckedContinuation<ReaderPageResult, Never>] = [:]
        reader.pageFetchForUITest = { index, _, _ in await withCheckedContinuation { releases[index] = $0 } }
        reader.requestTurn(.page("1", 1))
        for _ in 0..<100 where releases[1] == nil { await Task.yield() }
        reader.requestTurn(.page("1", 2))
        for _ in 0..<100 where releases[2] == nil { await Task.yield() }
        releases.removeValue(forKey: 2)?.resume(returning: reusePage(2))
        for _ in 0..<100 where reader.pageIndex != 2 { await Task.yield() }
        releases.removeValue(forKey: 1)?.resume(returning: reusePage(1))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(reader.pageIndex, 2)
        XCTAssertNil(reader.pendingTurn)
        reader.stop()
    }

    func testCachedVolumeEdgeContextCommitsExactPreview() async throws {
        let store = ReaderPageContentStore { request in self.reusePage(request.index) }
        _ = try await store.load(.init(collection: "bukhari", volume: "2", index: 0))
        _ = try await store.load(.init(collection: "bukhari", volume: "2", index: 4))
        let reader = ReaderModel(convex: ConvexClientWithAuth(deploymentUrl: "https://example.invalid", authProvider: ClerkConvexAuthProvider()),
            collectionSlug: "bukhari", collectionName: "Bukhari", language: "en", isSignedIn: { false }, pageStore: store)
        reader.seedForUITest(volumes: [OutlineVolume(volumeId: "1", title: "One", hadithCount: 5), OutlineVolume(volumeId: "2", title: "Two", hadithCount: 5)], selectedVolumeId: "1")
        let source = reusePage(0)
        reader.seedPagesForUITest([ReaderPageResult(items: source.items, page: 1, pageSize: source.pageSize,
            totalPages: 1, hasMore: false, contentVersion: source.contentVersion,
            paginationVersion: source.paginationVersion, pageKey: source.pageKey)])
        let preview = try XCTUnwrap(reader.renderedNeighbor(.next))
        XCTAssertEqual(preview.volume.title, "Two")
        XCTAssertEqual(preview.index, 0)
        XCTAssertEqual(preview.landing?.page.volumeId, "2")
        XCTAssertEqual(reader.selectedVolumeId, "1")
        XCTAssertNil(preview.range)
        for index in 1...3 { _ = try await store.load(.init(collection: "bukhari", volume: "2", index: index)) }
        XCTAssertNotNil(store.knownRange(collection: "bukhari", volume: "2"))
        XCTAssertTrue(reader.commitRenderedPage(preview))
        XCTAssertEqual(reader.selectedVolumeId, "2")
        XCTAssertEqual(reader.renderedCurrentPage()?.id, preview.id)
        XCTAssertNil(reader.renderedCurrentPage()?.range, "A metadata update during the drag must not change the prepared header at handoff")
        let old = try XCTUnwrap(reader.renderedPage(volumeId: "1", index: 0, payload: reusePage(0)))
        reader.clearRecentPositions()
        XCTAssertFalse(reader.commitRenderedPage(old))
        reader.stop()
    }

    func testPreparedCrossVolumeRoundTripRebasesCommittedOrigin() async throws {
        let page = reusePage(0)
        let single = ReaderPageResult(items: page.items, page: 1, pageSize: page.pageSize,
            totalPages: 1, hasMore: false, contentVersion: page.contentVersion,
            paginationVersion: page.paginationVersion, pageKey: page.pageKey)
        let store = ReaderPageContentStore { _ in single }
        for volume in ["1", "2"] {
            _ = try await store.load(.init(collection: "bukhari", volume: volume, index: 0))
        }
        let reader = ReaderModel(convex: ConvexClientWithAuth(deploymentUrl: "https://example.invalid", authProvider: ClerkConvexAuthProvider()),
            collectionSlug: "bukhari", collectionName: "Bukhari", language: "en", isSignedIn: { false }, pageStore: store)
        reader.seedForUITest(volumes: [OutlineVolume(volumeId: "1", title: "One", hadithCount: 1), OutlineVolume(volumeId: "2", title: "Two", hadithCount: 1)], selectedVolumeId: "1")
        reader.seedPagesForUITest([single])
        let forward = try XCTUnwrap(reader.renderedNeighbor(.next))
        XCTAssertTrue(reader.commitRenderedPage(forward))
        let origin = try XCTUnwrap(reader.renderedCurrentPage())
        XCTAssertEqual(origin.id, forward.id)
        XCTAssertEqual(origin.generation, reader.pageGeneration)
        XCTAssertTrue(reader.isCommitted(origin))
        let backward = try XCTUnwrap(reader.renderedNeighbor(.previous))
        XCTAssertTrue(reader.commitRenderedPage(backward))
        XCTAssertEqual(reader.selectedVolumeId, "1")
        XCTAssertEqual(reader.renderedCurrentPage()?.generation, reader.pageGeneration)
        reader.stop()
    }

    func testCachedPreviousVolumePreviewUsesLastPage() async throws {
        let store = ReaderPageContentStore { request in self.reusePage(request.index) }
        _ = try await store.load(.init(collection: "bukhari", volume: "1", index: 4))
        let reader = ReaderModel(convex: ConvexClientWithAuth(deploymentUrl: "https://example.invalid", authProvider: ClerkConvexAuthProvider()),
            collectionSlug: "bukhari", collectionName: "Bukhari", language: "en", isSignedIn: { false }, pageStore: store)
        reader.seedForUITest(volumes: [OutlineVolume(volumeId: "1", title: "One", hadithCount: 5), OutlineVolume(volumeId: "2", title: "Two", hadithCount: 5)], selectedVolumeId: "2")
        reader.seedPagesForUITest([reusePage(0)])
        let preview = try XCTUnwrap(reader.renderedNeighbor(.previous))
        XCTAssertEqual(preview.volume.title, "One")
        XCTAssertEqual(preview.index, 4)
        XCTAssertTrue(reader.commitRenderedPage(preview))
        XCTAssertEqual(reader.pageIndex, 4)
        XCTAssertEqual(reader.renderedCurrentPage()?.id, preview.id)
        reader.stop()
    }

    func testPreparedPageCarriesRecentLandingThroughCommit() throws {
        let reader = model()
        reader.seedForUITest(volumes: [OutlineVolume(volumeId: "2", title: "Two", hadithCount: 5)], selectedVolumeId: "2")
        let first = reusePage(0)
        reader.seedPagesForUITest([first, reusePage(1)])
        reader.captureStableScroll(hadiths: first.items, leadingIndex: 0, rawPageOffset: 100, normalizedOffset: 0.4)
        reader.pageIndex = 1
        let preview = try XCTUnwrap(reader.renderedNeighbor(.previous))
        XCTAssertEqual(preview.landing?.landing, .semantic(providerHadithId: "1", normalizedOffset: 0.4))
        XCTAssertTrue(reader.commitRenderedPage(preview))
        XCTAssertEqual(reader.verticalLanding, preview.landing)
        reader.stop()
    }

    func testOneVersusTwoLookaheadExperiment() async throws {
        for journey in [[0, 1, 2, 3, 4], [0, 1, 2, 1, 0], [3, 4, 3, 2, 3]] {
            for distance in 1...2 {
                var calls: [Int] = []
                var used = Set<Int>()
                var demandWait = 0.0
                let store = ReaderPageContentStore { request in
                    calls.append(request.index)
                    try await Task.sleep(for: .milliseconds(25))
                    return self.reusePage(request.index)
                }
                _ = try await store.load(.init(collection: "bukhari", volume: "2", index: journey[0]))
                for index in journey {
                    let start = ContinuousClock.now
                    _ = try await store.load(.init(collection: "bukhari", volume: "2", index: index))
                    demandWait += Double(start.duration(to: .now).components.attoseconds) / 1e15
                    used.insert(index)
                    for next in (index + 1)...(index + distance) where next < 5 {
                        _ = try await store.load(.init(collection: "bukhari", volume: "2", index: next))
                    }
                }
                let unused = Set(calls).subtracting(used).count
                print("UNIT2_LOOKAHEAD journey=\(journey) distance=\(distance) calls=\(calls.count) unused=\(unused) retainedPages=\(store.retainedPageCount) demandWaitMs=\(demandWait)")
                XCTAssertEqual(calls.count, Set(calls).count)
            }
        }
    }

    func testReturningLastEdgeUsesCachedTailWithoutFirstPageRequest() async throws {
        let store = ReaderPageContentStore(capacity: 2) { request in self.reusePage(request.index) }
        _ = try await store.load(.init(collection: "bukhari", volume: "2", index: 4))
        let reader = ReaderModel(convex: ConvexClientWithAuth(deploymentUrl: "https://example.invalid", authProvider: ClerkConvexAuthProvider()),
            collectionSlug: "bukhari", collectionName: "Bukhari", language: "en", isSignedIn: { false }, pageStore: store)
        reader.seedForUITest(volumes: [OutlineVolume(volumeId: "1", title: "One", hadithCount: 5), OutlineVolume(volumeId: "2", title: "Two", hadithCount: 5)], selectedVolumeId: "1")
        var calls = [String]()
        reader.pageFetchForUITest = { index, volume, _ in calls.append(volume); return self.reusePage(index) }
        reader.switchToVolume("2", edge: .last)
        for _ in 0..<100 where reader.pageIndex != 4 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(reader.pageIndex, 4)
        XCTAssertFalse(calls.contains("2"), "A retained last page must not fetch an evicted first page just to learn the count")
        reader.stop()
    }

    func testPendingTurnUsesResolvedOrdinalAndShrunkenPageCount() async throws {
        let reader = model()
        reader.seedForUITest(volumes: [OutlineVolume(volumeId: "2", title: "Two", hadithCount: 5)], selectedVolumeId: "2")
        reader.seedPagesForUITest([reusePage(0), reusePage(1), reusePage(2)])
        reader.pageFetchForUITest = { _, _, _ in
            ReaderPageResult(items: self.reusePage(0).items, page: 1, pageSize: 1, totalPages: 1, hasMore: false,
                contentVersion: "cv1:shrunk", paginationVersion: 2, pageKey: "pg2:shrunk")
        }
        reader.requestTurn(.page("2", 3))
        for _ in 0..<100 where reader.pendingTurn != nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(reader.pageIndex, 0)
        XCTAssertEqual(reader.pages.count, 1)
        XCTAssertEqual(reader.pages.first?.contentVersion, "cv1:shrunk")
        XCTAssertFalse(reader.hasNextPage)
        reader.stop()
    }

    func testAccountChangeReplaysOrdinaryExplicitPageLoad() async throws {
        let reader = model()
        reader.seedForUITest(volumes: [OutlineVolume(volumeId: "1", title: "One", hadithCount: 5), OutlineVolume(volumeId: "2", title: "Two", hadithCount: 5)], selectedVolumeId: "1")
        var firstCalls = 0
        reader.pageFetchForUITest = { index, volume, _ in
            if volume == "2", index == 0 { firstCalls += 1; try await Task.sleep(for: .milliseconds(100)) }
            return self.reusePage(index)
        }
        reader.selectVolume("2")
        for _ in 0..<100 where firstCalls == 0 { await Task.yield() }
        reader.clearRecentPositions(restartLoading: true)
        for _ in 0..<100 where reader.currentPageHadiths.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(reader.selectedVolumeId, "2")
        XCTAssertEqual(reader.currentPageHadiths.first?.providerHadithId, "1")
        XCTAssertEqual(firstCalls, 2)
        reader.stop()
    }

    func testLanguageChangeErasesRequestedAllowanceAndQuotaState() {
        let model = model()
        model.seedQ1TranslationForUITest(id: "sunnah_now:bukhari:1", state: .failed(.quotaExceeded),
            allowance: TranslationAllowance(limit: 5, remaining: 0, retryAt: 1000))
        model.setLanguage("ur")
        XCTAssertTrue(model.translationAllowances.isEmpty)
        XCTAssertTrue(model.translations.isEmpty)
        XCTAssertFalse(model.hasQuotaFailure)
    }

    func testAccountChangeErasesPrivateAllowanceAndRejection() {
        let model = model()
        model.seedQ1TranslationForUITest(id: "sunnah_now:bukhari:1", state: .failed(.quotaExceeded),
            allowance: TranslationAllowance(limit: 5, remaining: 0, retryAt: 1000))
        model.resetTranslationRequestsForAccount()
        XCTAssertTrue(model.translationAllowances.isEmpty)
        XCTAssertFalse(model.hasQuotaFailure)
    }

    func testOnlyQuotaErrorMapsToPaywallAndRateErrorPreservesRetryTime() {
        XCTAssertEqual(TranslationFailure(message: "AI_GENERATION_QUOTA_EXCEEDED"), .quotaExceeded)
        for code in ["AI_RATE_LIMITED", "AI_GENERATION_BUSY", "AI_INTEGRITY_REJECTED", "AI_SERVICE_LIMIT", "AI_GENERATION_RETRY"] {
            let failure = TranslationFailure(message: "{\"code\":\"\(code)\",\"retryAt\":1800000000000}")
            XCTAssertNotEqual(failure, .quotaExceeded)
            XCTAssertEqual(failure.retryAt, 1_800_000_000_000)
        }
    }
}
