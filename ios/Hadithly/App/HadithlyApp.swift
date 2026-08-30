import SwiftUI
import ClerkKit

@main
struct HadithlyApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .environment(environment.guestData)
                .environment(Clerk.shared)
                .preferredColorScheme(.dark)
        }
    }
}
