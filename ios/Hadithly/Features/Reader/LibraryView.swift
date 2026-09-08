import SwiftUI

/// The seven collections. Tapping one opens the reader full screen over the
/// tab bar; the reader's close control is the way back to this tab.
struct LibraryView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(UserLibraryModel.self) private var library

    @State private var model = LibraryModel()
    @State private var openCollection: OpenCollection?
    @State private var openTarget: ReaderOpenTarget?

    struct OpenCollection: Identifiable {
        let slug: String
        let name: String
        var id: String { slug }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let entry = library.continueReading, let hadith = entry.hadith {
                    continueCard(entry, hadith: hadith)
                }

                ForEach(Array(ReaderModels.collections.enumerated()), id: \.element.slug) { index, collection in
                    collectionRow(slug: collection.slug, name: collection.name, position: index + 1)
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .task {
            library.refresh()
            model.start(convex: environment.convex)
        }
        .fullScreenCover(item: $openCollection) { collection in
            ReaderView(collectionSlug: collection.slug, collectionName: collection.name)
        }
        .fullScreenCover(item: $openTarget) { target in
            ReaderView(
                collectionSlug: target.slug,
                collectionName: target.name,
                openVolumeId: target.volumeId,
                openHadithNumber: target.hadithNumber
            )
        }
    }

    private func continueCard(_ entry: ProgressEntry, hadith: HadithRef) -> some View {
        Button {
            openTarget = ReaderOpenTarget(
                slug: entry.collectionSlug,
                name: hadith.collectionName,
                volumeId: hadith.volumeId,
                hadithNumber: hadith.hadithNumber
            )
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "book")
                    .font(.body)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 38, height: 38)
                    .background(Theme.accentSoft)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("Continue reading")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .textCase(.uppercase)
                    Text(hadith.collectionName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                    if !hadith.referenceDisplay.isEmpty {
                        Text(hadith.referenceDisplay)
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library.continueCard")
    }

    private func collectionRow(slug: String, name: String, position: Int) -> some View {
        Button {
            openCollection = OpenCollection(slug: slug, name: name)
        } label: {
            HStack(spacing: 14) {
                Text("\(position)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(Theme.surfaceElevated)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                    if let counts = model.counts[slug] {
                        Text(volumeSummary(counts))
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library.collection.\(slug)")
    }

    private func volumeSummary(_ counts: LibraryModel.VolumeCounts) -> String {
        let volumes = counts.volumes == 1 ? "volume" : "volumes"
        let hadiths = counts.hadiths == 1 ? "hadith" : "hadiths"
        return "\(counts.volumes) \(volumes) · \(counts.hadiths) \(hadiths) cached"
    }
}
