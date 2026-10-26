import XCTest
@testable import Hadithly

@MainActor
final class EvidenceE4Tests: XCTestCase {
    func testAppealDecoderAndExactDeadline() throws {
        let state = try JSONDecoder().decode(EvidenceAppealState.self, from: Data("{\"available\":true,\"deadline\":0,\"status\":\"not_requested\"}".utf8))
        XCTAssertFalse(state.canRequest)
        XCTAssertFalse(EvidenceAppealState(available: true, deadline: Date().timeIntervalSince1970 * 1000 + 60_000, status: "processing").canRequest)
        XCTAssertTrue(EvidenceAppealState(available: true, deadline: Date().timeIntervalSince1970 * 1000 + 60_000, status: "not_requested").canRequest)
    }
    func testRevocationAndSeparatePermissionDeadlinesClearTextAndCitations() {
        func loaded(_ id: String, source: String = "community") -> ReaderModel.TranslationState {
            .loaded(ReaderTranslation(translationId: id, translation: "Private test text", confidence: nil, riskFlags: [], glossaryNotes: [], source: source, sourceLabel: source == "gemini_ai" ? "AI translation" : "Community", aiModel: nil, groundingUsed: source == "gemini_ai", citations: [ReaderCitation(url: "https://example.org", title: "Test", domain: nil)], sourceReferenceUrl: nil, cached: true))
        }
        let original = ["one": loaded("first", source: "gemini_ai"), "two": loaded("second")]
        let statuses = [PublicationAvailability(translationId: "first", available: true, validUntil: 100), PublicationAvailability(translationId: "second", available: true, validUntil: 200)]
        let first = ReaderPublicationPolicy.keepingAvailable(original, statuses: statuses, now: 100)
        XCTAssertNil(first["one"])
        XCTAssertNotNil(first["two"])
        XCTAssertTrue(ReaderPublicationPolicy.keepingAvailable(first, statuses: statuses, now: 200).isEmpty)
        XCTAssertTrue(ReaderPublicationPolicy.keepingAvailable(original, statuses: [PublicationAvailability(translationId: "first", available: false, validUntil: nil), PublicationAvailability(translationId: "second", available: false, validUntil: nil)], now: 0).isEmpty)
    }
}
