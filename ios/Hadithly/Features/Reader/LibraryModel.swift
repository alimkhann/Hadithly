import Combine
import ConvexMobile
import Foundation
import Observation

/// Watches the cached volume outlines so the Library can show counts per
/// collection. Reads only the `collectionOutlines` cache — collections never
/// opened stay quiet with no counts.
@MainActor
@Observable
final class LibraryModel {
    struct ProgressSummary: Decodable, Equatable {
        let collectionSlug: String
        let state: String
        let totalHadiths: Double?
        let readOrdinal: Double?
    }
    struct VolumeCounts: Equatable {
        let volumes: Int
        let hadiths: Int
    }

    private(set) var counts: [String: VolumeCounts] = [:]
    private(set) var progressSummaries: [String: ProgressSummary] = [:]

    private var cancellables: Set<AnyCancellable> = []

    func start(convex: ConvexClientWithAuth<String>) {
        guard cancellables.isEmpty else { return }
        for (slug, _) in ReaderModels.collections {
            convex.subscribe(
                to: "collections:getOutline",
                with: ["collectionSlug": slug as ConvexEncodable?],
                yielding: CollectionOutlineResult?.self
            )
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] outline in
                    guard let outline, !outline.volumes.isEmpty else { return }
                    let totalHadiths = outline.volumes.reduce(0) { $0 + $1.hadithCount }
                    self?.counts[slug] = VolumeCounts(
                        volumes: outline.volumes.count,
                        hadiths: totalHadiths
                    )
                }
            )
            .store(in: &cancellables)
        }
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
