import Foundation

@MainActor
final class PurchaseOperationQueue {
    private var tail: Task<Void, Never>?

    func run<Result>(_ operation: @escaping @MainActor () async -> Result) async -> Result {
        let previous = tail
        let next = Task { await previous?.value; return await operation() }
        tail = Task { _ = await next.value }
        return await next.value
    }
}
