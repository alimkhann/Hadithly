import Foundation
public enum LogLevel { case warn }
public enum PackageType { case monthly, annual, weekly }
public struct StoreProduct { public var productIdentifier: String; public init(_ id: String) { productIdentifier = id } }
public struct Package { public var identifier: String; public var packageType: PackageType; public var storeProduct: StoreProduct; public init(_ id: String, _ type: PackageType, _ product: String) { identifier = id; packageType = type; storeProduct = StoreProduct(product) } }
public struct CustomerInfo { public var activeSubscriptions: Set<String> = []; public init() {} }
public struct Offering { public var availablePackages: [Package]; public init(_ packages: [Package]) { availablePackages = packages } }
public struct Offerings { public var current: Offering?; public init(_ packages: [Package]) { current = Offering(packages) } }
public final class Purchases {
 public static let shared = Purchases(); public static var logLevel = LogLevel.warn
 public static func configure(withAPIKey: String, appUserID: String? = nil) { if let appUserID { shared.currentID = appUserID } }
 public var currentID = "anonymous"; public var isAnonymous: Bool { currentID == "anonymous" }
 public var offeringCallback: ((Offerings?, Error?) -> Void)?
 public var purchaseCallback: ((String?, CustomerInfo?, Error?, Bool) -> Void)?
 public var loginCalls: [String] = []
 public func logIn(_ id: String, completion: (CustomerInfo?, Bool, Error?) -> Void) { currentID = id; loginCalls.append(id); completion(CustomerInfo(), false, nil) }
 public func logOut(completion: (CustomerInfo?, Error?) -> Void) { currentID = "anonymous"; completion(CustomerInfo(), nil) }
 public func getOfferings(completion: @escaping (Offerings?, Error?) -> Void) { offeringCallback = completion }
 public func purchase(package: Package, completion: @escaping (String?, CustomerInfo?, Error?, Bool) -> Void) { purchaseCallback = completion }
 public func restorePurchases(completion: (CustomerInfo?, Error?) -> Void) { completion(CustomerInfo(), nil) }
}
