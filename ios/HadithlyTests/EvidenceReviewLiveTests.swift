import XCTest
import UIKit
import CryptoKit
import ClerkKit
import ClerkConvex
import ConvexMobile
@testable import Hadithly

final class EvidenceReviewLiveTests: XCTestCase {
    private struct Draft: Decodable {
        struct Item: Decodable { let itemId: String; let state: String }
        let submissionId: String
        let status: String
        let items: [Item]
        let citations: [EvidenceCitation]?
        let appeal: EvidenceAppealState?
    }
    private struct Finalized: Decodable { let status: String }
    private struct Translation: Decodable { let _id: String; let content: String; let source: String; let citations: [ReaderCitation]?; let aiModel: String? }

    @MainActor
    func testSignedInEvidencePublishesThroughBothReviewsAndMaterializesForReader() async throws {
        let e4 = ProcessInfo.processInfo.environment["E4_LIVE_VERIFICATION"] == "1"
        guard e4 || ProcessInfo.processInfo.environment["E3_LIVE_VERIFICATION"] == "1" else { throw XCTSkip("Opt-in development evidence integration") }
        let config = AppConfig()
        let url = try XCTUnwrap(URL(string: config.convexURL))
        XCTAssertTrue(url.host?.contains("festive-cobra-664") == true)
        for _ in 0..<200 { if Clerk.shared.isLoaded { break }; try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertNotNil(Clerk.shared.session, "An existing signed-in development session is required")
        let provider = ClerkConvexAuthProvider()
        let client = ConvexClientWithAuth(deploymentUrl: config.convexURL, authProvider: provider)
        provider.bind(client: client); _ = await client.loginFromCache()
        let phrase = "This is a test text."
        let png = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 180)).pngData { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 900, height: 180))
            (phrase as NSString).draw(at: CGPoint(x: 30, y: 50), withAttributes: [.font: UIFont.systemFont(ofSize: 36), .foregroundColor: UIColor.black])
        }
        let descriptor: [String: ConvexEncodable?] = ["kind": "file", "clientItemKey": "e3_native_fixture", "declaredMime": "image/png", "declaredSize": Double(png.count),
            "declaredSha256": SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined(), "displayName": "e3-verification.png"]
        let resumed: Draft?
        if e4 {
            resumed = try await client.subscribe(to: "evidence:getOwnEvidenceForTarget", with: ["hadithInternalId": "local_dump:e3_fixture:9001", "language": "en"], yielding: Draft?.self).values.first(where: { _ in true }) ?? nil
        } else { resumed = nil }
        let draft: Draft
        if let resumed { draft = resumed } else {
        draft = try await client.mutation("evidence:createEvidenceDraft", with: ["hadithInternalId": "local_dump:e3_fixture:9001", "language": "en", "proposedContent": phrase, "draftKey": UUID().uuidString, "items": [descriptor] as ConvexEncodable?])
        let item = try XCTUnwrap(draft.items.first)
        let cachedToken = try await Clerk.shared.auth.getToken()
        let token = try XCTUnwrap(cachedToken)
        var components = try XCTUnwrap(URLComponents(string: config.convexURL))
        components.host = String(try XCTUnwrap(components.host).dropLast(".convex.cloud".count)) + ".convex.site"
        components.path = "/evidence/upload"
        var request = URLRequest(url: try XCTUnwrap(components.url)); request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); request.setValue("image/png", forHTTPHeaderField: "Content-Type")
        request.setValue(draft.submissionId, forHTTPHeaderField: "X-Evidence-Submission-Id"); request.setValue(item.itemId, forHTTPHeaderField: "X-Evidence-Item-Id")
        let (_, response) = try await URLSession.shared.upload(for: request, from: png)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let _: Finalized = try await client.mutation("evidence:finalizeEvidenceDraft", with: ["submissionId": draft.submissionId, "contributionConsentVersion": "e3-contribution-v1"])
        }
        let completion = Task { @MainActor in
            for try await snapshot in client.subscribe(to: "evidence:getOwnEvidenceDraft", with: ["submissionId": draft.submissionId], yielding: Draft.self).values {
                if e4 ? snapshot.status == "approved" : ["approved", "rejected", "review_unavailable", "processing_failed", "infected"].contains(snapshot.status) { return snapshot }
            }
            throw NSError(domain: "E3Live", code: 1)
        }
        let timeout = Task {
            try? await Task.sleep(for: .seconds(e4 ? 600 : 240))
            if !Task.isCancelled { completion.cancel() }
        }
        defer { timeout.cancel() }
        let final = try await completion.value
        XCTAssertEqual(final.status, "approved"); XCTAssertEqual(final.items.first?.state, "ready"); XCTAssertFalse(final.citations?.isEmpty ?? true)
        let stream = client.subscribe(to: "translations:getDefaultForProviderRef", with: ["provider": "local_dump", "collectionSlug": "e3_fixture", "providerHadithId": "9001", "language": "en"], yielding: Translation?.self)
        let materialized = try await stream.values.first(where: { $0 != nil })
        let translation = try XCTUnwrap(materialized ?? nil)
        XCTAssertEqual(translation.content, phrase); XCTAssertEqual(translation.source, "community"); XCTAssertNil(translation.aiModel); XCTAssertFalse(translation.citations?.isEmpty ?? true)
        if e4 {
            let _: TranslationReportResult = try await client.action("actions/ai:reportTranslation", with: ["translationId": translation._id, "reason": "Compare the complete supplied source again."])
            let replacement = try await client.subscribe(to: "translations:getDefaultForProviderRef", with: ["provider": "local_dump", "collectionSlug": "e3_fixture", "providerHadithId": "9001", "language": "en"], yielding: Translation?.self).values.first(where: { $0 != nil && $0?._id != translation._id })
            XCTAssertEqual(try XCTUnwrap(replacement ?? nil).content, phrase)
            let availability = try await client.subscribe(to: "translations:watchPublications", with: ["translationIds": [translation._id]], yielding: [PublicationAvailability].self).values.first(where: { $0.first?.available == false })
            XCTAssertEqual(availability?.first?.available, false)
            let adverse = try await client.subscribe(to: "evidence:getOwnEvidenceDraft", with: ["submissionId": draft.submissionId], yielding: Draft.self).values.first(where: { $0.status == "rejected" })
            XCTAssertEqual(adverse?.appeal?.available, true)
            let _: Finalized = try await client.mutation("evidenceCases:requestAppeal", with: ["submissionId": draft.submissionId, "reason": "The supplied source supports this exact test text."])
            let resolved = try await client.subscribe(to: "evidence:getOwnEvidenceDraft", with: ["submissionId": draft.submissionId], yielding: Draft.self).values.first(where: { $0.appeal?.status == "published" })
            XCTAssertEqual(resolved?.status, "approved")
        }
    }
}
