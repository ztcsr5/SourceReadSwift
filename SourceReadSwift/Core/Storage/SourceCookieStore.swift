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
        return HTTPCookie(properties: properties)
    }
}

actor SourceCookieStore {
    private var cookiesByHost: [String: [HTTPCookie]] = [:]
    private let storageURL: URL?

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

    func cookies(for url: URL) -> [HTTPCookie] {
        pruneExpiredCookies()
        guard let host = url.host?.lowercased() else { return [] }
        return cookiesByHost[host] ?? []
    }

    func cookieHeader(for url: URL) -> String? {
        let cookies = cookies(for: url)
        guard !cookies.isEmpty else { return nil }
        return HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
    }

    func store(_ cookies: [HTTPCookie], for url: URL) {
        guard let host = url.host?.lowercased() else { return }
        store(cookies, host: host)
    }

    func storeWebViewCookies(_ cookies: [HTTPCookie]) {
        for cookie in cookies {
            let host = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            guard !host.isEmpty else { continue }
            store([cookie], host: host)
        }
    }

    /// Store one or more raw Set-Cookie header values. URLSession may expose
    /// a combined field with an Expires comma; split it conservatively before
    /// handing each cookie to Foundation's RFC parser.
    func storeSetCookieHeaders(_ headers: [String: String], for url: URL) {
        let values = CookieHeaderParser.setCookieValues(from: headers)
        guard !values.isEmpty else { return }
        var parsed: [HTTPCookie] = []
        for value in values {
            parsed.append(contentsOf: HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": value], for: url))
        }
        store(parsed, for: url)
    }

    func clearCookies(for host: String) {
        let normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
        cookiesByHost.removeValue(forKey: normalized)
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

    private func store(_ cookies: [HTTPCookie], host: String) {
        let normalizedHost = host.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
        guard !normalizedHost.isEmpty else { return }

        var current = cookiesByHost[normalizedHost] ?? []
        for cookie in cookies {
            current.removeAll { $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path }
            current.append(cookie)
        }
        cookiesByHost[normalizedHost] = current
        saveToDisk()
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
            for (host, list) in records {
                let cookies = list.compactMap { $0.toHTTPCookie() }.filter { cookie in
                    guard let expires = cookie.expiresDate else { return true }
                    return expires > now
                }
                if !cookies.isEmpty {
                    restored[host] = cookies
                }
            }
            self.cookiesByHost = restored
        } catch {
            // Non-critical, start with clean memory
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
        } catch {
            // Non-fatal on write errors
        }
    }
}
