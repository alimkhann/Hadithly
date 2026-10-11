import Foundation

/// Test-only entry points must not be reachable by launching an ordinary
/// Debug app with a copied command-line argument.
enum AutomationContext {
    static var isActive: Bool {
#if DEBUG
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            ProcessInfo.processInfo.environment["HADITHLY_UI_TESTING"] == "1"
#else
        false
#endif
    }

    static func allows(_ argument: String) -> Bool {
        isActive && ProcessInfo.processInfo.arguments.contains(argument)
    }
}
