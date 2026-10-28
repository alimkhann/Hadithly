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

// BEGIN GENERATED WIDGET COPY
// Generated interface drafts; native review pending.
enum WidgetCopy {
    enum Key: String { case dailyTitle, dailyEmpty, dailyLocked, dailyAI, dailyOffline, dailyStale, continueTitle, continueResume, continueProgressPartial, continueProgressTotal, continueEmpty, continueLocked, continueStale, dailyGalleryDescription, continueGalleryDescription, notificationChannelTitle, notificationChannelDescription }
    private static let values: [String: [Key: String]] = [
        "en": [.dailyTitle: "Daily Hadith", .dailyEmpty: "Open Hadithly to prepare today’s hadith.", .dailyLocked: "Unlock Hadithly to view today’s hadith.", .dailyAI: "AI translation", .dailyOffline: "Saved offline copy", .dailyStale: "Update when opened", .continueTitle: "Continue Reading", .continueResume: "Resume reading", .continueProgressPartial: "Progress: Hadith %1$@", .continueProgressTotal: "Hadith %1$@ of %2$@", .continueEmpty: "Read a hadith to continue here.", .continueLocked: "Unlock your device to resume reading.", .continueStale: "Position will be checked when opened", .dailyGalleryDescription: "A private, cached reading prompt for today.", .continueGalleryDescription: "Resume your private reading position.", .notificationChannelTitle: "Daily Hadith", .notificationChannelDescription: "The daily hadith reminder"],
        "ar": [.dailyTitle: "الحديث اليومي", .dailyEmpty: "افتح حديثلي لتحضير حديث اليوم.", .dailyLocked: "افتح قفل الجهاز لعرض حديث اليوم.", .dailyAI: "ترجمة بالذكاء الاصطناعي", .dailyOffline: "نسخة محفوظة دون اتصال", .dailyStale: "حدّث عند الفتح", .continueTitle: "متابعة القراءة", .continueResume: "استئناف القراءة", .continueProgressPartial: "التقدم: الحديث %1$@", .continueProgressTotal: "الحديث %1$@ من %2$@", .continueEmpty: "اقرأ حديثًا للمتابعة هنا.", .continueLocked: "افتح قفل الجهاز لمتابعة القراءة.", .continueStale: "سيُتحقق من الموضع عند الفتح", .dailyGalleryDescription: "تذكير خاص بالقراءة اليومية من نسخة مخزنة.", .continueGalleryDescription: "تابع القراءة من موضعك الخاص.", .notificationChannelTitle: "الحديث اليومي", .notificationChannelDescription: "تذكير الحديث اليومي"],
        "ru": [.dailyTitle: "Хадис дня", .dailyEmpty: "Откройте Hadithly, чтобы подготовить хадис дня.", .dailyLocked: "Разблокируйте Hadithly, чтобы увидеть хадис дня.", .dailyAI: "Перевод ИИ", .dailyOffline: "Сохранённая офлайн-копия", .dailyStale: "Обновится при открытии", .continueTitle: "Продолжить чтение", .continueResume: "Продолжить чтение", .continueProgressPartial: "Прогресс: хадис %1$@", .continueProgressTotal: "Хадис %1$@ из %2$@", .continueEmpty: "Прочитайте хадис, чтобы продолжить здесь.", .continueLocked: "Разблокируйте устройство, чтобы продолжить чтение.", .continueStale: "Позиция будет проверена при открытии", .dailyGalleryDescription: "Личное напоминание о чтении дня из сохранённой копии.", .continueGalleryDescription: "Продолжайте с личной позиции чтения.", .notificationChannelTitle: "Хадис дня", .notificationChannelDescription: "Напоминание о хадисе дня"],
        "kk": [.dailyTitle: "Бүгінгі хадис", .dailyEmpty: "Бүгінгі хадисті дайындау үшін Hadithly ашыңыз.", .dailyLocked: "Бүгінгі хадисті көру үшін Hadithly құлпын ашыңыз.", .dailyAI: "AI аудармасы", .dailyOffline: "Желіден тыс сақталған көшірме", .dailyStale: "Ашқанда жаңартылады", .continueTitle: "Оқуды жалғастыру", .continueResume: "Оқуды жалғастыру", .continueProgressPartial: "Оқу барысы: %1$@-хадис", .continueProgressTotal: "%2$@ хадистің %1$@-і", .continueEmpty: "Оқуды осы жерден жалғастыру үшін хадис оқыңыз.", .continueLocked: "Оқуды жалғастыру үшін құрылғының құлпын ашыңыз.", .continueStale: "Ашылғанда оқу орны тексеріледі", .dailyGalleryDescription: "Бүгінгі оқуға арналған жеке, сақталған еске салғыш.", .continueGalleryDescription: "Жеке оқу орныңыздан жалғастырыңыз.", .notificationChannelTitle: "Бүгінгі хадис", .notificationChannelDescription: "Күнделікті хадис еске салғышы"],
        "ky": [.dailyTitle: "Бүгүнкү хадис", .dailyEmpty: "Бүгүнкү хадисти даярдоо үчүн Hadithly'ди ачыңыз.", .dailyLocked: "Бүгүнкү хадисти көрүү үчүн Hadithly кулпусун ачыңыз.", .dailyAI: "AI котормосу", .dailyOffline: "Офлайн сакталган көчүрмө", .dailyStale: "Ачканда жаңыланат", .continueTitle: "Окууну улантуу", .continueResume: "Окууну улантуу", .continueProgressPartial: "Окуу жүрүшү: %1$@-хадис", .continueProgressTotal: "%2$@ хадистин %1$@-и", .continueEmpty: "Окууну бул жерден улантуу үчүн хадис окуңуз.", .continueLocked: "Окууну улантуу үчүн түзмөктүн кулпусун ачыңыз.", .continueStale: "Ачылганда окуу орду текшерилет", .dailyGalleryDescription: "Бүгүнкү окууга арналган жеке, сакталган эскертме.", .continueGalleryDescription: "Жеке окуу ордуңуздан улантыңыз.", .notificationChannelTitle: "Бүгүнкү хадис", .notificationChannelDescription: "Күнүмдүк хадис эскертмеси"],
        "uz": [.dailyTitle: "Bugungi hadis", .dailyEmpty: "Bugungi hadisni tayyorlash uchun Hadithly’ni oching.", .dailyLocked: "Bugungi hadisni ko‘rish uchun Hadithly qulfini oching.", .dailyAI: "SI tarjimasi", .dailyOffline: "Oflayn saqlangan nusxa", .dailyStale: "Ochilganda yangilanadi", .continueTitle: "O‘qishni davom ettirish", .continueResume: "O‘qishni davom ettirish", .continueProgressPartial: "Oʻqish jarayoni: %1$@-hadis", .continueProgressTotal: "%2$@ tadan %1$@-hadis", .continueEmpty: "Bu yerdan davom ettirish uchun hadis oʻqing.", .continueLocked: "Oʻqishni davom ettirish uchun qurilma qulfini oching.", .continueStale: "Ochilganda oʻqish joyi tekshiriladi", .dailyGalleryDescription: "Bugungi oʻqish uchun shaxsiy, saqlangan eslatma.", .continueGalleryDescription: "Shaxsiy oʻqish joyingizdan davom eting.", .notificationChannelTitle: "Bugungi hadis", .notificationChannelDescription: "Kundalik hadis eslatmasi"],
        "tr": [.dailyTitle: "Günün hadisi", .dailyEmpty: "Bugünün hadisini hazırlamak için Hadithly’yi açın.", .dailyLocked: "Bugünün hadisini görmek için Hadithly’nin kilidini açın.", .dailyAI: "Yapay zekâ çevirisi", .dailyOffline: "Çevrimdışı kaydedilen kopya", .dailyStale: "Açıldığında güncellenir", .continueTitle: "Okumaya devam et", .continueResume: "Okumaya devam et", .continueProgressPartial: "İlerleme: %1$@. hadis", .continueProgressTotal: "%2$@ hadisten %1$@. hadis", .continueEmpty: "Buradan devam etmek için bir hadis okuyun.", .continueLocked: "Okumaya devam etmek için cihazın kilidini açın.", .continueStale: "Açıldığında okuma konumu kontrol edilir", .dailyGalleryDescription: "Bugün için özel, önbelleğe alınmış bir okuma hatırlatıcısı.", .continueGalleryDescription: "Kişisel okuma konumunuzdan devam edin.", .notificationChannelTitle: "Günün hadisi", .notificationChannelDescription: "Günlük hadis hatırlatıcısı"],
        "id": [.dailyTitle: "Hadis hari ini", .dailyEmpty: "Buka Hadithly untuk menyiapkan hadis hari ini.", .dailyLocked: "Buka kunci Hadithly untuk melihat hadis hari ini.", .dailyAI: "Terjemahan AI", .dailyOffline: "Salinan tersimpan offline", .dailyStale: "Diperbarui saat dibuka", .continueTitle: "Lanjutkan membaca", .continueResume: "Lanjutkan membaca", .continueProgressPartial: "Progres: Hadis %1$@", .continueProgressTotal: "Hadis %1$@ dari %2$@", .continueEmpty: "Baca hadis untuk melanjutkan di sini.", .continueLocked: "Buka kunci perangkat untuk melanjutkan membaca.", .continueStale: "Posisi akan diperiksa saat dibuka", .dailyGalleryDescription: "Pengingat bacaan pribadi hari ini dari salinan tersimpan.", .continueGalleryDescription: "Lanjutkan dari posisi bacaan pribadi Anda.", .notificationChannelTitle: "Hadis hari ini", .notificationChannelDescription: "Pengingat hadis harian"],
        "ur": [.dailyTitle: "آج کی حدیث", .dailyEmpty: "آج کی حدیث تیار کرنے کے لیے حدیثلی کھولیں۔", .dailyLocked: "آج کی حدیث دیکھنے کے لیے آلہ کھولیں۔", .dailyAI: "AI ترجمہ", .dailyOffline: "آف لائن محفوظ نقل", .dailyStale: "کھولنے پر اپ ڈیٹ ہوگا", .continueTitle: "مطالعہ جاری رکھیں", .continueResume: "مطالعہ جاری رکھیں", .continueProgressPartial: "پیش رفت: حدیث %1$@", .continueProgressTotal: "%2$@ میں سے حدیث %1$@", .continueEmpty: "یہاں سے جاری رکھنے کے لیے حدیث پڑھیں۔", .continueLocked: "مطالعہ جاری رکھنے کے لیے آلہ کھولیں۔", .continueStale: "کھولنے پر مقام کی جانچ ہوگی", .dailyGalleryDescription: "آج کے مطالعے کی محفوظ نقل سے نجی یاد دہانی۔", .continueGalleryDescription: "اپنے ذاتی مطالعے کے مقام سے جاری رکھیں۔", .notificationChannelTitle: "آج کی حدیث", .notificationChannelDescription: "روزانہ حدیث کی یاد دہانی"],
        "fr": [.dailyTitle: "Hadith du jour", .dailyEmpty: "Ouvrez Hadithly pour préparer le hadith du jour.", .dailyLocked: "Déverrouillez Hadithly pour voir le hadith du jour.", .dailyAI: "Traduction par IA", .dailyOffline: "Copie enregistrée hors ligne", .dailyStale: "Mise à jour à l’ouverture", .continueTitle: "Continuer la lecture", .continueResume: "Reprendre la lecture", .continueProgressPartial: "Progression : hadith %1$@", .continueProgressTotal: "Hadith %1$@ sur %2$@", .continueEmpty: "Lisez un hadith pour continuer ici.", .continueLocked: "Déverrouillez l’appareil pour reprendre la lecture.", .continueStale: "La position sera vérifiée à l’ouverture", .dailyGalleryDescription: "Un rappel de lecture privé pour aujourd’hui, conservé en cache.", .continueGalleryDescription: "Reprenez votre position de lecture privée.", .notificationChannelTitle: "Hadith du jour", .notificationChannelDescription: "Le rappel du hadith du jour"],
        "es": [.dailyTitle: "Hadiz del día", .dailyEmpty: "Abre Hadithly para preparar el hadiz del día.", .dailyLocked: "Desbloquea Hadithly para ver el hadiz del día.", .dailyAI: "Traducción con IA", .dailyOffline: "Copia guardada sin conexión", .dailyStale: "Se actualizará al abrir", .continueTitle: "Continuar leyendo", .continueResume: "Reanudar la lectura", .continueProgressPartial: "Progreso: hadiz %1$@", .continueProgressTotal: "Hadiz %1$@ de %2$@", .continueEmpty: "Lee un hadiz para continuar aquí.", .continueLocked: "Desbloquea el dispositivo para continuar leyendo.", .continueStale: "La posición se comprobará al abrir", .dailyGalleryDescription: "Un recordatorio privado de lectura del día desde una copia guardada.", .continueGalleryDescription: "Retoma tu posición de lectura privada.", .notificationChannelTitle: "Hadiz del día", .notificationChannelDescription: "El recordatorio del hadiz del día"],
        "pt": [.dailyTitle: "Hadith do dia", .dailyEmpty: "Abra o Hadithly para preparar o hadith do dia.", .dailyLocked: "Desbloqueie o Hadithly para ver o hadith do dia.", .dailyAI: "Tradução por IA", .dailyOffline: "Cópia salva off-line", .dailyStale: "Atualiza ao abrir", .continueTitle: "Continuar lendo", .continueResume: "Retomar a leitura", .continueProgressPartial: "Progresso: hadith %1$@", .continueProgressTotal: "Hadith %1$@ de %2$@", .continueEmpty: "Leia um hadith para continuar aqui.", .continueLocked: "Desbloqueie o dispositivo para continuar lendo.", .continueStale: "A posição será verificada ao abrir", .dailyGalleryDescription: "Um lembrete privado de leitura do dia a partir de uma cópia salva.", .continueGalleryDescription: "Retome sua posição de leitura privada.", .notificationChannelTitle: "Hadith do dia", .notificationChannelDescription: "O lembrete do hadith do dia"],
        "sw": [.dailyTitle: "Hadithi ya leo", .dailyEmpty: "Fungua Hadithly ili kuandaa hadithi ya leo.", .dailyLocked: "Fungua Hadithly ili kuona hadithi ya leo.", .dailyAI: "Tafsiri ya AI", .dailyOffline: "Nakala iliyohifadhiwa nje ya mtandao", .dailyStale: "Itasasishwa ikifunguliwa", .continueTitle: "Endelea kusoma", .continueResume: "Endelea kusoma", .continueProgressPartial: "Maendeleo: Hadithi %1$@", .continueProgressTotal: "Hadithi ya %1$@ kati ya %2$@", .continueEmpty: "Soma hadithi ili kuendelea hapa.", .continueLocked: "Fungua kifaa ili kuendelea kusoma.", .continueStale: "Mahali pa kusoma patakaguliwa ukifungua", .dailyGalleryDescription: "Kikumbusho binafsi cha usomaji wa leo kutoka nakala iliyohifadhiwa.", .continueGalleryDescription: "Endelea kutoka mahali pako binafsi pa kusoma.", .notificationChannelTitle: "Hadithi ya leo", .notificationChannelDescription: "Kikumbusho cha hadithi ya kila siku"],
        "hi": [.dailyTitle: "आज की हदीस", .dailyEmpty: "आज की हदीस तैयार करने के लिए Hadithly खोलें।", .dailyLocked: "आज की हदीस देखने के लिए Hadithly अनलॉक करें।", .dailyAI: "AI अनुवाद", .dailyOffline: "ऑफ़लाइन सहेजी गई प्रति", .dailyStale: "खोलने पर अपडेट होगा", .continueTitle: "पढ़ना जारी रखें", .continueResume: "पढ़ना जारी रखें", .continueProgressPartial: "प्रगति: हदीस %1$@", .continueProgressTotal: "%2$@ में से हदीस %1$@", .continueEmpty: "यहाँ जारी रखने के लिए हदीस पढ़ें।", .continueLocked: "पढ़ना जारी रखने के लिए डिवाइस अनलॉक करें।", .continueStale: "खोलने पर पढ़ने की स्थिति जाँची जाएगी", .dailyGalleryDescription: "सहेजी गई प्रति से आज पढ़ने का निजी रिमाइंडर।", .continueGalleryDescription: "अपने निजी पठन स्थान से जारी रखें।", .notificationChannelTitle: "आज की हदीस", .notificationChannelDescription: "दैनिक हदीस का रिमाइंडर"],
        "bn": [.dailyTitle: "আজকের হাদিস", .dailyEmpty: "আজকের হাদিস প্রস্তুত করতে Hadithly খুলুন।", .dailyLocked: "আজকের হাদিস দেখতে Hadithly আনলক করুন।", .dailyAI: "AI অনুবাদ", .dailyOffline: "অফলাইনে সংরক্ষিত কপি", .dailyStale: "খুললে আপডেট হবে", .continueTitle: "পড়া চালিয়ে যান", .continueResume: "পড়া চালিয়ে যান", .continueProgressPartial: "অগ্রগতি: হাদিস %1$@", .continueProgressTotal: "%2$@টির মধ্যে হাদিস %1$@", .continueEmpty: "এখান থেকে চালিয়ে যেতে একটি হাদিস পড়ুন।", .continueLocked: "পড়া চালিয়ে যেতে ডিভাইস আনলক করুন।", .continueStale: "খুললে পড়ার অবস্থান যাচাই করা হবে", .dailyGalleryDescription: "সঞ্চিত কপি থেকে আজকের পড়ার ব্যক্তিগত স্মরণিকা।", .continueGalleryDescription: "আপনার ব্যক্তিগত পড়ার অবস্থান থেকে চালিয়ে যান।", .notificationChannelTitle: "আজকের হাদিস", .notificationChannelDescription: "দৈনিক হাদিসের স্মরণিকা"]
    ]
    static func text(_ key: Key, locale: String) -> String {
        let language = Locale(identifier: locale).language.languageCode?.identifier ?? "en"
        return values[language]?[key] ?? values["en"]![key]!
    }
    static func format(_ key: Key, locale: String, numbers: Int...) -> String {
        let localeValue = Locale(identifier: locale)
        let arguments = numbers.map { $0.formatted(.number.locale(localeValue)) as CVarArg }
        return String(format: text(key, locale: locale), locale: localeValue, arguments: arguments)
    }
}
// END GENERATED WIDGET COPY

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
    var title: String { WidgetCopy.text(.continueTitle, locale: locale) }
    var resumeText: String { WidgetCopy.text(.continueResume, locale: locale) }
    var progressLabel: String {
        guard let progressOrdinal else { return resumeText }
        guard let progressTotal, progressTotal > 0 else { return WidgetCopy.format(.continueProgressPartial, locale: locale, numbers: progressOrdinal) }
        return WidgetCopy.format(.continueProgressTotal, locale: locale, numbers: progressOrdinal, progressTotal)
    }
    var compactLines: [String] { [reference, progressLabel] }
    var accessoryInlineText: String { resumeText }
    var isRightToLeft: Bool { Locale.Language(identifier: locale).characterDirection == .rightToLeft }
    var localizedEmptyMessage: String { WidgetCopy.text(.continueEmpty, locale: locale) }
    var localizedLockMessage: String { WidgetCopy.text(.continueLocked, locale: locale) }
    var staleMessage: String { WidgetCopy.text(.continueStale, locale: locale) }
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
