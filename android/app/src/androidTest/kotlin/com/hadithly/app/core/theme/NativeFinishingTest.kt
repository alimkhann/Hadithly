package com.hadithly.app.core.theme

import com.hadithly.app.core.preferences.nativeText
import com.hadithly.app.features.settings.offlineNoticeText
import com.hadithly.app.core.preferences.runtimeNoticeText

import androidx.compose.material.icons.filled.Bookmark
import android.graphics.Bitmap
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import com.hadithly.app.core.preferences.ReaderTheme
import com.hadithly.app.core.preferences.LocaleFallback
import com.hadithly.app.features.auth.SignInMode
import com.hadithly.app.features.auth.SignInScreen
import com.hadithly.app.features.main.HadithlyBottomNavigation
import com.hadithly.app.features.onboarding.OnboardingFlow
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import java.io.File

class NativeFinishingTest {
    @get:Rule val compose = createComposeRule()

    @Test fun savedRelativeTimeLocalePluralAndBucketBoundaries() {
        val now = 1_800_000_000_000.0
        val minutes = android.icu.text.RelativeDateTimeFormatter.RelativeUnit.MINUTES
        val hours = android.icu.text.RelativeDateTimeFormatter.RelativeUnit.HOURS
        val days = android.icu.text.RelativeDateTimeFormatter.RelativeUnit.DAYS
        val weeks = android.icu.text.RelativeDateTimeFormatter.RelativeUnit.WEEKS
        val months = android.icu.text.RelativeDateTimeFormatter.RelativeUnit.MONTHS
        val years = android.icu.text.RelativeDateTimeFormatter.RelativeUnit.YEARS
        val samples: List<Triple<Long, Long, android.icu.text.RelativeDateTimeFormatter.RelativeUnit?>> = listOf(
            Triple(-60L, 0L, null), Triple(0L, 0L, null), Triple(59L, 0L, null),
            Triple(60L, 1L, minutes), Triple(119L, 1L, minutes), Triple(120L, 2L, minutes), Triple(3_599L, 59L, minutes),
            Triple(3_600L, 1L, hours), Triple(86_399L, 23L, hours), Triple(86_400L, 1L, days), Triple(6 * 86_400L, 6L, days),
            Triple(7 * 86_400L, 1L, weeks), Triple(29 * 86_400L, 4L, weeks), Triple(30 * 86_400L, 1L, months),
            Triple(60 * 86_400L, 2L, months), Triple(364 * 86_400L, 12L, months), Triple(365 * 86_400L, 1L, years), Triple(400 * 86_400L, 1L, years),
        )
        for (language in listOf("en", "ar", "ru", "kk", "ky", "uz", "tr", "id", "ur", "fr", "es-419", "pt-BR", "sw", "hi", "bn")) {
            val locale = java.util.Locale.forLanguageTag(language)
            val formatter = android.icu.text.RelativeDateTimeFormatter.getInstance(locale)
            for ((elapsed, quantity, unit) in samples) {
                val expected = if (unit == null) formatter.format(android.icu.text.RelativeDateTimeFormatter.Direction.PLAIN, android.icu.text.RelativeDateTimeFormatter.AbsoluteUnit.NOW)
                    else formatter.format(quantity.toDouble(), android.icu.text.RelativeDateTimeFormatter.Direction.LAST, unit)
                assertTrue(expected.isNotEmpty())
                assertEquals(language + ":" + elapsed, expected, com.hadithly.app.features.saved.relativeSavedTime(now - elapsed * 1000, now, locale))
            }
        }
    }

    @Test fun savedTimestampUsesTheSelectedUILocale() {
        var locale by mutableStateOf("ar")
        compose.setContent { key(locale) { LocalizedPreview(ReaderTheme.LIGHT, locale) {
            val ref = com.hadithly.app.core.data.HadithRef("audit-time", "fixture", "Source collection", "1", "1", "Prepared text", "Prepared text", "Source reference")
            val now = System.currentTimeMillis().toDouble()
            val item = com.hadithly.app.core.data.SavedItemEntry(ref.hadithId, now, now, bookmarkCreatedAt = now, hadith = ref)
            Box(Modifier.fillMaxSize().statusBarsPadding().padding(20.dp)) {
                com.hadithly.app.features.saved.SharedSavedItemRow(item, emptyList(), false, {}, { _, _, _ -> }, {}, {}, {}, {})
            }
        } } }
        for (language in listOf("ar", "ru", "kk", "ky", "uz", "tr", "id", "ur", "fr", "es-419", "pt-BR", "sw", "hi", "bn", "en")) {
            compose.runOnIdle { locale = language }
            val formatter = android.icu.text.RelativeDateTimeFormatter.getInstance(java.util.Locale.forLanguageTag(language))
            val expected = formatter.format(android.icu.text.RelativeDateTimeFormatter.Direction.PLAIN, android.icu.text.RelativeDateTimeFormatter.AbsoluteUnit.NOW)
            compose.onNodeWithText(expected).assertIsDisplayed()
            capture("saved-time-" + language)
        }
    }

    @Test fun helpLabelsAndShareRepairRenderInEveryLocale() {
        var locale by mutableStateOf("ar")
        compose.setContent { key(locale) { LocalizedPreview(ReaderTheme.LIGHT, locale) {
            Box(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) { com.hadithly.app.features.settings.HelpSupportDestination() }
        } } }
        for ((language, labels) in listOf(
            "ar" to listOf("مشاركة Hadithly", "الأسئلة الشائعة والأدلة", "التواصل مع الدعم", "الإبلاغ عن مشكلة في الترجمة"),
            "ru" to listOf("Поделиться Hadithly", "Вопросы и руководства", "Связаться с поддержкой", "Сообщить об ошибке перевода"),
            "kk" to listOf("Hadithly бөлісу", "Сұрақтар мен нұсқаулықтар", "Қолдау қызметіне хабарласу", "Аударма мәселесін хабарлау"),
            "id" to listOf("Bagikan Hadithly", "Pertanyaan dan panduan", "Hubungi dukungan", "Laporkan masalah terjemahan"),
            "en" to listOf("Share Hadithly", "FAQ & guides", "Contact support", "Report a translation issue"),
            "ky" to listOf("Hadithly’ди бөлүшүү", "Суроолор жана колдонмолор", "Колдоо кызматына кайрылуу", "Котормодогу көйгөйдү билдирүү"),
            "uz" to listOf("Hadithly’ni ulashish", "Savollar va qoʻllanmalar", "Yordam xizmatiga murojaat qilish", "Tarjima muammosi haqida xabar berish"),
            "tr" to listOf("Hadithly’yi paylaş", "Sorular ve kılavuzlar", "Destekle iletişime geç", "Çeviri sorunu bildir"),
            "ur" to listOf("Hadithly شیئر کریں", "سوالات اور رہنما", "سپورٹ سے رابطہ کریں", "ترجمے کا مسئلہ رپورٹ کریں"),
            "fr" to listOf("Partager Hadithly", "Questions et guides", "Contacter l’assistance", "Signaler un problème de traduction"),
            "es-419" to listOf("Compartir Hadithly", "Preguntas y guías", "Contactar a soporte", "Reportar un problema de traducción"),
            "pt-BR" to listOf("Compartilhar Hadithly", "Perguntas e guias", "Falar com o suporte", "Relatar um problema na tradução"),
            "sw" to listOf("Shiriki Hadithly", "Maswali na miongozo", "Wasiliana na usaidizi", "Ripoti tatizo la tafsiri"),
            "hi" to listOf("Hadithly साझा करें", "प्रश्न और मार्गदर्शिकाएँ", "सहायता से संपर्क करें", "अनुवाद की समस्या बताएँ"),
            "bn" to listOf("Hadithly শেয়ার করুন", "প্রশ্ন ও নির্দেশিকা", "সহায়তায় যোগাযোগ করুন", "অনুবাদের সমস্যা জানান"),
        )) {
            compose.runOnIdle { locale = language }
            for (label in labels) compose.onNodeWithText(label).performScrollTo().assertIsDisplayed()
            capture("help-share-" + language)
        }
    }

    @Test fun authFieldsRetainLocalizedNamesAcrossPreviewStates() {
        var locale by mutableStateOf("ar")
        var mode by mutableStateOf(com.hadithly.app.features.auth.SignInMode.METHODS)
        compose.setContent { key(locale, mode) { LocalizedPreview(ReaderTheme.LIGHT, locale) {
            SignInScreen(onAuthenticated = {}, onDismiss = {}, previewMode = mode)
        } } }
        for ((language, labels) in listOf(
            "ar" to listOf("البريد الإلكتروني أو اسم المستخدم", "كلمة المرور", "تأكيد كلمة المرور", "البريد الإلكتروني", "رمز التحقق", "كلمة مرور جديدة", "المتابعة باستخدام Google"),
            "ru" to listOf("Почта или имя пользователя", "Пароль", "Повторите пароль", "Электронная почта", "Код подтверждения", "Новый пароль", "Продолжить с Google"),
            "kk" to listOf("Электрондық пошта немесе пайдаланушы аты", "Құпиясөз", "Құпиясөзді қайталау", "Электрондық пошта", "Растау коды", "Жаңа құпиясөз", "Google арқылы жалғастыру"),
            "id" to listOf("Email atau nama pengguna", "Kata sandi", "Ulangi kata sandi", "Email", "Kode verifikasi", "Kata sandi baru", "Lanjutkan dengan Google"),
            "en" to listOf("Email or username", "Password", "Repeat password", "Email", "Verification code", "New password", "Continue with Google"),
            "ky" to listOf("Электрондук почта же колдонуучу аты", "Сырсөз", "Сырсөздү кайталаңыз", "Электрондук почта", "Ырастоо коду", "Жаңы сырсөз", "Google аркылуу улантуу"),
            "uz" to listOf("Elektron pochta yoki foydalanuvchi nomi", "Parol", "Parolni takrorlang", "Elektron pochta", "Tasdiqlash kodi", "Yangi parol", "Google orqali davom etish"),
            "tr" to listOf("E-posta veya kullanıcı adı", "Parola", "Parolayı tekrarla", "E-posta", "Doğrulama kodu", "Yeni parola", "Google ile devam et"),
            "ur" to listOf("ای میل یا صارف نام", "پاس ورڈ", "پاس ورڈ دوبارہ لکھیں", "ای میل", "تصدیقی کوڈ", "نیا پاس ورڈ", "Google کے ساتھ جاری رکھیں"),
            "fr" to listOf("E-mail ou nom d’utilisateur", "Mot de passe", "Répéter le mot de passe", "E-mail", "Code de vérification", "Nouveau mot de passe", "Continuer avec Google"),
            "es-419" to listOf("Correo o nombre de usuario", "Contraseña", "Repetir contraseña", "Correo electrónico", "Código de verificación", "Nueva contraseña", "Continuar con Google"),
            "pt-BR" to listOf("E-mail ou nome de usuário", "Senha", "Repetir senha", "E-mail", "Código de verificação", "Nova senha", "Continuar com Google"),
            "sw" to listOf("Barua pepe au jina la mtumiaji", "Nenosiri", "Rudia nenosiri", "Barua pepe", "Msimbo wa uthibitishaji", "Nenosiri jipya", "Endelea kwa Google"),
            "hi" to listOf("ईमेल या उपयोगकर्ता नाम", "पासवर्ड", "पासवर्ड दोहराएँ", "ईमेल", "सत्यापन कोड", "नया पासवर्ड", "Google के साथ जारी रखें"),
            "bn" to listOf("ইমেইল বা ব্যবহারকারীর নাম", "পাসওয়ার্ড", "পাসওয়ার্ড আবার লিখুন", "ইমেইল", "যাচাইকরণ কোড", "নতুন পাসওয়ার্ড", "Google দিয়ে চালিয়ে যান"),
        )) {
            compose.runOnIdle { locale = language; mode = com.hadithly.app.features.auth.SignInMode.METHODS }
            compose.onNodeWithText(labels[6]).assertIsDisplayed()
            val legalLines = mapOf(
                "en" to "By continuing, you agree to our Terms of Use. Read our Privacy Policy.",
                "ar" to "بالمتابعة، فإنك توافق على شروط الاستخدام. اقرأ سياسة الخصوصية.",
                "ru" to "Продолжая, вы принимаете документ «Условия использования». Прочитайте документ «Политика конфиденциальности».",
                "kk" to "Жалғастыру арқылы Пайдалану шарттары құжатын қабылдайсыз. Құпиялық саясаты құжатын оқыңыз.",
                "ky" to "Улантуу менен Колдонуу шарттары документин кабыл аласыз. Купуялык саясаты документин окуңуз.",
                "uz" to "Davom etish orqali Foydalanish shartlari hujjatiga rozilik bildirasiz. Maxfiylik siyosati hujjatini oʻqing.",
                "tr" to "Devam ederek Kullanım Koşulları metnini kabul edersiniz. Gizlilik Politikası metnini okuyun.",
                "id" to "Dengan melanjutkan, Anda menyetujui Ketentuan Penggunaan. Baca Kebijakan Privasi.",
                "ur" to "جاری رکھنے سے آپ استعمال کی شرائط سے اتفاق کرتے ہیں۔ ہماری رازداری کی پالیسی پڑھیں۔",
                "fr" to "En continuant, vous acceptez nos Conditions d’utilisation. Consultez notre Politique de confidentialité.",
                "es-419" to "Al continuar, aceptas nuestros Términos de uso. Lee nuestra Política de privacidad.",
                "pt-BR" to "Ao continuar, você aceita nossos Termos de uso. Leia nossa Política de privacidade.",
                "sw" to "Kwa kuendelea, unakubali Masharti ya matumizi yetu. Soma Sera ya faragha yetu.",
                "hi" to "जारी रखकर आप हमारी उपयोग की शर्तें स्वीकार करते हैं। हमारी निजता नीति पढ़ें।",
                "bn" to "চালিয়ে গেলে আপনি আমাদের ব্যবহারের শর্তাবলি মেনে নিচ্ছেন। আমাদের গোপনীয়তা নীতি পড়ুন।"
            )
            compose.onNodeWithTag("signin.legal").assertTextEquals(legalLines.getValue(language))
            capture("auth-methods-" + language)
            compose.runOnIdle { mode = com.hadithly.app.features.auth.SignInMode.PASSWORD_SIGN_IN }
            compose.onNodeWithContentDescription(labels[0]).assertExists()
            compose.onNodeWithTag("auth.field.identifier").performTextInput("reader@example.org")
            compose.onNodeWithContentDescription(labels[0]).assertExists()
            compose.onNodeWithContentDescription(labels[1]).assertExists()
            capture("auth-password-" + language)
            compose.runOnIdle { mode = com.hadithly.app.features.auth.SignInMode.SIGN_UP }
            compose.onNodeWithContentDescription(labels[3]).assertExists()
            compose.onNodeWithContentDescription(labels[2]).assertExists()
            capture("auth-signup-" + language)
            compose.runOnIdle { mode = com.hadithly.app.features.auth.SignInMode.EMAIL_ENTRY }
            compose.onNodeWithContentDescription(labels[3]).assertExists()
            capture("auth-email-" + language)
            compose.runOnIdle { mode = com.hadithly.app.features.auth.SignInMode.FORGOT_PASSWORD_ENTRY }
            compose.onNodeWithContentDescription(labels[3]).assertExists()
            capture("auth-forgot-" + language)
            compose.runOnIdle { mode = com.hadithly.app.features.auth.SignInMode.CODE_ENTRY }
            compose.onNodeWithContentDescription(labels[4]).assertExists()
            capture("auth-code-" + language)
            compose.runOnIdle { mode = com.hadithly.app.features.auth.SignInMode.RESET_PASSWORD }
            compose.onNodeWithContentDescription(labels[5]).assertExists()
            capture("auth-reset-" + language)
        }
    }

    @Test fun savedRowAnnouncesLocalizedPrivateStatesAndActions() {
        var locale by mutableStateOf("ar")
        compose.setContent { key(locale) { LocalizedPreview(ReaderTheme.LIGHT, locale) {
            val ref = com.hadithly.app.core.data.HadithRef("audit-saved", "fixture", "Source collection", "1", "1", com.hadithly.app.features.onboarding.PreparedTranslationExample.arabic, "Prepared text", "Source reference")
            val item = com.hadithly.app.core.data.SavedItemEntry(ref.hadithId, 1.0, 1.0, bookmarkCreatedAt = 1.0, favoriteCreatedAt = 1.0, noteContent = "Private note", hadith = ref)
            Box(Modifier.fillMaxSize().statusBarsPadding().padding(20.dp)) {
                com.hadithly.app.features.saved.SharedSavedItemRow(item, emptyList(), false, {}, { _, _, _ -> }, {}, {}, {}, {})
            }
        } } }
        for ((language, labels) in listOf(
            "ar" to listOf("تم وضع إشارة مرجعية", "تمت الإضافة إلى المفضلة", "يتضمن ملاحظة", "إجراءات العنصر المحفوظ"),
            "ru" to listOf("В закладках", "В избранном", "Есть заметка", "Действия с сохранённым"),
            "kk" to listOf("Бетбелгі қойылған", "Таңдаулыларға қосылған", "Жазбасы бар", "Сақталған элемент әрекеттері"),
            "id" to listOf("Ditandai", "Ditambahkan ke favorit", "Memiliki catatan", "Tindakan item tersimpan"),
            "en" to listOf("Bookmarked", "Favorited", "Has note", "Saved item actions"),
            "ky" to listOf("Кыстарма коюлган", "Тандалмаларга кошулган", "Жазуусу бар", "Сакталган нерсенин аракеттери"),
            "uz" to listOf("Xatchoʻp qoʻyilgan", "Sevimlilarga qoʻshilgan", "Qaydi bor", "Saqlangan element amallari"),
            "tr" to listOf("Yer imlerine eklendi", "Favorilere eklendi", "Notu var", "Kaydedilen öğe işlemleri"),
            "ur" to listOf("بُک مارک کیا گیا", "پسندیدہ میں شامل ہے", "نوٹ موجود ہے", "محفوظ مواد کے اختیارات"),
            "fr" to listOf("Marqué", "Ajouté aux favoris", "Contient une note", "Actions sur l’élément enregistré"),
            "es-419" to listOf("Con marcador", "Agregado a favoritos", "Tiene una nota", "Acciones del elemento guardado"),
            "pt-BR" to listOf("Com marcador", "Adicionado aos favoritos", "Tem uma nota", "Ações do item salvo"),
            "sw" to listOf("Imewekewa alamisho", "Imeongezwa kwenye vipendwa", "Ina dokezo", "Vitendo vya kilichohifadhiwa"),
            "hi" to listOf("बुकमार्क किया गया", "पसंदीदा में जोड़ा गया", "नोट है", "सहेजे गए आइटम की कार्रवाइयाँ"),
            "bn" to listOf("বুকমার্ক করা আছে", "পছন্দের তালিকায় যোগ করা আছে", "নোট আছে", "সংরক্ষিত বিষয়ের বিকল্প"),
        )) {
            compose.runOnIdle { locale = language }
            compose.onNodeWithTag("saved.open.audit-saved").assert(androidx.compose.ui.test.SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.StateDescription, labels.take(3).joinToString(", ")))
            compose.onNodeWithContentDescription(labels[3]).assertIsDisplayed()
            compose.onNodeWithText("Source reference").assertExists()
            compose.onNodeWithText("Private note").assertExists()
            capture("saved-accessibility-" + language)
        }
    }

    @Test fun readerTranslationPreviewAndDisclosureUseSelectedLanguages() {
        var locale by mutableStateOf("ar")
        compose.setContent { key(locale) { LocalizedPreview(ReaderTheme.LIGHT, locale) {
            var prefs by remember { mutableStateOf(com.hadithly.app.core.preferences.ReaderPreferences(appTheme = ReaderTheme.LIGHT, translationLocale = locale)) }
            Box(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
                com.hadithly.app.features.settings.ReaderPreferenceContent(
                    preferences = prefs, prefix = "settings", onLanguage = { prefs = prefs.copy(translationLocale = it) },
                    onArabicFontSize = { prefs = prefs.copy(arabicFontSize = it) }, onTranslationFontSize = { prefs = prefs.copy(translationFontSize = it) },
                    onTheme = { prefs = prefs.copy(readerTheme = it, usesSeparateReaderTheme = true) }, onArabicFont = { prefs = prefs.copy(arabicFont = it) },
                    onVisibility = { _, _ -> }, onDismiss = {},
                )
            }
        } } }
        for ((language, preview, disclosure) in listOf(
            Triple("ar", "اقرأ النص الأصلي، وافهم معناه بلغتك.", "تُميَّز ترجمات الذكاء الاصطناعي وقد تحتوي على أخطاء. تظهر تفاصيل المصادر عند توفرها."),
            Triple("ru", "Читайте оригинал и понимайте его смысл на своём языке.", "Переводы ИИ помечены и могут содержать ошибки. Сведения об источниках показываются при наличии."),
            Triple("kk", "Түпнұсқа мәтінді оқып, мағынасын өз тіліңізде түсініңіз.", "ЖИ аудармалары белгіленеді және қателер болуы мүмкін. Дереккөз мәліметтері бар болса көрсетіледі."),
            Triple("id", "Baca teks asli dan pahami maknanya dalam bahasa Anda.", "Terjemahan AI diberi label dan dapat mengandung kesalahan. Detail sumber ditampilkan jika tersedia."),
            Triple("en", "Read the original text and understand its meaning in your language.", "AI translations are labeled and may contain errors. Source details appear when available."),
            Triple("ky", "Түп нуска текстти окуп, маанисин өз тилиңизде түшүнүңүз.", "ЖИ котормолору белгиленет жана каталарды камтышы мүмкүн. Булак маалыматы бар болсо көрсөтүлөт."),
            Triple("uz", "Asl matnni o‘qing va ma’nosini o‘z tilingizda tushuning.", "SI tarjimalari belgilangan va xatolarni oʻz ichiga olishi mumkin. Manba tafsilotlari mavjud boʻlsa koʻrsatiladi."),
            Triple("tr", "Özgün metni okuyun ve anlamını kendi dilinizde anlayın.", "Yapay zekâ çevirileri etiketlenir ve hata içerebilir. Kaynak bilgileri mevcut olduğunda gösterilir."),
            Triple("ur", "اصل متن پڑھیں اور اس کا مطلب اپنی زبان میں سمجھیں۔", "AI تراجم کی نشاندہی کی جاتی ہے اور ان میں غلطیاں ہو سکتی ہیں۔ ذرائع کی تفصیلات دستیاب ہونے پر دکھائی جاتی ہیں۔"),
            Triple("fr", "Lisez le texte original et comprenez-en le sens dans votre langue.", "Les traductions par IA sont signalées et peuvent contenir des erreurs. Les sources sont détaillées lorsqu’elles sont disponibles."),
            Triple("es-419", "Lee el texto original y entiende su significado en tu idioma.", "Las traducciones con IA están identificadas y pueden contener errores. Los detalles de las fuentes aparecen cuando están disponibles."),
            Triple("pt-BR", "Leia o texto original e entenda seu significado no seu idioma.", "As traduções por IA são identificadas e podem conter erros. Os detalhes das fontes aparecem quando disponíveis."),
            Triple("sw", "Soma maandishi ya asili na uelewe maana yake kwa lugha yako.", "Tafsiri za AI zinawekewa alama na zinaweza kuwa na makosa. Maelezo ya vyanzo huonekana yanapopatikana."),
            Triple("hi", "मूल पाठ पढ़ें और उसका अर्थ अपनी भाषा में समझें।", "AI अनुवाद चिह्नित होते हैं और उनमें त्रुटियाँ हो सकती हैं। स्रोतों का विवरण उपलब्ध होने पर दिखाया जाता है।"),
            Triple("bn", "মূল পাঠ পড়ুন এবং আপনার ভাষায় এর অর্থ বুঝুন।", "AI অনুবাদ চিহ্নিত থাকে এবং এতে ভুল থাকতে পারে। উৎসের বিবরণ পাওয়া গেলে দেখানো হয়।"),
        )) {
            compose.runOnIdle { locale = language }
            compose.onNodeWithTag("settings.settings.translation").performClick()
            compose.onNodeWithText(preview).assertIsDisplayed()
            capture("reader-translation-preview-" + language)
            compose.onNodeWithText(disclosure).performScrollTo().assertIsDisplayed()
            capture("reader-translation-disclosure-" + language)
        }
    }

    @Test fun appAppearanceLabelsLocalizeWithoutMergingReaderChoices() {
        var locale by mutableStateOf("ar")
        compose.setContent { key(locale) { LocalizedPreview(ReaderTheme.LIGHT, locale) {
            var prefs by remember { mutableStateOf(com.hadithly.app.core.preferences.ReaderPreferences(appTheme = ReaderTheme.LIGHT)) }
            Box(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
                com.hadithly.app.features.settings.AppearanceOptions(prefs,
                    onAppTheme = { prefs = prefs.copy(appTheme = it) }, onSeparateReaderTheme = { prefs = prefs.copy(usesSeparateReaderTheme = it) }, onReaderTheme = { prefs = prefs.copy(readerTheme = it) })
            }
        } } }
        for ((language, labels) in listOf(
            "ar" to listOf("مظهر التطبيق", "استخدام مظهر منفصل للقارئ", "النظام", "فاتح"),
            "ru" to listOf("Внешний вид приложения", "Использовать отдельное оформление для чтения", "Как в системе", "Светлая"),
            "kk" to listOf("Қолданба көрінісі", "Оқу үшін бөлек көріністі пайдалану", "Жүйелік", "Ашық"),
            "id" to listOf("Tampilan aplikasi", "Gunakan tampilan pembaca terpisah", "Sistem", "Terang"),
            "en" to listOf("App appearance", "Use a separate reader appearance", "System", "Light"),
            "ky" to listOf("Колдонмонун көрүнүшү", "Окуу үчүн өзүнчө көрүнүштү колдонуу", "Тутумдук", "Жарык"),
            "uz" to listOf("Ilova ko‘rinishi", "Oʻqish uchun alohida koʻrinishdan foydalanish", "Tizim", "Yorugʻ"),
            "tr" to listOf("Uygulama görünümü", "Okuma için ayrı bir görünüm kullan", "Sistem", "Açık"),
            "ur" to listOf("ایپ کی ظاہری شکل", "مطالعے کے لیے الگ ظاہری شکل استعمال کریں", "سسٹم", "روشن"),
            "fr" to listOf("Apparence de l’application", "Utiliser une apparence de lecture distincte", "Système", "Clair"),
            "es-419" to listOf("Apariencia de la app", "Usar una apariencia de lectura independiente", "Sistema", "Claro"),
            "pt-BR" to listOf("Aparência do app", "Usar aparência de leitura separada", "Sistema", "Claro"),
            "sw" to listOf("Mwonekano wa programu", "Tumia mwonekano tofauti wa usomaji", "Mfumo", "Angavu"),
            "hi" to listOf("ऐप का रूप", "पढ़ने के लिए अलग रूप इस्तेमाल करें", "सिस्टम", "हल्का"),
            "bn" to listOf("অ্যাপের চেহারা", "পড়ার জন্য আলাদা চেহারা ব্যবহার করুন", "সিস্টেম", "হালকা"),
        )) {
            compose.runOnIdle { locale = language }
            compose.onNodeWithText(labels[0]).assertIsDisplayed()
            compose.onNodeWithText(labels[1]).performScrollTo().assertIsDisplayed()
            compose.onNodeWithTag("settings.appearance.system").assertTextContains(labels[2])
            compose.onNodeWithTag("settings.appearance.light").assertTextContains(labels[3]).assertIsSelected()
            compose.onNodeWithTag("settings.appearance.reader.system").assertDoesNotExist()
            capture("app-appearance-" + language)
        }
    }

    @Test fun offlineNoticesUseSelectedLanguage() = verifyOfflineNotices(false)
    @Test fun offlineNoticesRemainReadableAtLargeText() = verifyOfflineNotices(true)

    private fun verifyOfflineNotices(large: Boolean) {
        val copy = org.json.JSONObject(InstrumentationRegistry.getInstrumentation().context.assets.open("a4-offline-copy.json").bufferedReader().use { it.readText() }).getJSONObject("locales")
        var locale by mutableStateOf("en")
        var index by mutableIntStateOf(0)
        var callbacks = 0
        val name = "Original %lld %@ اسم"
        compose.setContent { LocalizedPreview(ReaderTheme.LIGHT, locale) {
            CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, if (large) 2f else 1f)) {
                val resources = androidx.compose.ui.platform.LocalResources.current
                val key = com.hadithly.app.features.settings.offlineCopyKeys[index]
                val rendered = when (index) {
                    1 -> nativeText(key, name)
                    4 -> nativeText(key, 42)
                    10 -> nativeText(key, "12 MB")
                    11 -> nativeText(key, "2.0")
                    18 -> resources.offlineNoticeText("Not enough storage: need 12 MB, 8 MB free.")
                    23 -> resources.offlineNoticeText("The new file is missing 2 of your saved hadiths. Your copy stays active.")
                    else -> resources.offlineNoticeText(key)
                }
                Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().verticalScroll(androidx.compose.foundation.rememberScrollState()).padding(16.dp)) {
                    androidx.compose.material3.Text(name, modifier = Modifier.testTag("offlineAudit.name"))
                    androidx.compose.material3.Text(rendered, modifier = Modifier.testTag("offlineAudit.notice"), fontSize = androidx.compose.ui.unit.TextUnit(12f, androidx.compose.ui.unit.TextUnitType.Sp))
                    androidx.compose.material3.Button(onClick = { index = (index + 1) % 30 }, modifier = Modifier.testTag("offlineAudit.next")) { androidx.compose.material3.Text("Next fixture notice") }
                    androidx.compose.material3.Button(onClick = { callbacks++ }, modifier = Modifier.testTag("offlineAudit.callback")) { androidx.compose.material3.Text("Local callback") }
                }
            }
        } }
        val locales = if (large) listOf("ar", "ur", "ru", "bn") else listOf("en", "ar", "ru", "kk", "ky", "uz", "tr", "id", "ur", "fr", "es-419", "pt-BR", "sw", "hi", "bn")
        for (tag in locales) {
            compose.runOnIdle { locale = tag; index = 0; callbacks = 0 }
            val values = copy.getJSONArray(tag)
            for (i in 0 until values.length()) {
                val args: Array<Any> = when (i) { 1 -> arrayOf(name); 4 -> arrayOf(42); 10 -> arrayOf("12 MB"); 11 -> arrayOf("2.0"); 18 -> arrayOf("12 MB", "8 MB"); 23 -> arrayOf(2); else -> emptyArray() }
                val textLocale = java.util.Locale.forLanguageTag(tag)
                val bidi = androidx.core.text.BidiFormatter.getInstance(textLocale)
                val expected = if (args.isEmpty()) values.getString(i) else String.format(textLocale, values.getString(i).replace("%@", "%s").replace("%lld", "%d"), *args.map { if (it is String) bidi.unicodeWrap(it) else it }.toTypedArray())
                val notice = compose.onNodeWithTag("offlineAudit.notice")
                notice.performScrollTo().assertIsDisplayed().assertTextEquals(expected)
                val layouts = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
                notice.performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) { it(layouts) }
                val layout = layouts.single()
                assertFalse(layout.didOverflowHeight); assertFalse(layout.multiParagraph.didExceedMaxLines)
                assertEquals(expected.length, layout.getLineEnd(layout.lineCount - 1))
                for (line in 0 until layout.lineCount) {
                    assertFalse(layout.isLineEllipsized(line))
                    assertTrue("$tag:$i line=$line left=${layout.getLineLeft(line)} right=${layout.getLineRight(line)} width=${layout.size.width}", layout.getLineRight(line) - layout.getLineLeft(line) <= layout.size.width + 2f)
                }
                if (i in listOf(0,1,18,23,29)) capture("offline-$tag" + (if (large) "-large-" else "-") + i)
                if (i < values.length() - 1) compose.onNodeWithTag("offlineAudit.next").performScrollTo().performClick()
            }
            compose.onNodeWithTag("offlineAudit.name").assertTextEquals(name)
            compose.runOnIdle { assertEquals(0, callbacks) }
            compose.onNodeWithTag("offlineAudit.callback").performScrollTo().performClick()
            compose.runOnIdle { assertEquals(1, callbacks) }
        }
    }

    @Test fun runtimeNoticesUseSelectedLanguage() = verifyRuntimeNotices(false)
    @Test fun runtimeNoticesRemainReadableAtLargeText() = verifyRuntimeNotices(true)

    private fun verifyRuntimeNotices(large: Boolean) {
        fun load(name: String) = org.json.JSONObject(InstrumentationRegistry.getInstrumentation().context.assets.open(name).bufferedReader().use { it.readText() })
        val copy = load("a4-runtime-notice-copy.json")
        val binding = load("a4-runtime-binding-copy.json")
        val newKeys = com.hadithly.app.core.preferences.runtimeCopyKeys
        val extra = listOf("This action could not be completed. Please try again.","Check your connection and try again.","Done","Cancel","Show Library list","Show Library grid","Remove bookmark","Remove favorite","Add to favorites","Add note","Edit note")
        val sources = newKeys + extra + "Synthetic private diagnostic %@"
        var locale by mutableStateOf("en")
        var index by mutableIntStateOf(0)
        var callbacks = 0
        val opaque = "Original %lld %@ اسم"
        compose.setContent { LocalizedPreview(ReaderTheme.LIGHT, locale) {
            CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, if (large) 2f else 1f)) {
                Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().verticalScroll(androidx.compose.foundation.rememberScrollState()).padding(24.dp)) {
                    androidx.compose.material3.Text(opaque, modifier = Modifier.testTag("runtimeAudit.opaque"))
                    val text = if (index < newKeys.size || index == sources.lastIndex) com.hadithly.app.core.preferences.runtimeNoticeText(if (index == 6) "Export saved: 2 saved items, 3 reading positions." else sources[index]) else nativeText(sources[index])
                    androidx.compose.material3.Text(text, modifier = Modifier.testTag("runtimeAudit.notice"))
                    androidx.compose.material3.Button(onClick = { index = (index + 1) % sources.size }, modifier = Modifier.testTag("runtimeAudit.next")) { androidx.compose.material3.Text("Next fixture notice") }
                    androidx.compose.material3.Button(onClick = { callbacks++ }, modifier = Modifier.testTag("runtimeAudit.callback")) { androidx.compose.material3.Text("Local callback") }
                }
            }
        } }
        val locales = if (large) listOf("ar", "ur", "ru", "bn") else listOf("en", "ar", "ru", "kk", "ky", "uz", "tr", "id", "ur", "fr", "es-419", "pt-BR", "sw", "hi", "bn")
        for (tag in locales) {
            compose.runOnIdle { locale = tag; index = 0; callbacks = 0 }
            val values = copy.getJSONObject("locales").getJSONArray(tag)
            val reused = binding.getJSONObject("locales").getJSONArray(tag)
            for (i in sources.indices) {
                val expected = when {
                    i == 6 -> String.format(java.util.Locale.forLanguageTag(tag), values.getString(i).replace("%lld", "%d"), 2, 3)
                    i < newKeys.size -> values.getString(i)
                    i < sources.lastIndex -> reused.getString(i - newKeys.size)
                    else -> copy.getJSONObject("labels").getJSONObject(tag).getString("fallback")
                }
                val notice = compose.onNodeWithTag("runtimeAudit.notice")
                notice.performScrollTo().assertIsDisplayed().assertTextEquals(expected)
                val layouts = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
                notice.performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) { it(layouts) }
                val layout = layouts.single()
                assertFalse("$tag:$i height", layout.didOverflowHeight); assertFalse(layout.multiParagraph.didExceedMaxLines)
                assertEquals(expected.length, layout.getLineEnd(layout.lineCount - 1))
                for (line in 0 until layout.lineCount) {
                    assertFalse(layout.isLineEllipsized(line))
                    assertTrue("$tag:$i line $line", layout.getLineRight(line) - layout.getLineLeft(line) <= layout.size.width + 2f)
                }
                if ((!large && i in listOf(0,21,66)) || (large && i in listOf(1,6,12,23,28,55,sources.lastIndex))) capture("runtime-$tag" + (if (large) "-large-" else "-") + i)
                if (i < sources.lastIndex) compose.onNodeWithTag("runtimeAudit.next").performScrollTo().performClick()
            }
            compose.onNodeWithTag("runtimeAudit.opaque").performScrollTo().assertTextEquals(opaque)
            compose.runOnIdle { assertEquals(0, callbacks) }
            compose.onNodeWithTag("runtimeAudit.callback").performScrollTo().performClick()
            compose.runOnIdle { assertEquals(1, callbacks) }
        }
    }

    @Test fun runtimeNoticeBoundariesUseKnownCopyAndBoundDiagnostics() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        for (tag in listOf("en", "ar", "ru", "kk", "ky", "uz", "tr", "id", "ur", "fr", "es-419", "pt-BR", "sw", "hi", "bn")) {
            val configuration = android.content.res.Configuration(context.resources.configuration).apply { setLocale(java.util.Locale.forLanguageTag(tag)) }
            val resources = context.createConfigurationContext(configuration).resources
            val fallback = resources.nativeText("This action could not be completed. Please try again.")
            for (source in listOf("Private diagnostic %@", "Export saved: 999999999999999999999999 saved items, 1 reading positions.")) assertEquals(tag, fallback, resources.runtimeNoticeText(source))
            assertEquals(resources.nativeText("Use your original Hadithly account to finish or restore this purchase."), resources.runtimeNoticeText("Sign in to your original Hadithly account before restoring."))
            assertEquals(resources.nativeText("Each file must be 10 MB or smaller."), resources.runtimeNoticeText("Each file must be 10 MB or smaller."))
            assertEquals(resources.getString(com.hadithly.app.R.string.e4_appeal_error), resources.runtimeNoticeText("e4.appeal_error"))
            assertEquals(resources.nativeText("Could not check for updates. Your downloads keep working offline."), resources.offlineNoticeText("Could not check for updates (Private diagnostic %@). Your downloads keep working offline."))
            assertEquals(resources.nativeText("Download failed."), resources.offlineNoticeText("Private diagnostic %@"))
        }
    }

    @Test fun edgeCopyUsesSelectedLanguage() = verifyEdgeCopy(false)
    @Test fun edgeCopyRemainsReadableAtLargeText() = verifyEdgeCopy(true)
    private fun verifyEdgeCopy(large: Boolean) {
        fun load(name: String) = org.json.JSONObject(InstrumentationRegistry.getInstrumentation().context.assets.open(name).bufferedReader().use { it.readText() }).getJSONObject("locales")
        val copy = load("a4-runtime-edge-copy.json")
        val reuse = load("a4-runtime-edge-reuse.json")
        var locale by mutableStateOf("en")
        var index by mutableIntStateOf(0)
        var callbacks = 0
        val opaque = "Original %lld %@ اسم"
        compose.setContent { LocalizedPreview(ReaderTheme.LIGHT, locale) {
            CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, if (large) 2f else 1f)) {
                Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().verticalScroll(androidx.compose.foundation.rememberScrollState()).padding(24.dp)) {
                    androidx.compose.material3.Text(opaque, modifier = Modifier.testTag("edgeAudit.opaque"))
                    val text = when (index) {
                        0 -> com.hadithly.app.features.auth.authEmailCodePrompt("name%lld+%@person@example.test")
                        1 -> nativeText("All folders")
                        else -> com.hadithly.app.features.reader.CopyAttribution.line(opaque, "57", "Source %@ %lld", true, nativeText("Hadith"), nativeText("AI translation"))
                    }
                    androidx.compose.material3.Text(text, modifier = Modifier.testTag("edgeAudit.notice"))
                    androidx.compose.material3.Button(onClick = { index = (index + 1) % 3 }, modifier = Modifier.testTag("edgeAudit.next")) { androidx.compose.material3.Text("Next fixture notice") }
                    androidx.compose.material3.Button(onClick = { callbacks++ }, modifier = Modifier.testTag("edgeAudit.callback")) { androidx.compose.material3.Text("Local callback") }
                }
            }
        } }
        for (tag in if (large) listOf("ar","ur","ru","bn") else listOf("en","ar","ru","kk","ky","uz","tr","id","ur","fr","es-419","pt-BR","sw","hi","bn")) {
            compose.runOnIdle { locale = tag; index = 0; callbacks = 0 }
            val labels = reuse.getJSONArray(tag)
            val wrapped = androidx.core.text.BidiFormatter.getInstance(java.util.Locale.forLanguageTag(tag)).unicodeWrap("name%lld+%@person@example.test")
            val expected = listOf(String.format(java.util.Locale.forLanguageTag(tag), labels.getString(0).replace("%@","%s"), wrapped), labels.getString(1), "— $opaque · " + copy.getJSONArray(tag).getString(0) + " 57 · Source %@ %lld · " + labels.getString(2))
            for (i in 0..2) {
                val notice = compose.onNodeWithTag("edgeAudit.notice")
                notice.performScrollTo().assertIsDisplayed().assertTextEquals(expected[i])
                val layouts = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
                notice.performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) { it(layouts) }
                val layout = layouts.single()
                assertFalse(layout.didOverflowHeight); assertFalse(layout.multiParagraph.didExceedMaxLines)
                assertEquals(expected[i].length, layout.getLineEnd(layout.lineCount - 1))
                for (line in 0 until layout.lineCount) { assertFalse(layout.isLineEllipsized(line)); assertTrue(layout.getLineRight(line) - layout.getLineLeft(line) <= layout.size.width + 2f) }
                capture("edge-$tag" + (if (large) "-large-" else "-") + i)
                if (i < 2) compose.onNodeWithTag("edgeAudit.next").performScrollTo().performClick()
            }
            compose.onNodeWithTag("edgeAudit.opaque").assertTextEquals(opaque)
            compose.runOnIdle { assertEquals(0, callbacks) }
            compose.onNodeWithTag("edgeAudit.callback").performScrollTo().performClick()
            compose.runOnIdle { assertEquals(1, callbacks) }
        }
    }

    @Test fun edgeMenusUseSelectedLanguage() = verifyEdgeMenus(false)
    @Test fun edgeMenusRemainReadableAtLargeText() = verifyEdgeMenus(true)
    private fun verifyEdgeMenus(large: Boolean) {
        val copy = org.json.JSONObject(InstrumentationRegistry.getInstrumentation().context.assets.open("a4-runtime-edge-reuse.json").bufferedReader().use { it.readText() }).getJSONObject("locales")
        var locale by mutableStateOf("en")
        var saved by mutableStateOf(false)
        var expanded by mutableStateOf(true)
        var callbacks = 0
        var actions = emptyList<com.hadithly.app.features.reader.HadithMenuAction>()
        var today = emptyList<String>()
        compose.setContent { LocalizedPreview(ReaderTheme.LIGHT, locale) {
            CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, if (large) 2f else 1f)) {
                actions = com.hadithly.app.features.reader.localizedHadithMenuActions(com.hadithly.app.features.reader.hadithMenuActions(saved, saved, saved,
                    com.hadithly.app.core.data.ReaderTranslation("prepared", "Prepared user content", source = "fixture", sourceLabel = "Fixture"), { callbacks++ }, { callbacks++ }, { callbacks++ }, { callbacks++ }, { callbacks++ }, { callbacks++ }, { callbacks++ }))
                today = com.hadithly.app.features.today.todayAccessibilityActionLabels(saved,saved,saved)
                Box(Modifier.fillMaxSize().statusBarsPadding().padding(24.dp)) {
                    com.hadithly.app.features.reader.HadithContextMenu("Original %lld %@ اسم", actions, expanded, { expanded = false })
                }
            }
        } }
        for (tag in if (large) listOf("ar","ur","ru","bn") else listOf("en","ar","ru","kk","ky","uz","tr","id","ur","fr","es-419","pt-BR","sw","hi","bn")) for (selected in listOf(false,true)) {
            compose.runOnIdle { locale = tag; saved = selected; expanded = true; callbacks = 0 }
            val values = copy.getJSONArray(tag)
            val indices = listOf(if (selected) 5 else 4, if (selected) 7 else 6, if (selected) 9 else 8, 10,11,13,12)
            for ((i,name) in listOf("bookmark","favorite","note","copy","share","reportTranslation","suggestTranslation").withIndex()) {
                val node = compose.onNodeWithTag("reader.$name")
                node.performScrollTo().assertIsDisplayed().assertTextContains(values.getString(indices[i]))
            }
            capture("edge-menu-$tag" + (if (large) "-large-" else "-") + selected)
            compose.runOnIdle {
                assertEquals(indices.map { values.getString(it) }, actions.map { it.label })
                assertEquals(actions.map { it.label }, com.hadithly.app.features.reader.customActionsFor(actions).map { it.label })
                assertEquals(listOf(3,indices[0],indices[1],indices[2],10,11,12).map { values.getString(it) }, today)
                assertEquals(0, callbacks)
                assertTrue(com.hadithly.app.features.reader.customActionsFor(actions)[3].action())
                assertEquals(1, callbacks)
            }
            compose.onNodeWithTag("reader.copy").performScrollTo().performClick()
            compose.runOnIdle { assertFalse(expanded); assertEquals(2, callbacks) }
        }
    }

    @Test fun finalWrappersUseSelectedLanguage() = verifyFinalWrappers(false)
    @Test fun finalWrappersRemainReadableAtLargeText() = verifyFinalWrappers(true)
    private fun verifyFinalWrappers(large: Boolean) {
        fun load(name: String) = org.json.JSONObject(InstrumentationRegistry.getInstrumentation().context.assets.open(name).bufferedReader().use { it.readText() }).getJSONObject("locales")
        val copy = load("a4-final-wrapper-copy.json")
        val reuse = load("a4-final-wrapper-reuse.json")
        val keys = listOf("Not bookmarked","Bookmark %@","Bookmark current hadith","Bookmark positioned hadith","Remove bookmark for positioned hadith","Expand chapters in %@","Collapse chapters in %@","Volumes and chapters","Your private saved reading","Type, appearance, and text","This page","Positioned hadith","Close reader","Close reader menu","Open reader menu","Sahih","Hasan","Daif","Reading","Library","Support","Account","Saved items could not load","Free","Pro trial","Off","Contents","Bookmarks & Notes","Settings","Search","Back","Show Library list","Show Library grid","Bookmarked","Favorited","Has note","Unverified")
        var locale by mutableStateOf("en")
        var index by mutableIntStateOf(0)
        compose.setContent { LocalizedPreview(ReaderTheme.LIGHT, locale) {
            CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, if (large) 2f else 1f)) {
                Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().verticalScroll(androidx.compose.foundation.rememberScrollState()).padding(24.dp)) {
                    Box(Modifier.testTag("finalAudit.notice").semantics(mergeDescendants = true) {}) {
                        when (index) {
                            in 18..20 -> com.hadithly.app.features.settings.SettingsGroupHeader(keys[index])
                            21 -> androidx.compose.material3.Text(com.hadithly.app.features.settings.settingsAccountLabel(null))
                            22 -> com.hadithly.app.features.settings.SettingsSyncNotice()
                            else -> androidx.compose.material3.Text(if (keys[index].contains("%@")) nativeText(keys[index], "Original %lld %@ اسم") else nativeText(keys[index]))
                        }
                    }
                    androidx.compose.material3.Button(onClick = { index = (index + 1) % keys.size }, modifier = Modifier.testTag("finalAudit.next")) { androidx.compose.material3.Text("Next fixture notice") }
                    androidx.compose.material3.Text(com.hadithly.app.features.settings.settingsAccountLabel("Original %lld %@ اسم"), modifier = Modifier.testTag("finalAudit.opaque"))
                }
            }
        } }
        for (tag in if (large) listOf("ar","ur","ru","bn") else listOf("en","ar","ru","kk","ky","uz","tr","id","ur","fr","es-419","pt-BR","sw","hi","bn")) {
            compose.runOnIdle { locale = tag; index = 0 }
            val values = copy.getJSONArray(tag)
            val labels = reuse.getJSONArray(tag)
            for (i in keys.indices) {
                val template = if (i < 18) values.getString(i) else labels.getString(i-18)
                val expected = if (template.contains("%@")) String.format(java.util.Locale.forLanguageTag(tag), template.replace("%@","%s"), androidx.core.text.BidiFormatter.getInstance(java.util.Locale.forLanguageTag(tag)).unicodeWrap("Original %lld %@ اسم")) else template
                val notice = compose.onNodeWithTag("finalAudit.notice")
                notice.performScrollTo().assertIsDisplayed().assertTextEquals(expected)
                val layouts = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
                notice.performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) { it(layouts) }
                val layout = layouts.single()
                assertFalse(layout.didOverflowHeight); assertFalse(layout.multiParagraph.didExceedMaxLines)
                assertEquals(expected.length, layout.getLineEnd(layout.lineCount - 1))
                for (line in 0 until layout.lineCount) { assertFalse(layout.isLineEllipsized(line)); assertTrue("$tag:$i", layout.getLineRight(line)-layout.getLineLeft(line) <= layout.size.width+2f) }
                if ((large && i in listOf(1,5,9,15)) || (!large && i == 0)) capture("final-$tag" + (if (large) "-large-" else "-") + i)
                if (i < keys.lastIndex) compose.onNodeWithTag("finalAudit.next").performScrollTo().performClick()
            }
            compose.onNodeWithTag("finalAudit.opaque").performScrollTo().assertTextEquals("Original %lld %@ اسم")
        }
    }

    @Test fun chromeUsesSelectedLanguage() = verifyChrome(false)
    @Test fun chromeRemainsReadableAtLargeText() = verifyChrome(true)
    private fun verifyChrome(large: Boolean) {
        fun load(name: String) = org.json.JSONObject(InstrumentationRegistry.getInstrumentation().context.assets.open(name).bufferedReader().use { it.readText() }).getJSONObject("locales")
        val copy = load("a4-final-wrapper-copy.json"); val reuse = load("a4-final-wrapper-reuse.json")
        var locale by mutableStateOf("en"); var bookmarked by mutableStateOf(false); var open by mutableStateOf(false)
        var callbacks = 0
        compose.setContent { LocalizedPreview(ReaderTheme.LIGHT, locale) {
            CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, if (large) 2f else 1f)) {
                Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(24.dp)) {
                    Box(Modifier.weight(1f, fill = false)) {
                        com.hadithly.app.features.reader.ReaderMenuStack("Original %lld %@ اسم", bookmarked, { callbacks++ }, { callbacks++ }, { callbacks++ }, { bookmarked = !bookmarked; callbacks++ }, { callbacks++ })
                    }
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        com.hadithly.app.features.reader.ReaderChromeCircle(androidx.compose.material.icons.Icons.AutoMirrored.Filled.ArrowBack, "Back", { callbacks++ })
                        com.hadithly.app.features.reader.ReaderChromeCircle(androidx.compose.material.icons.Icons.Filled.Close, if (open) "Close reader menu" else "Open reader menu", { open = !open; callbacks++ })
                    }
                }
            }
        } }
        for (tag in if (large) listOf("ar","ur","ru","bn") else listOf("en","ar","ru","kk","ky","uz","tr","id","ur","fr","es-419","pt-BR","sw","hi","bn")) {
            compose.runOnIdle { locale = tag; bookmarked = false; open = false; callbacks = 0 }
            val values = copy.getJSONArray(tag); val labels = reuse.getJSONArray(tag)
            for ((i,name) in listOf("contents","saved","settings").withIndex()) {
                val row = compose.onNodeWithTag("reader.menu.$name")
                row.performScrollTo().assertIsDisplayed().assertTextContains(labels.getString(8+i)).assertTextContains(values.getString(7+i))
                for (text in listOf(labels.getString(8+i), values.getString(7+i))) {
                    val layouts = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
                    compose.onNodeWithText(text, useUnmergedTree = true).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) { it(layouts) }
                    val layout = layouts.single()
                    assertFalse(layout.didOverflowHeight); assertFalse(layout.multiParagraph.didExceedMaxLines)
                    assertEquals(text.length, layout.getLineEnd(layout.lineCount-1))
                    for (line in 0 until layout.lineCount) assertFalse(layout.isLineEllipsized(line))
                }
                capture("chrome-$tag" + (if (large) "-large-" else "-") + i)
            }
            compose.runOnIdle { assertEquals(0,callbacks) }
            val wrapped = androidx.core.text.BidiFormatter.getInstance(java.util.Locale.forLanguageTag(tag)).unicodeWrap("Original %lld %@ اسم")
            compose.onNodeWithTag("reader.menu.bookmark").performScrollTo().assertContentDescriptionEquals(String.format(values.getString(1).replace("%@","%s"),wrapped)).performClick()
            compose.onNodeWithTag("reader.menu.bookmark").assertContentDescriptionEquals(values.getString(4))
            compose.runOnIdle { assertTrue(bookmarked); assertEquals(1,callbacks) }
            compose.onNodeWithContentDescription(values.getString(14)).performClick()
            compose.onNodeWithContentDescription(values.getString(13)).assertIsDisplayed()
            compose.runOnIdle { assertTrue(open); assertEquals(2,callbacks) }
        }
    }

    @Test fun authenticityCopyUsesSelectedLanguage() = verifyAuthenticityCopy(false)
    @Test fun authenticityCopyRemainsReadableAtLargeText() = verifyAuthenticityCopy(true)
    private fun verifyAuthenticityCopy(large: Boolean) {
        fun load(name: String) = org.json.JSONObject(InstrumentationRegistry.getInstrumentation().context.assets.open(name).bufferedReader().use { it.readText() }).getJSONObject("locales")
        val copy = load("a4-authenticity-copy.json"); val grades = load("a4-final-wrapper-copy.json")
        var locale by mutableStateOf("en"); var index by mutableIntStateOf(0)
        val scopes = listOf("hadith", "collection", "unknown", "hadith", "unknown", "hadith")
        val values = listOf("sahih", "hasan", null, "custom", "sahih", null)
        compose.setContent { LocalizedPreview(ReaderTheme.LIGHT, locale) {
            CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, if (large) 2f else 1f)) {
                Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().verticalScroll(androidx.compose.foundation.rememberScrollState()).padding(24.dp)) {
                    androidx.compose.material3.Text(com.hadithly.app.core.preferences.authenticityText(scopes[index], values[index], "Original %lld %@ اسم"), modifier = Modifier.testTag("authenticityAudit.notice"))
                    androidx.compose.material3.Button(onClick = { index = (index + 1) % scopes.size }, modifier = Modifier.testTag("authenticityAudit.next")) { androidx.compose.material3.Text("Next fixture notice") }
                }
            }
        } }
        for (tag in if (large) listOf("ar","ur","ru","bn") else listOf("en","ar","ru","kk","ky","uz","tr","id","ur","fr","es-419","pt-BR","sw","hi","bn")) {
            compose.runOnIdle { locale = tag; index = 0 }
            val templates = copy.getJSONArray(tag); val labels = grades.getJSONArray(tag)
            val bidi = androidx.core.text.BidiFormatter.getInstance(java.util.Locale.forLanguageTag(tag))
            for (i in scopes.indices) {
                val template = templates.getString(if (i == 0 || i == 3) 0 else if (i == 1) 1 else 2).replace("%@","%s").replace("\$@","\$s")
                val source = bidi.unicodeWrap("Original %lld %@ اسم")
                val expected = if (i == 0 || i == 1 || i == 3) String.format(java.util.Locale.forLanguageTag(tag), template, bidi.unicodeWrap(if (i == 3) "Custom" else labels.getString(if (i == 0) 15 else 16)), source) else String.format(java.util.Locale.forLanguageTag(tag), template, source)
                val notice = compose.onNodeWithTag("authenticityAudit.notice")
                notice.performScrollTo().assertIsDisplayed().assertTextEquals(expected)
                val layouts = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
                notice.performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) { it(layouts) }
                val layout = layouts.single()
                assertFalse(layout.didOverflowHeight); assertFalse(layout.multiParagraph.didExceedMaxLines)
                assertEquals(expected.length, layout.getLineEnd(layout.lineCount - 1))
                for (line in 0 until layout.lineCount) { assertFalse(layout.isLineEllipsized(line)); assertTrue("$tag:$i", layout.getLineRight(line)-layout.getLineLeft(line) <= layout.size.width+2f) }
                if (i < 3) capture("authenticity-$tag" + (if (large) "-large-" else "-") + i)
                if (i < scopes.lastIndex) compose.onNodeWithTag("authenticityAudit.next").performScrollTo().performClick()
            }
            compose.runOnIdle { assertEquals(listOf("hadith", "collection", "unknown", "hadith", "unknown", "hadith"), scopes); assertEquals(listOf("sahih", "hasan", null, "custom", "sahih", null), values) }
        }
    }

    @Test fun profileNoticesUseSelectedLanguage() = verifyProfileNotices(false)
    @Test fun profileNoticesRemainReadableAtLargeText() = verifyProfileNotices(true)

    private fun verifyProfileNotices(large: Boolean) {
        val copy = org.json.JSONObject(InstrumentationRegistry.getInstrumentation().context.assets.open("a4-profile-notice-copy.json").bufferedReader().use { it.readText() })
        var locale by mutableStateOf("en")
        var index by mutableIntStateOf(0)
        var name by mutableStateOf("Original %lld %@ اسم")
        compose.setContent { LocalizedPreview(ReaderTheme.LIGHT, locale) {
            CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, if (large) 2f else 1f)) {
                Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().verticalScroll(androidx.compose.foundation.rememberScrollState()).padding(16.dp)) {
                    androidx.compose.material3.OutlinedTextField(name, { name = it }, modifier = Modifier.testTag("profileAudit.name"))
                    com.hadithly.app.features.settings.ProfileStatusNotice(com.hadithly.app.features.settings.ProfileNotice.entries[index].source)
                    androidx.compose.material3.Button(onClick = { index = (index + 1) % 6 }, modifier = Modifier.testTag("profileAudit.next")) { androidx.compose.material3.Text("Next fixture notice") }
                }
            }
        } }
        val locales = if (large) listOf("ar", "ur", "ru", "bn") else listOf("en", "ar", "ru", "kk", "ky", "uz", "tr", "id", "ur", "fr", "es-419", "pt-BR", "sw", "hi", "bn")
        for (tag in locales) {
            compose.runOnIdle { locale = tag; index = 0 }
            val values = copy.getJSONObject("locales").getJSONArray(tag)
            for (i in 0..5) {
                val expected = if (i < 5) values.getString(i) else copy.getJSONObject("labels").getJSONObject(tag).getString("fallback")
                val notice = compose.onNodeWithTag("settings.profile.notice")
                notice.performScrollTo().assertIsDisplayed().assertTextEquals(expected)
                val layouts = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
                notice.performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) { it(layouts) }
                capture("profile-$tag" + (if (large) "-large-" else "-") + i)
                val layout = layouts.single()
                assertFalse("$tag:$i height", layout.didOverflowHeight)
                assertFalse("$tag:$i lines", layout.multiParagraph.didExceedMaxLines)
                assertEquals(expected.length, layout.getLineEnd(layout.lineCount - 1))
                for (line in 0 until layout.lineCount) {
                    assertFalse("$tag:$i ellipsis", layout.isLineEllipsized(line))
                    assertTrue("$tag:$i line $line width", layout.getLineRight(line) - layout.getLineLeft(line) <= layout.size.width + 1f)
                }
                if (i < 5) compose.onNodeWithTag("profileAudit.next").performScrollTo().performClick()
            }
            compose.onNodeWithTag("profileAudit.name").assertTextEquals("Original %lld %@ اسم")
            compose.runOnIdle { assertEquals("Original %lld %@ اسم", name) }
        }
    }

    @Test fun savedFiltersUseSelectedLanguage() {
        val copy = org.json.JSONObject(InstrumentationRegistry.getInstrumentation().context.assets.open("a4-saved-filter-copy.json").bufferedReader().use { it.readText() }).getJSONObject("locales")
        var locale by mutableStateOf("en")
        var selected by mutableIntStateOf(0)
        var folder by mutableStateOf(false)
        var loads = 0
        var opens = 0
        var removals = 0
        compose.setContent { key(locale) { LocalizedPreview(ReaderTheme.LIGHT, locale) {
            val ref = com.hadithly.app.core.data.HadithRef("audit-retry", "fixture", "Prepared example", "1", "1", "", null, "Original source reference %lld %@")
            val item = com.hadithly.app.core.data.SavedItemEntry(ref.hadithId, 1.0, 1.0, bookmarkCreatedAt = 1.0, hadith = ref)
            Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().verticalScroll(androidx.compose.foundation.rememberScrollState()).padding(16.dp)) {
                com.hadithly.app.features.saved.SavedFilterBar(selected, { selected = it }, "saved.filter")
                com.hadithly.app.features.saved.SavedEmptyState(selected, folder, androidx.compose.material.icons.Icons.Filled.Bookmark, Modifier.heightIn(min = 200.dp))
                androidx.compose.material3.Text(androidx.compose.ui.res.stringResource(com.hadithly.app.R.string.saved_removal_undo_message), modifier = Modifier.testTag("savedAudit.removalMessage"))
                com.hadithly.app.features.saved.SharedSavedItemRow(item, emptyList(), false, { opens += 1 }, { _, _, _ -> removals += 1 }, {}, {}, {}, {}, {
                    loads += 1
                    if (loads == 1) error("Synthetic preview failure")
                    it.copy(arabicText = "Prepared Arabic preview", englishText = "Prepared interface preview")
                })
            }
        } } }
        for (tag in listOf("en", "ar", "ru", "kk", "ky", "uz", "tr", "id", "ur", "fr", "es-419", "pt-BR", "sw", "hi", "bn")) {
            compose.runOnIdle { locale = tag; selected = 0; loads = 0; opens = 0; removals = 0; folder = false }
            val values = copy.getJSONArray(tag)
            for ((index, filter) in listOf("all", "bookmarks", "favorites", "notes").withIndex()) {
                val button = compose.onNodeWithTag("saved.filter.$filter")
                button.performScrollTo().assertIsDisplayed().assertTextEquals(values.getString(index))
                button.performClick().assertIsSelected()
                compose.onNodeWithText(values.getString(5 + index)).performScrollTo().assertIsDisplayed()
                compose.onNodeWithText(values.getString(9 + index)).performScrollTo().assertIsDisplayed()
                compose.onNodeWithTag("savedAudit.removalMessage").performScrollTo().assertIsDisplayed().assertTextEquals(values.getString(14))
                capture("saved-filter-$tag-$filter")
            }
            val all = compose.onNodeWithTag("saved.filter.all").fetchSemanticsNode().boundsInRoot
            val notes = compose.onNodeWithTag("saved.filter.notes").fetchSemanticsNode().boundsInRoot
            assertEquals(tag in listOf("ar", "ur"), all.left > notes.left)
            compose.runOnIdle { folder = true }
            compose.onNodeWithText(values.getString(15)).performScrollTo().assertIsDisplayed()
            compose.onNodeWithText(values.getString(16)).performScrollTo().assertIsDisplayed()
            capture("saved-folder-empty-$tag")
            compose.onNodeWithTag("saved.preview.audit-retry").performScrollTo().performClick()
            compose.onNodeWithTag("saved.preview.retry").performScrollTo().assertIsDisplayed().assertTextEquals(values.getString(13))
            capture("saved-preview-retry-$tag")
            compose.onNodeWithTag("saved.preview.retry").performClick()
            compose.onNodeWithText("Prepared interface preview").performScrollTo().assertIsDisplayed()
            compose.runOnIdle { assertEquals(2, loads); assertEquals(0, opens); assertEquals(0, removals) }
        }
    }

    @Test fun savedEmptyGuidanceRemainsReachableAtLargeText() {
        val copy = org.json.JSONObject(InstrumentationRegistry.getInstrumentation().context.assets.open("a4-saved-filter-copy.json").bufferedReader().use { it.readText() }).getJSONObject("locales")
        var locale by mutableStateOf("ar")
        var selected by mutableIntStateOf(1)
        compose.setContent { key(locale) { LocalizedPreview(ReaderTheme.LIGHT, locale) {
            CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, 2f)) {
                Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(16.dp)) {
                    com.hadithly.app.features.saved.SavedEmptyState(selected, false, androidx.compose.material.icons.Icons.Filled.Bookmark, Modifier.weight(1f))
                    com.hadithly.app.features.saved.SavedFilterBar(selected, { selected = it }, "saved.filter")
                }
            }
        } } }
        for (tag in listOf("ar", "ru", "bn")) {
            compose.runOnIdle { locale = tag; selected = 1 }
            val values = copy.getJSONArray(tag)
            compose.onNodeWithText(values.getString(6)).performScrollTo().assertIsDisplayed()
            capture("saved-large-title-$tag")
            compose.onNodeWithText(values.getString(10)).performScrollTo().assertIsDisplayed()
            capture("saved-large-guidance-$tag")
            compose.onNodeWithTag("saved.filter.notes").performClick().assertIsSelected()
            compose.onNodeWithText(values.getString(12)).performScrollTo().assertIsDisplayed()
        }
    }

    @Test fun evidenceIntakeKeepsPrivateProcessingCopyLocalized() {
        val copy = org.json.JSONObject(InstrumentationRegistry.getInstrumentation().context.assets.open("a4-evidence-intake-copy.json").bufferedReader().use { it.readText() })
        var locale by mutableStateOf("en")
        var status by mutableStateOf("awaiting_processing")
        var retries = 0
        compose.setContent { key(locale) { LocalizedPreview(ReaderTheme.LIGHT, locale) {
            Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().verticalScroll(androidx.compose.foundation.rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                androidx.compose.material3.Text(nativeText("Sign in from Settings to suggest a translation with evidence."), modifier = Modifier.testTag("intakeAudit.signIn"))
                androidx.compose.material3.Text(nativeText("The private files were removed before processing. You can start a new suggestion."), modifier = Modifier.testTag("intakeAudit.filesRemoved"))
                com.hadithly.app.features.reader.EvidenceProcessingStatusContent(status, listOf("prepared-item"),
                    citations = listOf(com.hadithly.app.core.data.EvidenceCitation("https://example.org/prepared", "Original source %lld %@", "p. 1")),
                    onRetry = { retries += 1; status = "awaiting_processing" })
            }
        } } }
        for (tag in listOf("en", "ar", "ru", "kk", "ky", "uz", "tr", "id", "ur", "fr", "es-419", "pt-BR", "sw", "hi", "bn")) {
            compose.runOnIdle { locale = tag; status = "awaiting_processing"; retries = 0 }
            val values = copy.getJSONObject("locales").getJSONArray(tag)
            val labels = copy.getJSONObject("labels").getJSONObject(tag)
            compose.onNodeWithTag("intakeAudit.signIn").performScrollTo().assertIsDisplayed().assertTextEquals(values.getString(0))
            compose.onNodeWithTag("intakeAudit.filesRemoved").assertTextEquals(values.getString(1))
            compose.onNodeWithText(values.getString(3)).performScrollTo().assertIsDisplayed()
            compose.onNodeWithText(values.getString(2)).performScrollTo().assertIsDisplayed()
            capture("intake-waiting-$tag")
            compose.runOnIdle { status = "processing_failed" }
            compose.onNodeWithText(values.getString(6)).performScrollTo().assertIsDisplayed()
            compose.onNodeWithTag("submission.retryProcessing").assertTextEquals(values.getString(4))
            compose.onNodeWithTag("submission.approved").assertDoesNotExist()
            capture("intake-failed-$tag")
            compose.onNodeWithTag("submission.retryProcessing").performScrollTo().performClick()
            compose.runOnIdle { assertEquals(1, retries); status = "evidence_ready" }
            compose.onNodeWithTag("submission.ready").performScrollTo().assertIsDisplayed().assertTextEquals(labels.getString("Evidence checks complete"))
            compose.onNodeWithText(labels.getString("e3.waiting")).assertExists()
            compose.onNodeWithTag("submission.approved").assertDoesNotExist()
            compose.onNodeWithTag("submission.retryProcessing").assertDoesNotExist()
            compose.onNodeWithTag("submission.citation.0").performScrollTo().assertIsDisplayed()
            compose.onNodeWithText("Original source %lld %@", useUnmergedTree = true).assertExists()
            capture("intake-ready-$tag")
        }
    }

    @Test fun authFailureUsesSelectedLanguage() {
        val copy = org.json.JSONObject(InstrumentationRegistry.getInstrumentation().context.assets.open("a4-auth-failure-copy.json").bufferedReader().use { it.readText() })
        var locale by mutableStateOf("en")
        compose.setContent { key(locale) { LocalizedPreview(ReaderTheme.LIGHT, locale) {
            Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().verticalScroll(androidx.compose.foundation.rememberScrollState()).padding(16.dp)) {
                androidx.compose.material3.Text(com.hadithly.app.features.today.todayGreeting(null), modifier = Modifier.testTag("authAudit.greetingGuest"))
                androidx.compose.material3.Text(com.hadithly.app.features.today.todayGreeting("Original %lld %@ اسم"), modifier = Modifier.testTag("authAudit.greetingName"))
                for (message in com.hadithly.app.features.auth.AuthFailureMessage.entries) {
                    com.hadithly.app.features.auth.AuthErrorBanner(message.source, Modifier.testTag("authAudit.error.${message.name}"))
                }
            }
        } } }
        for (tag in listOf("en", "ar", "ru", "kk", "ky", "uz", "tr", "id", "ur", "fr", "es-419", "pt-BR", "sw", "hi", "bn")) {
            compose.runOnIdle { locale = tag }
            val labels = copy.getJSONObject("labels").getJSONObject(tag)
            compose.onNodeWithTag("authAudit.greetingGuest").performScrollTo().assertTextEquals(labels.getString("greeting_guest"))
            val expected = String.format(java.util.Locale.forLanguageTag(tag), labels.getString("greeting_name").replace("%@", "%s"), "Original %lld %@ اسم")
            val actual = compose.onNodeWithTag("authAudit.greetingName").fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.Text].single().text
            val marks = Regex("[\u200e\u200f\u061c\u202a-\u202e\u2066-\u2069]")
            assertEquals(expected.replace(marks, ""), actual.replace(marks, ""))
            capture("greeting-errors-top-$tag")
            val messages = copy.getJSONObject("locales").getJSONArray(tag)
            for ((index, message) in com.hadithly.app.features.auth.AuthFailureMessage.entries.withIndex()) {
                compose.onNodeWithTag("authAudit.error.${message.name}").performScrollTo().assertIsDisplayed().assertTextEquals(messages.getString(index))
            }
            capture("greeting-errors-bottom-$tag")
        }
    }

    @Test fun evidenceItemStatesUseSelectedLanguage() {
        val copy = org.json.JSONObject(InstrumentationRegistry.getInstrumentation().context.assets.open("a4-evidence-copy.json").bufferedReader().use { it.readText() })
        val keys = copy.getJSONArray("keys")
        val states = listOf("reserved", "validating", "quarantined_unscanned", "pending_safe_fetch", "processing", "ready", "failed", "infected", "invalid", "expired", "future_state")
        var locale by mutableStateOf("en")
        compose.setContent { key(locale) { LocalizedPreview(ReaderTheme.LIGHT, locale) {
            Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().verticalScroll(androidx.compose.foundation.rememberScrollState()).padding(16.dp)) {
                for (state in states) com.hadithly.app.features.reader.EvidenceItemStatusLine("Original source %lld %@.pdf", state)
                com.hadithly.app.features.reader.EvidenceUploadProgress(0.42)
                com.hadithly.app.features.reader.EvidenceProcessingStatusContent("infected", emptyList(), onRetry = {})
            }
        } } }
        for (tag in listOf("en", "ar", "ru", "kk", "ky", "uz", "tr", "id", "ur", "fr", "es-419", "pt-BR", "sw", "hi", "bn")) {
            compose.runOnIdle { locale = tag }
            val values = copy.getJSONObject("locales").getJSONArray(tag)
            for (state in states) {
                val key = copy.getJSONObject("state_keys").getString(state)
                val index = (0 until keys.length()).first { keys.getString(it) == key }
                compose.onNode(hasText(values.getString(index)) and hasAnyAncestor(hasTestTag("submission.itemStatus.$state")), useUnmergedTree = true).performScrollTo().assertIsDisplayed()
                compose.onNode(hasText("Original source %lld %@.pdf") and hasAnyAncestor(hasTestTag("submission.itemStatus.$state")), useUnmergedTree = true).assertExists()
            }
            val progress = compose.onNodeWithTag("submission.uploadProgress")
            progress.performScrollTo().assertIsDisplayed()
            val expected = java.text.NumberFormat.getPercentInstance(java.util.Locale.forLanguageTag(tag)).apply { maximumFractionDigits = 0 }.format(0.42)
            progress.assert(SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.StateDescription, expected))
            capture("evidence-copy-$tag")
        }
    }

    @Test fun deletionDisclosuresLocalizeAndCancelWithoutRequest() = verifyDeletionDisclosures(false)

    @Test fun deletionDisclosuresRemainReadableWithSystemLargeText() = verifyDeletionDisclosures(true)

    private fun verifyDeletionDisclosures(systemLargeText: Boolean) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val copy = org.json.JSONObject(instrumentation.context.assets.open("a4-deletion-copy.json").bufferedReader().use { it.readText() }).getJSONObject("locales")
        var locale by mutableStateOf("en")
        var fontScale by mutableStateOf(1f)
        var presented by mutableStateOf(false)
        var deletionRequests = 0
        compose.setContent { key(locale, fontScale) { LocalizedPreview(ReaderTheme.LIGHT, locale) {
            CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, fontScale)) {
                Surface(Modifier.fillMaxSize()) {
                    Column(Modifier.statusBarsPadding().navigationBarsPadding().verticalScroll(androidx.compose.foundation.rememberScrollState()).padding(16.dp)) {
                        com.hadithly.app.features.settings.AccountDeletionWarning(fontSize = androidx.compose.ui.unit.TextUnit.Unspecified)
                        androidx.compose.material3.TextButton(onClick = { presented = true }, modifier = Modifier.testTag("deletionAudit.present")) { androidx.compose.material3.Text(nativeText("Delete account")) }
                    }
                    if (presented) com.hadithly.app.features.settings.AccountDeletionConfirmation(false, { presented = false }, { deletionRequests += 1 })
                }
            }
        } } }
        if (systemLargeText) assertTrue("The emulator must run at system font_scale=2.0", instrumentation.targetContext.resources.configuration.fontScale >= 1.99f)
        val cases = if (systemLargeText) listOf("ar" to 2f, "ru" to 2f, "bn" to 2f)
            else listOf("en", "ar", "ru", "kk", "ky", "uz", "tr", "id", "ur", "fr", "es-419", "pt-BR", "sw", "hi", "bn").map { it to 1f }
        for ((tag, scale) in cases) {
            compose.runOnIdle { locale = tag; fontScale = scale; presented = false }
            val expected = copy.getJSONArray(tag)
            val footer = compose.onNodeWithTag("settings.deletionSubscriptionWarning")
            footer.performScrollTo().assertIsDisplayed()
            assertEquals(expected.getString(3), footer.fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.Text].single().text)
            assertTrue(expected.getString(3).contains("Play Store")); assertFalse(expected.getString(3).contains("Apple"))
            capture("deletion-warning-$tag" + if (scale > 1f) "-large" else "")
            compose.onNodeWithTag("deletionAudit.present").performScrollTo().performClick()
            compose.onNodeWithTag("settings.deletionTitle").assertIsDisplayed().assertTextEquals(expected.getString(0))
            val message = compose.onNodeWithTag("settings.deletionMessage")
            message.performScrollTo().assertIsDisplayed().assertTextEquals(expected.getString(1))
            capture("deletion-message-$tag" + if (scale > 1f) "-large" else "")
            val warning = compose.onNode(hasTestTag("settings.deletionSubscriptionWarning") and hasAnyAncestor(hasTestTag("settings.deletionDialogText")))
            warning.performScrollTo().assertIsDisplayed().assertTextEquals(expected.getString(3))
            for (action in listOf("settings.confirmDeletion", "settings.cancelDeletion")) {
                val button = compose.onNodeWithTag(action).assertIsEnabled()
                val bounds = button.fetchSemanticsNode().touchBoundsInRoot
                val density = instrumentation.targetContext.resources.displayMetrics.density
                assertTrue("$action touch height is ${bounds.height / density}dp", bounds.height / density >= 47.5f)
                assertTrue("$action touch width is ${bounds.width / density}dp", bounds.width / density >= 47.5f)
            }
            capture("deletion-confirmation-$tag" + if (scale > 1f) "-large" else "")
            compose.onNodeWithTag("settings.cancelDeletion").performClick()
            compose.runOnIdle { assertEquals(0, deletionRequests) }
            compose.onNodeWithTag("settings.deletionTitle").assertDoesNotExist()
        }
    }

    @Test fun deletionConfirmationKeepsActionsDisabledDuringDeletion() {
        var dismissed = 0
        var deletionRequests = 0
        compose.setContent { LocalizedPreview(ReaderTheme.LIGHT, "en") {
            com.hadithly.app.features.settings.AccountDeletionConfirmation(true, { dismissed += 1 }, { deletionRequests += 1 })
        } }
        compose.onNodeWithTag("settings.confirmDeletion").assertIsNotEnabled()
        compose.onNodeWithTag("settings.cancelDeletion").assertIsNotEnabled()
        android.os.ParcelFileDescriptor.AutoCloseInputStream(InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand("input keyevent KEYCODE_BACK")).use { it.readBytes() }
        compose.onNodeWithTag("settings.deletionTitle").assertIsDisplayed()
        compose.runOnIdle { assertEquals(0, dismissed); assertEquals(0, deletionRequests) }
    }

    @Test fun privacyDisclosuresRenderInEveryLocaleWithoutChangingConsent() {
        var locale by mutableStateOf("ar")
        val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as com.hadithly.app.HadithlyApplication
        val policyLabels = mapOf(
            "en" to listOf("Privacy Policy", "Terms of Use", "How deletion works"),
            "ar" to listOf("سياسة الخصوصية", "شروط الاستخدام", "كيفية حذف البيانات"),
            "ru" to listOf("Политика конфиденциальности", "Условия использования", "Как удаляются данные"),
            "kk" to listOf("Құпиялық саясаты", "Пайдалану шарттары", "Деректерді жою тәртібі"),
            "ky" to listOf("Купуялык саясаты", "Колдонуу шарттары", "Маалыматтарды өчүрүү тартиби"),
            "uz" to listOf("Maxfiylik siyosati", "Foydalanish shartlari", "Maʼlumotlar qanday oʻchiriladi"),
            "tr" to listOf("Gizlilik Politikası", "Kullanım Koşulları", "Veriler nasıl silinir"),
            "id" to listOf("Kebijakan Privasi", "Ketentuan Penggunaan", "Cara penghapusan data"),
            "ur" to listOf("رازداری کی پالیسی", "استعمال کی شرائط", "ڈیٹا کیسے حذف ہوتا ہے"),
            "fr" to listOf("Politique de confidentialité", "Conditions d’utilisation", "Fonctionnement de la suppression"),
            "es-419" to listOf("Política de privacidad", "Términos de uso", "Cómo se eliminan los datos"),
            "pt-BR" to listOf("Política de privacidade", "Termos de uso", "Como os dados são excluídos"),
            "sw" to listOf("Sera ya faragha", "Masharti ya matumizi", "Jinsi data inavyofutwa"),
            "hi" to listOf("निजता नीति", "उपयोग की शर्तें", "डेटा कैसे मिटाया जाता है"),
            "bn" to listOf("গোপনীয়তা নীতি", "ব্যবহারের শর্তাবলি", "ডেটা কীভাবে মুছে ফেলা হয়")
        )
        val usageBefore = app.analytics.sharing.value
        val crashBefore = com.hadithly.app.core.diagnostics.CrashReporting.hasConsent
        compose.setContent { key(locale) { LocalizedPreview(ReaderTheme.LIGHT, locale) {
            Box(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
                com.hadithly.app.features.settings.PrivacyDataDestination({})
            }
        } } }
        for ((language, analytics, crash) in listOf(
            Triple("ar", "شارك إحصاءات أساسية عن التطبيق للمساعدة في تحسين Hadithly. لا تتضمن مطلقًا نصوص قراءتك أو ملاحظاتك أو تفاصيل حسابك. يؤدي إيقاف هذا الخيار إلى مسح الإحصاءات التي تنتظر الإرسال.", "تساعدنا تقارير الأعطال على إصلاح المشكلات. ولا تتضمن مطلقًا نصوص قراءتك أو ملاحظاتك أو تفاصيل حسابك. يؤدي إيقافها إلى مسح التقارير المعلّقة على هذا الجهاز."),
            Triple("ru", "Делитесь базовой статистикой работы приложения, чтобы помочь улучшить Hadithly. Текст, который вы читаете, ваши заметки и данные аккаунта никогда не включаются. Отключение удаляет статистику, ожидающую отправки.", "Отчёты о сбоях помогают нам исправлять проблемы. Они никогда не содержат текст, который вы читаете, ваши заметки или данные аккаунта. Отключение удаляет ожидающие отправки отчёты на этом устройстве."),
            Triple("kk", "Hadithly қолданбасын жақсартуға көмектесу үшін қолданбаның негізгі статистикасын бөлісіңіз. Оқитын мәтіндеріңіз, жазбаларыңыз және тіркелгі деректеріңіз ешқашан жіберілмейді. Бұл мүмкіндікті өшірсеңіз, жіберуді күтіп тұрған статистика жойылады.", "Істен шығу туралы есептер ақауларды түзетуге көмектеседі. Оларға сіз оқитын мәтіндер, жазбаларыңыз немесе тіркелгі деректеріңіз ешқашан кірмейді. Өшіру осы құрылғыдағы жіберілуді күтіп тұрған есептерді тазалайды."),
            Triple("id", "Bagikan statistik dasar aplikasi untuk membantu meningkatkan Hadithly. Teks bacaan, catatan, dan detail akun Anda tidak pernah disertakan. Menonaktifkan opsi ini akan menghapus statistik yang menunggu untuk dikirim.", "Laporan kerusakan membantu kami memperbaiki masalah. Laporan ini tidak pernah menyertakan teks bacaan, catatan, atau detail akun Anda. Menonaktifkannya menghapus laporan yang menunggu dikirim di perangkat ini."),
            Triple("en", "Share basic app statistics to help improve Hadithly. Your reading text, notes and account details are never included. Turning this off clears pending statistics.", "Crash reports help us fix problems. They never include your reading text, notes or account details. Turning this off clears pending reports on this device."),
            Triple("ky", "Hadithly тиркемесин жакшыртуу үчүн колдонмонун негизги статистикасын бөлүшүңүз. Сиз окуган текст, жазууларыңыз жана каттоо эсебиңиздин маалыматы эч качан кошулбайт. Бул мүмкүнчүлүктү өчүрсөңүз, жөнөтүүнү күтүп турган статистика тазаланат.", "Иштен чыгуу тууралуу отчеттор көйгөйлөрдү оңдоого жардам берет. Аларда сиз окуган текст, жазууларыңыз же каттоо эсебиңиздин маалыматы эч качан камтылбайт. Өчүрүү бул түзмөктөгү жөнөтүлө элек отчетторду тазалайт."),
            Triple("uz", "Hadithly ilovasini yaxshilashga yordam berish uchun ilovaning asosiy statistikasini ulashing. Siz oʻqiyotgan matn, qaydlaringiz va hisobingizga oid maʼlumotlar hech qachon kiritilmaydi. Bu imkoniyatni oʻchirish yuborilishni kutayotgan statistikani tozalaydi.", "Nosozlik hisobotlari muammolarni tuzatishimizga yordam beradi. Ularga siz oʻqiyotgan matn, qaydlaringiz yoki hisobingizga oid maʼlumotlar hech qachon kiritilmaydi. Buni oʻchirish ushbu qurilmadagi yuborilishini kutayotgan hisobotlarni tozalaydi."),
            Triple("tr", "Hadithly uygulamasını iyileştirmeye yardımcı olmak için temel uygulama istatistiklerini paylaşın. Okuduğunuz metinler, notlarınız ve hesap bilgileriniz hiçbir zaman dahil edilmez. Bu seçeneği kapatmak gönderilmeyi bekleyen istatistikleri temizler.", "Çökme raporları sorunları gidermemize yardımcı olur. Okuduğunuz metinleri, notlarınızı veya hesap bilgilerinizi hiçbir zaman içermezler. Kapatıldığında bu cihazda gönderilmeyi bekleyen raporlar silinir."),
            Triple("ur", "Hadithly کو بہتر بنانے میں مدد کے لیے ایپ کے بنیادی اعداد و شمار شیئر کریں۔ آپ کے پڑھے جانے والے متن، نوٹس اور اکاؤنٹ کی تفصیلات کبھی شامل نہیں ہوتیں۔ اسے بند کرنے سے بھیجے جانے کے منتظر اعداد و شمار صاف ہو جاتے ہیں۔", "کریش رپورٹس مسائل درست کرنے میں ہماری مدد کرتی ہیں۔ ان میں آپ کے پڑھے جانے والے متن، نوٹس یا اکاؤنٹ کی تفصیلات کبھی شامل نہیں ہوتیں۔ اسے بند کرنے سے اس آلے پر بھیجے جانے کے منتظر رپورٹس صاف ہو جاتی ہیں۔"),
            Triple("fr", "Partagez des statistiques de base sur l’application pour aider à améliorer Hadithly. Le texte que vous lisez, vos notes et les détails de votre compte ne sont jamais inclus. La désactivation efface les statistiques en attente d’envoi.", "Les rapports de plantage nous aident à corriger les problèmes. Ils ne contiennent jamais le texte que vous lisez, vos notes ni les détails de votre compte. La désactivation efface les rapports en attente sur cet appareil."),
            Triple("es-419", "Comparte estadísticas básicas de la app para ayudar a mejorar Hadithly. Nunca se incluyen el texto que lees, tus notas ni los datos de tu cuenta. Al desactivar esta opción, se borran las estadísticas pendientes de envío.", "Los informes de cierres inesperados nos ayudan a solucionar problemas. Nunca incluyen el texto que lees, tus notas ni los datos de tu cuenta. Desactivar esta opción borra los informes pendientes de este dispositivo."),
            Triple("pt-BR", "Compartilhe estatísticas básicas do aplicativo para ajudar a melhorar o Hadithly. O texto que você lê, suas notas e os dados da sua conta nunca são incluídos. Desativar esta opção limpa as estatísticas pendentes de envio.", "Os relatórios de falhas nos ajudam a corrigir problemas. Eles nunca incluem o texto que você lê, suas notas ou os dados da sua conta. Desativar essa opção apaga os relatórios pendentes neste dispositivo."),
            Triple("sw", "Shiriki takwimu za msingi za programu ili kusaidia kuboresha Hadithly. Maandishi unayosoma, madokezo yako na maelezo ya akaunti yako hayajumuishwi kamwe. Kuzima chaguo hili hufuta takwimu zinazosubiri kutumwa.", "Ripoti za hitilafu hutusaidia kurekebisha matatizo. Hazijumuishi kamwe maandishi unayosoma, madokezo yako au maelezo ya akaunti yako. Kuzima chaguo hili hufuta ripoti zinazosubiri kutumwa kwenye kifaa hiki."),
            Triple("hi", "Hadithly को बेहतर बनाने में मदद के लिए ऐप के बुनियादी आँकड़े साझा करें। आपके पढ़े जाने वाले पाठ, नोट्स और खाते की जानकारी कभी शामिल नहीं होती। इसे बंद करने पर भेजे जाने की प्रतीक्षा कर रहे आँकड़े मिट जाते हैं।", "क्रैश रिपोर्ट हमें समस्याएँ ठीक करने में मदद करती हैं। इनमें आपके पढ़े जाने वाले पाठ, नोट्स या खाते की जानकारी कभी शामिल नहीं होती। इसे बंद करने से इस डिवाइस पर भेजे जाने की प्रतीक्षा कर रही रिपोर्ट मिट जाती हैं।"),
            Triple("bn", "Hadithly উন্নত করতে সাহায্য করার জন্য অ্যাপের মৌলিক পরিসংখ্যান শেয়ার করুন। আপনি যে লেখা পড়ছেন, আপনার নোট ও অ্যাকাউন্টের তথ্য কখনো অন্তর্ভুক্ত হয় না। এটি বন্ধ করলে পাঠানোর অপেক্ষায় থাকা পরিসংখ্যান মুছে যায়।", "ক্র্যাশ রিপোর্ট আমাদের সমস্যা ঠিক করতে সাহায্য করে। এতে আপনি যে লেখা পড়ছেন, আপনার নোট বা অ্যাকাউন্টের তথ্য কখনো অন্তর্ভুক্ত হয় না। এটি বন্ধ করলে এই ডিভাইসে পাঠানোর অপেক্ষায় থাকা রিপোর্ট মুছে যায়।"),
        )) {
            compose.runOnIdle { locale = language }
            compose.onNodeWithText(analytics).performScrollTo().assertIsDisplayed()
            compose.onNodeWithText(crash).performScrollTo().assertIsDisplayed()
            capture("privacy-disclosures-" + language)
            for (title in policyLabels.getValue(language)) compose.onNodeWithText(title).performScrollTo().assertIsDisplayed().assertHeightIsAtLeast(48.dp)
            capture("privacy-policies-" + language)
        }
        compose.runOnIdle {
            assertEquals(usageBefore, app.analytics.sharing.value)
            assertEquals(crashBefore, com.hadithly.app.core.diagnostics.CrashReporting.hasConsent)
        }
    }

    @Test fun contentsGuidanceAndValidationLocalizeAtRuntime() {
        var locale by mutableStateOf("ar")
        compose.setContent { key(locale) { LocalizedPreview(ReaderTheme.LIGHT, locale) {
            Box(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
                com.hadithly.app.features.reader.ContentsSheet(
                    volumes = listOf(com.hadithly.app.core.data.OutlineVolume(volumeId = "1", title = "Volume 1", hadithCount = 7.0)),
                    selectedVolumeId = null, collectionName = "Sahih al-Bukhari", arabicVisible = true,
                    onSelect = {}, onSelectChapter = { _, _ -> }, onJumpToReference = { false }, onDismiss = {},
                )
            }
        } } }
        for ((language, hint, error) in listOf(
            Triple("ar", "انتقل إلى رقم حديث، مثل 57.", "أدخل رقم حديث مثل 57 أو 4.5."),
            Triple("ru", "Перейти к номеру хадиса, например 57.", "Введите номер хадиса, например 57 или 4.5."),
            Triple("kk", "Хадис нөміріне өту, мысалы 57.", "57 немесе 4.5 сияқты хадис нөмірін енгізіңіз."),
            Triple("id", "Lompat ke nomor hadis, misalnya 57.", "Masukkan nomor hadis seperti 57 atau 4.5."),
            Triple("en", "Jump to a hadith number, e.g. 57.", "Enter a hadith number like 57 or 4.5."),
            Triple("ky", "Хадис номерине өтүңүз, мисалы 57.", "57 же 4.5 сыяктуу хадис номерин киргизиңиз."),
            Triple("uz", "Hadis raqamiga o‘ting, masalan 57.", "57 yoki 4.5 kabi hadis raqamini kiriting."),
            Triple("tr", "Hadis numarasına git, örneğin 57.", "57 veya 4.5 gibi bir hadis numarası girin."),
            Triple("ur", "حدیث نمبر پر جائیں، مثلاً 57۔", "57 یا 4.5 جیسا حدیث نمبر درج کریں۔"),
            Triple("fr", "Aller au numéro de hadith, par exemple 57.", "Saisissez un numéro de hadith comme 57 ou 4.5."),
            Triple("es-419", "Ir al número de hadiz, por ejemplo, 57.", "Ingresa un número de hadiz como 57 o 4.5."),
            Triple("pt-BR", "Ir para o número do hadith, por exemplo, 57.", "Digite um número de hadith como 57 ou 4.5."),
            Triple("sw", "Nenda kwenye nambari ya hadithi, kwa mfano 57.", "Weka nambari ya hadithi kama 57 au 4.5."),
            Triple("hi", "हदीस संख्या पर जाएँ, जैसे 57।", "57 या 4.5 जैसा हदीस नंबर दर्ज करें।"),
            Triple("bn", "হাদিস নম্বরে যান, যেমন ৫৭।", "57 বা 4.5-এর মতো হাদিস নম্বর লিখুন।"),
        )) {
            compose.runOnIdle { locale = language }
            compose.onNodeWithText(hint).assertIsDisplayed()
            compose.onNodeWithTag("reader.contents.jump").performTextInput("abc")
            compose.onNodeWithTag("reader.contents.jump").performImeAction()
            compose.onNodeWithText(error).assertIsDisplayed()
            capture("contents-validation-" + language)
        }
    }

    @Test fun savedFolderNoticeResourcesKeepInterpolatedNames() {
        val base = InstrumentationRegistry.getInstrumentation().targetContext
        for ((language, expected) in listOf(
            "ar" to "تم حذف المجلد My folder",
            "ru" to "Папка My folder удалена",
            "kk" to "My folder қалтасы жойылды",
            "id" to "Folder My folder dihapus",
            "en" to "Folder My folder deleted",
            "ky" to "My folder папкасы өчүрүлдү",
            "uz" to "My folder jildi o‘chirildi",
            "tr" to "My folder klasörü silindi",
            "ur" to "فولڈر My folder حذف کر دیا گیا",
            "fr" to "Dossier My folder supprimé",
            "es-419" to "Carpeta My folder eliminada",
            "pt-BR" to "Pasta My folder excluída",
            "sw" to "Folda My folder imefutwa",
            "hi" to "फ़ोल्डर My folder मिटाया गया",
            "bn" to "My folder ফোল্ডার মুছে ফেলা হয়েছে",
        )) {
            val config = android.content.res.Configuration(base.resources.configuration).apply { setLocale(java.util.Locale.forLanguageTag(language)) }
            val context = base.createConfigurationContext(config)
            assertEquals(language, expected, context.getString(com.hadithly.app.R.string.saved_folder_deleted, "My folder"))
        }
    }

    @Test fun nativeCopyKeepsNumericFormatArgumentsTyped() {
        val base = InstrumentationRegistry.getInstrumentation().targetContext
        for (language in listOf("en", "ar")) {
            val config = android.content.res.Configuration(base.resources.configuration).apply { setLocale(java.util.Locale.forLanguageTag(language)) }
            val context = base.createConfigurationContext(config)
            assertEquals(context.getString(com.hadithly.app.R.string.q1_remaining, 3, 5), context.nativeText("q1.remaining", 3, 5))
        }
    }

    @Test fun readingProgressLabelsUseLocalizedWordsAndNumbers() {
        var locale by mutableStateOf("ar")
        compose.setContent { LocalizedPreview(ReaderTheme.LIGHT, locale) {
            Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(24.dp)) {
                for (state in listOf("in_progress", "unopened", "completed", "stale")) {
                    com.hadithly.app.features.library.ProgressSlot(com.hadithly.app.core.data.CollectionProgressSummary("bukhari", state, 10.0, 3.0), false)
                }
                com.hadithly.app.features.library.ProgressSlot(null, false)
            }
        } }
        for ((language, title) in listOf("en" to "Not started", "ar" to "لم يبدأ بعد", "ru" to "Не начато", "kk" to "Басталмаған", "ky" to "Баштала элек", "uz" to "Boshlanmagan", "tr" to "Başlanmadı", "id" to "Belum dimulai", "ur" to "ابھی شروع نہیں کیا", "fr" to "Pas encore commencé", "es-419" to "Sin empezar", "pt-BR" to "Não iniciado", "sw" to "Bado haijaanza", "hi" to "अभी शुरू नहीं किया", "bn" to "শুরু করা হয়নি", "ar-u-nu-arab" to "لم يبدأ بعد")) {
            compose.runOnIdle { locale = language }
            compose.onNodeWithText(title).assertIsDisplayed()
            if (language.startsWith("ar")) {
                val number = java.text.NumberFormat.getIntegerInstance(java.util.Locale.forLanguageTag(language))
                compose.onNodeWithText("الحديث", substring = true).assertTextContains(number.format(3), substring = true).assertTextContains(number.format(10), substring = true)
                if (language == "ar-u-nu-arab") {
                    compose.onNodeWithText("الحديث", substring = true).assertTextContains("٣", substring = true).assertTextContains("١٠", substring = true)
                }
                compose.onNodeWithText("تقدم القراءة غير متاح").assertIsDisplayed()
            }
            capture("reading-progress-" + language)
        }
    }

    @Test fun dailyEmptyStateLocalizesItsActualTitleAndCollectionGuidance() {
        var locale by mutableStateOf("ar")
        compose.setContent { LocalizedPreview(ReaderTheme.LIGHT, locale) {
            com.hadithly.app.features.today.TodayScreen({}, previewState = "empty")
        } }
        for ((language, title, guidance) in listOf(
            Triple("en", "Your daily reading", "Today’s hadith is not available yet. Choose a collection below to keep reading."),
            Triple("ar", "قراءتك اليومية", "حديث اليوم غير متاح بعد. اختر مجموعة أدناه لمتابعة القراءة."),
            Triple("ru", "Ваше ежедневное чтение", "Сегодняшний хадис пока недоступен. Выберите сборник ниже, чтобы продолжить чтение."),
            Triple("kk", "Күнделікті оқуыңыз", "Бүгінгі хадис әзірге қолжетімсіз. Оқуды жалғастыру үшін төменнен жинақты таңдаңыз."),
            Triple("ky", "Күнүмдүк окууңуз", "Бүгүнкү хадис азырынча жеткиликсиз. Окууну улантуу үчүн төмөндөн жыйнак тандаңыз."),
            Triple("uz", "Kundalik mutolaangiz", "Bugungi hadis hali mavjud emas. O‘qishni davom ettirish uchun quyidan to‘plamni tanlang."),
            Triple("tr", "Günlük okumanız", "Bugünün hadisi henüz mevcut değil. Okumaya devam etmek için aşağıdan bir koleksiyon seçin."),
            Triple("id", "Bacaan harian Anda", "Hadis hari ini belum tersedia. Pilih koleksi di bawah untuk melanjutkan membaca."),
            Triple("ur", "آپ کا روزانہ مطالعہ", "آج کی حدیث ابھی دستیاب نہیں ہے۔ پڑھنا جاری رکھنے کے لیے نیچے کوئی مجموعہ منتخب کریں۔"),
            Triple("fr", "Votre lecture du jour", "Le hadith du jour n’est pas encore disponible. Choisissez un recueil ci-dessous pour continuer à lire."),
            Triple("es-419", "Tu lectura diaria", "El hadiz de hoy aún no está disponible. Elige una colección abajo para seguir leyendo."),
            Triple("pt-BR", "Sua leitura diária", "O hadith de hoje ainda não está disponível. Escolha uma coleção abaixo para continuar a leitura."),
            Triple("sw", "Usomaji wako wa kila siku", "Hadithi ya leo bado haipatikani. Chagua mkusanyiko hapa chini ili kuendelea kusoma."),
            Triple("hi", "आपका दैनिक पठन", "आज की हदीस अभी उपलब्ध नहीं है। पढ़ना जारी रखने के लिए नीचे कोई संग्रह चुनें।"),
            Triple("bn", "আপনার দৈনিক পাঠ", "আজকের হাদিস এখনও উপলব্ধ নয়। পড়া চালিয়ে যেতে নিচে একটি সংকলন বেছে নিন।"),
        )) {
            compose.runOnIdle { locale = language }
            compose.onNodeWithText(title).assertIsDisplayed()
            compose.onNodeWithText(guidance, substring = true).assertIsDisplayed()
            capture("daily-empty-" + language)
        }
    }

    @Test fun freshStoreAndLightWelcomeUseDeviceDefaults() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val defaults = context.getSharedPreferences("native-finishing-first-launch", 0)
        defaults.edit().clear().commit()
        try {
            val preferences = com.hadithly.app.core.preferences.PreferencesStore(defaults, listOf("ru-RU"))
            assertEquals(ReaderTheme.SYSTEM, preferences.preferences.value.appTheme)
            assertEquals("ru", preferences.preferences.value.uiLocale)
            preferences.setUILocale("kk")
            assertEquals("kk", com.hadithly.app.core.preferences.PreferencesStore(defaults, listOf("fr-FR")).preferences.value.uiLocale)
        } finally { defaults.edit().clear().commit() }
        val onboarding = context.getSharedPreferences("onboarding", 0)
        val previous = onboarding.all
        onboarding.edit().clear().commit()
        try {
            compose.setContent { LocalizedPreview(ReaderTheme.LIGHT, locale = "ru") {
                com.hadithly.app.features.onboarding.OnboardingFlow("ru", {}, {})
            } }
            compose.onNodeWithTag("onboarding.getStarted").assertTextContains("Начать")
            capture("welcome-light-russian")
        } finally {
            val edit = onboarding.edit().clear()
            previous.forEach { (key, value) -> when (value) { is Int -> edit.putInt(key, value); is Boolean -> edit.putBoolean(key, value); is String -> edit.putString(key, value) } }
            edit.commit()
        }
    }

    @OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
    @Test fun nativeReaderSheetsAndEmptyStates() {
        var scene by mutableStateOf("contents")
        var previewLocale by mutableStateOf("en")
        val app = com.hadithly.app.HadithlyApplication.instance()
        val hadith = com.hadithly.app.core.data.ReaderHadith(_id = "finishing-57", provider = "sunnah_now", canonicalId = "sunnah_now:bukhari:57", providerHadithId = "57", collectionSlug = "bukhari",
            arabicText = "إِنَّمَا الأَعْمَالُ بِالنِّيَّاتِ", englishText = "Actions are judged by intentions.", referenceDisplay = "Sahih al-Bukhari · Hadith 57", collectionName = "Sahih al-Bukhari",
            authenticity = com.hadithly.app.core.data.AuthenticityClaim(kind = "collection_scope", normalizedGrade = "sahih", claimScope = "collection", sourceLabel = "Documented Sahih collection", sourceName = "Sunnah.now", sourceUrl = "https://sunnah.now", verificationMethod = "manual_collection_mapping"))
        val ref = com.hadithly.app.core.data.HadithRef(hadithId = hadith._id, collectionSlug = "bukhari", collectionName = hadith.collectionName, volumeId = "1", hadithNumber = "57", referenceDisplay = hadith.referenceDisplay, arabicText = hadith.arabicText, englishText = hadith.englishText)
        compose.setContent { LocalizedPreview(ReaderTheme.PAPER, previewLocale) {
            Surface(Modifier.fillMaxSize(), color = LocalHadithlyColors.current.background) {
                key(scene) {
                    if (scene == "saved-main") androidx.compose.material3.Scaffold(bottomBar = { HadithlyBottomNavigation(2) {} }, containerColor = LocalHadithlyColors.current.background) { padding -> Box(Modifier.padding(padding)) { com.hadithly.app.features.saved.SavedScreen {} } }
                    else if (scene == "bookmark") com.hadithly.app.features.reader.BookmarkPlacementSheet(com.hadithly.app.features.reader.BookmarkPlacementTargets(hadith, hadith), { false }, {}, {})
                    else androidx.compose.material3.ModalBottomSheet(onDismissRequest = {}, containerColor = LocalHadithlyColors.current.background,
                        sheetState = androidx.compose.material3.rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
                        when (scene) {
                            "contents" -> com.hadithly.app.features.reader.ContentsSheet(listOf(com.hadithly.app.core.data.OutlineVolume("1", "Volume 1", "Revelation", 58.0,
                                listOf(com.hadithly.app.core.data.OutlineChapter("1", "Revelation", "كتاب بدء الوحي", 7.0, "1")))), "1", "Sahih al-Bukhari", true, {}, { _, _ -> }, { true }, {})
                            "search" -> com.hadithly.app.features.reader.ReaderSearchSheet({ emptyList() }, {}, {})
                            "saved" -> com.hadithly.app.features.reader.ReaderSavedSheet(listOf(com.hadithly.app.core.data.SavedItemEntry(hadith._id, System.currentTimeMillis().toDouble() - 300_000, System.currentTimeMillis().toDouble() - 300_000, bookmarkCreatedAt = System.currentTimeMillis().toDouble() - 300_000, hadith = ref)), emptyList(), app.library, {}, {}, {})
                            else -> com.hadithly.app.features.saved.SavedScreen {}
                        }
                    }
                }
            }
        } }
        for (next in listOf("contents", "search", "saved", "bookmark", "saved-main")) {
            compose.runOnIdle { scene = next }
            compose.waitForIdle()
            capture("reader-$next")
            if (next == "search") {
                compose.onNodeWithTag("reader.search.field").performTextInput("zzz-no-match")
                compose.mainClock.advanceTimeBy(1000)
                compose.onNodeWithTag("reader.search.empty").assertIsDisplayed()
                capture("reader-search-empty")
            }
            if (next == "saved-main") {
                compose.onNodeWithTag("saved.filter.notes").performClick().assertIsSelected()
                capture("reader-saved-main-notes")
            }
            if (next == "saved") {
                compose.onNodeWithTag("reader.saved.tab.notes").performClick().assertIsSelected()
                compose.onNodeWithTag("reader.saved.empty").assertIsDisplayed()
                capture("reader-saved-notes-empty")
            }
        }
        for (locale in listOf("ar", "ur")) {
            compose.runOnIdle { previewLocale = locale; scene = "contents" }
            compose.waitForIdle()
            capture("normal-$locale-reader-contents")
            compose.runOnIdle { scene = "saved" }
            compose.waitForIdle()
            capture("normal-$locale-reader-saved")
        }
    }

    @Test fun firstInstallAndAccountRoutes() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val prefs = context.getSharedPreferences("onboarding", 0)
        val previous = prefs.all
        prefs.edit().clear().commit()
        try {
            compose.setContent { LocalizedPreview(ReaderTheme.DARK) { OnboardingFlow("en", {}, {}) } }
            compose.onNodeWithTag("onboarding.getStarted").assertIsDisplayed()
            capture("01-welcome")
            compose.onNodeWithTag("onboarding.getStarted").performClick()
            compose.onNodeWithTag("onboarding.continue").assertIsDisplayed()
            capture("02-language")
            compose.onNodeWithTag("onboarding.continue").performClick()
            compose.waitUntil(30_000) {
                compose.onAllNodesWithTag("onboarding.dailyText").fetchSemanticsNodes().isNotEmpty() ||
                    compose.onAllNodesWithTag("onboarding.dailyRetry").fetchSemanticsNodes().isNotEmpty()
            }
            val dailyText = compose.onAllNodesWithTag("onboarding.dailyText").fetchSemanticsNodes().isNotEmpty()
            if (dailyText) {
                compose.onNodeWithTag("onboarding.dailyText").assertIsDisplayed()
                capture("03-daily-hadith")
            } else {
                compose.onNodeWithTag("onboarding.dailyRetry").assertIsDisplayed()
                capture("03-daily-unavailable-retry")
            }
            compose.onNodeWithTag("onboarding.continue").performClick()
            compose.onNodeWithTag("onboarding.guest").assertIsDisplayed()
            capture("05-account")
            compose.onNodeWithTag("onboarding.signIn").performClick()
            compose.onNodeWithTag("signin.screen.methods").assertExists()
            capture("06-auth-methods")
            compose.onNodeWithTag("signin.createAccount").performScrollTo().performClick()
            compose.onNodeWithTag("signin.screen.sign_up").assertExists()
            capture("07-sign-up")
            compose.onNodeWithTag("signin.close").performClick()
            compose.onNodeWithTag("onboarding.signIn").performClick()
            compose.onNodeWithTag("signin.screen.methods").assertExists()
            compose.onNodeWithText("Continue with email").performScrollTo().performClick()
            compose.onNodeWithTag("signin.screen.password_sign_in").assertExists()
            capture("08-password")
            compose.onNodeWithTag("signin.forgot").performScrollTo().performClick()
            compose.onNodeWithTag("signin.screen.forgot_password_entry").assertExists()
            capture("09-recovery")
            compose.onNodeWithTag("signin.back").performClick()
            compose.onNodeWithTag("signin.useCode").performScrollTo().performClick()
            compose.onNodeWithTag("signin.screen.email_entry").assertExists()
            capture("10-email-code-entry")
        } finally {
            val edit = prefs.edit().clear()
            previous.forEach { (key, value) -> when (value) { is Int -> edit.putInt(key, value); is Boolean -> edit.putBoolean(key, value); is String -> edit.putString(key, value) } }
            edit.commit()
        }
    }

    @Test fun codeResetAndKeyboardPreviewStates() {
        var mode by mutableStateOf(SignInMode.CODE_ENTRY)
        var imeVisible = false
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        automation.executeShellCommand("settings put secure show_ime_with_hard_keyboard 1").close()
        compose.setContent { LocalizedPreview(ReaderTheme.LIGHT) {
            val imeBottom = WindowInsets.ime.getBottom(LocalDensity.current)
            SideEffect { imeVisible = imeBottom > 0 }
            key(mode) { SignInScreen({}, {}, previewMode = mode) }
        } }
        for (entry in listOf(SignInMode.METHODS, SignInMode.CODE_ENTRY, SignInMode.RESET_PASSWORD, SignInMode.SIGN_UP)) {
            compose.runOnIdle { mode = entry }
            if (entry == SignInMode.METHODS) {
                compose.onNodeWithText("Google sign-in opens in your browser and returns here.").assertIsDisplayed()
            }
            compose.waitUntil(10_000) { compose.onAllNodesWithTag("signin.screen.${entry.name.lowercase()}").fetchSemanticsNodes().isNotEmpty() }
            capture("auth-${entry.name.lowercase()}")
        }
        compose.onNodeWithText("you@example.com").performClick().performTextInput("reader@example.org")
        compose.waitUntil(10_000) { imeVisible }
        compose.onNodeWithText("Create account").performScrollTo().assertIsDisplayed()
        capture("sign-up-keyboard")
    }

    @Test fun bottomNavigationKeepsSelectionAndSupportsLargeRTLText() {
        var large by mutableStateOf(false)
        compose.setContent {
            LocalizedPreview(ReaderTheme.LIGHT) {
                CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, if (large) 2f else 1f),
                    LocalLayoutDirection provides if (large) LayoutDirection.Rtl else LayoutDirection.Ltr) {
                    var selected by remember { mutableIntStateOf(0) }
                    Surface(Modifier.fillMaxSize(), color = LocalHadithlyColors.current.background) {
                        androidx.compose.material3.Scaffold(containerColor = LocalHadithlyColors.current.background,
                            bottomBar = { HadithlyBottomNavigation(selected) { selected = it } }) { padding ->
                            Box(Modifier.padding(padding)) { com.hadithly.app.features.settings.SettingsScreen {} }
                        }
                    }
                }
            }
        }
        for (tag in listOf("today", "library", "saved", "settings")) {
            compose.onNodeWithTag("tabs.$tag").performClick().assertIsSelected()
        }
        capture("bottom-navigation")
        compose.runOnIdle { large = true }
        compose.onNodeWithTag("tabs.today").performClick().assertIsSelected()
        compose.onNodeWithTag("tabs.settings").performClick().assertIsSelected()
        capture("bottom-navigation-large-rtl")
    }

    @Test fun settingsSignInHidesTheUnderlyingAccessibilityTreeAndCancelRestoresTheTab() {
        val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as com.hadithly.app.HadithlyApplication
        val previous = app.settings.onboardingCompleted.value
        try {
            app.settings.setOnboardingCompleted(true)
            compose.setContent { LocalizedPreview(ReaderTheme.LIGHT) { com.hadithly.app.RootApp() } }
            compose.waitUntil(10_000) { compose.onAllNodesWithTag("tabs.settings").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithTag("tabs.settings").performClick()
            compose.onNodeWithTag("settings.signin").performClick()
            compose.onNodeWithText("Continue with email").performScrollTo().performClick()
            compose.onNodeWithTag("signin.screen.password_sign_in").assertIsDisplayed()
            compose.onNodeWithTag("tabs.settings").assertDoesNotExist()
            capture("settings-inline-sign-in")
            compose.onNodeWithTag("signin.close").performClick()
            compose.onNodeWithTag("tabs.settings").assertIsSelected()
            compose.onNodeWithTag("settings.signin").assertIsDisplayed()
        } finally { app.settings.setOnboardingCompleted(previous) }
    }

    @Test fun annualPricingPrototypeShowsMonthlyEquivalentAndNativeSelection() {
        var theme by mutableStateOf(ReaderTheme.LIGHT)
        compose.setContent { LocalizedPreview(theme) {
            var annual by remember { mutableStateOf(true) }
            Box(Modifier.fillMaxSize()) {
                EntryArtworkBackdrop()
                Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()
                    .verticalScroll(androidx.compose.foundation.rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                    com.hadithly.app.features.purchases.PaywallHeading()
                    com.hadithly.app.features.purchases.PaywallPlanOption(true, annual, "$2.08", 30) { annual = true }
                    com.hadithly.app.features.purchases.PaywallPlanOption(false, !annual, "$2.99", null) { annual = false }
                    androidx.compose.material3.Button(onClick = {}, enabled = false, modifier = Modifier.fillMaxWidth()) {
                        androidx.compose.material3.Text(androidx.compose.ui.res.stringResource(if (annual) com.hadithly.app.R.string.la2_subscribe_annual else com.hadithly.app.R.string.la2_subscribe_monthly))
                    }
                    com.hadithly.app.features.purchases.PaywallRenewalNotice()
                }
            }
        } }
        compose.onNodeWithTag("paywall.annual").assertIsSelected()
        compose.onNodeWithTag("paywall.quotaReason").assertExists()
        compose.onNodeWithText("$2.08").assertIsDisplayed()
        compose.onNodeWithText("$24.99").assertDoesNotExist()
        compose.onNodeWithTag("paywall.monthly").performClick().assertIsSelected()
        compose.onNodeWithTag("paywall.annual").performClick()
        compose.onNodeWithText("More AI translations").performScrollTo()
        capture("paywall-prototype-light")
        compose.runOnIdle { theme = ReaderTheme.DARK }
        capture("paywall-prototype-dark")
    }

    @Test fun paywallPrototypeKeepsPricesReadableAtLargeRTLSize() {
        var annual by mutableStateOf(true)
        compose.setContent { LocalizedPreview(ReaderTheme.LIGHT, "ar") {
            CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, 2f),
                LocalLayoutDirection provides LayoutDirection.Rtl) {
                Box(Modifier.fillMaxSize()) {
                    EntryArtworkBackdrop()
                    Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()
                        .verticalScroll(androidx.compose.foundation.rememberScrollState()).padding(24.dp),
                        verticalArrangement = Arrangement.spacedBy(20.dp)) {
                        com.hadithly.app.features.purchases.PaywallHeading()
                        com.hadithly.app.features.purchases.PaywallPlanOption(true, annual, "$2.08", 30) { annual = true }
                        com.hadithly.app.features.purchases.PaywallPlanOption(false, !annual, "$2.99", null) { annual = false }
                        com.hadithly.app.features.purchases.PaywallRenewalNotice()
                    }
                }
            }
        } }
        compose.onNodeWithTag("paywall.quotaReason").assertTextContains("استخدمت", substring = true)
        compose.onNodeWithText("$2.08").performScrollTo().assertIsDisplayed()
        capture("paywall-prototype-large-rtl-annual")
        compose.onNodeWithTag("paywall.monthly").performScrollTo().performClick().assertIsSelected()
        compose.onNodeWithText("$2.99").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("$24.99").assertDoesNotExist()
        capture("paywall-prototype-large-rtl-monthly")
    }

    @Test fun smallLargeTextAuthRemainsScrollable() {
        compose.setContent { LocalizedPreview(ReaderTheme.LIGHT) {
            CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, 2f), LocalLayoutDirection provides LayoutDirection.Rtl) {
                Box(Modifier.fillMaxWidth().height(560.dp)) { SignInScreen({}, {}, previewMode = SignInMode.SIGN_UP) }
            }
        } }
        compose.waitUntil(10_000) { compose.onAllNodesWithTag("signin.screen.sign_up").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Create account").performScrollTo().assertIsDisplayed()
        capture("sign-up-small-large-rtl")
    }

    private fun capture(name: String) {
        compose.waitForIdle()
        Thread.sleep(350) // Native window presentation completes outside the Compose test clock.
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        compose.waitUntil(5_000) {
            instrumentation.uiAutomation.rootInActiveWindow?.packageName?.toString() == instrumentation.targetContext.packageName
        }
        val file = File(instrumentation.targetContext.getExternalFilesDir(null), "finishing-$name.png")
        instrumentation.uiAutomation.takeScreenshot().let { bitmap ->
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }; bitmap.recycle()
        }
        instrumentation.uiAutomation.executeShellCommand("cp ${file.absolutePath} /sdcard/Pictures/finishing-$name.png").close()
    }

    @Test fun normalArabicAndUrduWelcomeAndAccountScreens() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val prefs = context.getSharedPreferences("onboarding", 0)
        val previous = prefs.all
        var route by mutableStateOf("ar-welcome")
        try {
            prefs.edit().clear().putInt("step", 0).commit()
            compose.setContent {
                key(route) {
                    val locale = route.substringBefore('-')
                    LocalizedPreview(ReaderTheme.LIGHT, locale) { OnboardingFlow(locale, {}, {}) }
                }
            }
            for (next in listOf("ar-welcome", "ar-account", "ur-welcome", "ur-account")) {
                if (next != route) compose.runOnIdle {
                    prefs.edit().putInt("step", if (next.endsWith("account")) 3 else 0).commit()
                    route = next
                }
                compose.waitForIdle()
                if (next.endsWith("welcome")) {
                    compose.onNodeWithTag("onboarding.getStarted").assertIsDisplayed()
                } else {
                    compose.onNodeWithTag("onboarding.signIn").assertIsDisplayed()
                    compose.onNodeWithTag("onboarding.guest").assertIsDisplayed()
                }
                capture("normal-$next")
            }
        } finally {
            val edit = prefs.edit().clear()
            previous.forEach { (key, value) -> when (value) { is Int -> edit.putInt(key, value); is Boolean -> edit.putBoolean(key, value); is String -> edit.putString(key, value) } }
            edit.commit()
        }
    }
}

@Composable
internal fun LocalizedPreview(theme: ReaderTheme, locale: String = "en", content: @Composable () -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val configuration = android.content.res.Configuration(androidx.compose.ui.platform.LocalConfiguration.current).apply { setLocale(java.util.Locale.forLanguageTag(locale)); setLayoutDirection(java.util.Locale.forLanguageTag(locale)) }
    val localized = context.createConfigurationContext(configuration)
    CompositionLocalProvider(androidx.compose.ui.platform.LocalConfiguration provides configuration,
        androidx.compose.ui.platform.LocalResources provides localized.resources,
        LocalLayoutDirection provides if (LocaleFallback.isRTL(locale)) LayoutDirection.Rtl else LayoutDirection.Ltr) { HadithlyTheme(theme, content) }
}
