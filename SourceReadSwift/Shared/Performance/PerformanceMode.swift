import Foundation

/// Diagnostic switch for isolating compositor cost from main-thread work.
/// Off by default: the designed UI keeps its native glass and system tab bar.
enum PerformanceMode {
    static let defaultsKey = "settings.performanceMode"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }
}
