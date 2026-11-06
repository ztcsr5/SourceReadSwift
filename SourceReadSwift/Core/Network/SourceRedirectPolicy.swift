import Foundation

struct SourceRedirectRequest: Sendable {
    let url: URL
    let method: SourceHTTPMethod
    let headers: [String: String]
    let body: Data?
}

/// Apply identical origin, credential and method rules to HTTP and HTML redirects.
enum SourceRedirectPolicy {
    static func redirect(_ current: SourceRedirectRequest, to target: URL, statusCode: Int) throws -> SourceRedirectRequest {
        guard let scheme = target.scheme?.lowercased(), ["http", "https"].contains(scheme),
              target.host?.isEmpty == false, target.user == nil, target.password == nil else {
            throw SourceEngineError.network("书源跳转被拒绝：目标必须是不含账号密码的 HTTP(S) 地址")
        }
        guard current.url.scheme?.lowercased() != "https" || scheme == "https" else {
            throw SourceEngineError.network("书源跳转被拒绝：HTTPS 不能自动降级为明文 HTTP")
        }
        let isSameOrigin = sameOrigin(current.url, target)
        let changesToGET = [200, 301, 302, 303].contains(statusCode)
        if !isSameOrigin, !changesToGET,
           current.body != nil || (current.method != .get && current.method != .head) {
            throw SourceEngineError.network("书源跳转被拒绝：不能向其他站点重放请求正文")
        }
        // Source authors can name custom token headers arbitrarily; a denylist
        // cannot reliably identify them, so only representation headers survive.
        let forwarded = Set(["accept", "accept-language", "user-agent", "range"])
        var headers = isSameOrigin ? current.headers : current.headers.filter { forwarded.contains($0.key.lowercased()) }
        headers = headers.filter { $0.key.lowercased() != "referer" }
        if isSameOrigin {
            var referer = URLComponents(url: current.url, resolvingAgainstBaseURL: true)
            referer?.user = nil
            referer?.password = nil
            referer?.query = nil
            referer?.fragment = nil
            headers["Referer"] = referer?.url?.absoluteString
        } else {
            var origin = URLComponents(url: target, resolvingAgainstBaseURL: true)
            origin?.path = "/"
            origin?.query = nil
            origin?.fragment = nil
            headers["Referer"] = origin?.url?.absoluteString
        }
        if changesToGET {
            headers = headers.filter { !["content-type", "content-length", "origin"].contains($0.key.lowercased()) }
        }
        return SourceRedirectRequest(url: target,
                                     method: changesToGET && current.method != .head ? .get : current.method,
                                     headers: headers, body: changesToGET ? nil : current.body)
    }

    private static func sameOrigin(_ first: URL, _ second: URL) -> Bool {
        first.scheme?.lowercased() == second.scheme?.lowercased()
            && first.host?.lowercased() == second.host?.lowercased()
            && effectivePort(first) == effectivePort(second)
    }

    private static func effectivePort(_ url: URL) -> Int {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
    }
}
