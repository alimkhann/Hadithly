import DeviceCheck
import ClerkKit
import ClerkConvex
import ConvexMobile
import XCTest
@testable import Hadithly

final class TranslationQ1LiveTests: XCTestCase {
    private struct Target: Decodable { let canonicalId: String; let language: String }
    private struct Allowance: Decodable { let used: Double; let remaining: Double }

    @MainActor
    func testExplicitAuthenticatedGenerationAndCacheReuse() async throws {
        guard ProcessInfo.processInfo.environment["Q1_LIVE_VERIFICATION"] == "1" else { throw XCTSkip("Opt-in Q1 development integration") }
        if ProcessInfo.processInfo.environment["Q1_REAL_ATTEST"] == "1" { XCTAssertTrue(DCAppAttestService.shared.isSupported) }
        let config = AppConfig()
        XCTAssertTrue(config.convexURL.contains("festive-cobra-664"))
        for _ in 0..<200 { if Clerk.shared.isLoaded { break }; try await Task.sleep(for: .milliseconds(100)) }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let ticketFile = documents.appendingPathComponent("q1-signin-ticket")
        if Clerk.shared.session == nil, FileManager.default.fileExists(atPath: ticketFile.path) {
            defer { try? FileManager.default.removeItem(at: ticketFile) }
            do {
                let ticket = try String(contentsOf: ticketFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                let signedIn = try await Clerk.shared.auth.signInWithTicket(ticket)
                if let sessionId = signedIn.createdSessionId { try await Clerk.shared.auth.setActive(sessionId: sessionId) }
            } catch { throw NSError(domain: "Q1Live", code: 1, userInfo: [NSLocalizedDescriptionKey: "Temporary development sign-in failed"]) }
        }
        XCTAssertNotNil(Clerk.shared.session, "An existing signed-in development session is required")
        let targetURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("q1-native-target.json")
        let target = try JSONDecoder().decode(Target.self, from: Data(contentsOf: targetURL))
        let provider = ClerkConvexAuthProvider()
        let client = ConvexClientWithAuth(deploymentUrl: config.convexURL, authProvider: provider)
        provider.bind(client: client); _ = await client.loginFromCache()
        let _: String = try await client.mutation("users:ensureCurrentUser", with: [:])
        let available = try await client.subscribe(to: "translations:getReaderDefaults", with: ["hadithInternalIds": [target.canonicalId], "language": target.language], yielding: [ReaderDefaultTranslation].self).values.first(where: { _ in true })
        if let cached = available?.first?.translation {
            let cachedResult: ReaderTranslation = try await client.action("actions/ai:translateHadith", with: ["hadithInternalId": target.canonicalId, "targetLanguage": target.language])
            XCTAssertTrue(cachedResult.cached); XCTAssertEqual(cachedResult.translationId, cached._id)
            return
        }
        let before = try await client.subscribe(to: "quotas:getTranslationAllowance", yielding: Allowance.self).values.first(where: { _ in true })
        let request: [String: ConvexEncodable?] = ["hadithInternalId": target.canonicalId, "targetLanguage": target.language]
        do {
            let _: ReaderTranslation = try await client.action("actions/ai:translateHadith", with: request)
            XCTFail("A new request without proof must be rejected")
        } catch { XCTAssertTrue(ReaderModels.errorMessage(of: error).contains("AI_INTEGRITY_REQUIRED")) }
        let arguments = try await GenerationRequest.arguments(hadithId: target.canonicalId, language: target.language, convex: client)
        let generated: ReaderTranslation = try await client.action("actions/ai:translateHadith", with: arguments)
        XCTAssertFalse(generated.cached); XCTAssertFalse(generated.groundingUsed); XCTAssertFalse(generated.translation.isEmpty)
        let reused: ReaderTranslation = try await client.action("actions/ai:translateHadith", with: request)
        XCTAssertTrue(reused.cached); XCTAssertEqual(reused.translationId, generated.translationId)
        let after = try await client.subscribe(to: "quotas:getTranslationAllowance", yielding: Allowance.self).values.first(where: { _ in true })
        XCTAssertEqual(after?.used, (before?.used ?? -1) + 1)
        let defaults = try await client.subscribe(to: "translations:getReaderDefaults", with: ["hadithInternalIds": [target.canonicalId], "language": target.language], yielding: [ReaderDefaultTranslation].self).values.first(where: { _ in true })
        XCTAssertEqual(defaults?.first?.translation?._id, generated.translationId)
        let other = try await client.subscribe(to: "translations:getReaderDefaults", with: ["hadithInternalIds": [target.canonicalId], "language": "ur"], yielding: [ReaderDefaultTranslation].self).values.first(where: { _ in true })
        XCTAssertNil(other?.first?.translation)
        if ProcessInfo.processInfo.environment["Q1_REAL_ATTEST"] == "1" {
            let assertionArguments = try await GenerationRequest.arguments(hadithId: target.canonicalId, language: "kk", convex: client)
            let assertionResult: ReaderTranslation = try await client.action("actions/ai:translateHadith", with: assertionArguments)
            XCTAssertFalse(assertionResult.cached)
        }
    }
}
