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
                // Header card
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

                // Status notifications
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

                // Log Messages
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

                // Instructions
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
            .padding(AppTheme.pagePadding)
        }
        .pageBackground()
        .navigationTitle("Web 写源与传输")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Prevent screen sleep while user is editing on PC
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
            server.start()
        }
        .onDisappear {
            // Restore normal screen sleep when leaving view, but preserve server state
            // so user can switch to WeChat/Notes to copy and share the link freely.
            UIApplication.shared.isIdleTimerDisabled = false
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

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let lockQueue = DispatchQueue(label: "com.sourceread.server.lock")
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    var onJSONReceived: ((String) -> Result<String, Error>)?

    init(sourceStore: SourceStore? = nil) {
        self.sourceStore = sourceStore
        self.localIP = getLocalIPAddresses().first ?? "127.0.0.1"
        registerBackgroundKeepalive()
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
        guard isRunning, backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "SourceReadWebServerBackground") { [weak self] in
            self?.endBackgroundTask()
        }
        log("应用切至后台，已开启后台网络保活")
    }

    @objc private func handleWillEnterForeground() {
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    func refreshAddresses() {
        let addresses = getLocalIPAddresses()
        self.localIP = addresses.first ?? "127.0.0.1"
        self.localURLs = self.webURLs()
        self.log("已刷新网络接口，当前地址：\(self.localURLs.joined(separator: ", "))")
    }

    func clearLogs() {
        self.logMessages.removeAll()
    }

    func start() {
        guard !isRunning, !isStarting else { return }
        isStarting = true
        lastError = nil
        localIP = getLocalIPAddresses().first ?? "127.0.0.1"

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = false

        let candidates = [port] + (1122...1132).map(UInt16.init).filter { $0 != port }
        var lastStartError: Error?
        for candidate in candidates {
            do {
                let l = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: candidate) ?? 8080)
                listener = l
                port = candidate
                lastStartError = nil
                break
            } catch {
                lastStartError = error
                listener = nil
            }
        }

        guard listener != nil else {
            isStarting = false
            lastError = "无法创建网络监听：\(lastStartError?.localizedDescription ?? "端口不可用")"
            log(lastError ?? "无法创建网络监听")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self.isStarting = false
                    self.isRunning = true
                    self.localIP = getLocalIPAddresses().first ?? self.localIP
                    self.localURLs = self.webURLs()
                    self.log("服务器启动成功，正在监听端口 \(self.port)...")
                case .failed(let error):
                    self.isStarting = false
                    self.lastError = "服务器启动失败：\(error.localizedDescription)"
                    self.log(self.lastError ?? "服务器启动失败")
                    self.stop()
                case .cancelled:
                    self.isStarting = false
                    self.isRunning = false
                    self.localURLs = []
                    self.log("服务器已停止")
                default:
                    break
                }
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        listener?.start(queue: DispatchQueue.global(qos: .userInitiated))
    }

    func stop() {
        endBackgroundTask()
        listener?.cancel()
        listener = nil
        lockQueue.async { [weak self] in
            guard let self = self else { return }
            for connection in self.connections {
                connection.cancel()
            }
            self.connections.removeAll()
        }
        isRunning = false
        isStarting = false
        localURLs = []
    }

    private func handleNewConnection(_ connection: NWConnection) {
        log("收到来自 \(connection.endpoint) 的新连接")
        lockQueue.async { [weak self] in
            self?.connections.append(connection)
        }
        connection.stateUpdateHandler = { [weak self] state in
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
                self.log("导入成功：\(message)")
                self.sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "application/json; charset=utf-8", body: #"{"ok":true,"message":"\#(self.jsonEscape(message))"}"#, keepAlive: keepAlive)
            case .failure(let error):
                self.log("导入失败：\(error.localizedDescription)")
                self.sendResponse(connection: connection, statusCode: 400, statusText: "Bad Request", contentType: "application/json; charset=utf-8", body: #"{"ok":false,"error":"\#(self.jsonEscape(error.localizedDescription))"}"#, keepAlive: keepAlive)
            }
        }
    }

    private func respondWithSourceStore(connection: NWConnection, _ body: @escaping @MainActor (SourceStore?) -> Void) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            body(self.sourceStore)
        }
    }

    private func sendJSON<T: Encodable>(connection: NWConnection, value: T, keepAlive: Bool = true) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            let data = try encoder.encode(value)
            sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "application/json; charset=utf-8", body: String(decoding: data, as: UTF8.self), keepAlive: keepAlive)
        } catch {
            sendResponse(connection: connection, statusCode: 500, statusText: "Internal Error", contentType: "application/json; charset=utf-8", body: #"{"ok":false,"error":"encoding failed"}"#, keepAlive: keepAlive)
        }
    }

    private func jsonEscape(_ text: String) -> String {
        guard let data = try? JSONEncoder().encode(text),
              let encoded = String(data: data, encoding: .utf8) else { return "" }
        return String(encoded.dropFirst().dropLast())
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
        let responseBodyData = body.data(using: .utf8) ?? Data()
        let bodyLength = includeBody ? responseBodyData.count : 0
        let connectionHeader = keepAlive ? "keep-alive" : "close"
        let headerLines = [
            "HTTP/1.1 \(statusCode) \(statusText)",
            "Content-Type: \(contentType)",
            "Content-Length: \(bodyLength)",
            "Connection: \(connectionHeader)",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, HEAD, POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type",
            "Access-Control-Max-Age: 600",
            "\r\n"
        ]
        let headerString = headerLines.joined(separator: "\r\n")

        var responseData = headerString.data(using: .utf8) ?? Data()
        if includeBody {
            responseData.append(responseBodyData)
        }

        connection.send(
            content: responseData,
            contentContext: keepAlive ? .defaultMessage : .finalMessage,
            isComplete: true,
            completion: .contentProcessed { [weak self] error in
                if let error = error {
                    self?.log("发送响应错误: \(error)")
                } else {
                    self?.log("已发送响应: \(statusCode) \(statusText)")
                }
                if keepAlive {
                    self?.receiveRequest(on: connection, accumulated: Data())
                }
            }
        )
    }

    private func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timeStr = formatter.string(from: Date())
        DispatchQueue.main.async {
            self.logMessages.insert("[\(timeStr)] \(message)", at: 0)
            if self.logMessages.count > 80 {
                self.logMessages.removeLast(self.logMessages.count - 80)
            }
        }
    }

    private func webURLs() -> [String] {
        var seen = Set<String>()
        var urls: [String] = []
        let addresses = getLocalIPAddresses()
        for ip in addresses {
            guard !ip.isEmpty, ip != "127.0.0.1", seen.insert(ip).inserted else { continue }
            urls.append("http://\(ip):\(port)")
        }
        if urls.isEmpty {
            let fallback = (localIP != "127.0.0.1" && !localIP.isEmpty) ? localIP : "127.0.0.1"
            urls.append("http://\(fallback):\(port)")
        }
        return urls
    }

    private func getWebPageHtml() -> String {
        return stableWebPageHtml()
    }

    private func stableWebPageHtml() -> String {
        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>源阅读 Web 写源与管理后台 · SourceRead Studio</title>
            <style>
                :root {
                    --primary: #4f46e5;
                    --primary-hover: #4338ca;
                    --bg: #f8fafc;
                    --card: #ffffff;
                    --text: #0f172a;
                    --muted: #64748b;
                    --border: #e2e8f0;
                    --success: #10b981;
                    --error: #ef4444;
                    --code-bg: #f1f5f9;
                }
                @media (prefers-color-scheme: dark) {
                    :root {
                        --bg: #0b0f19;
                        --card: #151d2e;
                        --text: #f8fafc;
                        --muted: #94a3b8;
                        --border: #1e293b;
                        --code-bg: #0f172a;
                    }
                }
                * { box-sizing: border-box; margin: 0; padding: 0; }
                body {
                    min-height: 100vh;
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
                    background: var(--bg);
                    color: var(--text);
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                    padding: 24px 16px;
                    line-height: 1.5;
                }
                .container {
                    max-width: 860px;
                    width: 100%;
                    background: var(--card);
                    border: 1px solid var(--border);
                    border-radius: 20px;
                    box-shadow: 0 10px 40px rgba(0,0,0,0.06);
                    padding: 28px;
                }
                .header {
                    display: flex;
                    align-items: center;
                    justify-content: space-between;
                    margin-bottom: 20px;
                    padding-bottom: 16px;
                    border-bottom: 1px solid var(--border);
                }
                .brand {
                    display: flex;
                    align-items: center;
                    gap: 12px;
                }
                .brand-icon {
                    width: 40px;
                    height: 40px;
                    border-radius: 10px;
                    background: linear-gradient(135deg, #4f46e5, #06b6d4);
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    color: white;
                    font-weight: 900;
                    font-size: 20px;
                }
                .brand-title h1 {
                    font-size: 20px;
                    font-weight: 700;
                }
                .brand-title p {
                    font-size: 13px;
                    color: var(--muted);
                }
                .badge {
                    display: inline-flex;
                    align-items: center;
                    gap: 6px;
                    padding: 6px 12px;
                    border-radius: 999px;
                    background: rgba(16, 185, 129, 0.12);
                    color: var(--success);
                    font-size: 12px;
                    font-weight: 600;
                }
                .badge-dot {
                    width: 8px;
                    height: 8px;
                    border-radius: 50%;
                    background: var(--success);
                    box-shadow: 0 0 8px var(--success);
                    animation: pulse 2s infinite;
                }
                @keyframes pulse {
                    0% { opacity: 0.6; }
                    50% { opacity: 1; }
                    100% { opacity: 0.6; }
                }
                .editor-wrapper {
                    position: relative;
                    margin-bottom: 16px;
                }
                textarea {
                    width: 100%;
                    min-height: 380px;
                    padding: 16px;
                    border: 1px solid var(--border);
                    border-radius: 14px;
                    background: var(--code-bg);
                    color: var(--text);
                    font-family: "Fira Code", Menlo, Monaco, Consolas, monospace;
                    font-size: 13px;
                    line-height: 1.6;
                    resize: vertical;
                    outline: none;
                    transition: border-color 0.2s, box-shadow 0.2s;
                }
                textarea:focus {
                    border-color: var(--primary);
                    box-shadow: 0 0 0 3px rgba(79, 70, 229, 0.15);
                }
                .toolbar {
                    display: flex;
                    flex-wrap: wrap;
                    gap: 10px;
                    margin-bottom: 18px;
                }
                button {
                    padding: 10px 16px;
                    border-radius: 10px;
                    font-size: 13px;
                    font-weight: 600;
                    cursor: pointer;
                    border: 1px solid var(--border);
                    background: var(--card);
                    color: var(--text);
                    transition: all 0.15s ease;
                    display: inline-flex;
                    align-items: center;
                    gap: 6px;
                }
                button:hover {
                    background: var(--border);
                }
                button.btn-primary {
                    background: var(--primary);
                    border-color: var(--primary);
                    color: white;
                    flex: 1;
                    min-width: 200px;
                    justify-content: center;
                    font-size: 14px;
                    padding: 12px 20px;
                }
                button.btn-primary:hover {
                    background: var(--primary-hover);
                }
                button:disabled {
                    opacity: 0.6;
                    cursor: not-allowed;
                }
                .status-box {
                    background: var(--code-bg);
                    border: 1px solid var(--border);
                    border-radius: 10px;
                    padding: 12px 16px;
                    font-size: 12px;
                    color: var(--muted);
                    margin-bottom: 16px;
                    display: flex;
                    align-items: center;
                    justify-content: space-between;
                }
                .footer {
                    margin-top: 24px;
                    text-align: center;
                    font-size: 12px;
                    color: var(--muted);
                }
                .toast {
                    position: fixed;
                    top: 24px;
                    right: 24px;
                    padding: 14px 22px;
                    border-radius: 12px;
                    color: white;
                    font-size: 14px;
                    font-weight: 600;
                    box-shadow: 0 10px 30px rgba(0,0,0,0.15);
                    transform: translateY(-50px);
                    opacity: 0;
                    transition: all 0.3s cubic-bezier(0.16, 1, 0.3, 1);
                    z-index: 9999;
                    pointer-events: none;
                }
                .toast.show {
                    transform: translateY(0);
                    opacity: 1;
                }
                .toast.success { background: var(--success); }
                .toast.error { background: var(--error); }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <div class="brand">
                        <div class="brand-icon">源</div>
                        <div class="brand-title">
                            <h1>源阅读 Web 写源与管理后台</h1>
                            <p>SourceRead Web Studio · 局域网高速传输</p>
                        </div>
                    </div>
                    <div class="badge">
                        <div class="badge-dot"></div>
                        <span id="badge-text">已连接 iPhone</span>
                    </div>
                </div>

                <div class="toolbar">
                    <button type="button" onclick="insertTemplate()">📝 填入标准模板 (Legado 3.0)</button>
                    <button type="button" onclick="formatJSON()">✨ 格式化 JSON</button>
                    <button type="button" onclick="minifyJSON()">📦 压缩 JSON</button>
                    <button type="button" onclick="exportSources()">📥 导出手机全部书源</button>
                    <button type="button" onclick="clearInput()">🗑️ 清空</button>
                </div>

                <div class="editor-wrapper">
                    <textarea id="json-input" placeholder="在此粘贴 Legado 3.0 书源规则 JSON，或点击上方“填入标准模板”进行编辑..."></textarea>
                </div>

                <div style="display: flex; gap: 12px; margin-bottom: 16px;">
                    <button id="import-btn" class="btn-primary" onclick="performImport()">
                        🚀 立即导入到手机 (Import to iPhone)
                    </button>
                    <button type="button" onclick="refreshStatus()">
                        🔄 刷新状态
                    </button>
                </div>

                <div id="status-box" class="status-box">
                    <span id="status-text">正在探测 iPhone 服务状态...</span>
                    <span id="status-meta">Port: --</span>
                </div>

                <div class="footer">
                    提示：请保持手机屏幕常亮并处于 Web 写源页面 · 本机与 iPhone 需在同一 Wi-Fi 或热点下
                </div>
            </div>

            <div id="toast" class="toast"></div>

            <script>
                function insertTemplate() {
                    const template = [
                      {
                        "bookSourceName": "自定义新书源",
                        "bookSourceUrl": "https://example.com",
                        "bookSourceType": 0,
                        "enabled": true,
                        "searchUrl": "https://example.com/search?q={{key}}",
                        "ruleSearch": {
                          "bookList": ".book-item",
                          "name": ".title@text",
                          "author": ".author@text",
                          "bookUrl": "a@href"
                        },
                        "ruleToc": {
                          "chapterList": "#chapters a",
                          "chapterName": "text",
                          "chapterUrl": "href"
                        },
                        "ruleContent": {
                          "content": "#content@text"
                        }
                      }
                    ];
                    document.getElementById('json-input').value = JSON.stringify(template, null, 2);
                    showToast('已填入标准 Legado 3.0 书源模板', true);
                }

                function formatJSON() {
                    const input = document.getElementById('json-input');
                    const text = input.value.trim();
                    if (!text) {
                        showToast('请输入或粘贴 JSON 内容', false);
                        return;
                    }
                    try {
                        const parsed = JSON.parse(text);
                        input.value = JSON.stringify(parsed, null, 2);
                        showToast('JSON 格式化成功', true);
                    } catch (e) {
                        showToast('JSON 语法错误: ' + e.message, false);
                    }
                }

                function minifyJSON() {
                    const input = document.getElementById('json-input');
                    const text = input.value.trim();
                    if (!text) return;
                    try {
                        const parsed = JSON.parse(text);
                        input.value = JSON.stringify(parsed);
                        showToast('JSON 压缩完成', true);
                    } catch (e) {
                        showToast('压缩失败: ' + e.message, false);
                    }
                }

                function clearInput() {
                    if (confirm('确认清空当前编辑区内容？')) {
                        document.getElementById('json-input').value = '';
                    }
                }

                function showToast(message, isSuccess) {
                    const toast = document.getElementById('toast');
                    toast.textContent = message;
                    toast.className = 'toast ' + (isSuccess ? 'success' : 'error') + ' show';
                    setTimeout(() => toast.classList.remove('show'), 3500);
                }

                async function refreshStatus() {
                    const statusText = document.getElementById('status-text');
                    const statusMeta = document.getElementById('status-meta');
                    const badgeText = document.getElementById('badge-text');
                    try {
                        const res = await fetch('/api/status', { cache: 'no-store' });
                        if (!res.ok) throw new Error('HTTP ' + res.status);
                        const data = await res.json();
                        statusText.textContent = '在线 · 手机已有书源 ' + data.sourceCount + ' 个（' + data.enabledSourceCount + ' 个已启用）';
                        statusMeta.textContent = 'Port: ' + data.port;
                        badgeText.textContent = '已连接 iPhone (' + data.sourceCount + ' 源)';
                    } catch (err) {
                        statusText.textContent = '服务在线 · 状态更新中 (' + err.message + ')';
                        statusMeta.textContent = 'Port: OK';
                    }
                }

                async function exportSources() {
                    try {
                        const res = await fetch('/api/sources/export', { cache: 'no-store' });
                        if (!res.ok) throw new Error('HTTP ' + res.status);
                        const blob = await res.blob();
                        const a = document.createElement('a');
                        a.href = URL.createObjectURL(blob);
                        a.download = 'SourceRead-Backup-' + new Date().toISOString().slice(0,10) + '.json';
                        a.click();
                        URL.revokeObjectURL(a.href);
                        showToast('手机书源已成功导出到电脑', true);
                    } catch (err) {
                        showToast('导出失败: ' + err.message, false);
                    }
                }

                async function performImport() {
                    const input = document.getElementById('json-input');
                    const text = input.value.trim();
                    if (!text) {
                        showToast('请先输入或粘贴书源 JSON', false);
                        return;
                    }
                    const btn = document.getElementById('import-btn');
                    btn.disabled = true;
                    btn.textContent = '正在传输至手机...';
                    try {
                        const res = await fetch('/api/sources/import', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: text
                        });
                        const resText = await res.text();
                        let payload;
                        try { payload = JSON.parse(resText); } catch (_) { payload = null; }
                        if (res.ok && (!payload || payload.ok !== false)) {
                            const msg = (payload && payload.message) ? payload.message : '书源已成功保存到手机！';
                            showToast(msg, true);
                            input.value = '';
                        } else {
                            const err = (payload && payload.error) ? payload.error : resText;
                            showToast('导入失败: ' + err, false);
                        }
                    } catch (err) {
                        showToast('网络传输失败: ' + err.message, false);
                    } finally {
                        btn.disabled = false;
                        btn.textContent = '🚀 立即导入到手机 (Import to iPhone)';
                        refreshStatus();
                    }
                }

                // Initial status ping
                refreshStatus();
            </script>
        </body>
        </html>
        """
    }

}

// MARK: - IP Address Helper

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
