import Foundation
import Combine

@MainActor
class SearchViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var searchResults: [Hadith] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let hadithService: HadithServiceProtocol
    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(hadithService: HadithServiceProtocol = HadithAPIService()) {
        self.hadithService = hadithService
    }

    func performSearch() async {
        // Cancel previous search task
        searchTask?.cancel()

        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }

        // Create new search task with delay
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay

            guard !Task.isCancelled else { return }

            isLoading = true
            errorMessage = nil

            // For now, we'll use a mock search
            // In full implementation, this would call the API
            searchResults = await mockSearchResults()

            isLoading = false
        }

        await searchTask?.value
    }

    private func mockSearchResults() async -> [Hadith] {
        // Mock search results for demonstration
        return [
            Hadith(
                id: "search-1",
                collection: "Sahih Bukhari",
                bookNumber: 1,
                hadithNumber: 1,
                arabicText: "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ",
                englishText: "In the name of Allah, the Most Gracious, the Most Merciful",
                russianText: "Во имя Аллаха, Милостивого, Милосердного",
                narrator: "Abu Huraira",
                grade: "Sahih",
                reference: "Bukhari 1:1"
            ),
            Hadith(
                id: "search-2",
                collection: "Sahih Muslim",
                bookNumber: 1,
                hadithNumber: 1,
                arabicText: "إِنَّمَا الأَعْمَالُ بِالنِّيَّاتِ",
                englishText: "Actions are judged by intentions",
                russianText: "Поистине, дела оцениваются по намерениям",
                narrator: "Umar ibn al-Khattab",
                grade: "Sahih",
                reference: "Muslim 1:1"
            )
        ]
    }

    func clearSearch() {
        searchText = ""
        searchResults = []
        searchTask?.cancel()
    }
}