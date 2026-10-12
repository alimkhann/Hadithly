import Foundation

struct PendingPurchase: Codable, Equatable {
    enum Kind: String, Codable { case purchase, restore }
    let ownerID: String
    let productID: String?
    let kind: Kind
}

final class PendingPurchaseStore {
    private let defaults: UserDefaults
    private let key = "hadithly.pendingPurchase.v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var pending: PendingPurchase? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let record = try? JSONDecoder().decode(PendingPurchase.self, from: data), !record.ownerID.isEmpty, record.ownerID.count <= 200,
              record.kind == .restore || record.productID?.isEmpty == false else { return nil }
        return record
    }
    var unreadable: Bool { defaults.object(forKey: key) != nil && pending == nil }
    func blocks(_ ownerID: String) -> Bool { unreadable || (pending != nil && pending?.ownerID != ownerID) }

    func begin(ownerID: String, productID: String?, kind: PendingPurchase.Kind) -> Bool {
        guard !blocks(ownerID) else { return false }
        if let pending {
            if kind == .restore { return true }
            if pending.kind == .purchase { return pending.productID == productID }
        }
        guard let data = try? JSONEncoder().encode(PendingPurchase(ownerID: ownerID, productID: productID, kind: kind)) else { return false }
        defaults.set(data, forKey: key)
        return defaults.synchronize()
    }
    func clear(ownerID: String) {
        guard pending?.ownerID == ownerID else { return }
        defaults.removeObject(forKey: key)
        _ = defaults.synchronize()
    }
}
