import SwiftUI

/// One private Saved list. A row may carry every saved meaning without being repeated.
struct SavedView: View {
    private typealias Filter = SavedContentFilter
    @Environment(UserLibraryModel.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(AppEnvironment.self) private var environment
    @State private var filter: Filter = .all
    @State private var folderId: String?
    @State private var openTarget: ReaderOpenTarget?
    @State private var newFolderName = ""
    @State private var showNewFolder = false
    @State private var newFolderScope: UUID?
    @State private var pendingRemoval: SavedFacetRemoval?
    @State private var pendingRemovalScope: UUID?
    @State private var undoNotice: SavedUndoNotice?

#if DEBUG
    private var previewState: UserLibraryModel.LoadState?
    init(previewState: UserLibraryModel.LoadState? = nil) { self.previewState = previewState }
#endif

    private var currentLoadState: UserLibraryModel.LoadState {
#if DEBUG
        if let previewState { return previewState }
#endif
        return library.loadState
    }

    private var items: [SavedItemEntry] {
#if DEBUG
        if previewState != nil { return [] }
#endif
        return library.savedItems.filter { item in
            let facet = switch filter { case .all: true; case .bookmarks: item.bookmarkCreatedAt != nil; case .favorites: item.favoriteCreatedAt != nil; case .notes: item.noteContent != nil }
            return facet && (folderId == nil || item.folderId == folderId)
        }.sorted { $0.sortDate > $1.sortDate }
    }

    var body: some View {
        VStack(spacing: 12) {
            if !library.folders.isEmpty { folders }
            if library.savedItems.isEmpty && currentLoadState == .loading {
                ContentSkeleton(kind: .rows, label: "Loading saved items")
                    .padding(.top, 20)
                Spacer()
            } else if library.savedItems.isEmpty && currentLoadState == .failed {
                ContentUnavailableView {
                    Label("Saved items could not load", systemImage: "wifi.exclamationmark")
                } actions: {
                    Button("Try again") { library.refresh() }
                }
            } else if items.isEmpty {
                SavedEmptyState(filter: filter, isFolder: folderId != nil)
            } else {
                List(items) { item in
                    if item.hadith != nil {
                        SharedSavedItemRow(
                            item: item,
                            folders: library.folders,
                            folderName: library.folders.first(where: { $0.id == item.folderId })?.name,
                            showsFolder: folderId == nil,
                            onOpen: open,
                            onRemove: { [scope = library.actionScope] in requestRemoval($0, scope: scope) },
                            onMove: { [scope = library.actionScope] in if library.isActionCurrent(scope) { library.assignFolder(hadithId: item.hadithId, folderId: $0, scope: scope) } },
                            onSuggestTranslation: open
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    }
                }.listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
        .safeAreaInset(edge: .bottom) {
            SavedFilterBar(selection: $filter).padding(.vertical, 8)
        }
        .animation(reducedMotion ? nil : .easeInOut(duration: InterfaceMotion.reveal), value: currentLoadState)
        .animation(reducedMotion ? nil : .easeInOut(duration: InterfaceMotion.quick), value: filter)
        .animation(reducedMotion ? nil : .easeInOut(duration: InterfaceMotion.quick), value: folderId)
        .task {
#if DEBUG
            if previewState != nil { return }
#endif
            library.refresh()
        }
        .padding(.horizontal).appNavigationTitle("Saved")
        .background(Theme.background.ignoresSafeArea())
        .onChange(of: library.actionScope) { _, _ in
            pendingRemoval = nil; pendingRemovalScope = nil; undoNotice = nil
            showNewFolder = false; newFolderName = ""; newFolderScope = nil; folderId = nil
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("New folder", systemImage: "folder.badge.plus") { newFolderScope = library.actionScope; showNewFolder = true }.accessibilityLabel("Create saved folder") } }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let notice = undoNotice {
                SavedUndoBanner(notice: notice, onExpire: { undoNotice = nil })

            } else if let deletion = library.lastFolderDeletion {
                SavedUndoBanner(notice: SavedUndoNotice(id: deletion.undoID, message: "Folder \(deletion.name) deleted", undo: library.undoDeleteFolder, deadline: deletion.undoDeadline), onExpire: { library.clearFolderDeletion() })

            }
        }
        .animation(reducedMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: InterfaceMotion.reveal), value: undoNotice?.id)
        .animation(reducedMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: InterfaceMotion.reveal), value: library.lastFolderDeletion?.undoID)
        .confirmationDialog("Remove saved item?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            if let removal = pendingRemoval {
            Button("Remove", role: .destructive) { performRemoval(removal); pendingRemoval = nil }
            Button("Remove and don't ask again", role: .destructive) { environment.savedSafety.confirmsRemoval = false; performRemoval(removal); pendingRemoval = nil }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("You can undo this action for five seconds from the message at the bottom.") }
        .alert("New folder", isPresented: $showNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) { newFolderName = "" }
            Button("Create") { if let scope = newFolderScope { library.createFolder(name: newFolderName, scope: scope) }; newFolderName = "" }
        } message: { Text("Folders are private and can contain saved hadiths.") }
        .fullScreenCover(item: $openTarget) { target in ReaderView(collectionSlug: target.slug, collectionName: target.name, openVolumeId: target.volumeId, openHadithNumber: target.hadithNumber, targetSource: target.source) }
    }

    private var folders: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button("All folders") { folderId = nil }
                    .buttonStyle(.bordered)
                    .tint(folderId == nil ? Theme.accent : Theme.textSecondary)
                ForEach(library.folders) { folder in
                    Button { folderId = folder.id } label: {
                        Label(folder.name, systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .tint(folderId == folder.id ? Theme.accent : Theme.textSecondary)
                    .contextMenu { [scope = library.actionScope] in
                        Button("Delete folder", role: .destructive) {
                            if folderId == folder.id { folderId = nil }
                            library.deleteFolder(folder, scope: scope)
                        }
                    }
                    .accessibilityAction(named: "Delete folder") { [scope = library.actionScope] in
                        if folderId == folder.id { folderId = nil }
                        library.deleteFolder(folder, scope: scope)
                    }
                    .accessibilityHint("Opens this folder. Long press for folder actions.")
                }
            }
        }.accessibilityLabel("Saved folders")
    }

    private func open(_ ref: HadithRef) {
        openTarget = ReaderOpenTarget(slug: ref.collectionSlug, name: ref.collectionName, volumeId: ref.volumeId, hadithNumber: ref.hadithNumber, source: .saved)
    }

    private func requestRemoval(_ removal: SavedFacetRemoval, scope: UUID) {
        if environment.savedSafety.confirmsRemoval { pendingRemovalScope = scope; pendingRemoval = removal } else { performRemoval(removal, scope: scope) }
    }

    private func performRemoval(_ removal: SavedFacetRemoval, scope: UUID? = nil) {
        guard library.isActionCurrent(scope ?? pendingRemovalScope) else { return }
        switch removal {
        case .bookmark(let item, let ref):
            guard let createdAt = item.bookmarkCreatedAt else { return }
            guard library.removeBookmark(ref, scope: scope ?? pendingRemovalScope ?? library.actionScope) else { return }
            undoNotice = SavedUndoNotice(message: "Bookmark removed") { library.restoreBookmark(ref, createdAt: createdAt); undoNotice = nil }
        case .favorite(let item, let ref):
            guard let createdAt = item.favoriteCreatedAt else { return }
            guard library.removeFavorite(ref, scope: scope ?? pendingRemovalScope ?? library.actionScope) else { return }
            undoNotice = SavedUndoNotice(message: "Favorite removed") { library.restoreFavorite(ref, createdAt: createdAt); undoNotice = nil }
        case .note(let item, let ref):
            guard let content = item.noteContent else { return }
            guard library.deleteNote(ref, scope: scope ?? pendingRemovalScope ?? library.actionScope) else { return }
            undoNotice = SavedUndoNotice(message: "Note deleted") { library.restoreNote(ref, content: content, createdAt: item.createdAt, updatedAt: item.updatedAt); undoNotice = nil }
        }
    }
}
