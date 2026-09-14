import SwiftUI
import UIKit

enum SavedFacetRemoval: Identifiable {
    case bookmark(SavedItemEntry, HadithRef)
    case favorite(SavedItemEntry, HadithRef)
    case note(SavedItemEntry, HadithRef)

    var id: String {
        switch self {
        case .bookmark(let item, _): "bookmark-\(item.hadithId)"
        case .favorite(let item, _): "favorite-\(item.hadithId)"
        case .note(let item, _): "note-\(item.hadithId)"
        }
    }
}

struct SavedUndoNotice: Identifiable {
    let id = UUID()
    let message: String
    let undo: () -> Void
}

struct SavedUndoBanner: View {
    let notice: SavedUndoNotice

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(Theme.accent)
            Text(notice.message).font(.subheadline.weight(.medium))
            Spacer()
            Button("Undo", action: notice.undo).fontWeight(.semibold)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("saved.undoBanner")
    }
}

struct SharedSavedItemRow: View {
    let item: SavedItemEntry
    let folders: [SavedFolder]
    let folderName: String?
    let showsFolder: Bool
    let onOpen: (HadithRef) -> Void
    let onRemove: (SavedFacetRemoval) -> Void
    let onMove: (String?) -> Void
    let onSuggestTranslation: (HadithRef) -> Void

    @State private var expanded = false

    var body: some View {
        if let ref = item.hadith {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button { onOpen(ref) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ref.referenceDisplay.isEmpty ? ref.collectionName : ref.referenceDisplay)
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                            Text(SavedRelativeTime.string(since: item.sortDate))
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityHint("Opens this hadith in the reader")
                    .accessibilityIdentifier("saved.open.\(item.hadithId)")

                    if item.bookmarkCreatedAt != nil { facetButton("bookmark.fill", color: Theme.bookmark, label: "Remove bookmark") { onRemove(.bookmark(item, ref)) } }
                    if item.favoriteCreatedAt != nil { facetButton("heart.fill", color: Theme.favorite, label: "Remove favorite") { onRemove(.favorite(item, ref)) } }
                    if item.noteContent != nil { facetButton("square.and.pencil", color: Theme.accent, label: "Delete note") { onRemove(.note(item, ref)) } }

                    Menu {
                        Button("No folder") { onMove(nil) }
                        ForEach(folders) { folder in Button(folder.name) { onMove(folder.id) } }
                    } label: {
                        Image(systemName: "folder").frame(width: 30, height: 30)
                    }
                    .accessibilityLabel("Move to folder")

                    Button { expanded.toggle() } label: {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(expanded ? "Hide hadith preview" : "Show hadith preview")
                    .accessibilityIdentifier("saved.preview.\(item.hadithId)")
                }

                if showsFolder, let folderName {
                    Label(folderName, systemImage: "folder").font(.caption).foregroundStyle(Theme.textSecondary)
                }
                if let note = item.noteContent, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(expanded ? nil : 1)
                }
                if expanded {
                    if !ref.arabicText.isEmpty { Text(ref.arabicText).font(Theme.arabic(19)).frame(maxWidth: .infinity, alignment: .trailing).environment(\.layoutDirection, .rightToLeft) }
                    if let english = ref.englishText, !english.isEmpty { Text(english).font(.subheadline).foregroundStyle(Theme.textSecondary) }
                }
                Divider()
            }
            .padding(.top, 8)
            .contextMenu {
                Menu("Move to folder") { Button("No folder") { onMove(nil) }; ForEach(folders) { folder in Button(folder.name) { onMove(folder.id) } } }
                if item.bookmarkCreatedAt != nil { Button("Remove bookmark", role: .destructive) { onRemove(.bookmark(item, ref)) } }
                if item.favoriteCreatedAt != nil { Button("Remove favorite", role: .destructive) { onRemove(.favorite(item, ref)) } }
                if item.noteContent != nil { Button("Delete note", role: .destructive) { onRemove(.note(item, ref)) } }
                Button("Copy") { UIPasteboard.general.string = [ref.arabicText, ref.englishText, ref.referenceDisplay].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n") }
                if let url = URL(string: "https://hadithly.app/hadith/\(ref.collectionSlug)/\(ref.hadithNumber ?? "")") { ShareLink(item: url) { Text("Share") } }
                Button("Suggest Translation") { onSuggestTranslation(ref) }
            }
        }
    }

    private func facetButton(_ image: String, color: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: image).foregroundStyle(color).frame(width: 26, height: 30) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }
}
