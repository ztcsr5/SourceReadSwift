import Foundation

struct StoredCookieRecord: Codable, Equatable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresDate: Date?
    let isSecure: Bool
    let isHTTPOnly: Bool

    init(cookie: HTTPCookie) {
        self.name = cookie.name
        self.value = cookie.value
        self.domain = cookie.domain
        self.path = cookie.path
        self.expiresDate = cookie.expiresDate
        self.isSecure = cookie.isSecure
        self.isHTTPOnly = cookie.isHTTPOnly
    }

    func toHTTPCookie() -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path
        ]
        if let expiresDate {
            properties[.expires] = expiresDate
        }
        if isSecure {
            properties[.secure] = "TRUE"
        }
        if isHTTPOnly {
            properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
        }
        return HTTPCookie(properties: properties)
    }
}

actor SourceCookieStore {
    struct PersistenceFailure: LocalizedError, Equatable, Sendable {
        enum Operation: Equatable, Sendable { case read, write }
        let operation: Operation
        let errorDomain: String
        let errorCode: Int

        var errorDescription: String? {
            operation == .read ? "读取已保存 Cookie 失败，本次会话未恢复；请重新登录。"
                : "Cookie 保存失败，本次更改尚未保存到设备；请重试后再关闭页面。"
        }
    }

    private var cookiesByHost: [String: [HTTPCookie]] = [:]
    private let storageURL: URL?
    private(set) var persistenceFailure: PersistenceFailure?

    init(storageURL: URL? = defaultStorageURL) {
        self.storageURL = storageURL
        if let storageURL {
            self.loadFromDisk(url: storageURL)
        }
    }

    static var defaultStorageURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SourceReadSwift/Cookies/cookies.json")
    }

    /// Prevents login completion from treating an in-memory Cookie as a saved session.
    func requirePersistence() throws {
        if let persistenceFailure { throw persistenceFailure }
    }

    func cookies(for url: URL) -> [HTTPCookie] {
        pruneExpiredCookies()
        guard let host = url.host?.lowercased() else { return [] }
        // Domain cookies may serve sibling hosts, but host-only cookies stay
        // restricted by cookieMatches even when their bucket is a parent host.
        let isHTTPS = url.scheme?.lowercased() == "https"
        var result: [HTTPCookie] = []
        var seen = Set<String>()
        var candidate = host
        while true {
            for cookie in cookiesByHost[candidate] ?? [] where (!cookie.isSecure || isHTTPS) && cookieMatches(cookie, host: host, path: url.path) {
                let key = "\(cookie.name)|\(cookie.domain)|\(cookie.path)"
                if seen.insert(key).inserted {
                    result.append(cookie)
                }
            }
            guard let dot = candidate.firstIndex(of: ".") else { break }
            let parent = String(candidate[candidate.index(after: dot)...])
            if parent.isEmpty || !parent.contains(".") { break }
            candidate = parent
        }
        return result
    }

    /// True when `cookie` may be sent to `host` + `path`.
    private func cookieMatches(_ cookie: HTTPCookie, host: String, path: String) -> Bool {
        guard Self.cookieDomainMatches(cookie, host: host) else { return false }
        let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
        if cookiePath == "/" { return true }
        let requestPath = path.isEmpty ? "/" : path
        return requestPath == cookiePath || requestPath.hasPrefix(cookiePath.hasSuffix("/") ? cookiePath : cookiePath + "/")
    }

    private static func cookieDomainMatches(_ cookie: HTTPCookie, host: String) -> Bool {
        let domain = cookie.domain.lowercased()
        if domain.hasPrefix(".") {
            let bare = String(domain.dropFirst())
            return host == bare || host.hasSuffix("." + bare)
        }
        return host == domain
    }

    func cookieHeader(for url: URL) -> String? {
        let cookies = cookies(for: url)
        guard !cookies.isEmpty else { return nil }
        return HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
    }

    func store(_ cookies: [HTTPCookie], for url: URL) {
        guard let host = url.host?.lowercased() else { return }
        storeCookies(cookies.filter { Self.cookieDomainMatches($0, host: host) })
    }

    func storeWebViewCookies(_ cookies: [HTTPCookie]) {
        storeCookies(cookies)
    }

    /// Replace a browser's visited-domain snapshot, including deletions, without touching other sites.
    func replaceWebViewCookies(_ cookies: [HTTPCookie], forVisitedHosts hosts: Set<String>) {
        guard !hosts.isEmpty, !Task.isCancelled else { return }
        for bucket in Array(cookiesByHost.keys) {
            cookiesByHost[bucket]?.removeAll { Self.cookieMatchesVisitedHosts($0, hosts: hosts) }
        }
        Self.mergeCookies(cookies.filter { Self.cookieMatchesVisitedHosts($0, hosts: hosts) }, into: &cookiesByHost)
        saveToDisk()
    }

    /// Match host-only and parent-domain cookies against sites actually opened in the login browser.
    nonisolated static func cookieMatchesVisitedHosts(_ cookie: HTTPCookie, hosts: Set<String>) -> Bool {
        hosts.contains { cookieDomainMatches(cookie, host: $0.lowercased()) }
    }

    /// Store one or more raw Set-Cookie header values. URLSession may expose
    /// a combined field with an Expires comma; split it conservatively before
    /// handing each cookie to Foundation's RFC parser.
    func storeSetCookieHeaders(_ headers: [String: String], for url: URL) {
        let values = CookieHeaderParser.setCookieValues(from: headers)
        guard !values.isEmpty else { return }
        var parsed: [HTTPCookie] = []
        for value in values {
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": value], for: url)
            guard let cookie = cookies.first else { continue }
            // Foundation keeps the cookie but throws away expiry dates it
            // cannot parse, which is how `Max-Age=30` became permanent.
            if cookie.expiresDate == nil,
               let expiry = CookieHeaderParser.expiryDate(fromSetCookie: value) {
                parsed.append(cookieApplying(expiry: expiry, to: cookie))
            } else {
                parsed.append(cookie)
            }
        }
        store(parsed, for: url)
    }

    /// Rebuild a cookie with an expiry Foundation failed to parse.
    private func cookieApplying(expiry: Date, to cookie: HTTPCookie) -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: cookie.name,
            .value: cookie.value,
            .domain: cookie.domain,
            .path: cookie.path,
            .expires: expiry
        ]
        if cookie.isSecure { properties[.secure] = "TRUE" }
        if cookie.isHTTPOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        return HTTPCookie(properties: properties) ?? cookie
    }

    func clearCookies(for host: String) {
        let normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
        cookiesByHost.removeValue(forKey: normalized)
        saveToDisk()
    }

    /// Clears this site's login cookies, including parent-domain cookies and non-root paths.
    func clearCookies(matching url: URL) {
        guard let host = url.host?.lowercased() else { return }
        for bucket in Array(cookiesByHost.keys) {
            cookiesByHost[bucket]?.removeAll { Self.cookieDomainMatches($0, host: host) }
        }
        saveToDisk()
    }

    func clearAllCookies() {
        cookiesByHost.removeAll()
        saveToDisk()
    }

    func allCookies() -> [HTTPCookie] {
        pruneExpiredCookies()
        return Array(cookiesByHost.values.joined())
    }

    func cookieCount() -> Int {
        pruneExpiredCookies()
        return cookiesByHost.values.reduce(0) { $0 + $1.count }
    }

    func hostsWithCookies() -> [String] {
        pruneExpiredCookies()
        return Array(cookiesByHost.keys).sorted()
    }

    // MARK: - Internal Management & Persistence

    private func storeCookies(_ cookies: [HTTPCookie]) {
        guard !cookies.isEmpty else { return }
        Self.mergeCookies(cookies, into: &cookiesByHost)
        saveToDisk()
    }

    private static func mergeCookies(_ cookies: [HTTPCookie], into buckets: inout [String: [HTTPCookie]]) {
        for cookie in cookies {
            // A response from login.example may set Domain=.example. Indexing
            // it by the response host makes it invisible to api.example.
            let host = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
            guard !host.isEmpty else { continue }
            var current = buckets[host] ?? []
            current.removeAll { $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path }
            current.append(cookie)
            buckets[host] = current
        }
    }

    private func pruneExpiredCookies() {
        let now = Date()
        var hasPruned = false
        for (host, cookies) in cookiesByHost {
            let valid = cookies.filter { cookie in
                guard let expires = cookie.expiresDate else { return true }
                return expires > now
            }
            if valid.count != cookies.count {
                cookiesByHost[host] = valid
                hasPruned = true
            }
        }
        if hasPruned {
            saveToDisk()
        }
    }

    private func loadFromDisk(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let records = try JSONDecoder().decode([String: [StoredCookieRecord]].self, from: data)
            var restored: [String: [HTTPCookie]] = [:]
            let now = Date()
            for host in records.keys.sorted() {
                let origin = host.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
                let cookies = (records[host] ?? []).compactMap { $0.toHTTPCookie() }.filter { cookie in
                    guard Self.cookieDomainMatches(cookie, host: origin) else { return false }
                    guard let expires = cookie.expiresDate else { return true }
                    return expires > now
                }
                // Older files used response-host buckets for network cookies.
                Self.mergeCookies(cookies, into: &restored)
            }
            self.cookiesByHost = restored
            persistenceFailure = nil
        } catch {
            let failure = error as NSError
            persistenceFailure = PersistenceFailure(operation: .read, errorDomain: failure.domain, errorCode: failure.code)
        }
    }

    private func saveToDisk() {
        guard let storageURL else { return }
        var exportDict: [String: [StoredCookieRecord]] = [:]
        for (host, cookies) in cookiesByHost {
            let validRecords = cookies.compactMap { StoredCookieRecord(cookie: $0) }
            if !validRecords.isEmpty {
                exportDict[host] = validRecords
            }
        }

        do {
            let directory = storageURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            let data = try JSONEncoder().encode(exportDict)
            try data.write(to: storageURL, options: [.atomic])
            persistenceFailure = nil
        } catch {
            let failure = error as NSError
            persistenceFailure = PersistenceFailure(operation: .write, errorDomain: failure.domain, errorCode: failure.code)
        }
    }
}
