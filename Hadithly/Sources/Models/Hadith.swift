import Foundation
import CoreData

struct Hadith: Identifiable, Codable {
    let id: String
    let collection: String
    let bookNumber: Int
    let hadithNumber: Int
    let arabicText: String
    let englishText: String
    let russianText: String
    let narrator: String
    let grade: String
    let reference: String
    let isSaved: Bool

    init(id: String, collection: String, bookNumber: Int, hadithNumber: Int,
         arabicText: String, englishText: String, russianText: String,
         narrator: String, grade: String, reference: String, isSaved: Bool = false) {
        self.id = id
        self.collection = collection
        self.bookNumber = bookNumber
        self.hadithNumber = hadithNumber
        self.arabicText = arabicText
        self.englishText = englishText
        self.russianText = russianText
        self.narrator = narrator
        self.grade = grade
        self.reference = reference
        self.isSaved = isSaved
    }

    func text(for language: Language) -> String {
        switch language {
        case .arabic:
            return arabicText
        case .english:
            return englishText
        case .russian:
            return russianText
        }
    }
}

enum Language: String, CaseIterable, Codable {
    case arabic = "ar"
    case english = "en"
    case russian = "ru"

    var displayName: String {
        switch self {
        case .arabic: return "العربية"
        case .english: return "English"
        case .russian: return "Русский"
        }
    }

    var isRTL: Bool {
        return self == .arabic
    }
}