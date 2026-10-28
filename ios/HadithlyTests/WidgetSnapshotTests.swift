import XCTest
@testable import Hadithly

final class WidgetSnapshotTests: XCTestCase {
    func testAllWidgetLocalesHaveNativeCopyAndPreserveReferences() {
        for (locale, title, empty, continueEmpty, locked, offline) in [
            ("en", "Daily Hadith", "Open Hadithly to prepare today’s hadith.", "Read a hadith to continue here.", "Unlock your device to resume reading.", "Saved offline copy"),
            ("ar", "الحديث اليومي", "افتح حديثلي لتحضير حديث اليوم.", "اقرأ حديثًا للمتابعة هنا.", "افتح قفل الجهاز لمتابعة القراءة.", "نسخة محفوظة دون اتصال"),
            ("ru", "Хадис дня", "Откройте Hadithly, чтобы подготовить хадис дня.", "Прочитайте хадис, чтобы продолжить здесь.", "Разблокируйте устройство, чтобы продолжить чтение.", "Сохранённая офлайн-копия"),
            ("kk", "Бүгінгі хадис", "Бүгінгі хадисті дайындау үшін Hadithly ашыңыз.", "Оқуды осы жерден жалғастыру үшін хадис оқыңыз.", "Оқуды жалғастыру үшін құрылғының құлпын ашыңыз.", "Желіден тыс сақталған көшірме"),
            ("ky", "Бүгүнкү хадис", "Бүгүнкү хадисти даярдоо үчүн Hadithly'ди ачыңыз.", "Окууну бул жерден улантуу үчүн хадис окуңуз.", "Окууну улантуу үчүн түзмөктүн кулпусун ачыңыз.", "Офлайн сакталган көчүрмө"),
            ("uz", "Bugungi hadis", "Bugungi hadisni tayyorlash uchun Hadithly’ni oching.", "Bu yerdan davom ettirish uchun hadis oʻqing.", "Oʻqishni davom ettirish uchun qurilma qulfini oching.", "Oflayn saqlangan nusxa"),
            ("tr", "Günün hadisi", "Bugünün hadisini hazırlamak için Hadithly’yi açın.", "Buradan devam etmek için bir hadis okuyun.", "Okumaya devam etmek için cihazın kilidini açın.", "Çevrimdışı kaydedilen kopya"),
            ("id", "Hadis hari ini", "Buka Hadithly untuk menyiapkan hadis hari ini.", "Baca hadis untuk melanjutkan di sini.", "Buka kunci perangkat untuk melanjutkan membaca.", "Salinan tersimpan offline"),
            ("ur", "آج کی حدیث", "آج کی حدیث تیار کرنے کے لیے حدیثلی کھولیں۔", "یہاں سے جاری رکھنے کے لیے حدیث پڑھیں۔", "مطالعہ جاری رکھنے کے لیے آلہ کھولیں۔", "آف لائن محفوظ نقل"),
            ("fr", "Hadith du jour", "Ouvrez Hadithly pour préparer le hadith du jour.", "Lisez un hadith pour continuer ici.", "Déverrouillez l’appareil pour reprendre la lecture.", "Copie enregistrée hors ligne"),
            ("es-419", "Hadiz del día", "Abre Hadithly para preparar el hadiz del día.", "Lee un hadiz para continuar aquí.", "Desbloquea el dispositivo para continuar leyendo.", "Copia guardada sin conexión"),
            ("pt-BR", "Hadith do dia", "Abra o Hadithly para preparar o hadith do dia.", "Leia um hadith para continuar aqui.", "Desbloqueie o dispositivo para continuar lendo.", "Cópia salva off-line"),
            ("sw", "Hadithi ya leo", "Fungua Hadithly ili kuandaa hadithi ya leo.", "Soma hadithi ili kuendelea hapa.", "Fungua kifaa ili kuendelea kusoma.", "Nakala iliyohifadhiwa nje ya mtandao"),
            ("hi", "आज की हदीस", "आज की हदीस तैयार करने के लिए Hadithly खोलें।", "यहाँ जारी रखने के लिए हदीस पढ़ें।", "पढ़ना जारी रखने के लिए डिवाइस अनलॉक करें।", "ऑफ़लाइन सहेजी गई प्रति"),
            ("bn", "আজকের হাদিস", "আজকের হাদিস প্রস্তুত করতে Hadithly খুলুন।", "এখান থেকে চালিয়ে যেতে একটি হাদিস পড়ুন।", "পড়া চালিয়ে যেতে ডিভাইস আনলক করুন।", "অফলাইনে সংরক্ষিত কপি")
        ] {
            XCTAssertEqual(WidgetCopy.text(.dailyTitle, locale: locale), title)
            XCTAssertEqual(WidgetCopy.text(.dailyEmpty, locale: locale), empty)
            XCTAssertEqual(WidgetCopy.text(.dailyOffline, locale: locale), offline)
            let reference = "Original source · Hadith 57"
            let full = ContinueWidgetPresentation(reference: reference, progressFraction: 0.57, progressOrdinal: 57, progressTotal: 100, locale: locale)
            XCTAssertEqual(full.reference, reference)
            XCTAssertEqual(full.localizedEmptyMessage, continueEmpty)
            XCTAssertEqual(full.localizedLockMessage, locked)
            XCTAssertFalse(full.title.isEmpty)
            XCTAssertFalse(full.progressLabel.isEmpty)
            let absent = ContinueWidgetPresentation(reference: reference, progressFraction: nil, progressOrdinal: nil, progressTotal: nil, locale: locale)
            XCTAssertEqual(absent.progressLabel, absent.resumeText)
            for key in [WidgetCopy.Key.dailyLocked, .dailyAI, .dailyStale, .continueStale, .dailyGalleryDescription, .continueGalleryDescription] {
                XCTAssertFalse(WidgetCopy.text(key, locale: locale).isEmpty)
            }
        }
        XCTAssertEqual(WidgetCopy.text(.dailyTitle, locale: "fr-CA"), WidgetCopy.text(.dailyTitle, locale: "fr"))
        XCTAssertEqual(WidgetCopy.text(.dailyTitle, locale: "id-ID"), WidgetCopy.text(.dailyTitle, locale: "id"))
        XCTAssertEqual(WidgetCopy.text(.dailyTitle, locale: "zz-ZZ"), WidgetCopy.text(.dailyTitle, locale: "en"))
    }

    func testSnapshotAtRefreshBudgetIsFresh() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(WidgetRefreshPolicy.isStale(now.addingTimeInterval(-WidgetRefreshPolicy.maximumAge), now: now))
    }

    func testSnapshotBeyondRefreshBudgetIsStale() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(WidgetRefreshPolicy.isStale(now.addingTimeInterval(-WidgetRefreshPolicy.maximumAge - 1), now: now))
    }

    func testDailySnapshotIsStaleAfterItsLocalDayChanges() {
        let snapshot = WidgetDailySnapshot(
            collectionSlug: "bukhari", providerHadithId: "1", reference: "Bukhari · 1",
            text: "Text", arabicText: "متن", locale: "ur", arabicVisible: true, translationVisible: true, isAI: true, sourceScope: "Sahih collection scope · Sunnah.now",
            localDate: "2026-09-19", timezone: "Asia/Almaty", isOffline: false,
            updatedAt: Date(timeIntervalSince1970: 1_758_312_000)
        )
        XCTAssertTrue(WidgetRefreshPolicy.isStale(snapshot, now: Date(timeIntervalSince1970: 1_758_384_000)))
    }

    func testDailyPayloadDoesNotContainPrivateReadingFields() throws {
        let payload = DailyWidgetPayload(
            collectionSlug: "bukhari", providerHadithId: "57", reference: "Bukhari · 57",
            text: "translation", arabicText: "متن", locale: "ur", arabicVisible: true, translationVisible: true, isAI: true, sourceScope: "Sahih collection scope · Sunnah.now",
            localDate: "2026-09-19", timezone: "Asia/Almaty", updatedAt: 1_000
        )
        let encoded = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)
        XCTAssertFalse(encoded.contains("note"))
        XCTAssertFalse(encoded.contains("position"))
        XCTAssertFalse(encoded.contains("account"))
    }

    func testContinueSnapshotContainsPresentationOnly() throws {
        let snapshot = WidgetContinueSnapshot(
            reference: "Bukhari · Hadith 57", progressFraction: 0.57,
            progressOrdinal: 57, progressTotal: 100, locale: "ur", updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        for forbidden in ["collectionSlug", "providerHadithId", "position", "account", "note", "volumeId", "arabicExcerpt", "translationExcerpt"] {
            XCTAssertFalse(encoded.contains(forbidden), "Continue widget cache must not contain \(forbidden)")
        }
    }

    func testContinuePresentationKeepsOnlyOneReferenceAndSemanticProgress() {
        let presentation = ContinueWidgetPresentation(
            reference: "Bukhari · Hadith 57", progressFraction: 0.57, progressOrdinal: 57, progressTotal: 100, locale: "en"
        )
        XCTAssertEqual(presentation.compactLines, ["Bukhari · Hadith 57", "Hadith 57 of 100"])
        XCTAssertEqual(presentation.accessoryInlineText, "Resume reading")
        XCTAssertFalse(presentation.isRightToLeft)
        XCTAssertEqual(WidgetCopy.text(.continueEmpty, locale: "en"), "Read a hadith to continue here.")
        XCTAssertEqual(WidgetCopy.text(.continueLocked, locale: "en"), "Unlock your device to resume reading.")
    }

    func testContinuePresentationMirrorsUrdu() {
        let presentation = ContinueWidgetPresentation(reference: "Bukhari · Hadith 57", progressFraction: 0.5, progressOrdinal: 57, progressTotal: 100, locale: "ur")
        XCTAssertTrue(presentation.isRightToLeft)
        XCTAssertEqual(presentation.reference, "Bukhari · Hadith 57")
        XCTAssertTrue(presentation.progressLabel.contains("حدیث"))
    }

    func testContinueProgressUsesOrdinalWhenTotalIsUnavailable() {
        let presentation = ContinueWidgetPresentation(reference: "Bukhari · Hadith 57", progressFraction: nil, progressOrdinal: 57, progressTotal: nil, locale: "ar")
        XCTAssertEqual(presentation.progressLabel, WidgetCopy.format(.continueProgressPartial, locale: "ar", numbers: 57))
    }

    func testWidgetEmptyCopyUsesSelectedLocale() {
        XCTAssertEqual(WidgetCopy.text(.dailyTitle, locale: "ar"), "الحديث اليومي")
        XCTAssertEqual(WidgetCopy.text(.dailyEmpty, locale: "ur"), "آج کی حدیث تیار کرنے کے لیے حدیثلی کھولیں۔")
        XCTAssertEqual(ContinueWidgetPresentation(reference: "", progressFraction: nil, progressOrdinal: nil, progressTotal: nil, locale: "ar").localizedEmptyMessage, "اقرأ حديثًا للمتابعة هنا.")
    }

    func testNativeGaugeReceivesAClampedRoundedFraction() {
        XCTAssertEqual(WidgetProgressGaugeValue(fraction: 251.0 / 7277.0).value, 0.03)
        XCTAssertEqual(WidgetProgressGaugeValue(fraction: 3).value, 1)
    }

    func testNativeGaugeHasNoValueWhenProgressIsUnavailable() {
        XCTAssertNil(WidgetProgressGaugeValue(fraction: nil).value)
    }
}
