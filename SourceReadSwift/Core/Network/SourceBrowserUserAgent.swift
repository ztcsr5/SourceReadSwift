import Foundation

/// One compatibility identity for source scripts, login pages and browser fallbacks.
enum SourceBrowserUserAgent {
    // Keep the existing Mobile Safari identity stable across login and later requests.
    // This is an explicit compatibility policy, not the device's detected OS version.
    static let value = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
}
