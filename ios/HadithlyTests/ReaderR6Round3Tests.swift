import Foundation
import XCTest
@testable import Hadithly

/// R6 fixes round 3: axis-locked drag paging, the Arabic-only narrator
/// line, localized volume/chapter titles, bookmark placement, search
/// mapping, prefetch bounds, progress fractions, and relative-time rows.
/// All pure logic; no network, no layout.
final class ReaderR6Round3Tests: XCTestCase {
    // MARK: - Fixtures

    private func hadith(
        providerHadithId: String = "57",
        narrator: String? = "Narrated by Umar",
        narratorAr: String? = nil
    ) -> ReaderHadith {
        ReaderHadith(
            _id: "fixture-\(providerHadithId)",
            provider: "sunnah_now",
            canonicalId: "sunnah_now:bukhari:\(providerHadithId)",
            providerHadithId: providerHadithId,
            collectionSlug: "bukhari",
            volumeId: "2",
            chapterId: nil,
            arabicText: "نَصّ",
            englishText: "Text.",
            narrator: narrator,
            narratorAr: narratorAr,
            referenceDisplay: "Sahih al-Bukhari · Hadith \(providerHadithId)",
            collectionName: "Sahih al-Bukhari",
            chapterName: nil,
            authenticity: ReaderAuthenticity(
                kind: "collection_scope",
                normalizedGrade: "sahih",
                claimScope: "collection",
                sourceLabel: "Documented Sahih collection",
                sourceName: "Sunnah.now",
                sourceUrl: "https://sunnah.now",
                verificationMethod: "manual_collection_mapping"
            )
        )
    }

    // MARK: - 1. Axis-lock thresholds

    func testLockStaysUndecidedBelowTravelThreshold() {
        XCTAssertEqual(ReaderAxisLockPolicy.lock(for: .init(x: 5, y: 2)), .undecided)
        XCTAssertEqual(ReaderAxisLockPolicy.lock(for: .init(x: 2, y: 11)), .undecided)
        XCTAssertEqual(ReaderAxisLockPolicy.lock(for: .zero), .undecided)
    }

    func testLockDeclaresDominantAxis() {
        // Mostly-vertical swipes lock vertical and never drag horizontally.
        XCTAssertEqual(ReaderAxisLockPolicy.lock(for: .init(x: 6, y: 40)), .vertical)
        XCTAssertEqual(ReaderAxisLockPolicy.lock(for: .init(x: -8, y: 60)), .vertical)
        // Mostly-horizontal swipes lock horizontal.
        XCTAssertEqual(ReaderAxisLockPolicy.lock(for: .init(x: 40, y: 6)), .horizontal)
        XCTAssertEqual(ReaderAxisLockPolicy.lock(for: .init(x: -60, y: -8)), .horizontal)
    }

    func testLockIsStickyMidGesture() {
        // Once vertical, later horizontal dominance cannot flip the lock.
        XCTAssertEqual(
            ReaderAxisLockPolicy.update(current: .vertical, translation: .init(x: 200, y: 4)),
            .vertical
        )
        XCTAssertEqual(
            ReaderAxisLockPolicy.update(current: .horizontal, translation: .init(x: 4, y: 200)),
            .horizontal
        )
        // Undecided keeps arbitrating.
        XCTAssertEqual(
            ReaderAxisLockPolicy.update(current: .undecided, translation: .init(x: 40, y: 5)),
            .horizontal
        )
    }

    func testReleaseCommitsOnlyWhenHorizontallyLocked() {
        // Settled horizontal drag past the distance threshold turns.
        XCTAssertEqual(
            ReaderDragRelease.turn(
                translation: .init(x: -70, y: 8),
                velocity: .zero,
                lock: .horizontal,
                pageDirection: .ltr
            ),
            .next
        )
        // Short high-velocity horizontal flick turns.
        XCTAssertEqual(
            ReaderDragRelease.turn(
                translation: .init(x: -18, y: 2),
                velocity: .init(x: -900, y: 30),
                lock: .horizontal,
                pageDirection: .ltr
            ),
            .next
        )
        // Short slow drag cancels back.
        XCTAssertNil(ReaderDragRelease.turn(
            translation: .init(x: -30, y: 4),
            velocity: .init(x: -100, y: 10),
            lock: .horizontal,
            pageDirection: .ltr
        ))
        // A vertical lock never turns, however far the finger travels.
        XCTAssertNil(ReaderDragRelease.turn(
            translation: .init(x: 8, y: -300),
            velocity: .init(x: 20, y: -1_000),
            lock: .vertical,
            pageDirection: .ltr
        ))
        // No lock, no turn.
        XCTAssertNil(ReaderDragRelease.turn(
            translation: .init(x: -200, y: 0),
            velocity: .zero,
            lock: .undecided,
            pageDirection: .ltr
        ))
    }

    func testReleaseRespectsReadingDirection() {
        // RTL: a left drag moves backward.
        XCTAssertEqual(
            ReaderDragRelease.turn(
                translation: .init(x: -70, y: 5),
                velocity: .zero,
                lock: .horizontal,
                pageDirection: .rtl
            ),
            .previous
        )
        XCTAssertEqual(
            ReaderDragRelease.turn(
                translation: .init(x: 70, y: 5),
                velocity: .zero,
                lock: .horizontal,
                pageDirection: .rtl
            ),
            .next
        )
    }

    func testStripSlotsMirrorInRTL() {
        XCTAssertEqual(
            ReaderDragStrip.slots(hasPrevious: true, hasNext: true, pageDirection: .ltr).left,
            .previous
        )
        XCTAssertEqual(
            ReaderDragStrip.slots(hasPrevious: true, hasNext: true, pageDirection: .ltr).right,
            .next
        )
        // RTL swaps sides so a left drag still moves backward.
        XCTAssertEqual(
            ReaderDragStrip.slots(hasPrevious: true, hasNext: true, pageDirection: .rtl).left,
            .next
        )
        XCTAssertEqual(
            ReaderDragStrip.slots(hasPrevious: true, hasNext: true, pageDirection: .rtl).right,
            .previous
        )
        let missing = ReaderDragStrip.slots(hasPrevious: false, hasNext: false, pageDirection: .ltr)
        XCTAssertNil(missing.left)
        XCTAssertNil(missing.right)
    }

    // MARK: - 2. Arabic-only narrator line

    func testNarratorArShowsInArabicOnlyMode() {
        XCTAssertEqual(
            ReaderNarratorLine.text(
                narrator: "Narrated by Umar",
                narratorAr: "عن عمر",
                arabicVisible: true,
                translationVisible: false
            ),
            "عن عمر"
        )
    }

    func testNarratorHidesInArabicOnlyModeWhenArAbsent() {
        // Missing stays hidden — never falls back to the English narrator.
        for narratorAr: String? in [nil, "", "  "] {
            XCTAssertNil(
                ReaderNarratorLine.text(
                    narrator: "Narrated by Umar",
                    narratorAr: narratorAr,
                    arabicVisible: true,
                    translationVisible: false
                ),
                "narratorAr \(narratorAr ?? "nil") must hide the line"
            )
        }
    }

    func testMixedAndTranslationOnlyKeepEnglishNarrator() {
        XCTAssertEqual(
            ReaderNarratorLine.text(
                narrator: "Narrated by Umar",
                narratorAr: "عن عمر",
                arabicVisible: true,
                translationVisible: true
            ),
            "Narrated by Umar"
        )
        XCTAssertEqual(
            ReaderNarratorLine.text(
                narrator: "Narrated by Umar",
                narratorAr: "عن عمر",
                arabicVisible: false,
                translationVisible: true
            ),
            "Narrated by Umar"
        )
        XCTAssertNil(ReaderNarratorLine.text(
            narrator: nil, narratorAr: "عن عمر",
            arabicVisible: true, translationVisible: true
        ))
        XCTAssertNil(ReaderNarratorLine.text(
            narrator: "Narrated by Umar", narratorAr: "عن عمر",
            arabicVisible: false, translationVisible: false
        ))
    }

    func testNarratorArDecodesTolerantly() throws {
        // Rows cached before narratorAr existed carry no key: decoding
        // succeeds and the field stays nil (hidden).
        let legacy = """
        {
            "_id": "h1", "provider": "sunnah_now",
            "canonicalId": "sunnah_now:bukhari:57",
            "providerHadithId": "57", "collectionSlug": "bukhari",
            "volumeId": "2", "chapterId": null,
            "arabicText": "نَصّ", "englishText": "Text.",
            "narrator": "Narrated by Umar",
            "referenceDisplay": "Sahih al-Bukhari · Hadith 57",
            "collectionName": "Sahih al-Bukhari", "chapterName": null,
            "authenticity": {
                "kind": "collection_scope", "normalizedGrade": "sahih",
                "claimScope": "collection", "sourceLabel": "D",
                "sourceName": "Sunnah.now", "sourceUrl": "https://sunnah.now",
                "verificationMethod": "manual_collection_mapping"
            }
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ReaderHadith.self, from: legacy)
        XCTAssertNil(decoded.narratorAr)
        XCTAssertEqual(decoded.narrator, "Narrated by Umar")

        let current = """
        {
            "_id": "h1", "provider": "sunnah_now",
            "canonicalId": "sunnah_now:bukhari:57",
            "providerHadithId": "57", "collectionSlug": "bukhari",
            "volumeId": "2", "chapterId": null,
            "arabicText": "نَصّ", "englishText": "Text.",
            "narrator": "Narrated by Umar", "narratorAr": "عن عمر",
            "referenceDisplay": "Sahih al-Bukhari · Hadith 57",
            "collectionName": "Sahih al-Bukhari", "chapterName": null,
            "authenticity": {
                "kind": "collection_scope", "normalizedGrade": "sahih",
                "claimScope": "collection", "sourceLabel": "D",
                "sourceName": "Sunnah.now", "sourceUrl": "https://sunnah.now",
                "verificationMethod": "manual_collection_mapping"
            }
        }
        """.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(ReaderHadith.self, from: current).narratorAr, "عن عمر")
    }

    // MARK: - 2b. Volume/chapter display titles

    func testVolumeNumberParsesOnlyVolumeN() {
        XCTAssertEqual(ReaderVolumeTitle.volumeNumber(in: "Volume 2"), 2)
        XCTAssertEqual(ReaderVolumeTitle.volumeNumber(in: "volume 97"), 97)
        XCTAssertNil(ReaderVolumeTitle.volumeNumber(in: "Volume"))
        XCTAssertNil(ReaderVolumeTitle.volumeNumber(in: "Volume 0"))
        XCTAssertNil(ReaderVolumeTitle.volumeNumber(in: "Book 2"))
        XCTAssertNil(ReaderVolumeTitle.volumeNumber(in: "Volume 2 Extra"))
    }

    func testVolumeTitleLocalizesOnlyInArabicOnlyMode() {
        let format: (Int) -> String = { "VOLUME-\($0)" }
        // Arabic-only renders the localized name.
        XCTAssertEqual(
            ReaderVolumeTitle.displayTitle(
                title: "Volume 2", arabicVisible: true, translationVisible: false,
                localizedFormat: format
            ),
            "VOLUME-2"
        )
        // Every other mode keeps the outline title untouched.
        XCTAssertEqual(
            ReaderVolumeTitle.displayTitle(
                title: "Volume 2", arabicVisible: true, translationVisible: true,
                localizedFormat: format
            ),
            "Volume 2"
        )
        XCTAssertEqual(
            ReaderVolumeTitle.displayTitle(
                title: "Volume 2", arabicVisible: false, translationVisible: true,
                localizedFormat: format
            ),
            "Volume 2"
        )
        // Unparseable titles are never rewritten.
        XCTAssertEqual(
            ReaderVolumeTitle.displayTitle(
                title: "Muqaddima", arabicVisible: true, translationVisible: false,
                localizedFormat: format
            ),
            "Muqaddima"
        )
    }

    func testChapterDisplayUsesArabicTitleInArabicOnlyMode() {
        XCTAssertEqual(
            ReaderChapterLine.displayTitle(
                title: "Belief", arabicTitle: "كتاب الإيمان",
                arabicVisible: true, translationVisible: false
            ),
            "كتاب الإيمان"
        )
        XCTAssertEqual(
            ReaderChapterLine.displayTitle(
                title: "Belief", arabicTitle: nil,
                arabicVisible: true, translationVisible: false
            ),
            "Belief"
        )
        // Mixed and translation-only keep the English title.
        XCTAssertEqual(
            ReaderChapterLine.displayTitle(
                title: "Belief", arabicTitle: "كتاب الإيمان",
                arabicVisible: true, translationVisible: true
            ),
            "Belief"
        )
        XCTAssertEqual(
            ReaderChapterLine.displayTitle(
                title: "Belief", arabicTitle: "كتاب الإيمان",
                arabicVisible: false, translationVisible: true
            ),
            "Belief"
        )
    }

    // MARK: - 3. Source truth is backend-owned

    func testSourceLabelsRenderAsReturned() {
        // The client never substitutes its own source name: whatever the
        // backend returns renders verbatim, including Sunnah.now.
        let hadith = hadith()
        XCTAssertTrue(ReaderSourceLabel.text(for: hadith).contains("Bukhari"))
        XCTAssertEqual(hadith.authenticity.sourceName, "Sunnah.now")
        XCTAssertEqual(
            hadith.authenticity.displayLabel,
            "Sahih collection scope · Sunnah.now"
        )
    }

    // MARK: - 6. Progress fractions

    func testVolumeFractionFollowsOutlineOrder() throws {
        let volumes = [
            OutlineVolume(volumeId: "1", title: "Volume 1", hadithCount: 1),
            OutlineVolume(volumeId: "2", title: "Volume 2", hadithCount: 3),
            OutlineVolume(volumeId: "3", title: "Volume 3", hadithCount: 1),
        ]
        XCTAssertEqual(
            try XCTUnwrap(ReaderProgressBars.volumeFraction(selectedVolumeId: "1", volumes: volumes)),
            1.0 / 3.0, accuracy: 1e-9
        )
        XCTAssertEqual(
            try XCTUnwrap(ReaderProgressBars.volumeFraction(selectedVolumeId: "3", volumes: volumes)),
            1.0, accuracy: 1e-9
        )
        XCTAssertNil(ReaderProgressBars.volumeFraction(selectedVolumeId: "9", volumes: volumes))
        XCTAssertNil(ReaderProgressBars.volumeFraction(selectedVolumeId: "1", volumes: []))
    }

    func testPageFractionIsPageWithinVolume() throws {
        XCTAssertEqual(try XCTUnwrap(ReaderProgressBars.pageFraction(pageIndex: 0, totalPages: 4)), 0.25, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(ReaderProgressBars.pageFraction(pageIndex: 3, totalPages: 4)), 1.0, accuracy: 1e-9)
        XCTAssertNil(ReaderProgressBars.pageFraction(pageIndex: 0, totalPages: nil))
        XCTAssertNil(ReaderProgressBars.pageFraction(pageIndex: 0, totalPages: 0))
    }

    func testScrollFractionFillsWithPageScroll() {
        // A page that fits its viewport reads full.
        XCTAssertEqual(ReaderProgressBars.scrollFraction(contentHeight: 400, viewportHeight: 700, scrolled: 0), 1)
        // Tall pages fill from 0 at the top to 1 at the bottom.
        XCTAssertEqual(
            ReaderProgressBars.scrollFraction(contentHeight: 2000, viewportHeight: 700, scrolled: 0), 0
        )
        XCTAssertEqual(
            ReaderProgressBars.scrollFraction(contentHeight: 2000, viewportHeight: 700, scrolled: 650), 0.5,
            accuracy: 1e-9
        )
        XCTAssertEqual(
            ReaderProgressBars.scrollFraction(contentHeight: 2000, viewportHeight: 700, scrolled: 5000), 1
        )
    }

    // MARK: - 7. Prefetch bounds

    func testAdjacentVolumesAreNearestFirstAndBounded() {
        let volumes = (1...5).map {
            OutlineVolume(volumeId: "\($0)", title: "Volume \($0)", hadithCount: 1)
        }
        XCTAssertEqual(
            ReaderPrefetchTargets.adjacentVolumeIds(volumes: volumes, selectedVolumeId: "3"),
            ["2", "4"]
        )
        XCTAssertEqual(
            ReaderPrefetchTargets.adjacentVolumeIds(volumes: volumes, selectedVolumeId: "1"),
            ["2", "3"]
        )
        XCTAssertEqual(
            ReaderPrefetchTargets.adjacentVolumeIds(volumes: volumes, selectedVolumeId: "5"),
            ["4", "3"]
        )
        XCTAssertEqual(
            ReaderPrefetchTargets.adjacentVolumeIds(volumes: [volumes[0]], selectedVolumeId: "1"),
            []
        )
        XCTAssertEqual(
            ReaderPrefetchTargets.adjacentVolumeIds(volumes: volumes, selectedVolumeId: nil),
            []
        )
        XCTAssertEqual(
            ReaderPrefetchTargets.adjacentVolumeIds(volumes: volumes, selectedVolumeId: "3", maxCount: 1),
            ["2"]
        )
        XCTAssertLessThanOrEqual(
            ReaderPrefetchTargets.adjacentVolumeIds(volumes: volumes, selectedVolumeId: "3").count,
            ReaderPrefetchTargets.maxAdjacentVolumes
        )
    }

    func testEntryTargetNeedsProgressWithHadith() {
        XCTAssertNil(ReaderPrefetchTargets.entryTarget(progress: nil))
        let ref = HadithRef(
            hadithId: "h", collectionSlug: "bukhari", collectionName: "Sahih al-Bukhari",
            volumeId: "2", hadithNumber: "57", arabicText: "",
            englishText: nil, referenceDisplay: "Sahih al-Bukhari · Hadith 57"
        )
        let entry = ProgressEntry(collectionSlug: "bukhari", hadith: ref, updatedAt: .now)
        XCTAssertEqual(
            ReaderPrefetchTargets.entryTarget(progress: entry),
            ReaderPrefetchEntry(collectionSlug: "bukhari", volumeId: "2", hadithNumber: "57")
        )
        let volumeless = ProgressEntry(
            collectionSlug: "muslim",
            hadith: HadithRef(
                hadithId: "h", collectionSlug: "muslim", collectionName: "Sahih Muslim",
                volumeId: nil, hadithNumber: nil, arabicText: "",
                englishText: nil, referenceDisplay: ""
            ),
            updatedAt: .now
        )
        XCTAssertEqual(
            ReaderPrefetchTargets.entryTarget(progress: volumeless),
            ReaderPrefetchEntry(collectionSlug: "muslim", volumeId: nil, hadithNumber: nil)
        )
    }

    // MARK: - 8. Bookmark placement and state

    func testPlacementResolvesToPageStartOrPositioned() {
        let first = hadith(providerHadithId: "57")
        let positioned = hadith(providerHadithId: "58")
        XCTAssertEqual(
            ReaderBookmarkTarget.resolve(placement: .pageStart, pageFirst: first, positioned: positioned)?
                .providerHadithId,
            "57"
        )
        XCTAssertEqual(
            ReaderBookmarkTarget.resolve(placement: .currentHadith, pageFirst: first, positioned: positioned)?
                .providerHadithId,
            "58"
        )
        // Empty pages fall back instead of dropping the bookmark.
        XCTAssertEqual(
            ReaderBookmarkTarget.resolve(placement: .pageStart, pageFirst: nil, positioned: positioned)?
                .providerHadithId,
            "58"
        )
        XCTAssertNil(ReaderBookmarkTarget.resolve(placement: .pageStart, pageFirst: nil, positioned: nil))
    }

    func testNoteMarkerRendersAfterFavorite() {
        XCTAssertEqual(
            ReaderSavedMarkers.visible(bookmarked: true, favorited: true, hasNote: true),
            [.bookmark, .favorite, .note]
        )
        XCTAssertEqual(ReaderSavedMarkers.visible(bookmarked: false, favorited: false, hasNote: true), [.note])
        // Existing two-flag call sites keep their contract.
        XCTAssertEqual(ReaderSavedMarkers.visible(bookmarked: true, favorited: false), [.bookmark])
    }

    // MARK: - 8b. Search result mapping

    func testSearchRowsMapAndDropUnnavigable() throws {
        let payload = """
        [
            {
                "hadithId": "h57", "canonicalId": "sunnah_now:bukhari:57",
                "collectionSlug": "bukhari", "providerHadithId": "57",
                "referenceDisplay": "Sahih al-Bukhari · Hadith 57",
                "snippet": "Deeds are judged by intentions."
            },
            {
                "hadithId": "h58", "canonicalId": "sunnah_now:bukhari:58",
                "collectionSlug": "bukhari", "providerHadithId": "",
                "referenceDisplay": "Sahih al-Bukhari · Hadith 58",
                "snippet": "Belief."
            },
            {
                "hadithId": "h59", "collectionSlug": "bukhari",
                "providerHadithId": "59"
            }
        ]
        """.data(using: .utf8)!
        // Defensive decode: the third row misses most keys but still maps.
        let rows = try JSONDecoder().decode([EnglishSearchResult].self, from: payload)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].snippet, "Deeds are judged by intentions.")
        XCTAssertEqual(rows[2].referenceDisplay, "")
        // The R2 path needs a provider hadith id: row 2 drops out.
        let navigable = EnglishSearchMapping.navigable(rows)
        XCTAssertEqual(navigable.map(\.providerHadithId), ["57", "59"])
    }

    // MARK: - 10. Relative-time rows

    func testRelativeTimeBuckets() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(SavedRelativeTime.string(since: now.addingTimeInterval(-10), now: now), "just now")
        XCTAssertEqual(SavedRelativeTime.string(since: now.addingTimeInterval(-90), now: now), "1 minute ago")
        XCTAssertEqual(SavedRelativeTime.string(since: now.addingTimeInterval(-300), now: now), "5 minutes ago")
        XCTAssertEqual(
            SavedRelativeTime.string(since: now.addingTimeInterval(-3_600), now: now), "1 hour ago"
        )
        XCTAssertEqual(
            SavedRelativeTime.string(since: now.addingTimeInterval(-2 * 86_400), now: now), "2 days ago"
        )
        XCTAssertEqual(
            SavedRelativeTime.string(since: now.addingTimeInterval(-60 * 86_400), now: now), "2 months ago"
        )
        XCTAssertEqual(
            SavedRelativeTime.string(since: now.addingTimeInterval(-400 * 86_400), now: now), "1 year ago"
        )
    }

    // MARK: - R6 fix round: settle offsets, header titles, haptics

    func testCommitDragOffsetRevealsNeighborAndRejectsEdges() {
        let ltr = ReaderDragStrip.slots(hasPrevious: true, hasNext: true, pageDirection: .ltr)
        XCTAssertEqual(
            ReaderDragStrip.commitDragOffset(viewportWidth: 393, turn: .next, slots: ltr), -393
        )
        XCTAssertEqual(
            ReaderDragStrip.commitDragOffset(viewportWidth: 393, turn: .previous, slots: ltr), 393
        )
        // RTL mirrors sides but the settle target follows the slot, not the direction.
        let rtl = ReaderDragStrip.slots(hasPrevious: true, hasNext: true, pageDirection: .rtl)
        XCTAssertEqual(
            ReaderDragStrip.commitDragOffset(viewportWidth: 393, turn: .next, slots: rtl), 393
        )
        XCTAssertEqual(
            ReaderDragStrip.commitDragOffset(viewportWidth: 393, turn: .previous, slots: rtl), -393
        )
        // A turn with no slot (clamped edge) must cancel, never commit.
        let start = ReaderDragStrip.slots(hasPrevious: false, hasNext: true, pageDirection: .ltr)
        XCTAssertNil(ReaderDragStrip.commitDragOffset(viewportWidth: 393, turn: .previous, slots: start))
        XCTAssertEqual(
            ReaderDragStrip.commitDragOffset(viewportWidth: 393, turn: .next, slots: start), -393
        )
    }

    func testVolumeHeaderTitlePrefersActualName() {
        let named = OutlineVolume(
            volumeId: "1", title: "Volume 1",
            firstChapterTitle: "How the Divine Revelation started",
            hadithCount: 7
        )
        XCTAssertEqual(ReaderVolumeHeaderTitle.actualTitle(volume: named), "How the Divine Revelation started")
        // No first-chapter title: the first source-provided chapter title.
        let chaptered = OutlineVolume(
            volumeId: "2", title: "Volume 2", hadithCount: 3,
            chapters: [OutlineChapter(
                chapterId: "42", title: "Belief", arabicTitle: "كتاب الإيمان",
                hadithCount: 2, firstProviderHadithId: "58"
            )]
        )
        XCTAssertEqual(ReaderVolumeHeaderTitle.actualTitle(volume: chaptered), "Belief")
        // Arabic-only mode prefers the chapter's Arabic title.
        XCTAssertEqual(
            ReaderVolumeHeaderTitle.actualTitle(volume: chaptered, arabicVisible: true, translationVisible: false),
            "كتاب الإيمان"
        )
        // Nothing source-provided: the outline title survives untouched.
        let bare = OutlineVolume(volumeId: "3", title: "Volume 3", hadithCount: 1)
        XCTAssertEqual(ReaderVolumeHeaderTitle.actualTitle(volume: bare), "Volume 3")
    }

    func testVolumePositionFollowsOutlineOrder() {
        let volumes = (1...4).map {
            OutlineVolume(volumeId: "\($0)", title: "Volume \($0)", hadithCount: 1)
        }
        XCTAssertEqual(ReaderProgressBars.volumePosition(selectedVolumeId: "1", volumes: volumes), 1)
        XCTAssertEqual(ReaderProgressBars.volumePosition(selectedVolumeId: "4", volumes: volumes), 4)
        XCTAssertNil(ReaderProgressBars.volumePosition(selectedVolumeId: "9", volumes: volumes))
        XCTAssertNil(ReaderProgressBars.volumePosition(selectedVolumeId: nil, volumes: volumes))
        XCTAssertNil(ReaderProgressBars.volumePosition(selectedVolumeId: "1", volumes: []))
    }

    func testPillFillsMirrorAndroid() {
        // Page pill: intra-page scroll only, clamped.
        XCTAssertEqual(ReaderProgressBars.pagePillFillFraction(0), 0, accuracy: 1e-9)
        XCTAssertEqual(ReaderProgressBars.pagePillFillFraction(0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(ReaderProgressBars.pagePillFillFraction(1), 1, accuracy: 1e-9)
        XCTAssertEqual(ReaderProgressBars.pagePillFillFraction(-0.5), 0, accuracy: 1e-9)
        XCTAssertEqual(ReaderProgressBars.pagePillFillFraction(2), 1, accuracy: 1e-9)
        // Volume pill: page index plus intra-page scroll over the total.
        XCTAssertEqual(
            try XCTUnwrap(ReaderProgressBars.volumePillFillFraction(
                pageIndex: 0, totalPages: 10, intraPageFraction: 0.5
            )), 0.05, accuracy: 1e-9
        )
        XCTAssertEqual(
            try XCTUnwrap(ReaderProgressBars.volumePillFillFraction(
                pageIndex: 4, totalPages: 10, intraPageFraction: 1
            )), 0.5, accuracy: 1e-9
        )
        XCTAssertNil(ReaderProgressBars.volumePillFillFraction(
            pageIndex: 0, totalPages: nil, intraPageFraction: 0
        ))
        XCTAssertNil(ReaderProgressBars.volumePillFillFraction(
            pageIndex: 0, totalPages: 0, intraPageFraction: 0
        ))
    }

    func testHapticStylesAreRestrained() {
        XCTAssertEqual(ReaderHaptics.style(for: .menuToggle), .light)
        XCTAssertEqual(ReaderHaptics.style(for: .menuItemTap), .light)
        XCTAssertEqual(ReaderHaptics.style(for: .contextMenuOpen), .light)
        XCTAssertEqual(ReaderHaptics.style(for: .bookmarkRemove), .light)
        XCTAssertEqual(ReaderHaptics.style(for: .favoriteRemove), .light)
        // Medium only when something is added.
        XCTAssertEqual(ReaderHaptics.style(for: .bookmarkAdd), .medium)
        XCTAssertEqual(ReaderHaptics.style(for: .favoriteAdd), .medium)
        // Round 5: the page-settle tick is gone — no touch/drag/scroll
        // haptic in the focused view or during swipes. Hiding both text
        // layers is the only notification haptic.
        XCTAssertEqual(ReaderHaptics.style(for: .layersRejected), .error)
    }

    func testHapticDispatcherReachesInjectedPlayer() {
        final class Recorder: ReaderHapticPlayer {
            var events: [ReaderHapticEvent] = []
            func play(_ event: ReaderHapticEvent) { events.append(event) }
        }
        let recorder = Recorder()
        let previous = ReaderHapticDispatcher.shared
        ReaderHapticDispatcher.shared = recorder
        defer { ReaderHapticDispatcher.shared = previous }
        ReaderHapticDispatcher.trigger(.menuToggle)
        ReaderHapticDispatcher.trigger(.bookmarkAdd)
        ReaderHapticDispatcher.trigger(.layersRejected)
        XCTAssertEqual(recorder.events, [.menuToggle, .bookmarkAdd, .layersRejected])
    }

    // MARK: - Round 5: per-page scroll offset cache

    private func snapshot(id: String = "57") -> PageScrollSnapshot {
        PageScrollSnapshot(providerHadithId: id, rawPageOffset: 120, normalizedOffset: 0.25)
    }

    func testScrollCacheKeepsTwoMostRecentPages() {
        var cache: [Int: PageScrollSnapshot] = [:]
        var order: [Int] = []
        for page in [3, 4, 5] {
            let stored = ReaderPageScrollCache.storing(
                cache: cache, order: order, page: page, snapshot: snapshot(id: "\(page)")
            )
            cache = stored.cache
            order = stored.order
        }
        XCTAssertEqual(order, [4, 5])
        XCTAssertNil(cache[3])
        XCTAssertEqual(cache[4]?.providerHadithId, "4")
        XCTAssertEqual(cache[5]?.providerHadithId, "5")
    }

    func testScrollCacheRestoringRefreshesRecency() {
        let first = ReaderPageScrollCache.storing(
            cache: [:], order: [], page: 3, snapshot: snapshot(id: "3")
        )
        let second = ReaderPageScrollCache.storing(
            cache: first.cache, order: first.order, page: 4, snapshot: snapshot(id: "4")
        )
        // Re-storing page 3 moves it to the back; page 5 then evicts 4.
        let third = ReaderPageScrollCache.storing(
            cache: second.cache, order: second.order, page: 3, snapshot: snapshot(id: "3b")
        )
        let fourth = ReaderPageScrollCache.storing(
            cache: third.cache, order: third.order, page: 5, snapshot: snapshot(id: "5")
        )
        XCTAssertEqual(fourth.order, [3, 5])
        XCTAssertEqual(fourth.cache[3]?.providerHadithId, "3b")
        XCTAssertNil(fourth.cache[4])
    }

    func testFreshPageAlwaysResetsToItsHeader() {
        XCTAssertTrue(ReaderPageLanding.shouldResetToHeader(hasTargetOnPage: false, hasCachedOffset: false))
        XCTAssertFalse(ReaderPageLanding.shouldResetToHeader(hasTargetOnPage: true, hasCachedOffset: false))
        XCTAssertFalse(ReaderPageLanding.shouldResetToHeader(hasTargetOnPage: false, hasCachedOffset: true))
    }

    // MARK: - Round 7: confirmed tap vs drag

    func testConfirmedTapWithinMovementAndDuration() {
        XCTAssertTrue(ReaderConfirmedTap.isConfirmedTap(movement: 0, duration: 0.1))
        XCTAssertTrue(ReaderConfirmedTap.isConfirmedTap(movement: 9.9, duration: 0.39))
    }

    func testDragSwipeOrHoldNeverConfirms() {
        // At or beyond 10pt of travel the touch is a drag, swipe, or scroll.
        XCTAssertFalse(ReaderConfirmedTap.isConfirmedTap(movement: 10, duration: 0.1))
        XCTAssertFalse(ReaderConfirmedTap.isConfirmedTap(movement: 60, duration: 0.1))
        // At or beyond 0.4s the touch is a press-and-hold.
        XCTAssertFalse(ReaderConfirmedTap.isConfirmedTap(movement: 0, duration: 0.4))
        XCTAssertFalse(ReaderConfirmedTap.isConfirmedTap(movement: 0, duration: 0.8))
        XCTAssertFalse(ReaderConfirmedTap.isConfirmedTap(movement: 4, duration: 0.6))
    }
}
