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
    private(set) var progressSummaries: [String: ProgressSummary] = [:]

    private var cancellables: Set<AnyCancellable> = []

    func start(convex: ConvexClientWithAuth<String>) {
        guard cancellables.isEmpty else { return }
        convex.subscribe(
            to: "library:listCollectionProgressSummaries",
            with: [:],
            yielding: [ProgressSummary].self
        )
        .receive(on: DispatchQueue.main)
        .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] summaries in
            self?.progressSummaries = Dictionary(uniqueKeysWithValues: summaries.map { ($0.collectionSlug, $0) })
        })
        .store(in: &cancellables)
    }
}
