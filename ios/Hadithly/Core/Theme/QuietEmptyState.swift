import SwiftUI

struct QuietEmptyState: View {
    let title: String
    let message: String
    let symbol: String
    @Environment(\.readerPalette) private var palette
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 30, weight: .regular))
                .foregroundStyle(palette.textSecondary).padding(.bottom, 4).accessibilityHidden(true)
            Text(LocalizedStringKey(title)).font(.headline).foregroundStyle(palette.textPrimary)
            Text(LocalizedStringKey(message)).font(.subheadline).foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center).lineSpacing(3)
        }
        .frame(maxWidth: 300).padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
