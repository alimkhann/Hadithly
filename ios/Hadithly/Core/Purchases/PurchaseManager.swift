import Foundation
import Observation
import RevenueCat

/// RevenueCat lifecycle and purchase state. The SDK is configured once at
/// launch, then associated with the verified Clerk user after sign-in.
@MainActor
@Observable
final class PurchaseManager {
    private(set) var packages: [Package] = []
    private(set) var isConfigured = false
    private(set) var isLoading = false
    private(set) var isPurchasing = false
    private(set) var hasProEntitlement = false
    private(set) var errorMessage: String?

    init(apiKey: String) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmed.isEmpty,
            !trimmed.localizedCaseInsensitiveContains("placeholder"),
            !trimmed.localizedCaseInsensitiveContains("your_"),
            !trimmed.lowercased().hasPrefix("test_")
        else { return }

        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        #endif
        Purchases.configure(withAPIKey: trimmed)
        isConfigured = true
    }

    func logIn(appUserID: String) async {
        guard isConfigured else { return }
        let result: (CustomerInfo?, Error?) = await withCheckedContinuation { continuation in
            Purchases.shared.logIn(appUserID) { customerInfo, _, error in
                continuation.resume(returning: (customerInfo, error))
            }
        }
        apply(customerInfo: result.0)
        if let error = result.1 { errorMessage = error.localizedDescription }
    }

    func logOut() async {
        guard isConfigured, !Purchases.shared.isAnonymous else { return }
        let result: (CustomerInfo?, Error?) = await withCheckedContinuation { continuation in
            Purchases.shared.logOut { customerInfo, error in
                continuation.resume(returning: (customerInfo, error))
            }
        }
        apply(customerInfo: result.0)
        if let error = result.1 { errorMessage = error.localizedDescription }
    }

    func loadOffering() async {
        guard isConfigured else {
            errorMessage = "Subscriptions are not configured for this build."
            return
        }
        isLoading = true
        errorMessage = nil
        let result: (Offerings?, Error?) = await withCheckedContinuation { continuation in
            Purchases.shared.getOfferings { offerings, error in
                continuation.resume(returning: (offerings, error))
            }
        }
        isLoading = false
        packages = Self.sortedPackages(result.0?.current?.availablePackages ?? [])
        if packages.isEmpty, result.1 == nil {
            errorMessage = "No subscription plans are available right now."
        } else if let error = result.1 {
            errorMessage = error.localizedDescription
        }
    }

    func purchase(_ package: Package) async -> Bool {
        guard isConfigured else { return false }
        isPurchasing = true
        errorMessage = nil
        let result: (CustomerInfo?, Error?, Bool) = await withCheckedContinuation { continuation in
            Purchases.shared.purchase(package: package) { _, customerInfo, error, userCancelled in
                continuation.resume(returning: (customerInfo, error, userCancelled))
            }
        }
        isPurchasing = false
        apply(customerInfo: result.0)
        if let error = result.1, !result.2 { errorMessage = error.localizedDescription }
        return hasProEntitlement
    }

    func restore() async -> Bool {
        guard isConfigured else { return false }
        isPurchasing = true
        errorMessage = nil
        let result: (CustomerInfo?, Error?) = await withCheckedContinuation { continuation in
            Purchases.shared.restorePurchases { customerInfo, error in
                continuation.resume(returning: (customerInfo, error))
            }
        }
        isPurchasing = false
        apply(customerInfo: result.0)
        if let error = result.1 { errorMessage = error.localizedDescription }
        return hasProEntitlement
    }

    private func apply(customerInfo: CustomerInfo?) {
        guard let customerInfo else { return }
        hasProEntitlement = customerInfo.entitlements["pro"]?.isActive == true
    }

    private static func sortedPackages(_ packages: [Package]) -> [Package] {
        let priority: [PackageType: Int] = [.annual: 0, .sixMonth: 1, .threeMonth: 2, .twoMonth: 3, .monthly: 4, .weekly: 5]
        return packages.sorted {
            (priority[$0.packageType] ?? 99) < (priority[$1.packageType] ?? 99)
        }
    }
}
