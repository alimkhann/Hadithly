import SwiftUI

/// A small, code-native book object shared by Home and Library. The artwork is
/// deliberately wordless: collection identity remains available as accessible
/// text beside the cover rather than competing with the reader's typography.
struct CollectionCover: View {
    let position: Int
    var aspectRatio: CGFloat = 0.66

    private var ink: Color { CollectionCoverPalette.ink(for: position) }
    private var paper: Color { CollectionCoverPalette.paper(for: position) }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [paper, paper.opacity(0.72), ink.opacity(0.52)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Paper grain and a restrained binding rule make the object
                // feel held rather than like a colored card.
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.13), lineWidth: 0.8)
                Rectangle()
                    .fill(LinearGradient(colors: [ink.opacity(0.8), ink.opacity(0.2)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(5, proxy.size.width * 0.075))
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1)
                    .padding(.leading, max(5, proxy.size.width * 0.075))
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(ink.opacity(0.32), lineWidth: 1)
                    .padding(7)
            }
            .shadow(color: Color.black.opacity(0.42), radius: 10, x: 4, y: 7)
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private enum CollectionCoverPalette {
    static func paper(for position: Int) -> Color {
        ["C8A46D", "A96F61", "8B9B86", "B48F77", "8F93A5", "9A8065", "78949A"][safe: position - 1]
            .map(Color.init(hex:)) ?? Theme.surfaceElevated
    }

    static func ink(for position: Int) -> Color {
        ["4B3423", "4C2728", "29433A", "513A30", "323948", "4C392B", "29464B"][safe: position - 1]
            .map(Color.init(hex:)) ?? Theme.surface
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
