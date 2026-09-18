import Foundation

/// Pool-independent reachability probe. The reader and the download manager
/// must decide within seconds whether the backend is reachable — but on a
/// stalled network every in-flight Convex call can pin a cooperative-pool
/// thread, and a 6-thread iPhone pool can wedge so thoroughly that even
/// Swift task-group timeouts never fire (proven on-device; the simulator's
/// bigger pool always survived). URLSession runs on its own threads with
/// real socket timeouts, so this probe answers in bounded time no matter
/// how wedged Swift concurrency is.
///
/// Any HTTP response — even a 404 — counts as reachable; only transport
/// failure or timeout counts as unreachable. Results are cached briefly so
/// rapid page turns don't pay a round trip each.
actor OfflineProbe {
    static let shared = OfflineProbe()

    private static let probeTimeout = 3.0
    private static let cacheTTL = 30.0

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = probeTimeout
        config.timeoutIntervalForResource = probeTimeout
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private var lastCheck = Date.distantPast
    private var lastResult = false

    func isReachable(_ baseURL: URL) async -> Bool {
        if Date.now.timeIntervalSince(lastCheck) < Self.cacheTTL {
            return lastResult
        }
        let result = await probe(baseURL)
        lastCheck = .now
        lastResult = result
        return result
    }

    private func probe(_ baseURL: URL) async -> Bool {
        do {
            let (_, response) = try await Self.session.data(from: baseURL)
            return response is HTTPURLResponse
        } catch {
            return false
        }
    }

    /// Test support: forget the cached verdict.
    func reset() {
        lastCheck = .distantPast
    }
}
