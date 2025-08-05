import SwiftUI
import SwiftData

@main
struct HadithlyApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(persistenceController.container)
                .environmentObject(AppSettings())
                .environmentObject(LocalizationManager.shared)
        }
    }
}