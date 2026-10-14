import XCTest
import SwiftUI
@testable import Hadithly

final class SupportedLanguagesTests: XCTestCase {
    func testEnglishIsDefaultAndPresent() {
        XCTAssertTrue(SupportedLanguages.all.contains { $0.code == "en" })
    }

    func testLanguageCodesAreUnique() {
        let codes = SupportedLanguages.all.map(\.code)
        XCTAssertEqual(codes.count, Set(codes).count)
    }

    func testWaveOneContainsTheContractLocalesInOrder() {
        XCTAssertEqual(
            SupportedLanguages.all.map(\.code),
            ["en", "ar", "ru", "kk", "ky", "uz", "tr", "id", "ur", "fr", "es-419", "pt-BR", "sw", "hi", "bn"],
        )
    }

    func testColorHexParsing() {
        XCTAssertEqual(Color(hex: "0D0D0D"), Color(hex: "#0D0D0D"))
    }
}
