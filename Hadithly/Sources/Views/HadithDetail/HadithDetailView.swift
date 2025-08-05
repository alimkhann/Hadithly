import SwiftUI

struct HadithDetailView: View {
    let hadith: Hadith
    @StateObject private var viewModel: HadithDetailViewModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var localizationManager: LocalizationManager
    @Environment(\.dismiss) private var dismiss

    init(hadith: Hadith) {
        self.hadith = hadith
        self._viewModel = StateObject(wrappedValue: HadithDetailViewModel(hadith: hadith))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HadithHeaderView(hadith: hadith)

                // Arabic Text
                if settings.showArabicText {
                    HadithTextSection(
                        title: localizationManager.localizedString(.arabic),
                        text: hadith.arabicText,
                        isRTL: true
                    )
                }

                // Selected Language Text
                if !settings.pureArabicMode {
                    HadithTextSection(
                        title: settings.selectedLanguage.displayName,
                        text: hadith.text(for: settings.selectedLanguage),
                        isRTL: settings.selectedLanguage.isRTL
                    )
                }

                // All Languages (if not in pure Arabic mode)
                if !settings.pureArabicMode {
                    if settings.selectedLanguage != .english {
                        HadithTextSection(
                            title: localizationManager.localizedString(.english),
                            text: hadith.englishText,
                            isRTL: false
                        )
                    }

                    if settings.selectedLanguage != .russian {
                        HadithTextSection(
                            title: localizationManager.localizedString(.russian),
                            text: hadith.russianText,
                            isRTL: false
                        )
                    }
                }

                // Metadata
                HadithMetadataView(hadith: hadith)

                // Actions
                HadithActionsView(
                    hadith: hadith,
                    isSaved: viewModel.isSaved,
                    onSave: { viewModel.toggleSave() },
                    onShare: { viewModel.shareHadith() }
                )
            }
            .padding()
        }
        .navigationTitle(localizationManager.localizedString(.hadith))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(localizationManager.localizedString(.share)) {
                        viewModel.shareHadith()
                    }

                    Button(viewModel.isSaved ? localizationManager.localizedString(.removeFromSaved) : localizationManager.localizedString(.save)) {
                        viewModel.toggleSave()
                    }

                    Button(localizationManager.localizedString(.copyText)) {
                        viewModel.copyText()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            await viewModel.checkSavedStatus()
        }
    }
}

struct HadithHeaderView: View {
    let hadith: Hadith
    @EnvironmentObject var localizationManager: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(hadith.collection)
                    .font(.headline)
                    .foregroundColor(.green)

                Spacer()

                Text(hadith.grade)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(4)
            }

            Text(hadith.reference)
                .font(.subheadline)
                .foregroundColor(.secondary)

            if !hadith.narrator.isEmpty {
                Text("\(localizationManager.localizedString(.narrator)): \(hadith.narrator)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct HadithTextSection: View {
    let title: String
    let text: String
    let isRTL: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)

            Text(text)
                .font(.body)
                .multilineTextAlignment(isRTL ? .trailing : .leading)
                .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(8)
                .shadow(radius: 1)
        }
    }
}

struct HadithMetadataView: View {
    let hadith: Hadith
    @EnvironmentObject var localizationManager: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localizationManager.localizedString(.details))
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                MetadataRow(label: localizationManager.localizedString(.collection), value: hadith.collection)
                MetadataRow(label: localizationManager.localizedString(.book), value: "\(hadith.bookNumber)")
                MetadataRow(label: localizationManager.localizedString(.hadithNumber), value: "\(hadith.hadithNumber)")
                MetadataRow(label: localizationManager.localizedString(.grade), value: hadith.grade)
                if !hadith.narrator.isEmpty {
                    MetadataRow(label: localizationManager.localizedString(.narrator), value: hadith.narrator)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
    }
}

struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
        }
    }
}

struct HadithActionsView: View {
    let hadith: Hadith
    let isSaved: Bool
    let onSave: () -> Void
    let onShare: () -> Void
    @EnvironmentObject var localizationManager: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localizationManager.localizedString(.actions))
                .font(.headline)

            HStack(spacing: 12) {
                Button(action: onSave) {
                    HStack {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        Text(isSaved ? localizationManager.localizedString(.save) : localizationManager.localizedString(.save))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isSaved ? Color.green : Color(.systemGray5))
                    .foregroundColor(isSaved ? .white : .primary)
                    .cornerRadius(8)
                }

                Button(action: onShare) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text(localizationManager.localizedString(.share))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
        }
    }
}

#Preview {
    NavigationView {
        HadithDetailView(hadith: Hadith(
            id: "preview-1",
            collection: "Sahih Bukhari",
            bookNumber: 1,
            hadithNumber: 1,
            arabicText: "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ",
            englishText: "In the name of Allah, the Most Gracious, the Most Merciful",
            russianText: "Во имя Аллаха, Милостивого, Милосердного",
            narrator: "Abu Huraira",
            grade: "Sahih",
            reference: "Bukhari 1:1"
        ))
        .environmentObject(AppSettings())
        .environmentObject(LocalizationManager.shared)
    }
}
