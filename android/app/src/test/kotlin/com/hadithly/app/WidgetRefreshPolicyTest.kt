package com.hadithly.app

import com.hadithly.app.core.widgets.WidgetRefreshPolicy
import com.hadithly.app.core.widgets.DailyWidgetSnapshot
import com.hadithly.app.core.widgets.WidgetCopy
import com.hadithly.app.core.widgets.ContinueWidgetSnapshot
import com.hadithly.app.core.widgets.ContinueWidgetPresentation
import com.hadithly.app.features.widgets.ContinueWidgetSize
import com.hadithly.app.features.widgets.continueWidgetSize
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WidgetRefreshPolicyTest {
    @Test fun allWidgetLocalesHaveCopyAndPreserveReferences() {
        for ((locale, title, empty, continueEmpty, locked) in listOf(
            listOf("en", "Daily Hadith", "Open Hadithly to prepare today’s hadith.", "Read a hadith to continue here.", "Unlock your device to resume reading.", "Saved offline copy"),
            listOf("ar", "الحديث اليومي", "افتح حديثلي لتحضير حديث اليوم.", "اقرأ حديثًا للمتابعة هنا.", "افتح قفل الجهاز لمتابعة القراءة.", "نسخة محفوظة دون اتصال"),
            listOf("ru", "Хадис дня", "Откройте Hadithly, чтобы подготовить хадис дня.", "Прочитайте хадис, чтобы продолжить здесь.", "Разблокируйте устройство, чтобы продолжить чтение.", "Сохранённая офлайн-копия"),
            listOf("kk", "Бүгінгі хадис", "Бүгінгі хадисті дайындау үшін Hadithly ашыңыз.", "Оқуды осы жерден жалғастыру үшін хадис оқыңыз.", "Оқуды жалғастыру үшін құрылғының құлпын ашыңыз.", "Желіден тыс сақталған көшірме"),
            listOf("ky", "Бүгүнкү хадис", "Бүгүнкү хадисти даярдоо үчүн Hadithly'ди ачыңыз.", "Окууну бул жерден улантуу үчүн хадис окуңуз.", "Окууну улантуу үчүн түзмөктүн кулпусун ачыңыз.", "Офлайн сакталган көчүрмө"),
            listOf("uz", "Bugungi hadis", "Bugungi hadisni tayyorlash uchun Hadithly’ni oching.", "Bu yerdan davom ettirish uchun hadis oʻqing.", "Oʻqishni davom ettirish uchun qurilma qulfini oching.", "Oflayn saqlangan nusxa"),
            listOf("tr", "Günün hadisi", "Bugünün hadisini hazırlamak için Hadithly’yi açın.", "Buradan devam etmek için bir hadis okuyun.", "Okumaya devam etmek için cihazın kilidini açın.", "Çevrimdışı kaydedilen kopya"),
            listOf("id", "Hadis hari ini", "Buka Hadithly untuk menyiapkan hadis hari ini.", "Baca hadis untuk melanjutkan di sini.", "Buka kunci perangkat untuk melanjutkan membaca.", "Salinan tersimpan offline"),
            listOf("ur", "آج کی حدیث", "آج کی حدیث تیار کرنے کے لیے حدیثلی کھولیں۔", "یہاں سے جاری رکھنے کے لیے حدیث پڑھیں۔", "مطالعہ جاری رکھنے کے لیے آلہ کھولیں۔", "آف لائن محفوظ نقل"),
            listOf("fr", "Hadith du jour", "Ouvrez Hadithly pour préparer le hadith du jour.", "Lisez un hadith pour continuer ici.", "Déverrouillez l’appareil pour reprendre la lecture.", "Copie enregistrée hors ligne"),
            listOf("es-419", "Hadiz del día", "Abre Hadithly para preparar el hadiz del día.", "Lee un hadiz para continuar aquí.", "Desbloquea el dispositivo para continuar leyendo.", "Copia guardada sin conexión"),
            listOf("pt-BR", "Hadith do dia", "Abra o Hadithly para preparar o hadith do dia.", "Leia um hadith para continuar aqui.", "Desbloqueie o dispositivo para continuar lendo.", "Cópia salva off-line"),
            listOf("sw", "Hadithi ya leo", "Fungua Hadithly ili kuandaa hadithi ya leo.", "Soma hadithi ili kuendelea hapa.", "Fungua kifaa ili kuendelea kusoma.", "Nakala iliyohifadhiwa nje ya mtandao"),
            listOf("hi", "आज की हदीस", "आज की हदीस तैयार करने के लिए Hadithly खोलें।", "यहाँ जारी रखने के लिए हदीस पढ़ें।", "पढ़ना जारी रखने के लिए डिवाइस अनलॉक करें।", "ऑफ़लाइन सहेजी गई प्रति"),
            listOf("bn", "আজকের হাদিস", "আজকের হাদিস প্রস্তুত করতে Hadithly খুলুন।", "এখান থেকে চালিয়ে যেতে একটি হাদিস পড়ুন।", "পড়া চালিয়ে যেতে ডিভাইস আনলক করুন।", "অফলাইনে সংরক্ষিত কপি"),
        ).map { it.take(5) }) {
            org.junit.Assert.assertEquals(title, WidgetCopy.text(WidgetCopy.Key.dailyTitle, locale))
            org.junit.Assert.assertEquals(empty, WidgetCopy.text(WidgetCopy.Key.dailyEmpty, locale))
            val reference = "Original source · Hadith 57"
            val full = ContinueWidgetPresentation(reference, 0.57, 57, 100, locale)
            org.junit.Assert.assertEquals(reference, full.reference)
            org.junit.Assert.assertEquals(continueEmpty, full.emptyMessage)
            org.junit.Assert.assertEquals(locked, full.lockMessage)
            assertTrue(full.title.isNotEmpty())
            assertTrue(full.progressLabel.isNotEmpty())
            val absent = ContinueWidgetPresentation(reference, null, null, null, locale)
            org.junit.Assert.assertEquals(absent.resumeText, absent.progressLabel)
        }
        org.junit.Assert.assertEquals("Желіден тыс сақталған көшірме", WidgetCopy.text(WidgetCopy.Key.dailyOffline, "kk"))
        org.junit.Assert.assertEquals(WidgetCopy.text(WidgetCopy.Key.dailyTitle, "fr"), WidgetCopy.text(WidgetCopy.Key.dailyTitle, "fr-CA"))
        org.junit.Assert.assertEquals(WidgetCopy.text(WidgetCopy.Key.dailyTitle, "id"), WidgetCopy.text(WidgetCopy.Key.dailyTitle, "id_ID"))
        org.junit.Assert.assertEquals(WidgetCopy.text(WidgetCopy.Key.dailyTitle, "en"), WidgetCopy.text(WidgetCopy.Key.dailyTitle, "zz-ZZ"))
    }

    @Test fun `fresh widget cache is not marked stale`() {
        assertFalse(WidgetRefreshPolicy.isStale(updatedAt = 1_000L, now = 1_000L + WidgetRefreshPolicy.MAX_AGE_MS))
    }

    @Test fun `cache beyond budget is marked stale`() {
        assertTrue(WidgetRefreshPolicy.isStale(updatedAt = 1_000L, now = 1_001L + WidgetRefreshPolicy.MAX_AGE_MS))
    }

    @Test fun `offline daily cache is visibly stale`() {
        val snapshot = DailyWidgetSnapshot(
            collectionSlug = "bukhari", providerHadithId = "1", reference = "Bukhari · 1",
            text = "Text", locale = "en", isAI = false,
            sourceScope = "Sahih collection scope · Sunnah.now", localDate = "2026-09-19",
            timezone = "Asia/Almaty", isOffline = true, updatedAt = Long.MAX_VALUE,
        )
        assertTrue(WidgetRefreshPolicy.isStale(snapshot, now = 1_000L))
    }

    @Test fun `continue snapshot contains presentation only`() {
        val snapshot = ContinueWidgetSnapshot(
            reference = "Bukhari · Hadith 57", progressOrdinal = 57, progressTotal = 100,
            locale = "ur", updatedAt = 1_000L,
        )
        val encoded = Json.encodeToString(snapshot)
        listOf("collectionSlug", "providerHadithId", "position", "account", "note", "volumeId", "arabicExcerpt", "translationExcerpt").forEach {
            assertFalse("Continue widget cache must not contain $it", encoded.contains(it))
        }
    }

    @Test fun `continue presentation keeps one reference and semantic progress`() {
        val presentation = ContinueWidgetPresentation("Bukhari · Hadith 57", 0.57, 57, 100, "en")
        org.junit.Assert.assertEquals(listOf("Bukhari · Hadith 57", "Hadith 57 of 100"), presentation.compactLines)
        org.junit.Assert.assertEquals("Resume reading", presentation.accessoryInlineText)
        assertFalse(presentation.isRightToLeft)
        val urdu = ContinueWidgetPresentation("Bukhari · Hadith 57", 0.5, 57, 100, "ur")
        assertTrue(urdu.isRightToLeft)
        org.junit.Assert.assertEquals("Bukhari · Hadith 57", urdu.reference)
        assertTrue(urdu.progressLabel.contains("حدیث"))
        org.junit.Assert.assertEquals(
            WidgetCopy.format(WidgetCopy.Key.continueProgressPartial, "ar", 57),
            ContinueWidgetPresentation("Bukhari · Hadith 57", null, 57, null, "ar").progressLabel,
        )
        org.junit.Assert.assertEquals("Read a hadith to continue here.", WidgetCopy.text(WidgetCopy.Key.continueEmpty, "en"))
        org.junit.Assert.assertEquals("Unlock your device to resume reading.", WidgetCopy.text(WidgetCopy.Key.continueLocked, "en"))
    }

    @Test fun `continue widget chooses compact medium and large layouts`() {
        org.junit.Assert.assertEquals(ContinueWidgetSize.COMPACT, continueWidgetSize(DpSize(180.dp, 110.dp)))
        org.junit.Assert.assertEquals(ContinueWidgetSize.MEDIUM, continueWidgetSize(DpSize(240.dp, 160.dp)))
        org.junit.Assert.assertEquals(ContinueWidgetSize.LARGE, continueWidgetSize(DpSize(320.dp, 250.dp)))
    }

    @Test fun `widget empty copy follows the app locale`() {
        org.junit.Assert.assertEquals("الحديث اليومي", WidgetCopy.text(WidgetCopy.Key.dailyTitle, "ar"))
        org.junit.Assert.assertEquals("آج کی حدیث تیار کرنے کے لیے حدیثلی کھولیں۔", WidgetCopy.text(WidgetCopy.Key.dailyEmpty, "ur"))
        org.junit.Assert.assertEquals("اقرأ حديثًا للمتابعة هنا.", ContinueWidgetPresentation("", null, null, null, "ar").emptyMessage)
    }
}
