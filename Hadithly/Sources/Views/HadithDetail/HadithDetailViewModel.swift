import Foundation
import Combine
import SwiftData

@MainActor
class HadithDetailViewModel: ObservableObject {
    @Published var isSaved = false
    @Published var errorMessage: String?

    private let hadith: Hadith
    private let storageService: StorageServiceProtocol
    private var cancellables = Set<AnyCancellable>()

    init(hadith: Hadith, storageService: StorageServiceProtocol? = nil) {
        self.hadith = hadith
        if let storageService = storageService {
            self.storageService = storageService
        } else {
            // Use the shared persistence controller's container
            self.storageService = LocalStorageService(container: PersistenceController.shared.container)
        }
    }

    func checkSavedStatus() async {
        do {
            let savedHadiths = try await storageService.fetchSavedHadiths()
            isSaved = savedHadiths.contains { $0.id == hadith.id }
        } catch {
            errorMessage = "Failed to check saved status: \(error.localizedDescription)"
        }
    }

    func toggleSave() {
        Task {
            do {
                if isSaved {
                    try await storageService.deleteHadith(hadith.id)
                } else {
                    try await storageService.saveHadith(hadith)
                }
                isSaved.toggle()
            } catch {
                errorMessage = "Failed to \(isSaved ? "remove" : "save") hadith: \(error.localizedDescription)"
            }
        }
    }

    func shareHadith() {
        // TODO: Implement share functionality
        print("Sharing hadith: \(hadith.reference)")
    }

    func copyText() {
        // TODO: Implement copy to clipboard
        print("Copying hadith text to clipboard")
    }
}