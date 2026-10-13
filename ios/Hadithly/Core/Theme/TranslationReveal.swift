import SwiftUI

enum TranslationPresentationPhase: Equatable { case idle, requesting, available, recoverableFailure }

struct TranslationReveal<Content: View>: View {
    let phase: TranslationPresentationPhase
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    var body: some View {
        VStack(alignment: .leading) { content().transition(.opacity) }
            .animation(reducedMotion ? nil : .easeInOut(duration: 0.3), value: phase)
    }
}

extension ReaderModel.TranslationState {
    var presentationPhase: TranslationPresentationPhase {
        switch self { case .loading: .requesting; case .loaded: .available; case .failed: .recoverableFailure }
    }
}
