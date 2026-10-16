import SwiftUI
import UIKit

private struct SavedUndoPresenterKey: EnvironmentKey {
    static let defaultValue: ((SavedUndoNotice) -> Void)? = nil
}
extension EnvironmentValues {
    var presentSavedUndo: ((SavedUndoNotice) -> Void)? {
        get { self[SavedUndoPresenterKey.self] }
        set { self[SavedUndoPresenterKey.self] = newValue }
    }
}

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
    var id = UUID()
    let message: String
    let undo: () -> Void
    var deadline = Date.now.addingTimeInterval(SavedUndoDeadline.duration)
}

/// Bottom-placed undo toast with a five-second countdown ring. The host
/// view owns the notice lifetime, so the banner only reports expiry.
struct SavedUndoBanner: View {
    let notice: SavedUndoNotice
    var onExpire: (() -> Void)? = nil

    @Environment(\.readerPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(palette.textSecondary)
            Text(notice.message).font(.subheadline.weight(.medium))
            Spacer()
            Button {
                notice.undo()
                withAnimation(reducedMotion ? nil : .easeOut(duration: InterfaceMotion.quick)) { onExpire?() }
            } label: {
                HStack(spacing: 6) {
                    Text("Undo").fontWeight(.semibold)
                    CountdownRing(deadline: notice.deadline)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("saved.undoButton")
        }
        .foregroundStyle(palette.textPrimary)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("saved.undoBanner")
        .transition(reducedMotion ? .opacity : .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
        .task(id: notice.id) {
            do { try await Task.sleep(for: .seconds(max(0, notice.deadline.timeIntervalSinceNow))) }
            catch { return }
            withAnimation(reducedMotion ? nil : .easeOut(duration: InterfaceMotion.quick)) { onExpire?() }
        }
    }
}

/// Small ring that empties over five seconds, matching the banner deadline.
struct CountdownRing: View {
    let deadline: Date
    @Environment(\.readerPalette) private var palette
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var body: some View {
        TimelineView(.animation(paused: scenePhase != .active || reducedMotion)) { context in
            Canvas { graphics, size in
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
                graphics.stroke(Path(ellipseIn: rect), with: .color(palette.textSecondary.opacity(0.25)), lineWidth: 2)
                guard !reducedMotion else { return }
                let progress = min(1, max(0, deadline.timeIntervalSince(context.date) / SavedUndoDeadline.duration))
                var arc = Path()
                arc.addArc(center: CGPoint(x: size.width / 2, y: size.height / 2), radius: (min(size.width, size.height) - 2) / 2,
                    startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * progress), clockwise: false)
                graphics.stroke(arc, with: .color(palette.textSecondary), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }.frame(width: 16, height: 16).accessibilityHidden(true)
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

    @Environment(\.readerPalette) private var palette
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var body: some View {
        if let ref = item.hadith {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button { onOpen(ref) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ref.referenceDisplay.isEmpty ? ref.collectionName : ref.referenceDisplay)
                                .font(.subheadline.weight(.semibold)).foregroundStyle(palette.textPrimary).lineLimit(2)
                            HStack(spacing: 6) {
                                if item.bookmarkCreatedAt != nil { Image(systemName: "bookmark.fill").foregroundStyle(Theme.bookmark).accessibilityLabel("Bookmarked") }
                                if item.favoriteCreatedAt != nil { Image(systemName: "heart.fill").foregroundStyle(Theme.favorite).accessibilityLabel("Favorite") }
                                if item.noteContent != nil { Image(systemName: "note.text").foregroundStyle(palette.textPrimary).accessibilityLabel("Has note") }
                                Text(SavedRelativeTime.string(since: item.sortDate))
                            }.font(.caption).foregroundStyle(palette.textSecondary)
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
                    Label(folderName, systemImage: "folder").font(.caption).foregroundStyle(palette.textSecondary)
                }
                if let note = item.noteContent, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(palette.textSecondary).lineLimit(expanded ? nil : 2)
                }
                if expanded {
                    if !ref.arabicText.isEmpty { Text(ref.arabicText).font(Theme.arabic(19)).frame(maxWidth: .infinity, alignment: .trailing).environment(\.layoutDirection, .rightToLeft) }
                    if let english = ref.englishText, !english.isEmpty { Text(english).font(.subheadline).foregroundStyle(palette.textSecondary) }
                }
            }
            .padding(14)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
