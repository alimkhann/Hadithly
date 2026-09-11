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

// MARK: - Restrained reader haptics (R6 fix round)

/// Every haptic trigger point in the reader. Restrained and native: light
/// impacts for chrome/menu gestures, medium only when something is added,
/// a soft tick when a page settles, and an error when the user tries to
/// hide both text layers.
enum ReaderHapticEvent: String, Equatable, CaseIterable {
    case menuToggle
    case menuItemTap
    case contextMenuOpen
    case bookmarkAdd
    case bookmarkRemove
    case favoriteAdd
    case favoriteRemove
    case pageSettle
    case layersRejected
}

enum ReaderHapticStyle: Equatable {
    case light
    case medium
    case soft
    case error
}

enum ReaderHaptics {
    /// The pure event-to-style mapping, pinned in unit tests.
    static func style(for event: ReaderHapticEvent) -> ReaderHapticStyle {
        switch event {
        case .menuToggle, .menuItemTap, .contextMenuOpen, .bookmarkRemove, .favoriteRemove:
            .light
        case .bookmarkAdd, .favoriteAdd:
            .medium
        case .pageSettle:
            .soft
        case .layersRejected:
            .error
        }
    }
}

/// Injectable seam behind every reader haptic: production plays the system
/// generators, tests swap in a recorder and assert trigger points.
protocol ReaderHapticPlayer {
    func play(_ event: ReaderHapticEvent)
}

struct SystemReaderHapticPlayer: ReaderHapticPlayer {
    func play(_ event: ReaderHapticEvent) {
        switch ReaderHaptics.style(for: event) {
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .soft:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

enum ReaderHapticDispatcher {
    static var shared: any ReaderHapticPlayer = SystemReaderHapticPlayer()

    static func trigger(_ event: ReaderHapticEvent) {
        shared.play(event)
    }
}

@MainActor
final class ReaderPagingPanHandler: NSObject, UIGestureRecognizerDelegate {
    var pageDirection: HorizontalDirection
    var isEnabled: () -> Bool
    var onTurn: (ReaderPageTurn) -> Void
    var onProgress: (CGFloat) -> Void
    /// Release resolution for track-the-finger paging: the committed turn,
    /// or nil to cancel back to the current page. Defaults to driving
    /// `onTurn`, so discrete-swipe callers keep working unchanged.
    var onRelease: ((ReaderPageTurn?) -> Void)?
    private(set) var axisLock: ReaderAxisLock = .undecided
    private(set) weak var recognizer: UIPanGestureRecognizer?

    init(
        pageDirection: HorizontalDirection,
        isEnabled: @escaping () -> Bool,
        onTurn: @escaping (ReaderPageTurn) -> Void,
        onProgress: @escaping (CGFloat) -> Void = { _ in },
        onRelease: ((ReaderPageTurn?) -> Void)? = nil
    ) {
        self.pageDirection = pageDirection
        self.isEnabled = isEnabled
        self.onTurn = onTurn
        self.onProgress = onProgress
        self.onRelease = onRelease
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
        guard isEnabled() else { return }
        switch state {
        case .began:
            // A new gesture always re-arbitrates its axis from scratch.
            axisLock = .undecided
            onProgress(0)
            return
        case .changed:
            axisLock = ReaderAxisLockPolicy.update(current: axisLock, translation: translation)
            // Locked to the dominant axis: a mostly-vertical drag never
            // moves the page horizontally (progress stays pinned at rest).
            onProgress(axisLock == .horizontal ? translation.x : 0)
            return
        case .ended:
            axisLock = ReaderAxisLockPolicy.update(current: axisLock, translation: translation)
            let turn = ReaderDragRelease.turn(
                translation: translation,
                velocity: velocity,
                lock: axisLock,
                pageDirection: pageDirection
            )
            axisLock = .undecided
            if let turn {
                onTurn(turn)
            }
            onRelease?(turn)
            onProgress(0)
            return
        default:
            // Cancelled, failed, or possible: no turn, drag back to rest.
            axisLock = .undecided
            onRelease?(nil)
            onProgress(0)
            return
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
