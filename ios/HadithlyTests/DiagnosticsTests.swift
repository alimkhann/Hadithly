import XCTest
import Sentry
import zlib
@testable import Hadithly

final class DiagnosticsTests: XCTestCase {
    func testDefaultReportsAreOnAndExplicitOptOutPersists() throws {
        let suite = "diagnostics-default-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(CrashReporting(defaults: defaults).hasConsent)
        defaults.set(false, forKey: "diagnostics.consent")
        XCTAssertFalse(CrashReporting(defaults: defaults).hasConsent)
        defaults.set(true, forKey: "diagnostics.consent")
        XCTAssertTrue(CrashReporting(defaults: defaults).hasConsent)
    }

    func testActualTransportEnvelopeIsRedactedAndOptOutPurgesCache() throws {
        let suite = "hadithly-la1-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let reporter = CrashReporting(defaults: defaults, cache: cache)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DiagnosticsWireProtocol.self]
        let session = URLSession(configuration: config)
        let received = expectation(description: "actual SDK envelope")
        DiagnosticsWireProtocol.receive = { data in
            do {
                let bytes = try Self.gunzip(data)
                let payload = String(decoding: bytes, as: UTF8.self)
                XCTAssertFalse(payload.contains("PRIVATE_TEST_CANARY"))
                XCTAssertFalse(payload.contains("\"user\""))
                XCTAssertFalse(payload.contains("\"request\""))
                XCTAssertFalse(payload.contains("\"attachment\""))
                XCTAssertTrue(payload.contains("HadithlyNativeFailure"))
                XCTAssertTrue(payload.contains("\"surface\":\"ios\"") || payload.contains("\"surface\": \"ios\""))
                received.fulfill()
            } catch { XCTFail("Could not decode actual SDK envelope: \(error)"); received.fulfill() }
        }
        defer {
            reporter.setConsent(false); session.invalidateAndCancel()
            DiagnosticsWireProtocol.receive = nil
            defaults.removePersistentDomain(forName: suite)
        }
        defaults.set(true, forKey: "diagnostics.consent")
        reporter.startIfConsented(dsnOverride: "https://" + String(repeating: "a", count: 32) + "@o1.ingest.de.sentry.io/1", session: session)
        let event = Event(level: .error)
        event.message = SentryMessage(formatted: "PRIVATE_TEST_CANARY")
        event.user = User(userId: "PRIVATE_TEST_CANARY")
        event.exceptions = [Exception(value: "PRIVATE_TEST_CANARY", type: "PRIVATE_TEST_CANARY")]
        event.tags = ["operation": "synthetic"]
        SentrySDK.capture(event: event)
        SentrySDK.flush(timeout: 3)
        wait(for: [received], timeout: 5)
        reporter.setConsent(false)
        XCTAssertFalse(reporter.hasConsent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
    }

    private static func gunzip(_ data: Data) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream, 31, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw NSError(domain: "inflate", code: 1) }
        defer { inflateEnd(&stream) }
        var output = Data(count: 1_000_000)
        let status = data.withUnsafeBytes { input in
            output.withUnsafeMutableBytes { buffer in
                stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: UInt8.self).baseAddress)
                stream.avail_in = UInt32(data.count)
                stream.next_out = buffer.bindMemory(to: UInt8.self).baseAddress
                stream.avail_out = UInt32(buffer.count)
                return inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END else { throw NSError(domain: "inflate", code: Int(status)) }
        output.count = Int(stream.total_out)
        return output
    }
    func testActualSDKSerializationRemovesSensitiveFieldsAndKeepsSymbolAddresses() throws {
        let marker = "PRIVATE_TEST_CANARY"
        let source = Event(level: .fatal)
        source.message = SentryMessage(formatted: marker)
        source.extra = ["note": marker, "arabicText": "نص الاختبار"]
        source.tags = ["user": marker]
        source.context = ["account": ["id": marker]]
        let user = User(userId: marker); user.email = marker; source.user = user
        let frame = Frame()
        frame.instructionAddress = "0x1234"; frame.imageAddress = "0x1200"
        frame.function = marker; frame.contextLine = marker; frame.vars = ["token": marker]
        let stack = SentryStacktrace(frames: [frame], registers: ["secret": marker])
        let exception = Exception(value: marker, type: marker); exception.stacktrace = stack
        source.exceptions = [exception]
        let image = DebugMeta(); image.debugID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        image.imageAddress = "0x1200"; image.imageSize = 2048; image.codeFile = "/private/" + marker
        source.debugMeta = [image]
        source.releaseName = "hadithly@123456abcdef"; source.environment = "development"
        let safe = CrashReporting.redactedPreservingCapture(source)
        XCTAssertTrue(safe === source)
        let bytes = try JSONSerialization.data(withJSONObject: safe.serialize())
        let payload = String(decoding: bytes, as: UTF8.self)
        XCTAssertFalse(payload.contains(marker)); XCTAssertFalse(payload.contains("نص الاختبار"))
        XCTAssertFalse(payload.contains("/private/")); XCTAssertFalse(payload.contains("registers"))
        XCTAssertTrue(payload.contains("0x1234")); XCTAssertTrue(payload.contains(image.debugID!))
        XCTAssertEqual(safe.releaseName, source.releaseName)
        XCTAssertEqual(safe.tags?["surface"], "ios")
    }
}

private final class DiagnosticsWireProtocol: URLProtocol {
    static var receive: ((Data) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let data = request.httpBody { Self.receive?(data) }
        else if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let size = stream.read(&buffer, maxLength: buffer.count)
                if size <= 0 { break }
                data.append(contentsOf: buffer.prefix(size))
            }
            Self.receive?(data)
        } else { XCTFail("SDK transport supplied no readable envelope") }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
