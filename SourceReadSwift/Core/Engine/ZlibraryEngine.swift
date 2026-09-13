import Foundation

/// Z-Library 全球图书源引擎（多节点动态容灾、内置账号轮询、eAPI 检索与直链高速下载）
/// 移植自 cmbok_app 的 ZlibraryService 核心架构
actor ZlibraryEngine {
    static let shared = ZlibraryEngine()

    static let sourceName = "Z-Library"
    static let sourceUrl = "https://z-library.sk"

    private static let kSavedDomainKey = "zlibrary_active_domain"
    private static let kSavedCandidatesKey = "zlibrary_candidates"
    private static let cloudConfigUrl = "https://cdn.jsdelivr.net/gh/hlning/cmbok@main/url_config.json"

    private struct BuiltinAccount {
        let email: String
        let pass: String
    }

    private static let builtinAccounts: [BuiltinAccount] = [
        BuiltinAccount(email: "1911607739@qq.com", pass: "chnattDJ"),
        BuiltinAccount(email: "19201347003@163.com", pass: "roMrzP6w"),
        BuiltinAccount(email: "3923258126@qq.com", pass: "ExpZF37s"),
        BuiltinAccount(email: "t28505858@gmail.com", pass: "kb6zfmnl"),
        BuiltinAccount(email: "jerry051120@gmail.com", pass: "hWkrYvnN"),
        BuiltinAccount(email: "miya011112@gmail.com", pass: "jbcT6dCe"),
        BuiltinAccount(email: "c7735942@gmail.com", pass: "UzmehY6d"),
        BuiltinAccount(email: "nhl684561@163.com", pass: "e5gSqusZ")
    ]

    private static let defaultCandidates: [String] = [
        "zh.zlibrary.by",
        "zlib.bz",
        "free2read.cc",
        "26h2.tech",
        "86110101.xyz",
        "loves.works",
        "biblioteca.pro",
        "toffeeboba.com"
    ]

    private var activeDomain: String
    private var candidates: [String]
    private var isProbing = false
    private let session: URLSession

    private var cachedUserId: String?
    private var cachedUserKey: String?
    private var currentAccountIndex = 0

    private init() {
        let savedDomain = UserDefaults.standard.string(forKey: Self.kSavedDomainKey)
        let savedCandidates = UserDefaults.standard.stringArray(forKey: Self.kSavedCandidatesKey)
        self.activeDomain = savedDomain ?? Self.defaultCandidates[0]
        self.candidates = savedCandidates ?? Self.defaultCandidates
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 60
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"
        ]
        self.session = URLSession(configuration: config)
    }

    /// 获取当前生效域名
    func currentDomain() -> String {
        activeDomain
    }

    /// 后台启动动态镜像池测速选优与云端镜像列表拉取
    func refreshCandidatesAndProbe() async {
        guard !isProbing else { return }
        isProbing = true
        defer { isProbing = false }

        // 1. 异步尝试从云端拉取最新候选池
        if let cloudUrl = URL(string: Self.cloudConfigUrl) {
            if let (data, _) = try? await session.data(from: cloudUrl),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let list = json["zlibrary_url"] as? [String], !list.isEmpty {
                var merged = list
                for c in self.candidates where !merged.contains(c) {
                    merged.append(c)
                }
                self.candidates = merged
                UserDefaults.standard.set(merged, forKey: Self.kSavedCandidatesKey)
            }
        }

        // 2. 并发探测候选节点
        let best = await pickBestCandidate()
        if let best, best != activeDomain {
            activeDomain = best
            UserDefaults.standard.set(best, forKey: Self.kSavedDomainKey)
        }
    }

    /// 并发测速选优
    private func pickBestCandidate() async -> String? {
        let probeCandidates = candidates
        return await withTaskGroup(of: (String, Double)?.self) { group in
            for host in probeCandidates {
                group.addTask { [session = self.session] in
                    guard let url = URL(string: "https://\(host)/"), host != "zlib.bz" else { return nil }
                    let start = Date()
                    var request = URLRequest(url: url)
                    request.httpMethod = "HEAD"
                    request.timeoutInterval = 4
                    do {
                        let (_, response) = try await session.data(for: request)
                        guard let http = response as? HTTPURLResponse else { return nil }
                        if (200...599).contains(http.statusCode) {
                            let latency = Date().timeIntervalSince(start)
                            return (host, latency)
                        }
                    } catch {
                        // Ignore failed node
                    }
                    return nil
                }
            }

            var results: [(String, Double)] = []
            for await item in group {
                if let item {
                    results.append(item)
                    if item.1 < 1.5 {
                        group.cancelAll()
                        return item.0
                    }
                }
            }
            return results.min(by: { $0.1 < $1.1 })?.0
        }
    }

    /// 轮询内置账号获取有效登录态
    private func ensureAuthToken() async -> (userId: String, userKey: String)? {
        if let uid = cachedUserId, let ukey = cachedUserKey, !uid.isEmpty, !ukey.isEmpty {
            return (uid, ukey)
        }

        let total = Self.builtinAccounts.count
        for step in 0..<total {
            let idx = (currentAccountIndex + step) % total
            let acc = Self.builtinAccounts[idx]
            if let token = await loginAccount(email: acc.email, password: acc.pass) {
                cachedUserId = token.0
                cachedUserKey = token.1
                currentAccountIndex = (idx + 1) % total
                return token
            }
        }
        return nil
    }

    private func loginAccount(email: String, password: String) async -> (String, String)? {
        let domain = activeDomain
        guard let url = URL(string: "https://\(domain)/eapi/user/login") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "email=\(urlEncode(email))&password=\(urlEncode(password))"
        request.httpBody = Data(body.utf8)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let user = json["user"] as? [String: Any] {
                let uid = "\(user["id"] ?? "")"
                let key = "\(user["remix_userkey"] ?? "")"
                if !uid.isEmpty && !key.isEmpty {
                    return (uid, key)
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    /// 搜索图书
    func search(keyword: String, page: Int = 1) async -> Result<[SearchBook], SourceEngineError> {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return .success([]) }

        let auth = await ensureAuthToken()
        let order = candidateOrder()

        for domain in order.prefix(4) {
            guard let url = URL(string: "https://\(domain)/eapi/book/search") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            if let auth {
                request.setValue("siteLanguageV2=en; remix_userid=\(auth.userId); remix_userkey=\(auth.userKey)", forHTTPHeaderField: "Cookie")
            }
            let body = "message=\(urlEncode(query))&limit=30&page=\(page)&order=popular"
            request.httpBody = Data(body.utf8)

            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse {
                    if let location = http.value(forHTTPHeaderField: "Location"),
                       let locURL = URL(string: location), let newHost = locURL.host, !newHost.isEmpty {
                        activeDomain = newHost
                        UserDefaults.standard.set(newHost, forKey: Self.kSavedDomainKey)
                    }
                    guard (200...299).contains(http.statusCode) else { continue }
                }

                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let rawBooks = json["books"] as? [[String: Any]] {
                    let searchBooks = rawBooks.compactMap { item -> SearchBook? in
                        guard let id = item["id"] as? Int,
                              let title = item["title"] as? String else { return nil }
                        let author = item["author"] as? String
                        let ext = (item["extension"] as? String)?.uppercased() ?? "EPUB"
                        let filesizeString = item["filesizeString"] as? String ?? ""
                        let year = item["year"] as? String
                        let cover = item["cover"] as? String
                        let hash = item["hash"] as? String ?? ""
                        let description = (item["description"] as? String ?? "")
                            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                            .trimmingCharacters(in: .whitespacesAndNewlines)

                        var descParts: [String] = []
                        if !ext.isEmpty { descParts.append(ext) }
                        if !filesizeString.isEmpty { descParts.append(filesizeString) }
                        if let year, !year.isEmpty { descParts.append("\(year)年") }
                        let prefix = descParts.isEmpty ? "" : "[\(descParts.joined(separator: " · "))] "

                        return SearchBook(
                            name: title,
                            author: author,
                            coverUrl: cover,
                            bookUrl: "zlib://\(id)/\(hash)",
                            sourceName: "Z-Library",
                            sourceUrl: "https://\(domain)",
                            intro: prefix + description,
                            kind: ext,
                            lastChapter: year.map { "\($0)年" }
                        )
                    }
                    if !searchBooks.isEmpty {
                        return .success(searchBooks)
                    }
                }
            } catch {
                continue
            }
        }
        return .success([])
    }

    /// 获取下载链接
    func fetchDownloadURL(bookID: String, hash: String) async -> Result<URL, SourceEngineError> {
        let auth = await ensureAuthToken()
        let domain = activeDomain

        // 兼容 /dl/slug 格式
        if hash.hasPrefix("dl/") || hash.contains("/dl/") {
            var slug = hash
            if let match = slug.range(of: "dl/([A-Za-z0-9_-]+)", options: .regularExpression) {
                slug = String(slug[match]).replacingOccurrences(of: "dl/", with: "")
            }
            guard let dlUrl = URL(string: "https://\(domain)/dl/\(slug)") else {
                return .failure(.network("无效的下载地址"))
            }
            return .success(dlUrl)
        }

        guard let url = URL(string: "https://\(domain)/eapi/book/\(bookID)/\(hash)/file") else {
            return .failure(.network("无效的图书请求地址"))
        }

        var request = URLRequest(url: url)
        if let auth {
            request.setValue("siteLanguageV2=en; remix_userid=\(auth.userId); remix_userkey=\(auth.userKey)", forHTTPHeaderField: "Cookie")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return .failure(.network("获取下载链接失败"))
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let fileObj = json["file"] as? [String: Any],
               let downloadLink = fileObj["downloadLink"] as? String,
               let dlURL = URL(string: downloadLink) {
                return .success(dlURL)
            }
        } catch {
            return .failure(.network("获取下载链接异常: \(error.localizedDescription)"))
        }
        return .failure(.network("解析下载链接失败"))
    }

    /// 下载 EPUB 文件并保存到本地临时目录
    func downloadBook(bookID: String, hash: String, title: String) async throws -> URL {
        let linkResult = await fetchDownloadURL(bookID: bookID, hash: hash)
        guard case .success(let downloadURL) = linkResult else {
            if case .failure(let error) = linkResult {
                throw error
            }
            throw SourceEngineError.network("获取下载链接失败")
        }

        var request = URLRequest(url: downloadURL)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SourceEngineError.network("下载图书数据失败")
        }

        let safeTitle = title.replacingOccurrences(of: "[/\\?%*|\"<>:]", with: "_", options: .regularExpression)
        let tempDir = FileManager.default.temporaryDirectory
        let destination = tempDir.appendingPathComponent("\(safeTitle)_\(bookID).epub")
        try data.write(to: destination)
        return destination
    }

    private func candidateOrder() -> [String] {
        var list = [activeDomain]
        for c in candidates where !list.contains(c) {
            list.append(c)
        }
        return list
    }

    private func urlEncode(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? string
    }
}
