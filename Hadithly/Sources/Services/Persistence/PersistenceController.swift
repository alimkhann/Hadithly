import SwiftData
import Foundation

struct PersistenceController {
    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)

        // For preview, we'll create the sample data when needed
        // rather than trying to access mainContext synchronously
        return result
    }()

    let container: ModelContainer

    init(inMemory: Bool = false) {
        let schema = Schema([
            SavedHadith.self,
            SavedFolder.self
        ])

        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)

        do {
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    // Helper method to add sample data for previews
    @MainActor
    func addSampleData() {
        let sampleHadith = SavedHadith(
            id: "sample-1",
            collection: "Sahih Bukhari",
            bookNumber: 1,
            hadithNumber: 1,
            arabicText: "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ",
            englishText: "In the name of Allah, the Most Gracious, the Most Merciful",
            russianText: "Во имя Аллаха, Милостивого, Милосердного",
            narrator: "Abu Huraira",
            grade: "Sahih",
            reference: "Bukhari 1:1"
        )

        let context = container.mainContext
        context.insert(sampleHadith)

        do {
            try context.save()
        } catch {
            print("Failed to save sample data: \(error)")
        }
    }
}