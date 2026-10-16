import Foundation
import Sentry

enum DiagnosticFailure: String {
    case offlineManifest = "offline_manifest"
    case synthetic
}

final class CrashReporting {
    static let shared = CrashReporting()
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var running = false
    private let cache: URL

    init(defaults: UserDefaults = .standard, cache: URL? = nil) {
        self.defaults = defaults
        self.cache = cache ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("HadithlyDiagnostics")
    }
    var hasConsent: Bool { defaults.bool(forKey: "diagnostics.consent") }

    func startIfConsented(dsnOverride: String? = nil, session: URLSession? = nil) {
        guard hasConsent else { purge(); return }
        guard !running,
              let dsn = dsnOverride ?? Bundle.main.object(forInfoDictionaryKey: "DiagnosticsDSN") as? String,
              dsn.hasPrefix("https://"), !dsn.contains("PLACEHOLDER") else { return }
        purgeExpired()
        running = true
        let cachePath = cache.path
        SentrySDK.start { [weak self] options in
            options.dsn = dsn
            options.urlSession = session
            options.releaseName = DiagnosticsRelease.value
            options.environment = Self.environment
            options.cacheDirectoryPath = cachePath
            options.maxCacheItems = 10
            options.shutdownTimeInterval = 0
            options.sendDefaultPii = false
            options.enableMemoryIntrospection = false
            options.enableAutoSessionTracking = false
            options.enableAutoBreadcrumbTracking = false
            options.enableCaptureFailedRequests = false
            options.enableSwizzling = false
            options.enableAppHangTracking = false
            options.enableWatchdogTerminationTracking = false
            options.enableMetricKit = false
            options.enableMetricKitRawPayload = false
            options.enableLogs = false
            options.enableMetrics = false
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            options.attachAllThreads = false
            options.sendClientReports = false
            options.tracesSampleRate = 0
            options.sessionReplay.sessionSampleRate = 0
            options.sessionReplay.onErrorSampleRate = 0
            options.maxBreadcrumbs = 0
            options.beforeBreadcrumb = { _ in nil }
            installSentryPrivacyFilter(options: options) { [weak self] event, hint in
                hint.attachments = []
                guard let self, self.hasConsent, self.admit() else { return nil }
                let safe = Self.redactedPreservingCapture(event)
                let allowed: Set<String> = ["event_id", "timestamp", "level", "platform", "release", "environment", "dist", "tags", "exception", "stacktrace", "threads", "debug_meta"]
                guard Set(safe.serialize().keys).isSubset(of: allowed) else { return nil }
                return safe
            }
        }
    }

    func setConsent(_ enabled: Bool) {
        defaults.set(enabled, forKey: "diagnostics.consent")
        defaults.synchronize()
        if enabled { startIfConsented() }
        else {
            SentrySDK.close(); running = false; purge()
        }
    }

    func failure(_ failure: DiagnosticFailure) {
        guard hasConsent, running else { return }
        let event = Event(level: .error)
        event.exceptions = [Exception(value: failure.rawValue, type: "HadithlyFailure")]
        event.tags = ["operation": failure.rawValue]
        SentrySDK.capture(event: event)
    }

    private func admit() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let day = Int(Date().timeIntervalSince1970 / 86400)
        if defaults.integer(forKey: "diagnostics.day") != day {
            defaults.set(day, forKey: "diagnostics.day")
            defaults.set(0, forKey: "diagnostics.count")
        }
        let count = defaults.integer(forKey: "diagnostics.count")
        guard count < 5 else { return false }
        defaults.set(count + 1, forKey: "diagnostics.count")
        return true
    }

    private func purge() { try? FileManager.default.removeItem(at: cache) }
    private func purgeExpired() {
        guard let files = FileManager.default.enumerator(at: cache, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for case let file as URL in files {
            if let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               Date().timeIntervalSince(date) > 7 * 86400 { try? FileManager.default.removeItem(at: file) }
        }
    }

    static var environment: String {
        Bundle.main.object(forInfoDictionaryKey: "DiagnosticsEnvironment") as? String == "production" ? "production" : "development"
    }

    static func redacted(_ source: Event) -> Event {
        let result = Event(level: source.level == .fatal ? .fatal : .error)
        result.eventId = source.eventId
        result.timestamp = source.timestamp
        result.platform = "cocoa"
        result.releaseName = source.releaseName?.range(of: "^hadithly@[a-f0-9]{12}$", options: .regularExpression) != nil ? source.releaseName : DiagnosticsRelease.value
        result.environment = ["development", "production"].contains(source.environment ?? "") ? source.environment : environment
        result.dist = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let operation = source.tags?["operation"] == "synthetic" ? "synthetic" : source.tags?["operation"] == "offline_manifest" ? "offline_manifest" : "native_crash"
        result.tags = ["surface": "ios", "operation": operation]
        result.exceptions = (source.exceptions ?? []).prefix(4).map { original in
            let exception = Exception(value: operation, type: "HadithlyNativeFailure")
            let mechanism = Mechanism(type: "generic")
            mechanism.handled = original.mechanism?.handled ?? NSNumber(value: source.level != .fatal)
            exception.mechanism = mechanism
            exception.stacktrace = stack(original.stacktrace)
            return exception
        }
        result.stacktrace = stack(source.stacktrace)
        result.threads = source.threads?.prefix(32).map { original in
            let thread = SentryThread(threadId: original.threadId)
            thread.crashed = original.crashed
            thread.stacktrace = stack(original.stacktrace)
            return thread
        }
        result.debugMeta = source.debugMeta?.prefix(256).compactMap { original in
            guard let id = original.debugID, UUID(uuidString: id) != nil,
                  let address = hex(original.imageAddress) else { return nil }
            let image = DebugMeta()
            image.debugID = id; image.type = "macho"; image.imageAddress = address
            image.imageSize = original.imageSize
            image.imageVmAddress = hex(original.imageVmAddress)
            image.codeFile = "binary"
            return image
        }
        return result
    }

    static func redactedPreservingCapture(_ source: Event) -> Event {
        let clean = redacted(source)
        source.message = nil; source.error = nil; source.startTimestamp = nil
        source.logger = nil; source.serverName = nil; source.transaction = nil; source.type = nil
        source.extra = nil; source.sdk = nil; source.modules = nil; source.fingerprint = nil
        source.user = nil; source.context = nil; source.breadcrumbs = nil; source.request = nil
        source.platform = clean.platform; source.level = clean.level
        source.releaseName = clean.releaseName; source.environment = clean.environment; source.dist = clean.dist
        source.tags = clean.tags; source.exceptions = clean.exceptions; source.threads = clean.threads
        source.stacktrace = clean.stacktrace; source.debugMeta = clean.debugMeta
        return source
    }

    private static func hex(_ value: String?) -> String? {
        guard let value, value.range(of: "^0x[0-9a-fA-F]{1,16}$", options: .regularExpression) != nil else { return nil }
        return value
    }
    private static func stack(_ source: SentryStacktrace?) -> SentryStacktrace? {
        guard let source else { return nil }
        let frames = source.frames.suffix(128).map { original in
            let frame = Frame()
            frame.instructionAddress = hex(original.instructionAddress)
            frame.imageAddress = hex(original.imageAddress)
            frame.symbolAddress = hex(original.symbolAddress)
            frame.inApp = original.inApp
            return frame
        }
        return SentryStacktrace(frames: frames, registers: [:])
    }
}

