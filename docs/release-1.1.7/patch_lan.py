from pathlib import Path
import shutil
ROOT=Path(__file__).resolve().parents[2]
path=ROOT/'SourceReadSwift/Features/Discover/SourceWritingView.swift'
out=Path('F:/SourceReadSwift/release-1.1.7/pre-item14')
for name in ['SourceReadSwift/Features/Discover/SourceWritingView.swift','tools/lan_import.py']:
 target=out/name;target.parent.mkdir(parents=True,exist_ok=True)
 if not target.exists():shutil.copyfile(ROOT/name,target)
s=path.read_text(encoding='utf-8')
start=s.index('    private func getWebPageHtml() -> String {')
end=s.index('\n}\n\nprivate struct WebSourceListResponse',start)
s=s[:start]+'    private func getWebPageHtml() -> String { LANWorkbenchDocument.html }\n'+s[end:]
def replace(old,new):
 global s
 assert s.count(old)==1,(old,s.count(old))
 s=s.replace(old,new)
replace('    @Published var isStarting = false','    @Published var isStarting = false\n    @Published private(set) var pairingToken = ""\n    private let access = LANWorkbenchAccess()')
replace('        isStarting = true\n        lastError = nil','        pairingToken = access.renew()\n        isStarting = true\n        lastError = nil')
replace('    func stop() {\n        lockQueue.sync {','    func stop() {\n        access.revoke()\n        pairingToken = ""\n        lockQueue.sync {')
replace('        log("HTTP 请求: \\(method) \\(path)")','''        log("HTTP 请求: \\(method) \\(path)")
        if path.hasPrefix("/api/") || path == "/import" {
            guard access.permits(request) else {
                sendResponse(connection: connection, statusCode: 401, statusText: "Unauthorized",
                             contentType: "application/json; charset=utf-8",
                             body: #"{"ok":false,"error":"Pairing required"}"#, keepAlive: false)
                return
            }
        }''')
replace('''        } else if method == "GET" && path == "/api/sources/health" {''','''        } else if method == "GET" && path == "/api/source" {
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
        } else if method == "GET" && path == "/api/sources/health" {''')
replace('''        header += "Access-Control-Allow-Origin: *\\r\\n"
        header += "Access-Control-Allow-Methods: GET, POST, OPTIONS, PUT, DELETE\\r\\n"
        header += "Access-Control-Allow-Headers: Content-Type, Accept\\r\\n"
        header += keepAlive ? "Connection: keep-alive\\r\\n" : "Connection: close\\r\\n"''','''        header += "Cache-Control: no-store\\r\\n"
        header += "X-Content-Type-Options: nosniff\\r\\n"
        header += "Referrer-Policy: no-referrer\\r\\n"
        header += "Content-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'\\r\\n"
        // This parser handles one request per connection, not HTTP pipelining.
        // Advertising keep-alive previously left reused browser sockets idle.
        header += "Connection: close\\r\\n"''')
replace('''            if !keepAlive {
                connection.cancel()
            }''','''            connection.cancel()''')
replace('''                HStack(spacing: 12) {
                    Button {''','''                VStack(alignment: .leading, spacing: 8) {
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
                    Button {''')
s += '\nprivate struct WebSingleSourceResponse: Encodable {\n    let ok: Bool\n    let data: BookSource\n}\n'
path.write_text(s,encoding='utf-8')
print('Updated LAN server; old inline HTML removed; pre-item14 originals copied.')
