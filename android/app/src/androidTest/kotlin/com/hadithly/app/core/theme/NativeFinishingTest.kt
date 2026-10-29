package com.hadithly.app.core.theme

import com.hadithly.app.core.preferences.nativeText

import android.graphics.Bitmap
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
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
