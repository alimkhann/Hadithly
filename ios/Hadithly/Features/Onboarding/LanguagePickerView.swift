import SwiftUI

struct ReadingLanguage: Identifiable, Hashable {
    let code: String
    let name: String

    var id: String { code }
}

/// Languages the app actively supports for translations. English is the
/// default source language; the rest map to PRD phase-one priorities.
enum SupportedLanguages {
    static let all: [ReadingLanguage] = [
        ReadingLanguage(code: "en", name: "English"),
        ReadingLanguage(code: "kk", name: "Қазақша"),
        ReadingLanguage(code: "ru", name: "Русский"),
        ReadingLanguage(code: "uz", name: "Oʻzbekcha"),
        ReadingLanguage(code: "tr", name: "Türkçe"),
        ReadingLanguage(code: "id", name: "Bahasa Indonesia"),
        ReadingLanguage(code: "ur", name: "اردو"),
        ReadingLanguage(code: "ar", name: "العربية"),
    ]
}

struct LanguagePickerView: View {
    @Binding var selection: String
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("Choose your reading language")
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, Theme.Spacing.xl)

            Text("You can change this any time in Settings.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, Theme.Spacing.xs)

            ScrollView {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(SupportedLanguages.all) { language in
                        languageRow(language)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, Theme.Spacing.xl)
            }

            Button(action: onContinue) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.accent)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    private func languageRow(_ language: ReadingLanguage) -> some View {
        Button {
            selection = language.code
        } label: {
            HStack {
                Text(language.name)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if selection == language.code {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                selection == language.code ? Theme.accentSoft : Theme.surface
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    LanguagePickerView(selection: .constant("en"), onContinue: {})
}
