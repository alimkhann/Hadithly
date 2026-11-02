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

    func testAccountChangeRestartsPendingLastVolumeEdge() async throws {
        let reader = model()
        reader.seedForUITest(volumes: [OutlineVolume(volumeId: "1", title: "One", hadithCount: 5), OutlineVolume(volumeId: "2", title: "Two", hadithCount: 5)], selectedVolumeId: "1")
        var firstCalls = 0
        reader.pageFetchForUITest = { index, volume, _ in
            if volume == "2", index == 0 { firstCalls += 1; try await Task.sleep(for: .milliseconds(100)) }
            return self.reusePage(index)
        }
        reader.switchToVolume("2", edge: .last)
        for _ in 0..<100 where firstCalls == 0 { await Task.yield() }
        reader.clearRecentPositions(restartLoading: true)
        for _ in 0..<100 where reader.pageIndex != 4 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(reader.pageIndex, 4)
        XCTAssertEqual(reader.currentPageHadiths.first?.providerHadithId, "5")
        XCTAssertEqual(firstCalls, 2)
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
