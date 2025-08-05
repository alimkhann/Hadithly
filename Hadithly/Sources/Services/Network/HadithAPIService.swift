import Foundation
import Combine

// MARK: - Protocols for SOLID principles
protocol HadithServiceProtocol {
    func fetchHadiths(collection: String, bookNumber: Int, page: Int) async throws -> [Hadith]
    func searchHadiths(query: String, language: Language) async throws -> [Hadith]
    func fetchRandomHadith() async throws -> Hadith
    func fetchHolidayHadith(date: Date) async throws -> Hadith?
}

// MARK: - Network Manager Protocol
protocol NetworkManagerProtocol {
    func fetch<T: Decodable>(_ url: URL) async throws -> T
}

// MARK: - Network Manager
class NetworkManager: NetworkManagerProtocol {
    static let shared = NetworkManager()

    private init() {}

    func fetch<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NetworkError.invalidResponse
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum NetworkError: Error {
    case invalidResponse
    case decodingError
    case noData
}

// MARK: - Hadith API Service
class HadithAPIService: HadithServiceProtocol {
    private let networkManager: NetworkManagerProtocol
    private let cache = NSCache<NSString, NSData>()

    init(networkManager: NetworkManagerProtocol = NetworkManager.shared) {
        self.networkManager = networkManager
    }

    func fetchHadiths(collection: String, bookNumber: Int, page: Int) async throws -> [Hadith] {
        // Using fawazahmed0/hadith-api as primary source
        let baseURL = "https://cdn.jsdelivr.net/gh/fawazahmed0/hadith-api@1/editions"

        // For now, we'll use English as default and add translations later
        let urlString = "\(baseURL)/eng-\(collection.lowercased()).json"

        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidResponse
        }

        // Check cache first
        let cacheKey = "\(collection)-\(bookNumber)-\(page)" as NSString
        if let cachedData = cache.object(forKey: cacheKey) {
            return try parseHadiths(from: cachedData as Data)
        }

        // Fetch from network
        let hadithData: Data = try await networkManager.fetch(url)

        // Cache the response
        cache.setObject(hadithData as NSData, forKey: cacheKey)

        return try parseHadiths(from: hadithData)
    }

    func searchHadiths(query: String, language: Language) async throws -> [Hadith] {
        // For now, we'll search locally in cached data
        // In a full implementation, this would search across all collections
        return []
    }

    func fetchRandomHadith() async throws -> Hadith {
        // For now, return a sample hadith
        // In full implementation, this would fetch from a random collection
        return Hadith(
            id: "random-1",
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
    }

    func fetchHolidayHadith(date: Date) async throws -> Hadith? {
        // Check if it's a holiday and return special hadith
        // For now, return nil
        return nil
    }

    private func parseHadiths(from data: Data) throws -> [Hadith] {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return try parseHadiths(from: json)
    }

    private func parseHadiths(from data: [String: Any]) throws -> [Hadith] {
        // Parse the API response and convert to Hadith objects
        // This is a simplified implementation
        return []
    }
}