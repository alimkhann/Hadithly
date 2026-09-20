import XCTest
@testable import Hadithly

final class ContinueWidgetRouteTests: XCTestCase {
    func testGenericWidgetRequestUsesCurrentLibraryPosition() {
        let position = ReadingPosition.legacy(
            collectionSlug: "bukhari", providerHadithId: "57", volumeId: "2", updatedAt: 1_000
        )!
        let entry = ProgressEntry(
            collectionSlug: "bukhari",
            hadith: HadithRef(
                hadithId: "local-only", collectionSlug: "bukhari", collectionName: "Sahih al-Bukhari",
                volumeId: "2", hadithNumber: "57", arabicText: "", englishText: "", referenceDisplay: "Bukhari · Hadith 57"
            ), position: position, updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let target = ContinueWidgetRoute.target(from: [entry])
        XCTAssertEqual(target?.source, .continueReading)
        XCTAssertEqual(target?.position?.anchor.providerHadithId, "57")
        XCTAssertEqual(target?.position?.normalizedOffset, position.normalizedOffset)
    }

    func testGenericWidgetRequestPrefersTheNewestSyncedPosition() {
        func entry(number: String, updatedAt: TimeInterval) -> ProgressEntry {
            ProgressEntry(
                collectionSlug: "bukhari",
                hadith: HadithRef(
                    hadithId: "local-\(number)", collectionSlug: "bukhari", collectionName: "Sahih al-Bukhari",
                    volumeId: "2", hadithNumber: number, arabicText: "", englishText: "", referenceDisplay: "Bukhari · Hadith \(number)"
                ),
                position: ReadingPosition.legacy(collectionSlug: "bukhari", providerHadithId: number, volumeId: "2", updatedAt: updatedAt)!,
                updatedAt: Date(timeIntervalSince1970: updatedAt)
            )
        }
        XCTAssertEqual(ContinueWidgetRoute.target(from: [entry(number: "21", updatedAt: 1_000), entry(number: "57", updatedAt: 2_000)])?.position?.anchor.providerHadithId, "57")
    }
}
