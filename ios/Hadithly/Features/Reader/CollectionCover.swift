import SwiftUI
import UIKit

/// A small, code-native book object shared by Home and Library. The artwork is
/// deliberately wordless: collection identity remains available as accessible
/// text beside the cover rather than competing with the reader's typography.
struct CollectionCover: View {
    let position: Int
    var aspectRatio: CGFloat = 0.66

    private var image: UIImage? {
        guard let url = Bundle.main.url(
            forResource: CollectionCoverPalette.resource(for: position),
            withExtension: "png"
        ) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(CollectionCoverPalette.paper(for: position))
                }
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
                Rectangle()
                    .fill(LinearGradient(colors: [.black.opacity(0.34), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(5, proxy.size.width * 0.075))
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1)
                    .padding(.leading, max(5, proxy.size.width * 0.075))
            }
            .shadow(color: Color.black.opacity(0.42), radius: 10, x: 4, y: 7)
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private enum CollectionCoverPalette {
    static func resource(for position: Int) -> String {
        ["cover_bukhari", "cover_muslim", "cover_sunan_nasai", "cover_abu_dawood", "cover_tirmidhi", "cover_ibn_majah", "cover_mishkat"][safe: position - 1] ?? "cover_bukhari"
    }

    static func paper(for position: Int) -> Color {
        ["C8A46D", "A96F61", "8B9B86", "B48F77", "8F93A5", "9A8065", "78949A"][safe: position - 1]
            .map(Color.init(hex:)) ?? Theme.surfaceElevated
    }

}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
