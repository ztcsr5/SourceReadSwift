import SwiftUI
import Network
import Foundation
import UIKit
#if canImport(Darwin)
import Darwin
#endif

struct SourceWritingView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var server: LightweightHTTPServer
    @State private var importStatus: String?
    @State private var importError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppLayout.sectionGap) {
                serverControlCard
                statusMessagesSection
                logMessagesSection
                instructionsSection
            }
            .padding(AppTheme.pagePadding)
        }
        .pageBackground()
        .navigationTitle("Web 写源与传输")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true

            server.onJSONReceived = { jsonText in
                do {
                    let report = try appState.sourceStore.importJSON(jsonText)
                    let msg = "成功导入书源：\(report.userMessage)"
                    DispatchQueue.main.async {
                        self.importStatus = msg
                        self.importError = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            if self.importStatus == msg {
                                self.importStatus = nil
                            }
                        }
                    }
                    return .success(msg)
                } catch {
                    let errMsg = error.localizedDescription
                    DispatchQueue.main.async {
                        self.importError = "导入失败：\(errMsg)"
                        self.importStatus = nil
                    }
                    return .failure(error)
                }
            }
            server.sourceStore = appState.sourceStore
            server.bind(engine: appState.engine, healthStore: appState.sourceHealthStore)
            server.start()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    @ViewBuilder
    private var serverControlCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "globe")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(server.isRunning ? .green : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Web 写源服务")
                        .font(.title2.bold())
                    if server.isRunning {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("局域网服务运行中 · 屏幕常亮保护中")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { server.isRunning || server.isStarting },
                    set: { newValue in
                        if newValue {
                            server.start()
                        } else {
                            server.stop()
                        }
                    }
                ))
                .toggleStyle(SwitchToggleStyle(tint: AppTheme.accent))
                .labelsHidden()
            }

            Text(server.isRunning
                 ? "服务已启动！请保持手机在此页面（已自动常亮防休眠），在同一 Wi-Fi 下的电脑浏览器输入下方地址："
                 : "服务已停止。开启服务后，可在局域网内的电脑浏览器上直接编写、调试、格式化并一键推送到手机。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if server.isRunning {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(server.localURLs, id: \.self) { url in
                        HStack {
                            Text(url)
                                .font(.system(.callout, design: .monospaced))
                                .fontWeight(.semibold)
                                .foregroundStyle(AppTheme.accent)
                                .textSelection(.enabled)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = url
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("本次配对密钥")
                        .font(.caption.weight(.semibold))
                    Text(server.pairingToken)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                    Button {
                        UIPasteboard.general.string = server.pairingToken
                    } label: {
                        Label("复制配对密钥", systemImage: "key")
                    }
                    .buttonStyle(.bordered)
                    Text("网页输入此密钥后才能读取或修改源库。重启服务后失效。请使用可信 Wi-Fi；HTTP 不提供传输加密。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = server.localURLs.joined(separator: "\n")
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Label("复制访问地址", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        server.refreshAddresses()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Label("刷新地址", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    UIPasteboard.general.string = server.healthURLs.joined(separator: "\n")
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label("复制健康检查地址 (/health)", systemImage: "stethoscope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Text(server.localURLs.allSatisfy { $0.contains("127.0.0.1") }
                     ? "⚠️ 当前只发现本机回环地址，电脑无法通过 Wi‑Fi 访问。请让手机连接 Wi‑Fi，并在系统设置中允许本应用使用‘本地网络’。"
                     : "💡 PC 无法打开时，先访问任一 /health 地址；返回 SOURCE_READ_SWIFT_WEB_OK 即表示局域网连通。请确认手机已允许‘本地网络’权限，且路由器未开启 AP 隔离。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let lastError = server.lastError {
                Text(lastError)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
        .padding(AppLayout.cardInset)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var statusMessagesSection: some View {
        if let importStatus {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(importStatus)
                    .font(.subheadline)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }

        if let importError {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(importError)
                    .font(.subheadline)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var logMessagesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("运行日志")
                    .font(.headline)
                Spacer()
                if !server.logMessages.isEmpty {
                    Button("清空") {
                        server.clearLogs()
                    }
                    .font(.caption)
                }
            }

            if server.logMessages.isEmpty {
                Text("暂无日志，等待电脑连接...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .center)
                    .background(Color(.secondarySystemBackground).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(server.logMessages.prefix(15), id: \.self) { log in
                        Text(log)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    UIPasteboard.general.string = server.logMessages.joined(separator: "\n")
                } label: {
                    Label("复制全部日志", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("使用指引")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                Label("确保 iPhone 和电脑连接在同一个 Wi-Fi 或连接手机个人热点。", systemImage: "wifi")
                Label("打开电脑浏览器（Chrome/Edge/Safari），输入上方显示的地址。", systemImage: "macbook.and.iphone")
                Label("在网页中可直接填入标准模板、格式化校验 JSON、导出手机已有书源或推送新源。", systemImage: "square.and.arrow.down")
                Label("当前页面已开启常亮保护，请勿手动锁屏以保证服务持续响应。", systemImage: "sun.max")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - HTTP Server Implementation

final class LightweightHTTPServer: ObservableObject {
    @Published var isRunning = false
    @Published var isStarting = false
    @Published private(set) var pairingToken = ""
    private let access = LANWorkbenchAccess()
    @Published var port: UInt16 = 8080
    @Published var localIP: String = "127.0.0.1"
    @Published var localURLs: [String] = []
    var healthURLs: [String] {
        localURLs.map { $0 + "/health" }
    }
    @Published var lastError: String?
    @Published var logMessages: [String] = []

    /// Main-actor store reference used by the LAN editor API.
    var sourceStore: SourceStore?
    var engine: SourceEngine?
    var sourceHealthStore: SourceHealthStore?

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let lockQueue = DispatchQueue(label: "com.sourceread.server.lock")
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    var onJSONReceived: ((String) -> Result<String, Error>)?

    init(sourceStore: SourceStore? = nil, engine: SourceEngine? = nil, sourceHealthStore: SourceHealthStore? = nil) {
        self.sourceStore = sourceStore
        self.engine = engine
        self.sourceHealthStore = sourceHealthStore
        self.localIP = getLocalIPAddresses().first ?? "127.0.0.1"
        registerBackgroundKeepalive()
    }

    func bind(engine: SourceEngine, healthStore: SourceHealthStore) {
        self.engine = engine
        self.sourceHealthStore = healthStore
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        endBackgroundTask()
    }

    private func registerBackgroundKeepalive() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func handleDidEnterBackground() {
        guard isRunning else { return }
        beginBackgroundTask()
    }

    @objc private func handleWillEnterForeground() {
        endBackgroundTask()
    }

    private func beginBackgroundTask() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "LightweightHTTPServerKeepalive") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    func clearLogs() {
        DispatchQueue.main.async {
            self.logMessages.removeAll()
        }
    }

    func refreshAddresses() {
        let addresses = getLocalIPAddresses()
        self.localIP = addresses.first ?? "127.0.0.1"
        let activePort = self.port
        let resolved = addresses.isEmpty ? ["127.0.0.1"] : addresses
        self.localURLs = resolved.map { "http://\($0):\(activePort)" }
    }

    func start() {
        guard !isRunning && !isStarting else { return }
        pairingToken = access.renew()
        isStarting = true
        lastError = nil
        logMessages.removeAll()

        let candidatePorts: [UInt16] = [8080, 8081, 8888, 9090, 8000, 8088]
        startOnFirstAvailablePort(candidates: candidatePorts, index: 0)
    }

    private func startOnFirstAvailablePort(candidates: [UInt16], index: Int) {
        guard index < candidates.count else {
            DispatchQueue.main.async {
                self.isStarting = false
                self.isRunning = false
                self.lastError = "未能启动 HTTP 服务：尝试了端口 \(candidates.map { String($0) }.joined(separator: ", ")) 均被占用或不可用。"
                self.log("所有候选端口均启动失败")
            }
            return
        }

        let targetPort = candidates[index]
        log("尝试启动服务于端口 \(targetPort)...")

        do {
            guard let nwPort = NWEndpoint.Port(rawValue: targetPort) else {
                startOnFirstAvailablePort(candidates: candidates, index: index + 1)
                return
            }

            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: nwPort)

            listener.stateUpdateHandler = { [weak self, weak listener] newState in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    switch newState {
                    case .ready:
                        self.listener = listener
                        self.port = targetPort
                        self.isRunning = true
                        self.isStarting = false
                        self.refreshAddresses()
                        self.log("服务已启动！监听端口: \(targetPort)")
                        self.log("可访问地址:\n" + self.localURLs.map { "  - " + $0 }.joined(separator: "\n"))
                    case .failed(let error):
                        self.log("端口 \(targetPort) 失败: \(error.localizedDescription)")
                        listener?.cancel()
                        if self.isStarting {
                            self.startOnFirstAvailablePort(candidates: candidates, index: index + 1)
                        } else {
                            self.isRunning = false
                            self.lastError = "服务运行出错: \(error.localizedDescription)"
                        }
                    case .cancelled:
                        self.isRunning = false
                        self.isStarting = false
                    default:
                        break
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }

            listener.start(queue: DispatchQueue.global(qos: .userInitiated))
        } catch {
            log("端口 \(targetPort) 创建监听异常: \(error.localizedDescription)")
            startOnFirstAvailablePort(candidates: candidates, index: index + 1)
        }
    }

    func stop() {
        access.revoke()
        pairingToken = ""
        lockQueue.sync {
            for conn in connections {
                conn.cancel()
            }
            connections.removeAll()
        }
        listener?.cancel()
        listener = nil
        isRunning = false
        isStarting = false
        localURLs = []
        endBackgroundTask()
        log("服务已停止")
    }

    private func log(_ msg: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] \(msg)"
        DispatchQueue.main.async {
            self.logMessages.append(line)
            if self.logMessages.count > 100 {
                self.logMessages.removeFirst(self.logMessages.count - 100)
            }
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        lockQueue.async {
            self.connections.append(connection)
        }
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            switch state {
            case .failed, .cancelled:
                self?.lockQueue.async {
                    if let index = self?.connections.firstIndex(where: { $0 === connection }) {
                        self?.connections.remove(at: index)
                    }
                }
            default:
                break
            }
        }
        connection.start(queue: DispatchQueue.global(qos: .default))
        receiveRequest(on: connection, accumulated: Data())
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            if let error = error {
                self.log("连接读取错误: \(error)")
                connection.cancel()
                return
            }

            guard let data = data, !data.isEmpty else {
                if isComplete {
                    connection.cancel()
                } else {
                    self.receiveRequest(on: connection, accumulated: accumulated)
                }
                return
            }

            var buffer = accumulated
            buffer.append(data)
            if buffer.count > LightweightHTTPParser.maximumHeaderBytes + LightweightHTTPParser.maximumBodyBytes {
                self.sendResponse(connection: connection, statusCode: 413, statusText: "Payload Too Large", contentType: "text/plain; charset=utf-8", body: "Payload too large")
                return
            }
            switch LightweightHTTPParser.parse(buffer) {
            case .incomplete:
                self.receiveRequest(on: connection, accumulated: buffer)
            case .complete(let request):
                self.handleHttpRequest(request, connection: connection)
            case .failure(let statusCode, let message):
                self.sendResponse(connection: connection, statusCode: statusCode, statusText: Self.statusText(for: statusCode), contentType: "text/plain; charset=utf-8", body: message)
            }
        }
    }

    private static func statusText(for statusCode: Int) -> String {
        switch statusCode {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 413: return "Payload Too Large"
        case 431: return "Request Header Fields Too Large"
        case 500: return "Internal Server Error"
        case 501: return "Not Implemented"
        default: return "Error"
        }
    }

    private func handleHttpRequest(_ request: LightweightHTTPRequest, connection: NWConnection) {
        let method = request.method
        let path = request.path
        let keepAlive = request.headers["connection"]?.lowercased() != "close"
        log("HTTP 请求: \(method) \(path)")
        if path.hasPrefix("/api/") || path == "/import" {
            guard access.permits(request) else {
                sendResponse(connection: connection, statusCode: 401, statusText: "Unauthorized",
                             contentType: "application/json; charset=utf-8",
                             body: #"{"ok":false,"error":"Pairing required"}"#, keepAlive: false)
                return
            }
        }

        if method == "OPTIONS" {
            sendResponse(connection: connection, statusCode: 204, statusText: "No Content", contentType: "text/plain; charset=utf-8", body: "", keepAlive: keepAlive)
        } else if method == "GET" && (path == "/" || path == "/index.html" || path.isEmpty) {
            let html = getWebPageHtml()
            sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "text/html; charset=utf-8", body: html, keepAlive: keepAlive)
        } else if (method == "GET" || method == "HEAD") && path == "/health" {
            let healthBody = "SOURCE_READ_SWIFT_WEB_OK\nREAD_SOURCE_WEB_OK port=\(port)"
            sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "text/plain; charset=utf-8", body: healthBody, includeBody: method != "HEAD", keepAlive: keepAlive)
        } else if (method == "GET" || method == "HEAD") && path == "/favicon.ico" {
            sendResponse(connection: connection, statusCode: 204, statusText: "No Content", contentType: "image/x-icon", body: "", includeBody: false, keepAlive: keepAlive)
        } else if method == "GET" && path == "/api/status" {
            respondWithSourceStore(connection: connection) { store in
                let count = store?.sources.count ?? 0
                let enabledCount = store?.sources.filter(\.enabled).count ?? 0
                let body = #"{"ok":true,"service":"source-writing","port":\#(self.port),"sourceCount":\#(count),"enabledSourceCount":\#(enabledCount)}"#
                self.sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "application/json; charset=utf-8", body: body, keepAlive: keepAlive)
            }
        } else if method == "GET" && path == "/api/sources" {
            respondWithSourceStore(connection: connection) { store in
                let sources = store?.sources ?? []
                self.sendJSON(connection: connection, value: WebSourceListResponse(
                    ok: true,
                    total: sources.count,
                    enabledCount: sources.filter(\.enabled).count,
                    data: sources
                ), keepAlive: keepAlive)
            }
        } else if method == "GET" && path == "/api/source" {
            let components = URLComponents(string: "http://local/?" + (request.query ?? ""))
            let sourceURL = components?.queryItems?.first { $0.name == "url" }?.value
            respondWithSourceStore(connection: connection) { store in
                guard let sourceURL, let source = store?.sources.first(where: { $0.bookSourceUrl == sourceURL }) else {
                    self.sendResponse(connection: connection, statusCode: 404, statusText: "Not Found",
                                      contentType: "application/json; charset=utf-8",
                                      body: #"{"ok":false,"error":"Source not found"}"#, keepAlive: keepAlive)
                    return
                }
                self.sendJSON(connection: connection, value: WebSingleSourceResponse(ok: true, data: source), keepAlive: keepAlive)
            }
        } else if method == "GET" && path == "/api/sources/health" {
            handleSourcesHealth(connection: connection, keepAlive: keepAlive)
        } else if method == "GET" && path == "/api/sources/export" {
            respondWithSourceStore(connection: connection) { store in
                let snapshot = store?.backupSnapshot() ?? SourceLibrarySnapshot()
                self.sendJSON(connection: connection, value: snapshot, keepAlive: keepAlive)
            }
        } else if method == "POST" && (path == "/api/sources/import" || path == "/import") {
            guard let body = String(data: request.body, encoding: .utf8) else {
                sendResponse(connection: connection, statusCode: 400, statusText: "Bad Request", contentType: "application/json; charset=utf-8", body: #"{"ok":false,"error":"Request body must be UTF-8 JSON"}"#, keepAlive: keepAlive)
                return
            }
            importSourceJSON(body.trimmingCharacters(in: .whitespacesAndNewlines), connection: connection, keepAlive: keepAlive)
        } else if method == "POST" && path == "/api/source/debug" {
            handleSourceDebug(request: request, connection: connection, keepAlive: keepAlive)
        } else if method == "POST" && path == "/api/sources/save" {
            handleSourceSave(request: request, connection: connection, keepAlive: keepAlive)
        } else if method == "POST" && path == "/api/sources/delete" {
            handleSourceDelete(request: request, connection: connection, keepAlive: keepAlive)
        } else if method == "POST" && path == "/api/sources/toggle" {
            handleSourceToggle(request: request, connection: connection, keepAlive: keepAlive)
        } else {
            sendResponse(connection: connection, statusCode: 404, statusText: "Not Found", contentType: "text/plain; charset=utf-8", body: "Not Found", keepAlive: keepAlive)
        }
    }

    private func importSourceJSON(_ text: String, connection: NWConnection? = nil, keepAlive: Bool = true) {
        guard let onJSONReceived else {
            if let connection { sendResponse(connection: connection, statusCode: 500, statusText: "Internal Error", contentType: "text/plain; charset=utf-8", body: "No import handler registered", keepAlive: keepAlive) }
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let result = onJSONReceived(text)
            guard let connection else { return }
            switch result {
            case .success(let message):
                self.log("导入成功: \(message)")
                self.sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "application/json; charset=utf-8", body: #"{"ok":true,"message":"\#(self.jsonEscape(message))"}"#, keepAlive: keepAlive)
            case .failure(let error):
                self.log("导入失败: \(error.localizedDescription)")
                self.sendResponse(connection: connection, statusCode: 400, statusText: "Bad Request", contentType: "application/json; charset=utf-8", body: #"{"ok":false,"error":"\#(self.jsonEscape(error.localizedDescription))"}"#, keepAlive: keepAlive)
            }
        }
    }

    private func handleSourcesHealth(connection: NWConnection, keepAlive: Bool) {
        respondWithSourceStore(connection: connection) { store in
            let sources = store?.sources ?? []
            let healthRecords = self.sourceHealthStore?.records ?? [:]

            struct SourceHealthDTO: Codable {
                var id: String
                var name: String
                var url: String
                var group: String?
                var enabled: Bool
                var weight: Int
                var healthStatus: String
                var healthMessage: String
                var resultCount: Int
                var testedAt: Double?
            }

            let dtos = sources.map { s in
                let rec = healthRecords[s.bookSourceUrl]
                return SourceHealthDTO(
                    id: s.id,
                    name: s.bookSourceName,
                    url: s.bookSourceUrl,
                    group: s.bookSourceGroup,
                    enabled: s.enabled,
                    weight: s.weight,
                    healthStatus: rec?.status.rawValue ?? "untested",
                    healthMessage: rec?.message ?? "未检测",
                    resultCount: rec?.resultCount ?? 0,
                    testedAt: rec?.testedAt.timeIntervalSince1970
                )
            }

            struct HealthListResponse: Codable {
                var ok: Bool
                var total: Int
                var items: [SourceHealthDTO]
            }

            self.sendJSON(connection: connection, value: HealthListResponse(ok: true, total: dtos.count, items: dtos), keepAlive: keepAlive)
        }
    }

    private func handleSourceSave(request: LightweightHTTPRequest, connection: NWConnection, keepAlive: Bool) {
        respondWithSourceStore(connection: connection) { store in
            guard let store else {
                self.sendResponse(connection: connection, statusCode: 500, statusText: "Internal Error", contentType: "application/json", body: #"{"ok":false,"error":"Store not available"}"#, keepAlive: keepAlive)
                return
            }
            do {
                let report = try store.importJSONData(request.body)
                self.sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "application/json", body: #"{"ok":true,"message":"\#(self.jsonEscape(report.userMessage))"}"#, keepAlive: keepAlive)
            } catch {
                self.sendResponse(connection: connection, statusCode: 400, statusText: "Bad Request", contentType: "application/json", body: #"{"ok":false,"error":"\#(self.jsonEscape(error.localizedDescription))"}"#, keepAlive: keepAlive)
            }
        }
    }

    private func handleSourceDelete(request: LightweightHTTPRequest, connection: NWConnection, keepAlive: Bool) {
        respondWithSourceStore(connection: connection) { store in
            guard let store else { return }
            struct DeleteReq: Codable { var url: String }
            guard let req = try? JSONDecoder().decode(DeleteReq.self, from: request.body) else {
                self.sendResponse(connection: connection, statusCode: 400, statusText: "Bad Request", contentType: "application/json", body: #"{"ok":false,"error":"Invalid JSON"}"#, keepAlive: keepAlive)
                return
            }
            store.remove(sourceURLs: [req.url])
            self.sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "application/json", body: #"{"ok":true}"#, keepAlive: keepAlive)
        }
    }

    private func handleSourceToggle(request: LightweightHTTPRequest, connection: NWConnection, keepAlive: Bool) {
        respondWithSourceStore(connection: connection) { store in
            guard let store else { return }
            struct ToggleReq: Codable { var url: String; var enabled: Bool }
            guard let req = try? JSONDecoder().decode(ToggleReq.self, from: request.body) else {
                self.sendResponse(connection: connection, statusCode: 400, statusText: "Bad Request", contentType: "application/json", body: #"{"ok":false,"error":"Invalid JSON"}"#, keepAlive: keepAlive)
                return
            }
            store.setEnabled(req.enabled, for: [req.url])
            self.sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "application/json", body: #"{"ok":true}"#, keepAlive: keepAlive)
        }
    }

    private func handleSourceDebug(request: LightweightHTTPRequest, connection: NWConnection, keepAlive: Bool) {
        guard let engine = self.engine else {
            sendResponse(connection: connection, statusCode: 500, statusText: "Internal Error", contentType: "application/json; charset=utf-8", body: #"{"ok":false,"error":"引擎尚未就绪"}"#, keepAlive: keepAlive)
            return
        }

        struct DebugPayload: Codable {
            var source: BookSource?
            var keyword: String?
            var step: String?
            var bookUrl: String?
            var chapterUrl: String?
            var exploreUrl: String?
        }

        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(DebugPayload.self, from: request.body),
              let source = payload.source else {
            sendResponse(connection: connection, statusCode: 400, statusText: "Bad Request", contentType: "application/json; charset=utf-8", body: #"{"ok":false,"error":"缺少书源数据 (source JSON)"}"#, keepAlive: keepAlive)
            return
        }

        let keyword = (payload.keyword?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? payload.keyword! : "剑来"
        let step = payload.step ?? "all"

        Task {
            var logs: [String] = []
            func logStep(_ msg: String) {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss.SSS"
                logs.append("[\(formatter.string(from: Date()))] \(msg)")
            }

            logStep("🚀 开始调试书源 [\(source.bookSourceName)]，执行环节: \(step)")
            let totalStart = CFAbsoluteTimeGetCurrent()

            var searchResult: [SearchBook]? = nil
            var exploreResult: [SearchBook]? = nil
            var detailResult: BookDetail? = nil
            var chapterListResult: [BookChapter]? = nil
            var contentResult: ChapterContent? = nil
            var errorMessage: String? = nil

            // 0. Explore step (发现页): doubles as the only probe for sources
            // that ship no searchUrl, matching Legado's explore-only sources.
            let searchURLText = (source.searchUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let exploreURLText = (payload.exploreUrl ?? source.exploreUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let exploreOnly = searchURLText.isEmpty && !exploreURLText.isEmpty
            if step == "explore" || (step == "all" && exploreOnly) {
                let categories = ExploreCategoryParser.parse(exploreUrl: exploreURLText, source: source)
                if let first = categories.first {
                    logStep("🧭 发起发现页测试: '\(first.title)' -> \(first.url)...")
                    let eStart = CFAbsoluteTimeGetCurrent()
                    let eRes = await engine.exploreBooks(source: source, url: first.url, page: 1)
                    let eDuration = Int((CFAbsoluteTimeGetCurrent() - eStart) * 1000)
                    switch eRes {
                    case .success(let books):
                        exploreResult = books
                        logStep("✅ 发现页解析成功 (耗时 \(eDuration)ms)，返回 \(books.count) 条")
                        if books.isEmpty {
                            if step == "explore" { errorMessage = "发现页返回 0 条" }
                        } else if searchResult == nil {
                            searchResult = books
                        }
                    case .failure(let error):
                        errorMessage = "发现页失败: \(error.localizedDescription)"
                        logStep("❌ 发现页解析失败 (耗时 \(eDuration)ms): \(error.localizedDescription)")
                    }
                } else if step == "explore" {
                    errorMessage = "发现页分类为空（exploreUrl 无法解析出分类）"
                    logStep("❌ exploreUrl 无法解析出分类（\(exploreURLText.count) 字符）")
                } else {
                    logStep("⚠️ exploreUrl 存在但解析不出分类，跳过发现页")
                }
            }

            // 1. Search step
            if (step == "search" || step == "all") && !(step == "all" && exploreOnly) {
                logStep("🔍 发起搜索测试: keyword='\(keyword)', URL='\(source.searchUrl ?? "空")'...")
                let sStart = CFAbsoluteTimeGetCurrent()
                let sRes = await engine.searchBooks(source: source, keyword: keyword, page: 1)
                let sDuration = Int((CFAbsoluteTimeGetCurrent() - sStart) * 1000)
                switch sRes {
                case .success(let books):
                    searchResult = books
                    logStep("✅ 搜索成功 (耗时 \(sDuration)ms)，解析到 \(books.count) 条结果")
                    if books.isEmpty {
                        logStep("⚠️ 提示: 搜索结果为空，请检查 ruleSearch.bookList 或搜索 URL 编码")
                    } else {
                        for (idx, b) in books.prefix(3).enumerated() {
                            logStep("   #\(idx + 1) [\(b.name)] 作者: \(b.author ?? "未知") -> \(b.bookUrl)")
                        }
                    }
                case .failure(let error):
                    errorMessage = "搜索失败: \(error.localizedDescription)"
                    logStep("❌ 搜索失败 (耗时 \(sDuration)ms): \(error.localizedDescription)")
                }
            }

            // 2. Detail step
            if (step == "detail" || (step == "all" && searchResult?.isEmpty == false)) && errorMessage == nil {
                let targetBook: SearchBook
                if let first = searchResult?.first {
                    targetBook = first
                } else if let bUrl = payload.bookUrl, !bUrl.isEmpty {
                    targetBook = SearchBook(name: "测试书籍", author: "测试作者", coverUrl: nil, bookUrl: bUrl, sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl, intro: nil, kind: nil, lastChapter: nil, wordCount: nil, checkKeyWord: nil)
                } else {
                    targetBook = SearchBook(name: "测试书籍", author: nil, coverUrl: nil, bookUrl: source.bookSourceUrl, sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl, intro: nil, kind: nil, lastChapter: nil, wordCount: nil, checkKeyWord: nil)
                }

                logStep("📖 正在解析详情页: '\(targetBook.name)' (\(targetBook.bookUrl))...")
                let dStart = CFAbsoluteTimeGetCurrent()
                let dRes = await engine.getBookDetail(source: source, book: targetBook)
                let dDuration = Int((CFAbsoluteTimeGetCurrent() - dStart) * 1000)
                switch dRes {
                case .success(let detail):
                    detailResult = detail
                    logStep("✅ 详情页解析成功 (耗时 \(dDuration)ms): 书名='\(detail.name)', 作者='\(detail.author ?? "未知")', 目录URL='\(detail.tocUrl ?? targetBook.bookUrl)'")
                case .failure(let error):
                    if step == "detail" {
                        errorMessage = "详情解析失败: \(error.localizedDescription)"
                    }
                    logStep("❌ 详情页解析失败 (耗时 \(dDuration)ms): \(error.localizedDescription)")
                }
            }

            // 3. TOC step
            if (step == "toc" || (step == "all" && detailResult != nil)) && errorMessage == nil {
                let bookForToc: BookDetail = detailResult ?? BookDetail(name: "测试书籍", author: nil, coverUrl: nil, bookUrl: payload.bookUrl ?? source.bookSourceUrl, tocUrl: payload.bookUrl ?? source.bookSourceUrl, sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl, intro: nil, latestChapter: nil, wordCount: nil, status: nil, updateTime: nil, kind: nil)
                logStep("📑 正在解析目录列表: '\(bookForToc.tocUrl ?? bookForToc.bookUrl)'...")
                let tStart = CFAbsoluteTimeGetCurrent()
                let tRes = await engine.getChapterList(source: source, book: bookForToc, maxPages: 2)
                let tDuration = Int((CFAbsoluteTimeGetCurrent() - tStart) * 1000)
                switch tRes {
                case .success(let chapters):
                    chapterListResult = chapters
                    logStep("✅ 目录解析成功 (耗时 \(tDuration)ms)，解析到 \(chapters.count) 个章节")
                    if let first = chapters.first {
                        logStep("   首章: '\(first.title)' -> \(first.url)")
                    }
                case .failure(let error):
                    if step == "toc" {
                        errorMessage = "目录解析失败: \(error.localizedDescription)"
                    }
                    logStep("❌ 目录解析失败 (耗时 \(tDuration)ms): \(error.localizedDescription)")
                }
            }

            // 4. Content step
            if (step == "content" || (step == "all" && chapterListResult?.isEmpty == false)) && errorMessage == nil {
                let targetChapter: BookChapter
                if let first = chapterListResult?.first {
                    targetChapter = first
                } else if let cUrl = payload.chapterUrl, !cUrl.isEmpty {
                    targetChapter = BookChapter(title: "测试章节", url: cUrl, bookUrl: payload.bookUrl ?? source.bookSourceUrl, index: 0, isVip: false)
                } else {
                    targetChapter = BookChapter(title: "测试章节", url: source.bookSourceUrl, bookUrl: source.bookSourceUrl, index: 0, isVip: false)
                }

                logStep("📄 正在解析正文: '\(targetChapter.title)' (\(targetChapter.url))...")
                let cStart = CFAbsoluteTimeGetCurrent()
                let cRes = await engine.getContent(source: source, chapter: targetChapter, maxPages: 2)
                let cDuration = Int((CFAbsoluteTimeGetCurrent() - cStart) * 1000)
                switch cRes {
                case .success(let content):
                    contentResult = content
                    logStep("✅ 正文解析成功 (耗时 \(cDuration)ms)，提取到 \(content.paragraphs.count) 段文字 (共 \(content.paragraphs.joined().count) 字)")
                case .failure(let error):
                    if step == "content" {
                        errorMessage = "正文解析失败: \(error.localizedDescription)"
                    }
                    logStep("❌ 正文解析失败 (耗时 \(cDuration)ms): \(error.localizedDescription)")
                }
            }

            let totalDuration = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
            logStep("🏁 调试完成，总耗时 \(totalDuration)ms，判定: \(errorMessage == nil ? "通过 (PASS)" : "异常 (FAIL)")")

            // Update health record in sourceHealthStore
            await MainActor.run {
                if let healthStore = self.sourceHealthStore {
                    healthStore.record(
                        source: source,
                        status: errorMessage == nil ? .passed : .failed,
                        message: errorMessage ?? "在线调试通过 (耗时 \(totalDuration)ms)",
                        keyword: keyword,
                        resultCount: searchResult?.count ?? 0
                    )
                }
            }

            struct DebugResponse: Codable {
                var ok: Bool
                var step: String
                var durationMs: Int
                var logs: [String]
                var search: [SearchBook]?
                var explore: [SearchBook]?
                var detail: BookDetail?
                var toc: [BookChapter]?
                var content: ChapterContent?
                var error: String?
            }

            let resp = DebugResponse(
                ok: errorMessage == nil,
                step: step,
                durationMs: totalDuration,
                logs: logs,
                search: searchResult,
                explore: exploreResult,
                detail: detailResult,
                toc: chapterListResult.map { Array($0.prefix(30)) },
                content: contentResult,
                error: errorMessage
            )

            self.sendJSON(connection: connection, value: resp, keepAlive: keepAlive)
        }
    }

    private func respondWithSourceStore(connection: NWConnection, keepAlive: Bool = true, action: @escaping @MainActor (SourceStore?) -> Void) {
        Task { @MainActor in
            action(self.sourceStore)
        }
    }

    private func sendJSON<T: Encodable>(connection: NWConnection, value: T, keepAlive: Bool = true) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        do {
            let data = try encoder.encode(value)
            guard let json = String(data: data, encoding: .utf8) else {
                sendResponse(connection: connection, statusCode: 500, statusText: "Internal Error", contentType: "text/plain; charset=utf-8", body: "JSON encoding failed", keepAlive: keepAlive)
                return
            }
            sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "application/json; charset=utf-8", body: json, keepAlive: keepAlive)
        } catch {
            sendResponse(connection: connection, statusCode: 500, statusText: "Internal Error", contentType: "text/plain; charset=utf-8", body: error.localizedDescription, keepAlive: keepAlive)
        }
    }

    private func sendResponse(
        connection: NWConnection,
        statusCode: Int,
        statusText: String,
        contentType: String,
        body: String,
        includeBody: Bool = true,
        keepAlive: Bool = true
    ) {
        let bodyData = body.data(using: .utf8) ?? Data()
        var header = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(bodyData.count)\r\n"
        header += "Cache-Control: no-store\r\n"
        header += "X-Content-Type-Options: nosniff\r\n"
        header += "Referrer-Policy: no-referrer\r\n"
        header += "Content-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'\r\n"
        // This parser handles one request per connection, not HTTP pipelining.
        // Advertising keep-alive previously left reused browser sockets idle.
        header += "Connection: close\r\n"
        header += "\r\n"

        guard let headerData = header.data(using: .utf8) else {
            connection.cancel()
            return
        }

        var fullData = headerData
        if includeBody {
            fullData.append(bodyData)
        }

        connection.send(content: fullData, completion: .contentProcessed { [weak self, weak connection] error in
            guard let connection = connection else { return }
            if let error = error {
                self?.log("响应发送失败: \(error)")
                connection.cancel()
                return
            }
            connection.cancel()
        })
    }

    private func jsonEscape(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private func getWebPageHtml() -> String { LANWorkbenchDocument.html }

}

private struct WebSourceListResponse: Encodable {
    let ok: Bool
    let total: Int
    let enabledCount: Int
    let data: [BookSource]
}

private func getLocalIPAddresses() -> [String] {
    var primary: [String] = []
    var secondary: [String] = []
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0 else { return [] }
    guard let firstAddr = ifaddr else { return [] }

    for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
        let interface = ptr.pointee
        guard let addr = interface.ifa_addr else { continue }

        let flags = Int32(interface.ifa_flags)
        // Must be active (UP and RUNNING) and NOT loopback
        guard (flags & IFF_UP) == IFF_UP else { continue }
        guard (flags & IFF_RUNNING) == IFF_RUNNING else { continue }
        guard (flags & IFF_LOOPBACK) == 0 else { continue }

        let addrFamily = addr.pointee.sa_family
        if addrFamily == UInt8(AF_INET) {
            let name = String(cString: interface.ifa_name)
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count),
                        nil, socklen_t(0), NI_NUMERICHOST)
            let ip = String(cString: hostname)
            if ip != "127.0.0.1" && !ip.isEmpty {
                // Ignore cellular data (pdp_ip), VPNs (utun), and AirDrop (awdl/llw)
                guard !name.hasPrefix("pdp_ip"),
                      !name.hasPrefix("utun"),
                      !name.hasPrefix("awdl"),
                      !name.hasPrefix("llw"),
                      !name.hasPrefix("ipsec") else { continue }

                // Prioritize standard Wi-Fi (en0, en1) and hotspot/tethering (bridge100, ap0)
                if name.hasPrefix("en") || name.hasPrefix("bridge") || name.hasPrefix("ap") {
                    primary.append(ip)
                } else {
                    secondary.append(ip)
                }
            }
        }
    }
    freeifaddrs(ifaddr)

    // Sort so standard LAN subnets (192.168.x.x, 172.x.x.x, 10.x.x.x) appear first
    func rank(_ ip: String) -> Int {
        if ip.hasPrefix("192.168.") { return 0 }
        if ip.hasPrefix("172.") { return 1 }
        if ip.hasPrefix("10.") { return 2 }
        return 3
    }

    var seen = Set<String>()
    let sortedPrimary = primary.sorted { rank($0) < rank($1) }
    let sortedSecondary = secondary.sorted { rank($0) < rank($1) }
    return (sortedPrimary + sortedSecondary).filter { seen.insert($0).inserted }
}

private struct WebSingleSourceResponse: Encodable {
    let ok: Bool
    let data: BookSource
}
