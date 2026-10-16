import SwiftUI
import UIKit

/// Keep UIKit-owned menus and controls in the same appearance as SwiftUI content.
struct NativeAppearanceBoundary: ViewModifier {
    @Environment(\.readerTheme) private var theme
    @Environment(\.colorScheme) private var inheritedScheme
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    var statusHidden: Bool?

    private var scheme: ColorScheme { ReaderPalette.preferredColorScheme(for: theme) ?? inheritedScheme }
    func body(content: Content) -> some View {
        content.environment(\.colorScheme, scheme)
            .background {
                AppearanceControllerBridge(style: theme == .system ? .unspecified : (scheme == .dark ? .dark : .light),
                    statusHidden: statusHidden, animated: !reducedMotion)
                    .frame(width: 0, height: 0).allowsHitTesting(false).accessibilityHidden(true)
            }
    }
}

extension View {
    func nativeAppearanceBoundary(statusHidden: Bool? = nil) -> some View {
        modifier(NativeAppearanceBoundary(statusHidden: statusHidden))
    }
}

private struct AppearanceControllerBridge: UIViewControllerRepresentable {
    let style: UIUserInterfaceStyle
    let statusHidden: Bool?
    let animated: Bool
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.update(style: style, statusHidden: statusHidden, animated: animated)
    }
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.restore() }

    final class Controller: UIViewController {
        private weak var owner: UIViewController?
        private var previousStyle: UIUserInterfaceStyle = .unspecified
        private var style: UIUserInterfaceStyle = .unspecified
        private var statusHidden: Bool?
        override func loadView() { view = UIView(frame: .zero); view.isUserInteractionEnabled = false }
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if let parent { apply(to: parent) } else { restore() }
        }
        func update(style: UIUserInterfaceStyle, statusHidden: Bool?, animated: Bool) {
            let statusChanged = self.statusHidden != statusHidden
            self.style = style
            self.statusHidden = statusHidden
            guard let parent else { return }
            apply(to: parent)
            if statusChanged {
                let refresh = { parent.setNeedsStatusBarAppearanceUpdate(); parent.view.layoutIfNeeded() }
                if animated { UIView.animate(withDuration: InterfaceMotion.step, animations: refresh) }
                else { UIView.performWithoutAnimation(refresh) }
            }
        }
        private func apply(to parent: UIViewController) {
            if owner !== parent { restore(); owner = parent; previousStyle = parent.overrideUserInterfaceStyle }
            if parent.overrideUserInterfaceStyle != style { parent.overrideUserInterfaceStyle = style }
            view.overrideUserInterfaceStyle = style
        }
        func restore() {
            if let owner, owner.overrideUserInterfaceStyle == style { owner.overrideUserInterfaceStyle = previousStyle }
            owner = nil
        }
    }
}
