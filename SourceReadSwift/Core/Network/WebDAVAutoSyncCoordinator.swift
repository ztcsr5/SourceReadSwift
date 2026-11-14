import Foundation

/// Pure decision logic for checking whether WebDAV holds a newer snapshot than
/// the local device's last recorded sync timestamp.
enum WebDAVSyncDecision {
    static func newerRemoteBackup(
        items: [WebDAVRemoteItem],
        lastLocalSyncTimestamp: Double,
        lastUploadedFilename: String? = nil,
        clockToleranceSeconds: TimeInterval = 15
    ) -> WebDAVRemoteItem? {
        let threshold = Date(timeIntervalSince1970: max(lastLocalSyncTimestamp, 0) + clockToleranceSeconds)
        let sorted = items
            .filter { !$0.isDirectory && ($0.filename.lowercased().hasSuffix(".json") || $0.filename.lowercased().hasSuffix(".backup")) }
            .sorted { ($0.lastModified ?? .distantPast) > ($1.lastModified ?? .distantPast) }
        guard let newest = sorted.first, let modified = newest.lastModified else {
            return nil
        }
        if let lastUploadedFilename, newest.filename == lastUploadedFilename {
            return nil
        }
        if lastLocalSyncTimestamp <= 0 {
            return newest
        }
        return modified > threshold ? newest : nil
    }
}

/// Coordinates automatic WebDAV upload on background/exit (`webdav.autoSyncOnExit`)
/// and newer-remote backup detection when returning to the foreground.
@MainActor
final class WebDAVAutoSyncCoordinator: ObservableObject {
    static let shared = WebDAVAutoSyncCoordinator()

    enum DefaultsKey {
        static let serverURL = "webdav.serverURL"
        static let username = "webdav.username"
        static let remoteDirectory = "webdav.remoteDirectory"
        static let autoSyncOnExit = "webdav.autoSyncOnExit"
        static let lastSyncDate = "webdav.lastSyncDate"
        static let lastUploadedFilename = "webdav.lastUploadedFilename"
    }

    @Published var pendingNewerBackup: WebDAVRemoteItem?

    private let credentialStore = WebDAVCredentialStore()
    private var lastAutoUploadAt: Date?
    private var lastForegroundCheckAt: Date?
    private var dismissedRemoteIDs: Set<String> = []
    private var activeUploadTask: Task<Void, Never>?
    private var activeCheckTask: Task<Void, Never>?

    private init() {}

    func currentConfig(defaults: UserDefaults = .standard) -> WebDAVConfig {
        let server = defaults.string(forKey: DefaultsKey.serverURL) ?? "https://dav.jianguoyun.com/dav/"
        let user = defaults.string(forKey: DefaultsKey.username) ?? ""
        let dir = defaults.string(forKey: DefaultsKey.remoteDirectory) ?? "SourceReadSwift"
        let pwd = (try? credentialStore.load()) ?? ""
        return WebDAVConfig(serverURL: server, username: user, password: pwd, remoteDirectory: dir)
    }

    func performAutoUploadIfNeeded(appState: AppState, force: Bool = false) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: DefaultsKey.autoSyncOnExit) else { return }
        let config = currentConfig(defaults: defaults)
        guard config.isConfigured else { return }
        if !force, let last = lastAutoUploadAt, Date().timeIntervalSince(last) < 60 {
            return
        }
        lastAutoUploadAt = Date()
        let snapshot = appState.makeAppDataBackupSnapshot()
        let lease = ReadingWriteBackgroundLease()
        activeUploadTask?.cancel()
        activeUploadTask = Task {
            do {
                let filename = try await WebDAVSyncService.shared.uploadSnapshot(snapshot: snapshot, config: config)
                await MainActor.run {
                    defaults.set(Date().timeIntervalSince1970, forKey: DefaultsKey.lastSyncDate)
                    defaults.set(filename, forKey: DefaultsKey.lastUploadedFilename)
                    appState.record(DiagnosticEvent(
                        level: .info,
                        stage: "webdav.autoSync",
                        sourceName: filename,
                        message: "退后台自动云端备份已完成"
                    ))
                    lease.end()
                }
            } catch {
                await MainActor.run {
                    appState.record(DiagnosticEvent(
                        level: .warning,
                        stage: "webdav.autoSync",
                        message: "自动备份跳过：\(error.localizedDescription)"
                    ))
                    lease.end()
                }
            }
        }
    }

    func checkForNewerRemoteBackupIfNeeded() {
        let defaults = UserDefaults.standard
        let config = currentConfig(defaults: defaults)
        guard config.isConfigured else { return }
        if let last = lastForegroundCheckAt, Date().timeIntervalSince(last) < 120 {
            return
        }
        lastForegroundCheckAt = Date()
        let lastSync = defaults.double(forKey: DefaultsKey.lastSyncDate)
        let lastFilename = defaults.string(forKey: DefaultsKey.lastUploadedFilename)
        activeCheckTask?.cancel()
        activeCheckTask = Task {
            do {
                let items = try await WebDAVSyncService.shared.listBackups(config: config)
                await MainActor.run {
                    guard let candidate = WebDAVSyncDecision.newerRemoteBackup(
                        items: items,
                        lastLocalSyncTimestamp: lastSync,
                        lastUploadedFilename: lastFilename
                    ), !self.dismissedRemoteIDs.contains(candidate.id) else {
                        return
                    }
                    self.pendingNewerBackup = candidate
                }
            } catch {
                // Silent on startup/foreground check so transient offline states never nag.
            }
        }
    }

    func dismissPendingBackup() {
        if let item = pendingNewerBackup {
            dismissedRemoteIDs.insert(item.id)
        }
        pendingNewerBackup = nil
    }

    func restorePendingBackup(into appState: AppState) async throws -> AppDataBackupSnapshot {
        guard let item = pendingNewerBackup else {
            throw WebDAVError.fileNotFound
        }
        let defaults = UserDefaults.standard
        let config = currentConfig(defaults: defaults)
        let snapshot = try await WebDAVSyncService.shared.downloadSnapshot(filename: item.filename, config: config)
        try appState.restoreAppDataBackup(snapshot)
        defaults.set(Date().timeIntervalSince1970, forKey: DefaultsKey.lastSyncDate)
        defaults.set(item.filename, forKey: DefaultsKey.lastUploadedFilename)
        dismissedRemoteIDs.insert(item.id)
        pendingNewerBackup = nil
        return snapshot
    }
}
