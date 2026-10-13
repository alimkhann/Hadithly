import SwiftUI

struct WelcomeView: View {
    let onComplete: () -> Void
    @Environment(\.readerPalette) private var palette
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Hadithly").font(.title3.weight(.medium)).padding(.top, 36)
                    Text("la2.welcome").font(.largeTitle.bold()).multilineTextAlignment(.center).padding(.horizontal, 28)
                    Image("OnboardingBook").resizable().scaledToFit().frame(maxHeight: 450).accessibilityHidden(true)
                        .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .top, endPoint: .bottom))
                }
            }
            OnboardingPrimaryButton("la2.get_started", action: onComplete)
                .padding(24).accessibilityIdentifier("onboarding.getStarted")
        }.foregroundStyle(palette.textPrimary).background(palette.background.ignoresSafeArea())
    }
}
