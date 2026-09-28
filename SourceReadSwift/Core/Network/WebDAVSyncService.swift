import Foundation

/// WebDAV connection configuration for personal cloud backup & restore.
/// Fully compatible with standard WebDAV providers like Jianguoyun (坚果云),
/// Nextcloud, ownCloud, Synology WebDAV Server, QNAP, Koofr, and Alist.
struct WebDAVConfig: Codable, Equatable, Sendable {
    var serverURL: String
    var username: String
    var password: String
    var remoteDirectory: String

    init(
        serverURL: String = "https://dav.jianguoyun.com/dav/",
        username: String = "",
        password: String = "",
        remoteDirectory: String = "SourceReadSwift"
    ) {
        self.serverURL = serverURL
        self.username = username
        self.password = password
        self.remoteDirectory = remoteDirectory
    }

    var isConfigured: Bool {
        !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Metadata describing a remote backup file discovered on the WebDAV server.
struct WebDAVRemoteItem: Identifiable, Equatable, Sendable {
    var id: String { href }
    let href: String
    let filename: String
    let size: Int64
    let lastModified: Date?
    let isDirectory: Bool

    var formattedSize: String {
        if size <= 0 { return "--" }
        if size < 1024 { return "\(size) B" }
        let kb = Double(size) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        return String(format: "%.2f MB", mb)
    }

    var formattedDate: String {
        guard let lastModified else { return "未知时间" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: lastModified)
    }
}

/// Errors occurring during WebDAV operations.
enum WebDAVError: LocalizedError, Equatable {
    case invalidURL
    case unauthorized
    case httpError(statusCode: Int)
    case invalidResponse
    case fileNotFound
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "WebDAV 服务器地址或文件路径格式无效"
        case .unauthorized:
            return "WebDAV 鉴权失败，请检查用户名与应用密码"
        case .httpError(let statusCode):
            return "WebDAV 服务器返回错误代码：HTTP \(statusCode)"
        case .invalidResponse:
            return "WebDAV 服务器返回了无效或无法解析的响应"
        case .fileNotFound:
            return "指定的云端备份文件未找到"
        case .decodingFailed:
            return "解析云端备份数据失败，请确认文件格式正确"
        }
    }
}

/// Production-ready WebDAV service using Foundation URLSession and XMLParser.
final class WebDAVSyncService: Sendable {
    static let shared = WebDAVSyncService()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - URL & Auth Utilities

    func buildDirectoryURL(config: WebDAVConfig) -> URL? {
        var base = config.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }
        if !base.hasSuffix("/") {
            base += "/"
        }
        let dir = config.remoteDirectory.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if dir.isEmpty {
            return URL(string: base)
        }
        return URL(string: base + dir + "/")
    }

    func buildFileURL(config: WebDAVConfig, filename: String) -> URL? {
        guard let dirURL = buildDirectoryURL(config: config) else { return nil }
        let cleanedFilename = filename.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let encodedFilename = cleanedFilename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return dirURL.appendingPathComponent(cleanedFilename)
        }
        return URL(string: dirURL.absoluteString + encodedFilename)
    }

    func authHeader(config: WebDAVConfig) -> String {
        let authString = "\(config.username):\(config.password)"
        let authData = authString.data(using: .utf8) ?? Data()
        return "Basic \(authData.base64EncodedString())"
    }

    // MARK: - Connection & Directory Operations

    /// Tests the WebDAV server connection and directory readiness.
    func testConnection(config: WebDAVConfig) async throws -> Bool {
        guard let dirURL = buildDirectoryURL(config: config) else {
            throw WebDAVError.invalidURL
        }
        var request = URLRequest(url: dirURL)
        request.httpMethod = "PROPFIND"
        request.setValue(authHeader(config: config), forHTTPHeaderField: "Authorization")
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.timeoutInterval = 15

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebDAVError.invalidResponse
        }
        if httpResponse.statusCode == 200 || httpResponse.statusCode == 207 {
            return true
        } else if httpResponse.statusCode == 404 {
            // Directory does not exist yet; try creating it via MKCOL
            return try await createDirectoryIfNeeded(config: config)
        } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw WebDAVError.unauthorized
        } else {
            throw WebDAVError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    /// Creates the target directory on the WebDAV server if not already present.
    @discardableResult
    func createDirectoryIfNeeded(config: WebDAVConfig) async throws -> Bool {
        guard let dirURL = buildDirectoryURL(config: config) else {
            throw WebDAVError.invalidURL
        }
        var request = URLRequest(url: dirURL)
        request.httpMethod = "MKCOL"
        request.setValue(authHeader(config: config), forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebDAVError.invalidResponse
        }
        // 201 Created: Created successfully
        // 405 Method Not Allowed: Collection already exists (RFC 4918 §9.3)
        // 200 OK: Accepted by some WebDAV proxies
        if httpResponse.statusCode == 201 || httpResponse.statusCode == 405 || httpResponse.statusCode == 200 {
            return true
        } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw WebDAVError.unauthorized
        } else {
            throw WebDAVError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    // MARK: - Backup Upload & Download

    /// Uploads an AppDataBackupSnapshot JSON document to the WebDAV server.
    /// Returns the final uploaded filename.
    func uploadSnapshot(
        snapshot: AppDataBackupSnapshot,
        config: WebDAVConfig,
        filename: String? = nil
    ) async throws -> String {
        try await createDirectoryIfNeeded(config: config)

        let resolvedFilename: String
        if let filename, !filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolvedFilename = filename.hasSuffix(".json") ? filename : "\(filename).json"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            formatter.timeZone = TimeZone.current
            let timeStamp = formatter.string(from: Date())
            resolvedFilename = "SourceRead_Backup_\(timeStamp).json"
        }

        guard let fileURL = buildFileURL(config: config, filename: resolvedFilename) else {
            throw WebDAVError.invalidURL
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)

        var request = URLRequest(url: fileURL)
        request.httpMethod = "PUT"
        request.setValue(authHeader(config: config), forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        request.httpBody = data
        request.timeoutInterval = 30

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebDAVError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw WebDAVError.unauthorized
            }
            throw WebDAVError.httpError(statusCode: httpResponse.statusCode)
        }
        return resolvedFilename
    }

    /// Lists all backup documents residing in the WebDAV directory.
    func listBackups(config: WebDAVConfig) async throws -> [WebDAVRemoteItem] {
        guard let dirURL = buildDirectoryURL(config: config) else {
            throw WebDAVError.invalidURL
        }
        var request = URLRequest(url: dirURL)
        request.httpMethod = "PROPFIND"
        request.setValue(authHeader(config: config), forHTTPHeaderField: "Authorization")
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebDAVError.invalidResponse
        }
        guard httpResponse.statusCode == 207 || httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw WebDAVError.unauthorized
            }
            if httpResponse.statusCode == 404 {
                return []
            }
            throw WebDAVError.httpError(statusCode: httpResponse.statusCode)
        }

        let parser = WebDAVXMLParser(data: data)
        let allItems = parser.parse()

        // Filter to backup files only (excluding folders and non-backup resources)
        return allItems.filter { item in
            !item.isDirectory && (
                item.filename.lowercased().hasSuffix(".json") ||
                item.filename.lowercased().hasSuffix(".backup")
            )
        }.sorted { item1, item2 in
            (item1.lastModified ?? .distantPast) > (item2.lastModified ?? .distantPast)
        }
    }

    /// Downloads and decodes an AppDataBackupSnapshot from the WebDAV server.
    func downloadSnapshot(filename: String, config: WebDAVConfig) async throws -> AppDataBackupSnapshot {
        guard let fileURL = buildFileURL(config: config, filename: filename) else {
            throw WebDAVError.invalidURL
        }
        var request = URLRequest(url: fileURL)
        request.httpMethod = "GET"
        request.setValue(authHeader(config: config), forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebDAVError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw WebDAVError.unauthorized
            }
            if httpResponse.statusCode == 404 {
                throw WebDAVError.fileNotFound
            }
            throw WebDAVError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(AppDataBackupSnapshot.self, from: data) else {
            throw WebDAVError.decodingFailed
        }
        return snapshot
    }

    /// Deletes a specific backup document from the WebDAV server.
    func deleteBackup(filename: String, config: WebDAVConfig) async throws {
        guard let fileURL = buildFileURL(config: config, filename: filename) else {
            throw WebDAVError.invalidURL
        }
        var request = URLRequest(url: fileURL)
        request.httpMethod = "DELETE"
        request.setValue(authHeader(config: config), forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebDAVError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 404 else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw WebDAVError.unauthorized
            }
            throw WebDAVError.httpError(statusCode: httpResponse.statusCode)
        }
    }
}

// MARK: - WebDAV XML Parser

/// Robust, zero-dependency XML parser for WebDAV PROPFIND multistatus responses.
final class WebDAVXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var items: [WebDAVRemoteItem] = []

    private var currentText = ""
    private var currentHref = ""
    private var currentLength: Int64 = 0
    private var currentLastModified: Date? = nil
    private var currentIsDirectory = false

    private static let rfc1123Formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    private static let iso8601Formatter = ISO8601DateFormatter()

    init(data: Data) {
        self.data = data
    }

    func parse() -> [WebDAVRemoteItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        parser.parse()
        return items
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        let normalized = elementName.components(separatedBy: ":").last?.lowercased() ?? elementName.lowercased()
        currentText = ""
        if normalized == "response" {
            currentHref = ""
            currentLength = 0
            currentLastModified = nil
            currentIsDirectory = false
        } else if normalized == "collection" {
            currentIsDirectory = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let normalized = elementName.components(separatedBy: ":").last?.lowercased() ?? elementName.lowercased()
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized == "href" {
            currentHref = trimmed
        } else if normalized == "getcontentlength" {
            currentLength = Int64(trimmed) ?? 0
        } else if normalized == "getlastmodified" {
            currentLastModified = Self.rfc1123Formatter.date(from: trimmed) ?? Self.iso8601Formatter.date(from: trimmed)
        } else if normalized == "response" {
            if !currentHref.isEmpty {
                let unescapedHref = currentHref.removingPercentEncoding ?? currentHref
                let rawFilename = (unescapedHref as NSString).lastPathComponent
                let filename = rawFilename.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                if !filename.isEmpty {
                    let item = WebDAVRemoteItem(
                        href: currentHref,
                        filename: filename,
                        size: currentLength,
                        lastModified: currentLastModified,
                        isDirectory: currentIsDirectory
                    )
                    items.append(item)
                }
            }
        }
        currentText = ""
    }
}
