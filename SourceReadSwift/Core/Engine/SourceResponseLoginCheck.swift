import Foundation
import JavaScriptCore

/// Evaluates one response hook without changing the shared JavaScript network API.
enum SourceResponseLoginCheck {
    private static let maximumResends = 8

    static func evaluate(_ script: String, response: SourceResponse, context: RuleExecutionContext,
                         resend: @escaping () -> Result<SourceResponse, SourceEngineError>)
        -> Result<SourceResponse, SourceEngineError> {
        let runtime = context.jsRuntime(ajaxHandler: { context.networkHandler?($0) ?? "" })
        let javascript = runtime.context
        context.ingestResponse(response)
        var responses = [response]
        var resendCount = 0
        var resendFailure: SourceEngineError?
        let resendResponse: @convention(block) () -> NSDictionary = {
            guard resendCount < maximumResends else {
                resendFailure = .javascript("loginCheckJs 重发请求超过 8 次限制")
                return ["failure": "loginCheckJs 重发请求超过 8 次限制"]
            }
            resendCount += 1
            switch resend() {
            case .success(let next):
                context.ingestResponse(next)
                responses.append(next)
                return metadata(next) as NSDictionary
            case .failure(let error):
                resendFailure = error
                return ["failure": "loginCheckJs 重发请求失败"]
            }
        }
        javascript.exception = nil
        let factory = javascript.evaluateScript(bridgeScript)
        guard let session = factory?.call(withArguments: [metadata(response), resendResponse]),
              javascript.exception == nil, !session.isUndefined, !session.isNull,
              let original = session.objectForKeyedSubscript("response") else {
            return .failure(.javascript("loginCheckJs 响应桥构建失败"))
        }
        defer { session.objectForKeyedSubscript("restore")?.call(withArguments: []) }
        var bindings = context.snapshot()
        bindings["result"] = original
        bindings["baseUrl"] = response.url.absoluteString
        var replacement: [String: Any]?
        var extractionFailed = false
        let evaluated = runtime.evaluate(script, variables: bindings) { completion in
            let extracted = session.objectForKeyedSubscript("extract")?.call(withArguments: [completion])
            extractionFailed = javascript.exception != nil
            if let extracted, !extracted.isNull, !extracted.isUndefined {
                replacement = extracted.toDictionary() as? [String: Any]
            }
        }
        // A script may catch the bridge exception; exhausted or cancelled requests still fail the stage.
        if let resendFailure { return .failure(resendFailure) }
        if case .failure(let error) = evaluated { return .failure(error) }
        guard !extractionFailed else { return .failure(.javascript("loginCheckJs 返回的响应无法读取")) }
        guard let replacement else { return .success(response) }
        guard let address = replacement["url"] as? String, let url = URL(string: address),
              url.scheme != nil, let status = replacement["statusCode"] as? Int, (0...999).contains(status),
              let body = replacement["body"] as? String, let headers = replacement["headers"] as? [String: String] else {
            return .failure(.javascript("loginCheckJs 返回的响应缺少有效 URL、状态码或正文"))
        }
        if let retained = responses.first(where: {
            $0.url == url && $0.statusCode == status && $0.headers == headers && $0.body == body
        }) { return .success(retained) }
        return .success(SourceResponse(url: url, statusCode: status, headers: headers, body: body,
            data: Data(body.utf8), bodyWasDecoded: true))
    }

    private static func metadata(_ response: SourceResponse) -> [String: Any] {
        ["url": response.url.absoluteString, "statusCode": response.statusCode,
         "headers": response.headers, "body": response.body, "bytes": Array(response.data)]
    }

    private static let bridgeScript = #"""
    (function(metadata, resend) {
        var previous = java.getStrResponse;
        function wrap(response) {
            if (response.failure) throw new Error(response.failure);
            var wrapped = __bridgeResponse('', response.url, response);
            wrapped.code = wrapped.statusCode;
            return wrapped;
        }
        var original = wrap(metadata);
        java.getStrResponse = function(url, rule) {
            if (url == null && rule == null) return wrap(resend());
            return previous.apply(this, arguments);
        };
        return {
            response: original,
            restore: function() { java.getStrResponse = previous; },
            extract: function(response) {
                if (!response || typeof response.body !== 'function') return null;
                var body = response.body();
                var url = typeof response.url === 'function' ? response.url() : response.url;
                var code = typeof response.code === 'function' ? response.code() :
                    (typeof response.statusCode === 'function' ? response.statusCode() : response.statusCode);
                var rawHeaders = typeof response.headers === 'function' ? response.headers() : response.headers;
                if (rawHeaders && typeof rawHeaders.toJSON === 'function') rawHeaders = rawHeaders.toJSON();
                var headers = {};
                for (var key in (rawHeaders || {})) {
                    if (Object.prototype.hasOwnProperty.call(rawHeaders, key) && typeof rawHeaders[key] === 'string') {
                        headers[key] = rawHeaders[key];
                    }
                }
                return {url: String(url || ''), statusCode: Number(code),
                    headers: headers, body: body == null ? '' : String(body)};
            }
        };
    })
    """#
}
