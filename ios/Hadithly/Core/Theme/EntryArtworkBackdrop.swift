import SwiftUI

struct EntryArtworkBackdrop: View {
    var dimmed = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.readerPalette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geometry in
            Image(colorScheme == .dark ? "OnboardingBook" : "OnboardingBookLight")
                .resizable().scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .overlay(palette.background.opacity(dimmed || typeSize.isAccessibilitySize || reduceTransparency ? 0.9 : 0))
                .overlay {
                    LinearGradient(stops: [
                        .init(color: palette.background.opacity(0.96), location: 0),
                        .init(color: palette.background.opacity(0.84), location: 0.38),
                        .init(color: palette.background.opacity(0.06), location: 0.62),
                        .init(color: palette.background.opacity(0.96), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
