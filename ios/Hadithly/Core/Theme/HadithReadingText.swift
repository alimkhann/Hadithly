import SwiftUI

/// Shared card-free rendering for the Arabic original and a supplied translation.
/// Source, authenticity, and translation provenance stay with each feature row.
struct HadithReadingText: View {
    let arabicText: String
    let translation: String?
    let translationLanguage: String?
    let arabicVisible: Bool
    let translationVisible: Bool
    let arabicFontSize: CGFloat
    let arabicFont: ArabicFont
    let translationLineLimit: Int?
    let textColor: Color

    init(
        arabicText: String,
        translation: String?,
        translationLanguage: String?,
        arabicVisible: Bool = true,
        translationVisible: Bool = true,
        arabicFontSize: CGFloat = 28,
        arabicFont: ArabicFont = .amiri,
        translationLineLimit: Int? = nil,
        textColor: Color
    ) {
        self.arabicText = arabicText
        self.translation = translation
        self.translationLanguage = translationLanguage
        self.arabicVisible = arabicVisible
        self.translationVisible = translationVisible
        self.arabicFontSize = arabicFontSize
        self.arabicFont = arabicFont
        self.translationLineLimit = translationLineLimit
        self.textColor = textColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            if arabicVisible {
                Text(arabicText)
                    .font(Theme.arabic(arabicFontSize, arabicFont))
                    .lineSpacing(arabicFontSize * 0.75)
                    .foregroundStyle(textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.layoutDirection, .rightToLeft)
                    .lineLimit(translationLineLimit)
                    .accessibilityIdentifier("hadith.text.arabic")
            }
            if translationVisible, let translation {
                Text(translation)
                    .font(.body)
                    .lineSpacing(5)
                    .foregroundStyle(textColor)
                    .environment(\.layoutDirection, LocaleFallback.isRTL(translationLanguage ?? "en") ? .rightToLeft : .leftToRight)
                    .lineLimit(translationLineLimit)
                    .accessibilityIdentifier("hadith.text.translation")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
