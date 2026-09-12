import ConvexMobile
import Foundation
import Observation

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

    // Reading state
    private(set) var phase: Phase = .loadingOutline
    private(set) var volumes: [OutlineVolume] = []
    private(set) var pages: [ReaderPageResult] = []
    private(set) var selectedVolumeId: String?
    private(set) var isLoadingPage = false
    var pageIndex = 0 {
        didSet {
            guard oldValue != pageIndex else { return }
            snapshotScrollOffset(for: oldValue)
            restoreScrollOffset(for: pageIndex)
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
    private(set) var language: String

    private var outlineTask: Task<Void, Never>?
    private var pageTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?
    private var translationGeneration = 0
    private var lastPositionUpdatedAt = 0.0
    private var lastCapturedAnchor: String?
    private var lastCapturedNormalizedOffset: Double?
    private var lastStableAnchor: ReaderHadith?
    /// Volumes whose first page was already background-cached since the
    /// outline loaded (R6 round 3 adjacent prefetch).
    private var warmedVolumeIds: Set<String> = []
    private var lastStableRawPageOffset: Double = 0
    private var lastStableNormalizedOffset: Double = 0
    private(set) var restoredPosition: ReadingPosition?
    /// Bumped every time the model re-issues restoration (layout-preference
    /// changes re-anchor the semantic position). Views key their applied
    /// restoration on this so a preference change re-scrolls exactly once.
    private(set) var restorationGeneration = 0

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
    /// Round 5: vertical scroll offsets of the last two visited pages,
    /// keyed by page index. Leaving a page stores its offset; navigating
    /// back restores the exact offset instead of jumping to the top. The
    /// R1/R2 semantic save/restore still runs on settle underneath.
    private(set) var pageScrollCache: [Int: PageScrollSnapshot] = [:]
    private var pageScrollCacheOrder: [Int] = []
    /// Transient restore target for the current page: set when the reader
    /// lands on a cached page, nil otherwise. Consumed once by the page
    /// view's restoration path (keyed by `scrollRestoreGeneration`).
    private(set) var scrollRestoreSnapshot: PageScrollSnapshot?
    private(set) var scrollRestoreGeneration = 0

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
        widthClass: ReadingWidthClass = .compact
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
        guard case .loadingOutline = phase, outlineTask == nil else { return }
        outlineTask = Task { [weak self] in
            await self?.loadOutline()
        }
    }

    func stop() {
        outlineTask?.cancel()
        pageTask?.cancel()
        translationTask?.cancel()
        outlineTask = nil
        pageTask = nil
        translationTask = nil
    }

    private func loadOutline() async {
        do {
            let result: CollectionOutlineResult = try await convex.action(
                "actions/hadithData:getCollectionOutline",
                with: ["collectionSlug": collectionSlug as ConvexEncodable?]
            )
            volumes = result.volumes
            warmedVolumeIds = []
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
            phase = .failed(ReaderModels.errorMessage(of: error))
        }
        outlineTask = nil
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
        guard volumeId != selectedVolumeId else { return }
        // The R1 position of the page being left is saved before the
        // switch, exactly like the pill/swipe cross-volume path below.
        saveCurrentProgress()
        collapseToFocused()
        selectedVolumeId = volumeId
        resetReading()
        Task { await loadPage(0, volumeId: volumeId) }
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
                pageIndex += 1
            } else if index == pageIndex - 1, hasPreviousPage {
                pageIndex -= 1
            }
        case .volumeFirst(let volumeId):
            switchToVolume(volumeId, edge: .first)
        case .volumeLast(let volumeId):
            switchToVolume(volumeId, edge: .last)
        }
    }    /// Jumps to the first (or last) page of another volume. Saves the R1
    /// position of the page being left first; after the new volume's pages
    /// arrive, the exact R2 target (page 1, or the last page) is restored
    /// and saved, so the reader never strands on a stale page. While a
    /// first-visit volume fetches, the page is empty and the reader shows
    /// its loading state.
    func switchToVolume(_ volumeId: String, edge: VolumeEdge) {
        guard volumeId != selectedVolumeId else { return }
        guard volumes.contains(where: { $0.volumeId == volumeId }) else { return }
        saveCurrentProgress()
        collapseToFocused()
        selectedVolumeId = volumeId
        resetReading()
        landingHadithNumber = nil
        restoredPosition = nil
        pageTask = Task { [weak self] in
            await self?.loadVolumeEdge(volumeId, edge: edge)
        }
    }

    /// Loads a volume edge: page 1 for `.first`; for `.last` the first page
    /// is read only to learn the total, then the last page is fetched and
    /// published together so no intermediate page flashes.
    private func loadVolumeEdge(_ volumeId: String, edge: VolumeEdge) async {
        if isLoadingPage { return }
        isLoadingPage = true
        var shouldPrefetchNeighbor = false
        defer {
            isLoadingPage = false
            // The next page must be fetched only after the edge request
            // releases its single-flight lock. That gives the first page a
            // real in-volume swipe preview instead of a loading slot.
            if shouldPrefetchNeighbor {
                prefetchForwardIfNeeded()
            }
        }
        do {
            let first = try await fetchReaderPage(0, volumeId: volumeId)
            guard !Task.isCancelled else { return }
            let total = max(1, first.totalPages)
            switch edge {
            case .first:
                pages = [first]
                phase = .reading
                pageIndex = 0
                shouldPrefetchNeighbor = true
            case .last:
                let landingIndex = total - 1
                if landingIndex == 0 {
                    pages = [first]
                } else {
                    let last = try await fetchReaderPage(landingIndex, volumeId: volumeId)
                    guard !Task.isCancelled else { return }
                    var filled = (0..<landingIndex).map { _ in emptyPage() }
                    filled.append(last)
                    _ = first
                    pages = filled
                }
                phase = .reading
                pageIndex = landingIndex
            }
            scheduleTranslationsForCurrentPage()
            saveCurrentProgress()
            warmAdjacentVolumes()
        } catch is CancellationError {
            // A newer page or volume target replaces this fetch.
        } catch {
            if !Task.isCancelled, pages.isEmpty {
                phase = .failed(ReaderModels.errorMessage(of: error))
            }
        }
    }

    /// One Convex reader-page fetch without publishing, shared by the
    /// edge loader. `loadPage` keeps its own publish path unchanged.
    private func fetchReaderPage(_ index: Int, volumeId: String) async throws -> ReaderPageResult {
        try await convex.action(
            "actions/hadithData:getReaderPage",
            with: [
                "collectionSlug": collectionSlug as ConvexEncodable?,
                "volumeId": volumeId as ConvexEncodable?,
                "page": Double(index + 1) as ConvexEncodable?,
            ]
        )
    }

#if DEBUG
    /// Seeds outline state for the R5 contents fixture without network.
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
        Task { await loadPage(0, volumeId: volumeId, jumpToHadithNumber: chapter.firstProviderHadithId) }
    }

    /// R5 jump-to-reference: validates the number against the canonical
    /// hadith-id pattern and navigates through the same volume-locator path
    /// as canonical links. Well-formed but stale numbers fall back to the
    /// first volume's start, exactly like a stale canonical link. Returns
    /// false for malformed input so the sheet can keep itself open with an
    /// inline error.
    @discardableResult
    func jumpToReference(_ number: String) -> Bool {
        let trimmed = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ReaderShare.isValidReferenceNumber(trimmed) else { return false }
        collapseToFocused()
        if let volume = Self.volumeId(forHadithNumber: trimmed, in: volumes) {
            selectedVolumeId = volume
            resetReading()
            landingHadithNumber = trimmed
            restoredPosition = nil
            Task { await loadPage(0, volumeId: volume, jumpToHadithNumber: trimmed) }
        } else {
            landingHadithNumber = nil
            restoredPosition = nil
            guard let first = volumes.first?.volumeId else { return true }
            selectedVolumeId = first
            resetReading()
            Task { await loadPage(0, volumeId: first) }
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
            Task { [weak self] in await self?.loadPage(0, volumeId: volumeId, jumpToHadithNumber: trimmed) }
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

    private func resetReading() {
        pageTask?.cancel()
        translationTask?.cancel()
        pageTask = nil
        translationTask = nil
        translationGeneration += 1
        pages = []
        pageIndex = 0
        translations = [:]
        lastCapturedAnchor = nil
        lastCapturedNormalizedOffset = nil
        // A volume/jump change invalidates every cached offset: anchors
        // belong to the previous volume's pages.
        lastStableAnchor = nil
        lastStableRawPageOffset = 0
        lastStableNormalizedOffset = 0
        pageScrollCache = [:]
        pageScrollCacheOrder = []
        scrollRestoreSnapshot = nil
    }

    func setLanguage(_ code: String) {
        guard code != language else { return }
        language = code
        translationTask?.cancel()
        translationGeneration += 1
        translations = [:]
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
        isLoadingPage = true
        var shouldPrefetchNeighbor = false
        defer {
            isLoadingPage = false
            // `prefetchForwardIfNeeded` used to run while this request still
            // held `isLoadingPage`, so the reader always exposed a loading
            // neighbor. Run it after publication and lock release instead.
            if shouldPrefetchNeighbor {
                prefetchForwardIfNeeded()
            }
        }
        do {
            var args: [String: ConvexEncodable?] = [
                "collectionSlug": collectionSlug as ConvexEncodable?,
                "volumeId": volumeId as ConvexEncodable?,
                "page": Double(index + 1) as ConvexEncodable?,
            ]
            if let jumpToHadithNumber {
                args["targetHadithNumber"] = jumpToHadithNumber as ConvexEncodable?
            }
            let result: ReaderPageResult = try await convex.action(
                "actions/hadithData:getReaderPage",
                with: args
            )

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
                    scheduleTranslationsForCurrentPage()
                    saveCurrentProgress()
                    warmAdjacentVolumes()
                    shouldPrefetchNeighbor = true
                }
            }
        } catch {
            if pages.isEmpty {
                phase = .failed(ReaderModels.errorMessage(of: error))
            }
        }
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
        guard let lastPage = pages.last, lastPage.hasMore else { return }
        guard pageIndex >= pages.count - 1 else { return }
        pageTask?.cancel()
        pageTask = Task { await loadPage(pages.count, volumeId: volumeId) }
    }

    /// Background-caches the first page of the adjacent volumes so
    /// page/volume switches never wait. Bounded to the nearest neighbors,
    /// silent (no loading state, results discarded — the server action is
    /// cache-first), offline-tolerant (errors swallowed), and skipped for
    /// volumes already warmed since the outline loaded.
    func warmAdjacentVolumes() {
        let targets = ReaderPrefetchTargets.adjacentVolumeIds(
            volumes: volumes,
            selectedVolumeId: selectedVolumeId
        ).filter { !warmedVolumeIds.contains($0) }
        guard !targets.isEmpty else { return }
        for volumeId in targets { warmedVolumeIds.insert(volumeId) }
        Task { [weak self] in
            guard let self else { return }
            for volumeId in targets {
                _ = try? await self.fetchReaderPage(0, volumeId: volumeId) as ReaderPageResult
            }
        }
    }

    // MARK: - Translations

    private func scheduleTranslationsForCurrentPage() {
        guard language != "en" else { return }
        guard pages.indices.contains(pageIndex) else { return }
        let hadiths = pages[pageIndex].items
        guard !hadiths.isEmpty else { return }

        translationGeneration += 1
        let generation = translationGeneration
        translationTask?.cancel()
        translationTask = Task { [weak self] in
            for hadith in hadiths {
                guard !Task.isCancelled else { return }
                await self?.translateIfNeeded(hadith, generation: generation)
            }
        }
    }

    private func translateIfNeeded(_ hadith: ReaderHadith, generation: Int) async {
        if translations[hadith.internalId] != nil { return }
        guard isSignedIn() else {
            translations[hadith.internalId] = .failed(.requiresSignIn)
            return
        }
        translations[hadith.internalId] = .loading
        do {
            let result: ReaderTranslation = try await convex.action(
                "actions/ai:translateHadith",
                with: [
                    "hadithInternalId": hadith.internalId as ConvexEncodable?,
                    "targetLanguage": language as ConvexEncodable?,
                ]
            )
            guard generation == translationGeneration, !Task.isCancelled else { return }
            translations[hadith.internalId] = .loaded(result)
        } catch {
            guard generation == translationGeneration, !Task.isCancelled else { return }
            let failure = TranslationFailure(error: error)
            translations[hadith.internalId] = .failed(failure)
            // A hard wall (quota, sign-in) applies to the rest of the page;
            // stop burning calls and let the rows surface the state.
            if failure == .quotaExceeded || failure == .requiresSignIn {
                translationTask?.cancel()
            }
        }
    }

    /// Manual retry from a failed translation row.
    func retryTranslation(for hadith: ReaderHadith) {
        translationTask?.cancel()
        translationTask = Task { [weak self] in
            await self?.translateIfNeeded(hadith, generation: self?.translationGeneration ?? 0)
        }
    }

    var hasQuotaFailure: Bool {
        translations.values.contains { state in
            if case .failed(.quotaExceeded) = state { return true }
            return false
        }
    }

    /// RevenueCat unlocks asynchronously through the signed webhook. Clear
    /// the local wall and retry the current page after a successful purchase;
    /// if webhook propagation is still in flight the backend remains final.
    func retryTranslationsAfterPurchase() {
        translations = translations.filter { _, state in
            if case .failed(.quotaExceeded) = state { return false }
            return true
        }
        scheduleTranslationsForCurrentPage()
    }

    // MARK: - Translation contributions

    var canContribute: Bool { isSignedIn() }

    func submitTranslation(
        for hadith: ReaderHadith,
        proposedContent: String,
        replacing translation: ReaderTranslation?
    ) async throws -> TranslationSubmissionResult {
        var args: [String: ConvexEncodable?] = [
            "hadithInternalId": hadith.internalId as ConvexEncodable?,
            "language": language as ConvexEncodable?,
            "proposedContent": proposedContent as ConvexEncodable?,
        ]
        if let translation {
            args["replacesTranslationId"] = translation.translationId as ConvexEncodable?
        }
        return try await convex.action(
            "actions/ai:submitTranslation",
            with: args
        )
    }

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

    private func ref(for hadith: ReaderHadith) -> HadithRef {
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

    func saveNote(_ hadith: ReaderHadith, content: String) {
        library?.saveNote(ref(for: hadith), content: content)
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
        guard phase == .reading, pages.indices.contains(pageIndex) else { return }
        let page = pages[pageIndex]
        guard let first = page.items.first else { return }
        let restoredHadith = restoredPosition.flatMap { position in
            page.items.first(where: {
                $0.provider == position.anchor.provider
                    && $0.collectionSlug == position.anchor.collectionSlug
                    && $0.providerHadithId == position.anchor.providerHadithId
            })
        }
        let landingHadith = landingHadithNumber.flatMap { number in
            page.items.first { $0.providerHadithId == number }
        }
        let usesRestoredOffset = restoredHadith != nil
        saveProgress(
            anchor: restoredHadith ?? landingHadith ?? first,
            page: page,
            rawPageOffset: usesRestoredOffset ? restoredPosition?.rawPageOffset ?? 0 : 0,
            normalizedOffset: usesRestoredOffset ? restoredPosition?.normalizedOffset ?? 0 : 0
        )
    }

    /// The scroll view reports its leading visible hadith after it has settled.
    /// Tiny layout updates are ignored so reading does not create a write storm.
    func captureStableScroll(
        hadiths: [ReaderHadith],
        leadingIndex: Int,
        rawPageOffset: Double,
        normalizedOffset: Double
    ) {
        guard hadiths.indices.contains(leadingIndex), pages.indices.contains(pageIndex) else { return }
        let anchor = hadiths[leadingIndex]
        let clamped = min(1, max(0, normalizedOffset))
        lastStableAnchor = anchor
        lastStableRawPageOffset = max(0, rawPageOffset)
        lastStableNormalizedOffset = clamped
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
            normalizedOffset: clamped
        )
    }

    /// Round 5: stores the page being left in the 2-entry scroll cache.
    /// Only the last stable anchor of that same page qualifies, so a stale
    /// anchor from another volume can never poison the cache.
    private func snapshotScrollOffset(for page: Int) {
        guard pages.indices.contains(page),
              let anchor = lastStableAnchor,
              pages[page].items.contains(where: { $0.internalId == anchor.internalId })
        else { return }
        let stored = ReaderPageScrollCache.storing(
            cache: pageScrollCache,
            order: pageScrollCacheOrder,
            page: page,
            snapshot: PageScrollSnapshot(
                providerHadithId: anchor.providerHadithId,
                rawPageOffset: lastStableRawPageOffset,
                normalizedOffset: lastStableNormalizedOffset
            )
        )
        pageScrollCache = stored.cache
        pageScrollCacheOrder = stored.order
    }

    /// Round 5: arms the transient restore when landing on one of the last
    /// two pages; a first visit keeps nil so the page starts at the top
    /// (or at the R2 jump target when one is armed).
    private func restoreScrollOffset(for page: Int) {
        if let snapshot = pageScrollCache[page] {
            scrollRestoreSnapshot = snapshot
            scrollRestoreGeneration += 1
        } else {
            scrollRestoreSnapshot = nil
        }
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
        restorationGeneration += 1
        // The fresh semantic anchor wins over any cached scroll offset for
        // this page: the cached points belong to the previous layout.
        scrollRestoreSnapshot = nil
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
            paginationVersion: paginationVersion
        )
    }

    private func saveProgress(
        anchor: ReaderHadith,
        page: ReaderPageResult,
        rawPageOffset: Double,
        normalizedOffset: Double
    ) {
        let layout = readingLayout(page.paginationVersion ?? 1)
        let storedUpdatedAt = library?.progress(for: collectionSlug)?.position?.updatedAt ?? 0
        let updatedAt = max(
            Date.now.millisecondsSinceEpoch,
            max(storedUpdatedAt + 1, lastPositionUpdatedAt + 1)
        )
        lastPositionUpdatedAt = updatedAt
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
        library?.saveProgress(position, ref: ref(for: anchor))
    }
}
