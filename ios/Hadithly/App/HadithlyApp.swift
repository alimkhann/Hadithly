import SwiftUI
import ClerkKit

@main
struct HadithlyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment()

    var body: some Scene {
        let uiLocale = environment.preferences.preferences.uiLocale
        WindowGroup {
            RootView()
                .environment(environment)
                .environment(environment.guestData)
                .environment(environment.library)
                .environment(environment.push)
                .environment(Clerk.shared)
                .environment(\.locale, Locale(identifier: uiLocale))
                .environment(
                    \.layoutDirection,
                    LocaleFallback.isRTL(uiLocale) ? .rightToLeft : .leftToRight
                )
                .preferredColorScheme(.dark)
        }
    }
}
