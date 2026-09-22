import Foundation

enum SourceHTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
    case options = "OPTIONS"
}

struct SourceRequest: Sendable {
    let url: URL
    let method: SourceHTTPMethod
    let headers: [String: String]
    let body: Data?
    let expectedCharset: String?
    let timeout: TimeInterval
}

struct SourceResponse: Sendable {
    let url: URL
    let statusCode: Int
    let headers: [String: String]
    let body: String
    let data: Data
    /// Byte count before transport decoding when the adapter supplied a
    /// compressed payload.  Plain text-only fixtures leave this nil.
    let encodedByteCount: Int?
    /// True when `data`/`body` were produced by decoding Content-Encoding.
    let bodyWasDecoded: Bool
    /// Normalized Content-Encoding tokens observed on the response.
    let contentEncodings: [String]

    init(
        url: URL,
        statusCode: Int,
        headers: [String: String],
        body: String,
        data: Data,
        encodedByteCount: Int? = nil,
        bodyWasDecoded: Bool = false,
        contentEncodings: [String] = []
    ) {
        self.url = url
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.data = data
        self.encodedByteCount = encodedByteCount
        self.bodyWasDecoded = bodyWasDecoded
        self.contentEncodings = contentEncodings
    }
}

protocol SourceNetworkClient: Sendable {
    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError>
}

/// Allows book source HTTP requests to connect to community novel hosts with
/// expired, self-signed, or Let's Encrypt certificates, matching Android Legado's
/// default OkHttpClient `trustAllCerts` behavior.
final class InsecureTrustSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Disabling automatic redirects gives us full control over redirect loops,
        // mirroring OkHttp's RetryAndFollowUpInterceptor in Android Legado.
        // It prevents CFNetwork from prematurely failing with kCFURLErrorBadURL (-1000)
        // when Location headers contain GBK bytes, unencoded spaces, or cross-domain redirects.
        completionHandler(nil)
    }
}

final class URLSessionSourceNetworkClient: SourceNetworkClient, @unchecked Sendable {
    private static let sessionDelegate = InsecureTrustSessionDelegate()
    private static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: nil)
    }()

    private let session: URLSession
    private let cookieStore: SourceCookieStore

    init(session: URLSession? = nil, cookieStore: SourceCookieStore = SourceCookieStore()) {
        self.session = session ?? Self.defaultSession
        self.cookieStore = cookieStore
    }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        var currentURL = request.url
        var currentMethod = request.method
        var currentBody = request.body
        var currentHeaders = request.headers
        var redirectCount = 0
        let maxRedirects = 10

        while redirectCount <= maxRedirects {
            if currentURL.scheme?.lowercased() == "data" {
                return handleDataURL(currentURL)
            }
            var urlRequest = URLRequest(url: currentURL, timeoutInterval: request.timeout)
            urlRequest.httpMethod = currentMethod.rawValue
            urlRequest.httpBody = currentBody
            for (key, value) in currentHeaders {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
            if currentHeaders["Cookie"] == nil, let cookieHeader = await cookieStore.cookieHeader(for: currentURL) {
                urlRequest.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            }

            var responseData: Data? = nil
            var httpResponse: HTTPURLResponse? = nil

            do {
                let (data, response) = try await session.data(for: urlRequest, delegate: Self.sessionDelegate)
                if let http = response as? HTTPURLResponse {
                    responseData = data
                    httpResponse = http
                } else {
                    return .failure(.network("响应不是 HTTPURLResponse"))
                }
            } catch let urlError as URLError {
                // 1. Automatic HTTP Fallback when HTTPS fails with TLS/certificate/connection error
                if currentURL.scheme?.lowercased() == "https",
                   (urlError.code == .secureConnectionFailed ||
                    urlError.code == .serverCertificateUntrusted ||
                    urlError.code == .serverCertificateHasBadDate ||
                    urlError.code == .serverCertificateNotYetValid ||
                    urlError.code == .serverCertificateHasUnknownRoot ||
                    urlError.code == .cannotConnectToHost ||
                    urlError.code == .networkConnectionLost) {
                    if let httpURL = URL(string: currentURL.absoluteString.replacingOccurrences(of: "https://", with: "http://", options: .anchored)) {
                        currentURL = httpURL
                        continue
                    }
                }

                if urlError.code == .badURL {
                    return .failure(.network("URL 格式非法或解析异常 (-1000)"))
                } else if urlError.code == .timedOut {
                    return .failure(.network("连接超时"))
                } else if urlError.code == .cannotFindHost || urlError.code == .cannotConnectToHost {
                    return .failure(.network("无法连接到服务器或域名未解析"))
                }
                return .failure(.network(urlError.localizedDescription))
            } catch {
                return .failure(.network(error.localizedDescription))
            }

            guard let data = responseData, let http = httpResponse else {
                return .failure(.network("响应不是 HTTPURLResponse"))
            }

            // Check for 3xx redirect
            if (300...399).contains(http.statusCode),
               let location = http.allHeaderFields["Location"] as? String ?? http.allHeaderFields["location"] as? String,
               !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                redirectCount += 1
                if redirectCount > maxRedirects {
                    return .failure(.network("重定向次数过多 (\(redirectCount))"))
                }

                guard let nextURL = resolveRedirectLocation(location, relativeTo: currentURL) else {
                    return .failure(.network("重定向地址无效: \(location)"))
                }

                // Preserve / store cookies from redirect response
                let respHeaders = http.allHeaderFields.reduce(into: [String: String]()) { res, item in
                    res[String(describing: item.key)] = String(describing: item.value)
                }
                await cookieStore.storeSetCookieHeaders(respHeaders, for: currentURL)

                // Update Referer
                currentHeaders["Referer"] = currentURL.absoluteString

                // HTTP RFC 7231: switch POST/PUT to GET on 301, 302, 303
                if http.statusCode == 301 || http.statusCode == 302 || http.statusCode == 303 {
                    currentMethod = .get
                    currentBody = nil
                    currentHeaders.removeValue(forKey: "Content-Type")
                    currentHeaders.removeValue(forKey: "Content-Length")
                    currentHeaders.removeValue(forKey: "Origin")
                }

                currentURL = nextURL
                continue
            }

            // Check for HTML meta-refresh or location redirect on HTTP 200
            if http.statusCode == 200, data.count < 4096 {
                let respHeaders = http.allHeaderFields.reduce(into: [String: String]()) { res, item in
                    res[String(describing: item.key)] = String(describing: item.value)
                }
                let peekText = ResponseTextDecoder().decode(data: data, headers: respHeaders, preferredCharset: request.expectedCharset)
                if let redirectTarget = extractHtmlRedirect(from: peekText),
                   let nextURL = resolveRedirectLocation(redirectTarget, relativeTo: currentURL),
                   nextURL != currentURL {
                    redirectCount += 1
                    if redirectCount <= maxRedirects {
                        await cookieStore.storeSetCookieHeaders(respHeaders, for: currentURL)
                        currentHeaders["Referer"] = currentURL.absoluteString
                        currentMethod = .get
                        currentBody = nil
                        currentHeaders.removeValue(forKey: "Content-Type")
                        currentHeaders.removeValue(forKey: "Content-Length")
                        currentHeaders.removeValue(forKey: "Origin")
                        currentURL = nextURL
                        continue
                    }
                }
            }

            return await processResponse(data: data, http: http, request: request)
        }

        return .failure(.network("重定向超出最大限制"))
    }

    private func extractHtmlRedirect(from body: String) -> String? {
        guard body.count < 4096 else { return nil }
        let nsBody = body as NSString
        let fullRange = NSRange(location: 0, length: nsBody.length)

        // 1. Meta refresh: <meta http-equiv="refresh" content="1;url=...">
        let metaPattern = #"(?i)<meta[^>]+http-equiv\s*=\s*['"]?refresh['"]?[^>]+content\s*=\s*['"]?\s*\d+\s*;\s*url\s*=\s*([^'"\s>]+)['"]?"#
        if let regex = try? NSRegularExpression(pattern: metaPattern),
           let match = regex.firstMatch(in: body, range: fullRange),
           match.numberOfRanges > 1 {
            let target = nsBody.substring(with: match.range(at: 1)).trimmingCharacters(in: CharacterSet(charactersIn: "'\" \t\r\n"))
            if !target.isEmpty { return target }
        }

        // Reverse order: <meta content="0;url=..." http-equiv="refresh">
        let metaPattern2 = #"(?i)<meta[^>]+content\s*=\s*['"]?\s*\d+\s*;\s*url\s*=\s*([^'"\s>]+)['"]?[^>]+http-equiv\s*=\s*['"]?refresh['"]?"#
        if let regex = try? NSRegularExpression(pattern: metaPattern2),
           let match = regex.firstMatch(in: body, range: fullRange),
           match.numberOfRanges > 1 {
            let target = nsBody.substring(with: match.range(at: 1)).trimmingCharacters(in: CharacterSet(charactersIn: "'\" \t\r\n"))
            if !target.isEmpty { return target }
        }

        // 2. JS location redirect: location.href = '...', window.location = '...'
        let jsPattern = #"(?i)(?:window\.)?location(?:\.href)?\s*=\s*['"]([^'"]+)['"]"#
        if let regex = try? NSRegularExpression(pattern: jsPattern),
           let match = regex.firstMatch(in: body, range: fullRange),
           match.numberOfRanges > 1 {
            let target = nsBody.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !target.isEmpty && (target.hasPrefix("/") || target.hasPrefix("http") || target.contains(".php") || target.contains(".html") || target.contains("?")) {
                return target
            }
        }

        // JS location.replace("...")
        let jsReplacePattern = #"(?i)(?:window\.)?location\.replace\s*\(\s*['"]([^'"]+)['"]\s*\)"#
        if let regex = try? NSRegularExpression(pattern: jsReplacePattern),
           let match = regex.firstMatch(in: body, range: fullRange),
           match.numberOfRanges > 1 {
            let target = nsBody.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !target.isEmpty && (target.hasPrefix("/") || target.hasPrefix("http") || target.contains(".php") || target.contains(".html") || target.contains("?")) {
                return target
            }
        }

        return nil
    }

    private func handleDataURL(_ url: URL) -> Result<SourceResponse, SourceEngineError> {
        let urlString = url.absoluteString
        guard let commaIndex = urlString.firstIndex(of: ",") else {
            return .failure(.network("无效的 data URL"))
        }
        let meta = String(urlString[..<commaIndex])
        let payload = String(urlString[urlString.index(after: commaIndex)...])
        let isBase64 = meta.contains(";base64")
        let data: Data
        if isBase64 {
            let clean = payload.replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
                .trimmingCharacters(in: .whitespaces)
            data = Data(base64Encoded: clean) ?? payload.data(using: .utf8) ?? Data()
        } else {
            data = payload.removingPercentEncoding?.data(using: .utf8) ?? payload.data(using: .utf8) ?? Data()
        }
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return .success(SourceResponse(
            url: url,
            statusCode: 200,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            body: text,
            data: data
        ))
    }

    private func resolveRedirectLocation(_ location: String, relativeTo base: URL) -> URL? {
        var trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("\n") || trimmed.contains("\r") {
            if let firstLine = trimmed.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Strip accidental double domain prefix, e.g. "http://domain.comhttp://target.com/..."
        if trimmed.count > 8 {
            let searchStart = trimmed.index(trimmed.startIndex, offsetBy: 7)
            if let secondSchemeRange = trimmed.range(of: "https?://", options: .regularExpression, range: searchStart..<trimmed.endIndex) {
                trimmed = String(trimmed[secondSchemeRange.lowerBound...])
            }
        }

        // Handle protocol-relative URL: //example.com/path
        if trimmed.hasPrefix("//") {
            let scheme = base.scheme ?? "http"
            trimmed = "\(scheme):\(trimmed)"
        }

        // 1. Direct standard URL resolution
        if let direct = URL(string: trimmed, relativeTo: base)?.absoluteURL,
           let scheme = direct.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return direct
        }

        // 2. Percent-encode unencoded non-ASCII or special characters (spaces, unicode)
        var allowed = CharacterSet.urlQueryAllowed
        allowed.formUnion(.urlPathAllowed)
        allowed.formUnion(.urlHostAllowed)
        allowed.insert("#")
        allowed.insert(":")
        allowed.insert("?")
        allowed.insert("&")
        allowed.insert("=")
        allowed.insert("/")

        if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) {
            if let resolved = URL(string: encoded, relativeTo: base)?.absoluteURL,
               let scheme = resolved.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                return resolved
            }
        }

        return nil
    }

    private func processResponse(
        data: Data,
        http: HTTPURLResponse,
        request: SourceRequest
    ) async -> Result<SourceResponse, SourceEngineError> {
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, item in
            result[String(describing: item.key)] = String(describing: item.value)
        }
        let (text, decodedData, decoded) = autoreleasepool { () -> (String, Data, ResponseBodyDecoder.DecodeResult) in
            let decoded = ResponseBodyDecoder().decodeResult(data: data, headers: headers)
            let decodedData = decoded.data
            let text = ResponseTextDecoder().decode(data: decodedData, headers: headers, preferredCharset: request.expectedCharset)
            return (text, decodedData, decoded)
        }
        await cookieStore.storeSetCookieHeaders(headers, for: http.url ?? request.url)
        return .success(SourceResponse(
            url: http.url ?? request.url,
            statusCode: http.statusCode,
            headers: headers,
            body: text,
            data: decodedData,
            encodedByteCount: decoded.wasDecoded ? data.count : nil,
            bodyWasDecoded: decoded.wasDecoded,
            contentEncodings: decoded.encodings
        ))
    }
}
