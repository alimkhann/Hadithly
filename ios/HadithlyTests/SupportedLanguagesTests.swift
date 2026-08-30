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

    func testColorHexParsing() {
        XCTAssertEqual(Color(hex: "0D0D0D"), Color(hex: "#0D0D0D"))
    }
}
