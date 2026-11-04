import SwiftUI
import AppIntents
import ClerkKit
import UIKit

@main
struct HadithlyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            LocalizedAppRoot()
                .environment(environment)
        }
    }
}

/// Reads locale and direction inside the observable view tree. Keeping these
/// environment values here makes a live RTL-to-LTR switch update the existing
/// window instead of relying on the App scene body to be reevaluated.
private struct LocalizedAppRoot: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let preferences = environment.preferences.preferences
        let uiLocale = preferences.uiLocale

        AppPaletteRoot(theme: preferences.appTheme) {
            RootView()
        }
            .environment(environment.guestData)
            .environment(environment.library)
            .environment(environment.push)
            .environment(Clerk.shared)
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { environment.analytics.flush() }
            }
            .environment(\.locale, Locale(identifier: uiLocale))
            .environment(
                \.layoutDirection,
                LocaleFallback.isRTL(uiLocale) ? .rightToLeft : .leftToRight
            )
    }
}

/// One palette owner for all app content, presented sheets, tabs, and bars.
/// Updating the preference only invalidates this environment; it never changes
/// a view identity, so NavigationStack and Reader state remain in place.
private struct AppPaletteRoot<Content: View>: View {
    @Environment(\.colorScheme) private var systemScheme
    let theme: ReaderTheme
    let content: Content

    init(theme: ReaderTheme, @ViewBuilder content: () -> Content) {
        self.theme = theme
        self.content = content()
    }

    private var palette: ReaderPalette {
        ReaderPalette.resolved(theme, systemDark: systemScheme == .dark)
    }

    private var themedContent: Content {
        Theme.install(palette)
        return content
    }

    var body: some View {
        themedContent
            .nativeAppearanceBoundary()
            .environment(\.readerPalette, palette)
            .environment(\.readerTheme, theme)
            .tint(palette.interactive)
            .preferredColorScheme(ReaderPalette.preferredColorScheme(for: theme))
    }
}

@available(iOS 27, *)
final class ReaderOrientationSceneDelegate: NSObject, UIWindowSceneDelegate {
    func supportedInterfaceOrientations(for scene: UIWindowScene) -> UIInterfaceOrientationMask {
        ReaderOrientation.supportedOrientations(in: scene)
    }
}

@MainActor
@Observable
final class ReaderOrientation {
    private static let readers = NSMapTable<UIWindowScene, ReaderOrientation>.weakToWeakObjects()

    private weak var scene: UIWindowScene?
    private var observation: NSKeyValueObservation?
    private var lockedMask: UIInterfaceOrientationMask?
    private(set) var interfaceOrientation: UIInterfaceOrientation = .unknown
    fileprivate(set) var isResizing = false

    var isLocked: Bool { lockedMask != nil }
    var windowSafeInsets: UIEdgeInsets? { scene?.keyWindow?.safeAreaInsets }
    fileprivate var currentOrientation: UIInterfaceOrientation? { scene?.effectiveGeometry.interfaceOrientation }

    static func supportedOrientations(in scene: UIWindowScene?) -> UIInterfaceOrientationMask {
        guard let scene, let reader = readers.object(forKey: scene) else { return .portrait }
        return reader.lockedMask ?? .allButUpsideDown
    }

    func toggleLock() {
        guard let scene else { return }
        let orientation = scene.effectiveGeometry.interfaceOrientation
        if isLocked {
            lockedMask = nil
        } else {
            guard orientation != .unknown else { return }
            lockedMask = UIInterfaceOrientationMask(rawValue: 1 << orientation.rawValue)
        }
        Self.refresh(scene)
    }

    fileprivate func attach(to newScene: UIWindowScene?) {
        guard scene !== newScene else { return }
        observation = nil
        if let scene, Self.readers.object(forKey: scene) === self {
            Self.readers.removeObject(forKey: scene)
            Self.refresh(scene)
            if !scene.effectiveGeometry.interfaceOrientation.isPortrait {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
        }
        scene = newScene
        guard let newScene else { return }
        Self.readers.setObject(self, forKey: newScene)
        observation = newScene.observe(\.effectiveGeometry, options: [.initial, .new]) { [weak self] scene, _ in
            Task { @MainActor in
                guard let self, self.scene === scene else { return }
                let orientation = scene.effectiveGeometry.interfaceOrientation
                if self.interfaceOrientation != orientation {
                    self.interfaceOrientation = orientation
                }
            }
        }
        Self.refresh(newScene)
    }

    private static func refresh(_ scene: UIWindowScene) {
        var controller = scene.keyWindow?.rootViewController
        while let current = controller {
            current.setNeedsUpdateOfSupportedInterfaceOrientations()
            controller = current.presentedViewController
        }
    }
}

struct ReaderOrientationBoundary: UIViewControllerRepresentable {
    let orientation: ReaderOrientation
    let onResize: () -> Void

    func makeUIViewController(context: Context) -> WindowObserver {
        let observer = WindowObserver()
        observer.orientation = orientation
        observer.onResize = onResize
        return observer
    }

    func updateUIViewController(_ observer: WindowObserver, context: Context) {
        observer.onResize = onResize
    }

    static func dismantleUIViewController(_ observer: WindowObserver, coordinator: ()) {
        observer.orientation?.attach(to: nil)
        observer.orientation = nil
    }

    final class WindowObserver: UIViewController {
        weak var orientation: ReaderOrientation?
        var onResize: (() -> Void)?

        override func loadView() {
            let observer = SceneView()
            observer.isUserInteractionEnabled = false
            observer.onMove = { [weak self] scene in self?.orientation?.attach(to: scene) }
            view = observer
        }

        override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
            super.viewWillTransition(to: size, with: coordinator)
            let previousOrientation = orientation?.currentOrientation
            orientation?.isResizing = true
            let registered = coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                guard let self, let orientation, orientation.isResizing else { return }
                if orientation.currentOrientation != previousOrientation { onResize?() }
                orientation.isResizing = false
            }
            if !registered { orientation?.isResizing = false }
        }
    }

    final class SceneView: UIView {
        var onMove: ((UIWindowScene?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onMove?(window?.windowScene)
        }
    }
}
