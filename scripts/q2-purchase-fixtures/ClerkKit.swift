public final class ClerkUser { public let id: String; public init(id: String) { self.id = id } }
public final class Clerk { public static let shared = Clerk(); public var user: ClerkUser?; public init() {} }
