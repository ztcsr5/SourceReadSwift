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
            VStack(alignment: .leading, spacing: 24) {
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
        .padding(20)
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
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
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
            var detailResult: BookDetail? = nil
            var chapterListResult: [BookChapter]? = nil
            var contentResult: ChapterContent? = nil
            var errorMessage: String? = nil

            // 1. Search step
            if step == "search" || step == "all" {
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
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Access-Control-Allow-Methods: GET, POST, OPTIONS, PUT, DELETE\r\n"
        header += "Access-Control-Allow-Headers: Content-Type, Accept\r\n"
        header += keepAlive ? "Connection: keep-alive\r\n" : "Connection: close\r\n"
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
            if !keepAlive {
                connection.cancel()
            }
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

    private func getWebPageHtml() -> String {
        return #"""
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>SourceRead 书源工作台 · 编写 · 调试 · 管理</title>
  <style>
    :root {
      --bg: #0f172a;
      --card-bg: #1e293b;
      --card-border: #334155;
      --text: #f8fafc;
      --text-muted: #94a3b8;
      --primary: #3b82f6;
      --primary-hover: #2563eb;
      --success: #10b981;
      --warning: #f59e0b;
      --danger: #ef4444;
      --editor-bg: #090d16;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
      background-color: var(--bg);
      color: var(--text);
      line-height: 1.5;
      padding: 20px;
    }
    .container { max-width: 1200px; margin: 0 auto; }
    .header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding-bottom: 16px;
      margin-bottom: 20px;
      border-bottom: 1px solid var(--card-border);
    }
    .header h1 { font-size: 22px; font-weight: 700; display: flex; align-items: center; gap: 10px; }
    .status-badge {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 4px 12px;
      border-radius: 9999px;
      background: rgba(16, 185, 129, 0.15);
      color: #34d399;
      font-size: 13px;
      font-weight: 500;
    }
    .status-dot { width: 8px; height: 8px; border-radius: 50%; background: #10b981; }

    /* Nav Tabs */
    .tabs {
      display: flex;
      gap: 8px;
      margin-bottom: 20px;
      background: var(--card-bg);
      padding: 6px;
      border-radius: 12px;
      border: 1px solid var(--card-border);
    }
    .tab-btn {
      flex: 1;
      padding: 10px 16px;
      border: none;
      background: transparent;
      color: var(--text-muted);
      font-size: 14px;
      font-weight: 600;
      border-radius: 8px;
      cursor: pointer;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      transition: all 0.2s ease;
    }
    .tab-btn:hover { color: var(--text); background: rgba(255, 255, 255, 0.05); }
    .tab-btn.active { color: #fff; background: var(--primary); }

    .tab-pane { display: none; }
    .tab-pane.active { display: block; }

    /* Cards */
    .card {
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 12px;
      padding: 20px;
      margin-bottom: 20px;
    }
    .card-title {
      font-size: 16px;
      font-weight: 600;
      margin-bottom: 12px;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }

    /* Buttons */
    .btn {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 8px 16px;
      border-radius: 8px;
      font-size: 13px;
      font-weight: 600;
      border: none;
      cursor: pointer;
      transition: all 0.2s;
    }
    .btn-primary { background: var(--primary); color: white; }
    .btn-primary:hover { background: var(--primary-hover); }
    .btn-success { background: var(--success); color: white; }
    .btn-success:hover { background: #059669; }
    .btn-danger { background: var(--danger); color: white; }
    .btn-danger:hover { background: #dc2626; }
    .btn-outline { background: transparent; border: 1px solid var(--card-border); color: var(--text); }
    .btn-outline:hover { background: rgba(255, 255, 255, 0.08); }
    .btn:disabled { opacity: 0.5; cursor: not-allowed; }

    /* Inputs */
    .input {
      background: #0f172a;
      border: 1px solid var(--card-border);
      color: var(--text);
      padding: 8px 12px;
      border-radius: 6px;
      font-size: 13px;
    }
    .input:focus { outline: none; border-color: var(--primary); }

    /* Editor */
    .editor-wrapper {
      position: relative;
      border-radius: 8px;
      overflow: hidden;
      border: 1px solid var(--card-border);
      margin-bottom: 16px;
    }
    textarea.code-editor {
      width: 100%;
      height: 480px;
      background: var(--editor-bg);
      color: #38bdf8;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      font-size: 13px;
      line-height: 1.6;
      padding: 16px;
      border: none;
      resize: vertical;
      white-space: pre;
    }
    textarea.code-editor:focus { outline: none; }

    /* Terminal Console */
    .terminal {
      background: #090d16;
      border: 1px solid #1e293b;
      border-radius: 8px;
      padding: 14px;
      font-family: ui-monospace, Menlo, Consolas, monospace;
      font-size: 12px;
      color: #a5f3fc;
      max-height: 280px;
      overflow-y: auto;
      line-height: 1.6;
      margin-bottom: 16px;
    }
    .log-line { display: block; word-break: break-all; }
    .log-success { color: #34d399; }
    .log-error { color: #f87171; }
    .log-warn { color: #fbbf24; }

    /* Table */
    .table-responsive { overflow-x: auto; }
    table { width: 100%; border-collapse: collapse; font-size: 13px; text-align: left; }
    th { padding: 10px 12px; background: rgba(255, 255, 255, 0.03); color: var(--text-muted); border-bottom: 1px solid var(--card-border); font-weight: 600; }
    td { padding: 12px; border-bottom: 1px solid rgba(255, 255, 255, 0.05); vertical-align: middle; }
    tr:hover td { background: rgba(255, 255, 255, 0.02); }

    /* Badges */
    .pill {
      display: inline-block;
      padding: 2px 8px;
      border-radius: 9999px;
      font-size: 11px;
      font-weight: 600;
    }
    .pill-green { background: rgba(16, 185, 129, 0.2); color: #34d399; }
    .pill-yellow { background: rgba(245, 158, 11, 0.2); color: #fbbf24; }
    .pill-red { background: rgba(239, 68, 68, 0.2); color: #f87171; }
    .pill-gray { background: rgba(148, 163, 184, 0.2); color: #94a3b8; }

    /* Result preview grids */
    .result-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
      gap: 12px;
      margin-top: 12px;
    }
    .book-card {
      background: rgba(255, 255, 255, 0.03);
      border: 1px solid var(--card-border);
      border-radius: 8px;
      padding: 12px;
    }
    .book-card h4 { font-size: 14px; margin-bottom: 4px; color: #60a5fa; }
    .book-card p { font-size: 12px; color: var(--text-muted); margin-bottom: 2px; }

    .toast {
      position: fixed;
      bottom: 24px;
      right: 24px;
      padding: 12px 20px;
      border-radius: 8px;
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      color: #fff;
      font-size: 13px;
      box-shadow: 0 10px 25px rgba(0,0,0,0.5);
      display: none;
      z-index: 1000;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div>
        <h1>📖 SourceRead 书源工作台</h1>
        <p style="font-size: 13px; color: var(--text-muted); margin-top: 4px;">编写、调试、体检并一键推送到您的手机端</p>
      </div>
      <div class="status-badge">
        <span class="status-dot"></span>
        <span id="server-status">已连接手机</span>
      </div>
    </div>

    <!-- Navigation Tabs -->
    <div class="tabs">
      <button class="tab-btn active" onclick="switchTab('editor')">✍️ 书源编辑与推送</button>
      <button class="tab-btn" onclick="switchTab('debugger')">🧪 在线实时调试控制台</button>
      <button class="tab-btn" onclick="switchTab('library')">📚 手机源库诊断与管理</button>
    </div>

    <!-- TAB 1: Editor -->
    <div id="tab-editor" class="tab-pane active">
      <div class="card">
        <div class="card-title">
          <span>书源 JSON 代码编辑</span>
          <div style="display: flex; gap: 8px;">
            <button class="btn btn-outline" onclick="loadTemplate()">📋 载入模版</button>
            <button class="btn btn-outline" onclick="formatJSON()">⚡ 格式化</button>
            <button class="btn btn-primary" onclick="pushToPhone()">📲 一键推送到手机</button>
            <button class="btn btn-success" onclick="transferToDebug()">🧪 载入调试控制台 ➡️</button>
          </div>
        </div>
        <div class="editor-wrapper">
          <textarea id="source-code" class="code-editor" placeholder="在此粘贴或编写书源 JSON（支持单个书源对象或书源数组）..."></textarea>
        </div>
      </div>
    </div>

    <!-- TAB 2: Live Debugger -->
    <div id="tab-debugger" class="tab-pane">
      <div class="card">
        <div class="card-title">
          <span>书源测试与运行参数</span>
          <div id="debug-status-pill" class="pill pill-gray">就绪</div>
        </div>
        <div style="display: flex; gap: 12px; align-items: center; flex-wrap: wrap; margin-bottom: 16px;">
          <div>
            <label style="font-size: 12px; color: var(--text-muted); display: block; margin-bottom: 4px;">测试环节:</label>
            <select id="debug-step" class="input" style="width: 170px;">
              <option value="all">⚡ 全流程一键体检</option>
              <option value="search">🔍 仅测试搜索 (Search)</option>
              <option value="detail">📖 仅测试详情 (Detail)</option>
              <option value="toc">📑 仅测试目录 (TOC)</option>
              <option value="content">📄 仅测试正文 (Content)</option>
            </select>
          </div>
          <div>
            <label style="font-size: 12px; color: var(--text-muted); display: block; margin-bottom: 4px;">搜索测试关键词:</label>
            <input type="text" id="debug-keyword" class="input" value="剑来" style="width: 160px;" placeholder="例如: 剑来">
          </div>
          <div style="flex: 1; min-width: 200px;">
            <label style="font-size: 12px; color: var(--text-muted); display: block; margin-bottom: 4px;">指定书籍/章节 URL (可选，留空则自动联动上一环节):</label>
            <input type="text" id="debug-override-url" class="input" style="width: 100%;" placeholder="留空时自动读取搜索返回的第一本书与第一章">
          </div>
          <div style="align-self: flex-end;">
            <button id="btn-run-debug" class="btn btn-success" onclick="runDebug()">▶️ 开始调试</button>
          </div>
        </div>

        <div class="card-title" style="margin-top: 20px;">
          <span>执行日志输出 (Live Logs)</span>
          <span id="debug-duration" style="font-size: 12px; color: var(--text-muted);">耗时: 0ms</span>
        </div>
        <div id="debug-terminal" class="terminal">
          <span class="log-line">点击“开始调试”后，此处将实时展示手机引擎解析各环节的详细日志与耗时...</span>
        </div>

        <!-- Structured Results Accordion/Sections -->
        <div id="debug-results-container" style="display: none; margin-top: 16px;">
          <h3 style="font-size: 15px; margin-bottom: 10px;">📊 解析结果提取面板</h3>
          <div id="debug-search-section" style="margin-bottom: 16px; display: none;">
            <h4 style="font-size: 13px; color: #60a5fa; margin-bottom: 6px;">🔍 搜索结果列表 (共 <span id="debug-search-count">0</span> 本)</h4>
            <div id="debug-search-grid" class="result-grid"></div>
          </div>

          <div id="debug-detail-section" style="margin-bottom: 16px; display: none;">
            <h4 style="font-size: 13px; color: #a78bfa; margin-bottom: 6px;">📖 书籍详情页解析</h4>
            <div id="debug-detail-card" class="book-card" style="background: rgba(167, 139, 250, 0.05);"></div>
          </div>

          <div id="debug-toc-section" style="margin-bottom: 16px; display: none;">
            <h4 style="font-size: 13px; color: #34d399; margin-bottom: 6px;">📑 章节目录解析 (展示前 30 章)</h4>
            <div id="debug-toc-list" style="max-height: 200px; overflow-y: auto; background: #090d16; border: 1px solid var(--card-border); border-radius: 6px; padding: 8px; font-size: 12px;"></div>
          </div>

          <div id="debug-content-section" style="margin-bottom: 16px; display: none;">
            <h4 style="font-size: 13px; color: #fbbf24; margin-bottom: 6px;">📄 正文内容提取预览</h4>
            <div id="debug-content-card" style="background: #090d16; border: 1px solid var(--card-border); border-radius: 6px; padding: 12px; font-size: 13px; max-height: 220px; overflow-y: auto; line-height: 1.8; color: #e2e8f0;"></div>
          </div>
        </div>
      </div>
    </div>

    <!-- TAB 3: Source Library & Diagnostics -->
    <div id="tab-library" class="tab-pane">
      <div class="card">
        <div class="card-title">
          <span>手机已安装书源列表与健康状态</span>
          <div style="display: flex; gap: 8px;">
            <button class="btn btn-outline" onclick="loadSourceHealthList()">🔄 刷新源列表</button>
            <button class="btn btn-outline" onclick="exportBackup()">💾 导出备份</button>
          </div>
        </div>

        <div style="display: flex; gap: 10px; margin-bottom: 16px; flex-wrap: wrap;">
          <input type="text" id="filter-search" class="input" placeholder="按名称/分组/URL 快速过滤..." style="width: 240px;" oninput="applyFilter()">
          <button class="btn btn-outline" style="font-size: 12px;" onclick="setHealthFilter('all')">全部 (<span id="count-all">0</span>)</button>
          <button class="btn btn-outline" style="font-size: 12px;" onclick="setHealthFilter('passed')">🟢 正常 (<span id="count-passed">0</span>)</button>
          <button class="btn btn-outline" style="font-size: 12px;" onclick="setHealthFilter('failed')">🔴 异常/失效 (<span id="count-failed">0</span>)</button>
          <button class="btn btn-outline" style="font-size: 12px;" onclick="setHealthFilter('untested')">⚪ 未测试 (<span id="count-untested">0</span>)</button>
        </div>

        <div class="table-responsive">
          <table>
            <thead>
              <tr>
                <th style="width: 220px;">书源名称</th>
                <th>分组</th>
                <th>根地址</th>
                <th style="width: 140px;">健康状态</th>
                <th style="width: 80px;">启用</th>
                <th style="width: 180px;">快捷操作</th>
              </tr>
            </thead>
            <tbody id="sources-table-body">
              <tr><td colspan="6" style="text-align: center; color: var(--text-muted); padding: 24px;">加载中...</td></tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </div>

  <div id="toast" class="toast"></div>

  <script>
    let allSources = [];
    let currentHealthFilter = 'all';

    function showToast(msg, isError = false) {
      const toast = document.getElementById('toast');
      toast.innerText = msg;
      toast.style.borderColor = isError ? 'var(--danger)' : 'var(--success)';
      toast.style.display = 'block';
      setTimeout(() => { toast.style.display = 'none'; }, 3000);
    }

    function switchTab(tab) {
      document.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
      document.querySelectorAll('.tab-pane').forEach(pane => pane.classList.remove('active'));
      if (tab === 'editor') {
        document.querySelector('.tab-btn:nth-child(1)').classList.add('active');
        document.getElementById('tab-editor').classList.add('active');
      } else if (tab === 'debugger') {
        document.querySelector('.tab-btn:nth-child(2)').classList.add('active');
        document.getElementById('tab-debugger').classList.add('active');
      } else if (tab === 'library') {
        document.querySelector('.tab-btn:nth-child(3)').classList.add('active');
        document.getElementById('tab-library').classList.add('active');
        loadSourceHealthList();
      }
    }

    // TAB 1: Editor operations
    function formatJSON() {
      const editor = document.getElementById('source-code');
      try {
        const val = JSON.parse(editor.value.trim());
        editor.value = JSON.stringify(val, null, 2);
        showToast('JSON 格式化成功');
      } catch (e) {
        showToast('JSON 语法错误: ' + e.message, true);
      }
    }

    function loadTemplate() {
      const template = {
        "bookSourceName": "自定义测试书源",
        "bookSourceUrl": "https://example.com",
        "bookSourceGroup": "自写源",
        "bookSourceType": 0,
        "enabled": true,
        "weight": 90,
        "searchUrl": "https://example.com/search?q={{key}}",
        "ruleSearch": {
          "bookList": ".search-list .item",
          "name": "h3 a@text",
          "author": ".author@text",
          "bookUrl": "h3 a@href",
          "coverUrl": "img@src",
          "lastChapter": ".last-chapter a@text"
        },
        "ruleBookInfo": {
          "name": ".book-info h1@text",
          "author": ".book-info .author@text",
          "coverUrl": ".book-info img@src",
          "intro": "#intro@text",
          "tocUrl": "a:contains(完整目录)@href"
        },
        "ruleToc": {
          "chapterList": "#chapter-list a",
          "chapterName": "@text",
          "chapterUrl": "@href"
        },
        "ruleContent": {
          "content": "#content@html",
          "nextContentUrl": "a:contains(下一页)@href"
        }
      };
      document.getElementById('source-code').value = JSON.stringify(template, null, 2);
      showToast('已填入标准书源模版');
    }

    async function pushToPhone() {
      const text = document.getElementById('source-code').value.trim();
      if (!text) {
        showToast('请先输入书源 JSON', true);
        return;
      }
      try {
        JSON.parse(text);
      } catch (e) {
        showToast('JSON 格式校验失败: ' + e.message, true);
        return;
      }

      try {
        const res = await fetch('/api/sources/import', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: text
        });
        const data = await res.json();
        if (data.ok) {
          showToast('🎉 推送成功: ' + (data.message || '书源已保存'));
        } else {
          showToast('❌ 推送失败: ' + (data.error || '未知错误'), true);
        }
      } catch (e) {
        showToast('请求失败: ' + e.message, true);
      }
    }

    function transferToDebug() {
      const text = document.getElementById('source-code').value.trim();
      if (!text) {
        showToast('请先在编辑器编写或载入书源', true);
        return;
      }
      try {
        JSON.parse(text);
        switchTab('debugger');
        showToast('已载入书源到调试控制台');
      } catch (e) {
        showToast('JSON 格式无效: ' + e.message, true);
      }
    }

    // TAB 2: Live Debugger
    async function runDebug() {
      const code = document.getElementById('source-code').value.trim();
      if (!code) {
        showToast('请先在“书源编辑”中输入待调试的书源代码', true);
        switchTab('editor');
        return;
      }

      let sourceObj;
      try {
        const parsed = JSON.parse(code);
        sourceObj = Array.isArray(parsed) ? parsed[0] : parsed;
      } catch (e) {
        showToast('书源 JSON 解析失败: ' + e.message, true);
        return;
      }

      const step = document.getElementById('debug-step').value;
      const keyword = document.getElementById('debug-keyword').value.trim() || '剑来';
      const overrideUrl = document.getElementById('debug-override-url').value.trim();

      const runBtn = document.getElementById('btn-run-debug');
      const terminal = document.getElementById('debug-terminal');
      const pill = document.getElementById('debug-status-pill');
      const durationLabel = document.getElementById('debug-duration');

      runBtn.disabled = true;
      runBtn.innerText = '⏳ 调试运行中...';
      pill.className = 'pill pill-yellow';
      pill.innerText = '运行中';
      terminal.innerHTML = '<span class="log-line">🚀 正在将书源发送至手机端引擎执行实时解析...</span>';

      // Hide results container initially
      document.getElementById('debug-results-container').style.display = 'none';

      try {
        const payload = {
          source: sourceObj,
          keyword: keyword,
          step: step,
          bookUrl: overrideUrl,
          chapterUrl: overrideUrl
        };

        const res = await fetch('/api/source/debug', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });

        const data = await res.json();
        durationLabel.innerText = '耗时: ' + (data.durationMs || 0) + 'ms';

        if (data.logs && data.logs.length > 0) {
          terminal.innerHTML = data.logs.map(line => {
            let cls = 'log-line';
            if (line.includes('✅') || line.includes('成功')) cls += ' log-success';
            if (line.includes('❌') || line.includes('失败') || line.includes('异常')) cls += ' log-error';
            if (line.includes('⚠️')) cls += ' log-warn';
            return `<span class="${cls}">${escapeHtml(line)}</span>`;
          }).join('');
        }

        if (data.ok) {
          pill.className = 'pill pill-green';
          pill.innerText = '通过 (PASS)';
          showToast('✅ 调试完成：书源各环节解析正常');
        } else {
          pill.className = 'pill pill-red';
          pill.innerText = '异常 (FAIL)';
          showToast('❌ 调试提示异常: ' + (data.error || '解析失败'), true);
        }

        renderDebugResults(data);

      } catch (e) {
        terminal.innerHTML += `<span class="log-line log-error">❌ 请求异常: ${escapeHtml(e.message)}</span>`;
        pill.className = 'pill pill-red';
        pill.innerText = '请求失败';
        showToast('调试连接出错: ' + e.message, true);
      } finally {
        runBtn.disabled = false;
        runBtn.innerText = '▶️ 开始调试';
      }
    }

    function renderDebugResults(data) {
      const container = document.getElementById('debug-results-container');
      const searchSec = document.getElementById('debug-search-section');
      const detailSec = document.getElementById('debug-detail-section');
      const tocSec = document.getElementById('debug-toc-section');
      const contentSec = document.getElementById('debug-content-section');

      let hasResults = false;

      // 1. Search
      if (data.search && data.search.length > 0) {
        hasResults = true;
        searchSec.style.display = 'block';
        document.getElementById('debug-search-count').innerText = data.search.length;
        const grid = document.getElementById('debug-search-grid');
        grid.innerHTML = data.search.slice(0, 8).map(b => `
          <div class="book-card">
            <h4>${escapeHtml(b.name)}</h4>
            <p>作者: ${escapeHtml(b.author || '未知')}</p>
            <p style="word-break: break-all;">链接: <a href="${escapeHtml(b.bookUrl)}" target="_blank" style="color: #60a5fa;">${escapeHtml(b.bookUrl)}</a></p>
            <p>最新: ${escapeHtml(b.latestChapter || '无')}</p>
          </div>
        `).join('');
      } else {
        searchSec.style.display = 'none';
      }

      // 2. Detail
      if (data.detail) {
        hasResults = true;
        detailSec.style.display = 'block';
        const d = data.detail;
        document.getElementById('debug-detail-card').innerHTML = `
          <h4 style="color: #c084fc; font-size: 15px;">${escapeHtml(d.name)}</h4>
          <p>作者: ${escapeHtml(d.author || '未知')} · 状态: ${escapeHtml(d.status || '连载')}</p>
          <p>目录地址: <a href="${escapeHtml(d.tocUrl || d.bookUrl)}" target="_blank" style="color: #c084fc;">${escapeHtml(d.tocUrl || d.bookUrl)}</a></p>
          <p style="margin-top: 6px; color: #cbd5e1;">简介: ${escapeHtml(d.intro || '无简介')}</p>
        `;
      } else {
        detailSec.style.display = 'none';
      }

      // 3. TOC
      if (data.toc && data.toc.length > 0) {
        hasResults = true;
        tocSec.style.display = 'block';
        const list = document.getElementById('debug-toc-list');
        list.innerHTML = data.toc.map((c, i) => `
          <div style="padding: 3px 0; border-bottom: 1px solid rgba(255,255,255,0.04); display: flex; justify-content: space-between;">
            <span>#${i+1} ${escapeHtml(c.title)}</span>
            <span style="color: var(--text-muted); font-size: 11px;">${escapeHtml(c.url)}</span>
          </div>
        `).join('');
      } else {
        tocSec.style.display = 'none';
      }

      // 4. Content
      if (data.content && data.content.paragraphs && data.content.paragraphs.length > 0) {
        hasResults = true;
        contentSec.style.display = 'block';
        const card = document.getElementById('debug-content-card');
        const paras = data.content.paragraphs.slice(0, 10).map(p => `<p style="margin-bottom: 8px;">　　${escapeHtml(p)}</p>`).join('');
        card.innerHTML = `
          <div style="margin-bottom: 8px; font-weight: 600; color: #fbbf24;">${escapeHtml(data.content.title)}</div>
          <div>${paras}</div>
        `;
      } else {
        contentSec.style.display = 'none';
      }

      container.style.display = hasResults ? 'block' : 'none';
    }

    // TAB 3: Library & Diagnostics
    async function loadSourceHealthList() {
      const tbody = document.getElementById('sources-table-body');
      tbody.innerHTML = '<tr><td colspan="6" style="text-align: center; color: var(--text-muted); padding: 24px;">正在读取手机书源与健康诊断...</td></tr>';

      try {
        const res = await fetch('/api/sources/health', { cache: 'no-store' });
        const data = await res.json();
        allSources = data.items || [];
        updateCounts();
        applyFilter();
      } catch (e) {
        tbody.innerHTML = `<tr><td colspan="6" style="text-align: center; color: var(--danger); padding: 24px;">加载失败: ${escapeHtml(e.message)}</td></tr>`;
      }
    }

    function updateCounts() {
      document.getElementById('count-all').innerText = allSources.length;
      document.getElementById('count-passed').innerText = allSources.filter(s => s.healthStatus === 'passed').length;
      document.getElementById('count-failed').innerText = allSources.filter(s => s.healthStatus === 'failed' || s.healthStatus === 'blocked').length;
      document.getElementById('count-untested').innerText = allSources.filter(s => s.healthStatus === 'untested').length;
    }

    function setHealthFilter(filter) {
      currentHealthFilter = filter;
      applyFilter();
    }

    function applyFilter() {
      const query = (document.getElementById('filter-search').value || '').trim().toLowerCase();
      const filtered = allSources.filter(s => {
        const matchesQuery = !query ||
          s.name.toLowerCase().includes(query) ||
          (s.group && s.group.toLowerCase().includes(query)) ||
          s.url.toLowerCase().includes(query);

        if (!matchesQuery) return false;

        if (currentHealthFilter === 'all') return true;
        if (currentHealthFilter === 'passed') return s.healthStatus === 'passed';
        if (currentHealthFilter === 'failed') return s.healthStatus === 'failed' || s.healthStatus === 'blocked';
        if (currentHealthFilter === 'untested') return s.healthStatus === 'untested';
        return true;
      });

      renderSourcesTable(filtered);
    }

    function renderSourcesTable(sources) {
      const tbody = document.getElementById('sources-table-body');
      if (sources.length === 0) {
        tbody.innerHTML = '<tr><td colspan="6" style="text-align: center; color: var(--text-muted); padding: 24px;">没有符合条件的书源</td></tr>';
        return;
      }

      tbody.innerHTML = sources.map(s => {
        let statusBadge = '<span class="pill pill-gray">未测试</span>';
        if (s.healthStatus === 'passed') {
          statusBadge = '<span class="pill pill-green" title="' + escapeHtml(s.healthMessage) + '">🟢 正常</span>';
        } else if (s.healthStatus === 'failed' || s.healthStatus === 'blocked') {
          statusBadge = '<span class="pill pill-red" title="' + escapeHtml(s.healthMessage) + '">🔴 异常</span>';
        } else if (s.healthStatus === 'warning') {
          statusBadge = '<span class="pill pill-yellow" title="' + escapeHtml(s.healthMessage) + '">🟡 延迟高</span>';
        }

        return `
          <tr>
            <td>
              <div style="font-weight: 600;">${escapeHtml(s.name)}</div>
              <div style="font-size: 11px; color: var(--text-muted);">权重: ${s.weight}</div>
            </td>
            <td><span class="pill pill-gray">${escapeHtml(s.group || '未分组')}</span></td>
            <td><a href="${escapeHtml(s.url)}" target="_blank" style="color: #60a5fa; font-size: 12px;">${escapeHtml(s.url)}</a></td>
            <td>
              ${statusBadge}
              ${s.healthMessage && s.healthMessage !== '未检测' ? `<div style="font-size: 11px; color: var(--text-muted); margin-top: 2px;">${escapeHtml(s.healthMessage)}</div>` : ''}
            </td>
            <td>
              <input type="checkbox" ${s.enabled ? 'checked' : ''} onchange="toggleSource('${escapeJs(s.url)}', this.checked)">
            </td>
            <td>
              <div style="display: flex; gap: 6px;">
                <button class="btn btn-outline" style="padding: 4px 8px; font-size: 11px;" onclick="loadSourceIntoEditor('${escapeJs(s.url)}')">✏️ 编辑</button>
                <button class="btn btn-primary" style="padding: 4px 8px; font-size: 11px;" onclick="quickDebugSource('${escapeJs(s.url)}')">🧪 调试</button>
                <button class="btn btn-danger" style="padding: 4px 8px; font-size: 11px;" onclick="deleteSource('${escapeJs(s.url)}')">🗑️</button>
              </div>
            </td>
          </tr>
        `;
      }).join('');
    }

    async function toggleSource(url, enabled) {
      try {
        const res = await fetch('/api/sources/toggle', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ url: url, enabled: enabled })
        });
        const data = await res.json();
        if (data.ok) {
          showToast(enabled ? '已启用该书源' : '已禁用该书源');
        }
      } catch (e) {
        showToast('切换失败: ' + e.message, true);
      }
    }

    async function deleteSource(url) {
      if (!confirm(`确定要从手机删除此书源吗？\n${url}`)) return;
      try {
        const res = await fetch('/api/sources/delete', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ url: url })
        });
        const data = await res.json();
        if (data.ok) {
          showToast('书源已成功删除');
          loadSourceHealthList();
        } else {
          showToast('删除失败: ' + (data.error || '未知错误'), true);
        }
      } catch (e) {
        showToast('请求出错: ' + e.message, true);
      }
    }

    async function loadSourceIntoEditor(url) {
      try {
        const res = await fetch('/api/sources', { cache: 'no-store' });
        const data = await res.json();
        const found = (data.data || []).find(s => s.bookSourceUrl === url);
        if (found) {
          document.getElementById('source-code').value = JSON.stringify(found, null, 2);
          switchTab('editor');
          showToast(`已载入书源 [${found.bookSourceName}] 到编辑器`);
        } else {
          showToast('未找到指定书源数据', true);
        }
      } catch (e) {
        showToast('载入失败: ' + e.message, true);
      }
    }

    async function quickDebugSource(url) {
      await loadSourceIntoEditor(url);
      switchTab('debugger');
      runDebug();
    }

    async function exportBackup() {
      try {
        window.open('/api/sources/export', '_blank');
      } catch (e) {
        showToast('导出失败: ' + e.message, true);
      }
    }

    function escapeHtml(str) {
      if (!str) return '';
      return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
    }

    function escapeJs(str) {
      if (!str) return '';
      return String(str).replace(/'/g, "\\'");
    }
  </script>
</body>
</html>

"""#
    }
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
