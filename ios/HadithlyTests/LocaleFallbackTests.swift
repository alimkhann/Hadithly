import XCTest
@testable import Hadithly

final class LocaleFallbackTests: XCTestCase {
    func testCanonicalizesBCP47CasingAndSeparators() {
        XCTAssertEqual(LocaleFallback.canonicalizeLocaleTag("en"), "en")
        XCTAssertEqual(LocaleFallback.canonicalizeLocaleTag("EN"), "en")
        XCTAssertEqual(LocaleFallback.canonicalizeLocaleTag("en_US"), "en-US")
        XCTAssertEqual(LocaleFallback.canonicalizeLocaleTag("pt-br"), "pt-BR")
        XCTAssertEqual(LocaleFallback.canonicalizeLocaleTag("ES-419"), "es-419")
        XCTAssertEqual(LocaleFallback.canonicalizeLocaleTag("zh-HANS"), "zh-Hans")
    }

    func testCanonicalizeRejectsMalformedTags() {
        XCTAssertNil(LocaleFallback.canonicalizeLocaleTag(""))
        XCTAssertNil(LocaleFallback.canonicalizeLocaleTag("not a locale"))
        XCTAssertNil(LocaleFallback.canonicalizeLocaleTag("1n"))
        XCTAssertNil(LocaleFallback.canonicalizeLocaleTag("e"))
        XCTAssertNil(LocaleFallback.canonicalizeLocaleTag(String(repeating: "a-b-", count: 10)))
    }

    func testFallbackChainEndsAtEnglish() {
        XCTAssertEqual(LocaleFallback.fallbackChain(for: "ur-PK"), ["ur-PK", "ur", "en"])
        XCTAssertEqual(LocaleFallback.fallbackChain(for: "en"), ["en"])
        XCTAssertEqual(LocaleFallback.fallbackChain(for: "es-419"), ["es-419", "es", "en"])
        XCTAssertEqual(LocaleFallback.fallbackChain(for: "!!!"), ["en"])
    }

    func testResolveWalksTheChain() {
        let supported: Set<String> = ["en", "es", "es-419", "ar"]
        XCTAssertEqual(LocaleFallback.resolve("es-MX", supported: supported), "es")
        XCTAssertEqual(LocaleFallback.resolve("pt-BR", supported: supported), "en")
        XCTAssertEqual(LocaleFallback.resolve("ar", supported: supported), "ar")
        XCTAssertEqual(LocaleFallback.resolve("ar-EG", supported: supported), "ar")
    }

    func testRTLMetadataCoversArabicUrduAndPersian() {
        for tag in ["ar", "ar-EG", "ur", "ur-PK", "fa", "he", "ps", "ug"] {
            XCTAssertTrue(LocaleFallback.isRTL(tag), "\(tag) should resolve RTL")
        }
        for tag in ["en", "tr", "ru", "kk", "id", "fr", "hi", "bn"] {
            XCTAssertFalse(LocaleFallback.isRTL(tag), "\(tag) should resolve LTR")
        }
    }

    func testPseudolocalesResolveWithoutCrashing() {
        XCTAssertEqual(LocaleFallback.canonicalizeLocaleTag("en-XA"), "en-XA")
        XCTAssertEqual(LocaleFallback.canonicalizeLocaleTag("ar-XB"), "ar-XB")
        XCTAssertFalse(LocaleFallback.isRTL("en-XA"), "accented pseudolocale stays LTR")
        XCTAssertTrue(LocaleFallback.isRTL("ar-XB"), "RTL pseudolocale mirrors")
        XCTAssertEqual(LocaleFallback.resolve("en-XA", supported: ["en"]), "en")
        XCTAssertEqual(LocaleFallback.fallbackChain(for: "zz-QU"), ["zz-QU", "zz", "en"])
    }
}
