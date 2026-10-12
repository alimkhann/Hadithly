import ClerkKit
import ConvexMobile
import RevenueCat
import StoreKit
import XCTest
@testable import Hadithly

final class PurchaseQ2LiveTests: XCTestCase {
    private struct Status: Decodable { let subscriptionTier: String; let store: String? }
    private struct Allowance: Decodable { let limit: Double }

    @MainActor
    func testRegisteredAppleProductsAreAvailable() async throws {
        guard ProcessInfo.processInfo.environment["Q2_LIVE_STORE_READ"] == "1" else { throw XCTSkip("Opt-in real Apple product availability read") }
        XCTAssertTrue(AppConfig().convexURL.contains("festive-cobra-664"))
        let ids = ["com.hadithly.app.pro.monthly", "com.hadithly.app.pro.annual"]
        let products = try await Product.products(for: ids)
        XCTAssertEqual(products.map(\.id).sorted(), ids.sorted(), "Both actual Apple products must resolve without a StoreKit configuration file")
        for product in products {
            XCTAssertEqual(product.type, .autoRenewable)
            XCTAssertGreaterThan(product.price, 0)
            print("Q2 real Apple product: \(product.id), \(product.displayPrice)")
        }
    }

    @MainActor
    func testRealAppleOfferingLoadsForVerifiedHadithlyAccount() async throws {
        guard ProcessInfo.processInfo.environment["Q2_LIVE_STORE_READ"] == "1" else { throw XCTSkip("Opt-in Apple StoreKit/RevenueCat read") }
        for _ in 0..<200 { if Clerk.shared.isLoaded { break }; try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertNotNil(Clerk.shared.session, "An existing signed-in Hadithly development account is required")
        guard Clerk.shared.session != nil, let environment = AppEnvironment.activeForStoreVerification else { return }
        XCTAssertTrue(environment.config.convexURL.contains("festive-cobra-664"))
        await environment.completeSignIn()
        await environment.purchases.loadOffering()
        XCTAssertTrue(environment.purchases.isConfigured)
        XCTAssertEqual(environment.purchases.packages.count, 2, "Real store plans must load; no test-store substitutes")
        for package in environment.purchases.packages {
            XCTAssertTrue(PurchaseManager.allowedProduct(package.storeProduct.productIdentifier, annual: package.packageType == .annual))
            print("Q2 real StoreKit plan: \(package.storeProduct.productIdentifier), \(package.storeProduct.localizedPriceString)")
        }
        XCTAssertFalse(environment.purchases.packages.contains { $0.packageType == .weekly })
    }

    @MainActor
    func testRealAppleSandboxMonthlyPurchaseAndRestore() async throws {
        guard ProcessInfo.processInfo.environment["Q2_LIVE_STORE_PURCHASE"] == "1" else {
            throw XCTSkip("Opt-in real Apple sandbox purchase: sign in to the US sandbox tester on the device first")
        }
        for _ in 0..<200 { if Clerk.shared.isLoaded { break }; try await Task.sleep(for: .milliseconds(100)) }
        let environment = try XCTUnwrap(AppEnvironment.activeForStoreVerification)
        guard environment.config.convexURL.contains("festive-cobra-664"), Clerk.shared.session != nil else {
            XCTFail("Only the signed-in development app may run this sandbox check"); return
        }
        await environment.completeSignIn()
        await environment.purchases.loadOffering()
        let monthly = try XCTUnwrap(environment.purchases.packages.first { $0.packageType == .monthly })
        XCTAssertEqual(monthly.storeProduct.productIdentifier, "com.hadithly.app.pro.monthly")
        // The owner completes Apple's sandbox confirmation on the device.
        let purchased = await environment.purchases.purchase(monthly)
        XCTAssertTrue(purchased, "Real sandbox receipt must reconcile through RevenueCat and Convex")
        guard purchased else { return }
        let status = try await environment.convex.subscribe(to: "subscriptions:getStatus", yielding: Status.self).values.first(where: { _ in true })
        XCTAssertEqual(status?.subscriptionTier, "pro")
        XCTAssertEqual(status?.store, "app_store")
        let allowance = try await environment.convex.subscribe(to: "quotas:getTranslationAllowance", yielding: Allowance.self).values.first(where: { _ in true })
        XCTAssertEqual(allowance?.limit, 100)
        let restored = await environment.purchases.restore()
        XCTAssertTrue(restored)
        XCTAssertFalse(environment.purchases.isPurchasing)
        XCTAssertTrue(environment.purchases.hasProEntitlement)
        print("Q2 real Apple sandbox purchase, backend Pro/100 allowance and original-account restore passed")
    }
}
