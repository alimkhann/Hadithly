import Foundation
import SwiftData

// MARK: - Storage Service Protocol
protocol StorageServiceProtocol {
    func saveHadith(_ hadith: Hadith) async throws
    func fetchSavedHadiths() async throws -> [Hadith]
    func deleteHadith(_ hadithId: String) async throws
    func saveFolder(_ folder: UserFolder) async throws
    func fetchFolders() async throws -> [UserFolder]
    func deleteFolder(_ folderId: String) async throws
    func addHadithToFolder(_ hadithId: String, folderId: String) async throws
    func removeHadithFromFolder(_ hadithId: String, folderId: String) async throws
    func exportData() async throws -> Data
    func importData(_ data: Data) async throws
    func clearAllData() async throws
}

// MARK: - Local Storage Service
@MainActor
class LocalStorageService: StorageServiceProtocol {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func saveHadith(_ hadith: Hadith) async throws {
        let context = container.mainContext

        // Check if hadith already exists
        let descriptor = FetchDescriptor<SavedHadith>(
            predicate: #Predicate<SavedHadith> { $0.id == hadith.id }
        )

        let existingHadiths = try context.fetch(descriptor)

        if let existingHadith = existingHadiths.first {
            // Update existing hadith
            existingHadith.arabicText = hadith.arabicText
            existingHadith.englishText = hadith.englishText
            existingHadith.russianText = hadith.russianText
            existingHadith.narrator = hadith.narrator
            existingHadith.grade = hadith.grade
            existingHadith.reference = hadith.reference
            existingHadith.savedAt = Date()
        } else {
            // Create new hadith
            let savedHadith = SavedHadith(
                id: hadith.id,
                collection: hadith.collection,
                bookNumber: Int32(hadith.bookNumber),
                hadithNumber: Int32(hadith.hadithNumber),
                arabicText: hadith.arabicText,
                englishText: hadith.englishText,
                russianText: hadith.russianText,
                narrator: hadith.narrator,
                grade: hadith.grade,
                reference: hadith.reference
            )
            context.insert(savedHadith)
        }

        try context.save()
    }

    func fetchSavedHadiths() async throws -> [Hadith] {
        let context = container.mainContext
        let descriptor = FetchDescriptor<SavedHadith>(
            sortBy: [SortDescriptor(\.savedAt, order: .reverse)]
        )

        let savedHadiths = try context.fetch(descriptor)

        return savedHadiths.map { savedHadith in
            Hadith(
                id: savedHadith.id,
                collection: savedHadith.collection,
                bookNumber: Int(savedHadith.bookNumber),
                hadithNumber: Int(savedHadith.hadithNumber),
                arabicText: savedHadith.arabicText,
                englishText: savedHadith.englishText,
                russianText: savedHadith.russianText,
                narrator: savedHadith.narrator,
                grade: savedHadith.grade,
                reference: savedHadith.reference,
                isSaved: true
            )
        }
    }

    func deleteHadith(_ hadithId: String) async throws {
        let context = container.mainContext
        let descriptor = FetchDescriptor<SavedHadith>(
            predicate: #Predicate<SavedHadith> { $0.id == hadithId }
        )

        let hadiths = try context.fetch(descriptor)
        hadiths.forEach { context.delete($0) }

        try context.save()
    }

    func saveFolder(_ folder: UserFolder) async throws {
        let context = container.mainContext

        // Check if folder already exists
        let descriptor = FetchDescriptor<SavedFolder>(
            predicate: #Predicate<SavedFolder> { $0.id == folder.id }
        )

        let existingFolders = try context.fetch(descriptor)

        if let existingFolder = existingFolders.first {
            // Update existing folder
            existingFolder.name = folder.name
            existingFolder.color = folder.color
            existingFolder.hadithIds = folder.hadithIds.joined(separator: ",")
        } else {
            // Create new folder
            let savedFolder = SavedFolder(
                id: folder.id,
                name: folder.name,
                color: folder.color,
                createdAt: folder.createdAt,
                hadithIds: folder.hadithIds.joined(separator: ",")
            )
            context.insert(savedFolder)
        }

        try context.save()
    }

    func fetchFolders() async throws -> [UserFolder] {
        let context = container.mainContext
        let descriptor = FetchDescriptor<SavedFolder>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        let savedFolders = try context.fetch(descriptor)

        return savedFolders.map { savedFolder in
            UserFolder(
                id: savedFolder.id,
                name: savedFolder.name,
                color: savedFolder.color,
                createdAt: savedFolder.createdAt,
                hadithIds: savedFolder.hadithIds.components(separatedBy: ",").filter { !$0.isEmpty }
            )
        }
    }

    func deleteFolder(_ folderId: String) async throws {
        let context = container.mainContext
        let descriptor = FetchDescriptor<SavedFolder>(
            predicate: #Predicate<SavedFolder> { $0.id == folderId }
        )

        let folders = try context.fetch(descriptor)
        folders.forEach { context.delete($0) }

        try context.save()
    }

    func addHadithToFolder(_ hadithId: String, folderId: String) async throws {
        let context = container.mainContext
        let descriptor = FetchDescriptor<SavedFolder>(
            predicate: #Predicate<SavedFolder> { $0.id == folderId }
        )

        let folders = try context.fetch(descriptor)
        guard let folder = folders.first else {
            throw StorageError.folderNotFound
        }

        var hadithIds = folder.hadithIds.components(separatedBy: ",").filter { !$0.isEmpty }
        if !hadithIds.contains(hadithId) {
            hadithIds.append(hadithId)
            folder.hadithIds = hadithIds.joined(separator: ",")
            try context.save()
        }
    }

    func removeHadithFromFolder(_ hadithId: String, folderId: String) async throws {
        let context = container.mainContext
        let descriptor = FetchDescriptor<SavedFolder>(
            predicate: #Predicate<SavedFolder> { $0.id == folderId }
        )

        let folders = try context.fetch(descriptor)
        guard let folder = folders.first else {
            throw StorageError.folderNotFound
        }

        var hadithIds = folder.hadithIds.components(separatedBy: ",").filter { !$0.isEmpty }
        hadithIds.removeAll { $0 == hadithId }
        folder.hadithIds = hadithIds.joined(separator: ",")
        try context.save()
    }

    func exportData() async throws -> Data {
        let context = container.mainContext

        // Fetch all saved hadiths and folders
        let hadithDescriptor = FetchDescriptor<SavedHadith>()
        let folderDescriptor = FetchDescriptor<SavedFolder>()

        let savedHadiths = try context.fetch(hadithDescriptor)
        let savedFolders = try context.fetch(folderDescriptor)

        // Convert to exportable format
        let exportData = ExportData(
            hadiths: savedHadiths.map { savedHadith in
                Hadith(
                    id: savedHadith.id,
                    collection: savedHadith.collection,
                    bookNumber: Int(savedHadith.bookNumber),
                    hadithNumber: Int(savedHadith.hadithNumber),
                    arabicText: savedHadith.arabicText,
                    englishText: savedHadith.englishText,
                    russianText: savedHadith.russianText,
                    narrator: savedHadith.narrator,
                    grade: savedHadith.grade,
                    reference: savedHadith.reference,
                    isSaved: true
                )
            },
            folders: savedFolders.map { savedFolder in
                UserFolder(
                    id: savedFolder.id,
                    name: savedFolder.name,
                    color: savedFolder.color,
                    createdAt: savedFolder.createdAt,
                    hadithIds: savedFolder.hadithIds.components(separatedBy: ",").filter { !$0.isEmpty }
                )
            }
        )

        return try JSONEncoder().encode(exportData)
    }

    func importData(_ data: Data) async throws {
        let context = container.mainContext

        // Clear existing data
        try await clearAllData()

        // Decode import data
        let importData = try JSONDecoder().decode(ExportData.self, from: data)

        // Import hadiths
        for hadith in importData.hadiths {
            let savedHadith = SavedHadith(
                id: hadith.id,
                collection: hadith.collection,
                bookNumber: Int32(hadith.bookNumber),
                hadithNumber: Int32(hadith.hadithNumber),
                arabicText: hadith.arabicText,
                englishText: hadith.englishText,
                russianText: hadith.russianText,
                narrator: hadith.narrator,
                grade: hadith.grade,
                reference: hadith.reference
            )
            context.insert(savedHadith)
        }

        // Import folders
        for folder in importData.folders {
            let savedFolder = SavedFolder(
                id: folder.id,
                name: folder.name,
                color: folder.color,
                createdAt: folder.createdAt,
                hadithIds: folder.hadithIds.joined(separator: ",")
            )
            context.insert(savedFolder)
        }

        try context.save()
    }

    func clearAllData() async throws {
        let context = container.mainContext

        // Delete all saved hadiths
        let hadithDescriptor = FetchDescriptor<SavedHadith>()
        let savedHadiths = try context.fetch(hadithDescriptor)
        savedHadiths.forEach { context.delete($0) }

        // Delete all folders
        let folderDescriptor = FetchDescriptor<SavedFolder>()
        let savedFolders = try context.fetch(folderDescriptor)
        savedFolders.forEach { context.delete($0) }

        try context.save()
    }
}

// MARK: - Export Data Structure
struct ExportData: Codable {
    let hadiths: [Hadith]
    let folders: [UserFolder]
}

// MARK: - Storage Errors
enum StorageError: Error {
    case folderNotFound
    case hadithNotFound
    case importFailed
    case exportFailed
}
