import Foundation
import SwiftUI

/// Slice A (R6): Sajda-quiet page view-model logic.
///
/// Every type here is pure and UI-framework-free except for the grade-dot
/// color resolver, so the full slice-A contract is provable in unit tests:
/// grade mapping, compact source labels, bracketed header text, narrator
/// visibility, saved-state markers, chapter subtitles, volume corner/range
/// rules, and the per-block action set. Copy/share payloads are untouched
/// (`ReaderShare` keeps the full source line).
enum ReaderGradeKind: String, Equatable {
    case sahih
    case hasan
    case daif
    case unverified

    init(normalizedGrade: String?) {
        switch normalizedGrade?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        {
        case "sahih":
            self = .sahih
        case "hasan":
            self = .hasan
        case "daif", "dhaif", "daeef":
            self = .daif
        default:
            self = .unverified
        }
    }

    var accessibilityName: String {
        switch self {
        case .sahih: "Sahih"
        case .hasan: "Hasan"
        case .daif: "Daif"
        case .unverified: "Unverified"
        }
    }
}

/// The grade dot beside the compact source label. Colors are fixed pairs —
/// a brighter value on dark backgrounds, a darker value on light/paper —
/// so the dot stays visible on all four reader themes.
enum ReaderGradeDot {
    static func hex(for kind: ReaderGradeKind, dark: Bool) -> String {
        switch (kind, dark) {
        case (.sahih, true): "34D399"
        case (.sahih, false): "15803D"
        case (.hasan, true): "FBBF24"
        case (.hasan, false): "B45309"
        case (.daif, true): "F87171"
        case (.daif, false): "B91C1C"
        case (.unverified, true): "9CA3AF"
        case (.unverified, false): "6B7280"
        }
    }

    static func color(for kind: ReaderGradeKind, palette: ReaderPalette) -> Color {
        Color(hex: hex(for: kind, dark: palette == .dark))
    }
}

/// The compact tappable source label: `short name – provider id`.
/// The full source line stays in copy/share payloads; the page shows only
/// this quiet label with the grade dot before it.
enum ReaderSourceLabel {
    static func shortName(collectionSlug: String, collectionName: String) -> String {
        switch collectionSlug {
        case "bukhari": "Bukhari"
        case "muslim": "Muslim"
        case "sunan-nasai": "Nasa'i"
        case "abu-dawood": "Abu Dawud"
        case "tirmidhi": "Tirmidhi"
        case "ibn-majah": "Ibn Majah"
        case "mishkat-al-masabih": "Mishkat"
        default: collectionName
        }
    }

    static func text(for hadith: ReaderHadith) -> String {
        "\(shortName(collectionSlug: hadith.collectionSlug, collectionName: hadith.collectionName)) – \(hadith.providerHadithId)"
    }

    /// The per-hadith header label (`Bukhari – 57`). The header row pairs this with the grade dot
    /// before it and the saved-state mini markers after it; the whole
    /// header is the single tap target for the source sheet.
    static func headerText(for hadith: ReaderHadith) -> String {
        text(for: hadith)
    }
}

/// The narrator line shows in every visibility mode (round-2 correction):
/// it is hidden only when there is no narrator text or when both text
/// layers are hidden (a state the F2 contract rejects before it renders).
enum ReaderNarratorLine {
    static func shouldShow(
        narrator: String?,
        arabicVisible: Bool,
        translationVisible: Bool
    ) -> Bool {
        guard arabicVisible || translationVisible else { return false }
        guard let narrator = narrator?.trimmingCharacters(in: .whitespacesAndNewlines),
              !narrator.isEmpty
        else { return false }
        return true
    }
}

/// Where the narrator sits. Mixed and translation-only modes keep the
/// leading-edge line below the Arabic block (beside the translation).
/// Arabic-only mode puts the narrator between the hadith header label and
/// the Arabic block, aligned to the Arabic direction.
enum ReaderNarratorPlacement: Equatable {
    case aboveArabic
    case belowArabic

    static func placement(arabicVisible: Bool, translationVisible: Bool) -> ReaderNarratorPlacement {
        if arabicVisible, !translationVisible {
            return .aboveArabic
        }
        return .belowArabic
    }
}

/// Saved-state mini markers: small non-interactive indicators inline after
/// the header label. Bookmark first, then favorite. No note icon — notes
/// stay reachable through the long-press menu and VoiceOver actions only.
enum ReaderSavedMarker: Hashable {
    case bookmark
    case favorite
}

enum ReaderSavedMarkers {
    static func visible(bookmarked: Bool, favorited: Bool) -> [ReaderSavedMarker] {
        var markers: [ReaderSavedMarker] = []
        if bookmarked { markers.append(.bookmark) }
        if favorited { markers.append(.favorite) }
        return markers
    }
}

/// The seven R5 actions. The sighted path is the long-press context menu;
/// VoiceOver custom actions are the screen-reader equivalent. Report stays
/// gated on a loaded non-English translation, exactly like the menu.
enum ReaderHadithAction: String, CaseIterable, Equatable {
    case bookmark
    case favorite
    case note
    case copy
    case share
    case report
    case suggest
}

enum ReaderHadithActions {
    static func available(hasLoadedTranslation: Bool) -> [ReaderHadithAction] {
        hasLoadedTranslation
            ? ReaderHadithAction.allCases
            : ReaderHadithAction.allCases.filter { $0 != .report }
    }
}

/// Chapter transition subtitle: the Arabic title renders as a second line
/// only when the source provided one and it differs from the title.
/// Hadith rows carry no Arabic chapter title, so the outline's
/// source-provided chapters are consulted by chapter id. Nothing is
/// synthesized: no match means no subtitle.
enum ReaderChapterLine {
    static func arabicSubtitle(title: String, arabicTitle: String?, arabicVisible: Bool) -> String? {
        guard arabicVisible else { return nil }
        guard let arabic = arabicTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !arabic.isEmpty, arabic != title
        else { return nil }
        return arabic
    }

    static func arabicTitle(
        forChapterId chapterId: String?,
        in volumes: [OutlineVolume],
        volumeId: String?
    ) -> String? {
        guard let chapterId, !chapterId.isEmpty else { return nil }
        let chapters = volumes.first { $0.volumeId == volumeId }?.chapters ?? []
        return chapters.first { $0.chapterId == chapterId }?.arabicTitle
    }
}

/// Page-top corner label and volume-range rules. The `: first–last`
/// hadith-number range is appended ONLY when the volume is fully cached
/// (every loaded page is real and the backend reports no further pages)
/// and the range is computable from loaded items; otherwise title only.
enum ReaderVolumeRange {
    static func isFullyCached(pages: [ReaderPageResult]) -> Bool {
        guard !pages.isEmpty else { return false }
        guard pages.allSatisfy({ !$0.isPlaceholder }) else { return false }
        return pages.last?.hasMore == false
    }

    /// First/last provider ids across loaded (non-empty) pages.
    static func endpointIDs(pages: [ReaderPageResult]) -> (first: String, last: String)? {
        let ids = pages.flatMap { $0.items }.map { $0.providerHadithId }
        guard let first = ids.first, let last = ids.last else { return nil }
        return (first, last)
    }

    static func cornerText(volumeTitle: String, pages: [ReaderPageResult]) -> String {
        guard isFullyCached(pages: pages),
              let range = endpointIDs(pages: pages)
        else { return volumeTitle }
        if range.first == range.last { return "\(volumeTitle): \(range.first)" }
        return "\(volumeTitle): \(range.first)–\(range.last)"
    }
}

/// Volume-start header rule: the title header with its localized count
/// line renders on the first page of a volume only. The page-top corner
/// label yields to it there so the title never repeats on one page.
enum ReaderVolumeHeader {
    static func showsHeader(pageIndex: Int) -> Bool {
        pageIndex == 0
    }

    static func showsCornerLabel(pageIndex: Int) -> Bool {
        !showsHeader(pageIndex: pageIndex)
    }
}

/// The two bottom page pills (R6 round 2, Sajda `209 Page` style): LEFT is
/// the previous page, RIGHT is the next page. Every pill carries one snug
/// internal chevron pointing the logical way; the stack keeps the ambient
/// layout direction, so in RTL the previous pill sits on the right with
/// mirrored chevrons while the labels stay logical.
///
/// At a volume edge the outward pill names the neighboring volume (its full
/// localized title, never a bare number) and jumps across: the first page
/// of a volume (unless it is the first volume) offers the previous
/// volume's LAST page; the last page (unless last volume) offers the next
/// volume's FIRST page. The absolute ends have no outward pill. Volume
/// order is the outline order.
enum ReaderPagePills {
    enum Target: Equatable {
        case page(Int)
        case volumeFirst(volumeId: String)
        case volumeLast(volumeId: String)
    }

    struct Pill: Equatable {
        /// The pill text without the chevron (`Page 4`, or the neighbor
        /// volume's full title at a volume edge).
        let label: String
        let target: Target
        /// The logical turn this pill performs.
        let turn: ReaderPageTurn
        /// True when the pill crosses into another volume.
        let crossesVolume: Bool
    }

    struct State: Equatable {
        let previous: Pill?
        let next: Pill?
    }

    static func state(
        pageIndex: Int,
        hasPreviousPage: Bool,
        hasNextPage: Bool,
        atLoadedPage: Bool,
        volumes: [OutlineVolume],
        selectedVolumeId: String?
    ) -> State {
        let selectedIndex = volumes.firstIndex { $0.volumeId == selectedVolumeId }
        let previous: Pill?
        if hasPreviousPage {
            previous = Pill(
                label: "Page \(pageIndex)",
                target: .page(pageIndex - 1),
                turn: .previous,
                crossesVolume: false
            )
        } else if atLoadedPage, let index = selectedIndex, index > 0 {
            let neighbor = volumes[index - 1]
            previous = Pill(
                label: neighbor.title,
                target: .volumeLast(volumeId: neighbor.volumeId),
                turn: .previous,
                crossesVolume: true
            )
        } else {
            previous = nil
        }
        let next: Pill?
        if hasNextPage {
            next = Pill(
                label: "Page \(pageIndex + 2)",
                target: .page(pageIndex + 1),
                turn: .next,
                crossesVolume: false
            )
        } else if atLoadedPage, let index = selectedIndex, index < volumes.count - 1 {
            let neighbor = volumes[index + 1]
            next = Pill(
                label: neighbor.title,
                target: .volumeFirst(volumeId: neighbor.volumeId),
                turn: .next,
                crossesVolume: true
            )
        } else {
            next = nil
        }
        return State(previous: previous, next: next)
    }

    /// The chevron image inside a pill: it points back (previous) or
    /// forward (next) in the reading direction, so RTL mirrors both pills.
    static func chevronImage(for turn: ReaderPageTurn, pageDirection: HorizontalDirection) -> String {
        let pointsLeft = switch pageDirection {
        case .ltr: turn == .previous
        case .rtl: turn == .next
        }
        return pointsLeft ? "chevron.left" : "chevron.right"
    }
}
