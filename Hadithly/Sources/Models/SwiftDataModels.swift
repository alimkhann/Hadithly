import Foundation
import SwiftData

@Model
class SavedHadith {
    var id: String
    var collection: String
    var bookNumber: Int32
    var hadithNumber: Int32
    var arabicText: String
    var englishText: String
    var russianText: String
    var narrator: String
    var grade: String
    var reference: String
    var savedAt: Date

    init(id: String, collection: String, bookNumber: Int32, hadithNumber: Int32,
         arabicText: String, englishText: String, russianText: String,
         narrator: String, grade: String, reference: String, savedAt: Date = Date()) {
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
        self.savedAt = savedAt
    }
}

@Model
class SavedFolder {
    var id: String
    var name: String
    var color: String
    var createdAt: Date
    var hadithIds: String

    init(id: String, name: String, color: String, createdAt: Date, hadithIds: String) {
        self.id = id
        self.name = name
        self.color = color
        self.createdAt = createdAt
        self.hadithIds = hadithIds
    }
}