import ClerkKit
import ConvexMobile
import CryptoKit
import DeviceCheck
import Foundation

struct TranslationAllowance: Decodable, Equatable {
    let limit: Double
    let remaining: Double
    let retryAt: Double?
}

struct ReaderDefaultTranslation: Decodable {
    let hadithInternalId: String
    let translation: StoredReaderTranslation?
}

private struct GenerationChallenge: Decodable {
    let challengeId: String
    let payload: String
    let keyRegistered: Bool
    let allowUnavailable: Bool
}

/// Device proof is created only for an explicit translation request.
@MainActor
enum GenerationRequest {
    static func arguments(hadithId: String, language: String, convex: ConvexClientWithAuth<String>) async throws -> [String: ConvexEncodable?] {
        let service = DCAppAttestService.shared
        guard let accountId = Clerk.shared.user?.id else { throw GenerationRequestError.signIn }
        let storageKey = "q1.appAttest.\(accountId)"
        var keyId = UserDefaults.standard.string(forKey: storageKey)
        if service.isSupported && keyId == nil {
            keyId = try await service.generateKey()
            UserDefaults.standard.set(keyId, forKey: storageKey)
        }
        var challengeArguments: [String: ConvexEncodable?] = ["hadithInternalId": hadithId, "targetLanguage": language]
        if let keyId { challengeArguments["keyId"] = keyId }
        let challenge: GenerationChallenge = try await convex.mutation("generationIntegrity:beginChallenge", with: challengeArguments)
        let proof: [String: ConvexEncodable?]
        if service.isSupported, let keyId {
            let hash = Data(SHA256.hash(data: Data(challenge.payload.utf8)))
            do {
                if challenge.keyRegistered {
                    let assertion = try await service.generateAssertion(keyId, clientDataHash: hash)
                    proof = ["kind": "app_attest", "keyId": keyId, "assertion": assertion.base64EncodedString()]
                } else {
                    let attestation = try await service.attestKey(keyId, clientDataHash: hash)
                    proof = ["kind": "app_attest", "keyId": keyId, "attestation": attestation.base64EncodedString()]
                }
            } catch {
                // An ambiguous registration can be retried with a fresh hardware key.
                UserDefaults.standard.removeObject(forKey: storageKey)
                throw error
            }
        } else {
            guard challenge.allowUnavailable else { throw GenerationRequestError.integrity }
            proof = ["kind": "unavailable"]
        }
        return ["hadithInternalId": hadithId, "targetLanguage": language,
                "challengeId": challenge.challengeId, "proof": proof]
    }
}

private enum GenerationRequestError: Error {
    case signIn
    case integrity
}
