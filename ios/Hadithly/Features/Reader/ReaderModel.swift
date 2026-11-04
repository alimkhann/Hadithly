import ClerkKit
import ConvexMobile
import Foundation
import Observation
import os

enum ReaderScrollProfile {
    static let enabled = ProcessInfo.processInfo.environment["HADITHLY_READER_PROFILE"] == "1"
    private static let log = OSLog(subsystem: "com.hadithly.app.reader", category: .pointsOfInterest)

    static func begin(_ name: StaticString) -> OSSignpostID? {
        guard enabled else { return nil }
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
    }

    static func beginAnimation(_ name: StaticString) -> OSSignpostID? {
        guard enabled else { return nil }
        let id = OSSignpostID(log: log)
        os_signpost(.animationBegin, log: log, name: name, signpostID: id)
        return id
    }

    static func end(_ name: StaticString, _ id: OSSignpostID?) {
        guard let id else { return }
        os_signpost(.end, log: log, name: name, signpostID: id)
    }
}

/// Drives the reader: loads the collection outline, pages hadiths by content
/// size through `actions/hadithData:getReaderPage`, prefetches forward, and
/// pulls AI translations for the chosen language through
/// `actions/ai:translateHadith` with graceful quota/sign-in handling.
/// Also owns the reader's personal-data side effects: bookmark/favorite/note
/// toggles and private reading-progress saves (Convex when signed in,
/// SwiftData for guests).
@MainActor
@Observable
final class ReaderModel {
    enum Phase: Equatable {
        case loadingOutline
        case reading
        case failed(String)
    }

    enum TranslationState {
        case loading
        case loaded(ReaderTranslation)
        case failed(TranslationFailure)
    }

    // Configuration
    let collectionSlug: String
    let collectionName: String
    private let convex: ConvexClientWithAuth<String>
    private let isSignedIn: () -> Bool
    private let library: UserLibraryModel?
    /// Volume to open first (continue-reading / saved-item deep links).
    private let openVolumeId: String?
    /// Hadith number to land on within that volume.
    private let openHadithNumber: String?
    private let openPosition: ReadingPosition?
    private let targetSource: ReaderTargetSource
    private let currentPreferences: () -> ReaderPreferences
    private let widthClass: ReadingWidthClass
    private let pageStore: ReaderPageContentStore
    /// O2 offline fallback. Set by the hosting view from AppEnvironment;
    /// nil in tests and previews that drive the model with fixtures.
    var automaticTranslationEnabled: () -> Bool = { false }
    private var automaticTranslationTask: Task<Void, Never>?
    private var automaticVisibleHadiths: [ReaderHadith] = []
    private var automaticRequests = ReaderAutomaticTranslationLedger()
#if DEBUG
    var navigationTraceForUITest: ((String) -> Void)?
    var pageFetchForUITest: ((Int, String, String?) async throws -> ReaderPageResult)?
    var automaticRequestForUITest: ((ReaderHadith) -> Void)?
#endif
    var offlineStore: OfflineStore?
    var analytics: UsageStatistics?
    private var measurement = ReaderMeasurement()
    private var usedOfflineForEntry = false
    func beginMeasurement() {
        emitMeasurement(measurement.begin(guest: !isSignedIn(), restoration: openPosition != nil, notification: targetSource == .notification))
    }
    private func emitMeasurement(_ facts: [AnalyticsMetric]) { for fact in facts { analytics?.record(fact) } }
    private func readable(_ hadith: ReaderHadith) -> Bool {
        let preferences = currentPreferences()
        if preferences.arabicVisible, !hadith.arabicText.isEmpty { return true }
        guard preferences.translationVisible else { return false }
        if case .loaded(let translation) = translations[hadith.internalId], !translation.translation.isEmpty { return true }
        return language == "en" && !(hadith.englishText ?? "").isEmpty
    }
    func observeVisibleContent(hadiths: [ReaderHadith], frames: [String: ReaderAnchorFrame], viewport: Double) {
        if verticalLanding == nil {
            let visible = hadiths.filter { hadith in
                guard let frame = frames[hadith.internalId] else { return false }
                return frame.minY < viewport && frame.minY + frame.height > 0
            }
            scheduleAutomaticTranslations(visible)
        }
        guard verticalLanding == nil, hadiths.contains(where: { hadith in
            guard let frame = frames[hadith.internalId] else { return false }
            return frame.minY < viewport && frame.minY + frame.height > 0 && readable(hadith)
        }) else { return }
        let wasRendered = measurement.rendered
        emitMeasurement(measurement.visible(offline: usedOfflineForEntry))
        if !wasRendered, measurement.rendered { analytics?.firstReaderSucceeded() }
    }
    private func invalidateAutomaticTranslationVisibility() {
        automaticTranslationTask?.cancel()
        automaticVisibleHadiths = []
    }

    private func scheduleAutomaticTranslations(_ visible: [ReaderHadith], force: Bool = false) {
        guard force || visible.map(\.internalId) != automaticVisibleHadiths.map(\.internalId) else { return }
        automaticVisibleHadiths = visible
        automaticTranslationTask?.cancel()
        let requestedLanguage = language
        automaticTranslationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, !Task.isCancelled, language == requestedLanguage,
                  automaticTranslationEnabled(), currentPreferences().translationVisible, isSignedIn() else { return }
            for hadith in visible {
                guard !hasQuotaFailure else { break }
                guard automaticRequests.claim(hadithId: hadith.internalId, locale: requestedLanguage,
                    hasTranslation: language == "en" && !(hadith.englishText ?? "").isEmpty,
                    hasRequestState: translations[hadith.internalId] != nil) else { continue }
#if DEBUG
                if let automaticRequestForUITest { automaticRequestForUITest(hadith); continue }
#endif
                retryTranslation(for: hadith)
            }
        }
    }

    func refreshAutomaticTranslationPreference() { scheduleAutomaticTranslations(automaticVisibleHadiths, force: true) }

    func inspectInitialTarget(hadiths: [ReaderHadith], frames: [String: ReaderAnchorFrame], viewport: Double) {
        let expected = openPosition?.anchor.providerHadithId ?? (targetSource == .notification ? openHadithNumber : nil)
        let desired = openPosition?.normalizedOffset ?? 0
        var exact = false
        if let hadith = hadiths.first(where: { $0.providerHadithId == expected }),
           let frame = (desired == 0 ? frames["chapter." + hadith.internalId] : nil) ?? frames[hadith.internalId] {
            exact = frame.minY < viewport && frame.minY + frame.height > 0 && abs(frame.minY + desired * frame.height) <= 8
        }
        emitMeasurement(measurement.settleTarget(exact: exact)); analytics?.flush()
    }
    func endMeasurement() { emitMeasurement(measurement.close()); analytics?.flush() }
    var offlineLocale: String?
    /// Base URL for the pool-independent reachability probe. When set, the
    /// reader checks it before issuing Convex calls so a stalled network
    /// serves the dump (or fails fast) instead of risking a wedged pool.
    var offlineProbeBaseURL: URL?

    // Reading state
    private(set) var phase: Phase = .loadingOutline {
        didSet { if case .failed = phase { emitMeasurement(measurement.failure()) } }
    }
    private(set) var volumes: [OutlineVolume] = []
    private(set) var pages: [ReaderPageResult] = []
    private(set) var selectedVolumeId: String? {
        didSet { if oldValue != selectedVolumeId { endViewportInteractions() } }
    }
    private(set) var isLoadingPage = false
    var pageIndex = 0 {
        didSet {
            guard oldValue != pageIndex else { return }
            retainedRenderedContext = nil
            endViewportInteractions()
            invalidateAutomaticTranslationVisibility()
            restoreCachedNeighbors()
            requestRecentLanding(for: pageIndex)
            trimPageSlots()
            collapseToFocused()
            lastCapturedAnchor = nil
            lastCapturedNormalizedOffset = nil
            prefetchForwardIfNeeded()
            loadCurrentPageIfNeeded()
            scheduleTranslationsForCurrentPage()
            saveCurrentProgress()
        }
    }

    // Chrome & sheets
    var chromeVisible = true

    /// Any horizontal or vertical scroll collapses to the focused view with
    /// no haptic (haptic lives only on the tap toggle in the view) and the
    /// view closes an open reader menu on the focus change.
    func collapseToFocused() {
        if chromeVisible {
            chromeVisible = false
        }
    }

    // Translation state, keyed by hadith internal id.
    private(set) var translations: [String: TranslationState] = [:]
    private(set) var translationAllowances: [String: TranslationAllowance] = [:]
    private var generationTasks: [String: Task<Void, Never>] = [:]
    private(set) var language: String

    private var outlineTask: Task<Void, Never>?
    private var pageTask: Task<Void, Never>?
    private var warmingTask: Task<Void, Never>?
    private var warmingGeneration = 0
    private(set) var pageGeneration = 0
    private(set) var navigationRevision = 0
    private enum PageLoadOperation {
        case page(Int, String, String?)
        case edge(String, VolumeEdge)
    }
    private var pageLoadOperation: PageLoadOperation?
    enum JumpPageSource: Equatable {
        case live(contentVersion: String?, paginationVersion: Double?)
        case offline(contentVersion: String)
    }
    struct JumpPageCount: Equatable {
        let count: Int
        let source: JumpPageSource
    }
    struct JumpDestination: Equatable {
        let volumeId: String
        let pageIndex: Int
        let pageCount: JumpPageCount
    }
    enum TurnTarget {
        case page(String, Int)
        case volumeEdge(String, VolumeEdge)
        case jump(JumpDestination)
    }
    struct PendingTurn {
        enum Status { case loading, failed }
        let id: UUID
        let target: TurnTarget
        var status: Status
    }
    private(set) var pendingTurn: PendingTurn?
    private var pendingTurnTask: Task<Void, Never>?

    func knownPageCountForJump(volumeId: String) -> JumpPageCount? {
        guard volumes.contains(where: { $0.volumeId == volumeId }) else { return nil }
        let current = pages.indices.contains(pageIndex) ? pages[pageIndex] : nil
        if let current, !current.isPlaceholder, isLegacyPage(current) {
            return nil
        }
        let page = selectedVolumeId == volumeId && current?.isPlaceholder == false
            ? current
            : pageStore.peek(collection: collectionSlug, volume: volumeId, index: 0)
                ?? pageStore.peekLast(collection: collectionSlug, volume: volumeId)
        guard let page, !isLegacyPage(page), pageStore.isCompatible(page, collection: collectionSlug) else { return nil }
        return livePageCountForJump(page)
    }

    func pageCountForJump(volumeId: String) async throws -> JumpPageCount {
        if let known = knownPageCountForJump(volumeId: volumeId) { return known }
        guard volumes.contains(where: { $0.volumeId == volumeId }) else { throw OfflineFetchTimeout.timedOut }
        let revision = navigationRevision
        let current = pages.indices.contains(pageIndex) ? pages[pageIndex] : nil
        if let current, !current.isPlaceholder, isLegacyPage(current) {
            guard let count = offlinePageCountForJump(volumeId: volumeId) else { throw OfflineFetchTimeout.timedOut }
            return count
        }
        do {
            let page = try await fetchTurnPage(0, volumeId: volumeId)
            try Task.checkCancellation()
            guard revision == navigationRevision else { throw CancellationError() }
            guard let count = livePageCountForJump(page) else { throw OfflineFetchTimeout.timedOut }
            return count
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            guard revision == navigationRevision else { throw CancellationError() }
            guard let count = offlinePageCountForJump(volumeId: volumeId) else { throw error }
            return count
        }
    }

    private func livePageCountForJump(_ page: ReaderPageResult) -> JumpPageCount? {
        guard !page.items.isEmpty, page.page > 0, page.page <= page.totalPages, !isLegacyPage(page) else { return nil }
        return JumpPageCount(count: page.totalPages,
            source: .live(contentVersion: page.contentVersion, paginationVersion: page.paginationVersion))
    }

    private func offlinePageCountForJump(volumeId: String) -> JumpPageCount? {
        guard let version = offlineStore?.registry.record(for: collectionSlug).activeBase,
              let page = offlinePayload(0, volumeId: volumeId, jumpToHadithNumber: nil),
              !page.items.isEmpty, page.totalPages > 0 else { return nil }
        return JumpPageCount(count: page.totalPages, source: .offline(contentVersion: version))
    }

    func jumpToPage(_ destination: JumpDestination) {
        if destination.volumeId == selectedVolumeId, destination.pageIndex == pageIndex { return }
        requestTurn(.jump(destination))
    }

    func cancelPendingTurn() {
        navigationRevision += 1
        pendingTurnTask?.cancel()
        pendingTurnTask = nil
        pendingTurn = nil
    }

    func retryPendingTurn() {
        guard let pending = pendingTurn else { return }
        if case let .jump(destination) = pending.target {
            let id = pending.id
            pendingTurn?.status = .loading
            pendingTurnTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let refreshed = try await self.refreshedJumpDestination(destination)
                    guard self.pendingTurn?.id == id, !Task.isCancelled else { return }
                    self.requestTurn(.jump(refreshed))
                } catch {
                    guard self.pendingTurn?.id == id, !Task.isCancelled else { return }
                    self.pendingTurn?.status = .failed
                    self.pendingTurnTask = nil
                }
            }
            return
        }
        requestTurn(pending.target)
    }

    private func refreshedJumpDestination(_ destination: JumpDestination) async throws -> JumpDestination {
        let count: JumpPageCount
        switch destination.pageCount.source {
        case .live:
            let page = try await fetchTurnPage(destination.pageIndex, volumeId: destination.volumeId)
            guard let refreshed = livePageCountForJump(page), page.page == destination.pageIndex + 1 else {
                throw OfflineFetchTimeout.timedOut
            }
            count = refreshed
        case .offline:
            guard let refreshed = offlinePageCountForJump(volumeId: destination.volumeId),
                  destination.pageIndex < refreshed.count else { throw OfflineFetchTimeout.timedOut }
            count = refreshed
        }
        return JumpDestination(volumeId: destination.volumeId, pageIndex: destination.pageIndex, pageCount: count)
    }

    func requestTurn(_ target: TurnTarget) {
        cancelPendingTurn()
        if case let .page(volume, index) = target, volume == selectedVolumeId,
           pages.indices.contains(index), !pages[index].isPlaceholder {
            pageIndex = index
            return
        }
        let id = UUID()
        pendingTurn = PendingTurn(id: id, target: target, status: .loading)
        pendingTurnTask = Task { [weak self] in await self?.resolveTurn(target, id: id) }
    }

    private func resolveTurn(_ target: TurnTarget, id: UUID) async {
        do {
            let volume: String
            let index: Int
            let result: ReaderPageResult
            switch target {
            case let .page(v, i):
                volume = v
                if v == selectedVolumeId, pages.indices.contains(pageIndex),
                   isLegacyPage(pages[pageIndex]), !pages[pageIndex].isPlaceholder {
                    guard let offline = offlinePayload(i, volumeId: v, jumpToHadithNumber: nil) else {
                        throw OfflineFetchTimeout.timedOut
                    }
                    result = offline
                } else {
                    result = try await fetchTurnPage(i, volumeId: v)
                }
                index = max(0, result.page - 1)
            case let .volumeEdge(v, edge):
                volume = v
                do {
                    let first: ReaderPageResult
                    if edge == .last, let cached = pageStore.peekLast(collection: collectionSlug, volume: v) {
                        first = cached
                    } else {
                        first = try await fetchTurnPage(0, volumeId: v)
                    }
                    let requested = edge == .first ? 0 : max(0, first.totalPages - 1)
                    result = requested == 0 || first.page == requested + 1 ? first : try await fetchTurnPage(requested, volumeId: v)
                } catch {
                    if Task.isCancelled { throw CancellationError() }
                    guard let first = offlinePayload(0, volumeId: v, jumpToHadithNumber: nil) else { throw error }
                    let requested = edge == .first ? 0 : max(0, first.totalPages - 1)
                    guard let offline = offlinePayload(requested, volumeId: v, jumpToHadithNumber: nil) else { throw error }
                    result = offline
                }
                index = max(0, result.page - 1)
            case let .jump(destination):
                volume = destination.volumeId
                index = destination.pageIndex
                guard volumes.contains(where: { $0.volumeId == volume }),
                      index >= 0, index < destination.pageCount.count else { throw OfflineFetchTimeout.timedOut }
                switch destination.pageCount.source {
                case .live:
                    result = try await fetchTurnPage(index, volumeId: volume)
                    guard livePageCountForJump(result) == destination.pageCount else { throw OfflineFetchTimeout.timedOut }
                case let .offline(version):
                    guard offlineStore?.registry.record(for: collectionSlug).activeBase == version,
                          let page = offlinePayload(index, volumeId: volume, jumpToHadithNumber: nil),
                          page.totalPages == destination.pageCount.count else { throw OfflineFetchTimeout.timedOut }
                    result = page
                }
                guard result.page == index + 1, !result.items.isEmpty else { throw OfflineFetchTimeout.timedOut }
            }
            guard pendingTurn?.id == id, !Task.isCancelled else { return }
            saveCurrentProgress()
            // An older foreground prefetch must not publish over this committed turn.
            pageGeneration += 1
            pageTask?.cancel()
            pageTask = nil
            pageLoadOperation = nil
            isLoadingPage = false
            if selectedVolumeId != volume {
                resetReading(preservingPendingTurn: true)
                selectedVolumeId = volume
                landingHadithNumber = nil
                restoredPosition = nil
            }
            if isLegacyPage(result) {
                pages = pages.map { _ in emptyPage() }
            }
            while pages.count < index { pages.append(emptyPage()) }
            if pages.indices.contains(index) { pages[index] = result } else { pages.append(result) }
            let limit = max(index + 1, result.totalPages)
            if pages.count > limit { pages.removeSubrange(limit...) }
            phase = .reading
            pageIndex = index
            if case .jump = target {
                recentPositions.removeAll { $0.volumeId == volume && $0.pageIndex == index }
                requestHeaderLanding(for: index)
            } else {
                requestRecentLanding(for: index)
            }
            scheduleTranslationsForCurrentPage()
            saveCurrentProgress()
            trimPageSlots()
            if !isLegacyPage(result) { warmAdjacentVolumes() }
            if pendingTurn?.id == id { pendingTurn = nil; pendingTurnTask = nil }
            prefetchForwardIfNeeded()
        } catch {
            guard pendingTurn?.id == id, !Task.isCancelled else { return }
            pendingTurn?.status = .failed
            pendingTurnTask = nil
        }
    }

    private func fetchTurnPage(_ index: Int, volumeId: String) async throws -> ReaderPageResult {
#if DEBUG
        if Self.forceOfflineReader { throw OfflineFetchTimeout.timedOut }
#endif
        let request = ReaderPageContentStore.Request(collection: collectionSlug, volume: volumeId, index: index)
        if let cached = pageStore.cachedRequest(request) { return cached }
        if await backendUnreachable() { throw OfflineFetchTimeout.timedOut }
        return try await fetchReaderPage(index, volumeId: volumeId)
    }
    private var translationTask: Task<Void, Never>?
    private var publicationTask: Task<Void, Never>?
    private var publicationDeadlineTask: Task<Void, Never>?
    private var translationGeneration = 0
    @ObservationIgnored private var scrollProgressTask: Task<Void, Never>?
    @ObservationIgnored private var pendingScrollSave: (scope: UUID, updatedAt: Double)?
    @ObservationIgnored private var lastViewportMotionUptime = -Double.infinity
    @ObservationIgnored private var activeViewportIDs: Set<UUID> = []
    private var lastPositionUpdatedAt = 0.0
    private var lastCapturedAnchor: String?
    private var lastCapturedNormalizedOffset: Double?
    private var lastStableAnchor: ReaderHadith?
    private var lastStableRawPageOffset: Double = 0
    private var lastStableNormalizedOffset: Double = 0
    private(set) var restoredPosition: ReadingPosition?

    /// The reading location is the settled leading hadith, not the first
    /// row on a page. Reader-menu actions must use the same anchor that R1
    /// persists for Continue Reading.
    func positionedHadith() -> ReaderHadith? {
        let page = currentPageHadiths
        if let stable = lastStableAnchor,
           page.contains(where: { $0.internalId == stable.internalId }) {
            return stable
        }
        let target = restoredPosition?.anchor.providerHadithId ?? landingHadithNumber
        return page.first(where: { $0.providerHadithId == target }) ?? page.first
    }
    private(set) var landingHadithNumber: String?
    /// The single state owner for vertical landing. It persists until the
    /// matching rendered page acknowledges the command.
    private(set) var verticalLanding: ReaderVerticalLandingRequest?
    private var nextVerticalLandingToken = 0
    @ObservationIgnored private var recentPositions: [RecentPagePosition] = []
    private(set) var recentSessionGeneration = 0
    @ObservationIgnored private var recentPositionToken = 0
    @ObservationIgnored private var recentLayout: (layout: ReadingLayout, signature: String)?

    private struct RecentPagePosition {
        let volumeId: String
        let pageIndex: Int
        let pageKey: String?
        let contentVersion: String?
        let paginationVersion: Double?
        let itemIDs: [String]
        let position: ReadingPosition
        let request: ReaderVerticalLandingRequest

        func matches(_ page: ReaderPageResult, volume: String, index: Int) -> Bool {
            volumeId == volume && pageIndex == index && pageKey == page.pageKey
                && contentVersion == page.contentVersion && paginationVersion == page.paginationVersion
                && itemIDs == page.items.map(\.internalId)
        }
    }

    struct RenderedPageContext: Identifiable {
        let volume: OutlineVolume
        let volumeNumber: Int?
        let index: Int
        let payload: ReaderPageResult
        let range: (first: String, last: String)?
        let landing: ReaderVerticalLandingRequest?
        let generation: Int
        let storeGeneration: Int
        func rebased(generation: Int, storeGeneration: Int) -> RenderedPageContext {
            RenderedPageContext(volume: volume, volumeNumber: volumeNumber, index: index, payload: payload,
                range: range, landing: landing, generation: generation, storeGeneration: storeGeneration)
        }

        var id: String {
            [volume.volumeId, String(index), payload.pageKey ?? "legacy", payload.contentVersion ?? "legacy",
             String(describing: payload.paginationVersion), payload.items.map(\.internalId).joined(separator: "|")].joined(separator: ":")
        }
    }

    private(set) var preparedPageRevision = 0
    // Keep the preview's header metadata stable for this page visit; navigation clears it.
    private var retainedRenderedContext: RenderedPageContext?

    func renderedPage(volumeId: String, index: Int, payload: ReaderPageResult) -> RenderedPageContext? {
        guard let volumeIndex = volumes.firstIndex(where: { $0.volumeId == volumeId }), !payload.isPlaceholder else { return nil }
        let recent = recentPositions.last { $0.matches(payload, volume: volumeId, index: index) }?.request
        let landing = volumeId == selectedVolumeId && index == pageIndex ? verticalLanding : recent ??
            ReaderVerticalLandingRequest(id: 0, page: .init(volumeId: volumeId, pageIndex: index), landing: .header)
        let retainedRange = volumeId == selectedVolumeId && ReaderVolumeRange.isFullyCached(pages: pages)
            ? ReaderVolumeRange.endpointIDs(pages: pages) : nil
        return RenderedPageContext(volume: volumes[volumeIndex], volumeNumber: volumeIndex + 1,
            index: index, payload: payload, range: pageStore.knownRange(collection: collectionSlug, volume: volumeId) ?? retainedRange,
            landing: landing, generation: pageGeneration, storeGeneration: pageStore.contextVersion)
    }

    func renderedCurrentPage() -> RenderedPageContext? {
        guard let volume = selectedVolumeId, pages.indices.contains(pageIndex) else { return nil }
        let current = renderedPage(volumeId: volume, index: pageIndex, payload: pages[pageIndex])
        if let retainedRenderedContext, retainedRenderedContext.id == current?.id { return retainedRenderedContext }
        return current
    }

    func renderedNeighbor(_ turn: ReaderPageTurn) -> RenderedPageContext? {
        _ = preparedPageRevision
        guard let volume = selectedVolumeId else { return nil }
        let index = pageIndex + (turn == .next ? 1 : -1)
        if (turn == .next ? hasNextPage : hasPreviousPage) {
            guard pages.indices.contains(index), !pages[index].isPlaceholder else { return nil }
            return renderedPage(volumeId: volume, index: index, payload: pages[index])
        }
        guard let neighbor = turn == .next ? nextVolume : previousVolume else { return nil }
        let page = turn == .next
            ? pageStore.peek(collection: collectionSlug, volume: neighbor.volumeId, index: 0)
            : pageStore.peekLast(collection: collectionSlug, volume: neighbor.volumeId)
        guard let page else { return nil }
        return renderedPage(volumeId: neighbor.volumeId, index: max(0, page.page - 1), payload: page)
    }

    func isCommitted(_ context: RenderedPageContext) -> Bool {
        guard selectedVolumeId == context.volume.volumeId, pageIndex == context.index,
              pages.indices.contains(pageIndex), let current = renderedCurrentPage() else { return false }
        return current.id == context.id
    }

    @discardableResult
    func commitRenderedPage(_ context: RenderedPageContext) -> Bool {
        guard context.generation == pageGeneration, context.storeGeneration == pageStore.contextVersion else { return false }
        if context.volume.volumeId == selectedVolumeId {
            guard pages.indices.contains(context.index),
                  renderedPage(volumeId: context.volume.volumeId, index: context.index, payload: pages[context.index])?.id == context.id else { return false }
            requestTurn(.page(context.volume.volumeId, context.index))
            verticalLanding = context.landing
            retainedRenderedContext = context.rebased(generation: pageGeneration, storeGeneration: pageStore.contextVersion)
            return true
        }
        guard let cached = pageStore.peek(collection: collectionSlug, volume: context.volume.volumeId, index: context.index),
              renderedPage(volumeId: context.volume.volumeId, index: context.index, payload: cached)?.id == context.id else { return false }
        cancelPendingTurn()
        saveCurrentProgress()
        resetReading()
        selectedVolumeId = context.volume.volumeId
        landingHadithNumber = nil
        restoredPosition = nil
        pages = (0..<context.index).map { _ in emptyPage() } + [context.payload]
        phase = .reading
        pageIndex = context.index
        verticalLanding = context.landing
        retainedRenderedContext = context.rebased(generation: pageGeneration, storeGeneration: pageStore.contextVersion)
        trimPageSlots()
        scheduleTranslationsForCurrentPage()
        saveCurrentProgress()
        warmAdjacentVolumes()
        prefetchForwardIfNeeded()
        return true
    }

    private func recentPosition(for index: Int) -> RecentPagePosition? {
        guard let volume = selectedVolumeId, pages.indices.contains(index) else { return nil }
        return recentPositions.last { $0.matches(pages[index], volume: volume, index: index) }
    }

    func landingForPage(_ index: Int) -> ReaderVerticalLandingRequest? {
        if index == pageIndex { return verticalLanding }
        if let recent = recentPosition(for: index) { return recent.request }
        return ReaderVerticalLandingRequest(id: 0,
            page: .init(volumeId: selectedVolumeId ?? "", pageIndex: index), landing: .header)
    }

    var knownVolumeRange: (first: String, last: String)? {
        guard let volume = selectedVolumeId else { return nil }
        return pageStore.knownRange(collection: collectionSlug, volume: volume)
    }

    func recentLandingForPage(_ index: Int) -> ReaderVerticalLandingRequest? {
        recentPosition(for: index)?.request
    }

    func clearRecentPositions(restartLoading: Bool = false) {
        retainedRenderedContext = nil
        cancelPendingTurn()
        let resumeLoad = restartLoading && isLoadingPage ? pageLoadOperation : nil
        warmingTask?.cancel()
        warmingGeneration += 1
        warmingTask = nil
        pageStore.clear()
        if restartLoading { pageStore.beginReading() }
        pageGeneration += 1
        pageTask?.cancel()
        isLoadingPage = false
        recentSessionGeneration += 1
        recentPositions.removeAll()
        if let landing = verticalLanding, landing.sessionGeneration != nil {
            requestHeaderLanding(for: pageIndex)
        }
        pageLoadOperation = nil
        if let resumeLoad {
            pageTask = Task {
                switch resumeLoad {
                case .page(let index, let volume, let target): await loadPage(index, volumeId: volume, jumpToHadithNumber: target)
                case .edge(let volume, let edge): await loadVolumeEdge(volume, edge: edge)
                }
            }
        }
    }

    private func requestRecentLanding(for index: Int) {
        if let recent = recentPosition(for: index) {
            verticalLanding = recent.request
        } else {
            requestHeaderLanding(for: index)
        }
    }

    private func rememberPosition(anchor: ReaderHadith, page: ReaderPageResult, normalizedOffset: Double, atHeader: Bool, viewport: ReaderViewportSnapshot?) {
        guard let volume = selectedVolumeId else { return }
        recentPositionToken -= 1
        let layout = readingLayout(page.paginationVersion ?? 1)
        if recentLayout?.layout != layout { recentLayout = (layout, layout.signature) }
        let position = ReadingPosition(anchor: .init(provider: anchor.provider, collectionSlug: anchor.collectionSlug,
            providerHadithId: anchor.providerHadithId), contentVersion: page.contentVersion ?? "legacy",
            volumeId: volume, chapterId: anchor.chapterId, pageKey: page.pageKey ?? "legacy",
            displayPageIndex: Double(max(1, page.page)), rawPageOffset: 0, normalizedOffset: normalizedOffset,
            layoutSignature: recentLayout!.signature, updatedAt: 0)
        recentPositions.removeAll { $0.volumeId == volume && $0.pageIndex == pageIndex }
        recentPositions.append(RecentPagePosition(volumeId: volume, pageIndex: pageIndex,
            pageKey: page.pageKey, contentVersion: page.contentVersion, paginationVersion: page.paginationVersion,
            itemIDs: page.items.map(\.internalId), position: position,
            request: ReaderVerticalLandingRequest(id: recentPositionToken,
                page: .init(volumeId: volume, pageIndex: pageIndex),
                landing: atHeader ? .header : .semantic(providerHadithId: anchor.providerHadithId, normalizedOffset: normalizedOffset), viewport: viewport, sessionGeneration: recentSessionGeneration)))
        if recentPositions.count > 32 { recentPositions.removeFirst(recentPositions.count - 32) }
    }

    init(
        convex: ConvexClientWithAuth<String>,
        collectionSlug: String,
        collectionName: String,
        language: String,
        isSignedIn: @escaping () -> Bool,
        library: UserLibraryModel? = nil,
        openVolumeId: String? = nil,
        openHadithNumber: String? = nil,
        openPosition: ReadingPosition? = nil,
        targetSource: ReaderTargetSource = .collection,
        currentPreferences: @escaping () -> ReaderPreferences = { ReaderPreferences() },
        widthClass: ReadingWidthClass = .compact,
        pageStore: ReaderPageContentStore? = nil
    ) {
        self.convex = convex
        self.collectionSlug = collectionSlug
        self.collectionName = collectionName
        self.language = language
        self.isSignedIn = isSignedIn
        self.library = library
        self.openVolumeId = openVolumeId
        self.openHadithNumber = openHadithNumber
        self.openPosition = openPosition
        self.targetSource = targetSource
        self.currentPreferences = currentPreferences
        self.widthClass = widthClass
        self.pageStore = pageStore ?? ReaderPageContentStore(convex: convex)
        self.pageStore.beginReading()
    }

    var currentPages: [ReaderPageResult] { pages }

    var currentPageHadiths: [ReaderHadith] {
        guard pages.indices.contains(pageIndex) else { return [] }
        return pages[pageIndex].items
    }

    var currentPageNumber: Int { pageIndex + 1 }

    var totalPages: Int? {
        pages.last?.totalPages
    }

    var currentVolumeTitle: String? {
        guard let selectedVolumeId else { return nil }
        return volumes.first { $0.volumeId == selectedVolumeId }?.title
    }

    var hasPreviousPage: Bool { pageIndex > 0 }

    var hasNextPage: Bool {
        guard pages.indices.contains(pageIndex) else { return false }
        if pageIndex < pages.count - 1 { return true }
        return pages[pageIndex].hasMore
    }

    // MARK: - Lifecycle

    func start() {
        watchLoadedPublications()
        guard case .loadingOutline = phase, outlineTask == nil else { return }
        outlineTask = Task { [weak self] in
            await self?.loadOutline()
        }
    }

    func stop() {
        cancelPendingTurn()
        endViewportInteractions()
        flushScrollProgress()
        pageGeneration += 1
        isLoadingPage = false
        automaticTranslationTask?.cancel()
        automaticVisibleHadiths = []
        outlineTask?.cancel()
        pageTask?.cancel()
        translationTask?.cancel()
        publicationTask?.cancel()
        publicationDeadlineTask?.cancel()
        outlineTask = nil
        pageTask = nil
        translationTask = nil
    }

    /// A fetch that never resolves (dead network, hung socket) must not
    /// strand the reader on a spinner when a verified dump is on disk.
    /// Each Convex fetch races a bounded sleeper; the timeout error falls
    /// into the same offline-fallback path as any other fetch failure.
    private static let fetchTimeoutSeconds = 10.0

    /// DEBUG-only test hook (`-forceOfflineReader` launch argument): skips
    /// the network fetch so UI tests can prove the dump fallback path in a
    /// single launch (download online, then read offline). Never compiled
    /// into release builds.
#if DEBUG
    private static var forceOfflineReader: Bool {
        AutomationContext.allows("-forceOfflineReader")
    }
#endif

    /// True when the backend is provably unreachable. The probe runs on
    /// URLSession's own threads, so it answers even when every Convex call
    /// would wedge the cooperative pool.
    private func backendUnreachable() async -> Bool {
        guard let probeURL = offlineProbeBaseURL else { return false }
        return await OfflineProbe.shared.isReachable(probeURL) == false
    }

    private func loadOutline() async {
        do {
#if DEBUG
            if Self.forceOfflineReader {
                throw OfflineFetchTimeout.timedOut
            }
#endif
            if await backendUnreachable() {
                if useOfflineOutline() {
                    outlineTask = nil
                    return
                }
                phase = .failed("You're offline. Connect to load this collection.")
                outlineTask = nil
                return
            }
            let result: CollectionOutlineResult = try await OfflineModels.withFetchTimeout(seconds: Self.fetchTimeoutSeconds) {
                try await self.convex.action(
                    "actions/hadithData:getCollectionOutline",
                    with: ["collectionSlug": self.collectionSlug as ConvexEncodable?]
                )
            }
            volumes = result.volumes
            // Explicit deep links (Today/Saved) name a volume; a canonical
            // link carries only the hadith number, so the volume holding it
            // comes from the outline's source-provided counts. Unknown or
            // stale numbers degrade to the first volume.
            let target = ReaderTargetResolver.resolve(.init(
                source: targetSource,
                collectionSlug: collectionSlug,
                hadithNumber: openHadithNumber,
                position: openPosition
            ))
            restoredPosition = target.position
            landingHadithNumber = target.hadithNumber
            let targetVolume = target.hadithNumber.flatMap {
                Self.volumeId(forHadithNumber: $0, in: volumes)
            }
            let requested = result.volumes.first { $0.volumeId == openVolumeId }?.volumeId
            let restoredVolume = result.volumes.first { $0.volumeId == target.volumeId }?.volumeId
            let firstVolume = restoredVolume ?? requested ?? targetVolume ?? result.volumes.first?.volumeId
            selectedVolumeId = firstVolume
            if let firstVolume {
                await loadPage(
                    0,
                    volumeId: firstVolume,
                    jumpToHadithNumber: target.hadithNumber
                )
            } else {
                phase = .failed("No volumes found for this collection.")
            }
        } catch {
            if !useOfflineOutline() {
                phase = .failed(ReaderModels.errorMessage(of: error))
            }
        }
        outlineTask = nil
    }

    /// O2: when the outline fetch fails (airplane mode, revoked session)
    /// and a verified dump is active, read the outline from disk. Volumes
    /// come from the dump's own volume ids; titles fall back to the id so
    /// nothing is invented. Returns false when no dump is active.
    @discardableResult
    private func useOfflineOutline() -> Bool {
        usedOfflineForEntry = true
        guard let store = offlineStore,
              let outline = store.offlineOutline(slug: collectionSlug),
              !outline.volumes.isEmpty
        else { return false }
        volumes = outline.volumes
        let target = ReaderTargetResolver.resolve(.init(
            source: targetSource,
            collectionSlug: collectionSlug,
            hadithNumber: openHadithNumber,
            position: openPosition
        ))
        restoredPosition = target.position
        landingHadithNumber = target.hadithNumber
        let targetVolume = target.hadithNumber.flatMap {
            Self.volumeId(forHadithNumber: $0, in: volumes)
        }
        let requested = outline.volumes.first { $0.volumeId == openVolumeId }?.volumeId
        let restoredVolume = outline.volumes.first { $0.volumeId == target.volumeId }?.volumeId
        selectedVolumeId = requested ?? restoredVolume ?? targetVolume ?? outline.volumes.first?.volumeId
        if let selectedVolumeId {
            Task { [weak self] in
                await self?.loadPage(0, volumeId: selectedVolumeId, jumpToHadithNumber: target.hadithNumber)
            }
        } else {
            phase = .failed("No volumes found for this collection.")
        }
        return true
    }

    /// Locates the source-provided volume that holds a hadith number by
    /// walking the outline's counts in order. Sub-references ("4.5") use
    /// the integer part. Returns nil when the number exceeds the collection.
    nonisolated static func volumeId(
        forHadithNumber hadithNumber: String,
        in volumes: [OutlineVolume]
    ) -> String? {
        guard
            let integerPart = hadithNumber.split(separator: ".").first,
            let target = Int(integerPart)
        else { return nil }
        var lower = 0
        for volume in volumes {
            let upper = lower + volume.hadithCount
            if target > lower && target <= upper { return volume.volumeId }
            lower = upper
        }
        return nil
    }

    func selectVolume(_ volumeId: String) {
        cancelPendingTurn()
        guard volumeId != selectedVolumeId else { return }
        // The R1 position of the page being left is saved before the
        // switch, exactly like the pill/swipe cross-volume path below.
        saveCurrentProgress()
        collapseToFocused()
        selectedVolumeId = volumeId
        resetReading()
        pageTask = Task { await loadPage(0, volumeId: volumeId) }
    }

    /// Volumes in outline order around the selection, for the bottom pills
    /// and the cross-volume swipe path. Nil at the absolute ends.
    var previousVolume: OutlineVolume? {
        guard let id = selectedVolumeId,
              let index = volumes.firstIndex(where: { $0.volumeId == id }),
              index > 0
        else { return nil }
        return volumes[index - 1]
    }

    var nextVolume: OutlineVolume? {
        guard let id = selectedVolumeId,
              let index = volumes.firstIndex(where: { $0.volumeId == id }),
              index < volumes.count - 1
        else { return nil }
        return volumes[index + 1]
    }

    /// Where a cross-volume jump lands: the neighbor's first page, or its
    /// last page when coming from the other side.
    enum VolumeEdge {
        case first
        case last
    }

    /// The pure pill state behind the bottom pills and the boundary
    /// decision in the swipe path: neighbor page numbers mid-volume, the
    /// neighboring volume's full title at a volume edge, nothing at the
    /// absolute ends.
    var pillState: ReaderPagePills.State {
        // A cross-volume pill is offered only from a fully loaded page:
        // never from a deep-link placeholder or a next-page phantom that
        // is still fetching.
        let atLoadedPage = pages.indices.contains(pageIndex) && !pages[pageIndex].isPlaceholder
        return ReaderPagePills.state(
            pageIndex: pageIndex,
            hasPreviousPage: hasPreviousPage,
            hasNextPage: hasNextPage,
            atLoadedPage: atLoadedPage,
            volumes: volumes,
            selectedVolumeId: selectedVolumeId
        )
    }

    /// Follows one bottom pill to its target: an in-volume page turn, or a
    /// cross-volume jump. The swipe path calls the same method, so pills
    /// and swipes can never disagree.
    func followPill(_ pill: ReaderPagePills.Pill) {
        switch pill.target {
        case .page(let index):
            // Same step semantics as the swipe path: forward onto (or
            // toward) the next page, back onto the previous page.
            if index == pageIndex + 1, hasNextPage {
                if let volume = selectedVolumeId { requestTurn(.page(volume, index)) }
            } else if index == pageIndex - 1, hasPreviousPage {
                if let volume = selectedVolumeId { requestTurn(.page(volume, index)) }
            }
        case .volumeFirst(let volumeId):
            switchToVolume(volumeId, edge: .first)
        case .volumeLast(let volumeId):
            switchToVolume(volumeId, edge: .last)
        }
    }

    /// Request a neighboring volume without replacing the visible page until ready.
    func switchToVolume(_ volumeId: String, edge: VolumeEdge) {
        guard volumeId != selectedVolumeId else { return }
        guard volumes.contains(where: { $0.volumeId == volumeId }) else { return }
        collapseToFocused()
        let turn: ReaderPageTurn = edge == .first ? .next : .previous
        if let prepared = renderedNeighbor(turn), prepared.volume.volumeId == volumeId,
           (edge == .first ? prepared.index == 0 : prepared.index == prepared.payload.totalPages - 1),
           commitRenderedPage(prepared) { return }
        requestTurn(.volumeEdge(volumeId, edge))
    }

    /// Loads a volume edge: page 1 for `.first`; for `.last` the first page
    /// is read only to learn the total, then the last page is fetched and
    /// published together so no intermediate page flashes.
    private func loadVolumeEdge(_ volumeId: String, edge: VolumeEdge) async {
        if isLoadingPage { return }
        pageLoadOperation = .edge(volumeId, edge)
        isLoadingPage = true
        let generation = pageGeneration
        var shouldPrefetchNeighbor = false
        defer {
            if generation == pageGeneration {
                pageLoadOperation = nil
                isLoadingPage = false
                // Prefetch only after this request releases its loading state.
                if shouldPrefetchNeighbor { prefetchForwardIfNeeded() }
            }
        }
        do {
            let first: ReaderPageResult
            if edge == .last, let cached = pageStore.peekLast(collection: collectionSlug, volume: volumeId) {
                first = cached
            } else {
                first = try await fetchReaderPage(0, volumeId: volumeId)
            }
            guard generation == pageGeneration, !Task.isCancelled else { return }
            let total = max(1, first.totalPages)
            switch edge {
            case .first:
                pages = [first]
                phase = .reading
                pageIndex = 0
                requestRecentLanding(for: 0)
                shouldPrefetchNeighbor = true
            case .last:
                let landingIndex = total - 1
                if landingIndex == 0 {
                    pages = [first]
                } else {
                    let last = try await fetchReaderPage(landingIndex, volumeId: volumeId)
                    guard generation == pageGeneration, !Task.isCancelled else { return }
                    var filled = (0..<landingIndex).map { _ in emptyPage() }
                    filled.append(last)
                    _ = first
                    pages = filled
                }
                phase = .reading
                pageIndex = landingIndex
                requestRecentLanding(for: landingIndex)
            }
            scheduleTranslationsForCurrentPage()
            saveCurrentProgress()
            warmAdjacentVolumes()
        } catch is CancellationError {
            // A newer page or volume target replaces this fetch.
        } catch {
            if generation == pageGeneration, !Task.isCancelled, pages.isEmpty {
                phase = .failed(ReaderModels.errorMessage(of: error))
            }
        }
    }

    private func fetchReaderPage(_ index: Int, volumeId: String, targetHadithNumber: String? = nil) async throws -> ReaderPageResult {
        let request = ReaderPageContentStore.Request(collection: collectionSlug, volume: volumeId,
            index: index, target: targetHadithNumber)
#if DEBUG
        if let pageFetchForUITest {
            return try await pageStore.load(request, fetch: { request in
                try await pageFetchForUITest(request.index, request.volume, request.target)
            })
        }
#endif
        return try await pageStore.load(request)
    }

    private func isLegacyPage(_ page: ReaderPageResult) -> Bool {
        page.pageKey == nil || page.pageKey == "legacy"
    }

    private func restoreCachedNeighbors() {
        guard let volume = selectedVolumeId else { return }
        if pages.indices.contains(pageIndex), !pages[pageIndex].isPlaceholder, isLegacyPage(pages[pageIndex]) { return }
        for index in [pageIndex - 1, pageIndex, pageIndex + 1] where pages.indices.contains(index) {
            if !pageStore.isCompatible(pages[index], collection: collectionSlug) { pages[index] = emptyPage() }
            guard pages[index].isPlaceholder else { continue }
            if let page = pageStore.peek(collection: collectionSlug, volume: volume, index: index) { pages[index] = page }
        }
    }

    private func trimPageSlots() {
        let pinned = Set([pageIndex - 1, pageIndex, pageIndex + 1, pages.count - 1])
        for index in pages.indices where !pinned.contains(index) { pages[index] = emptyPage() }
    }

#if DEBUG
    /// Seeds outline state for the R5 contents fixture without network.
    func seedQ1TranslationForUITest(id: String, state: TranslationState, allowance: TranslationAllowance?) {
        translations[id] = state
        translationAllowances[id] = allowance
    }

    func seedPagesForUITest(_ pages: [ReaderPageResult]) { self.pages = pages }

    func startContinueForUITest() async {
        let target = ReaderTargetResolver.resolve(.init(source: targetSource, collectionSlug: collectionSlug,
            hadithNumber: openHadithNumber, position: openPosition))
        restoredPosition = target.position
        landingHadithNumber = target.hadithNumber
        guard let volume = target.volumeId ?? volumes.first?.volumeId else { return }
        selectedVolumeId = volume
        await loadPage(0, volumeId: volume, jumpToHadithNumber: target.hadithNumber)
    }

    func seedForUITest(volumes: [OutlineVolume], selectedVolumeId: String) {
        self.volumes = volumes
        self.selectedVolumeId = selectedVolumeId
        self.phase = .reading
    }

    /// Seeds saved state for the R6A reader fixture without network. When
    /// seeded, `isBookmarked`/`isFavorite` answer from these sets so the
    /// mini markers render deterministically.
    private var uitestSavedStateSeeded = false
    private var uitestBookmarkedIds: Set<String> = []
    private var uitestFavoritedIds: Set<String> = []
    private var uitestNotedIds: Set<String> = []

    func seedSavedStateForUITest(bookmarkedIds: Set<String>, favoritedIds: Set<String>) {
        uitestSavedStateSeeded = true
        uitestBookmarkedIds = bookmarkedIds
        uitestFavoritedIds = favoritedIds
    }

    /// Seeds note presence for the R6 round-3 reader fixture without
    /// network. Seeded hadiths report a stub note so the green inline
    /// marker renders deterministically.
    func seedNotesForUITest(notedIds: Set<String>) {
        uitestSavedStateSeeded = true
        uitestNotedIds = notedIds
    }
#endif

    /// R5 contents navigation: selects the volume holding a source-provided
    /// chapter and lands on the chapter's first hadith through the same
    /// R2 target path as canonical links (`loadPage` with
    /// `jumpToHadithNumber`). Unlike `selectVolume`, this always navigates —
    /// even inside the current volume — because the target hadith differs.
    func selectChapter(volumeId: String, chapter: OutlineChapter) {
        selectedVolumeId = volumeId
        resetReading()
        collapseToFocused()
        landingHadithNumber = chapter.firstProviderHadithId
        restoredPosition = nil
        pageTask = Task { await loadPage(0, volumeId: volumeId, jumpToHadithNumber: chapter.firstProviderHadithId) }
    }

    /// R5 jump-to-reference: validates the number against the canonical
    /// hadith-id pattern and navigates through the same volume-locator path
    /// as canonical links. Well-formed but stale numbers fall back to the
    /// first volume's start, exactly like a stale canonical link. Returns
    /// false for malformed input so the sheet can keep itself open with an
    /// inline error.
    @discardableResult
    func jumpToReference(_ number: String) -> Bool {
#if DEBUG
        navigationTraceForUITest?("jump:" + number)
#endif
        let trimmed = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ReaderShare.isValidReferenceNumber(trimmed) else { return false }
        collapseToFocused()
        if let volume = Self.volumeId(forHadithNumber: trimmed, in: volumes) {
            selectedVolumeId = volume
            resetReading()
            landingHadithNumber = trimmed
            restoredPosition = nil
            pageTask = Task { await loadPage(0, volumeId: volume, jumpToHadithNumber: trimmed) }
        } else {
            landingHadithNumber = nil
            restoredPosition = nil
            guard let first = volumes.first?.volumeId else { return true }
            selectedVolumeId = first
            resetReading()
            pageTask = Task { await loadPage(0, volumeId: first) }
        }
        return true
    }

    /// Exact navigation for saved entries and search results that already
    /// name their volume: the R2 jump path pinned to that volume instead of
    /// the outline-count locator. Falls back to `jumpToReference` when the
    /// volume is unknown or not in the outline.
    func jumpToHadith(volumeId: String?, hadithNumber: String) {
        let trimmed = hadithNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ReaderShare.isValidReferenceNumber(trimmed) else { return }
        collapseToFocused()
        if let volumeId,
           volumes.contains(where: { $0.volumeId == volumeId }) {
            selectedVolumeId = volumeId
            resetReading()
            landingHadithNumber = trimmed
            restoredPosition = nil
            pageTask = Task { [weak self] in await self?.loadPage(0, volumeId: volumeId, jumpToHadithNumber: trimmed) }
        } else {
            jumpToReference(trimmed)
        }
    }

    // MARK: - English-text search (R6 round 3)

    /// One-shot read of the public `hadiths:searchEnglish` query over
    /// cached provider English text. Blank text returns [] without touching
    /// the backend; failures degrade to [] so the sheet stays quiet
    /// (the query deploys after this client task). The SDK has no one-shot
    /// query call, so this takes the first subscription emission.
    func searchEnglish(text: String, limit: Int = ReaderPrefetchTargets.defaultSearchLimit) async -> [EnglishSearchResult] {
        let queryText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !queryText.isEmpty else { return [] }
        let clamped = max(1, min(25, limit))
        do {
            for try await rows in convex.subscribe(
                to: "hadiths:searchEnglish",
                with: [
                    "text": queryText as ConvexEncodable?,
                    "collectionSlug": collectionSlug as ConvexEncodable?,
                    "limit": Double(clamped) as ConvexEncodable?,
                ],
                yielding: [EnglishSearchResult].self
            ).values {
                return EnglishSearchMapping.navigable(rows)
            }
        } catch {
            return []
        }
        return []
    }

    // MARK: - Adjacent-volume prefetch (R6 round 3)

    private func resetReading(preservingPendingTurn: Bool = false) {
        retainedRenderedContext = nil
        if !preservingPendingTurn { cancelPendingTurn() }
        flushScrollProgress()
        pageGeneration += 1
        pageTask?.cancel()
        isLoadingPage = false
        translationTask?.cancel()
        publicationTask?.cancel()
        publicationDeadlineTask?.cancel()
        pageTask = nil
        translationTask = nil
        translationGeneration += 1
        pages = []
        pageIndex = 0
        translations = [:]
        translationAllowances = [:]
        lastCapturedAnchor = nil
        lastCapturedNormalizedOffset = nil
        lastStableAnchor = nil
        lastStableRawPageOffset = 0
        lastStableNormalizedOffset = 0
        verticalLanding = nil
    }

    func setLanguage(_ code: String) {
        guard code != language else { return }
        language = code
        translationTask?.cancel()
        publicationTask?.cancel()
        publicationDeadlineTask?.cancel()
        translationGeneration += 1
        translations = [:]
        translationAllowances = [:]
        scheduleTranslationsForCurrentPage()
    }

    // MARK: - Paging

    /// Loads reader page `index` (0-based) for the given volume. Pages before
    /// the requested one are filled with empty results so the page index
    /// stays aligned. When `jumpToHadithNumber` is set (deep link from
    /// Today/Saved/continue reading), the backend resolves the page that
    /// contains that hadith and it is placed at its true position.
    private func loadPage(_ index: Int, volumeId: String, jumpToHadithNumber: String? = nil) async {
        if isLoadingPage { return }
        pageLoadOperation = .page(index, volumeId, jumpToHadithNumber)
        isLoadingPage = true
        let generation = pageGeneration
        var shouldPrefetchNeighbor = false
        defer {
            if generation == pageGeneration {
                pageLoadOperation = nil
                isLoadingPage = false
                if shouldPrefetchNeighbor { prefetchForwardIfNeeded() }
            }
        }
        do {
#if DEBUG
            if Self.forceOfflineReader {
                throw OfflineFetchTimeout.timedOut
            }
#endif
            let request = ReaderPageContentStore.Request(collection: collectionSlug, volume: volumeId,
                index: index, target: jumpToHadithNumber)
            let result: ReaderPageResult
            if let cached = pageStore.cachedRequest(request) {
                result = cached
            } else {
                let unreachable = await backendUnreachable()
                guard generation == pageGeneration, !Task.isCancelled else { return }
                if unreachable {
                    if !useOfflinePage(index, volumeId: volumeId, jumpToHadithNumber: jumpToHadithNumber),
                       pages.isEmpty {
                        phase = .failed("You're offline. Connect to load this collection.")
                    }
                    return
                }
                result = try await fetchReaderPage(index, volumeId: volumeId, targetHadithNumber: jumpToHadithNumber)
            }
            guard generation == pageGeneration, !Task.isCancelled else { return }
            if jumpToHadithNumber != nil {
                // The server picked the page; slot it at its real position
                // and land there. Earlier pages load on demand when the
                // reader swipes back onto them.
                let landingIndex = max(0, result.page - 1)
                while pages.count < landingIndex { pages.append(emptyPage()) }
                if pages.indices.contains(landingIndex) {
                    pages[landingIndex] = result
                } else {
                    pages.append(result)
                }
                phase = .reading
                pageIndex = landingIndex
                requestEntryLanding(for: landingIndex)
                restoreCachedNeighbors()
                trimPageSlots()
                warmAdjacentVolumes()
                shouldPrefetchNeighbor = true
            } else {
                while pages.count < index { pages.append(emptyPage()) }
                if pages.indices.contains(index) {
                    pages[index] = result
                } else {
                    pages.append(result)
                }
                phase = .reading
                if pageIndex == index {
                    if verticalLanding == nil || verticalLanding?.landing == .header {
                        requestRecentLanding(for: index)
                    }
                    restoreCachedNeighbors()
                    trimPageSlots()
                    scheduleTranslationsForCurrentPage()
                    saveCurrentProgress()
                    warmAdjacentVolumes()
                    shouldPrefetchNeighbor = true
                }
            }
            trimPageSlots()
        } catch {
            guard generation == pageGeneration, !Task.isCancelled else { return }
            if !useOfflinePage(index, volumeId: volumeId, jumpToHadithNumber: jumpToHadithNumber),
               pages.isEmpty
            {
                phase = .failed(ReaderModels.errorMessage(of: error))
            }
        }
    }

    /// O2: when a page fetch fails and a verified dump is active, serve the
    /// page from disk with the same content-sized chunking. Positions still
    /// resolve by semantic anchor, so approximate page numbers never strand
    /// the reader. Returns false when no dump covers the request.
    @discardableResult
    private func useOfflinePage(_ index: Int, volumeId: String, jumpToHadithNumber: String?) -> Bool {
        guard jumpToHadithNumber != nil || !pages.contains(where: { !$0.isPlaceholder && !isLegacyPage($0) }) else { return false }
        guard let result = offlinePayload(index, volumeId: volumeId, jumpToHadithNumber: jumpToHadithNumber) else { return false }
        usedOfflineForEntry = true
        while pages.count < index { pages.append(emptyPage()) }
        if pages.indices.contains(index) {
            pages[index] = result
        } else {
            pages.append(result)
        }
        phase = .reading
        if jumpToHadithNumber != nil {
            pageIndex = index
            requestEntryLanding(for: index)
            return true
        }
        if pageIndex == index {
            if verticalLanding == nil {
                requestHeaderLanding(for: index)
            }
            saveCurrentProgress()
        }
        return true
    }

    private func offlinePayload(_ index: Int, volumeId: String, jumpToHadithNumber: String?) -> ReaderPageResult? {
        guard let store = offlineStore else { return nil }
        if let jump = jumpToHadithNumber,
           let hadith = store.offlineHadith(canonicalId: "sunnah_now:\(collectionSlug):\(jump)", slug: collectionSlug, locale: offlineLocale) {
            return ReaderPageResult(items: [hadith], page: 1, pageSize: 1, totalPages: 1, hasMore: false,
                                    contentVersion: nil, paginationVersion: nil, pageKey: nil)
        }
        return store.offlinePage(slug: collectionSlug, volumeId: volumeId, page: index, locale: offlineLocale)
    }

    private func emptyPage() -> ReaderPageResult {
        ReaderPageResult(
            items: [], page: 0, pageSize: 0, totalPages: 0, hasMore: false,
            contentVersion: nil, paginationVersion: nil, pageKey: nil
        )
    }

    /// Swiping back onto a page that was skipped by a deep-link jump loads
    /// it on demand. Placeholder pages carry page == 0.
    private func loadCurrentPageIfNeeded() {
        guard !isLoadingPage, pages.indices.contains(pageIndex) else { return }
        guard pages[pageIndex].isPlaceholder, let volumeId = selectedVolumeId else { return }
        pageTask?.cancel()
        pageTask = Task { await loadPage(pageIndex, volumeId: volumeId) }
    }

    /// Loads the next reader page when the selection moves onto or within
    /// one page of the loaded edge. The selection may legitimately sit one
    /// past the last loaded page while its content is in flight.
    func prefetchForwardIfNeeded() {
        guard !isLoadingPage, let volumeId = selectedVolumeId else { return }
        guard pages.indices.contains(pageIndex), !isLegacyPage(pages[pageIndex]) else { return }
        guard let lastPage = pages.last, lastPage.hasMore else { return }
        guard pageIndex >= pages.count - 1 else { return }
        pageTask?.cancel()
        pageTask = Task { await loadPage(pages.count, volumeId: volumeId) }
    }

    /// Background-caches the first page of the adjacent volumes so
    /// page/volume switches never wait. Bounded to the nearest neighbors,
    /// silent and offline-tolerant. Successful public payloads are retained
    /// in the same bounded store used by foreground page requests.
    func warmAdjacentVolumes() {
        let targets = ReaderPrefetchTargets.adjacentVolumeIds(
            volumes: volumes,
            selectedVolumeId: selectedVolumeId
        )
        guard !targets.isEmpty else { return }
        guard warmingTask == nil else { return }
        warmingGeneration += 1
        let generation = warmingGeneration
        warmingTask = Task { [weak self] in
            guard let self else { return }
            defer { if generation == self.warmingGeneration { self.warmingTask = nil } }
            for volumeId in targets {
                guard !Task.isCancelled else { return }
                if (try? await self.fetchReaderPage(0, volumeId: volumeId)) != nil,
                   generation == self.warmingGeneration, !Task.isCancelled {
                    self.preparedPageRevision += 1
                }
            }
        }
    }

    // MARK: - Translations

    /// Opening and paging only read existing exact-locale translations.
    private func scheduleTranslationsForCurrentPage() {
        guard pages.indices.contains(pageIndex) else { return }
        let hadiths = pages[pageIndex].items
        guard !hadiths.isEmpty else { return }
        translationGeneration += 1
        let generation = translationGeneration
        let requestedLanguage = language
        translationTask?.cancel()
        translationTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await rows in convex.subscribe(to: "translations:getReaderDefaults", with: [
                    "hadithInternalIds": hadiths.map(\.internalId), "language": requestedLanguage,
                ], yielding: [ReaderDefaultTranslation].self).values {
                    guard generation == translationGeneration, !Task.isCancelled else { return }
                    for row in rows {
                        if let stored = row.translation {
                            translations[row.hadithInternalId] = .loaded(stored.readerTranslation)
                        }
                    }
                    watchLoadedPublications()
                    break
                }
            } catch { /* Cached/offline/provider reading stays available. */ }
        }
    }

    private func generateTranslation(_ hadith: ReaderHadith, requestedLanguage: String) async {
        analytics?.record(.translationResultStarted)
        let id = hadith.internalId
        let requestedAccountId = Clerk.shared.user?.id
        guard isSignedIn() else { translations[id] = .failed(.requiresSignIn); analytics?.record(.translationResultSignInRequired); return }
        translations[id] = .loading
        do {
            // An action retry can reuse a result even if device proof is unavailable.
            let stored = try? await convex.subscribe(to: "translations:getDefaultForProviderRef", with: [
                "provider": hadith.provider, "collectionSlug": hadith.collectionSlug,
                "providerHadithId": hadith.providerHadithId, "language": requestedLanguage,
            ], yielding: StoredReaderTranslation?.self).values.first(where: { _ in true })
            if let stored = stored ?? nil {
                guard language == requestedLanguage, Clerk.shared.user?.id == requestedAccountId else { return }
                translations[id] = .loaded(stored.readerTranslation)
                analytics?.record(.translationResultCache)
                watchLoadedPublications()
                await refreshTranslationAllowance(for: id, language: requestedLanguage, accountId: requestedAccountId)
                return
            }
            await refreshTranslationAllowance(for: id, language: requestedLanguage, accountId: requestedAccountId)
            let arguments = try await GenerationRequest.arguments(hadithId: id, language: requestedLanguage, convex: convex)
            let result: ReaderTranslation = try await convex.action("actions/ai:translateHadith", with: arguments)
            guard language == requestedLanguage, Clerk.shared.user?.id == requestedAccountId else { return }
            translations[id] = .loaded(result)
            analytics?.record(result.cached ? .translationResultCache : .translationResultGenerated)
            watchLoadedPublications()
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            guard language == requestedLanguage, Clerk.shared.user?.id == requestedAccountId else { return }
            translations[id] = .failed(TranslationFailure(error: error))
            switch TranslationFailure(error: error) {
            case .quotaExceeded: analytics?.record(.translationResultQuota)
            case .requiresSignIn: analytics?.record(.translationResultSignInRequired)
            case .failed: analytics?.record(.translationResultFailed)
            }
        }
        await refreshTranslationAllowance(for: id, language: requestedLanguage, accountId: requestedAccountId)
    }

    private func refreshTranslationAllowance(for id: String, language requestedLanguage: String, accountId: String?) async {
        if let allowance = try? await convex.subscribe(to: "quotas:getTranslationAllowance", yielding: TranslationAllowance.self)
            .values.first(where: { _ in true }) {
            guard language == requestedLanguage, Clerk.shared.user?.id == accountId, isSignedIn() else { return }
            translationAllowances[id] = allowance
        }
    }

    private func watchLoadedPublications() {
        publicationTask?.cancel()
        publicationDeadlineTask?.cancel()
        let entries = translations.compactMap { key, state -> (String, String)? in
            if case .loaded(let translation) = state { return (key, translation.translationId) }
            return nil
        }.sorted { $0.0 < $1.0 }
        let observed = Array(entries.suffix(40))
        for entry in entries.dropLast(observed.count) { translations.removeValue(forKey: entry.0) }
        guard !observed.isEmpty else { return }
        publicationTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await statuses in convex.subscribe(to: "translations:watchPublications", with: ["translationIds": observed.map(\.1)], yielding: [PublicationAvailability].self).values {
                    guard !Task.isCancelled else { return }
                    applyPublicationAvailability(statuses)
                    publicationDeadlineTask?.cancel()
                    if statuses.contains(where: { $0.validUntil != nil }) {
                        publicationDeadlineTask = Task { [weak self] in
                            while let deadline = statuses.compactMap(\.validUntil).filter({ $0 > Date().timeIntervalSince1970 * 1000 }).min() {
                                let delay = max(0, deadline / 1000 - Date().timeIntervalSince1970)
                                try? await Task.sleep(for: .seconds(delay))
                                guard !Task.isCancelled else { return }
                                self?.applyPublicationAvailability(statuses)
                            }
                        }
                    }
                }
                if !Task.isCancelled { for entry in observed { translations.removeValue(forKey: entry.0) } }
            } catch {
                guard !Task.isCancelled else { return }
                for entry in observed { translations.removeValue(forKey: entry.0) }
            }
        }
    }

    func applyPublicationAvailability(_ statuses: [PublicationAvailability], now: Double = Date().timeIntervalSince1970 * 1000) {
        translations = ReaderPublicationPolicy.keepingAvailable(translations, statuses: statuses, now: now)
    }

    /// The only path that creates new reader translations.
    func retryTranslation(for hadith: ReaderHadith) {
        guard generationTasks[hadith.internalId] == nil else { return }
        let requestedLanguage = language
        generationTasks[hadith.internalId] = Task { [weak self] in
            guard let self else { return }
            defer { generationTasks.removeValue(forKey: hadith.internalId) }
            await generateTranslation(hadith, requestedLanguage: requestedLanguage)
        }
    }

    func resetTranslationRequestsForAccount() {
        cancelScrollProgress()
        automaticTranslationTask?.cancel()
        automaticRequests = ReaderAutomaticTranslationLedger()
        translationAllowances = [:]
        translations = translations.filter { _, state in
            if case .loaded = state { return true }
            return false
        }
        for task in generationTasks.values { task.cancel() }
        generationTasks = [:]
        refreshAutomaticTranslationPreference()
    }

    var hasQuotaFailure: Bool {
        translations.values.contains { state in
            if case .failed(.quotaExceeded) = state { return true }
            return false
        }
    }

    /// Purchase retry resumes only the hadiths explicitly rejected at quota.
    func retryTranslationsAfterPurchase() {
        let requested = currentPageHadiths.filter { hadith in
            if case .failed(.quotaExceeded) = translations[hadith.internalId] { return true }
            return false
        }
        for hadith in requested { retryTranslation(for: hadith) }
    }

    // MARK: - Translation contributions

    var canContribute: Bool { isSignedIn() }

    func reportTranslation(_ translation: ReaderTranslation, reason: String) async throws {
        let _: TranslationReportResult = try await convex.action(
            "actions/ai:reportTranslation",
            with: [
                "translationId": translation.translationId as ConvexEncodable?,
                "reason": reason as ConvexEncodable?,
            ]
        )
    }

    // MARK: - Saved data (bookmarks / favorites / notes / progress)

    func ref(for hadith: ReaderHadith) -> HadithRef {
        HadithRef(
            hadithId: hadith._id,
            collectionSlug: hadith.collectionSlug,
            collectionName: hadith.collectionName,
            volumeId: selectedVolumeId,
            hadithNumber: hadith.providerHadithId,
            arabicText: hadith.arabicText,
            englishText: hadith.englishText,
            referenceDisplay: hadith.referenceDisplay
        )
    }

    func isBookmarked(_ hadith: ReaderHadith) -> Bool {
        #if DEBUG
        if uitestSavedStateSeeded { return uitestBookmarkedIds.contains(hadith._id) }
        #endif
        return library?.isBookmarked(hadithId: hadith._id) ?? false
    }

    func isFavorite(_ hadith: ReaderHadith) -> Bool {
        #if DEBUG
        if uitestSavedStateSeeded { return uitestFavoritedIds.contains(hadith._id) }
        #endif
        return library?.isFavorite(hadithId: hadith._id) ?? false
    }

    func savedItem(for hadith: ReaderHadith) -> SavedItemEntry? {
        library?.savedItems.first { $0.hadithId == hadith._id }
    }

    func restoreBookmark(_ hadith: ReaderHadith, createdAt: Date) { library?.restoreBookmark(ref(for: hadith), createdAt: createdAt) }
    func restoreFavorite(_ hadith: ReaderHadith, createdAt: Date) { library?.restoreFavorite(ref(for: hadith), createdAt: createdAt) }

    func toggleBookmark(_ hadith: ReaderHadith) {
        let adding = !isBookmarked(hadith)
        library?.toggleBookmark(ref(for: hadith))
        ReaderHapticDispatcher.trigger(adding ? .bookmarkAdd : .bookmarkRemove)
    }

    func toggleFavorite(_ hadith: ReaderHadith) {
        let adding = !isFavorite(hadith)
        library?.toggleFavorite(ref(for: hadith))
        ReaderHapticDispatcher.trigger(adding ? .favoriteAdd : .favoriteRemove)
    }

    var libraryActionScope: UUID? { library?.actionScope }
    func isLibraryActionCurrent(_ captured: UUID?) -> Bool { library?.isActionCurrent(captured) ?? false }

    @discardableResult func saveNote(_ hadith: ReaderHadith, content: String) -> Bool {
        library?.saveNote(ref(for: hadith), content: content) ?? false
    }

    func noteContent(for hadith: ReaderHadith) -> String? {
        #if DEBUG
        if uitestSavedStateSeeded, uitestNotedIds.contains(hadith._id) { return "Fixture note" }
        #endif
        return library?.notes.first { $0.hadith?.hadithId == hadith._id }?.noteContent
    }

    /// Persists the position of the first hadith on the current page. Runs
    /// on every page turn and when the reader closes; the backend upserts
    /// per collection so repeats stay cheap.
    func saveCurrentProgress() {
        saveCurrentProgress(capturedAt: nil)
    }

    private func saveCurrentProgress(capturedAt: Double?) {
        cancelScrollProgress()
        guard phase == .reading, pages.indices.contains(pageIndex) else { return }
        let page = pages[pageIndex]
        guard let first = page.items.first else { return }
        let effectivePosition = recentPosition(for: pageIndex)?.position ?? restoredPosition
        let restoredHadith = effectivePosition.flatMap { position in
            page.items.first(where: {
                $0.provider == position.anchor.provider
                    && $0.collectionSlug == position.anchor.collectionSlug
                    && $0.providerHadithId == position.anchor.providerHadithId
            })
        }
        let landingHadith = landingHadithNumber.flatMap { number in
            page.items.first { $0.providerHadithId == number }
        }
        let stableHadith = lastStableAnchor.flatMap { stable in
            page.items.first { $0.internalId == stable.internalId }
        }
        let rawPageOffset: Double
        let normalizedOffset: Double
        if stableHadith != nil {
            rawPageOffset = lastStableRawPageOffset
            normalizedOffset = lastStableNormalizedOffset
        } else if restoredHadith != nil {
            rawPageOffset = effectivePosition?.rawPageOffset ?? 0
            normalizedOffset = effectivePosition?.normalizedOffset ?? 0
        } else {
            rawPageOffset = 0
            normalizedOffset = 0
        }
        saveProgress(
            anchor: stableHadith ?? restoredHadith ?? landingHadith ?? first,
            page: page,
            rawPageOffset: rawPageOffset,
            normalizedOffset: normalizedOffset,
            capturedAt: capturedAt
        )
    }

    func setViewportActive(_ active: Bool, id: UUID) {
        if active {
            activeViewportIDs.insert(id)
            library?.setReaderViewportActive(true, id: id)
        } else if activeViewportIDs.remove(id) != nil {
            lastViewportMotionUptime = ProcessInfo.processInfo.systemUptime
            library?.setReaderViewportActive(false, id: id)
        }
    }

    func endViewportInteractions() {
        guard !activeViewportIDs.isEmpty else { return }
        let active = activeViewportIDs
        activeViewportIDs.removeAll()
        lastViewportMotionUptime = ProcessInfo.processInfo.systemUptime
        for id in active { library?.setReaderViewportActive(false, id: id) }
    }

    /// The scroll view reports its leading visible hadith after it has settled.
    /// Tiny layout updates are ignored so reading does not create a write storm.
    func captureStableScroll(
        hadiths: [ReaderHadith],
        leadingIndex: Int,
        rawPageOffset: Double,
        normalizedOffset: Double,
        atHeader: Bool = false,
        viewport: ReaderViewportSnapshot? = nil
    ) {
        guard verticalLanding == nil else { return }
        guard hadiths.indices.contains(leadingIndex), pages.indices.contains(pageIndex),
              hadiths.map(\.internalId) == pages[pageIndex].items.map(\.internalId) else { return }
        lastViewportMotionUptime = ProcessInfo.processInfo.systemUptime
        library?.noteReaderViewportMotion(at: lastViewportMotionUptime)
        let anchor = hadiths[leadingIndex]
        let clamped = min(1, max(0, normalizedOffset))
        lastStableAnchor = anchor
        lastStableRawPageOffset = max(0, rawPageOffset)
        lastStableNormalizedOffset = clamped
        rememberPosition(anchor: anchor, page: pages[pageIndex], normalizedOffset: clamped, atHeader: atHeader, viewport: viewport)
        let capturedAt = nextPositionUpdatedAt()
        if pendingScrollSave != nil { pendingScrollSave?.updatedAt = capturedAt }
        if lastCapturedAnchor == anchor.internalId,
           let lastCapturedNormalizedOffset,
           abs(lastCapturedNormalizedOffset - clamped) < 0.02 {
            return
        }
        // Any real vertical scroll collapses to the focused view with no
        // haptic. The very first capture after a page loads is the initial
        // settle, not a scroll, so it never collapses.
        if lastCapturedAnchor != nil {
            collapseToFocused()
        }
        lastCapturedAnchor = anchor.internalId
        lastCapturedNormalizedOffset = clamped
        saveProgress(
            anchor: anchor,
            page: pages[pageIndex],
            rawPageOffset: max(0, rawPageOffset),
            normalizedOffset: clamped,
            coalescingScroll: true,
            capturedAt: capturedAt
        )
    }

    private func requestHeaderLanding(for page: Int) {
        guard let volumeId = selectedVolumeId else { return }
        requestVerticalLanding(.header, volumeId: volumeId, page: page)
    }

    /// Explicit entry targets take priority over temporary recent-page positions.
    private func requestEntryLanding(for page: Int) {
        guard let volumeId = selectedVolumeId,
              pages.indices.contains(page)
        else { return }
        recentPositions.removeAll { $0.volumeId == volumeId && $0.pageIndex == page }
        let items = pages[page].items
        if let position = restoredPosition,
           items.contains(where: { $0.providerHadithId == position.anchor.providerHadithId }) {
            requestVerticalLanding(
                .semantic(
                    providerHadithId: position.anchor.providerHadithId,
                    normalizedOffset: position.normalizedOffset
                ),
                volumeId: volumeId,
                page: page
            )
        } else if let hadith = landingHadithNumber,
                  items.contains(where: { $0.providerHadithId == hadith }) {
            requestVerticalLanding(.semantic(providerHadithId: hadith, normalizedOffset: 0), volumeId: volumeId, page: page)
        } else {
            requestHeaderLanding(for: page)
        }
    }

    private func requestVerticalLanding(
        _ landing: ReaderVerticalLanding,
        volumeId: String,
        page: Int
    ) {
        nextVerticalLandingToken += 1
        verticalLanding = ReaderVerticalLandingRequest(
            id: nextVerticalLandingToken,
            page: .init(volumeId: volumeId, pageIndex: page),
            landing: landing
        )
    }

    func acknowledgeVerticalLanding(_ request: ReaderVerticalLandingRequest) {
        guard verticalLanding == request else { return }
        verticalLanding = nil
    }
    /// Compact top progress fraction (R4): the visible page over the known
    /// total. Nil when the backend has not reported a total yet.
    var compactProgressFraction: Double? {
        guard let total = totalPages, total > 0 else { return nil }
        return Double(pageIndex + 1) / Double(total)
    }

    /// Re-issues restoration against the current layout signature (R4). After
    /// a font, size, visibility, or locale change the raw offset is stale; the
    /// last stable semantic anchor recovers the exact position.
    func reanchorAfterLayoutChange() {
        invalidateAutomaticTranslationVisibility()
        guard phase == .reading,
              pages.indices.contains(pageIndex),
              let anchor = lastStableAnchor,
              pages[pageIndex].items.contains(where: { $0.internalId == anchor.internalId })
        else { return }
        let page = pages[pageIndex]
        restoredPosition = Self.reanchoredPosition(
            anchor: anchor,
            page: page,
            volumeId: anchor.volumeId ?? selectedVolumeId ?? "unknown",
            rawPageOffset: lastStableRawPageOffset,
            normalizedOffset: lastStableNormalizedOffset,
            layout: readingLayout(page.paginationVersion ?? 1)
        )
        if let volumeId = selectedVolumeId {
            requestVerticalLanding(
                .semantic(providerHadithId: anchor.providerHadithId, normalizedOffset: lastStableNormalizedOffset),
                volumeId: volumeId,
                page: pageIndex
            )
        }
    }

    /// The pure projection behind `reanchorAfterLayoutChange`: rebuilds a V1
    /// position for the stable anchor against the new layout signature.
    nonisolated static func reanchoredPosition(
        anchor: ReaderHadith,
        page: ReaderPageResult,
        volumeId: String?,
        rawPageOffset: Double,
        normalizedOffset: Double,
        layout: ReadingLayout
    ) -> ReadingPosition {
        ReadingPosition(
            anchor: .init(
                provider: anchor.provider,
                collectionSlug: anchor.collectionSlug,
                providerHadithId: anchor.providerHadithId
            ),
            contentVersion: page.contentVersion ?? "legacy",
            volumeId: volumeId ?? "unknown",
            chapterId: anchor.chapterId,
            pageKey: page.pageKey ?? "legacy",
            displayPageIndex: Double(max(1, page.page)),
            rawPageOffset: rawPageOffset,
            normalizedOffset: normalizedOffset,
            layoutSignature: layout.signature,
            updatedAt: 0
        )
    }

    private func readingLayout(_ paginationVersion: Double) -> ReadingLayout {
        let preferences = currentPreferences()
        return ReadingLayout(
            locale: preferences.translationLocale,
            arabicVisible: preferences.arabicVisible,
            translationVisible: preferences.translationVisible,
            arabicFontId: preferences.arabicFont.rawValue,
            arabicFontSize: preferences.arabicFontSize,
            widthClass: widthClass,
            paginationVersion: paginationVersion,
            translationFontSize: preferences.translationFontSize
        )
    }

    private func saveProgress(
        anchor: ReaderHadith,
        page: ReaderPageResult,
        rawPageOffset: Double,
        normalizedOffset: Double,
        coalescingScroll: Bool = false,
        capturedAt: Double? = nil
    ) {
        guard let library else { return }
        if coalescingScroll {
            pendingScrollSave = (scope: library.actionScope, updatedAt: capturedAt ?? nextPositionUpdatedAt())
            if scrollProgressTask == nil {
                scrollProgressTask = Task { [weak self] in
                    while let self {
                        guard let pendingScrollSave, library.isActionCurrent(pendingScrollSave.scope) else {
                            cancelScrollProgress()
                            return
                        }
                        let delay = activeViewportIDs.isEmpty
                            ? lastViewportMotionUptime + 0.5 - ProcessInfo.processInfo.systemUptime : 0.5
                        if delay > 0 {
                            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                        } else {
                            do { try await library.waitForReaderQuiet() } catch { return }
                            guard !Task.isCancelled else { return }
                            if activeViewportIDs.isEmpty,
                               ProcessInfo.processInfo.systemUptime >= lastViewportMotionUptime + 0.5 {
                                flushScrollProgress()
                                return
                            }
                        }
                    }
                }
            }
            return
        }
        let layout = readingLayout(page.paginationVersion ?? 1)
        let updatedAt = capturedAt ?? nextPositionUpdatedAt()
        let position = ReadingPosition(
            anchor: .init(
                provider: anchor.provider,
                collectionSlug: anchor.collectionSlug,
                providerHadithId: anchor.providerHadithId
            ),
            contentVersion: page.contentVersion ?? "legacy",
            volumeId: anchor.volumeId ?? selectedVolumeId ?? "unknown",
            chapterId: anchor.chapterId,
            pageKey: page.pageKey ?? "legacy",
            displayPageIndex: Double(max(1, page.page)),
            rawPageOffset: rawPageOffset,
            normalizedOffset: normalizedOffset,
            layoutSignature: layout.signature,
            updatedAt: updatedAt
        )
        library.saveProgress(position, ref: ref(for: anchor))
    }

    private func nextPositionUpdatedAt() -> Double {
        let storedUpdatedAt = library?.latestPositionTimestamp(for: collectionSlug) ?? 0
        let updatedAt = max(Date.now.millisecondsSinceEpoch, max(storedUpdatedAt + 1, lastPositionUpdatedAt + 1))
        lastPositionUpdatedAt = updatedAt
        return updatedAt
    }

    private func cancelScrollProgress() {
        scrollProgressTask?.cancel()
        scrollProgressTask = nil
        pendingScrollSave = nil
    }

    private func flushScrollProgress() {
        let pending = pendingScrollSave
        cancelScrollProgress()
        guard let pending, let library, library.isActionCurrent(pending.scope) else { return }
        let interval = ReaderScrollProfile.begin("ScrollProgressPersistence")
        defer { ReaderScrollProfile.end("ScrollProgressPersistence", interval) }
        saveCurrentProgress(capturedAt: pending.updatedAt)
    }
}


@MainActor
final class ReaderPageContentStore {
    struct Request: Hashable {
        let collection: String
        let volume: String
        let index: Int
        var target: String? = nil
    }

    private struct Slot: Hashable {
        let collection: String
        let volume: String
        let index: Int
    }

    private struct Identity: Equatable {
        let key: String
        let version: String
        let pagination: Double
        let providers: [String]
    }

    private struct Entry {
        let identity: Identity
        let page: ReaderPageResult
        let sequence: Int
        let storedAt: Date
    }

    private struct Flight {
        let task: Task<ReaderPageResult, Error>
        let sequence: Int
        let generation: Int
    }

    typealias Fetch = (Request) async throws -> ReaderPageResult
    private let fetch: Fetch
    private let capacity: Int
    private var entries: [Slot: Entry] = [:]
    private var order: [Slot] = []
    private var flights: [Request: Flight] = [:]
    private var latestSequences: [Slot: Int] = [:]
    private var sequenceOrder: [Slot] = []
    private var oldestAcceptedSequence = 0
    private var sequence = 0
    private var generation = 0
    private var reading = false
    private struct Volume: Hashable { let collection: String; let volume: String }
    private struct Coverage {
        var loaded = IndexSet()
        let total: Int
        var first: String?
        var last: String?
    }
    private var coverage: [Volume: Coverage] = [:]
    private var paginationByCollection: [String: (version: Double, sequence: Int)] = [:]
    private(set) var observedIdentityChanges = 0

    init(capacity: Int = 28, fetch: @escaping Fetch) {
        self.capacity = max(1, capacity)
        self.fetch = fetch
    }

    convenience init(convex: ConvexClientWithAuth<String>) {
        self.init { request in
            var arguments: [String: ConvexEncodable?] = [
                "collectionSlug": request.collection as ConvexEncodable?,
                "volumeId": request.volume as ConvexEncodable?,
                "page": Double(request.index + 1) as ConvexEncodable?,
            ]
            if let target = request.target { arguments["targetHadithNumber"] = target as ConvexEncodable? }
            return try await convex.action("actions/hadithData:getReaderPage", with: arguments)
        }
    }

    func beginReading() {
        if !reading { expireEntryWarmth() }
        reading = true
    }

    func clear() {
        generation += 1
        for flight in flights.values { flight.task.cancel() }
        flights.removeAll()
        entries.removeAll()
        order.removeAll()
        latestSequences.removeAll()
        sequenceOrder.removeAll()
        paginationByCollection.removeAll()
        coverage.removeAll()
        reading = false
    }

    private func expireEntryWarmth() {
        let expired = entries.filter { Date().timeIntervalSince($0.value.storedAt) > 120 }.map(\.key)
        for key in expired { entries[key] = nil; order.removeAll { $0 == key } }
    }

    func knownRange(collection: String, volume: String) -> (first: String, last: String)? {
        guard let known = coverage[Volume(collection: collection, volume: volume)],
              known.loaded.count == known.total, let first = known.first, let last = known.last else { return nil }
        return (first, last)
    }

    private func rememberCoverage(_ page: ReaderPageResult, request: Request) {
        let index = page.page - 1
        guard index >= 0, index < page.totalPages, !page.items.isEmpty else { return }
        let key = Volume(collection: request.collection, volume: request.volume)
        var known = coverage[key].flatMap { $0.total == page.totalPages ? $0 : nil } ?? Coverage(total: page.totalPages)
        known.loaded.insert(index)
        if index == 0 { known.first = page.items.first?.providerHadithId }
        if index == page.totalPages - 1 { known.last = page.items.last?.providerHadithId }
        coverage[key] = known
    }

    func isCompatible(_ page: ReaderPageResult, collection: String) -> Bool {
        paginationByCollection[collection].map { $0.version == page.paginationVersion } ?? true
    }

    func peek(collection: String, volume: String, index: Int) -> ReaderPageResult? {
        if !reading { expireEntryWarmth() }
        let slot = Slot(collection: collection, volume: volume, index: index)
        guard let entry = entries[slot] else { return nil }
        touch(slot)
        return entry.page
    }

    func cachedRequest(_ request: Request) -> ReaderPageResult? {
        if !reading { expireEntryWarmth() }
        guard let target = request.target else {
            return peek(collection: request.collection, volume: request.volume, index: request.index)
        }
        guard let hit = entries.filter({ $0.key.collection == request.collection && $0.key.volume == request.volume
            && $0.value.page.items.contains { $0.providerHadithId == target } }).max(by: { $0.value.sequence < $1.value.sequence }) else { return nil }
        touch(hit.key)
        return hit.value.page
    }

    func peekLast(collection: String, volume: String) -> ReaderPageResult? {
        guard let slot = entries.filter({ $0.key.collection == collection && $0.key.volume == volume
            && $0.key.index == $0.value.page.totalPages - 1 }).max(by: { $0.value.sequence < $1.value.sequence })?.key else { return nil }
        return peek(collection: collection, volume: volume, index: slot.index)
    }

    var contextVersion: Int { generation }

    func load(_ request: Request, fetch override: Fetch? = nil, expectedVersion: Int? = nil) async throws -> ReaderPageResult {
        try Task.checkCancellation()
        guard expectedVersion == nil || expectedVersion == generation else { throw CancellationError() }
        if let hit = cachedRequest(request) {
            try Task.checkCancellation()
            return hit
        }
        let flight: Flight
        if let existing = flights[request] { flight = existing }
        else {
            if flights.count >= 4 {
                let waitingGeneration = generation
                try await Task.sleep(for: .milliseconds(25))
                return try await load(request, fetch: override, expectedVersion: waitingGeneration)
            }
            sequence += 1
            let loader = override ?? fetch
            let task = Task { try await OfflineModels.withFetchTimeout(seconds: 10) { try await loader(request) } }
            flight = Flight(task: task, sequence: sequence, generation: generation)
            flights[request] = flight
        }
        do {
            let page = try await flight.task.value
            guard flight.generation == generation, !flight.task.isCancelled,
                  flight.sequence >= oldestAcceptedSequence else { throw CancellationError() }
            if flights[request]?.sequence == flight.sequence { flights[request] = nil }
            let slot = Slot(collection: request.collection, volume: request.volume, index: max(0, page.page - 1))
            if let latest = latestSequences[slot], latest > flight.sequence {
                guard let current = entries[slot], request.target.map({ target in current.page.items.contains { $0.providerHadithId == target } }) ?? true else { throw CancellationError() }
                try Task.checkCancellation()
                return current.page
            }
            if page.page > 0, let key = page.pageKey, key != "legacy",
               let version = page.contentVersion, version != "legacy", let pagination = page.paginationVersion {
                if let prior = paginationByCollection[request.collection], prior.version != pagination {
                    guard prior.sequence <= flight.sequence else { throw CancellationError() }
                    coverage = coverage.filter { $0.key.collection != request.collection }
                    let obsolete = entries.keys.filter { $0.collection == request.collection }
                    for key in obsolete { entries[key] = nil; order.removeAll { $0 == key } }
                }
                if (paginationByCollection[request.collection]?.sequence ?? -1) < flight.sequence {
                    paginationByCollection[request.collection] = (pagination, flight.sequence)
                }
                rememberCoverage(page, request: request)
                let identity = Identity(key: key, version: version, pagination: pagination,
                    providers: page.items.map { "\($0.provider)|\($0.internalId)|\($0.id)" })
                if let prior = entries[slot], prior.identity != identity { observedIdentityChanges += 1; entries[slot] = nil }
                entries[slot] = Entry(identity: identity, page: page, sequence: flight.sequence, storedAt: Date())
                latestSequences[slot] = flight.sequence
                sequenceOrder.removeAll { $0 == slot }; sequenceOrder.append(slot)
                while sequenceOrder.count > capacity * 2 {
                    let removed = sequenceOrder.removeFirst()
                    oldestAcceptedSequence = max(oldestAcceptedSequence, latestSequences.removeValue(forKey: removed) ?? 0)
                }
                touch(slot)
                while order.count > capacity { entries[order.removeFirst()] = nil }
            }
            try Task.checkCancellation()
            return page
        } catch {
            if flight.generation == generation, flights[request]?.sequence == flight.sequence { flights[request] = nil }
            throw error
        }
    }

    private func touch(_ slot: Slot) { order.removeAll { $0 == slot }; order.append(slot) }

#if DEBUG
    var retainedPageCount: Int { entries.count }
    var inFlightPageCount: Int { flights.count }
#endif
}
