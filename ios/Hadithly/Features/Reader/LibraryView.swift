import SwiftUI

/// The Library is collection browsing, not a second progress dashboard.
/// Progress receives a deliberately empty visual slot until H2 supplies an
/// authoritative collection summary.
struct LibraryView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(UserLibraryModel.self) private var library

    @State private var openCollection: OpenCollection?
    @State private var openTarget: ReaderOpenTarget?
    @State private var presentation: Presentation = .grid
    @State private var model = LibraryModel()

    private enum Presentation { case grid, list }

    struct OpenCollection: Identifiable {
        let slug: String
        let name: String
        var id: String { slug }
    }

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        ScrollView {
            Group {
                if let entry = library.continueReading, let hadith = entry.hadith {
                    Button { openTarget = ReaderOpenTarget(slug: entry.collectionSlug, name: hadith.collectionName, volumeId: hadith.volumeId, hadithNumber: hadith.hadithNumber, source: .continueReading, position: entry.position) } label: {
                        HStack { CollectionCover(position: (ReaderModels.collections.firstIndex { $0.slug == entry.collectionSlug } ?? 0) + 1).frame(width: 42, height: 62); VStack(alignment: .leading) { Text("Continue reading").font(.caption).foregroundStyle(Theme.textSecondary); Text(hadith.referenceDisplay).foregroundStyle(Theme.textPrimary) }; Spacer() }.padding(10).background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                }
                switch presentation {
                case .grid:
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(Array(ReaderModels.collections.enumerated()), id: \.element.slug) { index, collection in
                            collectionGridItem(slug: collection.slug, name: collection.name, position: index + 1)
                        }
                    }
                case .list:
                    LazyVStack(spacing: 12) {
                        ForEach(Array(ReaderModels.collections.enumerated()), id: \.element.slug) { index, collection in
                            collectionListItem(slug: collection.slug, name: collection.name, position: index + 1)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presentation = presentation == .grid ? .list : .grid
                } label: {
                    Image(systemName: presentation == .grid ? "list.bullet" : "square.grid.2x2")
                }
                .accessibilityLabel(presentation == .grid ? "Show Library list" : "Show Library grid")
                .accessibilityIdentifier("library.layoutToggle")
            }
        }
        .task {
            library.refresh()
            model.start(convex: environment.convex)
            ReaderPrefetch.warmEntry(
                convex: environment.convex,
                target: ReaderPrefetchTargets.entryTarget(progress: library.continueReading)
            )
        }
        .fullScreenCover(item: $openCollection) { collection in
            ReaderView(collectionSlug: collection.slug, collectionName: collection.name)
        }
        .fullScreenCover(item: $openTarget) { target in
            ReaderView(collectionSlug: target.slug, collectionName: target.name, openVolumeId: target.volumeId, openHadithNumber: target.hadithNumber, openPosition: target.position, targetSource: target.source)
        }
    }

    private func collectionGridItem(slug: String, name: String, position: Int) -> some View {
        Button { openCollection = OpenCollection(slug: slug, name: name) } label: {
            VStack(alignment: .leading, spacing: 9) {
                CollectionCover(position: position)
                    .frame(maxWidth: .infinity)
                Text("\(position)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                progressSlot(summary(for: slug))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(position). \(name)")
        .accessibilityIdentifier("library.collection.\(slug)")
    }

    private func collectionListItem(slug: String, name: String, position: Int) -> some View {
        Button { openCollection = OpenCollection(slug: slug, name: name) } label: {
            HStack(spacing: 14) {
                CollectionCover(position: position)
                    .frame(width: 56, height: 82)
                VStack(alignment: .leading, spacing: 7) {
                    Text("\(position)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                    Text(name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                    progressSlot(summary(for: slug))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(position). \(name)")
        .accessibilityIdentifier("library.collection.\(slug)")
    }

    private func progressSlot(_ summary: LibraryModel.ProgressSummary?) -> some View {
        let label: String = switch summary?.state {
        case "unopened": "Not started"
        case "in_progress": "Hadith \(Int(summary?.readOrdinal ?? 0)) of \(Int(summary?.totalHadiths ?? 0))"
        case "completed": "Complete"
        case "stale": "Position unavailable"
        default: "Progress unavailable"
        }
        return VStack(alignment: .leading, spacing: 4) {
            Capsule().fill(Theme.surfaceElevated).frame(height: 3)
            Text(label).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
    }

    private func summary(for slug: String) -> LibraryModel.ProgressSummary? {
        if let progress = library.progress(for: slug), model.progressSummaries[slug]?.state == "unopened" {
            return .init(collectionSlug: slug, state: "in_progress", totalHadiths: model.progressSummaries[slug]?.totalHadiths, readOrdinal: Double(progress.hadith?.hadithNumber ?? "") )
        }
        return model.progressSummaries[slug]
    }
}
