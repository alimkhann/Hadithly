import Foundation

/// Progress + completion surface for one file download. The store drives
/// state; this type only moves bytes into a `.tmp` file.
protocol OfflineDownloadTask: Sendable {
    func cancelProducingResume() async -> Data?
}

/// Injectable download transport. Production uses URLSession; tests use a
/// file-backed fake. Signed Convex storage URLs are short-lived, so resume
/// re-fetches a fresh manifest URL and continues from the persisted byte
/// offset where the server honors `Range`.
protocol OfflineDownloadTransport: Sendable {
    func download(
        from url: URL,
        resumingFrom offset: Int64,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> Data
    func cancel() async
    /// HTTP status of the last completed response (200 full, 206 partial).
    /// The store appends to a partial file only on 206; a 200 after a
    /// `Range` request means the server ignored it, so the file restarts.
    func lastStatusCode() async -> Int
}

enum OfflineDownloadError: Error, Equatable {
    case noData
    case httpStatus(Int)
    case cancelled
}

/// Foreground URLSession transport. iOS suspends work in the background:
/// the task reports cancellation, the store keeps the partial `.tmp` plus
/// its byte offset, and the download resumes on the next foreground run.
/// Nothing partial is ever verified or activated.
actor URLSessionOfflineTransport: OfflineDownloadTransport {
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<Data, Error>?
    private var progressHandler: (@Sendable (Double) -> Void)?
    private var resumedOffset: Int64 = 0
    private var statusCode: Int = 0

    func lastStatusCode() async -> Int { statusCode }

    func download(
        from url: URL,
        resumingFrom offset: Int64,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> Data {
        cancelTask()
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            self.continuation = cont
            self.progressHandler = progress
            self.resumedOffset = offset
            var request = URLRequest(url: url)
            if offset > 0 {
                request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
            }
            let delegate = OfflineDownloadDelegate(transport: self)
            let sessionWithDelegate = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            self.task = sessionWithDelegate.downloadTask(with: request)
            self.task?.resume()
        }
    }

    func cancel() async {
        cancelTask(error: OfflineDownloadError.cancelled)
    }

    fileprivate func setStatus(_ code: Int) {
        statusCode = code
    }

    private func cancelTask(error: Error? = nil) {
        task?.cancel()
        task = nil
        if let error, let cont = continuation {
            continuation = nil
            cont.resume(throwing: error)
        }
    }

    fileprivate func finish(progress: Double) {
        progressHandler?(progress)
    }

    fileprivate func complete(url: URL?) {
        guard let cont = continuation else { return }
        continuation = nil
        task = nil
        guard let url, let data = try? Data(contentsOf: url) else {
            cont.resume(throwing: OfflineDownloadError.noData)
            return
        }
        cont.resume(returning: data)
    }

    fileprivate func fail(_ error: Error) {
        guard let cont = continuation else { return }
        continuation = nil
        task = nil
        cont.resume(throwing: error)
    }
}

private final class OfflineDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var transport: URLSessionOfflineTransport?

    init(transport: URLSessionOfflineTransport) {
        self.transport = transport
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { await transport?.finish(progress: fraction) }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        Task { await transport?.complete(url: location) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let status = (task.response as? HTTPURLResponse)?.statusCode {
            Task { await transport?.setStatus(status) }
        }
        if let error {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                Task { await transport?.fail(OfflineDownloadError.cancelled) }
            } else {
                Task { await transport?.fail(error) }
            }
        } else if let response = task.response as? HTTPURLResponse, !(200 ... 299).contains(response.statusCode) {
            Task { await transport?.fail(OfflineDownloadError.httpStatus(response.statusCode)) }
        }
    }
}
