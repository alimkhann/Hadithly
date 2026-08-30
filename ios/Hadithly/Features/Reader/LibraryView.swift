import SwiftUI

/// The seven collections. Tapping one opens the reader full screen over the
/// tab bar; the reader's close control is the way back to this tab.
struct LibraryView: View {
    @State private var openCollection: OpenCollection?

    struct OpenCollection: Identifiable {
        let slug: String
        let name: String
        var id: String { slug }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(Array(ReaderModels.collections.enumerated()), id: \.element.slug) { index, collection in
                    collectionRow(slug: collection.slug, name: collection.name, position: index + 1)
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(item: $openCollection) { collection in
            ReaderView(collectionSlug: collection.slug, collectionName: collection.name)
        }
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

                Text(name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
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
}
