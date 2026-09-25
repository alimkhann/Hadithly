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
    static func title(_ locale: String) -> String {
        switch Locale(identifier: locale).language.languageCode?.identifier {
        case "ar": "الحديث اليومي"
        case "ur": "آج کی حدیث"
        default: "Daily Hadith"
        }
    }
    static func empty(_ locale: String) -> String {
        switch Locale(identifier: locale).language.languageCode?.identifier {
        case "ar": "افتح حديثلي لتحضير حديث اليوم."
        case "ur": "آج کی حدیث تیار کرنے کے لیے حدیثلی کھولیں۔"
        default: "Open Hadithly to prepare today’s hadith."
        }
    }
    static func locked(_ locale: String) -> String {
        switch Locale(identifier: locale).language.languageCode?.identifier {
        case "ar": "افتح قفل الجهاز لعرض حديث اليوم."
        case "ur": "آج کی حدیث دیکھنے کے لیے آلہ کھولیں۔"
        default: "Unlock Hadithly to view today’s hadith."
        }
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
    var title: String { language == "ar" ? "متابعة القراءة" : language == "ur" ? "مطالعہ جاری رکھیں" : "Continue Reading" }
    var resumeText: String { language == "ar" ? "استئناف القراءة" : language == "ur" ? "مطالعہ جاری رکھیں" : "Resume reading" }
    var progressLabel: String {
        guard let progressOrdinal else { return resumeText }
        guard let progressTotal, progressTotal > 0 else {
            switch language {
            case "ar": return "التقدم: الحديث \(progressOrdinal)"
            case "ur": return "پیش رفت: حدیث \(progressOrdinal)"
            default: return "Progress: Hadith \(progressOrdinal)"
            }
        }
        switch language {
        case "ar": return "الحديث \(progressOrdinal) من \(progressTotal)"
        case "ur": return "حدیث \(progressOrdinal)، کل \(progressTotal)"
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
    var localizedEmptyMessage: String { language == "ar" ? "اقرأ حديثًا للمتابعة هنا." : language == "ur" ? "یہاں سے جاری رکھنے کے لیے حدیث پڑھیں۔" : Self.emptyMessage }
    var localizedLockMessage: String { language == "ar" ? "افتح قفل الجهاز لمتابعة القراءة." : language == "ur" ? "مطالعہ جاری رکھنے کے لیے آلہ کھولیں۔" : Self.lockMessage }
    var staleMessage: String { language == "ar" ? "سيُتحقق من الموضع عند الفتح" : language == "ur" ? "کھولنے پر مقام کی جانچ ہوگی" : "Position will be checked when opened" }
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
