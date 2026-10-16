import SwiftUI

struct ReadingLanguage: Identifiable, Hashable {
    let code: String
    let name: String

    var id: String { code }
    var flag: String {
        switch code {
        case "en": "🇬🇧"
        case "ar": "🇸🇦"
        case "ru": "🇷🇺"
        case "kk": "🇰🇿"
        case "ky": "🇰🇬"
        case "uz": "🇺🇿"
        case "tr": "🇹🇷"
        case "id": "🇮🇩"
        case "ur": "🇵🇰"
        case "fr": "🇫🇷"
        case "es-419": "🌎"
        case "pt-BR": "🇧🇷"
        case "sw": "🇰🇪"
        case "hi": "🇮🇳"
        case "bn": "🇧🇩"
        default: "🌐"
        }
    }
}

/// Languages the app actively supports for translations. English is the
/// default source language; the rest map to PRD phase-one priorities.
enum SupportedLanguages {
    static let all: [ReadingLanguage] = [
        ReadingLanguage(code: "en", name: "English"),
        ReadingLanguage(code: "ar", name: "العربية"),
        ReadingLanguage(code: "ru", name: "Русский"),
        ReadingLanguage(code: "kk", name: "Қазақша"),
        ReadingLanguage(code: "ky", name: "Кыргызча"),
        ReadingLanguage(code: "uz", name: "Oʻzbekcha"),
        ReadingLanguage(code: "tr", name: "Türkçe"),
        ReadingLanguage(code: "id", name: "Bahasa Indonesia"),
        ReadingLanguage(code: "ur", name: "اردو"),
        ReadingLanguage(code: "fr", name: "Français"),
        ReadingLanguage(code: "es-419", name: "Español (Latinoamérica)"),
        ReadingLanguage(code: "pt-BR", name: "Português (Brasil)"),
        ReadingLanguage(code: "sw", name: "Kiswahili"),
        ReadingLanguage(code: "hi", name: "हिन्दी"),
        ReadingLanguage(code: "bn", name: "বাংলা"),
    ]
}

struct LanguagePickerView: View {
    @Environment(\.readerPalette) private var palette
    @Binding var selection: String

    var body: some View {
        VStack(spacing: 0) {
            Text("la2.language")
                .font(.title2.bold())
                .foregroundStyle(palette.textPrimary)
                .padding(.top, Theme.Spacing.xl)

            Text("la2.suggested")
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, Theme.Spacing.xs)

            List(SupportedLanguages.all) { language in
                languageRow(language)
                    .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .padding(.top, 16)

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    private func languageRow(_ language: ReadingLanguage) -> some View {
        Button {
            selection = language.code
        } label: {
            HStack(spacing: 12) {
                Text(language.flag).font(.title2).accessibilityHidden(true)
                Text(language.name)
                    .font(.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if selection == language.code {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.interactive)
                }
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == language.code ? .isSelected : [])
        .accessibilityIdentifier("onboarding.language.\(language.code)")
    }
}

#Preview {
    LanguagePickerView(selection: .constant("en"))
}
