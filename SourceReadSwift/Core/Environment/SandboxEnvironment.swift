import Foundation

/// Detects sandbox runtime environments such as LiveContainer, SideStore, or TrollStore.
///
/// LiveContainer runs guest applications inside an unprivileged virtualized container
/// without JIT entitlements or multi-process WebKit support. Under LiveContainer,
/// headless WKWebView instantiation in background tasks will abort or trigger memory
/// limits, and file system directories (like Library/Application Support) may not exist.
enum SandboxEnvironment {
    /// True when running inside LiveContainer.
    static var isLiveContainer: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["LIVECONTAINER"] != nil || env["LC_APP_ID"] != nil {
            return true
        }
        let bundlePath = Bundle.main.bundlePath.lowercased()
        if bundlePath.contains("livecontainer") || bundlePath.contains("/data/app/") {
            return true
        }
        let home = NSHomeDirectory().lowercased()
        if home.contains("livecontainer") {
            return true
        }
        let bundleID = Bundle.main.bundleIdentifier?.lowercased() ?? ""
        if bundleID.contains("livecontainer") {
            return true
        }
        let exec = Bundle.main.executablePath?.lowercased() ?? ""
        if exec.contains("livecontainer") {
            return true
        }
        return false
    }

    /// Safe batch concurrency to avoid exhausting memory or Mach ports.
    static var recommendedBatchConcurrency: Int {
        isLiveContainer ? 2 : 3
    }
}
