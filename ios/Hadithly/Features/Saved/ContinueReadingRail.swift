import SwiftUI

/// The horizontally scrollable Continue Reading rail shared by Today and
/// Library. Today shows up to three recent positions; Library shows only the
/// most recent one. Rows reuse the Today card geometry.
struct ContinueReadingRail: View {
    let entries: [ProgressEntry]
    let showsTitle: Bool
    let onOpen: (ProgressEntry, HadithRef) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsTitle {
                Text("Continue reading")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(entries.filter { $0.hadith != nil }.sorted { $0.updatedAt > $1.updatedAt }) { entry in
                        if let hadith = entry.hadith {
                            Button {
                                onOpen(entry, hadith)
                            } label: {
                                ContinueReadingCard(hadith: hadith, position: collectionPosition(entry.collectionSlug))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("today.continueCard.\(entry.collectionSlug)")
                        }
                    }
                }
                .padding(.horizontal, showsTitle ? 16 : 0)
            }
            .padding(.horizontal, showsTitle ? -16 : 0)
        }
    }

    private func collectionPosition(_ slug: String) -> Int {
        (ReaderModels.collections.firstIndex(where: { $0.slug == slug }) ?? 0) + 1
    }
}

private struct ContinueReadingCard: View {
    let hadith: HadithRef
    let position: Int
    var body: some View {
        HStack(spacing: 12) {
            CollectionCover(position: position).frame(width: 52, height: 76)
            VStack(alignment: .leading, spacing: 5) {
                Text(hadith.collectionName).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(2)
                Text(hadith.referenceDisplay).font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
        }
        .frame(width: 218, alignment: .leading)
        .padding(10)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
