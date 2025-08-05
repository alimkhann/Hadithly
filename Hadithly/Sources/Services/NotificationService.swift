import Foundation
import UserNotifications

// MARK: - Notification Service Protocol
protocol NotificationServiceProtocol {
    func requestPermission() async -> Bool
    func scheduleDailyNotification(at time: Date) async throws
    func cancelAllNotifications() async
    func updateNotificationSchedule() async throws
}

// MARK: - Notification Service
class NotificationService: NotificationServiceProtocol {
    static let shared = NotificationService()

    init() {}

    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("Failed to request notification permission: \(error)")
            return false
        }
    }

    func scheduleDailyNotification(at time: Date) async throws {
        let center = UNUserNotificationCenter.current()

        // Cancel existing notifications
        await cancelAllNotifications()

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Daily Hadith"
        content.body = "Time for your daily hadith reading"
        content.sound = .default
        content.categoryIdentifier = "DAILY_HADITH"

        // Create date components for daily trigger
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: time)

        // Create trigger
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        // Create request
        let request = UNNotificationRequest(
            identifier: "daily_hadith",
            content: content,
            trigger: trigger
        )

        // Schedule notification
        try await center.add(request)
    }

    func cancelAllNotifications() async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
    }

    func updateNotificationSchedule() async throws {
        // This will be called when notification settings change
        // For now, we'll just schedule the default time
        let defaultTime = Calendar.current.date(from: DateComponents(hour: 8, minute: 0)) ?? Date()
        try await scheduleDailyNotification(at: defaultTime)
    }

    func scheduleRandomHadithNotification() async throws {
        let content = UNMutableNotificationContent()
        content.title = "Random Hadith"
        content.body = "Here's a random hadith for you to reflect on"
        content.sound = .default
        content.categoryIdentifier = "RANDOM_HADITH"

        // Schedule for 5 minutes from now
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 300, repeats: false)

        let request = UNNotificationRequest(
            identifier: "random_hadith_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        try await UNUserNotificationCenter.current().add(request)
    }
}
