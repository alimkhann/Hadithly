import ConvexMobile
import Foundation
import Observation

/// Drives the reader: loads the collection outline, pages hadiths by content
/// size through `actions/hadithData:getReaderPage`, prefetches forward, and
/// pulls AI translations for the chosen language through
/// `actions/ai:translateHadith` with graceful quota/sign-in handling.
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

    // Reading state
    private(set) var phase: Phase = .loadingOutline
    private(set) var volumes: [OutlineVolume] = []
    private(set) var pages: [ReaderPageResult] = []
    private(set) var selectedVolumeId: String?
    private(set) var isLoadingPage = false
    var pageIndex = 0 {
        didSet {
            guard oldValue != pageIndex else { return }
            prefetchForwardIfNeeded()
            scheduleTranslationsForCurrentPage()
        }
    }

    // Chrome & sheets
    var chromeVisible = true

    // Translation state, keyed by hadith internal id.
    private(set) var translations: [String: TranslationState] = [:]
    private(set) var language: String

    private var outlineTask: Task<Void, Never>?
    private var pageTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?
    private var translationGeneration = 0

    init(
        convex: ConvexClientWithAuth<String>,
        collectionSlug: String,
        collectionName: String,
        language: String,
        isSignedIn: @escaping () -> Bool
    ) {
        self.convex = convex
        self.collectionSlug = collectionSlug
        self.collectionName = collectionName
        self.language = language
        self.isSignedIn = isSignedIn
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
            let firstVolume = result.volumes.first?.volumeId
            selectedVolumeId = firstVolume
            if let firstVolume {
                await loadPage(0, volumeId: firstVolume)
            } else {
                phase = .failed("No volumes found for this collection.")
            }
        } catch {
            phase = .failed(ReaderModels.errorMessage(of: error))
        }
        outlineTask = nil
    }

    func selectVolume(_ volumeId: String) {
        guard volumeId != selectedVolumeId else { return }
        selectedVolumeId = volumeId
        resetReading()
        Task { await loadPage(0, volumeId: volumeId) }
    }

    private func resetReading() {
        pageTask?.cancel()
        translationTask?.cancel()
        pageTask = nil
        translationTask = nil
        translationGeneration += 1
        pages = []
        pageIndex = 0
        translations = [:]
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
    /// the requested one are filled with empty results so the TabView index
    /// stays aligned.
    private func loadPage(_ index: Int, volumeId: String) async {
        if isLoadingPage { return }
        isLoadingPage = true
        defer { isLoadingPage = false }
        do {
            let args: [String: ConvexEncodable?] = [
                "collectionSlug": collectionSlug as ConvexEncodable?,
                "volumeId": volumeId as ConvexEncodable?,
                "page": Double(index + 1) as ConvexEncodable?,
            ]
            let result: ReaderPageResult = try await convex.action(
                "actions/hadithData:getReaderPage",
                with: args
            )
            while pages.count < index { pages.append(emptyPage()) }
            if pages.indices.contains(index) {
                pages[index] = result
            } else {
                pages.append(result)
            }
            phase = .reading
            if pageIndex == index {
                scheduleTranslationsForCurrentPage()
            }
        } catch {
            if pages.isEmpty {
                phase = .failed(ReaderModels.errorMessage(of: error))
            }
        }
    }

    private func emptyPage() -> ReaderPageResult {
        ReaderPageResult(items: [], page: 0, pageSize: 0, totalPages: 0, hasMore: false)
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
}
