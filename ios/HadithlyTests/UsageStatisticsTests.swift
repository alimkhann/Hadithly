import XCTest
@testable import Hadithly

@MainActor final class UsageStatisticsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() {
        suite = "LA2Tests.\(UUID().uuidString)"; defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }
    func testDevelopmentNativeTransportFixture() async throws {
        guard ProcessInfo.processInfo.environment["HADITHLY_LA2_LIVE"] == "1" else { throw XCTSkip("Opt-in development transport proof") }
        for _ in 0..<5 {
            let fixtureSuite = "LA2Live.\(UUID().uuidString)"
            let fixtureDefaults = UserDefaults(suiteName: fixtureSuite)!
            defer { fixtureDefaults.removePersistentDomain(forName: fixtureSuite) }
            let store = UsageStatistics(cloudURL: "https://festive-cobra-664.eu-west-1.convex.cloud", defaults: fixtureDefaults)
            store.startOnboarding()
            for metric in [AnalyticsMetric.onboardingStepWelcomeViewed, .onboardingStepLanguageViewed, .onboardingStepDemoViewed, .onboardingStepDemoUsed, .onboardingStepEntryViewed] { store.record(metric) }
            store.completeOnboarding(.onboardingCompletedGuest)
            try await waitForUpload(store, fixtureDefaults)
            var reader = ReaderMeasurement()
            for metric in reader.begin(guest: true, restoration: true, notification: true) { store.record(metric) }
            for metric in reader.visible(offline: false) + reader.settleTarget(exact: true) { store.record(metric) }
            store.firstReaderSucceeded()
            try await waitForUpload(store, fixtureDefaults)
            for metric in [AnalyticsMetric.offlineActivationResultStarted, .offlineActivationResultActivated, .translationResultStarted, .translationResultQuota,
                .paywallResultShown, .paywallResultAvailable, .paywallResultPurchaseStarted, .purchaseResultMonthlyStarted, .purchaseResultConfirmed,
                .paywallResultConfirmed, .recoverableErrorTranslation, .recoverableErrorTranslationRecovered] { store.record(metric) }
            store.flush(); try await waitForUpload(store, fixtureDefaults)
            XCTAssertEqual(store.clipped, 0); store.setSharing(false)
        }
    }
    private func waitForUpload(_ store: UsageStatistics, _ fixtureDefaults: UserDefaults) async throws {
        for _ in 0..<100 {
            if let data = fixtureDefaults.data(forKey: "analytics.counts.v1"),
               let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let pending = json["pending"] as? [Any], pending.isEmpty { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("Development fixture upload did not drain"); store.setSharing(false)
    }
    func testSameOperationRecoveryExpiresAndClippedOrderingCannotResumeAcrossMidnight() throws {
        var time = Date(timeIntervalSince1970: 86_400 * 100 + 86_390)
        let store = UsageStatistics(cloudURL: "invalid", defaults: defaults, now: { time })
        store.record(.translationResultFailed); store.record(.offlineActivationResultActivated)
        store.record(.translationResultCache)
        store.record(.purchaseResultRestoreFailed); time.addTimeInterval(1801); store.record(.purchaseResultRestoreConfirmed)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(defaults.data(forKey: "analytics.counts.v1"))) as? [String: Any])
        let counterText = String(describing: raw)
        XCTAssertTrue(counterText.contains("recoverable_error.translation_recovered"))
        XCTAssertFalse(counterText.contains("recoverable_error.purchase_recovered"))
        store.clearPending()
        time = Date(timeIntervalSince1970: 86_400 * 200 + 86_390)
        for _ in 0..<39 { store.record(.translationResultCache) }
        store.record(.onboardingStepWelcomeViewed); store.record(.onboardingStepLanguageViewed)
        store.record(.onboardingStepDemoViewed); store.record(.onboardingStepEntryViewed); store.completeOnboarding(.onboardingCompletedGuest)
        time.addTimeInterval(20); store.record(.onboardingCompletedFirstReaderSuccess)
        let data = try XCTUnwrap(defaults.data(forKey: "analytics.counts.v1"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("onboarding_step.ordered_first_reader"))
    }
    func testPaywallSequenceRejectsOutOfOrderAndRepeatedStages() throws {
        let store = UsageStatistics(cloudURL: "invalid", defaults: defaults)
        store.record(.paywallResultConfirmed)
        for _ in 0..<2 { store.record(.paywallResultShown); store.record(.paywallResultAvailable); store.record(.paywallResultPurchaseStarted) }
        store.record(.paywallResultConfirmed); store.record(.paywallResultConfirmed)
        let data = try XCTUnwrap(defaults.data(forKey: "analytics.counts.v1"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["counts"] as? [String: Int], ["paywall_result.shown": 1, "paywall_result.available": 1, "paywall_result.purchase_started": 1, "paywall_result.confirmed": 1])
    }
    func testCorruptRetryStateCannotOverflowOrRestoreUnboundedAttempts() throws {
        let hour = Int(Date().timeIntervalSince1970 / 3600)
        let summary: [String: Any] = ["version": 1, "platform": "ios", "batchId": UUID().uuidString.lowercased(), "hour": hour,
            "counters": [["metric": "reader_open_result.guest_online", "count": 1]]]
        for invalidHour in [hour, Int.max] {
            defaults.set(true, forKey: "analytics.sharing")
            let raw: [String: Any] = ["day": hour / 24, "admitted": 0, "hour": invalidHour, "counts": [:],
                "pending": [["summary": summary, "attempts": -100]]]
            defaults.set(try JSONSerialization.data(withJSONObject: raw), forKey: "analytics.counts.v1")
            let store = UsageStatistics(cloudURL: "invalid", defaults: defaults)
            store.record(.readerOpenResultGuestOnline)
            let clean = try XCTUnwrap(defaults.data(forKey: "analytics.counts.v1"))
            XCTAssertFalse(String(decoding: clean, as: UTF8.self).contains("-100"))
            store.setSharing(false)
        }
    }
    func testMalformedPrivacyChoiceFailsClosedEvenWhenNSNumberIsOne() {
        for value in [0, 1, 2, 42] {
            defaults.removeObject(forKey: "analytics.sharing")
            defaults.set(value, forKey: "analytics.sharing")
            XCTAssertFalse(UsageStatistics(cloudURL: "invalid", defaults: defaults).sharing)
        }
        defaults.set(true, forKey: "analytics.sharing")
        XCTAssertTrue(UsageStatistics(cloudURL: "invalid", defaults: defaults).sharing)
    }
    func testClosedCatalogAndPreparedExamples() {
        XCTAssertEqual(Set(AnalyticsMetric.allCases.map { $0.rawValue.split(separator: ".")[0] }).count, 10)
        XCTAssertEqual(Set(PreparedTranslationExample.translations.keys), Set(SupportedLanguages.all.map(\.code)))
        XCTAssertEqual(PreferencesStore.suggestedLanguage(["de-DE", "kk-KZ", "en-US"]), "kk")
        XCTAssertEqual(PreferencesStore.suggestedLanguage(["zz-ZZ"]), "en")
    }
    func testReaderCancellationRecoveryAndTargetVerdictsAreDistinct() {
        var cancelled = ReaderMeasurement()
        _ = cancelled.begin(guest: true, restoration: false, notification: false)
        XCTAssertEqual(cancelled.close(), [.readerOpenResultAbandoned])
        XCTAssertEqual(cancelled.failure(), [])
        var failedTarget = ReaderMeasurement()
        _ = failedTarget.begin(guest: true, restoration: true, notification: true)
        _ = failedTarget.failure()
        XCTAssertEqual(failedTarget.close(), [.restorationResultFailed, .notificationOpenResultFailed])
        var reader = ReaderMeasurement()
        _ = reader.begin(guest: true, restoration: true, notification: true)
        XCTAssertEqual(reader.failure(), [.readerOpenResultFailed, .recoverableErrorReader])
        XCTAssertEqual(reader.failure(), [])
        XCTAssertEqual(reader.visible(offline: false), [.readerOpenResultGuestStarted, .readerOpenResultGuestOnline, .recoverableErrorReaderRecovered])
        XCTAssertEqual(reader.settleTarget(exact: false), [.restorationResultFallback, .notificationOpenResultFallback])
        XCTAssertEqual(reader.settleTarget(exact: true), [])
        XCTAssertEqual(reader.failure(), [.recoverableErrorReader])
        XCTAssertEqual(reader.visible(offline: true), [.recoverableErrorReaderRecovered])
    }
    func testStrictNativeDecoderRejectsUnknownFieldsAndValues() throws {
        let valid: [String: Any] = ["version": 1, "platform": "ios", "batchId": UUID().uuidString.lowercased(), "hour": 1,
            "counters": [["metric": "onboarding_completed.guest", "count": 1]]]
        let decoder = JSONDecoder()
        XCTAssertNoThrow(try decoder.decode(AnalyticsSummary.self, from: JSONSerialization.data(withJSONObject: valid)))
        for key in ["text", "locale", "token", "email", "canonicalId", "notes", "properties"] {
            var dirty = valid; dirty[key] = "PRIVATE_CANARY"
            XCTAssertThrowsError(try decoder.decode(AnalyticsSummary.self, from: JSONSerialization.data(withJSONObject: dirty)))
        }
        var nested = valid; nested["counters"] = [["metric": "onboarding_completed.guest", "count": 1, "text": "PRIVATE_CANARY"]]
        XCTAssertThrowsError(try decoder.decode(AnalyticsSummary.self, from: JSONSerialization.data(withJSONObject: nested)))
        for count in [-1, 0, 41] {
            nested["counters"] = [["metric": "onboarding_completed.guest", "count": count]]
            XCTAssertThrowsError(try decoder.decode(AnalyticsSummary.self, from: JSONSerialization.data(withJSONObject: nested)))
        }
    }
    func testFortyFactCapAndIndependentOptOut() throws {
        let store = UsageStatistics(cloudURL: "invalid", defaults: defaults)
        for _ in 0..<50 { store.record(.readerOpenResultGuestOnline) }
        let json = try XCTUnwrap(defaults.data(forKey: "analytics.counts.v1"))
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        XCTAssertEqual(raw["admitted"] as? Int, 40); XCTAssertEqual(store.clipped, 11)
        defaults.set(true, forKey: "diagnostics.consent")
        store.setSharing(false)
        XCTAssertNil(defaults.data(forKey: "analytics.counts.v1")); XCTAssertTrue(defaults.bool(forKey: "diagnostics.consent"))
        store.record(.onboardingCompletedGuest)
        XCTAssertNil(defaults.data(forKey: "analytics.counts.v1"))
        XCTAssertFalse(UsageStatistics(cloudURL: "invalid", defaults: defaults).sharing)
    }
    func testExpiryAndSignOutErasePendingFacts() throws {
        var time = Date(timeIntervalSince1970: 3_600_000)
        let store = UsageStatistics(cloudURL: "invalid", defaults: defaults, now: { time })
        store.record(.restorationResultExact)
        time.addTimeInterval(86_400)
        store.flush()
        let data = try XCTUnwrap(defaults.data(forKey: "analytics.counts.v1"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("restoration_result.exact"))
        store.record(.onboardingCompletedGuest); store.clearPending()
        XCTAssertNil(defaults.data(forKey: "analytics.counts.v1"))
    }
    func testOrderedFunnelKeepsItsStartCohortAcrossMidnight() throws {
        var time = Date(timeIntervalSince1970: 86_400 * 100 + 86_390)
        let store = UsageStatistics(cloudURL: "invalid", defaults: defaults, now: { time })
        store.record(.onboardingStepWelcomeViewed)
        time.addTimeInterval(20)
        store.record(.onboardingStepLanguageViewed)
        store.record(.onboardingStepLanguageViewed)
        let data = try XCTUnwrap(defaults.data(forKey: "analytics.counts.v1"))
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let pending = try XCTUnwrap(raw["pending"] as? [[String: Any]])
        let summaries = pending.compactMap { $0["summary"] as? [String: Any] }
        XCTAssertTrue(summaries.contains { ($0["hour"] as? Int) == 100 * 24 + 23 })
        let counts = raw["counts"] as? [String: Int]
        let counters = summaries.flatMap { $0["counters"] as? [[String: Any]] ?? [] }
        let ordered = counters.filter { ($0["metric"] as? String) == "onboarding_step.ordered_language" }
            .reduce(0) { $0 + ($1["count"] as? Int ?? 0) }
        XCTAssertEqual(ordered + (counts?["onboarding_step.ordered_language"] ?? 0), 1)
    }
    func testRetryNeverSendsAfterQueueExpiry() async {
        var time = Date()
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AnalyticsProtocol.self]
        let first = expectation(description: "first attempt")
        let extra = expectation(description: "expired request must not send"); extra.isInverted = true
        var requests = 0
        AnalyticsProtocol.status = 503
        AnalyticsProtocol.receive = { _ in requests += 1; if requests == 1 { first.fulfill() } else { extra.fulfill() } }
        let store = UsageStatistics(cloudURL: "https://test.convex.cloud", defaults: defaults, now: { time }, session: URLSession(configuration: config))
        store.record(.restorationResultExact); store.flush()
        await fulfillment(of: [first], timeout: 3)
        time.addTimeInterval(86_400)
        await fulfillment(of: [extra], timeout: 13)
        store.setSharing(false); AnalyticsProtocol.receive = nil; AnalyticsProtocol.status = 204
    }
    func testActualSerializedRequestHasNoAuthCookieIdentityOrContent() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AnalyticsProtocol.self]
        let captured = expectation(description: "summary sent")
        AnalyticsProtocol.receive = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertEqual(request.url?.path, "/analytics/summary")
            var bytes = request.httpBody ?? Data()
            if let stream = request.httpBodyStream, bytes.isEmpty {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }; bytes.append(buffer, count: count)
                }
            }
            do {
                let summary = try JSONDecoder().decode(AnalyticsSummary.self, from: bytes)
                XCTAssertEqual(summary.counters, [AnalyticsCounter(metric: .readerOpenResultGuestOnline, count: 1)])
            } catch { XCTFail("Invalid serialized analytics summary") }
            captured.fulfill()
        }
        let store = UsageStatistics(cloudURL: "https://test.convex.cloud", defaults: defaults, session: URLSession(configuration: config))
        store.record(.readerOpenResultGuestOnline); store.flush()
        await fulfillment(of: [captured], timeout: 3)
        store.setSharing(false); AnalyticsProtocol.receive = nil
    }
}

private final class AnalyticsProtocol: URLProtocol {
    static var receive: ((URLRequest) -> Void)?
    static var status = 204
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.receive?(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
