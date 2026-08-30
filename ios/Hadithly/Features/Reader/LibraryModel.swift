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
    struct VolumeCounts: Equatable {
        let volumes: Int
        let hadiths: Int
    }

    private(set) var counts: [String: VolumeCounts] = [:]

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
    }
}
