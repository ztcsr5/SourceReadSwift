import Foundation

/// Converts low-level source failures into actionable states shown in the source manager.
/// This is intentionally deterministic so batch diagnostics and XCTest use the same policy.
enum SourceDiagnosticClassifier {
    static func kind(
        message: String,
        stage: String,
        resultCount: Int = 0,
        contentIsEmpty: Bool = false
    ) -> SourceDiagnosticFailureKind {
        let value = "\(stage) \(message)".lowercased()
        if containsAny(value, ["测试关键词为空", "empty keyword", "invalid input"]) {
            return .invalidInput
        }
        if containsAny(value, ["cloudflare", "cf-chl", "challenge-platform", "captcha", "人机验证", "安全验证", "验证页面", "请输入验证码", "verification", "getverificationcode", "actyzm"]) {
            return .verification
        }
        if containsAny(value, ["401", "unauthorized", "未登录", "登录后", "cookie", "需要登录", "session expired", "请先登录"]) {
            return .authentication
        }
        if containsAny(value, ["403", "forbidden", "access denied", "blocked", "被拦截", "拒绝访问", "封禁", "rate limit", "429"]) {
            return .blocked
        }
        if containsAny(value, ["timeout", "timed out", "超时"]) {
            return .timeout
        }
        if contentIsEmpty || containsAny(value, ["empty", "为空", "解析为空", "没有识别到"]) {
            return .emptyResult
        }
        if containsAny(value, ["unsupported", "不支持", "未实现"]) {
            return .unsupported
        }
        if containsAny(value, ["javascript", "js error", "脚本", "exception", "aes", "decrypt", "symmetriccrypto", "乱序"]) {
            return .javascript
        }
        if containsAny(value, ["parse", "parser", "rule", "解析", "规则", "jsonpath", "xpath", "selector", "gbk", "gb2312", "gb18030", "queryttf", "font-obf", "反爬"]) {
            return .parsing
        }
        if resultCount > 0 { return .unknown }
        return .network
    }

    static func kind(error: SourceEngineError, stage: String) -> SourceDiagnosticFailureKind {
        switch error {
        case .unsupported(let message):
            let detected = kind(message: message, stage: stage)
            return detected == .network ? .unsupported : detected
        case .invalidSource(let message):
            return containsAny(message.lowercased(), ["关键词为空", "empty keyword"]) ? .invalidInput : .invalidSource
        case .network(let message):
            let candidate = kind(message: message, stage: stage)
            return candidate == .network ? .network : candidate
        case .rule(let message):
            let candidate = kind(message: message, stage: stage)
            return candidate == .network ? .parsing : candidate
        case .javascript(let message):
            let candidate = kind(message: message, stage: stage)
            return candidate == .network ? .javascript : candidate
        case .blocked:
            return .blocked
        case .empty:
            return .emptyResult
        }
    }

    static func status(
        message: String,
        stage: String,
        resultCount: Int = 0,
        contentIsEmpty: Bool = false
    ) -> SourceHealthStatus {
        let value = "\(stage) \(message)".lowercased()
        switch kind(message: message, stage: stage, resultCount: resultCount, contentIsEmpty: contentIsEmpty) {
        case .verification:
            return .verificationRequired
        case .authentication:
            return .requiresLogin
        case .blocked:
            return .blocked
        case .emptyResult, .timeout:
            return .warning
        case .invalidSource, .invalidInput, .unsupported, .javascript, .parsing, .network, .cancelled, .unknown:
            if containsAny(value, ["invalid source", "无效书源", "书源 url"]) { return .failed }
            if resultCount > 0 { return .passed }
            return .failed
        }
    }

    struct SniffedDiagnostic: Sendable {
        let kind: SourceDiagnosticFailureKind
        let status: SourceHealthStatus
        let classification: String
        let summary: String
    }

    /// Deep inspection of response body snippet and HTTP status to detect WAF,
    /// Cloudflare challenges, anti-bot sliders, and API business error codes.
    static func sniffSnippet(
        snippet: String?,
        statusCode: Int?,
        decodedByteCount: Int? = nil,
        stage: String
    ) -> SniffedDiagnostic? {
        guard let snippet = snippet, !snippet.isEmpty else {
            if statusCode == 403 {
                return SniffedDiagnostic(
                    kind: .blocked,
                    status: .blocked,
                    classification: "blocked(\"HTTP 403 源站拒绝访问\")",
                    summary: "HTTP 403 源站拒绝访问 (WAF/防爬)"
                )
            }
            if statusCode == 200 && (decodedByteCount ?? 0) <= 30 {
                return SniffedDiagnostic(
                    kind: .emptyResult,
                    status: .warning,
                    classification: "empty(\"源站返回空响应流 (\(decodedByteCount ?? 0) 字节)\")",
                    summary: "源站响应内容为空 (仅 \(decodedByteCount ?? 0) 字节)"
                )
            }
            return nil
        }

        let lower = snippet.lowercased()

        // 1. Regional block / WAF block
        if containsAny(lower, ["<title>地区拦截</title>", "地区拦截", "访问受限", "地域限制", "ip受限", "站点已开启防护", "waf拦截"]) {
            return SniffedDiagnostic(
                kind: .blocked,
                status: .blocked,
                classification: "blocked(\"源站地区拦截/WAF防护\")",
                summary: "源站拦截: 地区限制或WAF防火墙"
            )
        }

        // 2. Cloudflare 5s shield / Turnstile challenge
        if containsAny(lower, ["cf-chl", "challenge-platform", "turnstile", "just a moment...", "attention required! | cloudflare", "cf-mitigated"]) {
            return SniffedDiagnostic(
                kind: .blocked,
                status: .blocked,
                classification: "blocked(\"Cloudflare 5秒盾/质询防护\")",
                summary: "源站受 Cloudflare 5秒盾质询保护"
            )
        }

        // 3. Third-party slider / verification
        if containsAny(lower, ["bdturing", "turing", "geetest", "极验", "顶象", "dx-captcha", "滑动验证", "拖动滑块", "点选验证码"]) {
            return SniffedDiagnostic(
                kind: .verification,
                status: .verificationRequired,
                classification: "verification(\"第三方安全滑块验证\")",
                summary: "需要完成安全滑块人机验证"
            )
        }

        // 4. JSON API error responses (e.g. {"code": 1055, "message": "没有该小说呢！"})
        if snippet.hasPrefix("{"), let data = snippet.data(using: .utf8) {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let codeVal = obj["code"] ?? obj["status"] ?? obj["errorCode"]
                let msgVal = obj["message"] ?? obj["msg"] ?? obj["info"] ?? obj["error"]
                if let code = codeVal {
                    let codeStr = String(describing: code)
                    let msgStr = (msgVal as? String) ?? (msgVal != nil ? String(describing: msgVal!) : "")
                    // Check if non-success code
                    if !["0", "200", "true", "success"].contains(codeStr.lowercased()) {
                        if ["1055"].contains(codeStr) || containsAny(msgStr.lowercased(), ["没有该小说", "未找到", "无结果", "no novel", "not found"]) {
                            let displayMsg = msgStr.isEmpty ? "无相关书籍" : msgStr
                            return SniffedDiagnostic(
                                kind: .emptyResult,
                                status: .warning,
                                classification: "empty(\"API提示: \(displayMsg) (代码 \(codeStr))\")",
                                summary: "API提示: \(displayMsg)"
                            )
                        } else if ["401", "403", "-1"].contains(codeStr) && containsAny(msgStr.lowercased(), ["token", "auth", "login", "登录", "授权", "未登录"]) {
                            let displayMsg = msgStr.isEmpty ? "需要登录或Token已过期" : msgStr
                            return SniffedDiagnostic(
                                kind: .authentication,
                                status: .requiresLogin,
                                classification: "auth(\"API未授权: \(displayMsg) (代码 \(codeStr))\")",
                                summary: "API未授权: \(displayMsg)"
                            )
                        } else {
                            let displayMsg = msgStr.isEmpty ? "业务返回码 \(codeStr)" : "\(msgStr) (\(codeStr))"
                            return SniffedDiagnostic(
                                kind: .emptyResult,
                                status: .warning,
                                classification: "apiError(\"API错误: \(displayMsg)\")",
                                summary: "API返回: \(displayMsg)"
                            )
                        }
                    }
                }
            }
        }

        // 5. HTTP 403 Forbidden
        if statusCode == 403 {
            return SniffedDiagnostic(
                kind: .blocked,
                status: .blocked,
                classification: "blocked(\"HTTP 403 源站拒绝访问\")",
                summary: "HTTP 403 源站拒绝访问 (WAF/防爬)"
            )
        }

        // 6. Suspiciously empty response
        if statusCode == 200 && (decodedByteCount ?? snippet.count) <= 30 {
            return SniffedDiagnostic(
                kind: .emptyResult,
                status: .warning,
                classification: "empty(\"源站返回空响应流 (\(decodedByteCount ?? snippet.count) 字节)\")",
                summary: "源站响应为空 (仅 \(decodedByteCount ?? snippet.count) 字节)"
            )
        }

        return nil
    }

    private static func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { value.contains($0.lowercased()) }
    }
}
