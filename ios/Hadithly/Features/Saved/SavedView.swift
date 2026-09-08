import ClerkKit
import SwiftUI

/// Saved: bookmarks, favorites, and notes — private to the reader. Each
/// category opens a bottom sheet over the current context, in the style of
/// the Sajda reference. Tapping an item reopens the reader at that hadith.
struct SavedView: View {
    enum Section: String, Identifiable, CaseIterable {
        case bookmarks
        case favorites
        case notes

        var id: String { rawValue }

        var title: String {
            switch self {
            case .bookmarks: return "Bookmarks"
            case .favorites: return "Favorites"
            case .notes: return "Notes"
            }
        }

        var systemImage: String {
            switch self {
            case .bookmarks: return "bookmark"
            case .favorites: return "heart"
            case .notes: return "square.and.pencil"
            }
        }

        var tint: Color {
            switch self {
            case .bookmarks: return Theme.bookmark
            case .favorites: return Theme.favorite
            case .notes: return Theme.accent
            }
        }
    }

    @Environment(AppEnvironment.self) private var environment
    @Environment(Clerk.self) private var clerk
    @Environment(UserLibraryModel.self) private var library

    @State private var activeSection: Section?
    @State private var openTarget: ReaderOpenTarget?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(Section.allCases) { section in
                    sectionCard(section)
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Saved")
        .navigationBarTitleDisplayMode(.large)
        .task { library.refresh() }
        .sheet(item: $activeSection) { section in
            SavedListSheet(
                section: section,
                onOpen: { ref in
                    activeSection = nil
                    openRef(ref)
                }
            )
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $openTarget) { target in
            ReaderView(
                collectionSlug: target.slug,
                collectionName: target.name,
                openVolumeId: target.volumeId,
                openHadithNumber: target.hadithNumber
            )
        }
    }

    private func entries(for section: Section) -> [SavedEntry] {
        switch section {
        case .bookmarks: return library.bookmarks
        case .favorites: return library.favorites
        case .notes: return library.notes
        }
    }

    private func sectionCard(_ section: Section) -> some View {
        let count = entries(for: section).count
        return Button {
            activeSection = section
        } label: {
            HStack(spacing: 14) {
                Image(systemName: section.systemImage)
                    .font(.body)
                    .foregroundStyle(section.tint)
                    .frame(width: 38, height: 38)
                    .background(section.tint.opacity(0.14))
                    .clipShape(Circle())

                Text(section.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)

                Image(systemName: "chevron.up")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("saved.section.\(section.rawValue)")
    }

    private func openRef(_ ref: HadithRef) {
        openTarget = ReaderOpenTarget(
            slug: ref.collectionSlug,
            name: ref.collectionName,
            volumeId: ref.volumeId,
            hadithNumber: ref.hadithNumber
        )
    }
}

// MARK: - Bottom sheet list

private struct SavedListSheet: View {
    let section: SavedView.Section
    let onOpen: (HadithRef) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(UserLibraryModel.self) private var library

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(entries) { entry in
                                SavedEntryRow(
                                    entry: entry,
                                    section: section,
                                    onOpen: onOpen
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle(section.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var entries: [SavedEntry] {
        switch section {
        case .bookmarks: return library.bookmarks
        case .favorites: return library.favorites
        case .notes: return library.notes
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: section.systemImage)
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
            Text("Nothing saved yet")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
            Text("While reading, tap the \(section.title.lowercased()) action under a hadith.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

// MARK: - One row

private struct SavedEntryRow: View {
    let entry: SavedEntry
    let section: SavedView.Section
    let onOpen: (HadithRef) -> Void

    @Environment(UserLibraryModel.self) private var library

    var body: some View {
        Group {
            if let ref = entry.hadith {
                rowBody(ref)
            }
        }
    }

    private func rowBody(_ ref: HadithRef) -> some View {
        Button {
            onOpen(ref)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(ref.referenceDisplay.isEmpty ? ref.collectionName : ref.referenceDisplay)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    if section == .notes {
                        deleteButton(ref)
                    } else {
                        removeButton(ref)
                    }
                }

                if !ref.arabicText.isEmpty {
                    Text(ref.arabicText)
                        .font(Theme.arabic(17))
                        .lineSpacing(17 * 0.7)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(3)
                }

                if let note = entry.noteContent, !note.isEmpty {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(section.tint.opacity(0.9))
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func removeButton(_ ref: HadithRef) -> some View {
        Button {
            switch section {
            case .bookmarks: library.toggleBookmark(ref)
            case .favorites: library.toggleFavorite(ref)
            case .notes: library.deleteNote(ref)
            }
        } label: {
            Image(systemName: "xmark")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove")
    }

    private func deleteButton(_ ref: HadithRef) -> some View {
        Button {
            library.deleteNote(ref)
        } label: {
            Image(systemName: "trash")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.destructive)
                .padding(6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete note")
    }
}
