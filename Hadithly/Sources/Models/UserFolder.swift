import Foundation
import CoreData

struct UserFolder: Identifiable, Codable {
    let id: String
    let name: String
    let color: String
    let createdAt: Date
    let hadithIds: [String]

    init(id: String = UUID().uuidString, name: String, color: String = "green",
         createdAt: Date = Date(), hadithIds: [String] = []) {
        self.id = id
        self.name = name
        self.color = color
        self.createdAt = createdAt
        self.hadithIds = hadithIds
    }
}

class AppSettings: ObservableObject {
    @Published var selectedLanguage: Language = .english
    @Published var notificationsEnabled: Bool = true
    @Published var notificationTime: Date = Calendar.current.date(from: DateComponents(hour: 8, minute: 0)) ?? Date()
    @Published var autoSave: Bool = true
    @Published var fontSize: Double = 16.0
    @Published var theme: AppTheme = .system
    @Published var showArabicText: Bool = true
    @Published var pureArabicMode: Bool = false

    init() {
        load()
    }

    func save() {
        // Save to UserDefaults
        UserDefaults.standard.set(selectedLanguage.rawValue, forKey: "selectedLanguage")
        UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled")
        UserDefaults.standard.set(notificationTime, forKey: "notificationTime")
        UserDefaults.standard.set(autoSave, forKey: "autoSave")
        UserDefaults.standard.set(fontSize, forKey: "fontSize")
        UserDefaults.standard.set(theme.rawValue, forKey: "theme")
        UserDefaults.standard.set(showArabicText, forKey: "showArabicText")
        UserDefaults.standard.set(pureArabicMode, forKey: "pureArabicMode")
    }

    func load() {
        if let languageString = UserDefaults.standard.string(forKey: "selectedLanguage"),
           let language = Language(rawValue: languageString) {
            selectedLanguage = language
        } else {
            // Detect device language
            let deviceLanguage = Locale.current.language.languageCode?.identifier ?? "en"
            selectedLanguage = deviceLanguage == "ru" ? .russian : .english
        }

        notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        if let time = UserDefaults.standard.object(forKey: "notificationTime") as? Date {
            notificationTime = time
        }
        autoSave = UserDefaults.standard.bool(forKey: "autoSave")
        fontSize = UserDefaults.standard.double(forKey: "fontSize")
        if fontSize == 0 { fontSize = 16.0 }
        if let themeString = UserDefaults.standard.string(forKey: "theme"),
           let theme = AppTheme(rawValue: themeString) {
            self.theme = theme
        }
        showArabicText = UserDefaults.standard.bool(forKey: "showArabicText")
        if UserDefaults.standard.object(forKey: "showArabicText") == nil {
            showArabicText = true // Default to showing Arabic
        }
        pureArabicMode = UserDefaults.standard.bool(forKey: "pureArabicMode")
    }
}

enum AppTheme: String, CaseIterable {
    case light = "light"
    case dark = "dark"
    case system = "system"

    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }
}