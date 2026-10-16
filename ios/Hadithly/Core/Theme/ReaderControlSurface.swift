import SwiftUI

private struct ReaderControlSurface<S: Shape>: ViewModifier {
    @Environment(\.readerPalette) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(palette.surfaceElevated, in: shape)
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(palette.divider.opacity(0.7), lineWidth: 0.5))
        }
    }
}

extension View {
    func readerControlSurface<S: Shape>(in shape: S) -> some View {
        modifier(ReaderControlSurface(shape: shape))
    }
}

struct ReaderGlassGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var body: some View {
        if #available(iOS 26.0, *) { GlassEffectContainer(spacing: 12, content: content) }
        else { content() }
    }
}
