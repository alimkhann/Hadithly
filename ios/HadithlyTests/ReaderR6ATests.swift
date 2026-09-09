import XCTest
@testable import Hadithly

/// Slice A (R6): the quiet-page view-model contract — grade-dot mapping,
/// compact source labels, bracketed header text, narrator visibility,
/// saved-state markers, chapter subtitles, volume corner/range rules, the
/// per-block action set, and position-reanchor survival across the density
/// restyle. All pure logic; no network, no layout.
final class ReaderR6ATests: XCTestCase {
    // MARK: - Fixtures

    private func hadith(
        providerHadithId: String = "57",
        collectionSlug: String = "bukhari",
        collectionName: String = "Sahih al-Bukhari",
        chapterId: String? = nil,
        normalizedGrade: String? = "sahih",
        claimScope: String = "collection",
        sourceName: String = "Sunnah.com",
        sourceUrl: String = "https://sunnah.com/bukhari/about",
        narrator: String? = nil
    ) -> ReaderHadith {
        ReaderHadith(
            _id: "fixture-\(providerHadithId)",
            provider: "sunnah_now",
            canonicalId: "sunnah_now:\(collectionSlug):\(providerHadithId)",
            providerHadithId: providerHadithId,
            collectionSlug: collectionSlug,
            volumeId: "2",
            chapterId: chapterId,
            arabicText: "نَصّ",
            englishText: "Text.",
            narrator: narrator,
            referenceDisplay: "\(collectionName) · Hadith \(providerHadithId)",
            collectionName: collectionName,
            chapterName: nil,
            authenticity: ReaderAuthenticity(
                kind: "test",
                normalizedGrade: normalizedGrade,
                claimScope: claimScope,
                sourceLabel: "Test",
                sourceName: sourceName,
                sourceUrl: sourceUrl,
                verificationMethod: "test"
            )
        )
    }

    private func page(
        ids: [String],
        page: Int = 1,
        totalPages: Int = 1,
        hasMore: Bool = false,
        placeholder: Bool = false
    ) -> ReaderPageResult {
        if placeholder {
            return ReaderPageResult(
                items: [], page: 0, pageSize: 0, totalPages: 0, hasMore: false,
                contentVersion: nil, paginationVersion: nil, pageKey: nil
            )
        }
        return ReaderPageResult(
            items: ids.map { hadith(providerHadithId: $0) },
            page: page, pageSize: 10, totalPages: totalPages, hasMore: hasMore,
            contentVersion: "cv1", paginationVersion: 1, pageKey: "pg\(page)"
        )
    }

    // MARK: - Grade mapping

    func testGradeMappingCoversKnownGrades() {
        XCTAssertEqual(ReaderGradeKind(normalizedGrade: "sahih"), .sahih)
        XCTAssertEqual(ReaderGradeKind(normalizedGrade: "hasan"), .hasan)
        XCTAssertEqual(ReaderGradeKind(normalizedGrade: "daif"), .daif)
    }

    func testGradeMappingIsCaseInsensitiveAndTrims() {
        XCTAssertEqual(ReaderGradeKind(normalizedGrade: " Sahih "), .sahih)
        XCTAssertEqual(ReaderGradeKind(normalizedGrade: "HASAN"), .hasan)
        XCTAssertEqual(ReaderGradeKind(normalizedGrade: "Dhaif"), .daif)
    }

    func testGradeMappingUnknownIsUnverified() {
        for grade: String? in [nil, "", "unknown", "weak", "sahih_li_ghairihi"] {
            XCTAssertEqual(
                ReaderGradeKind(normalizedGrade: grade), .unverified,
                "grade \(grade ?? "nil") must not invent a dot color"
            )
        }
    }

    func testGradeDotsAreDistinctAndThemeAware() {
        let kinds: [ReaderGradeKind] = [.sahih, .hasan, .daif, .unverified]
        let darkHex = kinds.map { ReaderGradeDot.hex(for: $0, dark: true) }
        let lightHex = kinds.map { ReaderGradeDot.hex(for: $0, dark: false) }
        XCTAssertEqual(Set(darkHex).count, 4, "every grade needs its own dark dot")
        XCTAssertEqual(Set(lightHex).count, 4, "every grade needs its own light dot")
        // Theme-aware: dark and light variants differ so the dot stays
        // visible on both dark and light/paper reader themes.
        for kind in kinds {
            XCTAssertNotEqual(
                ReaderGradeDot.hex(for: kind, dark: true),
                ReaderGradeDot.hex(for: kind, dark: false),
                "\(kind) dot must adapt to the theme"
            )
        }
    }

    // MARK: - Source label and marker

    func testShortNamesForAllSevenCollections() {
        let cases: [(slug: String, name: String, short: String)] = [
            ("bukhari", "Sahih al-Bukhari", "Bukhari"),
            ("muslim", "Sahih Muslim", "Muslim"),
            ("sunan-nasai", "Sunan an-Nasa'i", "Nasa'i"),
            ("abu-dawood", "Abu Dawood", "Abu Dawud"),
            ("tirmidhi", "Jami` at-Tirmidhi", "Tirmidhi"),
            ("ibn-majah", "Ibn Majah", "Ibn Majah"),
            ("mishkat-al-masabih", "Mishkat al-Masabih", "Mishkat"),
        ]
        for (slug, name, short) in cases {
            XCTAssertEqual(
                ReaderSourceLabel.shortName(collectionSlug: slug, collectionName: name),
                short, slug
            )
        }
    }

    func testShortNameFallsBackToCollectionName() {
        XCTAssertEqual(
            ReaderSourceLabel.shortName(collectionSlug: "forty-nawawi", collectionName: "Forty Nawawi"),
            "Forty Nawawi"
        )
    }

    func testSourceLabelTextIsCompact() {
        XCTAssertEqual(ReaderSourceLabel.text(for: hadith()), "Bukhari – 57")
        XCTAssertEqual(
            ReaderSourceLabel.text(for: hadith(providerHadithId: "4.5", collectionSlug: "muslim", collectionName: "Sahih Muslim")),
            "Muslim – 4.5"
        )
    }

    func testHeaderTextIsBracketedCompactLabel() {
        XCTAssertEqual(ReaderSourceLabel.headerText(for: hadith()), "[Bukhari – 57]")
        XCTAssertEqual(
            ReaderSourceLabel.headerText(for: hadith(providerHadithId: "4.5", collectionSlug: "muslim", collectionName: "Sahih Muslim")),
            "[Muslim – 4.5]"
        )
        XCTAssertFalse(ReaderSourceLabel.headerText(for: hadith()).contains("Chapter"))
        XCTAssertFalse(ReaderSourceLabel.headerText(for: hadith()).contains("Hadith"))
    }

    // MARK: - Narrator visibility (translation metadata)

    func testNarratorShowsWithTranslationLayer() {
        XCTAssertTrue(ReaderNarratorLine.shouldShow(
            narrator: "Narrated by Umar", translationVisible: true
        ))
    }

    func testNarratorHiddenInArabicOnlyMode() {
        // The narrator is translation metadata: hiding the translation
        // layer hides the narrator even when one exists.
        XCTAssertFalse(ReaderNarratorLine.shouldShow(
            narrator: "Narrated by Umar", translationVisible: false
        ))
        XCTAssertFalse(ReaderNarratorLine.shouldShow(narrator: nil, translationVisible: true))
        XCTAssertFalse(ReaderNarratorLine.shouldShow(narrator: "  ", translationVisible: true))
    }

    // MARK: - Saved-state mini markers

    func testSavedMarkersBookmarkThenFavorite() {
        XCTAssertEqual(
            ReaderSavedMarkers.visible(bookmarked: true, favorited: true),
            [.bookmark, .favorite]
        )
        XCTAssertEqual(
            ReaderSavedMarkers.visible(bookmarked: true, favorited: false),
            [.bookmark]
        )
        XCTAssertEqual(
            ReaderSavedMarkers.visible(bookmarked: false, favorited: true),
            [.favorite]
        )
        XCTAssertEqual(
            ReaderSavedMarkers.visible(bookmarked: false, favorited: false),
            []
        )
    }

    // MARK: - Action set

    func testAllSevenActionsWithLoadedTranslation() {
        XCTAssertEqual(ReaderHadithActions.available(hasLoadedTranslation: true).count, 7)
        XCTAssertTrue(ReaderHadithActions.available(hasLoadedTranslation: true).contains(.share))
        XCTAssertTrue(ReaderHadithActions.available(hasLoadedTranslation: true).contains(.report))
    }

    func testReportGatedWithoutLoadedTranslation() {
        let actions = ReaderHadithActions.available(hasLoadedTranslation: false)
        XCTAssertEqual(actions.count, 6)
        XCTAssertFalse(actions.contains(.report))
        // The sighted long-press menu and the VoiceOver set stay identical.
        XCTAssertTrue(actions.contains(.share))
        XCTAssertTrue(actions.contains(.suggest))
    }

    // MARK: - Chapter subtitles

    func testArabicSubtitleOnlyWhenDifferent() {
        XCTAssertEqual(
            ReaderChapterLine.arabicSubtitle(title: "Belief", arabicTitle: "كتاب الإيمان"),
            "كتاب الإيمان"
        )
        for arabic: String? in [nil, "", "  ", "Belief"] {
            XCTAssertNil(
                ReaderChapterLine.arabicSubtitle(title: "Belief", arabicTitle: arabic),
                "arabic \(arabic ?? "nil") must not render a second line"
            )
        }
    }

    func testArabicTitleLookupNeverSynthesizes() {
        let volumes = [
            OutlineVolume(
                volumeId: "2",
                title: "Volume 2",
                hadithCount: 3,
                chapters: [
                    OutlineChapter(
                        chapterId: "42",
                        title: "Belief",
                        arabicTitle: "كتاب الإيمان",
                        hadithCount: 2,
                        firstProviderHadithId: "58"
                    ),
                ]
            ),
        ]
        XCTAssertEqual(
            ReaderChapterLine.arabicTitle(forChapterId: "42", in: volumes, volumeId: "2"),
            "كتاب الإيمان"
        )
        XCTAssertNil(ReaderChapterLine.arabicTitle(forChapterId: "43", in: volumes, volumeId: "2"))
        XCTAssertNil(ReaderChapterLine.arabicTitle(forChapterId: nil, in: volumes, volumeId: "2"))
        XCTAssertNil(ReaderChapterLine.arabicTitle(forChapterId: "42", in: volumes, volumeId: "9"))
        XCTAssertNil(ReaderChapterLine.arabicTitle(forChapterId: "42", in: [], volumeId: "2"))
    }

    // MARK: - Volume corner and range

    func testFullyCachedRequiresCompletePages() {
        XCTAssertTrue(ReaderVolumeRange.isFullyCached(pages: [page(ids: ["57"])]))
        XCTAssertTrue(ReaderVolumeRange.isFullyCached(
            pages: [page(ids: ["57"], hasMore: true), page(ids: ["58"], page: 2)]
        ))
        XCTAssertFalse(ReaderVolumeRange.isFullyCached(pages: []))
        XCTAssertFalse(ReaderVolumeRange.isFullyCached(
            pages: [page(ids: ["57"], hasMore: true)]
        ), "more pages outstanding means the range is not the volume range")
        XCTAssertFalse(ReaderVolumeRange.isFullyCached(
            pages: [page(ids: [], placeholder: true), page(ids: ["57"], page: 2)]
        ), "a skipped placeholder page means the volume is not fully cached")
    }

    func testCornerTextAppendsRangeOnlyWhenCached() {
        XCTAssertEqual(
            ReaderVolumeRange.cornerText(
                volumeTitle: "Volume 2",
                pages: [page(ids: ["57", "58"], hasMore: true), page(ids: ["59"], page: 2)]
            ),
            "Volume 2: 57–59"
        )
        XCTAssertEqual(
            ReaderVolumeRange.cornerText(volumeTitle: "Volume 2", pages: [page(ids: ["57"])]),
            "Volume 2: 57"
        )
        XCTAssertEqual(
            ReaderVolumeRange.cornerText(
                volumeTitle: "Volume 2",
                pages: [page(ids: ["57"], hasMore: true)]
            ),
            "Volume 2",
            "title only while pages are still loading"
        )
        XCTAssertEqual(
            ReaderVolumeRange.cornerText(volumeTitle: "Volume 2", pages: []),
            "Volume 2"
        )
    }

    func testVolumeHeaderOnlyOnFirstPage() {
        XCTAssertTrue(ReaderVolumeHeader.showsHeader(pageIndex: 0))
        XCTAssertFalse(ReaderVolumeHeader.showsHeader(pageIndex: 1))
        XCTAssertTrue(ReaderVolumeHeader.showsCornerLabel(pageIndex: 1))
        XCTAssertFalse(ReaderVolumeHeader.showsCornerLabel(pageIndex: 0))
    }

    // MARK: - String Catalog plurals

    func testVolumeCountPluralEntryExists() throws {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Hadithly/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let entry = try XCTUnwrap(strings["%lld hadiths"] as? [String: Any])
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
        let english = try XCTUnwrap(localizations["en"] as? [String: Any])
        let variations = try XCTUnwrap(english["variations"] as? [String: Any])
        let plural = try XCTUnwrap(variations["plural"] as? [String: Any])
        XCTAssertNotNil(plural["one"], "English needs the one category (1 hadith)")
        XCTAssertNotNil(plural["other"], "English needs the other category (10 hadiths)")
    }

    // MARK: - Position survival across the density restyle

    /// Slice A changes spacing, alignment, and chrome but keeps the R1/R2
    /// position path byte-identical: the reanchored projection preserves
    /// the semantic anchor and offsets against the current layout
    /// signature, so restoration lands exactly where reading stopped.
    func testReanchorPreservesAnchorAcrossRestyle() {
        let anchor = hadith(providerHadithId: "57")
        let layout = ReadingLayout(
            locale: "en",
            arabicVisible: true,
            translationVisible: true,
            arabicFontId: "amiri",
            arabicFontSize: 26,
            widthClass: .compact,
            paginationVersion: 1
        )
        let pageResult = page(ids: ["57", "58"])
        let position = ReaderModel.reanchoredPosition(
            anchor: anchor,
            page: pageResult,
            volumeId: "2",
            rawPageOffset: 120,
            normalizedOffset: 0.25,
            layout: layout
        )
        XCTAssertEqual(position.anchor.providerHadithId, "57")
        XCTAssertEqual(position.anchor.collectionSlug, "bukhari")
        XCTAssertEqual(position.layoutSignature, layout.signature)
        XCTAssertEqual(position.normalizedOffset, 0.25, accuracy: 1e-9)
        XCTAssertEqual(position.rawPageOffset, 120, accuracy: 1e-9)
        XCTAssertEqual(position.volumeId, "2")
    }

    func testScrollRestorationMathUnchanged() {
        // Tall item: the normalized offset maps into the scrollable range
        // as offset / (itemHeight - viewportHeight), unclamped.
        XCTAssertEqual(
            ReaderScrollRestoration.anchorY(normalizedOffset: 0, itemHeight: 2000, viewportHeight: 700),
            0, accuracy: 1e-9
        )
        XCTAssertEqual(
            ReaderScrollRestoration.anchorY(normalizedOffset: 1, itemHeight: 2000, viewportHeight: 700),
            2000 / 1300, accuracy: 1e-9
        )
        // Short items and empty viewports anchor at the top, as before.
        XCTAssertEqual(
            ReaderScrollRestoration.anchorY(normalizedOffset: 0.5, itemHeight: 400, viewportHeight: 700),
            0, accuracy: 1e-9
        )
    }
}
