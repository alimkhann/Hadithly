import Foundation
import ConvexMobile
import ClerkConvex
import ClerkKit

/// Reads deployment configuration from Info.plist (populated via Secrets.xcconfig).
struct AppConfig {
    let convexURL: String
    let clerkPublishableKey: String

    init(infoDictionary: [String: Any]? = Bundle.main.infoDictionary) {
        let info = infoDictionary ?? [:]
        guard
            let convexURL = info["ConvexURL"] as? String,
            !convexURL.isEmpty,
            let clerkPublishableKey = info["ClerkPublishableKey"] as? String,
            !clerkPublishableKey.isEmpty
        else {
            fatalError(
                "Missing ConvexURL or ClerkPublishableKey in Info.plist. "
                    + "Copy ios/Secrets.xcconfig.example to ios/Secrets.xcconfig."
            )
        }
        self.convexURL = convexURL
        self.clerkPublishableKey = clerkPublishableKey
    }
}

/// Process-wide dependency container.
/// Owns the Clerk-configured Convex client; views observe auth through `Clerk.shared`.
@MainActor
@Observable
final class AppEnvironment {
    let config: AppConfig
    let convex: ConvexClientWithAuth<String>

    init(config: AppConfig = AppConfig()) {
        self.config = config
        Clerk.configure(publishableKey: config.clerkPublishableKey)
        self.convex = ConvexClientWithAuth(
            deploymentUrl: config.convexURL,
            authProvider: ClerkConvexAuthProvider()
        )
    }
}
