import Foundation

struct PurchaseAccountGate {
    private(set) var accountID: String?
    private(set) var revision = 0
    private(set) var ready = false

    mutating func bind(_ accountID: String?) -> Int {
        revision += 1
        self.accountID = accountID
        ready = false
        return revision
    }

    mutating func identified(_ revision: Int) {
        if self.revision == revision, accountID != nil { ready = true }
    }

    func accepts(_ revision: Int, currentAccountID: String?) -> Bool {
        ready && self.revision == revision && accountID != nil && accountID == currentAccountID
    }
}
