import Foundation

/// Downloaded payload for a remote import link.
struct SourceImportPayload: Equatable, Sendable {
    let url: URL
    let statusCode: Int
    let headers: [String: String]
    let data: Data
    let text: String
}

/// Abstraction over the import download so tests can supply canned responses
/// without touching the network.
protocol SourceImportDownloading: Sendable {
    func download(from rawURL: String) async -> Result<SourceImportPayload, SourceImportError>
}

/// Downloads book-source exports from HTTP(S) URLs.
///
/// This deliberately reuses `URLSessionSourceNetworkClient` instead of
/// `URLSession.shared`: community sources live on hosts with expired
/// certificates, GBK responses, relative redirects and Cloudflare challenges.
/// The engine client already solved those problems for chapter downloads, so
/// the import path now shares the same redirect, cookie and charset behaviour.
struct SourceImportDownloader: SourceImportDownloading, Sendable {
    static let defaultMaximumBytes = 20 * 1024 * 1024

    private let client: any SourceNetworkClient
    private let maximumBytes: Int
    private let timeout: TimeInterval

    init(
        client: any SourceNetworkClient = URLSessionSourceNetworkClient(),
        maximumBytes: Int = SourceImportDownloader.defaultMaximumBytes,
        timeout: TimeInterval = 30
    ) {
        self.client = client
        self.maximumBytes = maximumBytes
        self.timeout = timeout
    }

    func download(from rawURL: String) async -> Result<SourceImportPayload, SourceImportError> {
        guard let url = SourceImportURLNormalizer.url(from: rawURL) else {
            return .failure(.invalidURL(rawURL))
        }

        let request = SourceRequest(
            url: url,
            method: .get,
            headers: Self.requestHeaders,
            body: nil,
            expectedCharset: nil,
            timeout: timeout
        )

        switch await client.load(request) {
        case .failure(let error):
            return .failure(.network(error.localizedDescription))
        case .success(let response):
            guard (200...299).contains(response.statusCode) else {
                return .failure(.httpStatus(response.statusCode))
            }
            if let declared = Self.contentLength(in: response.headers), declared > maximumBytes {
                return .failure(.responseTooLarge(declared))
            }
            guard response.data.count <= maximumBytes else {
                return .failure(.responseTooLarge(response.data.count))
            }
            guard !response.data.isEmpty else {
                return .failure(.emptyResponse)
            }
            if Self.looksLikeChallenge(text: response.body, headers: response.headers) {
                return .failure(.challengePage)
            }
            if Self.looksLikeHTMLErrorPage(text: response.body) {
                return .failure(.notSourceJSON)
            }
            return .success(SourceImportPayload(
                url: response.url,
                statusCode: response.statusCode,
                headers: response.headers,
                data: response.data,
                text: response.body
            ))
        }
    }

    static let requestHeaders: [String: String] = [
        "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1 SourceReadSwift",
        "Accept": "application/json,text/plain,*/*",
        "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8"
    ]

    private static func contentLength(in headers: [String: String]) -> Int? {
        guard let raw = headerValue("Content-Length", in: headers) else { return nil }
        return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func headerValue(_ name: String, in headers: [String: String]) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// Detects Cloudflare / JS challenge interstitials that return HTTP 200.
    ///
    /// A valid export always starts with `{` or `[`, so JSON wins before any
    /// marker scan: a source whose search rule contains the words
    /// "checking your browser" must never be rejected as a challenge page.
    static func looksLikeChallenge(text: String, headers: [String: String]) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return false }

        let lower = trimmed.lowercased()
        let looksLikeHTML = lower.contains("<html")
            || lower.contains("<!doctype")
            || lower.contains("<head")
            || lower.contains("<body")
        guard looksLikeHTML else { return false }

        let markers = [
            "challenge-platform",
            "cf-chl",
            "__cf_chl_",
            "checking your browser",
            "just a moment",
            "attention required",
            "enable javascript and cookies",
            "cf-browser-verification",
            "ddos protection by",
            "verify you are human"
        ]
        let hits = markers.filter { lower.contains($0) }
        guard !hits.isEmpty else { return false }

        let server = headerValue("Server", in: headers)?.lowercased() ?? ""
        let hasCloudflareHeader = headers.keys.contains { $0.lowercased().hasPrefix("cf-") }
        return hits.count >= 2
            || lower.contains("cloudflare")
            || server.contains("cloudflare")
            || hasCloudflareHeader
    }

    private static func looksLikeHTMLErrorPage(text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("<!doctype html") || trimmed.hasPrefix("<html")
    }
}

/// Rewrites share links into the raw file URL the server actually serves.
///
/// Users paste whatever the browser address bar shows: a GitHub `blob` page,
/// a Gitee `blob` page, a GitLab `-/blob/` page, or a Bitbucket `src` page.
/// All of them return HTML, which is why the old import path failed with an
/// opaque JSON decoding error.
enum SourceImportURLNormalizer {
    private static let trailingPunctuation = CharacterSet(
        charactersIn: ".,;:!?)]}>\"'\u{FF0C}\u{3002}\u{FF1B}\u{FF1A}\u{FF01}\u{FF1F}\u{FF09}\u{3011}\u{300B}\u{3001}"
    )

    static func normalizedString(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'<>"))
        if text.hasPrefix("("), text.hasSuffix(")") {
            text = String(text.dropFirst().dropLast())
        }
        while let last = text.last,
              last.unicodeScalars.allSatisfy({ trailingPunctuation.contains($0) }) {
            text.removeLast()
        }
        guard !text.isEmpty else { return "" }

        var lower = text.lowercased()
        if !lower.hasPrefix("http://"), !lower.hasPrefix("https://") {
            let knownHosts = [
                "github.com/",
                "raw.githubusercontent.com/",
                "gitee.com/",
                "gitlab.com/",
                "bitbucket.org/",
                "cdn.jsdelivr.net/"
            ]
            if knownHosts.contains(where: { lower.hasPrefix($0) }) {
                text = "https://" + text
                lower = text.lowercased()
            }
        }

        guard var components = URLComponents(string: text),
              let host = components.host?.lowercased() else {
            return text
        }

        var path = components.path
        switch host {
        case "github.com", "www.github.com":
            guard path.contains("/blob/") else { return text }
            components.scheme = "https"
            components.host = "raw.githubusercontent.com"
            components.path = path.replacingOccurrences(of: "/blob/", with: "/")
            return components.url?.absoluteString ?? text
        case "gitee.com", "www.gitee.com":
            guard path.contains("/blob/") else { return text }
            components.scheme = "https"
            components.host = "gitee.com"
            components.path = path.replacingOccurrences(of: "/blob/", with: "/raw/")
            return components.url?.absoluteString ?? text
        case "gitlab.com", "www.gitlab.com":
            guard path.contains("/-/blob/") else { return text }
            components.scheme = "https"
            components.host = "gitlab.com"
            components.path = path.replacingOccurrences(of: "/-/blob/", with: "/-/raw/")
            return components.url?.absoluteString ?? text
        case "bitbucket.org", "www.bitbucket.org":
            guard path.contains("/src/") else { return text }
            components.scheme = "https"
            components.host = "bitbucket.org"
            components.path = path.replacingOccurrences(of: "/src/", with: "/raw/")
            return components.url?.absoluteString ?? text
        default:
            _ = path
            return text
        }
    }

    static func url(from raw: String) -> URL? {
        let normalized = normalizedString(raw)
        guard !normalized.isEmpty else { return nil }

        if let url = URL(string: normalized),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https",
           url.host != nil {
            return url
        }

        guard let encoded = normalized.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encoded),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }
        return url
    }
}