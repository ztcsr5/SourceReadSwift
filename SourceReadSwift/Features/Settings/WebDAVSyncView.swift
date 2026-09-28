import SwiftUI
import UIKit

/// Presets for popular WebDAV cloud storage providers.
enum WebDAVProviderPreset: String, CaseIterable, Identifiable {
    case jianguoyun = "坚果云"
    case nextcloud = "Nextcloud"
    case custom = "自定义"

    var id: String { rawValue }

    var defaultURL: String {
        switch self {
        case .jianguoyun:
            return "https://dav.jianguoyun.com/dav/"
        case .nextcloud:
            return "https://cloud.example.com/remote.php/dav/files/username/"
        case .custom:
            return "https://"
        }
    }

    var hintText: String {
        switch self {
        case .jianguoyun:
            return "坚果云需在官网「账户信息 - 安全设置」中生成专用应用密码（非网页登录密码）。"
        case .nextcloud:
            return "Nextcloud 建议使用「个人设置 - 安全 - 设备与会话」创建独立应用令牌。"
        case .custom:
            return "支持标准 WebDAV 协议（如 Synology 群晖、QNAP 威联通、Alist、Koofr 等）。"
        }
    }
}

/// WebDAV cloud synchronization and multi-device backup management view.
struct WebDAVSyncView: View {
    @EnvironmentObject private var appState: AppState

    @AppStorage("webdav.serverURL") private var serverURL: String = "https://dav.jianguoyun.com/dav/"
    @AppStorage("webdav.username") private var username: String = ""
    @AppStorage("webdav.password") private var password: String = ""
    @AppStorage("webdav.remoteDirectory") private var remoteDirectory: String = "SourceReadSwift"
    @AppStorage("webdav.lastSyncDate") private var lastSyncTimestamp: Double = 0
    @AppStorage("webdav.autoSyncOnExit") private var autoSyncOnExit: Bool = false

    @State private var selectedPreset: WebDAVProviderPreset = .jianguoyun
    @State private var isTesting = false
    @State private var testResult: TestResult? = nil
    @State private var isUploading = false
    @State private var isFetchingList = false
    @State private var remoteBackups: [WebDAVRemoteItem] = []
    @State private var actionMessage: String?
    @State private var selectedBackupToRestore: WebDAVRemoteItem?
    @State private var showRestoreConfirmation = false
    @State private var isRestoring = false

    private enum TestResult {
        case success(String)
        case failure(String)
    }

    private var currentConfig: WebDAVConfig {
        WebDAVConfig(
            serverURL: serverURL,
            username: username,
            password: password,
            remoteDirectory: remoteDirectory
        )
    }

    var body: some View {
        List {
            // MARK: - Server Configuration
            Section {
                Picker("服务预设", selection: $selectedPreset) {
                    ForEach(WebDAVProviderPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .onChange(of: selectedPreset) { newPreset in
                    if newPreset != .custom && serverURL.isEmpty || serverURL == "https://" || serverURL.contains("jianguoyun") || serverURL.contains("cloud.example.com") {
                        serverURL = newPreset.defaultURL
                    }
                }

                HStack {
                    Text("服务器")
                        .frame(width: 72, alignment: .leading)
                    TextField("https://dav.example.com/dav/", text: $serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                HStack {
                    Text("账号")
                        .frame(width: 72, alignment: .leading)
                    TextField("用户名或注册邮箱", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                HStack {
                    Text("密码")
                        .frame(width: 72, alignment: .leading)
                    SecureField("应用密码或授权令牌", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                HStack {
                    Text("远程目录")
                        .frame(width: 72, alignment: .leading)
                    TextField("SourceReadSwift", text: $remoteDirectory)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Button {
                    testConnection()
                } label: {
                    HStack {
                        Label("测试连接", systemImage: "antenna.radiowaves.left.and.right")
                        Spacer()
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        } else if let result = testResult {
                            switch result {
                            case .success(let text):
                                Text(text)
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            case .failure(let text):
                                Text(text)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
                .disabled(!currentConfig.isConfigured || isTesting)
            } header: {
                Text("WebDAV 账户配置")
            } footer: {
                Text(selectedPreset.hintText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // MARK: - Cloud Backup Actions
            Section("云端备份操作") {
                Button {
                    uploadBackupNow()
                } label: {
                    HStack {
                        Label("立即备份到云端", systemImage: "arrow.up.icloud")
                        Spacer()
                        if isUploading {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(!currentConfig.isConfigured || isUploading)

                if lastSyncTimestamp > 0 {
                    HStack {
                        Text("上次云端备份")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formattedLastSyncDate)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                if let message = actionMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(message.contains("失败") ? .red : .secondary)
                }
            }

            // MARK: - Remote Backups List
            Section {
                Button {
                    fetchRemoteBackups()
                } label: {
                    HStack {
                        Label("刷新云端备份列表", systemImage: "arrow.clockwise")
                        Spacer()
                        if isFetchingList {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(!currentConfig.isConfigured || isFetchingList)

                if isFetchingList && remoteBackups.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView("正在连接云端...")
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else if remoteBackups.isEmpty {
                    Text("云端暂无备份文件。点击上方「立即备份到云端」开始首次备份。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(remoteBackups) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.filename)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                HStack(spacing: 8) {
                                    Text(item.formattedDate)
                                    Text("·")
                                    Text(item.formattedSize)
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                selectedBackupToRestore = item
                                showRestoreConfirmation = true
                            } label: {
                                Text("恢复")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.accent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(AppTheme.accent.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.borderless)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteRemoteBackup(item)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("云端备份历史")
            } footer: {
                Text("从云端恢复将合并与更新您现有的书架藏书、书源规则、净化设置与阅读偏好。左滑可删除历史备份。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("WebDAV 云端同步")
        .navigationBarTitleDisplayMode(.inline)
        .alert("确认从云端恢复？", isPresented: $showRestoreConfirmation) {
            Button("取消", role: .cancel) { selectedBackupToRestore = nil }
            Button("立即恢复", role: .destructive) {
                if let item = selectedBackupToRestore {
                    restoreFromCloud(item)
                }
            }
        } message: {
            if let item = selectedBackupToRestore {
                Text("即将从云端备份「\(item.filename)」恢复完整数据。请确认操作。")
            } else {
                Text("即将恢复完整数据。")
            }
        }
        .onAppear {
            if currentConfig.isConfigured && remoteBackups.isEmpty {
                fetchRemoteBackups()
            }
        }
    }

    private var formattedLastSyncDate: String {
        guard lastSyncTimestamp > 0 else { return "从未" }
        let date = Date(timeIntervalSince1970: lastSyncTimestamp)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }

    // MARK: - Actions

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task {
            do {
                let success = try await WebDAVSyncService.shared.testConnection(config: currentConfig)
                await MainActor.run {
                    isTesting = false
                    if success {
                        testResult = .success("连接成功！")
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } else {
                        testResult = .failure("服务器未就绪")
                    }
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    testResult = .failure(error.localizedDescription)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func uploadBackupNow() {
        isUploading = true
        actionMessage = nil
        Task {
            do {
                let snapshot = await MainActor.run {
                    appState.makeAppDataBackupSnapshot()
                }
                let uploadedFilename = try await WebDAVSyncService.shared.uploadSnapshot(
                    snapshot: snapshot,
                    config: currentConfig
                )
                await MainActor.run {
                    isUploading = false
                    lastSyncTimestamp = Date().timeIntervalSince1970
                    actionMessage = "已成功备份到云端：\(uploadedFilename)"
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    fetchRemoteBackups()
                }
            } catch {
                await MainActor.run {
                    isUploading = false
                    actionMessage = "云端备份失败：\(error.localizedDescription)"
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func fetchRemoteBackups() {
        guard currentConfig.isConfigured else { return }
        isFetchingList = true
        Task {
            do {
                let list = try await WebDAVSyncService.shared.listBackups(config: currentConfig)
                await MainActor.run {
                    remoteBackups = list
                    isFetchingList = false
                }
            } catch {
                await MainActor.run {
                    isFetchingList = false
                    actionMessage = "获取云端列表失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func restoreFromCloud(_ item: WebDAVRemoteItem) {
        isRestoring = true
        actionMessage = nil
        Task {
            do {
                let snapshot = try await WebDAVSyncService.shared.downloadSnapshot(
                    filename: item.filename,
                    config: currentConfig
                )
                await MainActor.run {
                    do {
                        try appState.restoreAppDataBackup(snapshot)
                        isRestoring = false
                        actionMessage = "成功恢复 \(snapshot.bookshelf.books.count) 本书、\(snapshot.sources.sources.count) 个书源！"
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } catch {
                        isRestoring = false
                        actionMessage = "恢复本地数据失败：\(error.localizedDescription)"
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                    }
                }
            } catch {
                await MainActor.run {
                    isRestoring = false
                    actionMessage = "下载云端备份失败：\(error.localizedDescription)"
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func deleteRemoteBackup(_ item: WebDAVRemoteItem) {
        Task {
            do {
                try await WebDAVSyncService.shared.deleteBackup(
                    filename: item.filename,
                    config: currentConfig
                )
                await MainActor.run {
                    remoteBackups.removeAll(where: { $0.id == item.id })
                    actionMessage = "已删除云端备份 \(item.filename)"
                }
            } catch {
                await MainActor.run {
                    actionMessage = "删除失败：\(error.localizedDescription)"
                }
            }
        }
    }
}
