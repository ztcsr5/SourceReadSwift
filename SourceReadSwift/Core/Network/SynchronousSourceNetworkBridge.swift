import Foundation

/// Runs an injected async SourceNetworkClient from JavaScriptCore's synchronous
/// callback boundary.  A detached task is intentional: waiting on a task
/// scheduled on the cooperative executor from inside JSCore can deadlock.
struct SynchronousSourceNetworkBridge {
    static func loadResult(
        urlText: String,
        source: BookSource,
        network: SourceNetworkClient,
        timeout: TimeInterval? = nil,
        cookieHeader: String? = nil,
        persistentValues: [String: String] = [:],
        persistentState: RulePersistentState? = nil,
        cookieStore: SourceCookieStore? = nil,
        observeExchange: ((SourceRequest, Result<SourceResponse, SourceEngineError>?) -> Void)? = nil
    ) -> Result<SourceResponse, SourceEngineError>? {
        var values = persistentValues
        if cookieStore != nil {
            // Browser login can replace the session while this JS stack is
            // suspended. Its old automatic snapshot must not become an explicit header.
            values.removeValue(forKey: "cookieHeader")
        } else if let cookieHeader, !cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            values["cookieHeader"] = cookieHeader
        }
        let request = SourceRequestBuilder().buildPageRequest(
            source: source,
            urlText: urlText,
            persistentValues: values
        )
        let effectiveTimeout = timeout ?? request.timeout
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox()
        let requestTask = Task.detached(priority: nil) {
            defer { semaphore.signal() }
            // Legado 的 JS 网络调用同样走并发率限制（getConcurrentRecordBlocking）。
            let rateRule = SourceRateRule(request.concurrentRate)
            let rateKey = request.rateLimitKey
            if let rateRule, let rateKey {
                do { try await SourceRateLimiter.shared.acquire(key: rateKey, rule: rateRule) }
                catch {
                    box.store(.failure(.network("请求已取消")))
                    return
                }
            }
            defer {
                if let rateRule, let rateKey {
                    SourceRateLimiter.shared.release(key: rateKey, rule: rateRule)
                }
            }
            guard !Task.isCancelled else {
                box.store(.failure(.network("请求已取消")))
                return
            }
            let currentRequest: SourceRequest
            if let cookieStore {
                currentRequest = await requestWithCurrentCookies(request, store: cookieStore)
            } else {
                currentRequest = request
            }
            box.recordRequest(currentRequest)
            let result = await network.load(currentRequest)
            if let cookieStore, currentRequest.usesCookies, case .success(let response) = result {
                await cookieStore.storeSetCookieHeaders(response.headers, for: response.url)
            }
            box.store(result)
        }
        guard semaphore.wait(timeout: .now() + effectiveTimeout) == .success else {
            requestTask.cancel()
            observeExchange?(box.sentRequest() ?? request, nil)
            return nil
        }
        let result = box.load()?.map { response in
            let normalized = ResponseBodyDecoder().normalize(response, preferredCharset: request.expectedCharset)
            persistentState?.ingestResponse(normalized)
            return normalized
        }
        observeExchange?(box.sentRequest() ?? request, result)
        return result
    }

    static func loadResponse(
        urlText: String,
        source: BookSource,
        network: SourceNetworkClient,
        timeout: TimeInterval? = nil,
        cookieHeader: String? = nil,
        persistentValues: [String: String] = [:],
        persistentState: RulePersistentState? = nil,
        cookieStore: SourceCookieStore? = nil
    ) -> SourceResponse? {
        guard let result = loadResult(
            urlText: urlText,
            source: source,
            network: network,
            timeout: timeout,
            cookieHeader: cookieHeader,
            persistentValues: persistentValues,
            persistentState: persistentState,
            cookieStore: cookieStore
        ), case .success(let response) = result else { return nil }
        return response
    }

    static func loadBody(
        urlText: String,
        source: BookSource,
        network: SourceNetworkClient,
        timeout: TimeInterval? = nil,
        cookieHeader: String? = nil,
        persistentValues: [String: String] = [:],
        persistentState: RulePersistentState? = nil,
        cookieStore: SourceCookieStore? = nil
    ) -> String {
        loadResponse(
            urlText: urlText,
            source: source,
            network: network,
            timeout: timeout,
            cookieHeader: cookieHeader,
            persistentValues: persistentValues,
            persistentState: persistentState,
            cookieStore: cookieStore
        )?.body ?? ""
    }

    private static func requestWithCurrentCookies(_ request: SourceRequest, store: SourceCookieStore) async -> SourceRequest {
        guard request.usesCookies,
              !request.headers.keys.contains(where: { $0.caseInsensitiveCompare("Cookie") == .orderedSame }),
              let currentCookie = await store.cookieHeader(for: request.url), !currentCookie.isEmpty else { return request }
        var headers = request.headers
        headers["Cookie"] = currentCookie
        return SourceRequest(url: request.url, method: request.method, headers: headers, body: request.body,
            expectedCharset: request.expectedCharset, timeout: request.timeout,
            webView: request.webView, webJs: request.webJs, retry: request.retry,
            concurrentRate: request.concurrentRate, rateLimitKey: request.rateLimitKey,
            shouldReturnInlineHex: request.shouldReturnInlineHex, usesCookies: request.usesCookies)
    }

    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Result<SourceResponse, SourceEngineError>?
        private var request: SourceRequest?

        func recordRequest(_ request: SourceRequest) {
            lock.lock(); self.request = request; lock.unlock()
        }

        func sentRequest() -> SourceRequest? {
            lock.lock(); defer { lock.unlock() }; return request
        }

        func store(_ value: Result<SourceResponse, SourceEngineError>) {
            lock.lock(); self.value = value; lock.unlock()
        }

        func load() -> Result<SourceResponse, SourceEngineError>? {
            lock.lock(); defer { lock.unlock() }
            return value
        }
    }
}
