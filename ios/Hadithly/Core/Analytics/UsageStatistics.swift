import Foundation
import CoreFoundation
import Observation

struct AnalyticsCounter: Codable, Equatable {
    let metric: AnalyticsMetric
    let count: Int
    enum CodingKeys: String, CodingKey { case metric, count }
    init(metric: AnalyticsMetric, count: Int) { self.metric = metric; self.count = count }
    init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: AnalyticsCodingKey.self)
        guard Set(raw.allKeys.map(\.stringValue)) == ["metric", "count"] else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unapproved analytics field"))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        metric = try values.decode(AnalyticsMetric.self, forKey: .metric)
        count = try values.decode(Int.self, forKey: .count)
        guard (1...40).contains(count) else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid counter")) }
    }
}
struct AnalyticsSummary: Codable, Equatable {
    let version: Int
    let platform: String
    let batchId: String
    let hour: Int
    let counters: [AnalyticsCounter]
    enum CodingKeys: String, CodingKey { case version, platform, batchId, hour, counters }
    init(version: Int, platform: String, batchId: String, hour: Int, counters: [AnalyticsCounter]) {
        self.version = version; self.platform = platform; self.batchId = batchId; self.hour = hour; self.counters = counters
    }
    init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: AnalyticsCodingKey.self)
        guard Set(raw.allKeys.map(\.stringValue)) == ["version", "platform", "batchId", "hour", "counters"] else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unapproved analytics field"))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version); platform = try values.decode(String.self, forKey: .platform)
        batchId = try values.decode(String.self, forKey: .batchId); hour = try values.decode(Int.self, forKey: .hour)
        counters = try values.decode([AnalyticsCounter].self, forKey: .counters)
        guard version == 1, platform == "ios", hour >= 0,
              batchId.range(of: "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", options: .regularExpression) != nil,
              (1...32).contains(counters.count),
              Set(counters.map(\.metric)).count == counters.count, counters.reduce(0, { $0 + $1.count }) <= 40 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid summary"))
        }
    }
}
private struct AnalyticsCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

@MainActor @Observable
final class UsageStatistics {
    private struct Pending: Codable { let summary: AnalyticsSummary; var attempts: Int }
    private struct State: Codable {
        var day: Int = 0
        var admitted: Int = 0
        var hour: Int = 0
        var counts: [String: Int] = [:]
        var pending: [Pending] = []
    }
    private let defaults: UserDefaults
    private let now: () -> Date
    private let endpoint: URL?
    private let session: URLSession
    private var state = State()
    private var task: Task<Void, Never>?
    private var revision = 0
    private var onboardingInProgress = false
    private var awaitingFirstReader = false
    private var firstReaderDeadline: Date?
    private var recoveryDeadlines: [AnalyticsMetric: Date] = [:]
    private var paywallStage = -1
    private var paywallHour = 0
    private var paywallDeadline = Date.distantPast
    private var funnelStage = -1
    private var funnelHour = 0
    private var funnelDeadline = Date.distantPast
    private(set) var sharing: Bool
    private(set) var clipped = 0

    init(cloudURL: String, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         session: URLSession? = nil) {
        self.defaults = defaults; self.now = now
        if let choice = defaults.object(forKey: "analytics.sharing") {
            sharing = (choice as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue } ?? false
        } else { sharing = true }
        var parts = URLComponents(string: cloudURL)
        if let host = parts?.host, host.hasSuffix(".convex.cloud"), parts?.scheme == "https" {
            parts?.host = String(host.dropLast(".convex.cloud".count)) + ".convex.site"
            parts?.path = "/analytics/summary"; parts?.query = nil; parts?.fragment = nil
            parts?.user = nil; parts?.password = nil; endpoint = parts?.url
        } else { endpoint = nil }
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil; config.urlCache = nil; config.httpShouldSetCookies = false
            config.timeoutIntervalForRequest = 3; config.timeoutIntervalForResource = 4
            self.session = URLSession(configuration: config, delegate: AnalyticsNoRedirect(), delegateQueue: nil)
        }
        let currentHour = Int(now().timeIntervalSince1970 / 3600)
        if sharing, let data = defaults.data(forKey: "analytics.counts.v1"), data.count <= 16_384,
           let restored = try? JSONDecoder().decode(State.self, from: data),
           (0...40).contains(restored.admitted), restored.day >= 0, (0...currentHour).contains(restored.hour),
           restored.pending.count <= 3,
           restored.pending.allSatisfy({ (0...3).contains($0.attempts) && $0.summary.hour <= currentHour }),
           restored.counts.keys.allSatisfy({ AnalyticsMetric(rawValue: $0) != nil }),
           restored.counts.values.allSatisfy({ (1...40).contains($0) }),
           restored.counts.values.reduce(0, +) <= 40 { state = restored }
        expire()
    }
    func setSharing(_ enabled: Bool) {
        sharing = enabled; defaults.set(enabled, forKey: "analytics.sharing")
        clearPending()
    }
    func clearPending() {
        revision += 1; task?.cancel(); task = nil
        state.counts = [:]; state.pending = []
        onboardingInProgress = false; awaitingFirstReader = false
        firstReaderDeadline = nil
        funnelStage = -1; paywallStage = -1; recoveryDeadlines = [:]
        defaults.removeObject(forKey: "analytics.counts.v1")
    }
    func record(_ metric: AnalyticsMetric) {
        guard sharing else { return }
        let recoveryPairs: [(AnalyticsMetric, AnalyticsMetric, Set<AnalyticsMetric>, AnalyticsMetric)] = [
            (.offlineActivationResultFailed, .recoverableErrorOffline, [.offlineActivationResultActivated, .offlineActivationResultUpdated], .recoverableErrorOfflineRecovered),
            (.translationResultFailed, .recoverableErrorTranslation, [.translationResultCache, .translationResultGenerated], .recoverableErrorTranslationRecovered),
            (.onboardingStepAuthFailed, .recoverableErrorAuthentication, [.onboardingCompletedAccountNew, .onboardingCompletedAccountExisting, .onboardingCompletedAccountUnknown], .recoverableErrorAuthenticationRecovered),
            (.purchaseResultFailed, .recoverableErrorPurchase, [.purchaseResultConfirmed, .purchaseResultRestoreConfirmed], .recoverableErrorPurchaseRecovered)
        ]
        for (failure, error, successes, recovered) in recoveryPairs {
            if metric == failure || failure == .purchaseResultFailed && metric == .purchaseResultRestoreFailed {
                add(error, hour: Int(now().timeIntervalSince1970 / 3600)); if state.admitted < 40 { recoveryDeadlines[error] = now().addingTimeInterval(1800) }
            } else if successes.contains(metric), let deadline = recoveryDeadlines.removeValue(forKey: error), now() <= deadline {
                add(recovered, hour: Int(now().timeIntervalSince1970 / 3600))
            } else if metric == recovered { recoveryDeadlines.removeValue(forKey: error) }
        }
        let paywallStages: Set<AnalyticsMetric> = [.paywallResultShown, .paywallResultAvailable, .paywallResultPurchaseStarted, .paywallResultConfirmed, .paywallResultDismissed]
        if paywallStages.contains(metric) {
            if metric == .paywallResultShown, paywallStage == -1 || paywallStage == 3 || now() > paywallDeadline {
                paywallStage = 0; paywallHour = Int(now().timeIntervalSince1970 / 3600)
                paywallDeadline = now().addingTimeInterval(1800); add(metric, hour: paywallHour)
            } else if now() <= paywallDeadline {
                switch metric {
                case .paywallResultAvailable where paywallStage == 0: paywallStage = 1; add(metric, hour: paywallHour)
                case .paywallResultPurchaseStarted where paywallStage == 1: paywallStage = 2; add(metric, hour: paywallHour)
                case .paywallResultConfirmed where paywallStage == 2: paywallStage = 3; add(metric, hour: paywallHour)
                case .paywallResultDismissed where (0...2).contains(paywallStage): paywallStage = -1; add(metric, hour: paywallHour)
                default: break
                }
            }
            return
        }
        let stepViews: Set<AnalyticsMetric> = [.onboardingStepWelcomeViewed, .onboardingStepLanguageViewed, .onboardingStepDemoViewed, .onboardingStepEntryViewed]
        if !stepViews.contains(metric) { add(metric, hour: Int(now().timeIntervalSince1970 / 3600)) }
        if metric == .onboardingStepWelcomeViewed, funnelStage == -1 {
            funnelStage = 0; funnelHour = Int(now().timeIntervalSince1970 / 3600)
            funnelDeadline = now().addingTimeInterval(1800); add(.onboardingStepOrderedStarted, hour: funnelHour)
        }
        guard now() <= funnelDeadline else { return }
        switch metric {
        case .onboardingStepLanguageViewed where funnelStage == 0:
            funnelStage = 1; add(.onboardingStepOrderedLanguage, hour: funnelHour)
        case .onboardingStepDemoViewed where funnelStage == 1:
            funnelStage = 2; add(.onboardingStepOrderedDemo, hour: funnelHour)
        case .onboardingStepEntryViewed where funnelStage == 2:
            funnelStage = 3; add(.onboardingStepOrderedEntry, hour: funnelHour)
        case .onboardingCompletedGuest, .onboardingCompletedAccountNew, .onboardingCompletedAccountExisting:
            if funnelStage == 3 { funnelStage = 4; add(.onboardingStepOrderedCompleted, hour: funnelHour) }
        case .onboardingCompletedFirstReaderSuccess where funnelStage == 4:
            funnelStage = 5; add(.onboardingStepOrderedFirstReader, hour: funnelHour)
        default: break
        }
    }
    private func add(_ metric: AnalyticsMetric, hour: Int) {
        guard sharing else { return }; expire()
        guard state.admitted < 39 else {
            clipped += 1; funnelStage = -2; paywallStage = -2; recoveryDeadlines = [:]
            if state.admitted == 39 {
                state.admitted = 40
                if state.counts.isEmpty { state.hour = hour }
                state.counts[AnalyticsMetric.recoverableErrorMeasurementClipped.rawValue, default: 0] += 1; persist()
            }
            return
        }
        if !state.counts.isEmpty, state.hour != hour {
            freezeCounters()
            if !state.counts.isEmpty { clipped += 1; return }
        }
        state.admitted += 1
        if state.counts.isEmpty { state.hour = hour }
        state.counts[metric.rawValue, default: 0] += 1; persist()
    }
    func startOnboarding() { if sharing { onboardingInProgress = true } }
    func completeOnboarding(_ metric: AnalyticsMetric) {
        record(metric); awaitingFirstReader = onboardingInProgress; onboardingInProgress = false
        firstReaderDeadline = now().addingTimeInterval(1800); flush()
    }
    func firstReaderSucceeded() {
        if awaitingFirstReader, let deadline = firstReaderDeadline, now() <= deadline {
            record(.onboardingCompletedFirstReaderSuccess)
        }
        awaitingFirstReader = false
        flush()
    }
    func flush() {
        expire(); guard sharing, task == nil, let endpoint else { return }
        freezeCounters()
        guard var pending = state.pending.first, pending.attempts < 3,
              let body = try? JSONEncoder().encode(pending.summary), body.count <= 4096 else { return }
        pending.attempts += 1; state.pending[0] = pending; persist()
        let capturedRevision = revision
        task = Task { [weak self] in
            guard let self else { return }
            if pending.attempts > 1 { try? await Task.sleep(for: .seconds(Double(pending.attempts * 5) + Double.random(in: 0...2))) }
            guard !Task.isCancelled, revision == capturedRevision, sharing else { return }
            expire()
            guard state.pending.first?.summary.batchId == pending.summary.batchId else { task = nil; flush(); return }
            var request = URLRequest(url: endpoint); request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = body
            var status = 0
            do { let (_, response) = try await session.data(for: request); status = (response as? HTTPURLResponse)?.statusCode ?? 0 } catch {}
            guard revision == capturedRevision, sharing else { return }
            task = nil
            guard state.pending.first?.summary.batchId == pending.summary.batchId else { flush(); return }
            if status == 204 || (400..<500).contains(status) && status != 429 || pending.attempts == 3 { state.pending.removeFirst() }
            persist()
            if !state.pending.isEmpty || !state.counts.isEmpty { flush() }
        }
    }
    private func freezeCounters() {
        while state.pending.count < 3, !state.counts.isEmpty {
            let keys = state.counts.keys.sorted().prefix(32)
            var budget = 40
            let counters = keys.compactMap { key -> AnalyticsCounter? in
                guard budget > 0 else { return nil }
                guard let metric = AnalyticsMetric(rawValue: key), let count = state.counts.removeValue(forKey: key) else { return nil }
                let accepted = min(count, budget); budget -= accepted
                if count > accepted { state.counts[key] = count - accepted }
                return AnalyticsCounter(metric: metric, count: accepted)
            }
            guard !counters.isEmpty else { state.counts = [:]; return }
            state.pending.append(Pending(summary: AnalyticsSummary(version: 1, platform: "ios",
                batchId: UUID().uuidString.lowercased(), hour: state.hour, counters: counters), attempts: 0))
        }
    }
    private func expire() {
        let hour = Int(now().timeIntervalSince1970 / 3600), day = hour / 24
        if state.hour + 24 <= hour || state.hour > hour { state.counts = [:] }
        state.pending.removeAll { $0.summary.hour + 24 <= hour || $0.summary.hour > hour || $0.attempts >= 3 && task == nil }
        if state.day != day {
            freezeCounters()
            if !state.counts.isEmpty { clipped += state.counts.values.reduce(0, +); state.counts = [:] }
            state.day = day; state.admitted = 0
        }
        if !sharing { state.counts = [:]; state.pending = []; defaults.removeObject(forKey: "analytics.counts.v1") }
        persist()
    }
    private func persist() {
        if sharing, let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: "analytics.counts.v1") }
    }
}

private final class AnalyticsNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
