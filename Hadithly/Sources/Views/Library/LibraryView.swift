import SwiftUI

struct LibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var localizationManager: LocalizationManager

    var body: some View {
        NavigationView {
            VStack {
                // Segmented Control
                Picker("View", selection: $viewModel.selectedView) {
                    Text(localizationManager.localizedString(.saved)).tag(LibraryViewType.saved)
                    Text(localizationManager.localizedString(.folders)).tag(LibraryViewType.folders)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                // Content
                switch viewModel.selectedView {
                case .saved:
                    SavedHadithsView(hadiths: viewModel.savedHadiths)
                case .folders:
                    FoldersView(folders: viewModel.folders)
                }
            }
            .navigationTitle(localizationManager.localizedString(.library))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(localizationManager.localizedString(.export)) {
                        viewModel.exportData()
                    }
                }
            }
        }
        .task {
            await viewModel.loadData()
        }
    }
}

enum LibraryViewType {
    case saved
    case folders
}

struct SavedHadithsView: View {
    let hadiths: [Hadith]
    @EnvironmentObject var localizationManager: LocalizationManager

    var body: some View {
        if hadiths.isEmpty {
            EmptyLibraryView(
                title: localizationManager.localizedString(.noSavedHadiths),
                message: localizationManager.localizedString(.hadithsYouSaveWillAppearHere),
                icon: "bookmark"
            )
        } else {
            List(hadiths) { hadith in
                NavigationLink(destination: HadithDetailView(hadith: hadith)) {
                    SavedHadithRow(hadith: hadith)
                }
            }
            .listStyle(PlainListStyle())
        }
    }
}

struct SavedHadithRow: View {
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

            // Reference and collection
            HStack {
                Text(hadith.reference)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(hadith.collection)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct FoldersView: View {
    let folders: [UserFolder]
    @EnvironmentObject var localizationManager: LocalizationManager

    var body: some View {
        if folders.isEmpty {
            EmptyLibraryView(
                title: localizationManager.localizedString(.noFolders),
                message: localizationManager.localizedString(.createFoldersToOrganizeYourSavedHadiths),
                icon: "folder"
            )
        } else {
            List(folders) { folder in
                NavigationLink(destination: FolderDetailView(folder: folder)) {
                    FolderRow(folder: folder)
                }
            }
            .listStyle(PlainListStyle())
        }
    }
}

struct FolderRow: View {
    let folder: UserFolder

    var body: some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundColor(.green)

            VStack(alignment: .leading, spacing: 4) {
                Text(folder.name)
                    .font(.headline)

                Text("\(folder.hadithIds.count) hadiths")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct EmptyLibraryView: View {
    let title: String
    let message: String
    let icon: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct FolderDetailView: View {
    let folder: UserFolder
    @StateObject private var viewModel = FolderDetailViewModel()

    var body: some View {
        List {
            ForEach(viewModel.hadiths) { hadith in
                NavigationLink(destination: HadithDetailView(hadith: hadith)) {
                    SavedHadithRow(hadith: hadith)
                }
            }
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.loadHadiths(for: folder)
        }
    }
}

#Preview {
    LibraryView()
        .environmentObject(AppSettings())
        .environmentObject(LocalizationManager.shared)
}
