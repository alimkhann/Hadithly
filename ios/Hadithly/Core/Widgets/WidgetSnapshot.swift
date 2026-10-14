import Foundation
import WidgetKit

/// The only data a widget may read. It is intentionally separate from Saved
/// data: no account identifiers, notes, folders, or raw profile fields cross
/// this boundary.
struct WidgetDailySnapshot: Codable, Equatable {
    let collectionSlug: String
    let providerHadithId: String
    let reference: String
    let text: String
    let arabicText: String
    let locale: String
    let arabicVisible: Bool
    let translationVisible: Bool
    let isAI: Bool
    let sourceScope: String
    let localDate: String
    let timezone: String
    let isOffline: Bool
    let updatedAt: Date
}

enum DailyWidgetCopy {
    private static func language(_ locale: String) -> String {
        Locale(identifier: locale).language.languageCode?.identifier ?? "en"
    }

    private static func value(_ locale: String, _ values: [String: String]) -> String {
        values[language(locale)] ?? values["en"]!
    }

    static func title(_ locale: String) -> String {
        value(locale, [
            "en": "Daily Hadith", "ar": "الحديث اليومي", "ru": "Хадис дня",
            "kk": "Бүгінгі хадис", "ky": "Бүгүнкү хадис", "uz": "Bugungi hadis",
            "tr": "Günün hadisi", "id": "Hadis hari ini", "ur": "آج کی حدیث",
            "fr": "Hadith du jour", "es": "Hadiz del día", "pt": "Hadith do dia",
            "sw": "Hadithi ya leo", "hi": "आज की हदीस", "bn": "আজকের হাদিস",
        ])
    }
    static func empty(_ locale: String) -> String {
        value(locale, [
            "en": "Open Hadithly to prepare today’s hadith.", "ar": "افتح حديثلي لتحضير حديث اليوم.",
            "ru": "Откройте Hadithly, чтобы подготовить хадис дня.", "kk": "Бүгінгі хадисті дайындау үшін Hadithly ашыңыз.",
            "ky": "Бүгүнкү хадисти даярдоо үчүн Hadithly'ди ачыңыз.", "uz": "Bugungi hadisni tayyorlash uchun Hadithly’ni oching.",
            "tr": "Bugünün hadisini hazırlamak için Hadithly’yi açın.", "id": "Buka Hadithly untuk menyiapkan hadis hari ini.",
            "ur": "آج کی حدیث تیار کرنے کے لیے حدیثلی کھولیں۔", "fr": "Ouvrez Hadithly pour préparer le hadith du jour.",
            "es": "Abre Hadithly para preparar el hadiz del día.", "pt": "Abra o Hadithly para preparar o hadith do dia.",
            "sw": "Fungua Hadithly ili kuandaa hadithi ya leo.", "hi": "आज की हदीस तैयार करने के लिए Hadithly खोलें।",
            "bn": "আজকের হাদিস প্রস্তুত করতে Hadithly খুলুন।",
        ])
    }
    static func locked(_ locale: String) -> String {
        value(locale, [
            "en": "Unlock Hadithly to view today’s hadith.", "ar": "افتح قفل الجهاز لعرض حديث اليوم.",
            "ru": "Разблокируйте Hadithly, чтобы увидеть хадис дня.", "kk": "Бүгінгі хадисті көру үшін Hadithly құлпын ашыңыз.",
            "ky": "Бүгүнкү хадисти көрүү үчүн Hadithly кулпусун ачыңыз.", "uz": "Bugungi hadisni ko‘rish uchun Hadithly qulfini oching.",
            "tr": "Bugünün hadisini görmek için Hadithly’nin kilidini açın.", "id": "Buka kunci Hadithly untuk melihat hadis hari ini.",
            "ur": "آج کی حدیث دیکھنے کے لیے آلہ کھولیں۔", "fr": "Déverrouillez Hadithly pour voir le hadith du jour.",
            "es": "Desbloquea Hadithly para ver el hadiz del día.", "pt": "Desbloqueie o Hadithly para ver o hadith do dia.",
            "sw": "Fungua Hadithly ili kuona hadithi ya leo.", "hi": "आज की हदीस देखने के लिए Hadithly अनलॉक करें।",
            "bn": "আজকের হাদিস দেখতে Hadithly আনলক করুন।",
        ])
    }
    static func ai(_ locale: String) -> String {
        value(locale, [
            "en": "AI translation", "ar": "ترجمة بالذكاء الاصطناعي", "ru": "Перевод ИИ", "kk": "AI аудармасы",
            "ky": "AI котормосу", "uz": "SI tarjimasi", "tr": "Yapay zekâ çevirisi", "id": "Terjemahan AI",
            "ur": "AI ترجمہ", "fr": "Traduction par IA", "es": "Traducción con IA", "pt": "Tradução por IA",
            "sw": "Tafsiri ya AI", "hi": "AI अनुवाद", "bn": "AI অনুবাদ",
        ])
    }
    static func offline(_ locale: String) -> String {
        value(locale, [
            "en": "Saved offline copy", "ar": "نسخة محفوظة دون اتصال", "ru": "Сохранённая офлайн-копия", "kk": "Желіде сақталған көшірме",
            "ky": "Офлайн сакталган көчүрмө", "uz": "Oflayn saqlangan nusxa", "tr": "Çevrimdışı kaydedilen kopya", "id": "Salinan tersimpan offline",
            "ur": "آف لائن محفوظ نقل", "fr": "Copie enregistrée hors ligne", "es": "Copia guardada sin conexión", "pt": "Cópia salva off-line",
            "sw": "Nakala iliyohifadhiwa nje ya mtandao", "hi": "ऑफ़लाइन सहेजी गई प्रति", "bn": "অফলাইনে সংরক্ষিত কপি",
        ])
    }
    static func stale(_ locale: String) -> String {
        value(locale, [
            "en": "Update when opened", "ar": "حدّث عند الفتح", "ru": "Обновится при открытии", "kk": "Ашқанда жаңартылады",
            "ky": "Ачканда жаңыланат", "uz": "Ochilganda yangilanadi", "tr": "Açıldığında güncellenir", "id": "Diperbarui saat dibuka",
            "ur": "کھولنے پر اپ ڈیٹ ہوگا", "fr": "Mise à jour à l’ouverture", "es": "Se actualizará al abrir", "pt": "Atualiza ao abrir",
            "sw": "Itasasishwa ikifunguliwa", "hi": "खोलने पर अपडेट होगा", "bn": "খুললে আপডেট হবে",
        ])
    }
}

/// Mirrors the public W1 payload and intentionally cannot represent a Saved
/// item, account field, Arabic fallback, or private reading position.
struct DailyWidgetPayload: Codable, Equatable {
    let collectionSlug: String
    let providerHadithId: String
    let reference: String
    let text: String
    let arabicText: String
    let locale: String
    let arabicVisible: Bool
    let translationVisible: Bool
    let isAI: Bool
    let sourceScope: String
    let localDate: String
    let timezone: String
    let updatedAt: Double

    func snapshot(isOffline: Bool = false) -> WidgetDailySnapshot {
        WidgetDailySnapshot(
            collectionSlug: collectionSlug,
            providerHadithId: providerHadithId,
            reference: reference,
            text: text,
            arabicText: arabicText,
            locale: locale,
            arabicVisible: arabicVisible,
            translationVisible: translationVisible,
            isAI: isAI,
            sourceScope: sourceScope,
            localDate: localDate,
            timezone: timezone,
            isOffline: isOffline,
            updatedAt: Date(timeIntervalSince1970: updatedAt / 1_000)
        )
    }
}

struct WidgetContinueSnapshot: Codable, Equatable {
    let reference: String
    let progressFraction: Double?
    let progressOrdinal: Int?
    let progressTotal: Int?
    let locale: String
    let updatedAt: Date
}

/// The widget stores presentation only. The authoritative private position
/// remains in UserLibraryModel and is resolved after the app opens.
enum ContinueWidgetProgress: String, Codable, Equatable {
    case inProgress = "in_progress"

    var label: String { "Reading in progress" }
}

struct ContinueWidgetPresentation: Equatable {
    let reference: String
    let progressFraction: Double?
    let progressOrdinal: Int?
    let progressTotal: Int?
    let locale: String

    init(reference: String, progressFraction: Double?, progressOrdinal: Int?, progressTotal: Int?, locale: String) {
        self.reference = reference
        self.progressFraction = progressFraction.map { min(1, max(0, $0)) }
        self.progressOrdinal = progressOrdinal
        self.progressTotal = progressTotal
        self.locale = locale
    }

    private var language: String { Locale(identifier: locale).language.languageCode?.identifier ?? "en" }
    var title: String {
        ["ar": "متابعة القراءة", "ur": "مطالعہ جاری رکھیں", "ru": "Продолжить чтение", "kk": "Оқуды жалғастыру", "ky": "Окууну улантуу", "uz": "O‘qishni davom ettirish", "tr": "Okumaya devam et", "id": "Lanjutkan membaca", "fr": "Continuer la lecture", "es": "Continuar leyendo", "pt": "Continuar lendo", "sw": "Endelea kusoma", "hi": "पढ़ना जारी रखें", "bn": "পড়া চালিয়ে যান"][language] ?? "Continue Reading"
    }
    var resumeText: String {
        ["ar": "استئناف القراءة", "ur": "مطالعہ جاری رکھیں", "ru": "Продолжить чтение", "kk": "Оқуды жалғастыру", "ky": "Окууну улантуу", "uz": "O‘qishni davom ettirish", "tr": "Okumaya devam et", "id": "Lanjutkan membaca", "fr": "Reprendre la lecture", "es": "Reanudar la lectura", "pt": "Retomar a leitura", "sw": "Endelea kusoma", "hi": "पढ़ना जारी रखें", "bn": "পড়া চালিয়ে যান"][language] ?? "Resume reading"
    }
    var progressLabel: String {
        guard let progressOrdinal else { return resumeText }
        guard let progressTotal, progressTotal > 0 else {
            switch language {
            case "ar": return "التقدم: الحديث \(progressOrdinal)"
            case "ur": return "پیش رفت: حدیث \(progressOrdinal)"
            case "ru": return "Прогресс: хадис \(progressOrdinal)"
            case "hi": return "प्रगति: हदीस \(progressOrdinal)"
            case "bn": return "অগ্রগতি: হাদিস \(progressOrdinal)"
            default: return "Progress: Hadith \(progressOrdinal)"
            }
        }
        switch language {
        case "ar": return "الحديث \(progressOrdinal) من \(progressTotal)"
        case "ur": return "حدیث \(progressOrdinal)، کل \(progressTotal)"
        case "ru": return "Хадис \(progressOrdinal) из \(progressTotal)"
        case "fr": return "Hadith \(progressOrdinal) sur \(progressTotal)"
        case "es": return "Hadiz \(progressOrdinal) de \(progressTotal)"
        case "pt": return "Hadith \(progressOrdinal) de \(progressTotal)"
        case "id": return "Hadis \(progressOrdinal) dari \(progressTotal)"
        case "sw": return "Hadithi \(progressOrdinal) kati ya \(progressTotal)"
        case "hi": return "हदीस \(progressOrdinal) में से \(progressTotal)"
        case "bn": return "হাদিস \(progressOrdinal) / \(progressTotal)"
        default: return "Hadith \(progressOrdinal) of \(progressTotal)"
        }
    }
    var localizedReference: String {
        switch language {
        case "ar": return reference.replacingOccurrences(of: "Hadith ", with: "الحديث ")
        case "ur": return reference.replacingOccurrences(of: "Hadith ", with: "حدیث ")
        default: return reference
        }
    }
    var compactLines: [String] { [localizedReference, progressLabel] }
    var accessoryInlineText: String { resumeText }
    var isRightToLeft: Bool {
        Locale.Language(identifier: locale).characterDirection == .rightToLeft
    }
    static let emptyMessage = "Read a hadith to continue here."
    static let lockMessage = "Unlock Hadithly to resume reading."
    var localizedEmptyMessage: String {
        ["ar": "اقرأ حديثًا للمتابعة هنا.", "ur": "یہاں سے جاری رکھنے کے لیے حدیث پڑھیں۔", "ru": "Прочитайте хадис, чтобы продолжить здесь.", "fr": "Lisez un hadith pour continuer ici.", "es": "Lee un hadiz para continuar aquí.", "pt": "Leia um hadith para continuar aqui.", "hi": "यहाँ जारी रखने के लिए हदीस पढ़ें।", "bn": "এখান থেকে চালিয়ে যেতে একটি হাদিস পড়ুন।"][language] ?? Self.emptyMessage
    }
    var localizedLockMessage: String {
        ["ar": "افتح قفل الجهاز لمتابعة القراءة.", "ur": "مطالعہ جاری رکھنے کے لیے آلہ کھولیں۔", "ru": "Разблокируйте устройство, чтобы продолжить чтение.", "fr": "Déverrouillez l’appareil pour reprendre la lecture.", "es": "Desbloquea el dispositivo para continuar leyendo.", "pt": "Desbloqueie o dispositivo para continuar lendo.", "hi": "पढ़ना जारी रखने के लिए डिवाइस अनलॉक करें।", "bn": "পড়া চালিয়ে যেতে ডিভাইস আনলক করুন।"][language] ?? Self.lockMessage
    }
    var staleMessage: String { DailyWidgetCopy.stale(locale) }
}

struct WidgetProgressGaugeValue: Equatable {
    let value: Double?

    init(fraction: Double?) {
        value = fraction.map { (min(1, max(0, $0)) * 100).rounded() / 100 }
    }

    var percent: Int? { value.map { Int(($0 * 100).rounded()) } }
}

extension WidgetContinueSnapshot {
    var presentation: ContinueWidgetPresentation {
        ContinueWidgetPresentation(reference: reference, progressFraction: progressFraction, progressOrdinal: progressOrdinal, progressTotal: progressTotal, locale: locale)
    }
}

enum WidgetSnapshotStore {
    static let suiteName = "group.com.hadithly.app"
    private static let dailyKey = "widget.daily.v3"
    private static let continueKey = "widget.continue.v3"
    private static let legacyContinueKey = "widget.continue.v2"
    private static let uiLocaleKey = "widget.uiLocale.v1"

    private static var defaults: UserDefaults { UserDefaults(suiteName: suiteName) ?? .standard }

    static func saveDaily(_ snapshot: WidgetDailySnapshot?) {
        write(snapshot, key: dailyKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "DailyHadithWidget")
    }

    @discardableResult
    static func markDailyOffline(locale: String, timezone: String) -> Bool {
        guard var snapshot = daily(), snapshot.locale == locale, snapshot.timezone == timezone else {
            saveDaily(nil)
            return false
        }
        snapshot = WidgetDailySnapshot(
            collectionSlug: snapshot.collectionSlug, providerHadithId: snapshot.providerHadithId,
            reference: snapshot.reference, text: snapshot.text, arabicText: snapshot.arabicText, locale: snapshot.locale,
            arabicVisible: snapshot.arabicVisible, translationVisible: snapshot.translationVisible,
            isAI: snapshot.isAI, sourceScope: snapshot.sourceScope, localDate: snapshot.localDate,
            timezone: snapshot.timezone, isOffline: true, updatedAt: snapshot.updatedAt
        )
        saveDaily(snapshot)
        return true
    }

    static func saveContinue(_ snapshot: WidgetContinueSnapshot?) {
        defaults.removeObject(forKey: legacyContinueKey)
        write(snapshot, key: continueKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "ContinueReadingWidget")
    }

    static func saveUILocale(_ locale: String) {
        defaults.set(locale, forKey: uiLocaleKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "ContinueReadingWidget")
    }

    static func uiLocale() -> String { defaults.string(forKey: uiLocaleKey) ?? Locale.current.identifier }

    static func daily() -> WidgetDailySnapshot? { read(WidgetDailySnapshot.self, key: dailyKey) }
    static func `continue`() -> WidgetContinueSnapshot? {
        defaults.removeObject(forKey: legacyContinueKey)
        return read(WidgetContinueSnapshot.self, key: continueKey)
    }

    private static func write<T: Encodable>(_ value: T?, key: String) {
        guard let value else { defaults.removeObject(forKey: key); return }
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

enum WidgetRefreshPolicy {
    static let maximumAge: TimeInterval = 36 * 60 * 60
    static func isStale(_ date: Date, now: Date = .now) -> Bool {
        now.timeIntervalSince(date) > maximumAge
    }

    static func isStale(_ snapshot: WidgetDailySnapshot, now: Date = .now) -> Bool {
        guard let timezone = TimeZone(identifier: snapshot.timezone) else { return true }
        let formatter = DateFormatter()
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd"
        return snapshot.isOffline || formatter.string(from: now) != snapshot.localDate ||
            now.timeIntervalSince(snapshot.updatedAt) > maximumAge
    }

    static func nextRefresh(after snapshot: WidgetDailySnapshot?, now: Date = .now) -> Date {
        guard let snapshot, let timezone = TimeZone(identifier: snapshot.timezone) else {
            return now.addingTimeInterval(maximumAge)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(maximumAge)
        let nextLocalDay = calendar.startOfDay(for: tomorrow)
        return min(nextLocalDay, snapshot.updatedAt.addingTimeInterval(maximumAge))
    }
}
