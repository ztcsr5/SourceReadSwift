import Foundation
import MachO

/// Detects sandbox runtime environments such as LiveContainer, SideStore, or TrollStore.
///
/// LiveContainer runs guest applications inside an unprivileged virtualized container
/// without JIT entitlements or multi-process WebKit support. Under LiveContainer,
/// headless WKWebView instantiation in background tasks will abort or trigger memory
/// limits, and file system directories (like Library/Application Support) may not exist.
enum SandboxEnvironment {
    /// True when running inside LiveContainer or a guest app container.
    static var isLiveContainer: Bool {
        detectLiveContainer(
            environment: ProcessInfo.processInfo.environment,
            bundlePath: Bundle.main.bundlePath,
            homeDirectory: NSHomeDirectory(),
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "",
            executablePath: Bundle.main.executablePath ?? "",
            loadedImageNames: loadedDyldImageNames(),
            hasLiveContainerClass: NSClassFromString("LCSharedUtils") != nil
                || NSClassFromString("LCTweakLoader") != nil
                || NSClassFromString("LiveContainer") != nil
        )
    }

    static func detectLiveContainer(
        environment: [String: String],
        bundlePath: String,
        homeDirectory: String,
        bundleIdentifier: String,
        executablePath: String,
        loadedImageNames: [String] = [],
        hasLiveContainerClass: Bool = false
    ) -> Bool {
        if hasLiveContainerClass {
            return true
        }
        if environment["LIVECONTAINER"] != nil
            || environment["LC_APP_ID"] != nil
            || environment["LC_HOME_PATH"] != nil
            || environment.keys.contains(where: { $0.hasPrefix("LC_") || $0.hasPrefix("LIVECONTAINER") }) {
            return true
        }
        for image in loadedImageNames {
            let lowerImage = image.lowercased()
            if lowerImage.contains("livecontainer")
                || lowerImage.contains("tweakloader")
                || lowerImage.contains("lcshared") {
                return true
            }
        }
        let lowerBundlePath = bundlePath.lowercased()
        if lowerBundlePath.contains("livecontainer")
            || lowerBundlePath.contains("/data/app/")
            || lowerBundlePath.contains("/documents/applications/")
            || (lowerBundlePath.contains("/containers/data/application/") && lowerBundlePath.contains("/applications/"))
            || (lowerBundlePath.contains("/containers/shared/appgroup/") && lowerBundlePath.contains("/applications/")) {
            return true
        }
        let lowerHome = homeDirectory.lowercased()
        if lowerHome.contains("livecontainer")
            || lowerHome.contains("/documents/data/application/")
            || lowerHome.contains("/documents/applications/") {
            return true
        }
        if bundleIdentifier.lowercased().contains("livecontainer") {
            return true
        }
        if executablePath.lowercased().contains("livecontainer") {
            return true
        }
        return false
    }

    private static func loadedDyldImageNames() -> [String] {
        let count = _dyld_image_count()
        var names: [String] = []
        names.reserveCapacity(Int(min(count, 512)))
        for index in 0..<count {
            if let rawName = _dyld_get_image_name(index) {
                names.append(String(cString: rawName))
            }
        }
        return names
    }

    /// Safe batch concurrency to avoid exhausting memory or Mach ports.
    static var recommendedBatchConcurrency: Int {
        let saved = UserDefaults.standard.integer(forKey: "batch_check_concurrent_threads")
        if saved >= 1 && saved <= 16 {
            return saved
        }
        return isLiveContainer ? 2 : 8
    }
}
