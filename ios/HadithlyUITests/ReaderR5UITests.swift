import XCTest

/// R5 gate: contents navigation (chapters, jump field) and the per-hadith
/// native menus. Fixture tests prove the new sheet UI offline; the live test
/// proves it against development Convex with the pre-R5 outline shape
/// (volumes exactly as before, jump navigating through the canonical path).
final class ReaderR5UITests: XCTestCase {
    private let timeout: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Fixture: chapters render from source-provided data

    func testContentsGuidanceAndValidationLocalizeAtRuntime() {
        for (locale, hint, error, title, volumes) in [
            ("ar", "انتقل إلى رقم حديث، مثل 57.", "أدخل رقم حديث مثل 57 أو 4.5.", "المحتويات", "المجلدات"),
            ("ru", "Перейти к номеру хадиса, например 57.", "Введите номер хадиса, например 57 или 4.5.", "Содержание", "ТОМА"),
            ("kk", "Хадис нөміріне өту, мысалы 57.", "57 немесе 4.5 сияқты хадис нөмірін енгізіңіз.", "Мазмұны", "ТОМДАР"),
            ("id", "Lompat ke nomor hadis, misalnya 57.", "Masukkan nomor hadis seperti 57 atau 4.5.", "Daftar isi", "VOLUME"),
            ("en", "Jump to a hadith number, e.g. 57.", "Enter a hadith number like 57 or 4.5.", "Contents", "Volumes"),
            ("ky", "Хадис номерине өтүңүз, мисалы 57.", "57 же 4.5 сыяктуу хадис номерин киргизиңиз.", "Мазмун", "ТОМДОР"),
            ("uz", "Hadis raqamiga o‘ting, masalan 57.", "57 yoki 4.5 kabi hadis raqamini kiriting.", "Mundarija", "JILDLAR"),
            ("tr", "Hadis numarasına git, örneğin 57.", "57 veya 4.5 gibi bir hadis numarası girin.", "İçindekiler", "CİLTLER"),
            ("ur", "حدیث نمبر پر جائیں، مثلاً 57۔", "57 یا 4.5 جیسا حدیث نمبر درج کریں۔", "فہرستِ مضامین", "جلدیں"),
            ("fr", "Aller au numéro de hadith, par exemple 57.", "Saisissez un numéro de hadith comme 57 ou 4.5.", "Sommaire", "TOMES"),
            ("es-419", "Ir al número de hadiz, por ejemplo, 57.", "Ingresa un número de hadiz como 57 o 4.5.", "Contenido", "VOLÚMENES"),
            ("pt-BR", "Ir para o número do hadith, por exemplo, 57.", "Digite um número de hadith como 57 ou 4.5.", "Conteúdo", "TOMOS"),
            ("sw", "Nenda kwenye nambari ya hadithi, kwa mfano 57.", "Weka nambari ya hadithi kama 57 au 4.5.", "Yaliyomo", "JUZUU"),
            ("hi", "हदीस संख्या पर जाएँ, जैसे 57।", "57 या 4.5 जैसा हदीस नंबर दर्ज करें।", "विषय-सूची", "खंड"),
            ("bn", "হাদিস নম্বরে যান, যেমন ৫৭।", "57 বা 4.5-এর মতো হাদিস নম্বর লিখুন।", "সূচিপত্র", "খণ্ড")
        ] {
            let app = XCUIApplication()
            app.launchArguments = ["-R5ContentsFixture"]
            app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "R5_LOCALE": locale]
            app.launch()
            XCTAssertTrue(app.staticTexts[hint].waitForExistence(timeout: timeout))
            XCTAssertEqual(element("reader.contents.title", in: app).label, title)
            XCTAssertTrue(app.staticTexts[volumes].exists)
            let jump = field("reader.contents.jump", in: app)
            jump.tap()
            jump.typeText("abc")
            element("reader.contents.jumpGo", in: app).tap()
            XCTAssertTrue(app.staticTexts[error].waitForExistence(timeout: timeout))
            XCTAssertTrue(jump.exists)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "contents-validation-" + locale
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }

    func testContentsShowsChaptersAndJumpField() {
        let app = launchContentsFixture()
        XCTAssertTrue(field("reader.contents.jump", in: app).waitForExistence(timeout: timeout))
        // Volume 1 starts expanded (it holds the selected volume): its
        // source-provided chapters render with counts, and the arabic
        // subtitle appears only where present and different.
        XCTAssertTrue(element("reader.contents.chapter.1.1", in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(element("reader.contents.chapter.1.6", in: app).exists)
        XCTAssertTrue(app.staticTexts["كتاب بدء الوحي"].exists)
        XCTAssertTrue(app.staticTexts["1. Revelation"].exists)
        XCTAssertFalse(app.buttons["Open from the start"].exists)
        // Volume 2 has no chapters entry content: it renders as a plain
        // volume row exactly like the pre-R5 sheet.
        XCTAssertTrue(element("reader.volume.2", in: app).waitForExistence(timeout: timeout))
    }

    func testContentsJumpRejectsMalformedInputInline() {
        let app = launchContentsFixture()
        let jump = field("reader.contents.jump", in: app)
        XCTAssertTrue(jump.waitForExistence(timeout: timeout))
        jump.tap()
        jump.typeText("abc")
        element("reader.contents.jumpGo", in: app).tap()
        XCTAssertTrue(element("reader.contents.jumpError", in: app).waitForExistence(timeout: timeout))
        // The sheet stays open on malformed input.
        XCTAssertTrue(field("reader.contents.jump", in: app).exists)
        XCTAssertFalse(element("r5.dismissed", in: app).exists)
    }

    func testContentsJumpAcceptsWellFormedInput() {
        let app = launchContentsFixture()
        let jump = field("reader.contents.jump", in: app)
        XCTAssertTrue(jump.waitForExistence(timeout: timeout))
        jump.tap()
        jump.typeText("57")
        element("reader.contents.jumpGo", in: app).tap()
        XCTAssertTrue(element("r5.dismissed", in: app).waitForExistence(timeout: timeout))
    }

    func testContentsChapterTapDismisses() {
        let app = launchContentsFixture()
        let chapter = element("reader.contents.chapter.1.1", in: app)
        XCTAssertTrue(chapter.waitForExistence(timeout: timeout))
        chapter.tap()
        XCTAssertTrue(element("r5.dismissed", in: app).waitForExistence(timeout: timeout))
    }

    func testContentsVolumeNameOpensWithoutExtraStartRow() {
        let app = launchContentsFixture()
        let volume = app.buttons.matching(identifier: "reader.volume.1").firstMatch
        XCTAssertTrue(volume.waitForExistence(timeout: timeout))
        volume.tap()
        XCTAssertTrue(element("r5.dismissed", in: app).waitForExistence(timeout: timeout))
    }

    func testContentsKeepsSourceNumbersAndDoesNotRepeatLocalizedGenericTitle() {
        let app = XCUIApplication()
        app.launchArguments = ["-R5ContentsFixture"]
        app.launchEnvironment = ["HADITHLY_UI_TESTING": "1", "R5_SPARSE_VOLUMES": "1", "R5_ARABIC_ONLY": "1"]
        app.launch()
        let source = app.buttons.matching(identifier: "reader.volume.3").firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: timeout))
        XCTAssertTrue(source.label.contains("\(3.formatted(.number.locale(Locale(identifier: "ar")))). Prayer"))
        let generic = app.buttons.matching(identifier: "reader.volume.7").firstMatch
        XCTAssertTrue(generic.exists)
        XCTAssertFalse(generic.label.contains(". "), "The localized generic title already includes its source number")
    }

    // MARK: - Live: real reader against development Convex

    /// Opens Bukhari live, jumps to Hadith 57 through the contents field,
    /// and proves the quiet page (no ellipsis), the grade dot plus source
    /// label, the long-press menu with its gating, and tap-to-toggle
    /// chrome with the context menu present.
    func testLiveContentsJumpAndHadithMenus() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Library"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Library"].tap()
        let collection = app.buttons["library.collection.bukhari"]
        XCTAssertTrue(collection.waitForExistence(timeout: 20))
        collection.tap()
        XCTAssertTrue(element("reader.page", in: app).waitForExistence(timeout: 30))

        revealChrome(app)
        app.buttons["reader.menu"].tap()
        let contentsCard = app.buttons["reader.menu.contents"]
        XCTAssertTrue(contentsCard.waitForExistence(timeout: timeout), "reader menu never opened")
        contentsCard.tap()
        let jump = field("reader.contents.jump", in: app)
        XCTAssertTrue(jump.waitForExistence(timeout: timeout), "Contents sheet never opened")
        // Pre-R5 cached outline: volumes render exactly as before.
        XCTAssertTrue(element("reader.volume.1", in: app).waitForExistence(timeout: timeout))
        jump.tap()
        jump.typeText("57")
        element("reader.contents.jumpGo", in: app).tap()

        // The jump lands through the same path as canonical links: the
        // target hadith's top header (`[Bukhari – 57]`, VoiceOver label
        // "Bukhari – 57, Sahih") is on screen.
        let headers = app.buttons.matching(identifier: "reader.hadithLabel")
        let target = headers.matching(NSPredicate(format: "label CONTAINS '57'")).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 30), "Jump to Hadith 57 never landed")

        // Slice A: the ellipsis is gone with no visual replacement. Every
        // block carries one top header with its grade dot and label; the
        // bottom compact label and the dim bare-number marker are gone.
        XCTAssertFalse(app.buttons["reader.moreActions"].exists, "ellipsis must be deleted")
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "reader.hadithMarker").firstMatch.exists,
            "bare-number marker must be deleted"
        )
        XCTAssertTrue(
            app.buttons["reader.hadithLabel"].firstMatch.waitForExistence(timeout: timeout),
            "top hadith header never rendered"
        )

        // Long-press is the only sighted path to actions: the full menu
        // with Report gated out in English (no loaded non-English
        // translation exists here).
        let arabic = app.staticTexts["reader.arabic"].firstMatch
        scrollUntilHittable(arabic, in: app)
        arabic.press(forDuration: 1.0)
        for identifier in [
            "reader.bookmark", "reader.favorite", "reader.note",
            "reader.copy", "reader.share", "reader.suggestTranslation",
        ] {
            XCTAssertTrue(
                app.buttons[identifier].firstMatch.waitForExistence(timeout: timeout),
                "long-press menu missing \(identifier)"
            )
        }
        XCTAssertFalse(
            app.buttons["reader.reportTranslation"].firstMatch.exists,
            "Report must stay gated without a loaded non-English translation"
        )
        app.buttons["reader.copy"].firstMatch.tap()

        // The menu opens identically from any block; Share travels with it.
        scrollUntilHittable(arabic, in: app)
        arabic.press(forDuration: 1.0)
        XCTAssertTrue(
            app.buttons["reader.bookmark"].firstMatch.waitForExistence(timeout: timeout),
            "long-press menu never appeared"
        )
        XCTAssertTrue(app.buttons["reader.share"].firstMatch.exists, "long-press menu missing Share")
        app.tap()

        // Tap-to-toggle chrome and paging still work with menus present.
        revealChrome(app)
        XCTAssertTrue(app.buttons["reader.close"].isHittable, "chrome never revealed on tap")
    }

    // MARK: - Helpers

    private func launchContentsFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-R5ContentsFixture"]
        app.launchEnvironment["HADITHLY_UI_TESTING"] = "1"
        app.launch()
        return app
    }

    private func revealChrome(_ app: XCUIApplication) {
        if !app.buttons["reader.close"].isHittable {
            element("reader.page", in: app).tap()
        }
    }

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 where !element.isHittable {
            app.swipeUp()
        }
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func field(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.textFields.matching(identifier: identifier).firstMatch
    }
}
