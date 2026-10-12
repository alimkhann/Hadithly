import Foundation
import ClerkKit
import RevenueCat

@main struct Review {
 @MainActor static func main() async {
  let domain = "q2-transport-" + UUID().uuidString
  let defaults = UserDefaults(suiteName: domain)!
  defer { defaults.removePersistentDomain(forName: domain) }
  let manager = PurchaseManager(apiKey: "appl_test_review", pendingStore: PendingPurchaseStore(defaults: defaults))
  manager.verifyBackendAccess = { true }
  Clerk.shared.user = ClerkUser(id: "a")
  await manager.logIn(appUserID: "a")
  precondition(manager.hasProEntitlement)
  let offering = Task { await manager.loadOffering() }
  while Purchases.shared.offeringCallback == nil { await Task.yield() }
  precondition(manager.isLoading)
  Clerk.shared.user = ClerkUser(id: "b")
  await manager.logIn(appUserID: "b")
  Purchases.shared.offeringCallback?(Offerings([]), nil)
  await offering.value
  precondition(!manager.isLoading, "Old offering must not strand new account loading")
  print("PASS: old-account offering rejected and new account loading is cleared")
  Purchases.shared.offeringCallback = nil
  let currentOffering = Task { await manager.loadOffering() }
  while Purchases.shared.offeringCallback == nil { await Task.yield() }
  let package = Package("$rc_monthly", .monthly, "com.hadithly.app.pro.monthly")
  Purchases.shared.offeringCallback?(Offerings([package]), nil)
  await currentOffering.value
  let purchase = Task { await manager.purchase(package) }
  while Purchases.shared.purchaseCallback == nil { await Task.yield() }
  Clerk.shared.user = ClerkUser(id: "c")
  let loginC = Task { await manager.logIn(appUserID: "c") }
  for _ in 0..<10 { await Task.yield() }
  precondition(Purchases.shared.currentID == "b", "SDK identity must stay b until store completion")
  precondition(!manager.isPurchasing)
  Purchases.shared.purchaseCallback?("first-transaction", CustomerInfo(), nil, false)
  let unlocked = await purchase.value
  await loginC.value
  precondition(Purchases.shared.currentID == "c")
  precondition(!unlocked, "Late purchase callback must not unlock a different account")
  print("PASS: SDK login c waits until b store operation completes")
  print("PASS: real PurchaseManager rejects late b callback and never returns unlocked for c")
  manager.verifyBackendAccess = { false }
  let restored = await manager.restore()
  precondition(!restored && !manager.isPurchasing && !manager.hasProEntitlement)
  print("PASS: successful SDK restore with denied backend terminates spinner and does not unlock")
  let stored = PendingPurchaseStore(defaults: defaults)
  precondition(stored.begin(ownerID: "original", productID: "com.hadithly.app.pro.monthly", kind: .purchase))
  Purchases.shared.currentID = "anonymous"
  Clerk.shared.user = ClerkUser(id: "other")
  let restarted = PurchaseManager(apiKey: "appl_test_review", pendingStore: PendingPurchaseStore(defaults: defaults))
  await restarted.logIn(appUserID: "other")
  precondition(Purchases.shared.currentID == "original")
  precondition(!restarted.hasProEntitlement)
  precondition(restarted.errorMessage?.contains("pending for another") == true)
  stored.clear(ownerID: "original")
  let accountOnly = PurchaseManager(apiKey: "", pendingStore: stored)
  accountOnly.verifyBackendAccess = { true }
  await accountOnly.logIn(appUserID: "other")
  precondition(!accountOnly.isConfigured && accountOnly.hasProEntitlement)
  let crossPlatformRestored = await accountOnly.restore()
  precondition(crossPlatformRestored)
  print("PASS: backend-confirmed own-account Pro works without a local store SDK configuration")
  print("PASS: actual manager startup pins an unresolved first purchase to its original account and blocks a different relaunch account")

 }
}
