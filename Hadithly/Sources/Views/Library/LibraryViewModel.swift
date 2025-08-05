import Foundation
import Combine
import SwiftData

@MainActor
class LibraryViewModel: ObservableObject {
    @Published var selectedView: LibraryViewType = .saved
    @Published var savedHadiths: [Hadith] = []
    @Published var folders: [UserFolder] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let storageService: StorageServiceProtocol
    private var cancellables = Set<AnyCancellable>()

    init(storageService: StorageServiceProtocol? = nil) {
        if let storageService = storageService {
            self.storageService = storageService
        } else {
            // Use the shared persistence controller's container
            self.storageService = LocalStorageService(container: PersistenceController.shared.container)
        }
    }

    func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            // Load saved hadiths
            savedHadiths = try await storageService.fetchSavedHadiths()

            // Load folders
            folders = try await storageService.fetchFolders()

        } catch {
            errorMessage = "Failed to load library data: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func exportData() {
        // TODO: Implement export functionality
        print("Exporting library data...")
    }

    func createFolder(name: String) async {
        do {
            let newFolder = UserFolder(name: name)
            try await storageService.saveFolder(newFolder)
            await loadData()
        } catch {
            errorMessage = "Failed to create folder: \(error.localizedDescription)"
        }
    }

    func deleteFolder(_ folder: UserFolder) async {
        do {
            try await storageService.deleteFolder(folder.id)
            await loadData()
        } catch {
            errorMessage = "Failed to delete folder: \(error.localizedDescription)"
        }
    }
}

@MainActor
class FolderDetailViewModel: ObservableObject {
    @Published var hadiths: [Hadith] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let storageService: StorageServiceProtocol

    init(storageService: StorageServiceProtocol? = nil) {
        if let storageService = storageService {
            self.storageService = storageService
        } else {
            // Use the shared persistence controller's container
            self.storageService = LocalStorageService(container: PersistenceController.shared.container)
        }
    }

    func loadHadiths(for folder: UserFolder) async {
        isLoading = true
        errorMessage = nil

        do {
            // Get all saved hadiths and filter by folder
            let allSavedHadiths = try await storageService.fetchSavedHadiths()
            hadiths = allSavedHadiths.filter { folder.hadithIds.contains($0.id) }
        } catch {
            errorMessage = "Failed to load folder hadiths: \(error.localizedDescription)"
        }

        isLoading = false
    }
}