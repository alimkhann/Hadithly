import SwiftUI

/// The Library is collection browsing, not a second progress dashboard.
/// Progress receives a deliberately empty visual slot until H2 supplies an
/// authoritative collection summary.
struct LibraryView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(UserLibraryModel.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    @State private var openTarget: ReaderOpenTarget?
    @State private var presentation: Presentation = .grid
    @State private var model = LibraryModel()

#if DEBUG
    private var isPreview = false
    init(previewLoading: Bool? = nil) {
        isPreview = previewLoading != nil
        let preview = LibraryModel()
        if let previewLoading { preview.seedPreview(loading: previewLoading) }
        _model = State(initialValue: preview)
    }
#endif

    private enum Presentation: Hashable { case grid, list }

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        ScrollView {
            Group {
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
            .id(presentation)
            .transition(.opacity)
        }
        .animation(reducedMotion ? nil : .easeInOut(duration: InterfaceMotion.step), value: presentation)
        .background(Theme.background)
        .appNavigationTitle("Library")
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
#if DEBUG
            if isPreview { return }
#endif
            library.refresh()
            model.start(convex: environment.convex)
            ReaderPrefetch.warmEntry(
                convex: environment.convex,
                target: ReaderPrefetchTargets.entryTarget(progress: library.continueReading)
            )
        }
        .fullScreenCover(item: $openTarget) { target in
            ReaderView(collectionSlug: target.slug, collectionName: target.name, openVolumeId: target.volumeId, openHadithNumber: target.hadithNumber, openPosition: target.position, targetSource: target.source)
        }
    }

    private func collectionGridItem(slug: String, name: String, position: Int) -> some View {
        Button { openTarget = collectionTarget(slug: slug, name: name) } label: {
            VStack(alignment: .leading, spacing: 9) {
                CollectionCover(position: position)
                    .frame(maxWidth: .infinity)
                CollectionTitle(number: position, name: name)
                progressSlot(summary(for: slug))
            }
        }
        .buttonStyle(QuietPressStyle())
        .accessibilityLabel("\(position). \(name)")
        .accessibilityIdentifier("library.collection.\(slug)")
    }

    private func collectionListItem(slug: String, name: String, position: Int) -> some View {
        Button { openTarget = collectionTarget(slug: slug, name: name) } label: {
            HStack(spacing: 14) {
                CollectionCover(position: position)
                    .frame(width: 56, height: 82)
                VStack(alignment: .leading, spacing: 7) {
                    CollectionTitle(number: position, name: name, font: .body)
                    progressSlot(summary(for: slug))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(QuietPressStyle())
        .accessibilityLabel("\(position). \(name)")
        .accessibilityIdentifier("library.collection.\(slug)")
    }

    private func collectionTarget(slug: String, name: String) -> ReaderOpenTarget {
        guard let progress = library.progress.first(where: { $0.collectionSlug == slug }),
              let hadith = progress.hadith,
              let position = progress.position
        else { return ReaderOpenTarget(slug: slug, name: name) }
        return ReaderOpenTarget(slug: slug, name: name, volumeId: hadith.volumeId,
                                hadithNumber: hadith.hadithNumber, source: .continueReading,
                                position: position)
    }

    private func progressSlot(_ summary: LibraryModel.ProgressSummary?) -> some View {
        let label: String = switch summary?.state {
        case "unopened": "Not started"
        case "in_progress":
            if let read = summary?.readOrdinal, let total = summary?.totalHadiths, total > 0 {
                "Hadith \(Int(read)) of \(Int(total))"
            } else { "Continue reading" }
        case "completed": "Complete"
        case "stale": "Position unavailable"
        default: "Progress unavailable"
        }
        return VStack(alignment: .leading, spacing: 4) {
            if summary == nil && model.isLoading {
                ContentSkeleton(kind: .compact, label: "Loading reading progress")
            } else {
            GeometryReader { proxy in
                Capsule().fill(Theme.surfaceElevated)
                if let fraction = progressFraction(summary) {
                    Capsule().fill(Theme.accent).frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 3)
            Text(label).font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func progressFraction(_ summary: LibraryModel.ProgressSummary?) -> CGFloat? {
        guard summary?.state == "in_progress", let read = summary?.readOrdinal,
              let total = summary?.totalHadiths, total > 0 else { return nil }
        return min(1, max(0, read / total))
    }

    private func summary(for slug: String) -> LibraryModel.ProgressSummary? {
        if let progress = library.progress(for: slug), model.progressSummaries[slug]?.state == "unopened" {
            return .init(collectionSlug: slug, state: "in_progress", totalHadiths: model.progressSummaries[slug]?.totalHadiths, readOrdinal: Double(progress.hadith?.hadithNumber ?? "") )
        }
        return model.progressSummaries[slug]
    }
}

struct CollectionTitle: View {
    let number: Int
    let name: String
    var font: Font = .subheadline
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(number)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .fixedSize()
            Text(name)
                .font(font.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
