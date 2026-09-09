import UIKit
import XCTest
@testable import Hadithly

@MainActor
final class ReaderPagingTests: XCTestCase {
    func testBehavioralDirectionMatrix() {
        let cases: [(String, ReaderPreferences, HorizontalDirection, ReaderPageTurn)] = [
            ("Arabic-only auto", preferences(locale: "en", arabic: true, translation: false), .rtl, .previous),
            ("translation-only English auto", preferences(locale: "en", arabic: false, translation: true), .ltr, .next),
            ("translation-only Urdu auto", preferences(locale: "ur", arabic: false, translation: true), .rtl, .previous),
            ("mixed Arabic and English auto", preferences(locale: "en", arabic: true, translation: true), .ltr, .next),
            ("mixed Arabic and Urdu auto", preferences(locale: "ur", arabic: true, translation: true), .rtl, .previous),
            ("forced LTR", preferences(locale: "ur", arabic: true, translation: true, direction: .ltr), .ltr, .next),
            ("forced RTL", preferences(locale: "en", arabic: true, translation: true, direction: .rtl), .rtl, .previous),
        ]

        for (name, preferences, expectedDirection, expectedLeftTurn) in cases {
            let policy = ReaderPagingPolicy(preferences: preferences)
            XCTAssertEqual(policy.pageDirection, expectedDirection, name)
            XCTAssertEqual(policy.turn(for: .left), expectedLeftTurn, name)
            XCTAssertEqual(
                policy.turn(for: .right),
                expectedLeftTurn == .next ? .previous : .next,
                name
            )
        }
    }

    func testFirstAndLastPageBoundariesAndEndControlOrder() {
        let ltr = ReaderPagingPolicy(pageDirection: .ltr)
        XCTAssertNil(ltr.destination(from: 0, pageCount: 3, turn: .previous))
        XCTAssertEqual(ltr.destination(from: 0, pageCount: 3, turn: .next), 1)
        XCTAssertEqual(ltr.destination(from: 2, pageCount: 3, turn: .previous), 1)
        XCTAssertNil(ltr.destination(from: 2, pageCount: 3, turn: .next))
        XCTAssertEqual(ltr.endControlOrder, [.previous, .next])

        let rtl = ReaderPagingPolicy(pageDirection: .rtl)
        XCTAssertEqual(rtl.endControlOrder, [.next, .previous])
    }

    func testPanHandlerUsesDistanceVelocityAndCancellationWithoutTakingVerticalScroll() {
        var turns: [ReaderPageTurn] = []
        let handler = ReaderPagingPanHandler(
            pageDirection: .rtl,
            isEnabled: { true },
            onTurn: { turns.append($0) }
        )

        handler.handle(
            state: .ended,
            translation: CGPoint(x: -70, y: 8),
            velocity: .zero
        )
        handler.handle(
            state: .ended,
            translation: CGPoint(x: -18, y: 2),
            velocity: CGPoint(x: -900, y: 30)
        )
        handler.handle(
            state: .ended,
            translation: CGPoint(x: 8, y: -300),
            velocity: CGPoint(x: 20, y: -1_000)
        )
        handler.handle(
            state: .cancelled,
            translation: CGPoint(x: 200, y: 0),
            velocity: CGPoint(x: 1_000, y: 0)
        )

        XCTAssertEqual(turns, [.previous, .previous])
    }

    func testPanRecognizerObservesScrollViewsSimultaneouslyAndNeverCancelsTouches() throws {
        let handler = ReaderPagingPanHandler(
            pageDirection: .ltr,
            isEnabled: { true },
            onTurn: { _ in }
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        handler.installIfNeeded(on: window)

        let recognizer = try XCTUnwrap(handler.recognizer)
        XCTAssertFalse(recognizer.cancelsTouchesInView)
        XCTAssertTrue(
            handler.gestureRecognizer(
                recognizer,
                shouldRecognizeSimultaneouslyWith: UIPanGestureRecognizer()
            )
        )
        handler.uninstall()
        XCTAssertNil(handler.recognizer)
        XCTAssertFalse(window.gestureRecognizers?.contains(recognizer) == true)
    }

    func testOneLineAndMultiScreenRestorationAnchors() {
        XCTAssertEqual(
            ReaderScrollRestoration.anchorY(
                normalizedOffset: 0.5,
                itemHeight: 200,
                viewportHeight: 800
            ),
            0
        )

        let anchor = ReaderScrollRestoration.anchorY(
            normalizedOffset: 0.5,
            itemHeight: 2_400,
            viewportHeight: 800
        )
        XCTAssertEqual(anchor, 0.75, accuracy: 0.0001)
        XCTAssertEqual(anchor * (800 - 2_400), -1_200, accuracy: 0.1)

        let nearEndAnchor = ReaderScrollRestoration.anchorY(
            normalizedOffset: 0.9,
            itemHeight: 2_400,
            viewportHeight: 800
        )
        XCTAssertEqual(nearEndAnchor, 1.35, accuracy: 0.0001)
        XCTAssertEqual(nearEndAnchor * (800 - 2_400), -2_160, accuracy: 0.1)
    }

    private func preferences(
        locale: String,
        arabic: Bool,
        translation: Bool,
        direction: ReadingDirection = .auto
    ) -> ReaderPreferences {
        var value = ReaderPreferences()
        value.translationLocale = locale
        value.arabicVisible = arabic
        value.translationVisible = translation
        value.readingDirection = direction
        return value
    }
}
