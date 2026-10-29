import XCTest
import UIKit

final class VisualPolishUITests: XCTestCase {
    func testProductionQuotaStaysInlineUntilPlansAreRequested() {
        let app = XCUIApplication()
        app.launchArguments = ["-NativePolishFixture"]
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "POLISH_SCREEN": "reader",
            "POLISH_THEME": "light", "PAGING_RENDER": "interactive", "Q1_STATE": "quota", "Q1_LANGUAGE": "ru"]
        app.launch()
        XCTAssertTrue(element("reader.page", app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["reader.quotaPaywall"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(element("paywall.quota", app).exists, "A translation limit must not interrupt reading")
        capture("quota-inline-production", app)
    }

    func testProductionFocusRetainsThinProgressAndTextPosition() {
        let app = XCUIApplication()
        app.launchArguments = ["-NativePolishFixture"]
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "POLISH_SCREEN": "reader",
            "POLISH_THEME": "paper", "PAGING_RENDER": "interactive"]
        app.launch()
        XCTAssertTrue(element("reader.page", app).waitForExistence(timeout: 10))
        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let menu = app.buttons["reader.menu"]
        if !menu.waitForExistence(timeout: 1) { center.tap() }
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        let text = app.staticTexts["reader.arabic"].firstMatch
        let textY = text.frame.minY
        center.tap()
        let progress = element("reader.focusedProgress", app)
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(progress.frame.height, 4)
        XCTAssertFalse(menu.exists)
        XCTAssertEqual(text.frame.minY, textY, accuracy: 1)
        capture("production-reader-focused-progress", app)
        center.tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertEqual(text.frame.minY, textY, accuracy: 1)
        capture("production-reader-controls-restored", app)
    }

    func testReaderMenuKeepsVisibleGapsBetweenGlassControls() {
        let app = XCUIApplication()
        app.launchArguments = ["-NativePolishFixture"]
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "POLISH_SCREEN": "reader",
            "POLISH_THEME": "paper", "PAGING_RENDER": "interactive"]
        app.launch()
        let menu = app.buttons["reader.menu"]
        XCTAssertTrue(element("reader.page", app).waitForExistence(timeout: 10))
        if !menu.waitForExistence(timeout: 1) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        let underlying = app.screenshot().image.cgImage!
        menu.tap()
        let contents = app.buttons["reader.menu.contents"]
        XCTAssertTrue(contents.waitForExistence(timeout: 5))
        capture("reader-menu-glass-gaps", app)
        let pairs = [(contents, app.buttons["reader.menu.saved"]),
                     (app.buttons["reader.menu.saved"], app.buttons["reader.menu.settings"])]
        for (upper, lower) in pairs {
            let point = CGPoint(x: upper.frame.midX, y: (upper.frame.maxY + lower.frame.minY) / 2)
            let before = pixel(in: app, at: point, from: underlying)
            let after = pixel(in: app, at: point)
            let difference = zip(before.prefix(3), after.prefix(3)).map { abs(Int($0) - Int($1)) }.reduce(0, +) / 3
            print("Reader menu gap average channel difference: \(difference)")
            XCTAssertLessThan(difference, 20, "Separate menu surfaces must leave the underlying reader visible through the gap")
        }
    }

    func testPageControlsUseSelectedLanguage() {
        for (locale, pageTemplate, previousTemplate, nextTemplate) in [
            ("en", "Page %1$@", "Previous page, %1$@", "Next page, %1$@"),
            ("ar", "الصفحة %1$@", "الصفحة السابقة، %1$@", "الصفحة التالية، %1$@"),
            ("ru", "Страница %1$@", "Предыдущая страница, %1$@", "Следующая страница, %1$@"),
            ("kk", "%1$@-бет", "Алдыңғы бет, %1$@", "Келесі бет, %1$@"),
            ("ky", "%1$@-бет", "Мурунку бет, %1$@", "Кийинки бет, %1$@"),
            ("uz", "%1$@-sahifa", "Oldingi sahifa, %1$@", "Keyingi sahifa, %1$@"),
            ("tr", "Sayfa %1$@", "Önceki sayfa, %1$@", "Sonraki sayfa, %1$@"),
            ("id", "Halaman %1$@", "Halaman sebelumnya, %1$@", "Halaman berikutnya, %1$@"),
            ("ur", "صفحہ %1$@", "پچھلا صفحہ، %1$@", "اگلا صفحہ، %1$@"),
            ("fr", "Page n° %1$@", "Page précédente, %1$@", "Page suivante, %1$@"),
            ("es-419", "Página %1$@", "Página anterior, %1$@", "Página siguiente, %1$@"),
            ("pt-BR", "Página %1$@", "Página anterior, %1$@", "Próxima página, %1$@"),
            ("sw", "Ukurasa %1$@", "Ukurasa uliotangulia, %1$@", "Ukurasa unaofuata, %1$@"),
            ("hi", "पृष्ठ %1$@", "पिछला पृष्ठ, %1$@", "अगला पृष्ठ, %1$@"),
            ("bn", "পৃষ্ঠা %1$@", "আগের পৃষ্ঠা, %1$@", "পরের পৃষ্ঠা, %1$@")
        ] {
            let value = Locale(identifier: locale)
            let page = String(format: pageTemplate, locale: value, arguments: [2.formatted(.number.locale(value))])
            for direction in ["ltr", "rtl"] {
                let app = launchPolish("reader", locale: locale, readingDirection: direction)
                let previous = app.buttons["reader.previousPage"].firstMatch
                let next = app.buttons["reader.nextPage"].firstMatch
                XCTAssertTrue(next.waitForExistence(timeout: 10))
                XCTAssertEqual(withoutDirectionalMarks(previous.label), withoutDirectionalMarks(String(format: previousTemplate, locale: value, arguments: ["Volume 1"])))
                XCTAssertEqual(withoutDirectionalMarks(next.label), withoutDirectionalMarks(String(format: nextTemplate, locale: value, arguments: [page])))
                XCTAssertEqual(previous.frame.minX > next.frame.minX, direction == "rtl")
                XCTAssertGreaterThanOrEqual(previous.frame.height, 44)
                XCTAssertGreaterThanOrEqual(next.frame.height, 44)
                capture("page-controls-" + locale + "-" + direction, app)
                next.tap()
                XCTAssertEqual(withoutDirectionalMarks(next.label), withoutDirectionalMarks(String(format: nextTemplate, locale: value, arguments: ["Volume 3"])))
                previous.tap()
                XCTAssertEqual(withoutDirectionalMarks(next.label), withoutDirectionalMarks(String(format: nextTemplate, locale: value, arguments: [page])))
                app.terminate()
            }
        }
    }

    func testProductionProgressLabelsUseTheUILocale() {
        for (locale, pageTemplate, volumeTemplate) in [
            ("en", "Page %1$@", "Volume %1$@ of %2$@"),
            ("ar", "الصفحة %1$@", "المجلد %1$@ من %2$@"),
            ("ru", "Страница %1$@", "Том %1$@ из %2$@"),
            ("kk", "%1$@-бет", "%2$@ томның %1$@-і"),
            ("ky", "%1$@-бет", "%2$@ томдун %1$@-си"),
            ("uz", "%1$@-sahifa", "%2$@ jilddan %1$@-jild"),
            ("tr", "Sayfa %1$@", "Cilt %1$@ / %2$@"),
            ("id", "Halaman %1$@", "Jilid %1$@ dari %2$@"),
            ("ur", "صفحہ %1$@", "جلد %1$@ از %2$@"),
            ("fr", "Page n° %1$@", "Volume %1$@ sur %2$@"),
            ("es-419", "Página %1$@", "Tomo %1$@ de %2$@"),
            ("pt-BR", "Página %1$@", "Volume %1$@ de %2$@"),
            ("sw", "Ukurasa %1$@", "Juzuu ya %1$@ kati ya %2$@"),
            ("hi", "पृष्ठ %1$@", "खंड %1$@, कुल %2$@"),
            ("bn", "পৃষ্ঠা %1$@", "খণ্ড %1$@ / %2$@")
        ] {
            let value = Locale(identifier: locale)
            let number = 1.formatted(.number.locale(value))
            let page = String(format: pageTemplate, locale: value, arguments: [number])
            let volume = String(format: volumeTemplate, locale: value, arguments: [number, number])
            let app = launchPolish("reader", locale: locale, production: true)
            XCTAssertTrue(element("reader.page", app).waitForExistence(timeout: 10))
            if !app.buttons["reader.menu"].waitForExistence(timeout: 1) {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            let progress = element("reader.unfocusedProgress", app)
            XCTAssertTrue(progress.waitForExistence(timeout: 5))
            XCTAssertEqual(withoutDirectionalMarks(progress.label), withoutDirectionalMarks(page + ", " + volume))
            capture("page-progress-" + locale, app)
            app.terminate()
        }
    }

    func testArabicOnlyVolumeNamesUseTheUILocale() {
        for (locale, expected) in [("ru", "Предыдущая страница, Том 1"), ("ar", "الصفحة السابقة، المجلد 1")] {
            let app = launchPolish("reader", locale: locale, arabicOnly: true)
            let previous = app.buttons["reader.previousPage"].firstMatch
            XCTAssertTrue(previous.waitForExistence(timeout: 10))
            XCTAssertEqual(withoutDirectionalMarks(previous.label), expected)
            capture("page-controls-arabic-only-" + locale, app)
            app.terminate()
        }
    }

    func testReaderCountsAndLanguageTotalRenderInEveryLocale() {
        for (locale, countTemplate, languagesTemplate) in [
            ("en", "%lld hadiths", "%lld languages available"),
            ("ar", "%lld أحاديث", "%lld لغة متاحة"),
            ("ru", "%lld хадиса", "%lld языков доступно"),
            ("kk", "%lld хадис", "%lld тіл қолжетімді"),
            ("ky", "%lld хадис", "%lld тил жеткиликтүү"),
            ("uz", "%lld hadis", "%lld ta til mavjud"),
            ("tr", "%lld hadis", "%lld dil kullanılabilir"),
            ("id", "%lld hadis", "%lld bahasa tersedia"),
            ("ur", "%lld احادیث", "%lld زبانیں دستیاب ہیں"),
            ("fr", "%lld hadiths", "%lld langues disponibles"),
            ("es-419", "%lld hadices", "%lld idiomas disponibles"),
            ("pt-BR", "%lld hadiths", "%lld idiomas disponíveis"),
            ("sw", "%lld hadithi", "%lld lugha zinapatikana"),
            ("hi", "%lld हदीस", "%lld भाषाएँ उपलब्ध"),
            ("bn", "%lld হাদিস", "%lldটি ভাষা উপলব্ধ")
        ] {
            let value = Locale(identifier: locale)
            let count = String(format: countTemplate, locale: value, arguments: [3])
            let total = String(format: languagesTemplate, locale: value, arguments: [15])
            let app = launchPolish("reader", locale: locale)
            let header = element("reader.volumeHeader", app)
            XCTAssertTrue(header.waitForExistence(timeout: 10))
            XCTAssertTrue(withoutDirectionalMarks(header.label).hasSuffix(count), header.label)
            capture("reader-count-" + locale, app)
            app.terminate()
            let settings = launchPolish("app-language", locale: locale)
            let footer = settings.staticTexts.matching(NSPredicate(format: "label == %@", total)).firstMatch
            if !footer.waitForExistence(timeout: 1) { settings.swipeUp() }
            XCTAssertTrue(footer.waitForExistence(timeout: 5), total)
            capture("language-count-" + locale, settings)
            settings.terminate()
        }
    }

    func testSavedTimestampUsesTheSelectedUILocale() {
        for locale in ["ar", "ru", "kk", "ky", "uz", "tr", "id", "ur", "fr", "es-419", "pt-BR", "sw", "hi", "bn", "en"] {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = Locale(identifier: locale)
            formatter.dateTimeStyle = .named
            formatter.unitsStyle = .full
            let expected = formatter.localizedString(from: DateComponents(second: 0))
            let app = launchPolish("saved-audit", locale: locale)
            let open = app.buttons["saved.open.audit-saved"]
            XCTAssertTrue(open.waitForExistence(timeout: 10))
            XCTAssertTrue(open.label.contains(expected), open.label)
            capture("saved-time-" + locale, app)
            app.terminate()
        }
    }

    func testHelpLabelsAndShareRepairRenderInEveryLocale() {
        for (locale, share, guides, contact, report) in [
            ("ar", "مشاركة Hadithly", "الأسئلة الشائعة والأدلة", "التواصل مع الدعم", "الإبلاغ عن مشكلة في الترجمة"),
            ("ru", "Поделиться Hadithly", "Вопросы и руководства", "Связаться с поддержкой", "Сообщить об ошибке перевода"),
            ("kk", "Hadithly бөлісу", "Сұрақтар мен нұсқаулықтар", "Қолдау қызметіне хабарласу", "Аударма мәселесін хабарлау"),
            ("id", "Bagikan Hadithly", "Pertanyaan dan panduan", "Hubungi dukungan", "Laporkan masalah terjemahan"),
            ("en", "Share Hadithly", "FAQ & guides", "Contact support", "Report a translation issue"),
            ("ky", "Hadithly’ди бөлүшүү", "Суроолор жана колдонмолор", "Колдоо кызматына кайрылуу", "Котормодогу көйгөйдү билдирүү"),
            ("uz", "Hadithly’ni ulashish", "Savollar va qoʻllanmalar", "Yordam xizmatiga murojaat qilish", "Tarjima muammosi haqida xabar berish"),
            ("tr", "Hadithly’yi paylaş", "Sorular ve kılavuzlar", "Destekle iletişime geç", "Çeviri sorunu bildir"),
            ("ur", "Hadithly شیئر کریں", "سوالات اور رہنما", "سپورٹ سے رابطہ کریں", "ترجمے کا مسئلہ رپورٹ کریں"),
            ("fr", "Partager Hadithly", "Questions et guides", "Contacter l’assistance", "Signaler un problème de traduction"),
            ("es-419", "Compartir Hadithly", "Preguntas y guías", "Contactar a soporte", "Reportar un problema de traducción"),
            ("pt-BR", "Compartilhar Hadithly", "Perguntas e guias", "Falar com o suporte", "Relatar um problema na tradução"),
            ("sw", "Shiriki Hadithly", "Maswali na miongozo", "Wasiliana na usaidizi", "Ripoti tatizo la tafsiri"),
            ("hi", "Hadithly साझा करें", "प्रश्न और मार्गदर्शिकाएँ", "सहायता से संपर्क करें", "अनुवाद की समस्या बताएँ"),
            ("bn", "Hadithly শেয়ার করুন", "প্রশ্ন ও নির্দেশিকা", "সহায়তায় যোগাযোগ করুন", "অনুবাদের সমস্যা জানান")
        ] {
            let app = launchPolish("help-audit", locale: locale)
            for label in [share, guides, contact, report] {
                let value = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
                for _ in 0..<6 where !value.exists { app.swipeUp() }
                XCTAssertTrue(value.exists, label)
            }
            capture("help-share-" + locale, app)
            app.terminate()
        }
    }

    func testAuthFieldsRetainLocalizedNamesAcrossAllPreviewStates() {
        for (locale, identifier, password, repeatPassword, email, code, newPassword, google, guest) in [
            ("ar", "البريد الإلكتروني أو اسم المستخدم", "كلمة المرور", "تأكيد كلمة المرور", "البريد الإلكتروني", "رمز التحقق", "كلمة مرور جديدة", "المتابعة باستخدام Google", "متابعة القراءة كضيف"),
            ("ru", "Почта или имя пользователя", "Пароль", "Повторите пароль", "Электронная почта", "Код подтверждения", "Новый пароль", "Продолжить с Google", "Продолжить чтение без входа"),
            ("kk", "Электрондық пошта немесе пайдаланушы аты", "Құпиясөз", "Құпиясөзді қайталау", "Электрондық пошта", "Растау коды", "Жаңа құпиясөз", "Google арқылы жалғастыру", "Қонақ ретінде оқуды жалғастыру"),
            ("id", "Email atau nama pengguna", "Kata sandi", "Ulangi kata sandi", "Email", "Kode verifikasi", "Kata sandi baru", "Lanjutkan dengan Google", "Lanjutkan membaca sebagai tamu"),
            ("en", "Email or username", "Password", "Repeat password", "Email", "Verification code", "New password", "Continue with Google", "Keep reading as a guest"),
            ("ky", "Электрондук почта же колдонуучу аты", "Сырсөз", "Сырсөздү кайталаңыз", "Электрондук почта", "Ырастоо коду", "Жаңы сырсөз", "Google аркылуу улантуу", "Конок катары окууну улантуу"),
            ("uz", "Elektron pochta yoki foydalanuvchi nomi", "Parol", "Parolni takrorlang", "Elektron pochta", "Tasdiqlash kodi", "Yangi parol", "Google orqali davom etish", "Mehmon sifatida oʻqishni davom ettirish"),
            ("tr", "E-posta veya kullanıcı adı", "Parola", "Parolayı tekrarla", "E-posta", "Doğrulama kodu", "Yeni parola", "Google ile devam et", "Misafir olarak okumaya devam et"),
            ("ur", "ای میل یا صارف نام", "پاس ورڈ", "پاس ورڈ دوبارہ لکھیں", "ای میل", "تصدیقی کوڈ", "نیا پاس ورڈ", "Google کے ساتھ جاری رکھیں", "مہمان کے طور پر پڑھنا جاری رکھیں"),
            ("fr", "E-mail ou nom d’utilisateur", "Mot de passe", "Répéter le mot de passe", "E-mail", "Code de vérification", "Nouveau mot de passe", "Continuer avec Google", "Continuer la lecture sans compte"),
            ("es-419", "Correo o nombre de usuario", "Contraseña", "Repetir contraseña", "Correo electrónico", "Código de verificación", "Nueva contraseña", "Continuar con Google", "Seguir leyendo como invitado"),
            ("pt-BR", "E-mail ou nome de usuário", "Senha", "Repetir senha", "E-mail", "Código de verificação", "Nova senha", "Continuar com Google", "Continuar lendo como visitante"),
            ("sw", "Barua pepe au jina la mtumiaji", "Nenosiri", "Rudia nenosiri", "Barua pepe", "Msimbo wa uthibitishaji", "Nenosiri jipya", "Endelea kwa Google", "Endelea kusoma kama mgeni"),
            ("hi", "ईमेल या उपयोगकर्ता नाम", "पासवर्ड", "पासवर्ड दोहराएँ", "ईमेल", "सत्यापन कोड", "नया पासवर्ड", "Google के साथ जारी रखें", "अतिथि के रूप में पढ़ना जारी रखें"),
            ("bn", "ইমেইল বা ব্যবহারকারীর নাম", "পাসওয়ার্ড", "পাসওয়ার্ড আবার লিখুন", "ইমেইল", "যাচাইকরণ কোড", "নতুন পাসওয়ার্ড", "Google দিয়ে চালিয়ে যান", "অতিথি হিসেবে পড়া চালিয়ে যান")
        ] {
            let app = launchPolish("auth-audit", locale: locale)
            XCTAssertTrue(app.buttons["signin.google"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["signin.google"].label.contains(google))
            XCTAssertTrue(app.buttons[guest].exists)
            let legalLines = [
                "en": "By continuing, you agree to our Terms of Use. Read our Privacy Policy.",
                "ar": "بالمتابعة، فإنك توافق على شروط الاستخدام. اقرأ سياسة الخصوصية.",
                "ru": "Продолжая, вы принимаете документ «Условия использования». Прочитайте документ «Политика конфиденциальности».",
                "kk": "Жалғастыру арқылы Пайдалану шарттары құжатын қабылдайсыз. Құпиялық саясаты құжатын оқыңыз.",
                "ky": "Улантуу менен Колдонуу шарттары документин кабыл аласыз. Купуялык саясаты документин окуңуз.",
                "uz": "Davom etish orqali Foydalanish shartlari hujjatiga rozilik bildirasiz. Maxfiylik siyosati hujjatini oʻqing.",
                "tr": "Devam ederek Kullanım Koşulları metnini kabul edersiniz. Gizlilik Politikası metnini okuyun.",
                "id": "Dengan melanjutkan, Anda menyetujui Ketentuan Penggunaan. Baca Kebijakan Privasi.",
                "ur": "جاری رکھنے سے آپ استعمال کی شرائط سے اتفاق کرتے ہیں۔ ہماری رازداری کی پالیسی پڑھیں۔",
                "fr": "En continuant, vous acceptez nos Conditions d’utilisation. Consultez notre Politique de confidentialité.",
                "es-419": "Al continuar, aceptas nuestros Términos de uso. Lee nuestra Política de privacidad.",
                "pt-BR": "Ao continuar, você aceita nossos Termos de uso. Leia nossa Política de privacidade.",
                "sw": "Kwa kuendelea, unakubali Masharti ya matumizi yetu. Soma Sera ya faragha yetu.",
                "hi": "जारी रखकर आप हमारी उपयोग की शर्तें स्वीकार करते हैं। हमारी निजता नीति पढ़ें।",
                "bn": "চালিয়ে গেলে আপনি আমাদের ব্যবহারের শর্তাবলি মেনে নিচ্ছেন। আমাদের গোপনীয়তা নীতি পড়ুন।"
            ]
            XCTAssertEqual(withoutDirectionalMarks(element("signin.legal", app).label), legalLines[locale])
            capture("auth-methods-" + locale, app)
            app.buttons["fixture.auth.password"].tap()
            let field = app.textFields["signin.identifier.field"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            XCTAssertEqual(field.label, identifier)
            field.tap(); field.typeText("reader@example.org")
            XCTAssertEqual(field.label, identifier)
            XCTAssertEqual(app.secureTextFields["signin.password.field"].label, password)
            capture("auth-password-" + locale, app)
            app.buttons["fixture.auth.signup"].tap()
            XCTAssertEqual(app.textFields["signup.email.field"].label, email)
            XCTAssertEqual(app.secureTextFields["signup.confirmPassword.field"].label, repeatPassword)
            capture("auth-signup-" + locale, app)
            app.buttons["fixture.auth.email"].tap()
            XCTAssertEqual(app.textFields["signin.email.field"].label, email)
            capture("auth-email-" + locale, app)
            app.buttons["fixture.auth.forgot"].tap()
            XCTAssertEqual(app.textFields["signin.forgotEmail.field"].label, email)
            capture("auth-forgot-" + locale, app)
            app.buttons["fixture.auth.code"].tap()
            XCTAssertEqual(app.textFields["signin.code.field"].label, code)
            capture("auth-code-" + locale, app)
            app.buttons["fixture.auth.reset"].tap()
            XCTAssertEqual(app.textFields["signin.resetCode.field"].label, code)
            XCTAssertEqual(app.secureTextFields["signin.newPassword.field"].label, newPassword)
            capture("auth-reset-" + locale, app)
            app.terminate()
        }
    }

    func testSavedRowAnnouncesLocalizedPrivateStatesAndActions() {
        for (locale, bookmark, favorite, note, actions) in [
            ("ar", "تم وضع إشارة مرجعية", "تمت الإضافة إلى المفضلة", "يتضمن ملاحظة", "إجراءات العنصر المحفوظ"),
            ("ru", "В закладках", "В избранном", "Есть заметка", "Действия с сохранённым"),
            ("kk", "Бетбелгі қойылған", "Таңдаулыларға қосылған", "Жазбасы бар", "Сақталған элемент әрекеттері"),
            ("id", "Ditandai", "Ditambahkan ke favorit", "Memiliki catatan", "Tindakan item tersimpan"),
            ("en", "Bookmarked", "Favorited", "Has note", "Saved item actions"),
            ("ky", "Кыстарма коюлган", "Тандалмаларга кошулган", "Жазуусу бар", "Сакталган нерсенин аракеттери"),
            ("uz", "Xatchoʻp qoʻyilgan", "Sevimlilarga qoʻshilgan", "Qaydi bor", "Saqlangan element amallari"),
            ("tr", "Yer imlerine eklendi", "Favorilere eklendi", "Notu var", "Kaydedilen öğe işlemleri"),
            ("ur", "بُک مارک کیا گیا", "پسندیدہ میں شامل ہے", "نوٹ موجود ہے", "محفوظ مواد کے اختیارات"),
            ("fr", "Marqué", "Ajouté aux favoris", "Contient une note", "Actions sur l’élément enregistré"),
            ("es-419", "Con marcador", "Agregado a favoritos", "Tiene una nota", "Acciones del elemento guardado"),
            ("pt-BR", "Com marcador", "Adicionado aos favoritos", "Tem uma nota", "Ações do item salvo"),
            ("sw", "Imewekewa alamisho", "Imeongezwa kwenye vipendwa", "Ina dokezo", "Vitendo vya kilichohifadhiwa"),
            ("hi", "बुकमार्क किया गया", "पसंदीदा में जोड़ा गया", "नोट है", "सहेजे गए आइटम की कार्रवाइयाँ"),
            ("bn", "বুকমার্ক করা আছে", "পছন্দের তালিকায় যোগ করা আছে", "নোট আছে", "সংরক্ষিত বিষয়ের বিকল্প")
        ] {
            let app = launchPolish("saved-audit", locale: locale)
            let open = app.buttons["saved.open.audit-saved"]
            XCTAssertTrue(open.waitForExistence(timeout: 10))
            for value in ["Source reference", bookmark, favorite, note] { XCTAssertTrue(open.label.contains(value), open.label) }
            XCTAssertTrue(app.buttons[actions].exists)
            XCTAssertTrue(app.staticTexts["Private note"].exists)
            capture("saved-accessibility-" + locale, app)
            app.buttons["saved.preview.audit-saved"].tap()
            XCTAssertTrue(app.staticTexts["Private note"].exists)
            app.terminate()
        }
    }

    func testReaderTranslationPreviewAndDisclosureUseSelectedLanguages() {
        for (locale, preview, disclosure) in [
            ("ar", "اقرأ النص الأصلي، وافهم معناه بلغتك.", "تُميَّز ترجمات الذكاء الاصطناعي وقد تحتوي على أخطاء. تظهر تفاصيل المصادر عند توفرها."),
            ("ru", "Читайте оригинал и понимайте его смысл на своём языке.", "Переводы ИИ помечены и могут содержать ошибки. Сведения об источниках показываются при наличии."),
            ("kk", "Түпнұсқа мәтінді оқып, мағынасын өз тіліңізде түсініңіз.", "ЖИ аудармалары белгіленеді және қателер болуы мүмкін. Дереккөз мәліметтері бар болса көрсетіледі."),
            ("id", "Baca teks asli dan pahami maknanya dalam bahasa Anda.", "Terjemahan AI diberi label dan dapat mengandung kesalahan. Detail sumber ditampilkan jika tersedia."),
            ("en", "Read the original text and understand its meaning in your language.", "AI translations are labeled and may contain errors. Source details appear when available."),
            ("ky", "Түп нуска текстти окуп, маанисин өз тилиңизде түшүнүңүз.", "ЖИ котормолору белгиленет жана каталарды камтышы мүмкүн. Булак маалыматы бар болсо көрсөтүлөт."),
            ("uz", "Asl matnni o‘qing va ma’nosini o‘z tilingizda tushuning.", "SI tarjimalari belgilangan va xatolarni oʻz ichiga olishi mumkin. Manba tafsilotlari mavjud boʻlsa koʻrsatiladi."),
            ("tr", "Özgün metni okuyun ve anlamını kendi dilinizde anlayın.", "Yapay zekâ çevirileri etiketlenir ve hata içerebilir. Kaynak bilgileri mevcut olduğunda gösterilir."),
            ("ur", "اصل متن پڑھیں اور اس کا مطلب اپنی زبان میں سمجھیں۔", "AI تراجم کی نشاندہی کی جاتی ہے اور ان میں غلطیاں ہو سکتی ہیں۔ ذرائع کی تفصیلات دستیاب ہونے پر دکھائی جاتی ہیں۔"),
            ("fr", "Lisez le texte original et comprenez-en le sens dans votre langue.", "Les traductions par IA sont signalées et peuvent contenir des erreurs. Les sources sont détaillées lorsqu’elles sont disponibles."),
            ("es-419", "Lee el texto original y entiende su significado en tu idioma.", "Las traducciones con IA están identificadas y pueden contener errores. Los detalles de las fuentes aparecen cuando están disponibles."),
            ("pt-BR", "Leia o texto original e entenda seu significado no seu idioma.", "As traduções por IA são identificadas e podem conter erros. Os detalhes das fontes aparecem quando disponíveis."),
            ("sw", "Soma maandishi ya asili na uelewe maana yake kwa lugha yako.", "Tafsiri za AI zinawekewa alama na zinaweza kuwa na makosa. Maelezo ya vyanzo huonekana yanapopatikana."),
            ("hi", "मूल पाठ पढ़ें और उसका अर्थ अपनी भाषा में समझें।", "AI अनुवाद चिह्नित होते हैं और उनमें त्रुटियाँ हो सकती हैं। स्रोतों का विवरण उपलब्ध होने पर दिखाया जाता है।"),
            ("bn", "মূল পাঠ পড়ুন এবং আপনার ভাষায় এর অর্থ বুঝুন।", "AI অনুবাদ চিহ্নিত থাকে এবং এতে ভুল থাকতে পারে। উৎসের বিবরণ পাওয়া গেলে দেখানো হয়।")
        ] {
            let app = launchPolish("reader-translation-settings", locale: locale, translationLocale: locale)
            let example = app.staticTexts.matching(NSPredicate(format: "label == %@", preview)).firstMatch
            XCTAssertTrue(example.waitForExistence(timeout: 10))
            capture("reader-translation-preview-" + locale, app)
            let footer = app.staticTexts.matching(NSPredicate(format: "label == %@", disclosure)).firstMatch
            for _ in 0..<8 where !footer.isHittable { app.swipeUp() }
            XCTAssertTrue(footer.isHittable)
            capture("reader-translation-disclosure-" + locale, app)
            app.terminate()
        }
    }

    func testAppAppearanceLabelsLocalizeWithoutMergingReaderChoices() {
        for (locale, title, separate, system, light) in [
            ("ar", "مظهر التطبيق", "استخدام مظهر منفصل للقارئ", "النظام", "فاتح"),
            ("ru", "Внешний вид приложения", "Использовать отдельное оформление для чтения", "Как в системе", "Светлая"),
            ("kk", "Қолданба көрінісі", "Оқу үшін бөлек көріністі пайдалану", "Жүйелік", "Ашық"),
            ("id", "Tampilan aplikasi", "Gunakan tampilan pembaca terpisah", "Sistem", "Terang"),
            ("en", "App appearance", "Use a separate reader appearance", "System", "Light"),
            ("ky", "Колдонмонун көрүнүшү", "Окуу үчүн өзүнчө көрүнүштү колдонуу", "Тутумдук", "Жарык"),
            ("uz", "Ilova ko‘rinishi", "Oʻqish uchun alohida koʻrinishdan foydalanish", "Tizim", "Yorugʻ"),
            ("tr", "Uygulama görünümü", "Okuma için ayrı bir görünüm kullan", "Sistem", "Açık"),
            ("ur", "ایپ کی ظاہری شکل", "مطالعے کے لیے الگ ظاہری شکل استعمال کریں", "سسٹم", "روشن"),
            ("fr", "Apparence de l’application", "Utiliser une apparence de lecture distincte", "Système", "Clair"),
            ("es-419", "Apariencia de la app", "Usar una apariencia de lectura independiente", "Sistema", "Claro"),
            ("pt-BR", "Aparência do app", "Usar aparência de leitura separada", "Sistema", "Claro"),
            ("sw", "Mwonekano wa programu", "Tumia mwonekano tofauti wa usomaji", "Mfumo", "Angavu"),
            ("hi", "ऐप का रूप", "पढ़ने के लिए अलग रूप इस्तेमाल करें", "सिस्टम", "हल्का"),
            ("bn", "অ্যাপের চেহারা", "পড়ার জন্য আলাদা চেহারা ব্যবহার করুন", "সিস্টেম", "হালকা")
        ] {
            let app = launchPolish("app-appearance", locale: locale)
            let toggle = app.switches["settings.appearance.separateReader"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 10))
            XCTAssertTrue(toggle.label.contains(separate))
            XCTAssertTrue(app.staticTexts[title].exists)
            XCTAssertTrue(element("settings.appearance.system", app).label.contains(system))
            XCTAssertTrue(element("settings.appearance.light", app).label.contains(light))
            XCTAssertFalse(element("settings.readerAppearance.system", app).exists)
            capture("app-appearance-" + locale, app)
            app.terminate()
        }
    }

    func testPrivacyDisclosuresRenderInEveryLocaleWithoutChangingConsent() {
        for (locale, usage, analytics, crash, policies, download, privacy, terms, deletion) in [
            ("ar", "مشاركة إحصاءات الاستخدام الخاصة", "شارك إحصاءات أساسية عن التطبيق للمساعدة في تحسين Hadithly. لا تتضمن مطلقًا نصوص قراءتك أو ملاحظاتك أو تفاصيل حسابك. يؤدي إيقاف هذا الخيار إلى مسح الإحصاءات التي تنتظر الإرسال.", "تساعدنا تقارير الأعطال على إصلاح المشكلات. ولا تتضمن مطلقًا نصوص قراءتك أو ملاحظاتك أو تفاصيل حسابك. يؤدي إيقافها إلى مسح التقارير المعلّقة على هذا الجهاز.", "السياسات", "نزّل ملفك الشخصي وإعداداتك والعناصر المحفوظة والمجلدات وتقدّم القراءة ومساهماتك. تبقى بيانات الضيف على هذا الجهاز.", "سياسة الخصوصية", "شروط الاستخدام", "كيفية حذف البيانات"),
            ("ru", "Делиться обезличенной статистикой", "Делитесь базовой статистикой работы приложения, чтобы помочь улучшить Hadithly. Текст, который вы читаете, ваши заметки и данные аккаунта никогда не включаются. Отключение удаляет статистику, ожидающую отправки.", "Отчёты о сбоях помогают нам исправлять проблемы. Они никогда не содержат текст, который вы читаете, ваши заметки или данные аккаунта. Отключение удаляет ожидающие отправки отчёты на этом устройстве.", "Политики", "Скачайте свой профиль, настройки, сохранённые элементы, папки, прогресс чтения и свои материалы. Данные гостя остаются на этом устройстве.", "Политика конфиденциальности", "Условия использования", "Как удаляются данные"),
            ("kk", "Жеке пайдалану статистикасын бөлісу", "Hadithly қолданбасын жақсартуға көмектесу үшін қолданбаның негізгі статистикасын бөлісіңіз. Оқитын мәтіндеріңіз, жазбаларыңыз және тіркелгі деректеріңіз ешқашан жіберілмейді. Бұл мүмкіндікті өшірсеңіз, жіберуді күтіп тұрған статистика жойылады.", "Істен шығу туралы есептер ақауларды түзетуге көмектеседі. Оларға сіз оқитын мәтіндер, жазбаларыңыз немесе тіркелгі деректеріңіз ешқашан кірмейді. Өшіру осы құрылғыдағы жіберілуді күтіп тұрған есептерді тазалайды.", "Саясаттар", "Профиліңізді, баптауларды, сақталған элементтерді, қалталарды, оқу барысын және қосқан материалдарыңызды жүктеп алыңыз. Қонақ деректері осы құрылғыда қалады.", "Құпиялық саясаты", "Пайдалану шарттары", "Деректерді жою тәртібі"),
            ("id", "Bagikan statistik penggunaan privat", "Bagikan statistik dasar aplikasi untuk membantu meningkatkan Hadithly. Teks bacaan, catatan, dan detail akun Anda tidak pernah disertakan. Menonaktifkan opsi ini akan menghapus statistik yang menunggu untuk dikirim.", "Laporan kerusakan membantu kami memperbaiki masalah. Laporan ini tidak pernah menyertakan teks bacaan, catatan, atau detail akun Anda. Menonaktifkannya menghapus laporan yang menunggu dikirim di perangkat ini.", "Kebijakan", "Unduh profil, pengaturan, item tersimpan, folder, kemajuan membaca, dan kontribusi Anda. Data tamu tetap berada di perangkat ini.", "Kebijakan Privasi", "Ketentuan Penggunaan", "Cara penghapusan data"),
            ("en", "Share private usage statistics", "Share basic app statistics to help improve Hadithly. Your reading text, notes and account details are never included. Turning this off clears pending statistics.", "Crash reports help us fix problems. They never include your reading text, notes or account details. Turning this off clears pending reports on this device.", "Policies", "Download your profile, settings, saved items, folders, reading progress and contributions. Guest data stays on this device.", "Privacy Policy", "Terms of Use", "How deletion works"),
            ("ky", "Жеке колдонуу статистикасын бөлүшүү", "Hadithly тиркемесин жакшыртуу үчүн колдонмонун негизги статистикасын бөлүшүңүз. Сиз окуган текст, жазууларыңыз жана каттоо эсебиңиздин маалыматы эч качан кошулбайт. Бул мүмкүнчүлүктү өчүрсөңүз, жөнөтүүнү күтүп турган статистика тазаланат.", "Иштен чыгуу тууралуу отчеттор көйгөйлөрдү оңдоого жардам берет. Аларда сиз окуган текст, жазууларыңыз же каттоо эсебиңиздин маалыматы эч качан камтылбайт. Өчүрүү бул түзмөктөгү жөнөтүлө элек отчетторду тазалайт.", "Саясаттар", "Профилиңизди, жөндөөлөрдү, сакталган нерселерди, папкаларды, окуу жүрүшүн жана кошкон материалдарыңызды жүктөп алыңыз. Коноктун дайындары ушул түзмөктө калат.", "Купуялык саясаты", "Колдонуу шарттары", "Маалыматтарды өчүрүү тартиби"),
            ("uz", "Shaxsiy foydalanish statistikasini ulashish", "Hadithly ilovasini yaxshilashga yordam berish uchun ilovaning asosiy statistikasini ulashing. Siz oʻqiyotgan matn, qaydlaringiz va hisobingizga oid maʼlumotlar hech qachon kiritilmaydi. Bu imkoniyatni oʻchirish yuborilishni kutayotgan statistikani tozalaydi.", "Nosozlik hisobotlari muammolarni tuzatishimizga yordam beradi. Ularga siz oʻqiyotgan matn, qaydlaringiz yoki hisobingizga oid maʼlumotlar hech qachon kiritilmaydi. Buni oʻchirish ushbu qurilmadagi yuborilishini kutayotgan hisobotlarni tozalaydi.", "Siyosatlar", "Profilingiz, sozlamalar, saqlangan elementlar, papkalar, oʻqish jarayoni va hissalaringizni yuklab oling. Mehmon maʼlumotlari shu qurilmada qoladi.", "Maxfiylik siyosati", "Foydalanish shartlari", "Maʼlumotlar qanday oʻchiriladi"),
            ("tr", "Özel kullanım istatistiklerini paylaş", "Hadithly uygulamasını iyileştirmeye yardımcı olmak için temel uygulama istatistiklerini paylaşın. Okuduğunuz metinler, notlarınız ve hesap bilgileriniz hiçbir zaman dahil edilmez. Bu seçeneği kapatmak gönderilmeyi bekleyen istatistikleri temizler.", "Çökme raporları sorunları gidermemize yardımcı olur. Okuduğunuz metinleri, notlarınızı veya hesap bilgilerinizi hiçbir zaman içermezler. Kapatıldığında bu cihazda gönderilmeyi bekleyen raporlar silinir.", "Politikalar", "Profilinizi, ayarlarınızı, kaydedilen öğeleri, klasörleri, okuma ilerlemesini ve katkılarınızı indirin. Misafir verileri bu cihazda kalır.", "Gizlilik Politikası", "Kullanım Koşulları", "Veriler nasıl silinir"),
            ("ur", "نجی استعمال کے اعدادوشمار شیئر کریں", "Hadithly کو بہتر بنانے میں مدد کے لیے ایپ کے بنیادی اعداد و شمار شیئر کریں۔ آپ کے پڑھے جانے والے متن، نوٹس اور اکاؤنٹ کی تفصیلات کبھی شامل نہیں ہوتیں۔ اسے بند کرنے سے بھیجے جانے کے منتظر اعداد و شمار صاف ہو جاتے ہیں۔", "کریش رپورٹس مسائل درست کرنے میں ہماری مدد کرتی ہیں۔ ان میں آپ کے پڑھے جانے والے متن، نوٹس یا اکاؤنٹ کی تفصیلات کبھی شامل نہیں ہوتیں۔ اسے بند کرنے سے اس آلے پر بھیجے جانے کے منتظر رپورٹس صاف ہو جاتی ہیں۔", "پالیسیاں", "اپنا پروفائل، ترتیبات، محفوظ کردہ آئٹمز، فولڈرز، پڑھنے کی پیش رفت اور اپنی شراکتیں ڈاؤن لوڈ کریں۔ مہمان کا ڈیٹا اسی ڈیوائس پر رہتا ہے۔", "رازداری کی پالیسی", "استعمال کی شرائط", "ڈیٹا کیسے حذف ہوتا ہے"),
            ("fr", "Partager des statistiques d’utilisation privées", "Partagez des statistiques de base sur l’application pour aider à améliorer Hadithly. Le texte que vous lisez, vos notes et les détails de votre compte ne sont jamais inclus. La désactivation efface les statistiques en attente d’envoi.", "Les rapports de plantage nous aident à corriger les problèmes. Ils ne contiennent jamais le texte que vous lisez, vos notes ni les détails de votre compte. La désactivation efface les rapports en attente sur cet appareil.", "Politiques", "Téléchargez votre profil, vos réglages, vos éléments enregistrés, vos dossiers, votre progression de lecture et vos contributions. Les données du mode invité restent sur cet appareil.", "Politique de confidentialité", "Conditions d’utilisation", "Fonctionnement de la suppression"),
            ("es-419", "Compartir estadísticas privadas de uso", "Comparte estadísticas básicas de la app para ayudar a mejorar Hadithly. Nunca se incluyen el texto que lees, tus notas ni los datos de tu cuenta. Al desactivar esta opción, se borran las estadísticas pendientes de envío.", "Los informes de cierres inesperados nos ayudan a solucionar problemas. Nunca incluyen el texto que lees, tus notas ni los datos de tu cuenta. Desactivar esta opción borra los informes pendientes de este dispositivo.", "Políticas", "Descarga tu perfil, configuración, elementos guardados, carpetas, progreso de lectura y contribuciones. Los datos de invitado permanecen en este dispositivo.", "Política de privacidad", "Términos de uso", "Cómo se eliminan los datos"),
            ("pt-BR", "Compartilhar estatísticas privadas de uso", "Compartilhe estatísticas básicas do aplicativo para ajudar a melhorar o Hadithly. O texto que você lê, suas notas e os dados da sua conta nunca são incluídos. Desativar esta opção limpa as estatísticas pendentes de envio.", "Os relatórios de falhas nos ajudam a corrigir problemas. Eles nunca incluem o texto que você lê, suas notas ou os dados da sua conta. Desativar essa opção apaga os relatórios pendentes neste dispositivo.", "Políticas", "Baixe seu perfil, configurações, itens salvos, pastas, progresso de leitura e contribuições. Os dados de visitante permanecem neste dispositivo.", "Política de privacidade", "Termos de uso", "Como os dados são excluídos"),
            ("sw", "Shiriki takwimu za matumizi binafsi", "Shiriki takwimu za msingi za programu ili kusaidia kuboresha Hadithly. Maandishi unayosoma, madokezo yako na maelezo ya akaunti yako hayajumuishwi kamwe. Kuzima chaguo hili hufuta takwimu zinazosubiri kutumwa.", "Ripoti za hitilafu hutusaidia kurekebisha matatizo. Hazijumuishi kamwe maandishi unayosoma, madokezo yako au maelezo ya akaunti yako. Kuzima chaguo hili hufuta ripoti zinazosubiri kutumwa kwenye kifaa hiki.", "Sera", "Pakua wasifu wako, mipangilio, vipengee ulivyohifadhi, folda, maendeleo ya usomaji na michango yako. Data ya mgeni hubaki kwenye kifaa hiki.", "Sera ya faragha", "Masharti ya matumizi", "Jinsi data inavyofutwa"),
            ("hi", "निजी उपयोग आँकड़े साझा करें", "Hadithly को बेहतर बनाने में मदद के लिए ऐप के बुनियादी आँकड़े साझा करें। आपके पढ़े जाने वाले पाठ, नोट्स और खाते की जानकारी कभी शामिल नहीं होती। इसे बंद करने पर भेजे जाने की प्रतीक्षा कर रहे आँकड़े मिट जाते हैं।", "क्रैश रिपोर्ट हमें समस्याएँ ठीक करने में मदद करती हैं। इनमें आपके पढ़े जाने वाले पाठ, नोट्स या खाते की जानकारी कभी शामिल नहीं होती। इसे बंद करने से इस डिवाइस पर भेजे जाने की प्रतीक्षा कर रही रिपोर्ट मिट जाती हैं।", "नीतियाँ", "अपनी प्रोफ़ाइल, सेटिंग्स, सहेजे गए आइटम, फ़ोल्डर, पढ़ने की प्रगति और योगदान डाउनलोड करें। अतिथि का डेटा इसी डिवाइस पर रहता है।", "निजता नीति", "उपयोग की शर्तें", "डेटा कैसे मिटाया जाता है"),
            ("bn", "ব্যক্তিগত ব্যবহার পরিসংখ্যান শেয়ার করুন", "Hadithly উন্নত করতে সাহায্য করার জন্য অ্যাপের মৌলিক পরিসংখ্যান শেয়ার করুন। আপনি যে লেখা পড়ছেন, আপনার নোট ও অ্যাকাউন্টের তথ্য কখনো অন্তর্ভুক্ত হয় না। এটি বন্ধ করলে পাঠানোর অপেক্ষায় থাকা পরিসংখ্যান মুছে যায়।", "ক্র্যাশ রিপোর্ট আমাদের সমস্যা ঠিক করতে সাহায্য করে। এতে আপনি যে লেখা পড়ছেন, আপনার নোট বা অ্যাকাউন্টের তথ্য কখনো অন্তর্ভুক্ত হয় না। এটি বন্ধ করলে এই ডিভাইসে পাঠানোর অপেক্ষায় থাকা রিপোর্ট মুছে যায়।", "নীতিমালা", "আপনার প্রোফাইল, সেটিংস, সংরক্ষিত আইটেম, ফোল্ডার, পড়ার অগ্রগতি ও অবদান ডাউনলোড করুন। অতিথির ডেটা এই ডিভাইসেই থাকে।", "গোপনীয়তা নীতি", "ব্যবহারের শর্তাবলি", "ডেটা কীভাবে মুছে ফেলা হয়")
        ] {
            let app = launchPolish("privacy", locale: locale)
            let usageSwitch = app.switches["settings.usageStatistics"]
            XCTAssertTrue(usageSwitch.waitForExistence(timeout: 10))
            XCTAssertTrue(usageSwitch.label.contains(usage))
            let crashSwitch = app.switches["settings.crashReports"]
            XCTAssertTrue(crashSwitch.exists)
            let usageBefore = usageSwitch.value as? String
            let crashBefore = crashSwitch.value as? String
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", analytics)).firstMatch.exists)
            for message in [crash, download, policies] {
                let text = app.staticTexts.matching(NSPredicate(format: "label == %@", message)).firstMatch
                for _ in 0..<6 where !text.exists { app.swipeUp() }
                XCTAssertTrue(text.exists, message)
                if message == crash { capture("privacy-disclosures-" + locale, app) }
            }
            for title in [privacy, terms, deletion] {
                let link = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
                for _ in 0..<6 where !link.isHittable { app.swipeUp() }
                XCTAssertTrue(link.isHittable, title)
            }
            capture("privacy-policies-" + locale, app)
            for _ in 0..<6 where !usageSwitch.isHittable { app.swipeDown() }
            XCTAssertEqual(usageSwitch.value as? String, usageBefore)
            XCTAssertEqual(crashSwitch.value as? String, crashBefore)
            app.terminate()
        }
    }

    func testSavedUndoNoticesResolveLocalizedKeysAndKeepFolderNames() {
        for (locale, bookmark, folder) in [
            ("ar", "تمت إزالة الإشارة المرجعية", "تم حذف المجلد My folder"),
            ("ru", "Закладка удалена", "Папка My folder удалена"),
            ("kk", "Бетбелгі жойылды", "My folder қалтасы жойылды"),
            ("id", "Penanda dihapus", "Folder My folder dihapus"),
            ("en", "Bookmark removed", "Folder My folder deleted"),
            ("ky", "Кыстарма өчүрүлдү", "My folder папкасы өчүрүлдү"),
            ("uz", "Xatcho‘p olib tashlandi", "My folder jildi o‘chirildi"),
            ("tr", "Yer imi kaldırıldı", "My folder klasörü silindi"),
            ("ur", "بک مارک ہٹا دیا گیا", "فولڈر My folder حذف کر دیا گیا"),
            ("fr", "Signet supprimé", "Dossier My folder supprimé"),
            ("es-419", "Marcador eliminado", "Carpeta My folder eliminada"),
            ("pt-BR", "Marcador removido", "Pasta My folder excluída"),
            ("sw", "Alamisho limeondolewa", "Folda My folder imefutwa"),
            ("hi", "बुकमार्क हटाया गया", "फ़ोल्डर My folder मिटाया गया"),
            ("bn", "বুকমার্ক সরানো হয়েছে", "My folder ফোল্ডার মুছে ফেলা হয়েছে")
        ] {
            let app = launchPolish("saved-undo", locale: locale)
            XCTAssertTrue(app.staticTexts[bookmark].waitForExistence(timeout: 10))
            let labels = app.staticTexts.allElementsBoundByIndex.map(\.label)
            if locale == "ar" { print("A4 Undo labels: " + labels.map(\.debugDescription).joined(separator: " | ")) }
            XCTAssertTrue(labels.contains { withoutDirectionalMarks($0) == folder }, labels.debugDescription)
            capture("saved-undo-" + locale, app)
            app.terminate()
        }
    }

    func testReadingProgressLabelsUseLocalizedWordsAndNumbers() {
        for (locale, unopened, complete, unavailable, positionUnavailable, word) in [
            ("en", "Not started", "Complete", "Progress unavailable", "Position unavailable", "Hadith"),
            ("ar", "لم يبدأ بعد", "مكتمل", "تقدم القراءة غير متاح", "موضع القراءة غير متاح", "الحديث"),
            ("ru", "Не начато", "Прочитано", "Прогресс чтения недоступен", "Позиция чтения недоступна", "Хадис"),
            ("kk", "Басталмаған", "Оқылды", "Оқу барысы қолжетімсіз", "Оқу орны қолжетімсіз", "хадистің"),
            ("ky", "Баштала элек", "Окулду", "Окуу жүрүшү жеткиликсиз", "Окуу орду жеткиликсиз", "хадистин"),
            ("uz", "Boshlanmagan", "O‘qib bo‘lingan", "O‘qish jarayoni mavjud emas", "O‘qish o‘rni mavjud emas", "tadan"),
            ("tr", "Başlanmadı", "Tamamlandı", "Okuma ilerlemesi kullanılamıyor", "Okuma konumu kullanılamıyor", "hadisten"),
            ("id", "Belum dimulai", "Selesai", "Kemajuan membaca tidak tersedia", "Posisi membaca tidak tersedia", "Hadis"),
            ("ur", "ابھی شروع نہیں کیا", "مکمل", "مطالعے کی پیش رفت دستیاب نہیں", "مطالعے کا مقام دستیاب نہیں", "میں"),
            ("fr", "Pas encore commencé", "Terminé", "Progression de lecture indisponible", "Position de lecture indisponible", "Hadith"),
            ("es-419", "Sin empezar", "Completado", "Progreso de lectura no disponible", "Posición de lectura no disponible", "Hadiz"),
            ("pt-BR", "Não iniciado", "Concluído", "Progresso de leitura indisponível", "Posição de leitura indisponível", "Hadith"),
            ("sw", "Bado haijaanza", "Imekamilika", "Maendeleo ya usomaji hayapatikani", "Sehemu ya kusoma haipatikani", "Hadithi ya"),
            ("hi", "अभी शुरू नहीं किया", "पूरा हुआ", "पढ़ने की प्रगति उपलब्ध नहीं है", "पढ़ने का स्थान उपलब्ध नहीं है", "में"),
            ("bn", "শুরু করা হয়নি", "সম্পূর্ণ", "পড়ার অগ্রগতি উপলব্ধ নয়", "পড়ার অবস্থান উপলব্ধ নয়", "টির")
        ] {
            let app = launchPolish("library-progress", locale: locale)
            XCTAssertTrue(app.staticTexts[unopened].firstMatch.waitForExistence(timeout: 10))
            let count = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", word)).firstMatch
            XCTAssertTrue(count.exists)
            if locale == "ar" { XCTAssertTrue(count.label.contains("٣")); XCTAssertTrue(count.label.contains("١٠")) }
            XCTAssertTrue(app.staticTexts[complete].firstMatch.exists)
            capture("library-progress-count-" + locale, app)
            app.swipeUp()
            XCTAssertTrue(app.staticTexts[positionUnavailable].firstMatch.exists)
            XCTAssertTrue(app.staticTexts[unavailable].firstMatch.waitForExistence(timeout: 5))
            capture("library-progress-" + locale, app)
            app.terminate()
        }
    }

    func testDailyEmptyStateLocalizesItsActualTitleAndCollectionGuidance() {
        for (locale, title, guidance) in [
            ("en", "Your daily reading", "Today’s hadith is not available yet. Choose a collection below to keep reading."),
            ("ar", "قراءتك اليومية", "حديث اليوم غير متاح بعد. اختر مجموعة أدناه لمتابعة القراءة."),
            ("ru", "Ваше ежедневное чтение", "Сегодняшний хадис пока недоступен. Выберите сборник ниже, чтобы продолжить чтение."),
            ("kk", "Күнделікті оқуыңыз", "Бүгінгі хадис әзірге қолжетімсіз. Оқуды жалғастыру үшін төменнен жинақты таңдаңыз."),
            ("ky", "Күнүмдүк окууңуз", "Бүгүнкү хадис азырынча жеткиликсиз. Окууну улантуу үчүн төмөндөн жыйнак тандаңыз."),
            ("uz", "Kundalik mutolaangiz", "Bugungi hadis hali mavjud emas. O‘qishni davom ettirish uchun quyidan to‘plamni tanlang."),
            ("tr", "Günlük okumanız", "Bugünün hadisi henüz mevcut değil. Okumaya devam etmek için aşağıdan bir koleksiyon seçin."),
            ("id", "Bacaan harian Anda", "Hadis hari ini belum tersedia. Pilih koleksi di bawah untuk melanjutkan membaca."),
            ("ur", "آپ کا روزانہ مطالعہ", "آج کی حدیث ابھی دستیاب نہیں ہے۔ پڑھنا جاری رکھنے کے لیے نیچے کوئی مجموعہ منتخب کریں۔"),
            ("fr", "Votre lecture du jour", "Le hadith du jour n’est pas encore disponible. Choisissez un recueil ci-dessous pour continuer à lire."),
            ("es-419", "Tu lectura diaria", "El hadiz de hoy aún no está disponible. Elige una colección abajo para seguir leyendo."),
            ("pt-BR", "Sua leitura diária", "O hadith de hoje ainda não está disponível. Escolha uma coleção abaixo para continuar a leitura."),
            ("sw", "Usomaji wako wa kila siku", "Hadithi ya leo bado haipatikani. Chagua mkusanyiko hapa chini ili kuendelea kusoma."),
            ("hi", "आपका दैनिक पठन", "आज की हदीस अभी उपलब्ध नहीं है। पढ़ना जारी रखने के लिए नीचे कोई संग्रह चुनें।"),
            ("bn", "আপনার দৈনিক পাঠ", "আজকের হাদিস এখনও উপলব্ধ নয়। পড়া চালিয়ে যেতে নিচে একটি সংকলন বেছে নিন।")
        ] {
            let app = launchPolish("today-empty", locale: locale)
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", guidance)).firstMatch.exists)
            capture("daily-empty-" + locale, app)
            app.terminate()
        }
    }

    func testDailyCardFollowsAppAppearanceWithSeparateReaderTheme() {
        for (appTheme, readerTheme) in [("light", "dark"), ("dark", "light")] {
            let app = XCUIApplication()
            app.launchArguments = ["-NativePolishFixture"]
            app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "POLISH_SCREEN": "today-ready",
                "POLISH_THEME": appTheme, "POLISH_READER_THEME": readerTheme]
            app.launch()
            let card = element("today.dailyCard", app)
            XCTAssertTrue(card.waitForExistence(timeout: 10))
            let color = pixel(in: app, at: CGPoint(x: card.frame.minX + card.frame.width * 0.85, y: card.frame.minY + 8))
            capture("daily-app-\(appTheme)-reader-\(readerTheme)", app)
            if appTheme == "light" {
                XCTAssertGreaterThan(Int(color[0]), 180, "Daily follows the light app, independently of the dark reader")
            } else {
                XCTAssertLessThan(Int(color[0]), 100, "Daily follows the dark app, independently of the light reader")
            }
            app.terminate()
        }
    }

    func testPageHandoffKeepsIncomingTextGeometry() {
        var positions: [CGFloat] = []
        for renderer in ["neighbor", "active"] {
            let app = XCUIApplication()
            app.launchArguments = ["-NativePolishFixture"]
            app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "POLISH_SCREEN": "reader", "POLISH_THEME": "light", "PAGING_RENDER": renderer]
            app.launch()
            let text = app.staticTexts["reader.arabic"].firstMatch
            XCTAssertTrue(text.waitForExistence(timeout: 10))
            positions.append(text.frame.minY)
            capture("page-handoff-\(renderer)", app)
            app.terminate()
        }
        XCTAssertEqual(positions[0], positions[1], accuracy: 1, "Incoming text must not jump when its page becomes active")
    }
    func testReaderSourcesOpenFromHadithHeader() {
        let app = XCUIApplication()
        app.launchArguments = ["-NativePolishFixture"]
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "POLISH_SCREEN": "reader", "POLISH_THEME": "paper", "Q1_STATE": "sources"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Prepared sourced translation"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["reader.aiBadge"].exists)
        app.buttons.matching(identifier: "reader.hadithLabel").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Prepared reference"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["reader.sourceSheet.name"].exists)
        XCTAssertTrue(element("translation.sources.ai", app).exists)
        capture("combined-reader-sources", app)
    }

    func testReaderCanPageWhileTranslationIsPreparing() {
        let app = XCUIApplication()
        app.launchArguments = ["-NativePolishFixture"]
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "POLISH_SCREEN": "reader", "POLISH_THEME": "light",
            "PAGING_RENDER": "interactive", "Q1_STATE": "loading", "Q1_LANGUAGE": "ru"]
        app.launch()
        XCTAssertTrue(element("reader.translationLoading", app).waitForExistence(timeout: 10))
        app.swipeLeft()
        XCTAssertTrue(element("reader.volumeCorner", app).waitForExistence(timeout: 5))
        app.swipeRight()
        XCTAssertTrue(element("reader.volumeHeader", app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("reader.translationLoading", app).exists)
        capture("reader-preparing-interrupted-by-paging", app)
    }

    func testProductionReaderSwipesAndHintDoesNotRepeat() {
        let app = XCUIApplication()
        app.launchArguments = ["-NativePolishFixture"]
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "POLISH_SCREEN": "reader", "POLISH_THEME": "light", "PAGING_RENDER": "interactive", "POLISH_RESET_HINT": "1"]
        app.launch()
        XCTAssertTrue(element("reader.volumeHeader", app).waitForExistence(timeout: 10))
        XCTAssertTrue(element("reader.actionHint", app).waitForExistence(timeout: 5))
        app.buttons["Dismiss hint"].tap()
        app.swipeLeft()
        XCTAssertTrue(element("reader.volumeCorner", app).waitForExistence(timeout: 5))
        app.swipeRight()
        XCTAssertTrue(element("reader.volumeHeader", app).waitForExistence(timeout: 5))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)))
        XCTAssertTrue(element("reader.volumeHeader", app).exists)
        app.terminate()
        app.launchEnvironment["POLISH_RESET_HINT"] = "0"
        app.launch()
        XCTAssertTrue(element("reader.volumeHeader", app).waitForExistence(timeout: 10))
        XCTAssertFalse(element("reader.actionHint", app).exists)
        capture("reader-final", app)
    }

    func testProductionReaderRTLSwipes() {
        let app = XCUIApplication()
        app.launchArguments = ["-NativePolishFixture"]
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "POLISH_SCREEN": "reader", "POLISH_THEME": "paper", "PAGING_RENDER": "interactive", "POLISH_DIRECTION": "rtl"]
        app.launch()
        XCTAssertTrue(element("reader.volumeHeader", app).waitForExistence(timeout: 10))
        app.swipeRight()
        XCTAssertTrue(element("reader.volumeCorner", app).waitForExistence(timeout: 5))
        app.swipeLeft()
        XCTAssertTrue(element("reader.volumeHeader", app).waitForExistence(timeout: 5))
        capture("reader-rtl-final", app)
    }

    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        let app = XCUIApplication()
        if app.state == .runningForeground { capture("final-" + name, app) }
        app.terminate()
        XCUIApplication(bundleIdentifier: "com.apple.Preferences").terminate()
    }

    func testLightSettingsHasDistinctSurfaces() {
        let app = XCUIApplication()
        app.launchArguments = ["-ReaderSettingsFixture"]
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "READER_SETTINGS_CONTEXT": "global", "READER_SETTINGS_THEME": "light"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        let title = app.navigationBars["Settings"].staticTexts["Settings"]
        XCTAssertTrue(title.exists)
        XCTAssertGreaterThan(inkFraction(in: app, rect: title.frame), 0.02, "The Settings title must contain visible dark text, not only an accessibility label")
        let row = app.buttons["settings.row.appearance"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let canvas = pixel(in: app, at: CGPoint(x: 4, y: row.frame.midY))
        let surface = pixel(in: app, at: CGPoint(x: row.frame.minX + row.frame.width * 0.7, y: row.frame.midY))
        XCTAssertGreaterThan(Int(canvas[0]) - Int(surface[0]), 10, "Light settings cells must not disappear into the white canvas")
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "light-settings-surfaces"
        capture.lifetime = .keepAlways
        add(capture)
    }

    func testLoadingSurfacesAndCollectionTitlesAcrossThemes() {
        for theme in ["light", "dark", "paper"] {
            for screen in ["today-loading", "library-ready", "saved-loading", "reader-loading"] {
                let app = launchPolish(screen, theme: theme)
                let probe = screen == "library-ready" ? "library.collection.bukhari" : screen == "reader-loading" ? "reader.pageLoading" : screen == "today-loading" ? "today.dailyLoading" : "loading.skeleton"
                XCTAssertTrue(element(probe, app).waitForExistence(timeout: 10), "Missing \(screen) in \(theme)")
                capture("\(screen)-\(theme)", app)
                app.terminate()
            }
        }
    }

    func testTodayRefreshAndOnboardingLoadsDailyHadith() {
        let today = launchPolish("today-loading", theme: "light")
        XCTAssertTrue(element("today.dailyLoading", today).waitForExistence(timeout: 10))
        let scroll = today.scrollViews.firstMatch
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            .press(forDuration: 0.1, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        XCTAssertTrue(element("today.dailyCard", today).waitForExistence(timeout: 10))
        let expand = today.buttons["today.expand"]
        for _ in 0..<4 where !expand.isHittable { today.swipeUp() }
        expand.tap()
        XCTAssertTrue(today.buttons["Show less"].exists)
        capture("today-loaded-expanded", today)
        today.terminate()

        let demo = launchPolish("demo", theme: "paper")
        XCTAssertTrue(waitForOnboardingDailyResult(demo))
        capture("onboarding-daily-hadith", demo)
        demo.terminate()

        for screen in ["today-failure", "saved-failure"] {
            let failed = launchPolish(screen)
            let title = screen == "saved-failure" ? "Saved items could not load" : "Today's hadith could not load"
            XCTAssertTrue(failed.staticTexts[title].waitForExistence(timeout: 10))
            XCTAssertFalse(element(screen == "today-failure" ? "today.dailyLoading" : "loading.skeleton", failed).exists)
            capture(screen, failed)
            failed.terminate()
        }
    }

    func testAIWaitingMotionAndReducedMotionThenCompletion() {
        let original = setReducedMotion(false)
        defer { _ = setReducedMotion(original) }
        for reduced in [false, true] {
            _ = setReducedMotion(reduced)
            let app = launchPolish("reader", theme: "light", reduced: reduced)
            let waiting = element("reader.translationLoading", app)
            XCTAssertTrue(waiting.waitForExistence(timeout: 10))
            let rect = waiting.frame
            let before = cropped(app, rect)
            Thread.sleep(forTimeInterval: 0.31)
            let after = cropped(app, rect)
            if reduced { XCTAssertEqual(before, after, "Reduce Motion must leave the waiting indicator static") }
            else { XCTAssertNotEqual(before, after, "An active AI request must show motion") }
            capture(reduced ? "ai-waiting-reduced" : "ai-waiting", app)
            waiting.doubleTap()
            XCTAssertTrue(app.staticTexts["Prepared translation preview."].waitForExistence(timeout: 10))
            XCTAssertFalse(waiting.exists)
            capture(reduced ? "ai-result-reduced" : "ai-result", app)
            app.terminate()
        }
    }

    func testLargeRTLAndOnboardingStepNavigation() {
        let app = launchPolish("library-ready", theme: "light", locale: "ar", large: true)
        XCTAssertTrue(app.buttons["library.collection.bukhari"].waitForExistence(timeout: 10))
        capture("library-large-rtl", app)
        app.buttons["library.layoutToggle"].tap()
        XCTAssertTrue(app.buttons["library.collection.bukhari"].exists)
        capture("library-list-large-rtl", app)
        app.terminate()

        let original = setReducedMotion(true)
        defer { _ = setReducedMotion(original) }
        let demo = launchPolish("demo", theme: "dark", reduced: true, large: true)
        XCTAssertTrue(waitForOnboardingDailyResult(demo))
        capture("onboarding-large-reduced", demo)
    }

    func testOnboardingStepNavigationRemainsImmediatelyUsable() {
        let app = launchPolish("onboarding", theme: "light")
        XCTAssertTrue(app.buttons["onboarding.getStarted"].waitForExistence(timeout: 10))
        app.buttons["onboarding.getStarted"].tap()
        XCTAssertTrue(app.buttons["onboarding.continue"].waitForExistence(timeout: 5))
        capture("onboarding-language-step", app)
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(waitForOnboardingDailyResult(app))
        capture("onboarding-demo-step", app)
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.buttons["onboarding.guest"].waitForExistence(timeout: 5))
        app.buttons["onboarding.back"].tap()
        XCTAssertTrue(waitForOnboardingDailyResult(app))
        app.buttons["onboarding.continue"].tap()
        app.buttons["onboarding.guest"].tap()
        XCTAssertTrue(element("polish.onboardingDone", app).waitForExistence(timeout: 5))
    }

    @discardableResult
    private func setReducedMotion(_ enabled: Bool) -> Bool {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let toggle = settings.switches["Reduce Motion"]
        if !toggle.waitForExistence(timeout: 2) {
            for _ in 0..<5 {
                if settings.cells.containing(.staticText, identifier: "Accessibility").firstMatch.exists { break }
                let back = settings.navigationBars.buttons.element(boundBy: 0)
                if back.exists && back.isHittable { back.tap() } else { break }
            }
            let accessibility = settings.cells.containing(.staticText, identifier: "Accessibility").firstMatch
            for _ in 0..<8 where !accessibility.isHittable { settings.swipeUp() }
            XCTAssertTrue(accessibility.exists)
            accessibility.tap()
            settings.staticTexts["Motion"].tap()
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let original = toggle.value as? String == "1"
        if original != enabled { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", enabled ? "1" : "0"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed)
        return original
    }

    private func launchPolish(_ screen: String, theme: String = "light", reduced: Bool = false, locale: String = "en", large: Bool = false, translationLocale: String? = nil, readingDirection: String? = nil, arabicOnly: Bool = false, production: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-NativePolishFixture"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "POLISH_SCREEN": screen, "POLISH_THEME": theme,
            "POLISH_LOCALE": locale, "POLISH_REDUCE_MOTION": reduced ? "1" : "0", "Q1_STATE": "loading", "Q1_LANGUAGE": "ru",
            "POLISH_INTERACTIVE": "1", "R6A_LOADING_FIXTURE": screen == "reader-loading" ? "true" : "false"]
        if let translationLocale { app.launchEnvironment["POLISH_TRANSLATION_LOCALE"] = translationLocale }
        if let readingDirection { app.launchEnvironment["R6A_PAGE_DIRECTION"] = readingDirection }
        if arabicOnly { app.launchEnvironment["R6A_TRANSLATION_VISIBLE"] = "false" }
        if production { app.launchEnvironment["PAGING_RENDER"] = "interactive" }
        app.launch()
        return app
    }

    private func withoutDirectionalMarks(_ value: String) -> String {
        value.replacingOccurrences(of: "[\u{200e}\u{200f}\u{061c}\u{2066}-\u{2069}]", with: "", options: .regularExpression)
    }

    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @discardableResult
    private func waitForOnboardingDailyResult(_ app: XCUIApplication) -> Bool {
        let text = element("onboarding.dailyText", app)
        let retry = app.buttons["onboarding.dailyRetry"]
        let result = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in text.exists || retry.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [result], timeout: 20), .completed)
        return text.exists
    }

    private func cropped(_ app: XCUIApplication, _ rect: CGRect) -> Data? {
        let image = app.screenshot().image.cgImage!
        let scale = CGFloat(image.width) / app.frame.width
        let box = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        guard let crop = image.cropping(to: box) else { return nil }
        return UIImage(cgImage: crop).pngData()
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("polish-\(name).png")
        try? app.screenshot().pngRepresentation.write(to: file)
    }

    private func inkFraction(in app: XCUIApplication, rect: CGRect) -> Double {
        guard rect.width > 0, rect.height > 0 else { return 0 }
        let image = app.screenshot().image.cgImage!
        let scale = CGFloat(image.width) / app.frame.width
        guard let crop = image.cropping(to: CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)) else { return 0 }
        var rgba = [UInt8](repeating: 255, count: 64 * 24 * 4)
        let context = CGContext(data: &rgba, width: 64, height: 24, bitsPerComponent: 8, bytesPerRow: 64 * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(crop, in: CGRect(x: 0, y: 0, width: 64, height: 24))
        return Double(stride(from: 0, to: rgba.count, by: 4).filter { Int(rgba[$0]) + Int(rgba[$0 + 1]) + Int(rgba[$0 + 2]) < 450 }.count) / (64 * 24)
    }

    private func pixel(in app: XCUIApplication, at point: CGPoint, from screenshot: CGImage? = nil) -> [UInt8] {
        let image = screenshot ?? app.screenshot().image.cgImage!
        let scale = CGFloat(image.width) / app.frame.width
        let sample = image.cropping(to: CGRect(x: point.x * scale, y: point.y * scale, width: 1, height: 1))!
        var rgba = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &rgba, width: 1, height: 1, bitsPerComponent: 8,
                                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return rgba
    }
}
