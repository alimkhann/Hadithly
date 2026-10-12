import CryptoKit
import DeviceCheck
import Foundation
import XCTest
@testable import Hadithly

final class AppAttestQ1LiveTests: XCTestCase {
    private struct Input: Decodable { let payload: String; let kind: String; let keyId: String? }
    private struct Output: Encodable { let keyId: String; let attestation: String?; let assertion: String? }
    @MainActor
    func testHardwareProofForServerChallenge() async throws {
        guard ProcessInfo.processInfo.environment["Q1_HARDWARE_PROOF"] == "1" else { throw XCTSkip("Opt-in physical App Attest check") }
        XCTAssertTrue(DCAppAttestService.shared.isSupported)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let input = try JSONDecoder().decode(Input.self, from: Data(contentsOf: documents.appendingPathComponent("q1-attest-input.json")))
        let hash = Data(SHA256.hash(data: Data(input.payload.utf8)))
        let output: Output
        if input.kind == "attestation" {
            let keyId = try await DCAppAttestService.shared.generateKey()
            let bytes = try await DCAppAttestService.shared.attestKey(keyId, clientDataHash: hash)
            output = Output(keyId: keyId, attestation: bytes.base64EncodedString(), assertion: nil)
        } else {
            let keyId = try XCTUnwrap(input.keyId)
            let bytes = try await DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: hash)
            output = Output(keyId: keyId, attestation: nil, assertion: bytes.base64EncodedString())
        }
        let outputURL = documents.appendingPathComponent("q1-attest-output.json")
        try JSONEncoder().encode(output).write(to: outputURL, options: [.atomic, .completeFileProtection])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }
}
