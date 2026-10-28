package com.hadithly.app.core.widgets

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import com.hadithly.app.core.data.ProgressEntry
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * A deliberately narrow, device-local cache for widgets. Saved notes,
 * account/profile fields, and folder names are not representable here.
 */
@Serializable
data class DailyWidgetSnapshot(
    val collectionSlug: String,
    val providerHadithId: String,
    val reference: String,
    val text: String,
    val arabicText: String = "",
    val locale: String,
    val arabicVisible: Boolean = true,
    val translationVisible: Boolean = true,
    val isAI: Boolean,
    val sourceScope: String,
    val localDate: String,
    val timezone: String,
    val isOffline: Boolean,
    val updatedAt: Long,
)

// BEGIN GENERATED WIDGET COPY
// Generated interface drafts; native review pending.
object WidgetCopy {
    enum class Key { dailyTitle, dailyEmpty, dailyLocked, dailyAI, dailyOffline, dailyStale, continueTitle, continueResume, continueProgressPartial, continueProgressTotal, continueEmpty, continueLocked, continueStale, dailyGalleryDescription, continueGalleryDescription, notificationChannelTitle, notificationChannelDescription }
    private val values = mapOf(
        "en" to mapOf(Key.dailyTitle to "Daily Hadith", Key.dailyEmpty to "Open Hadithly to prepare today’s hadith.", Key.dailyLocked to "Unlock Hadithly to view today’s hadith.", Key.dailyAI to "AI translation", Key.dailyOffline to "Saved offline copy", Key.dailyStale to "Update when opened", Key.continueTitle to "Continue Reading", Key.continueResume to "Resume reading", Key.continueProgressPartial to "Progress: Hadith %1\$s", Key.continueProgressTotal to "Hadith %1\$s of %2\$s", Key.continueEmpty to "Read a hadith to continue here.", Key.continueLocked to "Unlock your device to resume reading.", Key.continueStale to "Position will be checked when opened", Key.dailyGalleryDescription to "A private, cached reading prompt for today.", Key.continueGalleryDescription to "Resume your private reading position.", Key.notificationChannelTitle to "Daily Hadith", Key.notificationChannelDescription to "The daily hadith reminder"),
        "ar" to mapOf(Key.dailyTitle to "الحديث اليومي", Key.dailyEmpty to "افتح حديثلي لتحضير حديث اليوم.", Key.dailyLocked to "افتح قفل الجهاز لعرض حديث اليوم.", Key.dailyAI to "ترجمة بالذكاء الاصطناعي", Key.dailyOffline to "نسخة محفوظة دون اتصال", Key.dailyStale to "حدّث عند الفتح", Key.continueTitle to "متابعة القراءة", Key.continueResume to "استئناف القراءة", Key.continueProgressPartial to "التقدم: الحديث %1\$s", Key.continueProgressTotal to "الحديث %1\$s من %2\$s", Key.continueEmpty to "اقرأ حديثًا للمتابعة هنا.", Key.continueLocked to "افتح قفل الجهاز لمتابعة القراءة.", Key.continueStale to "سيُتحقق من الموضع عند الفتح", Key.dailyGalleryDescription to "تذكير خاص بالقراءة اليومية من نسخة مخزنة.", Key.continueGalleryDescription to "تابع القراءة من موضعك الخاص.", Key.notificationChannelTitle to "الحديث اليومي", Key.notificationChannelDescription to "تذكير الحديث اليومي"),
        "ru" to mapOf(Key.dailyTitle to "Хадис дня", Key.dailyEmpty to "Откройте Hadithly, чтобы подготовить хадис дня.", Key.dailyLocked to "Разблокируйте Hadithly, чтобы увидеть хадис дня.", Key.dailyAI to "Перевод ИИ", Key.dailyOffline to "Сохранённая офлайн-копия", Key.dailyStale to "Обновится при открытии", Key.continueTitle to "Продолжить чтение", Key.continueResume to "Продолжить чтение", Key.continueProgressPartial to "Прогресс: хадис %1\$s", Key.continueProgressTotal to "Хадис %1\$s из %2\$s", Key.continueEmpty to "Прочитайте хадис, чтобы продолжить здесь.", Key.continueLocked to "Разблокируйте устройство, чтобы продолжить чтение.", Key.continueStale to "Позиция будет проверена при открытии", Key.dailyGalleryDescription to "Личное напоминание о чтении дня из сохранённой копии.", Key.continueGalleryDescription to "Продолжайте с личной позиции чтения.", Key.notificationChannelTitle to "Хадис дня", Key.notificationChannelDescription to "Напоминание о хадисе дня"),
        "kk" to mapOf(Key.dailyTitle to "Бүгінгі хадис", Key.dailyEmpty to "Бүгінгі хадисті дайындау үшін Hadithly ашыңыз.", Key.dailyLocked to "Бүгінгі хадисті көру үшін Hadithly құлпын ашыңыз.", Key.dailyAI to "AI аудармасы", Key.dailyOffline to "Желіден тыс сақталған көшірме", Key.dailyStale to "Ашқанда жаңартылады", Key.continueTitle to "Оқуды жалғастыру", Key.continueResume to "Оқуды жалғастыру", Key.continueProgressPartial to "Оқу барысы: %1\$s-хадис", Key.continueProgressTotal to "%2\$s хадистің %1\$s-і", Key.continueEmpty to "Оқуды осы жерден жалғастыру үшін хадис оқыңыз.", Key.continueLocked to "Оқуды жалғастыру үшін құрылғының құлпын ашыңыз.", Key.continueStale to "Ашылғанда оқу орны тексеріледі", Key.dailyGalleryDescription to "Бүгінгі оқуға арналған жеке, сақталған еске салғыш.", Key.continueGalleryDescription to "Жеке оқу орныңыздан жалғастырыңыз.", Key.notificationChannelTitle to "Бүгінгі хадис", Key.notificationChannelDescription to "Күнделікті хадис еске салғышы"),
        "ky" to mapOf(Key.dailyTitle to "Бүгүнкү хадис", Key.dailyEmpty to "Бүгүнкү хадисти даярдоо үчүн Hadithly'ди ачыңыз.", Key.dailyLocked to "Бүгүнкү хадисти көрүү үчүн Hadithly кулпусун ачыңыз.", Key.dailyAI to "AI котормосу", Key.dailyOffline to "Офлайн сакталган көчүрмө", Key.dailyStale to "Ачканда жаңыланат", Key.continueTitle to "Окууну улантуу", Key.continueResume to "Окууну улантуу", Key.continueProgressPartial to "Окуу жүрүшү: %1\$s-хадис", Key.continueProgressTotal to "%2\$s хадистин %1\$s-и", Key.continueEmpty to "Окууну бул жерден улантуу үчүн хадис окуңуз.", Key.continueLocked to "Окууну улантуу үчүн түзмөктүн кулпусун ачыңыз.", Key.continueStale to "Ачылганда окуу орду текшерилет", Key.dailyGalleryDescription to "Бүгүнкү окууга арналган жеке, сакталган эскертме.", Key.continueGalleryDescription to "Жеке окуу ордуңуздан улантыңыз.", Key.notificationChannelTitle to "Бүгүнкү хадис", Key.notificationChannelDescription to "Күнүмдүк хадис эскертмеси"),
        "uz" to mapOf(Key.dailyTitle to "Bugungi hadis", Key.dailyEmpty to "Bugungi hadisni tayyorlash uchun Hadithly’ni oching.", Key.dailyLocked to "Bugungi hadisni ko‘rish uchun Hadithly qulfini oching.", Key.dailyAI to "SI tarjimasi", Key.dailyOffline to "Oflayn saqlangan nusxa", Key.dailyStale to "Ochilganda yangilanadi", Key.continueTitle to "O‘qishni davom ettirish", Key.continueResume to "O‘qishni davom ettirish", Key.continueProgressPartial to "Oʻqish jarayoni: %1\$s-hadis", Key.continueProgressTotal to "%2\$s tadan %1\$s-hadis", Key.continueEmpty to "Bu yerdan davom ettirish uchun hadis oʻqing.", Key.continueLocked to "Oʻqishni davom ettirish uchun qurilma qulfini oching.", Key.continueStale to "Ochilganda oʻqish joyi tekshiriladi", Key.dailyGalleryDescription to "Bugungi oʻqish uchun shaxsiy, saqlangan eslatma.", Key.continueGalleryDescription to "Shaxsiy oʻqish joyingizdan davom eting.", Key.notificationChannelTitle to "Bugungi hadis", Key.notificationChannelDescription to "Kundalik hadis eslatmasi"),
        "tr" to mapOf(Key.dailyTitle to "Günün hadisi", Key.dailyEmpty to "Bugünün hadisini hazırlamak için Hadithly’yi açın.", Key.dailyLocked to "Bugünün hadisini görmek için Hadithly’nin kilidini açın.", Key.dailyAI to "Yapay zekâ çevirisi", Key.dailyOffline to "Çevrimdışı kaydedilen kopya", Key.dailyStale to "Açıldığında güncellenir", Key.continueTitle to "Okumaya devam et", Key.continueResume to "Okumaya devam et", Key.continueProgressPartial to "İlerleme: %1\$s. hadis", Key.continueProgressTotal to "%2\$s hadisten %1\$s. hadis", Key.continueEmpty to "Buradan devam etmek için bir hadis okuyun.", Key.continueLocked to "Okumaya devam etmek için cihazın kilidini açın.", Key.continueStale to "Açıldığında okuma konumu kontrol edilir", Key.dailyGalleryDescription to "Bugün için özel, önbelleğe alınmış bir okuma hatırlatıcısı.", Key.continueGalleryDescription to "Kişisel okuma konumunuzdan devam edin.", Key.notificationChannelTitle to "Günün hadisi", Key.notificationChannelDescription to "Günlük hadis hatırlatıcısı"),
        "id" to mapOf(Key.dailyTitle to "Hadis hari ini", Key.dailyEmpty to "Buka Hadithly untuk menyiapkan hadis hari ini.", Key.dailyLocked to "Buka kunci Hadithly untuk melihat hadis hari ini.", Key.dailyAI to "Terjemahan AI", Key.dailyOffline to "Salinan tersimpan offline", Key.dailyStale to "Diperbarui saat dibuka", Key.continueTitle to "Lanjutkan membaca", Key.continueResume to "Lanjutkan membaca", Key.continueProgressPartial to "Progres: Hadis %1\$s", Key.continueProgressTotal to "Hadis %1\$s dari %2\$s", Key.continueEmpty to "Baca hadis untuk melanjutkan di sini.", Key.continueLocked to "Buka kunci perangkat untuk melanjutkan membaca.", Key.continueStale to "Posisi akan diperiksa saat dibuka", Key.dailyGalleryDescription to "Pengingat bacaan pribadi hari ini dari salinan tersimpan.", Key.continueGalleryDescription to "Lanjutkan dari posisi bacaan pribadi Anda.", Key.notificationChannelTitle to "Hadis hari ini", Key.notificationChannelDescription to "Pengingat hadis harian"),
        "ur" to mapOf(Key.dailyTitle to "آج کی حدیث", Key.dailyEmpty to "آج کی حدیث تیار کرنے کے لیے حدیثلی کھولیں۔", Key.dailyLocked to "آج کی حدیث دیکھنے کے لیے آلہ کھولیں۔", Key.dailyAI to "AI ترجمہ", Key.dailyOffline to "آف لائن محفوظ نقل", Key.dailyStale to "کھولنے پر اپ ڈیٹ ہوگا", Key.continueTitle to "مطالعہ جاری رکھیں", Key.continueResume to "مطالعہ جاری رکھیں", Key.continueProgressPartial to "پیش رفت: حدیث %1\$s", Key.continueProgressTotal to "%2\$s میں سے حدیث %1\$s", Key.continueEmpty to "یہاں سے جاری رکھنے کے لیے حدیث پڑھیں۔", Key.continueLocked to "مطالعہ جاری رکھنے کے لیے آلہ کھولیں۔", Key.continueStale to "کھولنے پر مقام کی جانچ ہوگی", Key.dailyGalleryDescription to "آج کے مطالعے کی محفوظ نقل سے نجی یاد دہانی۔", Key.continueGalleryDescription to "اپنے ذاتی مطالعے کے مقام سے جاری رکھیں۔", Key.notificationChannelTitle to "آج کی حدیث", Key.notificationChannelDescription to "روزانہ حدیث کی یاد دہانی"),
        "fr" to mapOf(Key.dailyTitle to "Hadith du jour", Key.dailyEmpty to "Ouvrez Hadithly pour préparer le hadith du jour.", Key.dailyLocked to "Déverrouillez Hadithly pour voir le hadith du jour.", Key.dailyAI to "Traduction par IA", Key.dailyOffline to "Copie enregistrée hors ligne", Key.dailyStale to "Mise à jour à l’ouverture", Key.continueTitle to "Continuer la lecture", Key.continueResume to "Reprendre la lecture", Key.continueProgressPartial to "Progression : hadith %1\$s", Key.continueProgressTotal to "Hadith %1\$s sur %2\$s", Key.continueEmpty to "Lisez un hadith pour continuer ici.", Key.continueLocked to "Déverrouillez l’appareil pour reprendre la lecture.", Key.continueStale to "La position sera vérifiée à l’ouverture", Key.dailyGalleryDescription to "Un rappel de lecture privé pour aujourd’hui, conservé en cache.", Key.continueGalleryDescription to "Reprenez votre position de lecture privée.", Key.notificationChannelTitle to "Hadith du jour", Key.notificationChannelDescription to "Le rappel du hadith du jour"),
        "es" to mapOf(Key.dailyTitle to "Hadiz del día", Key.dailyEmpty to "Abre Hadithly para preparar el hadiz del día.", Key.dailyLocked to "Desbloquea Hadithly para ver el hadiz del día.", Key.dailyAI to "Traducción con IA", Key.dailyOffline to "Copia guardada sin conexión", Key.dailyStale to "Se actualizará al abrir", Key.continueTitle to "Continuar leyendo", Key.continueResume to "Reanudar la lectura", Key.continueProgressPartial to "Progreso: hadiz %1\$s", Key.continueProgressTotal to "Hadiz %1\$s de %2\$s", Key.continueEmpty to "Lee un hadiz para continuar aquí.", Key.continueLocked to "Desbloquea el dispositivo para continuar leyendo.", Key.continueStale to "La posición se comprobará al abrir", Key.dailyGalleryDescription to "Un recordatorio privado de lectura del día desde una copia guardada.", Key.continueGalleryDescription to "Retoma tu posición de lectura privada.", Key.notificationChannelTitle to "Hadiz del día", Key.notificationChannelDescription to "El recordatorio del hadiz del día"),
        "pt" to mapOf(Key.dailyTitle to "Hadith do dia", Key.dailyEmpty to "Abra o Hadithly para preparar o hadith do dia.", Key.dailyLocked to "Desbloqueie o Hadithly para ver o hadith do dia.", Key.dailyAI to "Tradução por IA", Key.dailyOffline to "Cópia salva off-line", Key.dailyStale to "Atualiza ao abrir", Key.continueTitle to "Continuar lendo", Key.continueResume to "Retomar a leitura", Key.continueProgressPartial to "Progresso: hadith %1\$s", Key.continueProgressTotal to "Hadith %1\$s de %2\$s", Key.continueEmpty to "Leia um hadith para continuar aqui.", Key.continueLocked to "Desbloqueie o dispositivo para continuar lendo.", Key.continueStale to "A posição será verificada ao abrir", Key.dailyGalleryDescription to "Um lembrete privado de leitura do dia a partir de uma cópia salva.", Key.continueGalleryDescription to "Retome sua posição de leitura privada.", Key.notificationChannelTitle to "Hadith do dia", Key.notificationChannelDescription to "O lembrete do hadith do dia"),
        "sw" to mapOf(Key.dailyTitle to "Hadithi ya leo", Key.dailyEmpty to "Fungua Hadithly ili kuandaa hadithi ya leo.", Key.dailyLocked to "Fungua Hadithly ili kuona hadithi ya leo.", Key.dailyAI to "Tafsiri ya AI", Key.dailyOffline to "Nakala iliyohifadhiwa nje ya mtandao", Key.dailyStale to "Itasasishwa ikifunguliwa", Key.continueTitle to "Endelea kusoma", Key.continueResume to "Endelea kusoma", Key.continueProgressPartial to "Maendeleo: Hadithi %1\$s", Key.continueProgressTotal to "Hadithi ya %1\$s kati ya %2\$s", Key.continueEmpty to "Soma hadithi ili kuendelea hapa.", Key.continueLocked to "Fungua kifaa ili kuendelea kusoma.", Key.continueStale to "Mahali pa kusoma patakaguliwa ukifungua", Key.dailyGalleryDescription to "Kikumbusho binafsi cha usomaji wa leo kutoka nakala iliyohifadhiwa.", Key.continueGalleryDescription to "Endelea kutoka mahali pako binafsi pa kusoma.", Key.notificationChannelTitle to "Hadithi ya leo", Key.notificationChannelDescription to "Kikumbusho cha hadithi ya kila siku"),
        "hi" to mapOf(Key.dailyTitle to "आज की हदीस", Key.dailyEmpty to "आज की हदीस तैयार करने के लिए Hadithly खोलें।", Key.dailyLocked to "आज की हदीस देखने के लिए Hadithly अनलॉक करें।", Key.dailyAI to "AI अनुवाद", Key.dailyOffline to "ऑफ़लाइन सहेजी गई प्रति", Key.dailyStale to "खोलने पर अपडेट होगा", Key.continueTitle to "पढ़ना जारी रखें", Key.continueResume to "पढ़ना जारी रखें", Key.continueProgressPartial to "प्रगति: हदीस %1\$s", Key.continueProgressTotal to "%2\$s में से हदीस %1\$s", Key.continueEmpty to "यहाँ जारी रखने के लिए हदीस पढ़ें।", Key.continueLocked to "पढ़ना जारी रखने के लिए डिवाइस अनलॉक करें।", Key.continueStale to "खोलने पर पढ़ने की स्थिति जाँची जाएगी", Key.dailyGalleryDescription to "सहेजी गई प्रति से आज पढ़ने का निजी रिमाइंडर।", Key.continueGalleryDescription to "अपने निजी पठन स्थान से जारी रखें।", Key.notificationChannelTitle to "आज की हदीस", Key.notificationChannelDescription to "दैनिक हदीस का रिमाइंडर"),
        "bn" to mapOf(Key.dailyTitle to "আজকের হাদিস", Key.dailyEmpty to "আজকের হাদিস প্রস্তুত করতে Hadithly খুলুন।", Key.dailyLocked to "আজকের হাদিস দেখতে Hadithly আনলক করুন।", Key.dailyAI to "AI অনুবাদ", Key.dailyOffline to "অফলাইনে সংরক্ষিত কপি", Key.dailyStale to "খুললে আপডেট হবে", Key.continueTitle to "পড়া চালিয়ে যান", Key.continueResume to "পড়া চালিয়ে যান", Key.continueProgressPartial to "অগ্রগতি: হাদিস %1\$s", Key.continueProgressTotal to "%2\$sটির মধ্যে হাদিস %1\$s", Key.continueEmpty to "এখান থেকে চালিয়ে যেতে একটি হাদিস পড়ুন।", Key.continueLocked to "পড়া চালিয়ে যেতে ডিভাইস আনলক করুন।", Key.continueStale to "খুললে পড়ার অবস্থান যাচাই করা হবে", Key.dailyGalleryDescription to "সঞ্চিত কপি থেকে আজকের পড়ার ব্যক্তিগত স্মরণিকা।", Key.continueGalleryDescription to "আপনার ব্যক্তিগত পড়ার অবস্থান থেকে চালিয়ে যান।", Key.notificationChannelTitle to "আজকের হাদিস", Key.notificationChannelDescription to "দৈনিক হাদিসের স্মরণিকা")
    )
    fun text(key: Key, locale: String): String {
        val language = java.util.Locale.forLanguageTag(locale.replace('_', '-')).language.let { if (it == "in") "id" else it }
        return (values[language] ?: values.getValue("en")).getValue(key)
    }
    fun format(key: Key, locale: String, vararg numbers: Int): String {
        val localeValue = java.util.Locale.forLanguageTag(locale.replace('_', '-'))
        val formatter = java.text.NumberFormat.getIntegerInstance(localeValue)
        return String.format(localeValue, text(key, locale), *numbers.map { formatter.format(it) }.toTypedArray())
    }
}
// END GENERATED WIDGET COPY

/** Public W1 payload; its shape cannot carry notes, accounts, or positions. */
@Serializable
data class DailyWidgetPayload(
    val collectionSlug: String,
    val providerHadithId: String,
    val reference: String,
    val text: String,
    val arabicText: String = "",
    val locale: String,
    val arabicVisible: Boolean = true,
    val translationVisible: Boolean = true,
    val isAI: Boolean,
    val sourceScope: String,
    val localDate: String,
    val timezone: String,
    val updatedAt: Double,
)

@Serializable
data class ContinueWidgetSnapshot(
    val reference: String,
    val progressFraction: Double? = null,
    val progressOrdinal: Int? = null,
    val progressTotal: Int? = null,
    val locale: String,
    val updatedAt: Long,
)

data class ContinueWidgetPresentation(
    val reference: String,
    val progressFraction: Double?,
    val progressOrdinal: Int?,
    val progressTotal: Int?,
    val locale: String,
) {
    val title: String get() = WidgetCopy.text(WidgetCopy.Key.continueTitle, locale)
    val resumeText: String get() = WidgetCopy.text(WidgetCopy.Key.continueResume, locale)
    val progressLabel: String get() = when {
        progressOrdinal == null -> resumeText
        progressTotal == null || progressTotal <= 0 -> WidgetCopy.format(WidgetCopy.Key.continueProgressPartial, locale, progressOrdinal)
        else -> WidgetCopy.format(WidgetCopy.Key.continueProgressTotal, locale, progressOrdinal, progressTotal)
    }
    val compactLines: List<String> get() = listOf(reference, progressLabel)
    val accessoryInlineText: String get() = resumeText
    val isRightToLeft: Boolean get() = com.hadithly.app.core.preferences.LocaleFallback.isRTL(locale)
    val emptyMessage: String get() = WidgetCopy.text(WidgetCopy.Key.continueEmpty, locale)
    val lockMessage: String get() = WidgetCopy.text(WidgetCopy.Key.continueLocked, locale)
    val staleMessage: String get() = WidgetCopy.text(WidgetCopy.Key.continueStale, locale)
}

class WidgetSnapshotStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun saveDaily(payload: DailyWidgetPayload?) {
        val snapshot = payload?.let {
            DailyWidgetSnapshot(
                collectionSlug = it.collectionSlug,
                providerHadithId = it.providerHadithId,
                reference = it.reference, text = it.text, arabicText = it.arabicText, locale = it.locale,
                arabicVisible = it.arabicVisible, translationVisible = it.translationVisible, isAI = it.isAI,
                sourceScope = it.sourceScope, localDate = it.localDate, timezone = it.timezone,
                isOffline = false, updatedAt = it.updatedAt.toLong(),
            )
        }
        prefs.edit().apply {
            if (snapshot == null) remove(DAILY) else putString(DAILY, json.encodeToString(snapshot))
        }.apply()
    }

    fun markDailyOffline(locale: String, timezone: String): Boolean {
        val snapshot = daily()
        if (snapshot == null || snapshot.locale != locale || snapshot.timezone != timezone) {
            saveDaily(null)
            return false
        }
        prefs.edit().putString(DAILY, json.encodeToString(snapshot.copy(isOffline = true))).apply()
        return true
    }

    fun saveContinue(entry: ProgressEntry?, locale: String, progressFraction: Double? = null, progressOrdinal: Int? = null, progressTotal: Int? = null) {
        val hadith = entry?.hadith
        val snapshot = if (entry != null && hadith != null) {
            ContinueWidgetSnapshot(
                reference = hadith.referenceDisplay,
                progressFraction = progressFraction,
                progressOrdinal = progressOrdinal,
                progressTotal = progressTotal,
                locale = locale,
                updatedAt = entry.updatedAt.toLong(),
            )
        } else null
        prefs.edit().apply {
            remove(LEGACY_CONTINUE)
            if (snapshot == null) remove(CONTINUE) else putString(CONTINUE, json.encodeToString(snapshot))
        }.apply()
    }

    fun daily(): DailyWidgetSnapshot? = read(DAILY)
    fun observeDaily() = callbackFlow<DailyWidgetSnapshot?> {
        val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key == DAILY) trySend(daily())
        }
        prefs.registerOnSharedPreferenceChangeListener(listener)
        trySend(daily())
        awaitClose { prefs.unregisterOnSharedPreferenceChangeListener(listener) }
    }.distinctUntilChanged()

    fun continueReading(): ContinueWidgetSnapshot? {
        prefs.edit().remove(LEGACY_CONTINUE).apply()
        return read(CONTINUE)
    }
    fun observeContinue() = callbackFlow<ContinueWidgetSnapshot?> {
        val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key == CONTINUE) trySend(continueReading())
        }
        prefs.registerOnSharedPreferenceChangeListener(listener)
        trySend(continueReading())
        awaitClose { prefs.unregisterOnSharedPreferenceChangeListener(listener) }
    }.distinctUntilChanged()

    private inline fun <reified T> read(key: String): T? =
        prefs.getString(key, null)?.let { runCatching { json.decodeFromString<T>(it) }.getOrNull() }

    private companion object {
        const val PREFS = "hadithly.widgets"
        const val DAILY = "daily.v2"
        const val CONTINUE = "continue.v2"
        const val LEGACY_CONTINUE = "continue.v1"
        val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    }
}

object WidgetRefreshPolicy {
    const val MAX_AGE_MS = 36L * 60L * 60L * 1000L
    fun isStale(updatedAt: Long, now: Long = System.currentTimeMillis()): Boolean = now - updatedAt > MAX_AGE_MS
    fun isStale(snapshot: DailyWidgetSnapshot, now: Long = System.currentTimeMillis()): Boolean {
        val currentDay = java.time.LocalDate.now(java.time.ZoneId.of(snapshot.timezone)).toString()
        return snapshot.isOffline || snapshot.localDate != currentDay || isStale(snapshot.updatedAt, now)
    }
}
