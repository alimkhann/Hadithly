import XCTest
@testable import Hadithly

final class WidgetSnapshotTests: XCTestCase {
    func testSnapshotAtRefreshBudgetIsFresh() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(WidgetRefreshPolicy.isStale(now.addingTimeInterval(-WidgetRefreshPolicy.maximumAge), now: now))
    }

    func testSnapshotBeyondRefreshBudgetIsStale() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(WidgetRefreshPolicy.isStale(now.addingTimeInterval(-WidgetRefreshPolicy.maximumAge - 1), now: now))
    }

    func testDailySnapshotIsStaleAfterItsLocalDayChanges() {
        let snapshot = WidgetDailySnapshot(
            collectionSlug: "bukhari", providerHadithId: "1", reference: "Bukhari · 1",
            text: "Text", arabicText: "متن", locale: "ur", arabicVisible: true, translationVisible: true, isAI: true, sourceScope: "Sahih collection scope · Sunnah.now",
            localDate: "2026-09-19", timezone: "Asia/Almaty", isOffline: false,
            updatedAt: Date(timeIntervalSince1970: 1_758_312_000)
        )
        XCTAssertTrue(WidgetRefreshPolicy.isStale(snapshot, now: Date(timeIntervalSince1970: 1_758_384_000)))
    }

    func testDailyPayloadDoesNotContainPrivateReadingFields() throws {
        let payload = DailyWidgetPayload(
            collectionSlug: "bukhari", providerHadithId: "57", reference: "Bukhari · 57",
            text: "translation", arabicText: "متن", locale: "ur", arabicVisible: true, translationVisible: true, isAI: true, sourceScope: "Sahih collection scope · Sunnah.now",
            localDate: "2026-09-19", timezone: "Asia/Almaty", updatedAt: 1_000
        )
        let encoded = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)
        XCTAssertFalse(encoded.contains("note"))
        XCTAssertFalse(encoded.contains("position"))
        XCTAssertFalse(encoded.contains("account"))
    }

    func testContinueSnapshotContainsPresentationOnly() throws {
        let snapshot = WidgetContinueSnapshot(
            reference: "Bukhari · Hadith 57", progressFraction: 0.57,
            progressOrdinal: 57, progressTotal: 100, locale: "ur", updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        for forbidden in ["collectionSlug", "providerHadithId", "position", "account", "note", "volumeId", "arabicExcerpt", "translationExcerpt"] {
            XCTAssertFalse(encoded.contains(forbidden), "Continue widget cache must not contain \(forbidden)")
        }
    }

    func testContinuePresentationKeepsOnlyOneReferenceAndSemanticProgress() {
        let presentation = ContinueWidgetPresentation(
            reference: "Bukhari · Hadith 57", progressFraction: 0.57, progressOrdinal: 57, progressTotal: 100, locale: "en"
        )
        XCTAssertEqual(presentation.compactLines, ["Bukhari · Hadith 57", "Hadith 57 of 100"])
        XCTAssertEqual(presentation.accessoryInlineText, "Resume reading")
        XCTAssertFalse(presentation.isRightToLeft)
        XCTAssertEqual(ContinueWidgetPresentation.emptyMessage, "Read a hadith to continue here.")
        XCTAssertEqual(ContinueWidgetPresentation.lockMessage, "Unlock Hadithly to resume reading.")
    }

    func testContinuePresentationMirrorsUrdu() {
        let presentation = ContinueWidgetPresentation(reference: "Bukhari · Hadith 57", progressFraction: 0.5, progressOrdinal: 57, progressTotal: 100, locale: "ur")
        XCTAssertTrue(presentation.isRightToLeft)
        XCTAssertTrue(presentation.localizedReference.contains("حدیث"))
        XCTAssertTrue(presentation.progressLabel.contains("حدیث"))
    }

    func testContinueProgressUsesOrdinalWhenTotalIsUnavailable() {
        let presentation = ContinueWidgetPresentation(reference: "Bukhari · Hadith 57", progressFraction: nil, progressOrdinal: 57, progressTotal: nil, locale: "ar")
        XCTAssertEqual(presentation.progressLabel, "التقدم: الحديث 57")
    }

    func testWidgetEmptyCopyUsesSelectedLocale() {
        XCTAssertEqual(DailyWidgetCopy.title("ar"), "الحديث اليومي")
        XCTAssertEqual(DailyWidgetCopy.empty("ur"), "آج کی حدیث تیار کرنے کے لیے حدیثلی کھولیں۔")
        XCTAssertEqual(ContinueWidgetPresentation(reference: "", progressFraction: nil, progressOrdinal: nil, progressTotal: nil, locale: "ar").localizedEmptyMessage, "اقرأ حديثًا للمتابعة هنا.")
    }

    func testNativeGaugeReceivesAClampedRoundedFraction() {
        XCTAssertEqual(WidgetProgressGaugeValue(fraction: 251.0 / 7277.0).value, 0.03)
        XCTAssertEqual(WidgetProgressGaugeValue(fraction: 3).value, 1)
    }

    func testNativeGaugeHasNoValueWhenProgressIsUnavailable() {
        XCTAssertNil(WidgetProgressGaugeValue(fraction: nil).value)
    }
}
