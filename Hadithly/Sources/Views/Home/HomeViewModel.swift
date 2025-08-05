import Foundation
import Combine

@MainActor
class HomeViewModel: ObservableObject {
    @Published var dailyHadith: Hadith?
    @Published var holidayHadith: Hadith?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let hadithService: HadithServiceProtocol
    private var cancellables = Set<AnyCancellable>()

    init(hadithService: HadithServiceProtocol = HadithAPIService()) {
        self.hadithService = hadithService
    }

    func loadDailyHadith() async {
        isLoading = true
        errorMessage = nil

        do {
            // Load daily hadith
            dailyHadith = try await hadithService.fetchRandomHadith()

            // Check for holiday hadith
            holidayHadith = try await hadithService.fetchHolidayHadith(date: Date())

        } catch {
            errorMessage = "Failed to load daily hadith: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func refreshDailyHadith() async {
        await loadDailyHadith()
    }

    func saveHadith(_ hadith: Hadith) {
        // TODO: Implement save functionality
        print("Saving hadith: \(hadith.reference)")
    }

    func shareHadith(_ hadith: Hadith) {
        // TODO: Implement share functionality
        print("Sharing hadith: \(hadith.reference)")
    }
}