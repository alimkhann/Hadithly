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
    let deadline = Date.now.addingTimeInterval(5)
}

enum SavedUndoDeadline {
    static let duration: TimeInterval = 5
}

/// Bottom-placed undo toast with a five-second countdown ring. The host
/// view owns the notice lifetime, so the banner only reports expiry.
struct SavedUndoBanner: View {
    let notice: SavedUndoNotice
    var onExpire: (() -> Void)? = nil

    @State private var startedAt = Date.now

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(Theme.accent)
            Text(notice.message).font(.subheadline.weight(.medium))
            Spacer()
            Button {
                notice.undo()
            } label: {
                HStack(spacing: 6) {
                    Text("Undo").fontWeight(.semibold)
                    CountdownRing(deadline: startedAt.addingTimeInterval(SavedUndoDeadline.duration))
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("saved.undoButton")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("saved.undoBanner")
        .task(id: notice.id) {
            startedAt = Date.now
            try? await Task.sleep(for: .seconds(SavedUndoDeadline.duration))
            onExpire?()
        }
    }
}

/// Small ring that empties over five seconds, matching the banner deadline.
struct CountdownRing: View {
    let deadline: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let remaining = max(0, deadline.timeIntervalSince(context.date))
            let progress = SavedUndoDeadline.duration <= 0 ? 0 : remaining / SavedUndoDeadline.duration
            ZStack {
                Circle().stroke(Theme.textSecondary.opacity(0.25), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        progress > 0.2 ? Theme.textSecondary : Theme.accent,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
        }
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
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var body: some View {
        if let ref = item.hadith {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button { onOpen(ref) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ref.referenceDisplay.isEmpty ? ref.collectionName : ref.referenceDisplay)
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(2)
                            HStack(spacing: 6) {
                                if item.bookmarkCreatedAt != nil { Image(systemName: "bookmark.fill").accessibilityLabel("Bookmarked") }
                                if item.favoriteCreatedAt != nil { Image(systemName: "heart.fill").accessibilityLabel("Favorite") }
                                if item.noteContent != nil { Image(systemName: "note.text").accessibilityLabel("Has note") }
                                Text(SavedRelativeTime.string(since: item.sortDate))
                            }.font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityHint("Opens this hadith in the reader")
                    .accessibilityIdentifier("saved.open.\(item.hadithId)")

                    Menu { rowActions(ref) } label: {
                        Image(systemName: "ellipsis").font(.body).frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Saved item actions")

                    Button {
                        withAnimation(reducedMotion ? nil : .easeInOut(duration: InterfaceMotion.step)) { expanded.toggle() }
                    } label: {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(expanded ? "Hide hadith preview" : "Show hadith preview")
                    .accessibilityIdentifier("saved.preview.\(item.hadithId)")
                }

                if showsFolder, let folderName {
                    Label(folderName, systemImage: "folder").font(.caption).foregroundStyle(Theme.textSecondary)
                }
                if let note = item.noteContent, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(expanded ? nil : 2)
                }
                if expanded {
                    if !ref.arabicText.isEmpty { Text(ref.arabicText).font(Theme.arabic(19)).frame(maxWidth: .infinity, alignment: .trailing).environment(\.layoutDirection, .rightToLeft) }
                    if let english = ref.englishText, !english.isEmpty { Text(english).font(.subheadline).foregroundStyle(Theme.textSecondary) }
                }
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contextMenu { rowActions(ref) }
        }
    }

    @ViewBuilder
    private func rowActions(_ ref: HadithRef) -> some View {
                Menu("Move to folder") { Button("No folder") { onMove(nil) }; ForEach(folders) { folder in Button(folder.name) { onMove(folder.id) } } }
                if item.bookmarkCreatedAt != nil { Button("Remove bookmark", role: .destructive) { onRemove(.bookmark(item, ref)) } }
                if item.favoriteCreatedAt != nil { Button("Remove favorite", role: .destructive) { onRemove(.favorite(item, ref)) } }
                if item.noteContent != nil { Button("Delete note", role: .destructive) { onRemove(.note(item, ref)) } }
                Button("Copy") { UIPasteboard.general.string = [ref.arabicText, ref.englishText, ref.referenceDisplay].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n") }
                if let url = URL(string: "https://hadithly.app/hadith/\(ref.collectionSlug)/\(ref.hadithNumber ?? "")") { ShareLink(item: url) { Text("Share") } }
                Button("Suggest Translation") { onSuggestTranslation(ref) }
    }
}
