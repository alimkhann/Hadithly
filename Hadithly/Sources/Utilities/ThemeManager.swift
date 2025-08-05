import SwiftUI

class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var currentTheme: AppTheme = .system

    private init() {}

    func applyTheme(_ theme: AppTheme) {
        currentTheme = theme

        switch theme {
        case .light:
            setAppearance(.light)
        case .dark:
            setAppearance(.dark)
        case .system:
            setAppearance(nil)
        }
    }

    private func setAppearance(_ appearance: UIUserInterfaceStyle?) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.windows.forEach { window in
                window.overrideUserInterfaceStyle = appearance ?? .unspecified
            }
        }
    }
}