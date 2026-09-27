import XCTest
@testable import Hadithly

final class EvidenceLocalDraftTests: XCTestCase {
    func testEvidencePreflightBoundaries() {
        XCTAssertFalse(EvidenceClientPolicy.acceptsFileSize(0))
        XCTAssertTrue(EvidenceClientPolicy.acceptsFileSize(10_000_000))
        XCTAssertFalse(EvidenceClientPolicy.acceptsFileSize(10_000_001))
        XCTAssertEqual(EvidenceClientPolicy.httpsURL(" https://example.org/source ")?.host, "example.org")
        for value in ["http://example.org", "https://user:password@example.org", "https:/source"] {
            XCTAssertNil(EvidenceClientPolicy.httpsURL(value))
        }
    }

    func testAccountDeletionClearsOnlyOwnedDraftsAndFiles() throws {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "EvidenceDrafts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let first = directory.appending(path: UUID().uuidString)
        let second = directory.appending(path: UUID().uuidString)
        try Data([1]).write(to: first)
        try Data([2]).write(to: second)
        let firstOwner = "test-\(UUID().uuidString)"
        let secondOwner = "test-\(UUID().uuidString)"
        let firstKey = "evidence.draft.\(firstOwner).hadith"
        let secondKey = "evidence.draft.\(secondOwner).hadith"
        defer {
            UserDefaults.standard.removeObject(forKey: firstKey)
            UserDefaults.standard.removeObject(forKey: secondKey)
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        for (key, file) in [(firstKey, first), (secondKey, second)] {
            let payload: [String: Any] = [
                "draftKey": UUID().uuidString,
                "proposedContent": "Private suggestion",
                "urlInput": "",
                "choices": [["id": "file", "kind": "file", "label": "Evidence", "fileURL": file.absoluteString]],
                "createdAt": 1_000.0,
            ]
            UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: payload), forKey: key)
        }

        EvidenceLocalDrafts.clear(for: firstOwner)

        XCTAssertNil(UserDefaults.standard.data(forKey: firstKey))
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertNotNil(UserDefaults.standard.data(forKey: secondKey))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }
}
