import Foundation

/// Downloads anonymous jsLib dependencies through the engine's injected transport.
actor SourceJavaScriptLibraryLoader {
    static let maximumBundleBytes = 8 * 1_024 * 1_024

    struct Limits: Sendable {
        var maxEntries = 32
        var maxBytes = 8 * 1_024 * 1_024
        var maxLibraryBytes = 2 * 1_024 * 1_024
        var lifetime: TimeInterval = 3_600
        var timeout: TimeInterval = 20
    }

    private struct CachedLibrary {
        let script: String
        let byteCount: Int
        let expires: Date
        var access: UInt64
    }

    private let network: SourceNetworkClient
    private let limits: Limits
    private let now: @Sendable () -> Date
    private var cache: [URL: CachedLibrary] = [:]
    private var inFlight: [URL: Task<Result<String, SourceEngineError>, Never>] = [:]
    private var cacheBytes = 0
    private var access: UInt64 = 0

    init(network: SourceNetworkClient, limits: Limits = Limits(),
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.network = network
        self.limits = limits
        self.now = now
    }

    /// A nil result means inline JavaScript; URL maps retain JSON declaration order.
    static func remoteURLs(in library: String) -> Result<[URL]?, SourceEngineError> {
        let trimmed = library.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)),
              let fields = object as? [String: Any] else { return .success(nil) }
        guard trimmed.utf8.count <= 64 * 1_024, fields.count <= 32,
              fields.values.allSatisfy({ $0 is String }) else {
            return .failure(.invalidSource("jsLib 库清单应为最多 32 项的名称 → HTTP(S) 地址映射，大小不超过 64 KiB"))
        }
        // Legado SharedJsScope uses Gson Map.values.forEach; Gson LinkedTreeMap
        // iterates in insertion order. Dictionary/Object.keys would reorder numeric keys.
        // https://github.com/skybbk1001/legadoT/blob/master/shared/src/commonMain/kotlin/io/legado/app/model/SharedJsScope.kt
        let pairPattern = #""(?:[^"\\]|\\.)*"\s*:\s*"(?:[^"\\]|\\.)*""#
        guard let pairs = try? NSRegularExpression(pattern: pairPattern),
              let separator = try? NSRegularExpression(pattern: #"^"(?:[^"\\]|\\.)*""#) else {
            return .failure(.rule("jsLib 库清单解析器初始化失败"))
        }
        let text = trimmed as NSString
        var seen = Set<String>()
        var urls: [URL] = []
        for match in pairs.matches(in: trimmed, range: NSRange(location: 0, length: text.length)) {
            let pair = text.substring(with: match.range)
            guard let nameMatch = separator.firstMatch(in: pair, range: NSRange(location: 0, length: (pair as NSString).length)),
                  let name = try? JSONDecoder().decode(String.self, from: Data((pair as NSString).substring(with: nameMatch.range).utf8)),
                  seen.insert(name).inserted else { continue }
            guard let address = fields[name] as? String, let url = libraryURL(address) else {
                return .failure(.invalidSource("jsLib 第 \(urls.count + 1) 项不是可加载的 HTTP(S) 库地址"))
            }
            urls.append(url)
        }
        guard seen.count == fields.count else { return .failure(.invalidSource("jsLib 库清单无法按声明顺序解析")) }
        return .success(urls)
    }

    /// Returns cached source text or a validated response; failures are never cached.
    func load(_ url: URL) async -> Result<String, SourceEngineError> {
        guard Self.libraryURL(url.absoluteString) != nil else { return .failure(.invalidSource("jsLib 库地址必须为不含账号密码的 HTTP(S) 地址")) }
        removeExpiredLibraries()
        access &+= 1
        if var cached = cache[url] {
            cached.access = access
            cache[url] = cached
            return .success(cached.script)
        }
        if let pending = inFlight[url] { return await pending.value }
        let network = network
        let limits = limits
        let task = Task.detached { await Self.download(url, network: network, limits: limits) }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        if case .success(let script) = result { cacheLibrary(script, for: url) }
        return result
    }

    /// Bridges JavaScriptCore's blocking callback without running network work on its thread.
    nonisolated func loadSynchronously(_ url: URL) -> Result<String, SourceEngineError> {
        guard !Thread.isMainThread else { return .failure(.network("jsLib 远程库不能在主线程同步下载")) }
        let semaphore = DispatchSemaphore(value: 0)
        let result = LibraryDownloadResult()
        let task = Task.detached {
            result.store(await self.load(url))
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 25) == .success, let response = result.load() else {
            task.cancel()
            return .failure(.network("jsLib 库下载超时，请重试"))
        }
        return response
    }

    private static func libraryURL(_ address: String) -> URL? {
        guard address.utf8.count <= 8_192, let url = URL(string: address),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false, url.user == nil, url.password == nil else { return nil }
        return url
    }

    private static func download(_ url: URL, network: SourceNetworkClient, limits: Limits) async -> Result<String, SourceEngineError> {
        let timeout = min(20, max(0.05, limits.timeout))
        let request = SourceRequest(url: url, method: .get,
            headers: ["Accept": "application/javascript, text/javascript, text/plain, */*"],
            body: nil, expectedCharset: nil, timeout: timeout, usesCookies: false)
        guard let result = await AsyncTimeout.run(seconds: timeout, operation: { await network.load(request) }) else {
            return .failure(.network("jsLib 库下载超时，请重试"))
        }
        switch result {
        case .failure:
            return .failure(.network("jsLib 库请求失败（\(url.host ?? "未知域名")），未取得 JavaScript"))
        case .success(let response):
            guard (200..<300).contains(response.statusCode) else {
                return .failure(.network("jsLib 库下载失败：HTTP \(response.statusCode)"))
            }
            let normalized = ResponseBodyDecoder().normalize(response, preferredCharset: nil)
            let script = normalized.body.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
            guard max(normalized.data.count, script.utf8.count) <= min(2 * 1_024 * 1_024, max(1, limits.maxLibraryBytes)) else {
                return .failure(.network("jsLib 单个库超过大小上限，未执行"))
            }
            let contentType = normalized.headers.first { $0.key.lowercased() == "content-type" }?.value.lowercased() ?? ""
            guard !script.isEmpty, !script.hasPrefix("<"),
                  !contentType.contains("html"), !contentType.contains("json"), !contentType.contains("xml"),
                  (try? JSONSerialization.jsonObject(with: Data(script.utf8))) == nil else {
                return .failure(.network("jsLib 下载内容为空、网页或 JSON 错误响应，未取得 JavaScript"))
            }
            return .success(script)
        }
    }

    private func removeExpiredLibraries() {
        let instant = now()
        for url in cache.keys.filter({ cache[$0]!.expires <= instant }) {
            cacheBytes -= cache.removeValue(forKey: url)?.byteCount ?? 0
        }
    }

    private func cacheLibrary(_ script: String, for url: URL) {
        let byteCount = script.utf8.count
        let byteLimit = min(Self.maximumBundleBytes, max(0, limits.maxBytes))
        let entryLimit = min(32, max(0, limits.maxEntries))
        guard byteCount <= byteLimit, entryLimit > 0 else { return }
        while cache.count >= entryLimit || cacheBytes + byteCount > byteLimit {
            guard let oldest = cache.min(by: { $0.value.access < $1.value.access })?.key else { break }
            cacheBytes -= cache.removeValue(forKey: oldest)?.byteCount ?? 0
        }
        access &+= 1
        cache[url] = CachedLibrary(script: script, byteCount: byteCount,
            expires: now().addingTimeInterval(max(0, limits.lifetime)), access: access)
        cacheBytes += byteCount
    }
}

private final class LibraryDownloadResult: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<String, SourceEngineError>?
    func store(_ value: Result<String, SourceEngineError>) { lock.lock(); defer { lock.unlock() }; result = value }
    func load() -> Result<String, SourceEngineError>? { lock.lock(); defer { lock.unlock() }; return result }
}
