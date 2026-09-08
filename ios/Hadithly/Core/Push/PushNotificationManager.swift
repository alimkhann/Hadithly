import ConvexMobile
import Foundation
import Observation
import UIKit
import UserNotifications

/// Registers the device for APNs and uploads the token to Convex so the
/// scheduled daily hadith send can reach this device. A singleton because
/// the UIApplicationDelegate receives the token with no view context.
@MainActor
@Observable
final class PushNotificationManager: NSObject {
    enum RegistrationState: Equatable {
        case unknown
        case notAuthorized
        case registered(String)
        case failed(String)
    }

    static let shared = PushNotificationManager()

    private(set) var state: RegistrationState = .unknown
    private(set) var authorizationGranted = false

    /// Set by AppEnvironment: uploads the token once a Convex session exists.
    /// Injected as a closure to keep this type free of app wiring.
    var uploadHandler: ((String) async -> Void)?

    private static let tokenKey = "push.deviceToken"

    private override init() {
        super.init()
        if let saved = UserDefaults.standard.string(forKey: Self.tokenKey) {
            state = .registered(saved)
        }
    }

    /// Requests notification permission and an APNs token. The token arrives
    /// asynchronously through the app delegate; the return value here only
    /// reflects authorization.
    @discardableResult
    func requestAuthorizationAndRegister() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            authorizationGranted = try await center.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
        } catch {
            state = .failed(error.localizedDescription)
            return false
        }
        guard authorizationGranted else {
            state = .notAuthorized
            return false
        }
        UIApplication.shared.registerForRemoteNotifications()
        return true
    }

    func handleDeviceToken(_ deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        state = .registered(hex)
        UserDefaults.standard.set(hex, forKey: Self.tokenKey)
        uploadCurrentToken()
    }

    func handleRegistrationFailure(_ error: Error) {
        state = .failed(error.localizedDescription)
    }

    /// Called after sign-in once the Convex session is live.
    func uploadTokenIfNeeded() async {
        uploadCurrentToken()
    }

    private func uploadCurrentToken() {
        guard case .registered(let token) = state else { return }
        Task { await uploadHandler?(token) }
    }
}

/// Bridges APNs callbacks into PushNotificationManager and shows the daily
/// hadith banner while the app is in the foreground.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationManager.shared.handleDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushNotificationManager.shared.handleRegistrationFailure(error)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}
