import SwiftUI

/// One private Saved list. A row may carry every saved meaning without being repeated.
struct SavedView: View {
    private enum Filter: String, CaseIterable, Identifiable { case all, bookmarks, favorites, notes; var id: Self { self }; var title: LocalizedStringKey { switch self { case .all: "All"; case .bookmarks: "Bookmarks"; case .favorites: "Favorites"; case .notes: "Notes" } } }
    @Environment(UserLibraryModel.self) private var library
    @State private var filter: Filter = .all
    @State private var folderId: String?
    @State private var openTarget: ReaderOpenTarget?
    @State private var newFolderName = ""
    @State private var showNewFolder = false

    private var items: [SavedItemEntry] {
        library.savedItems.filter { item in
            let facet = switch filter { case .all: true; case .bookmarks: item.bookmarkCreatedAt != nil; case .favorites: item.favoriteCreatedAt != nil; case .notes: item.noteContent != nil }
            return facet && (folderId == nil || item.folderId == folderId)
        }.sorted { $0.sortDate > $1.sortDate }
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("Saved filter", selection: $filter) { ForEach(Filter.allCases) { Text($0.title).tag($0) } }
                .pickerStyle(.segmented).accessibilityLabel("Saved filter")
            folders
            if items.isEmpty {
                ContentUnavailableView("Nothing saved yet", systemImage: "bookmark", description: Text("Bookmark, favorite, or add a note while reading to keep a hadith here."))
            } else {
                List(items) { item in
                    if let hadith = item.hadith {
                        Button { openTarget = ReaderOpenTarget(slug: hadith.collectionSlug, name: hadith.collectionName, volumeId: hadith.volumeId, hadithNumber: hadith.hadithNumber, source: .saved) } label: {
                            SavedItemRow(item: item, folderName: library.folders.first(where: { $0.id == item.folderId })?.name)
                        }.buttonStyle(.plain).accessibilityHint("Opens this hadith").contextMenu { itemMenu(item, hadith: hadith) }
                    }
                }.listStyle(.plain)
            }
        }
        .padding(.horizontal).navigationTitle("Saved")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("New folder", systemImage: "folder.badge.plus") { showNewFolder = true }.accessibilityLabel("Create saved folder") } }
        .safeAreaInset(edge: .bottom) {
            if let deletion = library.lastFolderDeletion {
                HStack {
                    Text("Folder \(deletion.name) deleted")
                    Spacer()
                    Button("Undo") { library.undoDeleteFolder() }
                        .accessibilityLabel("Undo deleting folder \(deletion.name)")
                }
                .padding(12)
                .background(Theme.surface)
            }
        }
        .alert("New folder", isPresented: $showNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) { newFolderName = "" }
            Button("Create") { library.createFolder(name: newFolderName); newFolderName = "" }
        } message: { Text("Folders are private and can contain saved hadiths.") }
        .fullScreenCover(item: $openTarget) { target in ReaderView(collectionSlug: target.slug, collectionName: target.name, openVolumeId: target.volumeId, openHadithNumber: target.hadithNumber, targetSource: target.source) }
    }

    private var folders: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button("All folders") { folderId = nil }.buttonStyle(.borderedProminent).tint(folderId == nil ? Theme.accent : Theme.surface)
                ForEach(library.folders) { folder in
                    Menu {
                        Button("Show folder") { folderId = folder.id }
                        Button("Delete folder", role: .destructive) {
                            if folderId == folder.id { folderId = nil }
                            library.deleteFolder(folder)
                        }
                    } label: { Label(folder.name, systemImage: "folder") }
                        .buttonStyle(.bordered).tint(folderId == folder.id ? Theme.accent : Theme.textSecondary)
                }
            }
        }.accessibilityLabel("Saved folders")
    }

    @ViewBuilder private func itemMenu(_ item: SavedItemEntry, hadith: HadithRef) -> some View {
        Menu("Move to folder") { Button("No folder") { library.assignFolder(hadithId: item.hadithId, folderId: nil) }; ForEach(library.folders) { folder in Button(folder.name) { library.assignFolder(hadithId: item.hadithId, folderId: folder.id) } } }
        if item.bookmarkCreatedAt != nil { Button("Remove bookmark", role: .destructive) { library.toggleBookmark(hadith) } }
        if item.favoriteCreatedAt != nil { Button("Remove favorite", role: .destructive) { library.toggleFavorite(hadith) } }
        if item.noteContent != nil { Button("Delete note", role: .destructive) { library.deleteNote(hadith) } }
    }
}

private struct SavedItemRow: View {
    let item: SavedItemEntry
    let folderName: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(item.hadith?.referenceDisplay ?? "Saved hadith").font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                if item.bookmarkCreatedAt != nil { Image(systemName: "bookmark.fill").foregroundStyle(Theme.bookmark).accessibilityLabel("Bookmarked") }
                if item.favoriteCreatedAt != nil { Image(systemName: "heart.fill").foregroundStyle(Theme.favorite).accessibilityLabel("Favorite") }
                if item.noteContent != nil { Image(systemName: "square.and.pencil").foregroundStyle(Theme.accent).accessibilityLabel("Has note") }
            }
            if let folderName { Label(folderName, systemImage: "folder").font(.caption).foregroundStyle(Theme.textSecondary) }
            if let note = item.noteContent, !note.isEmpty { Text(note).font(.subheadline).foregroundStyle(Theme.textSecondary).lineLimit(2) }
            if let arabic = item.hadith?.arabicText, !arabic.isEmpty { Text(arabic).font(.body).foregroundStyle(Theme.textPrimary).lineLimit(2) }
        }.padding(.vertical, 6)
    }
}
