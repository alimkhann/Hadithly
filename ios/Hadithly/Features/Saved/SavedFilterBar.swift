import SwiftUI

enum SavedContentFilter: String, CaseIterable, Identifiable {
    case all, bookmarks, favorites, notes
    var id: Self { self }
    var title: String { switch self { case .all: "All"; case .bookmarks: "Bookmarks"; case .favorites: "Favorites"; case .notes: "Notes" } }
    var symbol: String { switch self { case .all: "square.stack"; case .bookmarks: "bookmark"; case .favorites: "heart"; case .notes: "note.text" } }
    var emptyTitle: String { switch self { case .all: "Nothing saved yet"; case .bookmarks: "No bookmarks yet"; case .favorites: "No favorites yet"; case .notes: "No notes yet" } }
    var emptyMessage: String { switch self {
    case .all: "Hold a hadith while reading to bookmark it, favorite it, or add a note."
    case .bookmarks: "Hold a hadith and choose Bookmark to keep your place here."
    case .favorites: "Hold a hadith and choose Favorite to find it here."
    case .notes: "Hold a hadith and choose Add note to keep your thoughts here."
    } }
}

struct SavedFilterBar: View {
    @Binding var selection: SavedContentFilter
    var identifier = "saved.filter"
    @Namespace private var highlight
    @Environment(\.layoutDirection) private var direction
    @Environment(\.readerPalette) private var palette
    @Environment(\.dynamicTypeSize) private var size
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var body: some View {
        Group {
            if size.isAccessibilitySize {
                Menu {
                    Picker("Saved filter", selection: $selection) {
                        ForEach(SavedContentFilter.allCases) { filter in Label(LocalizedStringKey(filter.title), systemImage: filter.symbol).tag(filter) }
                    }
                } label: {
                    Label(LocalizedStringKey(selection.title), systemImage: selection.symbol)
                        .font(.body.weight(.medium)).frame(maxWidth: .infinity, minHeight: 48)
                }.buttonStyle(.plain).accessibilityIdentifier(identifier)
            } else {
                GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(SavedContentFilter.allCases) { filter in
                        Button { selection = filter } label: {
                            VStack(spacing: 4) {
                                Image(systemName: filter.symbol + (selection == filter && filter != .notes ? ".fill" : ""))
                                    .font(.system(size: 18, weight: .medium))
                                Text(LocalizedStringKey(filter.title)).font(.caption2.weight(selection == filter ? .semibold : .regular))
                            }
                            .foregroundStyle(selection == filter ? palette.textPrimary : palette.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background {
                                if selection == filter {
                                    Capsule().fill(palette.interactiveSoft)
                                        .matchedGeometryEffect(id: "selection", in: highlight)
                                }
                            }
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(LocalizedStringKey(filter.title)))
                        .accessibilityAddTraits(selection == filter ? .isSelected : [])
                        .accessibilityIdentifier("\(identifier).\(filter.rawValue)")
                    }
                }.padding(4)
                .simultaneousGesture(DragGesture(minimumDistance: 6).onChanged { gesture in
                    guard abs(gesture.translation.width) > abs(gesture.translation.height) else { return }
                    let filters = SavedContentFilter.allCases
                    let physical = min(filters.count - 1, max(0, Int((gesture.location.x - 4) / max(1, (geometry.size.width - 8) / CGFloat(filters.count)))))
                    selection = filters[direction == .rightToLeft ? filters.count - 1 - physical : physical]
                })
                }.frame(height: 56)
            }
        }
        .readerControlSurface(in: Capsule())
        .animation(reducedMotion ? nil : .easeInOut(duration: InterfaceMotion.step), value: selection)
    }
}
