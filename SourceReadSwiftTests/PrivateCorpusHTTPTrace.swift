import CryptoKit
import CoreFoundation
import Foundation
import SwiftSoup
@testable import SourceReadSwift

/// Probe-only transport observations. Never retain URLs, header values, or response text.
struct PrivateCorpusHTTPObservation: Codable, Sendable {
    let sequence: Int
    let endpointHash: String
    let scheme: String
    let method: String
    let startedMilliseconds: Int
    let requestBytes: Int
    let requestShape: PrivateCorpusJSONShape
    var elapsedMilliseconds = 0
    var outcome = "pending"
    var statusCode: Int?
    var responseBytes: Int?
    var responseShape: PrivateCorpusJSONShape?
    var responseEndpointHash: String?
    var html: PrivateCorpusHTMLShape?
}

/// Counts visible evidence without retaining authored rules, rendered text, or links.
struct PrivateCorpusHTMLShape: Codable, Sendable {
    let anchorCount: Int
    let keywordLinkCount: Int
    let chapterLinkCount: Int
    let explicitEmptyResults: Bool
    let challengeMarkup: Bool
    let passwordForm: Bool
    let renderingShell: Bool

    static func inspect(_ source: String, keyword: String) -> Self? {
        guard source.utf8.count <= 384 * 1024,
              source.drop(while: { $0.isWhitespace }).hasPrefix("<"),
              let document = try? SwiftSoup.parse(source),
              let body = document.body(), let text = try? body.text(),
              let anchors = try? body.select("a[href]").array() else { return nil }
        let labels = anchors.compactMap { try? $0.text() }
        let keywordLinks = keyword.isEmpty ? 0 : labels.filter {
            $0.range(of: keyword, options: .caseInsensitive) != nil
        }.count
        let chapterLinks = labels.filter {
            $0.range(of: #"第\s*[\d一二三四五六七八九十百千零两〇]+\s*[章节卷回话集]|\bchapter\s+\d+"#,
                     options: [.caseInsensitive, .regularExpression]) != nil
        }.count
        let empty = ["暂无搜索结果", "没有找到相关", "没有找到与", "未找到相关", "没有相关书籍", "no results found"]
            .contains { text.range(of: $0, options: .caseInsensitive) != nil }
        let challenge = (try? document.select("#challenge-form, #cf-challenge-running, .cf-turnstile, iframe[src*=captcha]").isEmpty()) == false
        let password = (try? body.select("form input[type=password]").isEmpty()) == false
        let hasShell = (try? body.select("#app, #root, #__next").isEmpty()) == false
        let needsScript = (try? document.select("script[src]").isEmpty()) == false
        return .init(anchorCount: anchors.count, keywordLinkCount: keywordLinks, chapterLinkCount: chapterLinks,
            explicitEmptyResults: empty, challengeMarkup: challenge, passwordForm: password,
            renderingShell: anchors.count <= 2 && text.count < 160 && hasShell && needsScript)
    }
}

struct PrivateCorpusJSONShape: Codable, Sendable {
    let root: String
    let fieldCount: Int?
    let fields: [String: String]
    let reasonHints: [String]

    private static let observedFields: Set<String> = [
        "data", "Data", "result", "Result", "code", "status", "success", "error", "message", "msg",
        "content", "Content", "chapters", "Chapters", "app", "version", "bookId", "chapterId",
        "info", "sound", "soundurl_128", "soundurl", "source", "url", "name", "bookid", "tab"
    ]

    static func inspectRequest(_ bytes: Data, contentType: String?) -> Self {
        let shape = inspect(bytes)
        let mediaType = contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
        guard shape.root == "non-json", mediaType == nil || mediaType == "application/x-www-form-urlencoded",
              let text = String(data: bytes, encoding: .utf8) else { return shape }
        let pairs = text.split(separator: "&", omittingEmptySubsequences: false)
        var fields: [String: String] = [:]
        for pair in pairs {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let name = String(parts[0]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding,
                  let value = String(parts[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding,
                  mediaType != nil || observedFields.contains(name) else { return shape }
            guard observedFields.contains(name) else { continue }
            fields[name] = fields[name] == nil ? (value.isEmpty ? "empty-string" : "string") : "duplicate"
        }
        // A missing header only permits a structural hint, not a claim about the transmitted MIME type.
        return .init(root: mediaType == nil ? "form-like" : "form", fieldCount: pairs.count, fields: fields, reasonHints: [])
    }

    static func inspect(_ bytes: Data) -> Self {
        guard !bytes.isEmpty else { return .init(root: "empty", fieldCount: nil, fields: [:], reasonHints: []) }
        guard bytes.count <= 256 * 1024 else {
            return .init(root: "over-size-limit", fieldCount: nil, fields: [:], reasonHints: [])
        }
        guard let value = try? JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed]) else {
            return .init(root: "non-json", fieldCount: nil, fields: [:], reasonHints: [])
        }
        let object = value as? [String: Any]
        let fields = fieldTypes(in: object ?? [:], prefix: "", depth: 3)
        let messages = ["message", "msg", "error"].compactMap { object?[$0] as? String }.joined(separator: " ").lowercased()
        let reasons = [
            ("authentication", ["登录", "登陆", "unauthorized", "login required", "token expired"]),
            ("source-version", ["书源版本", "更新书源", "version too old", "outdated version"]),
            ("rate-limit", ["请求频繁", "访问频繁", "too many requests", "rate limit"])
        ].compactMap { label, terms in terms.contains(where: { messages.contains($0) }) ? label : nil }
        return .init(root: kind(value), fieldCount: object?.count, fields: fields, reasonHints: reasons)
    }

    private static func fieldTypes(in object: [String: Any], prefix: String, depth: Int) -> [String: String] {
        guard depth > 0 else { return [:] }
        var fields: [String: String] = [:]
        for key in object.keys.filter({ observedFields.contains($0) }).sorted() {
            guard fields.count < 64 else { break }
            guard let value = object[key] else { continue }
            let path = prefix + key
            fields[path] = kind(value)
            if let nested = value as? [String: Any] {
                for (nestedPath, nestedKind) in fieldTypes(in: nested, prefix: path + ".", depth: depth - 1).sorted(by: { $0.key < $1.key }) {
                    guard fields.count < 64 else { break }
                    fields[nestedPath] = nestedKind
                }
            }
        }
        return fields
    }

    private static func kind(_ value: Any) -> String {
        if value is NSNull { return "null" }
        if value is [String: Any] { return "object" }
        if let array = value as? [Any] { return "array:\(array.count)" }
        if value is String { return "string" }
        if let number = value as? NSNumber {
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? "boolean" : "number"
        }
        return "unknown"
    }
}

/// Describes the parser's final output without exporting book text or a signed media link.
struct PrivateCorpusContentObservation: Codable, Sendable {
    let bytes: Int
    let paragraphs: Int
    let containsHTTPReference: Bool
    let matchesContentRuleLiterally: Bool
    let jsonShape: PrivateCorpusJSONShape

    init(content: ChapterContent, rule: String?) {
        let text = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
        bytes = text.utf8.count
        paragraphs = content.paragraphs.count
        containsHTTPReference = text.range(of: "https?://", options: .regularExpression) != nil
        matchesContentRuleLiterally = !text.isEmpty && text == rule?.trimmingCharacters(in: .whitespacesAndNewlines)
        jsonShape = .inspect(Data(text.utf8.prefix(256 * 1024 + 1)))
    }
}

struct PrivateCorpusImageObservation: Codable, Sendable {
    let samplePosition: Int
    let urlSHA256: String
    let hasTransportObservation: Bool
    let httpStatusCode: Int?
    let receivedBytes: Int64?
    let errorDomain: String?
    let errorCode: Int?
}

/// Each URL observation is consumed once; a cache hit is never counted as a new network request.
final class PrivateCorpusImageTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var observations: [ComicImageTransportObservation] = []

    func record(_ observation: ComicImageTransportObservation) {
        lock.lock()
        defer { lock.unlock() }
        if observations.count < 64 { observations.append(observation) }
    }

    func take(for url: URL, samplePosition: Int) -> PrivateCorpusImageObservation {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        lock.lock()
        let observation = observations.firstIndex(where: { $0.urlSHA256 == hash }).map { observations.remove(at: $0) }
        lock.unlock()
        return .init(samplePosition: samplePosition, urlSHA256: hash, hasTransportObservation: observation != nil,
            httpStatusCode: observation?.httpStatusCode, receivedBytes: observation?.receivedBytes,
            errorDomain: observation?.errorDomain, errorCode: observation?.errorCode)
    }
}

actor PrivateCorpusHTTPTrace: SourceNetworkClient {
    private let network: SourceNetworkClient
    private let keyword: String
    private let startedAt = ProcessInfo.processInfo.systemUptime
    private var observations: [PrivateCorpusHTTPObservation] = []
    private var requestStarts: [TimeInterval] = []
    private(set) var droppedRequests = 0
    private static let maximumObservations = 64

    init(network: SourceNetworkClient, keyword: String = "") {
        self.network = network
        self.keyword = keyword
    }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        guard observations.count < Self.maximumObservations else {
            droppedRequests += 1
            return await network.load(request)
        }
        let position = observations.count
        let start = ProcessInfo.processInfo.systemUptime
        let scheme = request.url.scheme ?? ""
        requestStarts.append(start)
        observations.append(.init(sequence: position, endpointHash: Self.endpointHash(request.url),
            scheme: ["http", "https", "data"].contains(scheme) ? scheme : "other",
            method: request.method.rawValue, startedMilliseconds: Self.milliseconds(start - startedAt),
            requestBytes: request.body?.count ?? 0,
            requestShape: .inspectRequest(request.body ?? Data(), contentType: request.headers.first {
                $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame
            }?.value)))
        let result = await network.load(request)
        observations[position].elapsedMilliseconds = Self.milliseconds(ProcessInfo.processInfo.systemUptime - start)
        switch result {
        case .success(let response):
            observations[position].outcome = "response"
            observations[position].statusCode = response.statusCode
            observations[position].responseBytes = response.data.count
            observations[position].responseShape = .inspect(Data(response.body.utf8.prefix(256 * 1024 + 1)))
            observations[position].responseEndpointHash = Self.endpointHash(response.url)
            observations[position].html = .inspect(response.body, keyword: keyword)
        case .failure(let failure):
            observations[position].outcome = Task.isCancelled ? "cancelled" : "failure"
            // Store a fixed category, never a transport error interpolating a URL or body.
            observations[position].responseShape = .init(
                root: SourceDiagnosticClassifier.kind(error: failure, stage: "transport").rawValue,
                fieldCount: nil, fields: [:], reasonHints: [])
        }
        return result
    }

    func snapshot() -> [PrivateCorpusHTTPObservation] {
        let now = ProcessInfo.processInfo.systemUptime
        return observations.enumerated().map { position, observation in
            var result = observation
            if result.outcome == "pending" { result.elapsedMilliseconds = Self.milliseconds(now - requestStarts[position]) }
            return result
        }
    }

    private static func milliseconds(_ seconds: TimeInterval) -> Int { max(0, Int(seconds * 1_000)) }

    static func endpointHash(_ url: URL) -> String {
        // Drop query, fragment and userinfo even before hashing; correlate calls without exporting identity.
        let endpoint = "\(url.scheme ?? "")://\(url.host ?? ""):\(url.port ?? 0)\(url.scheme == "data" ? "" : url.path)"
        return SHA256.hash(data: Data(endpoint.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
