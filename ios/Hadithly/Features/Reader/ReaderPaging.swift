import SwiftUI
import UIKit

enum ReaderPageTurn: Equatable, Hashable {
    case previous
    case next
}

enum ReaderSwipeDirection {
    case left
    case right
}

struct ReaderPagingPolicy {
    let pageDirection: HorizontalDirection

    init(preferences: ReaderPreferences) {
        pageDirection = ReaderPreferencesValidator
            .directionMetadata(for: preferences)
            .pageDirection
    }

    init(pageDirection: HorizontalDirection) {
        self.pageDirection = pageDirection
    }

    func turn(for swipe: ReaderSwipeDirection) -> ReaderPageTurn {
        switch (pageDirection, swipe) {
        case (.ltr, .left), (.rtl, .right):
            .next
        case (.ltr, .right), (.rtl, .left):
            .previous
        }
    }

    func destination(from index: Int, pageCount: Int, turn: ReaderPageTurn) -> Int? {
        guard pageCount > 0, index >= 0, index < pageCount else { return nil }
        let candidate = turn == .next ? index + 1 : index - 1
        return candidate >= 0 && candidate < pageCount ? candidate : nil
    }

    var endControlOrder: [ReaderPageTurn] {
        pageDirection == .ltr ? [.previous, .next] : [.next, .previous]
    }
}

enum ReaderScrollRestoration {
    static func anchorY(
        normalizedOffset: Double,
        itemHeight: CGFloat,
        viewportHeight: CGFloat
    ) -> CGFloat {
        guard itemHeight > viewportHeight, viewportHeight > 0 else { return 0 }
        let offset = CGFloat(min(1, max(0, normalizedOffset))) * itemHeight
        return max(0, offset / (itemHeight - viewportHeight))
    }
}

@MainActor
final class ReaderPagingPanHandler: NSObject, UIGestureRecognizerDelegate {
    var pageDirection: HorizontalDirection
    var isEnabled: () -> Bool
    var onTurn: (ReaderPageTurn) -> Void
    private(set) weak var recognizer: UIPanGestureRecognizer?

    init(
        pageDirection: HorizontalDirection,
        isEnabled: @escaping () -> Bool,
        onTurn: @escaping (ReaderPageTurn) -> Void
    ) {
        self.pageDirection = pageDirection
        self.isEnabled = isEnabled
        self.onTurn = onTurn
    }

    func installIfNeeded(on window: UIView) {
        guard recognizer == nil else { return }
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        recognizer.delegate = self
        recognizer.cancelsTouchesInView = false
        recognizer.maximumNumberOfTouches = 1
        window.addGestureRecognizer(recognizer)
        self.recognizer = recognizer
    }

    func uninstall() {
        guard let recognizer else { return }
        recognizer.view?.removeGestureRecognizer(recognizer)
        self.recognizer = nil
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        handle(
            state: recognizer.state,
            translation: recognizer.translation(in: recognizer.view),
            velocity: recognizer.velocity(in: recognizer.view)
        )
    }

    func handle(
        state: UIGestureRecognizer.State,
        translation: CGPoint,
        velocity: CGPoint
    ) {
        guard state == .ended, isEnabled() else { return }

        let distanceIsHorizontal = abs(translation.x) > abs(translation.y) * 1.4
        let velocityIsHorizontal = abs(velocity.x) > abs(velocity.y) * 1.4
        let qualifiesByDistance = distanceIsHorizontal && abs(translation.x) >= 55
        let qualifiesByVelocity = velocityIsHorizontal && abs(velocity.x) >= 700
        guard qualifiesByDistance || qualifiesByVelocity else { return }

        let horizontalMotion = qualifiesByDistance ? translation.x : velocity.x
        let swipe: ReaderSwipeDirection = horizontalMotion < 0 ? .left : .right
        onTurn(ReaderPagingPolicy(pageDirection: pageDirection).turn(for: swipe))
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
