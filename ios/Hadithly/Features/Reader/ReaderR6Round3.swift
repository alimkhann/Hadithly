import ConvexMobile
import Foundation

/// Round 3 (R6 fixes): pure, UI-framework-free reader logic behind the ten
/// owner-video fixes. Every type here is provable in unit tests with no
/// network and no layout: axis-locked drag paging, the Arabic-only narrator
/// line, localized volume / chapter display titles, bookmark placement,
/// English-text search mapping, prefetch bounds, progress fractions, and
/// relative-time rows for the reader Saved shortcut.

// MARK: - 1. Axis-locked drag paging

/// Which gesture axis owns the current drag. The lock is sticky: once the
/// finger has moved far enough to declare a dominant axis, the rest of the
/// gesture stays on it — a mostly-vertical swipe never drags the page
/// horizontally, and a mostly-horizontal swipe never scrolls it vertically.
enum ReaderAxisLock: Equatable {
    case undecided
    case horizontal
    case vertical
}

enum ReaderAxisLockPolicy {
    /// Finger travel before the dominant axis is declared. Below this the
    /// gesture is still ambiguous and drags nothing.
    static let lockDistance: CGFloat = 12
    /// How much stronger one axis must be to own the gesture.
    static let dominanceRatio: CGFloat = 1.5
    /// Settled horizontal travel that commits a page turn on release.
    static let turnDistance: CGFloat = 55
    /// Short high-velocity flick that commits a page turn on release.
    static let flickVelocity: CGFloat = 700

    /// The lock for a single translation snapshot: undecided until the
    /// finger has traveled `lockDistance`, then the dominant axis.
    static func lock(for translation: CGPoint) -> ReaderAxisLock {
        let horizontal = abs(translation.x)
        let vertical = abs(translation.y)
        guard max(horizontal, vertical) >= lockDistance else { return .undecided }
        if horizontal > vertical * dominanceRatio { return .horizontal }
        if vertical > horizontal * dominanceRatio { return .vertical }
        // Inside the dead band the stronger axis still wins once the
        // finger is clearly moving; ties stay undecided.
        if horizontal > vertical { return .horizontal }
        if vertical > horizontal { return .vertical }
        return .undecided
    }

    /// Sticky update: a decided lock never flips mid-gesture.
    static func update(current: ReaderAxisLock, translation: CGPoint) -> ReaderAxisLock {
        guard current == .undecided else { return current }
        return lock(for: translation)
    }
}

/// The release decision for a horizontally-locked drag: which logical turn
/// the finger committed, or nil to cancel back to the current page.
enum ReaderDragRelease {
    static func turn(
        translation: CGPoint,
        velocity: CGPoint,
        lock: ReaderAxisLock,
        pageDirection: HorizontalDirection
    ) -> ReaderPageTurn? {
        guard lock == .horizontal else { return nil }
        let horizontalDistance = abs(translation.x) > abs(translation.y) * ReaderAxisLockPolicy.dominanceRatio
        let horizontalVelocity = abs(velocity.x) > abs(velocity.y) * ReaderAxisLockPolicy.dominanceRatio
        let commitsByDistance = horizontalDistance && abs(translation.x) >= ReaderAxisLockPolicy.turnDistance
        let commitsByFlick = horizontalVelocity && abs(velocity.x) >= ReaderAxisLockPolicy.flickVelocity
        guard commitsByDistance || commitsByFlick else { return nil }
        let motion = commitsByDistance ? translation.x : velocity.x
        let swipe: ReaderSwipeDirection = motion < 0 ? .left : .right
        return ReaderPagingPolicy(pageDirection: pageDirection).turn(for: swipe)
    }
}

/// Which logical turns the two screen-edge slots of the drag strip reveal.
/// The strip always lays out LTR internally (left slot, current, right
/// slot); in RTL the logical neighbors swap sides so a left drag still
/// moves backward.
enum ReaderDragStrip {
    static func slots(
        hasPrevious: Bool,
        hasNext: Bool,
        pageDirection: HorizontalDirection
    ) -> (left: ReaderPageTurn?, right: ReaderPageTurn?) {
        switch pageDirection {
        case .ltr:
            return (left: hasPrevious ? .previous : nil, right: hasNext ? .next : nil)
        case .rtl:
            return (left: hasNext ? .next : nil, right: hasPrevious ? .previous : nil)
        }
    }

    /// The drag offset that fully reveals the neighbor for `turn`: the
    /// settle target the strip animates to before committing the pageIndex
    /// swap, so both pages stay in the hierarchy for the whole gesture.
    /// Nil when `turn` has no slot (a clamped edge drag that must cancel).
    /// Direction-agnostic: `slots` already encodes the LTR/RTL mirroring.
    static func commitDragOffset(
        viewportWidth: CGFloat,
        turn: ReaderPageTurn,
        slots: (left: ReaderPageTurn?, right: ReaderPageTurn?)
    ) -> CGFloat? {
        if turn == slots.left { return viewportWidth }
        if turn == slots.right { return -viewportWidth }
        return nil
    }
}

// MARK: - 2. Arabic-only narrator line + volume/chapter display titles

extension ReaderNarratorLine {
    /// The narration line for these visibility layers. Arabic-only mode
    /// shows the provider Arabic narrator (`narratorAr`), RTL-aligned
    /// between the header and the Arabic block; when it is absent the line
    /// hides (it never falls back to the English narrator there).
    /// Mixed and translation-only modes keep the English narrator line.
    static func text(
        narrator: String?,
        narratorAr: String?,
        arabicVisible: Bool,
        translationVisible: Bool
    ) -> String? {
        guard arabicVisible || translationVisible else { return nil }
        let raw: String?
        if arabicVisible, !translationVisible {
            raw = narratorAr
        } else {
            raw = narrator
        }
        guard let line = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !line.isEmpty
        else { return nil }
        return line
    }
}

/// Volume titles follow the visible layers. Arabic-only mode renders the
/// localized volume name (`Volume %lld`, so an Arabic UI reads
/// `المجلد ٢`) instead of the backend English title; every other mode
/// keeps the outline title untouched. Titles that do not parse as
/// `Volume N` are never rewritten.
enum ReaderVolumeTitle {
    static let formatKey = "Volume %lld"

    /// The trailing volume number in backend titles like `Volume 2`.
    static func volumeNumber(in title: String) -> Int? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ")
        guard parts.count == 2,
              parts[0].caseInsensitiveCompare("Volume") == .orderedSame,
              let number = Int(parts[1]), number > 0
        else { return nil }
        return number
    }

    static func displayTitle(
        title: String,
        arabicVisible: Bool,
        translationVisible: Bool,
        localizedFormat: (Int) -> String
    ) -> String {
        guard arabicVisible, !translationVisible,
              let number = volumeNumber(in: title)
        else { return title }
        return localizedFormat(number)
    }
}

extension ReaderChapterLine {
    /// Chapter names follow the visible layers. Arabic-only mode shows the
    /// source-provided `arabicTitle` when present, else the title.
    /// Mixed and translation-only modes keep the English title (with the
    /// existing Arabic second line where applicable).
    static func displayTitle(
        title: String,
        arabicTitle: String?,
        arabicVisible: Bool,
        translationVisible: Bool
    ) -> String {
        guard arabicVisible, !translationVisible else { return title }
        guard let arabic = arabicTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !arabic.isEmpty
        else { return title }
        return arabic
    }
}

/// Volume-start header title (R6 fix round): the big centered title is the
/// ACTUAL volume name — the outline's `firstChapterTitle` — falling back to
/// the first source-provided chapter title, then the outline title.
/// Hadithly never synthesizes a name: every fallback is source-provided.
enum ReaderVolumeHeaderTitle {
    static func actualTitle(
        volume: OutlineVolume,
        arabicVisible: Bool = true,
        translationVisible: Bool = true
    ) -> String {
        if let first = volume.firstChapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !first.isEmpty {
            return first
        }
        if let firstChapter = volume.chapters?.first {
            return ReaderChapterLine.displayTitle(
                title: firstChapter.title,
                arabicTitle: firstChapter.arabicTitle,
                arabicVisible: arabicVisible,
                translationVisible: translationVisible
            )
        }
        return volume.title
    }
}

// MARK: - 8. Bookmark placement

/// Where the menu bookmark lands. `pageStart` bookmarks the first hadith
/// on the current page; `currentHadith` bookmarks the positioned (R2
/// anchor) hadith.
enum ReaderBookmarkPlacement: Equatable {
    case pageStart
    case currentHadith
}

enum ReaderBookmarkTarget {
    /// Resolves the placement to a hadith. Falls back to the positioned
    /// hadith when the page is empty.
    static func resolve(
        placement: ReaderBookmarkPlacement,
        pageFirst: ReaderHadith?,
        positioned: ReaderHadith?
    ) -> ReaderHadith? {
        switch placement {
        case .pageStart:
            return pageFirst ?? positioned
        case .currentHadith:
            return positioned ?? pageFirst
        }
    }
}

// MARK: - Search mapping (public `hadiths:searchEnglish`)

// Note: the backend deploys this query after the client task, so every
// field decodes defensively: a row missing `snippet` (or any optional
// shape detail) still maps instead of dropping the whole result page.
struct EnglishSearchResult: Decodable, Identifiable, Equatable {
    let hadithId: String
    let canonicalId: String
    let collectionSlug: String
    let providerHadithId: String
    let referenceDisplay: String
    let snippet: String

    var id: String { hadithId }

    private enum CodingKeys: String, CodingKey {
        case hadithId, canonicalId, collectionSlug, providerHadithId, referenceDisplay, snippet
    }

    init(
        hadithId: String,
        canonicalId: String,
        collectionSlug: String,
        providerHadithId: String,
        referenceDisplay: String,
        snippet: String
    ) {
        self.hadithId = hadithId
        self.canonicalId = canonicalId
        self.collectionSlug = collectionSlug
        self.providerHadithId = providerHadithId
        self.referenceDisplay = referenceDisplay
        self.snippet = snippet
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hadithId = try container.decodeIfPresent(String.self, forKey: .hadithId) ?? ""
        canonicalId = try container.decodeIfPresent(String.self, forKey: .canonicalId) ?? ""
        collectionSlug = try container.decodeIfPresent(String.self, forKey: .collectionSlug) ?? ""
        providerHadithId = try container.decodeIfPresent(String.self, forKey: .providerHadithId) ?? ""
        referenceDisplay = try container.decodeIfPresent(String.self, forKey: .referenceDisplay) ?? ""
        snippet = try container.decodeIfPresent(String.self, forKey: .snippet) ?? ""
    }
}

enum EnglishSearchMapping {
    /// Rows without a provider hadith id cannot navigate the R2 path, so
    /// the sheet drops them instead of showing a dead row.
    static func navigable(_ results: [EnglishSearchResult]) -> [EnglishSearchResult] {
        results.filter { !$0.providerHadithId.isEmpty }
    }
}

// MARK: - 7. Prefetch bounds

/// Pure target selection behind quiet prefetching. Network calls stay in
/// the views/model (existing cache-first actions, results discarded,
/// errors swallowed); only the bounded selection is pinned here.
enum ReaderPrefetchTargets {
    /// At most this many volumes are warmed around the reader at once.
    static let maxAdjacentVolumes = 2
    /// Search/debug default; the client passes 10 and the server clamps.
    static let defaultSearchLimit = 10

    /// The continue-reading target to warm when an entry tab appears: the
    /// outline plus the target volume's first page. Nil with no progress.
    static func entryTarget(progress: ProgressEntry?) -> ReaderPrefetchEntry? {
        guard let progress, let hadith = progress.hadith else { return nil }
        return ReaderPrefetchEntry(
            collectionSlug: progress.collectionSlug,
            volumeId: hadith.volumeId,
            hadithNumber: hadith.hadithNumber
        )
    }

    /// Volumes around the selection in outline order, nearest first,
    /// bounded to `maxAdjacentVolumes`. Empty at a single-volume
    /// collection; one neighbor at either end.
    static func adjacentVolumeIds(
        volumes: [OutlineVolume],
        selectedVolumeId: String?,
        maxCount: Int = maxAdjacentVolumes
    ) -> [String] {
        guard maxCount > 0,
              let selected = selectedVolumeId,
              let index = volumes.firstIndex(where: { $0.volumeId == selected })
        else { return [] }
        var ids: [String] = []
        // Nearest-first: previous, next, then outward.
        var distance = 1
        while ids.count < maxCount, distance < volumes.count {
            if index - distance >= 0 {
                ids.append(volumes[index - distance].volumeId)
                if ids.count >= maxCount { break }
            }
            if index + distance < volumes.count {
                ids.append(volumes[index + distance].volumeId)
            }
            distance += 1
        }
        return ids
    }
}

// MARK: - 7. Quiet entry prefetch (fire-and-forget)

struct ReaderPrefetchEntry: Equatable {
    let collectionSlug: String
    let volumeId: String?
    let hadithNumber: String?
}

/// When Library, Today, or Saved appears, quietly ensures the outline
/// plus the continue-reading target volume's first page are cached.
/// Existing cache-first actions, results discarded, errors swallowed, no
/// UI. At most two backend calls.
enum ReaderPrefetch {
    static func warmEntry(
        convex: ConvexClientWithAuth<String>,
        target: ReaderPrefetchEntry?
    ) {
        guard let target else { return }
        Task {
            _ = try? await convex.action(
                "actions/hadithData:getCollectionOutline",
                with: ["collectionSlug": target.collectionSlug as ConvexEncodable?]
            ) as CollectionOutlineResult
            if let volumeId = target.volumeId {
                _ = try? await convex.action(
                    "actions/hadithData:getReaderPage",
                    with: [
                        "collectionSlug": target.collectionSlug as ConvexEncodable?,
                        "volumeId": volumeId as ConvexEncodable?,
                        "page": Double(1) as ConvexEncodable?,
                    ]
                ) as ReaderPageResult
            }
        }
    }
}

// MARK: - 6. Progress fractions

enum ReaderProgressBars {
    /// Static volume fraction for the unfocused volume bar: the selected
    /// volume's position in outline order. Nil with no outline.
    static func volumeFraction(selectedVolumeId: String?, volumes: [OutlineVolume]) -> Double? {
        guard !volumes.isEmpty,
              let selected = selectedVolumeId,
              let index = volumes.firstIndex(where: { $0.volumeId == selected })
        else { return nil }
        return Double(index + 1) / Double(volumes.count)
    }

    /// Static page fraction within the volume for the unfocused page bar.
    /// Nil until the backend reports a total.
    static func pageFraction(pageIndex: Int, totalPages: Int?) -> Double? {
        guard let total = totalPages, total > 0 else { return nil }
        return min(1, max(0, Double(pageIndex + 1) / Double(total)))
    }

    /// Dynamic focused fraction from the page scroll: 0 at the top, 1 at
    /// the bottom; a page that fits its viewport reads full.
    static func scrollFraction(contentHeight: CGFloat, viewportHeight: CGFloat, scrolled: CGFloat) -> Double {
        guard contentHeight > viewportHeight, viewportHeight > 0 else { return 1 }
        return min(1, max(0, scrolled / (contentHeight - viewportHeight)))
    }

    /// 1-based position of the selected volume in outline order, for the
    /// unfocused Volume pill and the volume header eyebrow. Nil with no
    /// outline or no selection.
    static func volumePosition(selectedVolumeId: String?, volumes: [OutlineVolume]) -> Int? {
        guard let selected = selectedVolumeId,
              let index = volumes.firstIndex(where: { $0.volumeId == selected })
        else { return nil }
        return index + 1
    }

    /// Unfocused Page pill (`Page N`) fill: the intra-page scroll fraction
    /// only — position within the current page. Clamped, never nil.
    /// Mirrors Android `pagePillFillFraction`.
    static func pagePillFillFraction(_ intraPageFraction: Double) -> Double {
        min(1, max(0, intraPageFraction))
    }

    /// Unfocused Volume pill (`Volume N`) fill: the current page fraction
    /// within the volume — page index plus intra-page scroll over the
    /// backend-reported total. Nil until the total is known.
    /// Mirrors Android `volumePillFillFraction`.
    static func volumePillFillFraction(
        pageIndex: Int,
        totalPages: Int?,
        intraPageFraction: Double
    ) -> Double? {
        guard let total = totalPages, total > 0 else { return nil }
        let intra = min(1, max(0, intraPageFraction))
        return min(1, max(0, (Double(max(0, pageIndex)) + intra) / Double(total)))
    }
}

// MARK: - Round 5: per-page vertical scroll offsets

/// A page's vertical scroll position, captured when the reader leaves the
/// page so navigating back restores the exact offset instead of jumping to
/// the top. Mirrors the R1/R2 anchor + normalized-offset shape, keyed by
/// the page index the snapshot was taken on.
struct PageScrollSnapshot: Equatable {
    /// Provider hadith id of the leading visible hadith.
    let providerHadithId: String
    let rawPageOffset: Double
    let normalizedOffset: Double
}

/// A bounded (2-entry, insertion-ordered) cache of per-page scroll offsets.
/// Pure so the eviction order is unit-pinned; the model owns the storage.
enum ReaderPageScrollCache {
    /// How many recent pages keep their scroll offset.
    static let maxEntries = 2

    /// Stores `snapshot` for `page`, refreshing its recency and evicting
    /// the oldest entries beyond `maxEntries`.
    static func storing(
        cache: [Int: PageScrollSnapshot],
        order: [Int],
        page: Int,
        snapshot: PageScrollSnapshot
    ) -> (cache: [Int: PageScrollSnapshot], order: [Int]) {
        var cache = cache
        var order = order.filter { $0 != page }
        order.append(page)
        cache[page] = snapshot
        while order.count > maxEntries {
            cache.removeValue(forKey: order.removeFirst())
        }
        return (cache, order)
    }
}

// MARK: - 10. Relative-time rows

enum SavedRelativeTime {
    /// Compact relative stamp for reader shortcut rows (`2 months ago`).
    /// Pure calendar buckets so the rows are unit-pinned; the sheet keeps
    /// the full date in accessibility labels.
    static func string(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case 0..<60:
            return "just now"
        case 60..<3_600:
            let minutes = seconds / 60
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        case 3_600..<86_400:
            let hours = seconds / 3_600
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        case 86_400..<7 * 86_400:
            let days = seconds / 86_400
            return days == 1 ? "1 day ago" : "\(days) days ago"
        case 7 * 86_400..<30 * 86_400:
            let weeks = seconds / (7 * 86_400)
            return weeks == 1 ? "1 week ago" : "\(weeks) weeks ago"
        case 30 * 86_400..<365 * 86_400:
            let months = seconds / (30 * 86_400)
            return months == 1 ? "1 month ago" : "\(months) months ago"
        default:
            let years = seconds / (365 * 86_400)
            return years == 1 ? "1 year ago" : "\(years) years ago"
        }
    }
}
