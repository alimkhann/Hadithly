import SwiftUI

enum TranslationPresentationPhase: Hashable { case idle, requesting, available, recoverableFailure }

enum InterfaceMotion {
    static let quick: Double = 0.15
    static let reveal: Double = 0.4
    static let step: Double = 0.25
    static let shimmerPeriod: Double = 2
    static let thinkingPulsePeriod: Double = 1.5
    static let travel: CGFloat = 8
}

struct TranslationReveal<Content: View>: View {
    let phase: TranslationPresentationPhase
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var body: some View {
        content()
            .id(phase)
            .transition(reducedMotion ? .opacity : .opacity.combined(with: .offset(y: InterfaceMotion.travel)))
            .animation(reducedMotion ? nil : .easeInOut(duration: InterfaceMotion.reveal), value: phase)
    }
}

struct QuietPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reducedMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(reducedMotion ? nil : .easeOut(duration: InterfaceMotion.quick), value: configuration.isPressed)
    }
}

private struct ShimmerSweep: ViewModifier {
    @Environment(\.readerPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.scenePhase) private var scenePhase
    var animated = true
    var intensity: Double = 0.12

    func body(content: Content) -> some View {
        content.overlay {
            if animated && !reducedMotion && scenePhase == .active {
                TimelineView(.animation(minimumInterval: 1 / 30)) { time in
                    GeometryReader { geometry in
                        let width = geometry.size.width
                        let progress = time.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: InterfaceMotion.shimmerPeriod) / InterfaceMotion.shimmerPeriod
                        LinearGradient(colors: [.clear, palette.interactive.opacity(intensity), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: width * 0.5)
                            .offset(x: -width * 0.5 + width * 2 * progress)
                    }
                }
                .mask(content)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
        }
    }
}

enum SkeletonKind { case paragraph, article, daily, rows, compact }

struct ContentSkeleton: View {
    var kind: SkeletonKind = .paragraph
    var animated = true
    var label: LocalizedStringKey = "Loading…"
    @Environment(\.readerPalette) private var palette

    var body: some View {
        shapes
            .foregroundStyle(palette.surfaceElevated)
            .modifier(ShimmerSweep(animated: animated))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityIdentifier("loading.skeleton")
    }

    @ViewBuilder private var shapes: some View {
        switch kind {
        case .compact:
            lines(widths: [0.78, 0.48], height: 7, spacing: 7)
        case .paragraph:
            lines(widths: [0.96, 0.88, 0.63], height: 11, spacing: 10)
        case .article:
            VStack(alignment: .leading, spacing: 28) {
                lines(widths: [0.44, 0.68], height: 12, spacing: 10)
                lines(widths: [0.95, 0.89, 0.97, 0.61], height: 20, spacing: 22)
                lines(widths: [0.96, 0.91, 0.7], height: 11, spacing: 12)
            }
        case .daily:
            VStack(alignment: .leading, spacing: 22) {
                lines(widths: [0.48], height: 10, spacing: 0)
                lines(widths: [0.94, 0.86, 0.58], height: 18, spacing: 18)
                lines(widths: [0.96, 0.84, 0.64], height: 11, spacing: 10)
            }
        case .rows:
            VStack(spacing: 20) {
                ForEach(0..<3) { _ in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 10).frame(width: 46, height: 60)
                        lines(widths: [0.92, 0.62, 0.42], height: 10, spacing: 9)
                    }
                }
            }
        }
    }

    private func lines(widths: [CGFloat], height: CGFloat, spacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(widths.enumerated()), id: \.offset) { _, width in
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: height / 2)
                        .frame(width: geometry.size.width * width)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: height)
            }
        }
    }
}

struct ArticleLoadingView: View {
    let title: LocalizedStringKey
    @Environment(\.readerPalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text(title).font(.subheadline).foregroundStyle(palette.textSecondary)
            ContentSkeleton(kind: .article, label: title)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 96)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

struct TranslationThinkingView: View {
    @Environment(\.readerPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.caption)
                Text("AI translation…")
                    .font(.caption.weight(.medium))
                    .modifier(ShimmerSweep(intensity: 0.65))
                if reducedMotion || scenePhase != .active {
                    dots(progress: 0)
                } else {
                    TimelineView(.animation(minimumInterval: 1 / 20)) { time in
                        dots(progress: time.date.timeIntervalSinceReferenceDate)
                    }
                }
            }
            .foregroundStyle(palette.textSecondary)
            ContentSkeleton(animated: !reducedMotion, label: "AI translation…")
                .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AI translation…")
        .accessibilityIdentifier("reader.translationLoading")
    }

    private func dots(progress: Double) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { index in
                Circle().frame(width: 3, height: 3)
                    .opacity(reducedMotion ? 0.6 : 0.35 + 0.65 * (sin(progress * 2 * .pi / InterfaceMotion.thinkingPulsePeriod - Double(index) * 0.9) + 1) / 2)
            }
        }
        .accessibilityHidden(true)
    }
}

extension ReaderModel.TranslationState {
    var presentationPhase: TranslationPresentationPhase {
        switch self { case .loading: .requesting; case .loaded: .available; case .failed: .recoverableFailure }
    }
}
