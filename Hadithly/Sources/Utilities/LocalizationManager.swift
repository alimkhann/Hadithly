import Foundation

class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published var currentLanguage: Language = .english

    private init() {
        detectDeviceLanguage()
    }

    func detectDeviceLanguage() {
        let deviceLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        currentLanguage = deviceLanguage == "ru" ? .russian : .english
    }

    func localizedString(_ key: LocalizationKey) -> String {
        switch currentLanguage {
        case .russian:
            return key.russian
        case .english:
            return key.english
        case .arabic:
            return key.arabic
        }
    }
}

enum LocalizationKey {
    case home
    case search
    case library
    case settings
    case dailyHadith
    case today
    case quickActions
    case collections
    case saved
    case folders
    case noSavedHadiths
    case hadithsYouSaveWillAppearHere
    case noFolders
    case createFoldersToOrganizeYourSavedHadiths
    case language
    case displayLanguage
    case notifications
    case display
    case dataManagement
    case about
    case version
    case save
    case share
    case export
    case `import`
    case clearAllData
    case cancel
    case confirm
    case error
    case success
    case loading
    case noResults
    case tryDifferentKeywords
    case details
    case actions
    case arabic
    case english
    case russian
    case showArabicText
    case pureArabicMode
    case fontSize
    case theme
    case dailyNotifications
    case notificationTime
    case privacyPolicy
    case termsOfService
    case hadith
    case narrator
    case grade
    case reference
    case collection
    case book
    case hadithNumber
    case copyText
    case removeFromSaved
    case exportData
    case importData
    case clearDataWarning
    case clearDataMessage
    case holidayHadith
    case specialHadith
    case searchHadiths
    case random

    var english: String {
        switch self {
        case .home: return "Home"
        case .search: return "Search"
        case .searchHadiths: return "Search Hadiths..."
        case .library: return "Library"
        case .random: return "Random"
        case .settings: return "Settings"
        case .dailyHadith: return "Daily Hadith"
        case .today: return "Today"
        case .quickActions: return "Quick Actions"
        case .collections: return "Collections"
        case .saved: return "Saved"
        case .folders: return "Folders"
        case .noSavedHadiths: return "No Saved Hadiths"
        case .hadithsYouSaveWillAppearHere: return "Hadiths you save will appear here"
        case .noFolders: return "No Folders"
        case .createFoldersToOrganizeYourSavedHadiths: return "Create folders to organize your saved hadiths"
        case .language: return "Language"
        case .displayLanguage: return "Display Language"
        case .notifications: return "Notifications"
        case .display: return "Display"
        case .dataManagement: return "Data Management"
        case .about: return "About"
        case .version: return "Version"
        case .save: return "Save"
        case .share: return "Share"
        case .export: return "Export"
        case .import: return "Import"
        case .clearAllData: return "Clear All Data"
        case .cancel: return "Cancel"
        case .confirm: return "Confirm"
        case .error: return "Error"
        case .success: return "Success"
        case .loading: return "Loading"
        case .noResults: return "No results found"
        case .tryDifferentKeywords: return "Try searching with different keywords or in a different language"
        case .details: return "Details"
        case .actions: return "Actions"
        case .arabic: return "Arabic"
        case .english: return "English"
        case .russian: return "Russian"
        case .showArabicText: return "Show Arabic Text"
        case .pureArabicMode: return "Pure Arabic Mode"
        case .fontSize: return "Font Size"
        case .theme: return "Theme"
        case .dailyNotifications: return "Daily Notifications"
        case .notificationTime: return "Notification Time"
        case .privacyPolicy: return "Privacy Policy"
        case .termsOfService: return "Terms of Service"
        case .hadith: return "Hadith"
        case .narrator: return "Narrator"
        case .grade: return "Grade"
        case .reference: return "Reference"
        case .collection: return "Collection"
        case .book: return "Book"
        case .hadithNumber: return "Hadith"
        case .copyText: return "Copy Text"
        case .removeFromSaved: return "Remove from Saved"
        case .exportData: return "Export Data"
        case .importData: return "Import Data"
        case .clearDataWarning: return "Clear All Data"
        case .clearDataMessage: return "This will permanently delete all saved hadiths and folders. This action cannot be undone."
        case .holidayHadith: return "Special Hadith"
        case .specialHadith: return "Special Hadith"
        }
    }

    var russian: String {
        switch self {
        case .home: return "Главная"
        case .search: return "Поиск"
        case .searchHadiths: return "Поиск хадисов..."
        case .library: return "Библиотека"
        case .random: return "Случайный"
        case .settings: return "Настройки"
        case .dailyHadith: return "Ежедневный хадис"
        case .today: return "Сегодня"
        case .quickActions: return "Быстрые действия"
        case .collections: return "Коллекции"
        case .saved: return "Сохраненные"
        case .folders: return "Папки"
        case .noSavedHadiths: return "Нет сохраненных хадисов"
        case .hadithsYouSaveWillAppearHere: return "Хадисы которые вы сохраните появятся здесь"
        case .noFolders: return "Нет папок"
        case .createFoldersToOrganizeYourSavedHadiths: return "Создайте папки чтобы организовать ваши сохраненные хадисы"
        case .language: return "Язык"
        case .displayLanguage: return "Язык отображения"
        case .notifications: return "Уведомления"
        case .display: return "Отображение"
        case .dataManagement: return "Управление данными"
        case .about: return "О приложении"
        case .version: return "Версия"
        case .save: return "Сохранить"
        case .share: return "Поделиться"
        case .export: return "Экспорт"
        case .import: return "Импорт"
        case .clearAllData: return "Очистить все данные"
        case .cancel: return "Отмена"
        case .confirm: return "Подтвердить"
        case .error: return "Ошибка"
        case .success: return "Успешно"
        case .loading: return "Загрузка"
        case .noResults: return "Результаты не найдены"
        case .tryDifferentKeywords: return "Попробуйте поиск с другими ключевыми словами или на другом языке"
        case .details: return "Детали"
        case .actions: return "Действия"
        case .arabic: return "Арабский"
        case .english: return "Английский"
        case .russian: return "Русский"
        case .showArabicText: return "Показывать арабский текст"
        case .pureArabicMode: return "Чистый арабский режим"
        case .fontSize: return "Размер шрифта"
        case .theme: return "Тема"
        case .dailyNotifications: return "Ежедневные уведомления"
        case .notificationTime: return "Время уведомления"
        case .privacyPolicy: return "Политика конфиденциальности"
        case .termsOfService: return "Условия использования"
        case .hadith: return "Хадис"
        case .narrator: return "Передатчик"
        case .grade: return "Оценка"
        case .reference: return "Ссылка"
        case .collection: return "Коллекция"
        case .book: return "Книга"
        case .hadithNumber: return "Хадис"
        case .copyText: return "Копировать текст"
        case .removeFromSaved: return "Удалить из сохраненных"
        case .exportData: return "Экспорт данных"
        case .importData: return "Импорт данных"
        case .clearDataWarning: return "Очистить все данные"
        case .clearDataMessage: return "Это навсегда удалит все сохраненные хадисы и папки. Это действие нельзя отменить."
        case .holidayHadith: return "Особый хадис"
        case .specialHadith: return "Особый хадис"
        }
    }

    var arabic: String {
        switch self {
        case .home: return "الرئيسية"
        case .search: return "بحث"
        case .searchHadiths: return "...بحث عن حديث"
        case .library: return "المكتبة"
        case .random: return "عشوائي"
        case .settings: return "الإعدادات"
        case .dailyHadith: return "الحديث اليومي"
        case .today: return "اليوم"
        case .quickActions: return "إجراءات سريعة"
        case .collections: return "المجموعات"
        case .saved: return "المحفوظات"
        case .folders: return "المجلدات"
        case .noSavedHadiths: return "لا توجد أحاديث محفوظة"
        case .hadithsYouSaveWillAppearHere: return "الأحاديث التي تحفظها ستظهر هنا"
        case .noFolders: return "لا توجد مجلدات"
        case .createFoldersToOrganizeYourSavedHadiths: return "أنشئ مجلدات لتنظيم الأحاديث المحفوظة"
        case .language: return "اللغة"
        case .displayLanguage: return "لغة العرض"
        case .notifications: return "الإشعارات"
        case .display: return "العرض"
        case .dataManagement: return "إدارة البيانات"
        case .about: return "حول"
        case .version: return "الإصدار"
        case .save: return "حفظ"
        case .share: return "مشاركة"
        case .export: return "تصدير"
        case .import: return "استيراد"
        case .clearAllData: return "مسح جميع البيانات"
        case .cancel: return "إلغاء"
        case .confirm: return "تأكيد"
        case .error: return "خطأ"
        case .success: return "تم بنجاح"
        case .loading: return "جارٍ التحميل"
        case .noResults: return "لم يتم العثور على نتائج"
        case .tryDifferentKeywords: return "جرّب كلمات مفتاحية مختلفة أو لغة أخرى"
        case .details: return "تفاصيل"
        case .actions: return "إجراءات"
        case .arabic: return "العربية"
        case .english: return "الإنجليزية"
        case .russian: return "الروسية"
        case .showArabicText: return "عرض النص العربي"
        case .pureArabicMode: return "الوضع العربي الصافي"
        case .fontSize: return "حجم الخط"
        case .theme: return "السمة"
        case .dailyNotifications: return "إشعارات يومية"
        case .notificationTime: return "وقت الإشعار"
        case .privacyPolicy: return "سياسة الخصوصية"
        case .termsOfService: return "شروط الخدمة"
        case .hadith: return "حديث"
        case .narrator: return "الراوي"
        case .grade: return "التصنيف"
        case .reference: return "المرجع"
        case .collection: return "المجموعة"
        case .book: return "الكتاب"
        case .hadithNumber: return "رقم الحديث"
        case .copyText: return "نسخ النص"
        case .removeFromSaved: return "إزالة من المحفوظات"
        case .exportData: return "تصدير البيانات"
        case .importData: return "استيراد البيانات"
        case .clearDataWarning: return "مسح جميع البيانات"
        case .clearDataMessage: return "سيؤدي هذا إلى حذف جميع الأحاديث والمجلدات المحفوظة نهائيًا. لا يمكن التراجع عن هذا الإجراء."
        case .holidayHadith: return "حديث خاص"
        case .specialHadith: return "حديث خاص"
        }
    }
}
