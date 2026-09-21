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
        // Novel hosts frequently return non-ASCII Location headers (e.g. unencoded Chinese queries)
        // or redirect to mirror domains. Foundation throws NSURLErrorBadURL (-1000) if the Location
        // header contains non-ASCII bytes or special characters. We sanitize it here.
        var sanitized = request
        // 1. Foundation automatically strips custom and sensitive headers on cross-domain redirect.
        // Re-inject the original request headers (User-Agent, Cookie, Referer, Accept) so target mirrors accept the request.
        if let originalHeaders = task.originalRequest?.allHTTPHeaderFields {
            for (key, value) in originalHeaders {
                if sanitized.value(forHTTPHeaderField: key) == nil {
                    sanitized.setValue(value, forHTTPHeaderField: key)
                }
            }
        }
        if sanitized.value(forHTTPHeaderField: "User-Agent") == nil {
            sanitized.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        }

        // 2. Parse and sanitize target Location
        if let location = response.allHeaderFields["Location"] as? String ?? response.allHeaderFields["location"] as? String {
            let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = response.url ?? task.originalRequest?.url
            var targetURL: URL? = nil
            if let base {
                targetURL = URL(string: trimmedLocation, relativeTo: base)?.absoluteURL
            }
            if targetURL == nil {
                if let encoded = trimmedLocation.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.union(.urlPathAllowed)) {
                    if let base {
                        targetURL = URL(string: encoded, relativeTo: base)?.absoluteURL
                    } else {
                        targetURL = URL(string: encoded)
                    }
                }
            }
            if let targetURL {
                sanitized.url = targetURL
            }
        }

        guard let targetURL = sanitized.url,
              let scheme = targetURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            // Abort redirect to invalid or non-HTTP scheme, deliver current response
            completionHandler(nil)
            return
        }
        completionHandler(sanitized)
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
        var urlRequest = URLRequest(url: request.url, timeoutInterval: request.timeout)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        if request.headers["Cookie"] == nil, let cookieHeader = await cookieStore.cookieHeader(for: request.url) {
            urlRequest.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        do {
            let (data, response) = try await session.data(for: urlRequest, delegate: Self.sessionDelegate)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.network("响应不是 HTTPURLResponse"))
            }
            return await processResponse(data: data, http: http, request: request)
        } catch let urlError as URLError {
            // 1. Automatic HTTP Fallback when HTTPS fails with TLS/certificate/connection error
            if request.url.scheme?.lowercased() == "https",
               (urlError.code == .secureConnectionFailed ||
                urlError.code == .serverCertificateUntrusted ||
                urlError.code == .serverCertificateHasBadDate ||
                urlError.code == .serverCertificateNotYetValid ||
                urlError.code == .serverCertificateHasUnknownRoot ||
                urlError.code == .cannotConnectToHost ||
                urlError.code == .networkConnectionLost) {
                if let httpURL = URL(string: request.url.absoluteString.replacingOccurrences(of: "https://", with: "http://", options: .anchored)) {
                    var httpReq = urlRequest
                    httpReq.url = httpURL
                    if let (data, response) = try? await session.data(for: httpReq, delegate: Self.sessionDelegate),
                       let http = response as? HTTPURLResponse,
                       (200...399).contains(http.statusCode) {
                        return await processResponse(data: data, http: http, request: request)
                    }
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
