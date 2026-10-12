import ClerkKit
import Foundation
import Observation
import RevenueCat

@MainActor
@Observable
final class PurchaseManager {
    private(set) var packages: [Package] = []
    private(set) var isConfigured = false
    private(set) var isLoading = false
    private(set) var isPurchasing = false
    private(set) var errorMessage: String?
    var verifyBackendAccess: (() async throws -> Bool)?
    private var gate = PurchaseAccountGate()
    private var confirmedPro = false
    private let operations = PurchaseOperationQueue()
    private let pendingStore: PendingPurchaseStore

    var hasProEntitlement: Bool { confirmedPro && gate.accepts(gate.revision, currentAccountID: Clerk.shared.user?.id) }

    init(apiKey: String, pendingStore: PendingPurchaseStore = PendingPurchaseStore()) {
        self.pendingStore = pendingStore
        guard !pendingStore.unreadable else { errorMessage = "Purchase state could not be read. Contact support; reading remains available."; return }
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.localizedCaseInsensitiveContains("placeholder"),
              !trimmed.localizedCaseInsensitiveContains("your_"), !trimmed.lowercased().hasPrefix("test_") else { return }
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: trimmed, appUserID: pendingStore.pending?.ownerID)
        isConfigured = true
    }

    func clearAccount() {
        _ = gate.bind(nil)
        confirmedPro = false
        packages = []
        isPurchasing = false
        isLoading = false
        errorMessage = nil
    }

    func logIn(appUserID: String) async {
        let revision = gate.bind(appUserID)
        confirmedPro = false
        packages = []
        isPurchasing = false
        isLoading = false
        errorMessage = nil
        if !isConfigured {
            gate.identified(revision)
            if verifyBackendAccess != nil { _ = await confirmBackend(revision) }
            return
        }
        guard !pendingStore.blocks(appUserID) else {
            errorMessage = "A store operation is pending for another Hadithly account. Sign in to the account that started it, then restore."
            return
        }
        let error: Error? = await operations.run { [self] in
            guard gate.revision == revision else { return nil }
            return await withCheckedContinuation { continuation in
                Purchases.shared.logIn(appUserID) { _, _, error in continuation.resume(returning: error) }
            }
        }
        guard gate.revision == revision else { return }
        if error != nil { errorMessage = "Sign in to your original Hadithly account to use this purchase."; return }
        gate.identified(revision)
        if gate.accepts(revision, currentAccountID: Clerk.shared.user?.id) { _ = await confirmBackend(revision) }
    }

    func logOut() async {
        clearAccount()
        guard isConfigured, pendingStore.pending == nil, !pendingStore.unreadable else { return }
        await operations.run {
            guard !Purchases.shared.isAnonymous else { return }
            let _: Error? = await withCheckedContinuation { continuation in
                Purchases.shared.logOut { _, error in continuation.resume(returning: error) }
            }
        }
    }

    func loadOffering() async {
        guard isConfigured else { errorMessage = "Subscriptions are not configured for this build."; return }
        let revision = gate.revision
        guard gate.accepts(revision, currentAccountID: Clerk.shared.user?.id) else {
            errorMessage = "Sign in to your Hadithly account before purchasing or restoring."; return
        }
        isLoading = true
        errorMessage = nil
        let result: (Offerings?, Error?) = await withCheckedContinuation { continuation in
            Purchases.shared.getOfferings { offerings, error in continuation.resume(returning: (offerings, error)) }
        }
        guard gate.accepts(revision, currentAccountID: Clerk.shared.user?.id) else { return }
        isLoading = false
        packages = (result.0?.current?.availablePackages ?? []).filter { package in
            Self.allowedProduct(package.storeProduct.productIdentifier, annual: package.packageType == .annual)
                && (package.packageType == .monthly || package.packageType == .annual)
        }.sorted { $0.packageType == .annual && $1.packageType != .annual }
        if result.1 != nil { errorMessage = "Plans could not be loaded. Try again." }
        else if packages.isEmpty { errorMessage = "No subscription plans are available right now." }
    }

    static func allowedProduct(_ id: String, annual: Bool) -> Bool {
        id == (annual ? "com.hadithly.app.pro.annual" : "com.hadithly.app.pro.monthly")
    }

    func purchase(_ package: Package) async -> Bool {
        let revision = gate.revision
        guard isConfigured, !isPurchasing, gate.accepts(revision, currentAccountID: Clerk.shared.user?.id),
              packages.contains(where: { $0.identifier == package.identifier }) else { return false }
        let hadPendingOperation = pendingStore.pending != nil
        guard let ownerID = gate.accountID, pendingStore.begin(ownerID: ownerID, productID: package.storeProduct.productIdentifier, kind: .purchase) else {
            errorMessage = "Finish or restore the pending purchase with your original Hadithly account first."; return false
        }
        isPurchasing = true
        errorMessage = nil
        defer { if gate.revision == revision { isPurchasing = false } }
        let result: (CustomerInfo?, Error?, Bool, Bool) = await operations.run { [self] in
            guard gate.accepts(revision, currentAccountID: Clerk.shared.user?.id) else { return (nil, nil, false, false) }
            return await withCheckedContinuation { continuation in
                Purchases.shared.purchase(package: package) { _, info, error, cancelled in continuation.resume(returning: (info, error, cancelled, true)) }
            }
        }
        if (!hadPendingOperation && (result.2 || !result.3)) || (result.3 && result.1 == nil && result.0 != nil) { pendingStore.clear(ownerID: ownerID) }
        if !gate.accepts(revision, currentAccountID: Clerk.shared.user?.id) { await identifyAfterResolvedStoreOperation(); return false }
        if result.2 { return false }
        if result.1 != nil { errorMessage = "Purchase could not be completed. Try again."; return false }
        return await confirmBackend(revision)
    }

    func restore() async -> Bool {
        let revision = gate.revision
        if !isConfigured, gate.accepts(revision, currentAccountID: Clerk.shared.user?.id), verifyBackendAccess != nil {
            return await confirmBackend(revision)
        }
        guard isConfigured, !isPurchasing, gate.accepts(revision, currentAccountID: Clerk.shared.user?.id) else {
            errorMessage = "Sign in to your original Hadithly account before restoring."; return false
        }
        let hadPendingOperation = pendingStore.pending != nil
        guard let ownerID = gate.accountID, pendingStore.begin(ownerID: ownerID, productID: nil, kind: .restore) else { return false }
        isPurchasing = true
        errorMessage = nil
        defer { if gate.revision == revision { isPurchasing = false } }
        let result: (CustomerInfo?, Error?, Bool) = await operations.run { [self] in
            guard gate.accepts(revision, currentAccountID: Clerk.shared.user?.id) else { return (nil, nil, false) }
            return await withCheckedContinuation { continuation in
                Purchases.shared.restorePurchases { info, error in continuation.resume(returning: (info, error, true)) }
            }
        }
        if !result.2 && !hadPendingOperation { pendingStore.clear(ownerID: ownerID) }
        if result.2, result.1 == nil, let info = result.0, let pending = pendingStore.pending,
           pending.kind == .restore || (pending.productID.map { info.activeSubscriptions.contains($0) } ?? false) {
            pendingStore.clear(ownerID: ownerID)
        }
        if !gate.accepts(revision, currentAccountID: Clerk.shared.user?.id) { await identifyAfterResolvedStoreOperation(); return false }
        if result.1 != nil { errorMessage = "Restore failed. Use the original Hadithly account and store account, then try again."; return false }
        return await confirmBackend(revision)
    }

    private func identifyAfterResolvedStoreOperation() async {
        if pendingStore.pending == nil, let current = Clerk.shared.user?.id { await logIn(appUserID: current) }
    }

    private func confirmBackend(_ revision: Int) async -> Bool {
        do {
            let active = try await verifyBackendAccess?() ?? false
            guard gate.accepts(revision, currentAccountID: Clerk.shared.user?.id) else { return false }
            confirmedPro = active
            if !active { errorMessage = "No active Pro purchase was found for this Hadithly account. Use the account that purchased Pro." }
            return active
        } catch {
            guard gate.accepts(revision, currentAccountID: Clerk.shared.user?.id) else { return false }
            confirmedPro = false
            errorMessage = "Your subscription could not be checked. Try Restore purchases again shortly."
            return false
        }
    }
}
