import Foundation
import Combine
import SwiftData

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var showClearDataAlert = false
    @Published var errorMessage: String?

    private let storageService: StorageServiceProtocol
    private let notificationService: NotificationServiceProtocol
    private var cancellables = Set<AnyCancellable>()

    init(storageService: StorageServiceProtocol? = nil,
         notificationService: NotificationServiceProtocol = NotificationService()) {
        if let storageService = storageService {
            self.storageService = storageService
        } else {
            // Use the shared persistence controller's container
            self.storageService = LocalStorageService(container: PersistenceController.shared.container)
        }
        self.notificationService = notificationService
    }

    func updateNotifications() {
        Task {
            do {
                try await notificationService.updateNotificationSchedule()
            } catch {
                errorMessage = "Failed to update notifications: \(error.localizedDescription)"
            }
        }
    }

    func exportData() {
        Task {
            do {
                let exportData = try await storageService.exportData()
                // TODO: Implement file sharing
                print("Export data: \(exportData)")
            } catch {
                errorMessage = "Failed to export data: \(error.localizedDescription)"
            }
        }
    }

    func importData() {
        // TODO: Implement file picker and import
        print("Import data...")
    }

    func clearAllData() {
        Task {
            do {
                try await storageService.clearAllData()
                errorMessage = nil
            } catch {
                errorMessage = "Failed to clear data: \(error.localizedDescription)"
            }
        }
    }
}