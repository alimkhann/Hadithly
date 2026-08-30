import SwiftUI
import ClerkKit

@main
struct HadithlyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .environment(environment.guestData)
                .environment(environment.library)
                .environment(environment.push)
                .environment(Clerk.shared)
                .preferredColorScheme(.dark)
        }
    }
}
