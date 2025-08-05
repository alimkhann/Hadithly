import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var localizationManager: LocalizationManager

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Search Bar
                SearchBar(text: $viewModel.searchText, language: settings.selectedLanguage)

                // Language Filter
                LanguageFilterView(selectedLanguage: $settings.selectedLanguage)

                // Search Results
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.searchResults.isEmpty && !viewModel.searchText.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(localizationManager.localizedString(.noResults))
                            .font(.headline)
                        Text(localizationManager.localizedString(.tryDifferentKeywords))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    SearchResultsView(results: viewModel.searchResults)
                }
            }
            .navigationTitle(localizationManager.localizedString(.search))
            .navigationBarTitleDisplayMode(.large)
        }
        .onChange(of: viewModel.searchText) { _, _ in
            Task {
                await viewModel.performSearch()
            }
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    let language: Language
    @EnvironmentObject var localizationManager: LocalizationManager

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField(localizationManager.localizedString(.searchHadiths), text: $text)
                .textFieldStyle(PlainTextFieldStyle())
                .environment(\.layoutDirection, language.isRTL ? .rightToLeft : .leftToRight)

            if !text.isEmpty {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
    }
}

struct LanguageFilterView: View {
    @Binding var selectedLanguage: Language
    @EnvironmentObject var localizationManager: LocalizationManager

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Language.allCases, id: \.self) { language in
                    LanguageFilterButton(
                        language: language,
                        isSelected: selectedLanguage == language
                    ) {
                        selectedLanguage = language
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct LanguageFilterButton: View {
    let language: Language
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(language.displayName)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.green : Color(.systemGray5))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
    }
}

struct SearchResultsView: View {
    let results: [Hadith]

    var body: some View {
        List(results) { hadith in
            NavigationLink(destination: HadithDetailView(hadith: hadith)) {
                HadithSearchRow(hadith: hadith)
            }
        }
        .listStyle(PlainListStyle())
    }
}

struct HadithSearchRow: View {
    let hadith: Hadith
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Arabic text
            if settings.showArabicText {
                Text(hadith.arabicText)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .environment(\.layoutDirection, .rightToLeft)
            }

            // Selected language text
            if !settings.pureArabicMode {
                Text(hadith.text(for: settings.selectedLanguage))
                    .font(.body)
                    .lineLimit(3)
                    .multilineTextAlignment(settings.selectedLanguage.isRTL ? .trailing : .leading)
            }

            // Reference and grade
            HStack {
                Text(hadith.reference)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(hadith.grade)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
    }
}

struct EmptySearchView: View {
    @EnvironmentObject var localizationManager: LocalizationManager

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text(localizationManager.localizedString(.noResults))
                .font(.headline)

            Text(localizationManager.localizedString(.tryDifferentKeywords))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    SearchView()
        .environmentObject(AppSettings())
        .environmentObject(LocalizationManager.shared)
}
