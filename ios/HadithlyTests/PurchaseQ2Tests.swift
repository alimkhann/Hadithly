import XCTest
@testable import Hadithly

final class PurchaseQ2Tests: XCTestCase {
    func testIdentifiedAccountRequiredAndLateCallbacksCannotCrossAccounts() {
        var gate = PurchaseAccountGate()
        let a = gate.bind("account-a")
        XCTAssertFalse(gate.accepts(a, currentAccountID: "account-a"))
        gate.identified(a)
        XCTAssertTrue(gate.accepts(a, currentAccountID: "account-a"))
        XCTAssertFalse(gate.accepts(a, currentAccountID: "account-b"))
        let b = gate.bind("account-b")
        gate.identified(a)
        XCTAssertFalse(gate.accepts(a, currentAccountID: "account-b"))
        XCTAssertFalse(gate.accepts(b, currentAccountID: "account-b"))
        gate.identified(b)
        XCTAssertTrue(gate.accepts(b, currentAccountID: "account-b"))
        _ = gate.bind(nil)
        XCTAssertFalse(gate.accepts(b, currentAccountID: nil))
    }

    func testPendingPurchaseSurvivesRelaunchAndCannotBeClearedByAnotherAccount() throws {
        let name = "q2-pending-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let first = PendingPurchaseStore(defaults: defaults)
        XCTAssertTrue(first.begin(ownerID: "original", productID: "monthly", kind: .purchase))
        let relaunched = PendingPurchaseStore(defaults: defaults)
        XCTAssertEqual(relaunched.pending?.ownerID, "original")
        XCTAssertTrue(relaunched.blocks("another"))
        XCTAssertFalse(relaunched.begin(ownerID: "another", productID: "monthly", kind: .purchase))
        relaunched.clear(ownerID: "another")
        XCTAssertNotNil(relaunched.pending)
        XCTAssertTrue(relaunched.begin(ownerID: "original", productID: nil, kind: .restore))
        XCTAssertEqual(relaunched.pending?.productID, "monthly")
        XCTAssertFalse(relaunched.begin(ownerID: "original", productID: "annual", kind: .purchase))
        relaunched.clear(ownerID: "original")
        XCTAssertNil(relaunched.pending)
        defaults.set(Data("corrupt".utf8), forKey: "hadithly.pendingPurchase.v1")
        XCTAssertTrue(relaunched.unreadable)
        XCTAssertTrue(relaunched.blocks("original"))
    }

    @MainActor
    func testOnlyRegisteredMonthlyAndAnnualProductsAreAccepted() {
        XCTAssertTrue(PurchaseManager.allowedProduct("com.hadithly.app.pro.monthly", annual: false))
        XCTAssertTrue(PurchaseManager.allowedProduct("com.hadithly.app.pro.annual", annual: true))
        XCTAssertFalse(PurchaseManager.allowedProduct("com.hadithly.app.pro.weekly", annual: false))
        XCTAssertFalse(PurchaseManager.allowedProduct("accidental_pro_monthly", annual: false))
        XCTAssertFalse(PurchaseManager.allowedProduct("com.hadithly.app.pro.annual", annual: false))
    }

    @MainActor
    func testUnconfiguredRestoreTerminatesWithoutUnlockingOrLeavingSpinner() async {
        let manager = PurchaseManager(apiKey: "")
        let restored = await manager.restore()
        XCTAssertFalse(restored)
        XCTAssertFalse(manager.isPurchasing)
        XCTAssertFalse(manager.hasProEntitlement)
        XCTAssertNotNil(manager.errorMessage)
    }
}
