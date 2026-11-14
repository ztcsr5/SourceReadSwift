import UIKit

/// Compatibility facade; new UI uses explicit async commit rather than saving on pick.
enum ReaderCustomWallpaperStore {
    private static let lock = NSRecursiveLock()
    private static var cached: ReaderWallpaperSnapshot?
    private static var revision = 0
    private static var failure: String?
    private static var repository: ReaderWallpaperRepository {
        ReaderWallpaperRepository(rootURL: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
    }
    static var wallpaperURL: URL { repository.legacyURL }
    static var hasEditedWallpaper: Bool { FileManager.default.fileExists(atPath: repository.recordURL.path) }
    static var cachedWallpaper: UIImage? { lock.lock(); defer { lock.unlock() }; return cached?.image }
    static var cachedJPEG: Data? { lock.lock(); defer { lock.unlock() }; return cached?.jpeg }
    static var adjustment: ReaderWallpaperAdjustment { lock.lock(); defer { lock.unlock() }; return cached?.adjustment ?? .init() }
    static var lastError: String? { lock.lock(); defer { lock.unlock() }; return failure }
    static var hasCustomWallpaper: Bool {
        cachedWallpaper != nil || FileManager.default.fileExists(atPath: repository.recordURL.path) || FileManager.default.fileExists(atPath: repository.legacyURL.path)
    }
    static var linkedAccentHex: UInt32? {
        lock.lock()
        let inMem = cached?.adjustment.linkedAccentHex
        lock.unlock()
        if let inMem { return inMem }
        let raw = UserDefaults.standard.integer(forKey: "reader.customWallpaperLinkedAccentHex")
        return raw > 0 ? UInt32(raw) : nil
    }

    static func linkedInkHex(isNight: Bool) -> UInt32? {
        lock.lock()
        let adj = cached?.adjustment
        lock.unlock()
        if let adj {
            return isNight ? adj.linkedNightInkHex : adj.linkedInkHex
        }
        let key = isNight ? "reader.customWallpaperLinkedNightInkHex" : "reader.customWallpaperLinkedInkHex"
        let raw = UserDefaults.standard.integer(forKey: key)
        return raw > 0 ? UInt32(raw) : nil
    }

    static var isWallpaperDark: Bool {
        if UserDefaults.standard.bool(forKey: "reader.customBackgroundIsDarkManual") {
            return UserDefaults.standard.bool(forKey: "reader.customBackgroundIsDark")
        }
        lock.lock(); defer { lock.unlock() }
        return cached?.adjustment.usesLightText ?? UserDefaults.standard.bool(forKey: "reader.customBackgroundIsDark")
    }

    static func warmWallpaper() async {
        let state = cacheState()
        guard !state.hasImage else { return }
        do {
            let target = repository
            let snapshot = try await Task.detached(priority: .userInitiated) { try target.load() }.value
            acceptWarm(snapshot, expected: state.revision)
        } catch { recordFailure(error, expected: state.revision) }
    }

    @MainActor static func saveEditedWallpaper(_ image: UIImage, adjustment: ReaderWallpaperAdjustment) async throws {
        advanceRevision()
        let target = repository
        let snapshot = try await Task.detached(priority: .userInitiated) { try target.save(image: image, adjustment: adjustment) }.value
        accept(snapshot)
    }

    @MainActor static func restoreEncodedWallpaper(_ jpeg: Data, adjustment: ReaderWallpaperAdjustment) async throws {
        advanceRevision()
        let target = repository
        let snapshot = try await Task.detached(priority: .userInitiated) { try target.saveEncodedJPEG(jpeg, adjustment: adjustment) }.value
        accept(snapshot)
    }

    @MainActor static func clearEditedWallpaper() async throws {
        advanceRevision()
        let target = repository
        try await Task.detached(priority: .utility) { try target.clear() }.value
        resetCache()
    }

    static func loadWallpaper() -> UIImage? {
        if let cachedWallpaper { return cachedWallpaper }
        do {
            let snapshot = try repository.load()
            lock.lock(); cached = snapshot; failure = nil; lock.unlock()
            return snapshot?.image
        } catch { recordFailure(error); return nil }
    }

    static func saveWallpaper(_ image: UIImage) {
        do {
            var adjustment = ReaderWallpaperAdjustment(); adjustment.usesLightText = image.isDarkPerception
            accept(try repository.save(image: image, adjustment: adjustment))
        } catch { recordFailure(error) }
    }
    static func clearWallpaper() {
        do { try repository.clear(); resetCache() }
        catch { recordFailure(error) }
    }

    private static func accept(_ snapshot: ReaderWallpaperSnapshot) {
        lock.lock(); revision += 1; cached = snapshot; failure = nil; lock.unlock()
        UserDefaults.standard.set(snapshot.adjustment.usesLightText, forKey: "reader.customBackgroundIsDark")
        UserDefaults.standard.set(true, forKey: "reader.customBackgroundIsDarkManual")
        UserDefaults.standard.set(snapshot.adjustment.fillMode.rawValue, forKey: "reader.customWallpaperFillMode")
        if let ink = snapshot.adjustment.linkedInkHex {
            UserDefaults.standard.set(Int(ink), forKey: "reader.customWallpaperLinkedInkHex")
        } else {
            UserDefaults.standard.removeObject(forKey: "reader.customWallpaperLinkedInkHex")
        }
        if let nightInk = snapshot.adjustment.linkedNightInkHex {
            UserDefaults.standard.set(Int(nightInk), forKey: "reader.customWallpaperLinkedNightInkHex")
        } else {
            UserDefaults.standard.removeObject(forKey: "reader.customWallpaperLinkedNightInkHex")
        }
        if let accent = snapshot.adjustment.linkedAccentHex {
            UserDefaults.standard.set(Int(accent), forKey: "reader.customWallpaperLinkedAccentHex")
        } else {
            UserDefaults.standard.removeObject(forKey: "reader.customWallpaperLinkedAccentHex")
        }
    }
    private static func resetCache() {
        lock.lock(); revision += 1; cached = nil; failure = nil; lock.unlock()
        UserDefaults.standard.removeObject(forKey: "reader.customBackgroundIsDark")
        UserDefaults.standard.removeObject(forKey: "reader.customBackgroundIsDarkManual")
        UserDefaults.standard.removeObject(forKey: "reader.customWallpaperLinkedInkHex")
        UserDefaults.standard.removeObject(forKey: "reader.customWallpaperLinkedNightInkHex")
        UserDefaults.standard.removeObject(forKey: "reader.customWallpaperLinkedAccentHex")
    }
    private static func cacheState() -> (revision: Int, hasImage: Bool) {
        lock.lock(); defer { lock.unlock() }; return (revision, cached != nil)
    }
    private static func advanceRevision() { lock.lock(); revision += 1; lock.unlock() }
    private static func acceptWarm(_ snapshot: ReaderWallpaperSnapshot?, expected: Int) {
        lock.lock(); defer { lock.unlock() }
        guard revision == expected else { return }
        cached = snapshot; failure = nil
    }
    private static func recordFailure(_ error: Error, expected: Int? = nil) {
        lock.lock(); defer { lock.unlock() }
        guard expected == nil || expected == revision else { return }
        failure = "壁纸操作失败：" + error.localizedDescription
    }
}
