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

    func testPanHandlerLocksAxisTracksFingerAndCancelsBack() {
        var turns: [ReaderPageTurn] = []
        var releases: [ReaderPageTurn?] = []
        var progresses: [CGFloat] = []
        let handler = ReaderPagingPanHandler(
            pageDirection: .rtl,
            isEnabled: { true },
            onTurn: { turns.append($0) },
            onProgress: { progresses.append($0) },
            onRelease: { releases.append($0) }
        )

        // Horizontal gesture: began arbitrates, changed locks and tracks
        // the finger, ended past the distance threshold turns.
        handler.handle(state: .began, translation: .zero, velocity: .zero)
        XCTAssertEqual(handler.axisLock, .undecided)
        handler.handle(state: .changed, translation: CGPoint(x: -40, y: 5), velocity: .zero)
        XCTAssertEqual(handler.axisLock, .horizontal)
        handler.handle(
            state: .ended,
            translation: CGPoint(x: -70, y: 8),
            velocity: .zero
        )
        // Short high-velocity horizontal flick turns without distance.
        handler.handle(state: .began, translation: .zero, velocity: .zero)
        handler.handle(state: .changed, translation: CGPoint(x: -18, y: 2), velocity: .zero)
        handler.handle(
            state: .ended,
            translation: CGPoint(x: -18, y: 2),
            velocity: CGPoint(x: -900, y: 30)
        )
        // Mostly-vertical gesture: the lock pins progress at rest and the
        // release cancels back — vertical scrolling never turns the page.
        handler.handle(state: .began, translation: .zero, velocity: .zero)
        handler.handle(state: .changed, translation: CGPoint(x: 8, y: -60), velocity: .zero)
        XCTAssertEqual(handler.axisLock, .vertical)
        handler.handle(
            state: .ended,
            translation: CGPoint(x: 8, y: -300),
            velocity: CGPoint(x: 20, y: -1_000)
        )
        // Cancelled horizontal gesture: no turn, cancel-back.
        handler.handle(state: .began, translation: .zero, velocity: .zero)
        handler.handle(state: .changed, translation: CGPoint(x: 200, y: 0), velocity: .zero)
        handler.handle(
            state: .cancelled,
            translation: CGPoint(x: 200, y: 0),
            velocity: CGPoint(x: 1_000, y: 0)
        )
        // A lone settled .ended still arbitrates its own axis (the old
        // discrete-swipe edge): strong horizontal travel turns.
        handler.handle(
            state: .ended,
            translation: CGPoint(x: -200, y: 0),
            velocity: .zero
        )

        XCTAssertEqual(turns, [.previous, .previous, .previous])
        XCTAssertEqual(releases.count, 5)
        XCTAssertEqual(releases[0], .previous)
        XCTAssertEqual(releases[1], .previous)
        XCTAssertNil(releases[2])
        XCTAssertNil(releases[3])
        XCTAssertEqual(releases[4], .previous)
        XCTAssertTrue(progresses.contains(-40), "horizontal drags track the finger")
        XCTAssertTrue(progresses.contains(200), "horizontal drags track the finger")
        XCTAssertFalse(progresses.contains(8), "vertical drags never move the page")
    }

    func testReleaseOwnsOffsetAfterEndedSoCommitAnimationSurvives() {
        // Round 5 swipe-jerk fix: once onRelease is set, the handler must
        // not reset progress after delegating — the release owner animates
        // onto the revealed neighbor (commit) or springs back (cancel).
        // A trailing reset would snap the strip to rest first, flashing the
        // swiping-from page before the settle swap.
        var releases: [ReaderPageTurn?] = []
        var progresses: [CGFloat] = []
        let handler = ReaderPagingPanHandler(
            pageDirection: .ltr,
            isEnabled: { true },
            onTurn: { _ in },
            onProgress: { progresses.append($0) },
            onRelease: { releases.append($0) }
        )
        handler.handle(state: .began, translation: .zero, velocity: .zero)
        handler.handle(state: .changed, translation: CGPoint(x: -70, y: 5), velocity: .zero)
        handler.handle(state: .ended, translation: CGPoint(x: -70, y: 5), velocity: .zero)
        XCTAssertEqual(releases, [.next])
        XCTAssertEqual(progresses, [0, -70])

        // Cancelled gestures behave the same: release owns the way back.
        var cancelledProgresses: [CGFloat] = []
        let cancelling = ReaderPagingPanHandler(
            pageDirection: .ltr,
            isEnabled: { true },
            onTurn: { _ in },
            onProgress: { cancelledProgresses.append($0) },
            onRelease: { _ in }
        )
        cancelling.handle(state: .began, translation: .zero, velocity: .zero)
        cancelling.handle(state: .changed, translation: CGPoint(x: 200, y: 0), velocity: .zero)
        cancelling.handle(state: .cancelled, translation: CGPoint(x: 200, y: 0), velocity: .zero)
        XCTAssertEqual(cancelledProgresses, [0, 200])
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
