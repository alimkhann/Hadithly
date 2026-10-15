import Combine
import ConvexMobile
import Foundation
import Observation

/// Watches one compact progress stream. Counts come from backend summaries;
/// the Library never downloads chapter outlines just to show a count.
@MainActor
@Observable
final class LibraryModel {
    struct ProgressSummary: Decodable, Equatable {
        let collectionSlug: String
        let state: String
        let totalHadiths: Double?
        let readOrdinal: Double?
    }
    private(set) var isLoading = true
    private(set) var progressSummaries: [String: ProgressSummary] = [:]

    private var cancellables: Set<AnyCancellable> = []

#if DEBUG
    func seedPreview(loading: Bool) {
        isLoading = loading
        if !loading {
            progressSummaries = Dictionary(uniqueKeysWithValues: ReaderModels.collections.map {
                ($0.slug, ProgressSummary(collectionSlug: $0.slug, state: "unopened", totalHadiths: nil, readOrdinal: nil))
            })
        }
    }
#endif

    func start(convex: ConvexClientWithAuth<String>) {
        guard cancellables.isEmpty else { return }
        convex.subscribe(
            to: "library:listCollectionProgressSummaries",
            with: [:],
            yielding: [ProgressSummary].self
        )
        .receive(on: DispatchQueue.main)
        .sink(receiveCompletion: { [weak self] _ in self?.isLoading = false }, receiveValue: { [weak self] summaries in
            self?.isLoading = false
            self?.progressSummaries = Dictionary(uniqueKeysWithValues: summaries.map { ($0.collectionSlug, $0) })
        })
        .store(in: &cancellables)
    }
}
