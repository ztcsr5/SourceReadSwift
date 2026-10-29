import Foundation

protocol SourceEngine: Sendable {
    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError>
    func exploreBooks(source: BookSource, url: String, page: Int) async -> Result<[SearchBook], SourceEngineError>
    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError>
    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError>
    func getChapterList(source: BookSource, book: BookDetail, maxPages: Int) async -> Result<[BookChapter], SourceEngineError>
    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError>
    func getContent(source: BookSource, chapter: BookChapter, maxPages: Int) async -> Result<ChapterContent, SourceEngineError>
    /// Executes a Legado `ruleContent.payAction` (purchase operation) with the
    /// same persistent state, cookies and JS runtime as the chapter request.
    func performPayAction(source: BookSource, chapter: BookChapter, payAction: String) async -> Result<PayActionOutcome, SourceEngineError>
    func verifyLogin(source: BookSource) async -> Result<SourceLoginVerification, SourceEngineError>
    /// Stores the `loginUi` form values where `source.getLoginInfoMap()` reads
    /// them, evaluates `loginUrl` as JS, then reports the `loginCheckJs`
    /// verdict.  Legado `BaseSource.login()` (BaseSource.kt L47-51).
    func login(source: BookSource, credentials: [String: String]) async -> Result<SourceLoginVerification, SourceEngineError>
}

extension SourceEngine {
    func exploreBooks(source: BookSource, url: String, page: Int) async -> Result<[SearchBook], SourceEngineError> {
        .failure(.rule("Explore not supported"))
    }

    func getChapterList(source: BookSource, book: BookDetail, maxPages: Int) async -> Result<[BookChapter], SourceEngineError> {
        await getChapterList(source: source, book: book)
    }

    func getContent(source: BookSource, chapter: BookChapter, maxPages: Int) async -> Result<ChapterContent, SourceEngineError> {
        await getContent(source: source, chapter: chapter)
    }

    func performPayAction(source: BookSource, chapter: BookChapter, payAction: String) async -> Result<PayActionOutcome, SourceEngineError> {
        .failure(.rule("Pay action is not supported by this engine"))
    }

    func login(source: BookSource, credentials: [String: String]) async -> Result<SourceLoginVerification, SourceEngineError> {
        .failure(.unsupported("Login is not supported by this engine"))
    }
}

protocol SourceWebViewFallbackControllable: AnyObject {
    var allowWebViewFallback: Bool { get set }
}

struct SourceLoginVerification: Equatable, Sendable {
    enum Status: String, Sendable, Equatable {
        case notConfigured
        case passed
        case requiresLogin
        case verificationRequired
        case blocked
        case warning
    }

    let status: Status
    let message: String
    let cookiePresent: Bool
}

extension SourceLoginVerification.Status {
    var displayTitle: String {
        switch self {
        case .notConfigured: return "INFO"
        case .passed: return "PASS"
        case .requiresLogin: return "LOGIN"
        case .verificationRequired: return "VERIFY"
        case .blocked: return "BLOCKED"
        case .warning: return "WARN"
        }
    }

    var healthStatus: SourceHealthStatus {
        switch self {
        case .notConfigured: return .warning
        case .passed: return .passed
        case .requiresLogin: return .requiresLogin
        case .verificationRequired: return .verificationRequired
        case .blocked: return .blocked
        case .warning: return .warning
        }
    }
}

extension SourceEngine {
    /// Engines that do not expose a login check remain fully source-compatible.
    func verifyLogin(source: BookSource) async -> Result<SourceLoginVerification, SourceEngineError> {
        .success(SourceLoginVerification(status: .notConfigured, message: "未配置 loginCheckJs", cookiePresent: false))
    }
}

final class LegadoSourceEngine: SourceEngine, SourceDiagnosticEvidenceProvider, SourceWebViewFallbackControllable, @unchecked Sendable {
    private let network: SourceNetworkClient
    private let diagnostics: DiagnosticSink
    private let cookieStore: SourceCookieStore
    private let purifyRules: () async -> [String]
    private let stateLock = NSLock()
    private var states: [String: RulePersistentState] = [:]
    private var stateAccessOrder: [String] = []
    static let maximumPersistentStates = 100
    private let evidenceLock = NSLock()
    private var evidence: [String: [SourceDiagnosticStage: SourceDiagnosticEvidence]] = [:]
    private let requestBuilder = SourceRequestBuilder()
    private let rateLimiter = SourceRateLimiter.shared
    private let searchURLResolver = SearchURLResolver()
    private let fallbackLock = NSLock()
    private var _allowWebViewFallback: Bool = true
    private let bookStateLock = NSLock()
    private var bookVariableDeltas: [String: [String: String]] = [:]
    private var bookVariableOrder: [String] = []
    static let maximumBookVariableEntries = 400

    var allowWebViewFallback: Bool {
        get {
            fallbackLock.lock()
            defer { fallbackLock.unlock() }
            return _allowWebViewFallback
        }
        set {
            fallbackLock.lock()
            defer { fallbackLock.unlock() }
            _allowWebViewFallback = newValue
        }
    }

    init(
        network: SourceNetworkClient? = nil,
        cookieStore: SourceCookieStore = SourceCookieStore(),
        diagnostics: DiagnosticSink = .noop,
        purifyRules: @escaping () async -> [String] = { [] }
    ) {
        self.cookieStore = cookieStore
        self.network = network ?? URLSessionSourceNetworkClient(cookieStore: cookieStore)
        self.diagnostics = diagnostics
        self.purifyRules = purifyRules
    }

    // MARK: - Per-book rule variables

    private func bookVariableKey(source: BookSource, bookURL: String) -> String {
        source.bookSourceUrl + "\u{1F}" + bookURL
    }

    /// Stores the variables written while one search row's `bookUrl` rule ran.
    /// Aggregators evaluate that rule for every row and reuse keys such as
    /// `id`, so without per-row capture the last row wins.
    private func storeBookVariables(source: BookSource, bookURL: String, delta: [String: String]) {
        guard !delta.isEmpty, !bookURL.isEmpty else { return }
        let key = bookVariableKey(source: source, bookURL: bookURL)
        bookStateLock.lock()
        bookVariableDeltas[key] = delta
        bookVariableOrder.removeAll { $0 == key }
        bookVariableOrder.append(key)
        while bookVariableOrder.count > Self.maximumBookVariableEntries {
            let evicted = bookVariableOrder.removeFirst()
            bookVariableDeltas.removeValue(forKey: evicted)
        }
        bookStateLock.unlock()
    }

    private func restoreBookVariables(source: BookSource, bookURL: String, into state: RulePersistentState) {
        guard !bookURL.isEmpty else { return }
        let key = bookVariableKey(source: source, bookURL: bookURL)
        bookStateLock.lock()
        let delta = bookVariableDeltas[key]
        bookStateLock.unlock()
        guard let delta else { return }
        for (name, value) in delta {
            state.put(value, for: name)
        }
    }

    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError> {
        let executionState = persistentState(for: source)
        let executionContext = RuleExecutionContext(persistentState: executionState, source: source, logHandler: { [diagnostics] message in
            Task { await diagnostics.emit(.init(level: .info, stage: "search.js", sourceName: source.bookSourceName, message: message)) }
        })
        defer { executionContext.cleanUp() }
        executionContext.setExecutionStage("search")
        attachVerificationCodeProvider(executionContext, source: source)
        executionContext.networkHandler = { [network] encoded in
            self.syncLoad(
                encoded: encoded,
                source: source,
                network: network,
                cookieHeader: executionContext.string(for: "cookieHeader"),
                persistentValues: executionState.snapshot(),
                persistentState: executionState
            )
        }
        executionContext.responseHandler = { [network] encoded in
            SynchronousSourceNetworkBridge.loadResponse(
                urlText: encoded,
                source: source,
                network: network,
                cookieHeader: executionContext.string(for: "cookieHeader"),
                persistentValues: executionState.snapshot(),
                persistentState: executionState
            )
        }
        await diagnostics.emit(.init(
            level: .info,
            stage: "search.prepare",
            sourceName: source.bookSourceName,
            message: "\u{51c6}\u{5907}\u{641c}\u{7d22}",
            details: ["keyword": keyword, "page": String(page)]
        ))

        let searchUrl: String
        switch searchURLResolver.resolve(source: source, keyword: keyword, page: page, persistentState: executionState, network: network, executionContext: executionContext) {
        case .success(let value):
            searchUrl = value
        case .failure(let error):
            await emitFailure(error, stage: "search.url", source: source)
            return .failure(error)
        }

        let request = requestBuilder.buildSearchRequest(
            source: source,
            searchUrl: searchUrl,
            keyword: keyword,
            page: page,
            persistentValues: executionState.snapshot()
        )
        switch await loadWithOptionalWebViewFallback(request, source: source, stage: "search.load") {
        case .success(let response):
            let transformedResponse = transformBodyIfNeeded(response, source: source, rules: [source.ruleSearch], network: network, stateOverride: executionState, executionContext: executionContext)
            recordJavaScriptEvidence(source: source, stage: "search", context: executionContext)
            guard !transformedResponse.body.isEmpty else {
                let error = SourceEngineError.empty("\u{641c}\u{7d22}\u{54cd}\u{5e94}\u{4e3a}\u{7a7a}")
                await emitFailure(error, stage: "search.empty", source: source, details: ["url": transformedResponse.url.absoluteString])
                return .failure(error)
            }
            var parser = SearchResultParser(executionContext: executionContext)
            parser.onBookVariables = { [weak self] bookURL, delta in
                self?.storeBookVariables(source: source, bookURL: bookURL, delta: delta)
            }
            let parsed = parser.parse(source: source, response: transformedResponse, keyword: keyword)
            if case .failure(let error) = parsed {
                await emitFailure(error, stage: "search.parse", source: source, details: ["url": transformedResponse.url.absoluteString])
            }
            return parsed
        case .failure(let error):
            await emitFailure(error, stage: "search.load", source: source, details: ["url": request.url.absoluteString])
            return .failure(error)
        }
    }

    func exploreBooks(source: BookSource, url: String, page: Int) async -> Result<[SearchBook], SourceEngineError> {
        let executionState = persistentState(for: source)
        let executionContext = RuleExecutionContext(persistentState: executionState, source: source, logHandler: { [diagnostics] message in
            Task { await diagnostics.emit(.init(level: .info, stage: "explore.js", sourceName: source.bookSourceName, message: message)) }
        })
        defer { executionContext.cleanUp() }
        executionContext.setExecutionStage("explore")
        attachVerificationCodeProvider(executionContext, source: source)
        executionContext.networkHandler = { [network] encoded in
            self.syncLoad(
                encoded: encoded,
                source: source,
                network: network,
                cookieHeader: executionContext.string(for: "cookieHeader"),
                persistentValues: executionState.snapshot(),
                persistentState: executionState
            )
        }
        executionContext.responseHandler = { [network] encoded in
            SynchronousSourceNetworkBridge.loadResponse(
                urlText: encoded,
                source: source,
                network: network,
                cookieHeader: executionContext.string(for: "cookieHeader"),
                persistentValues: executionState.snapshot(),
                persistentState: executionState
            )
        }
        await diagnostics.emit(.init(
            level: .info,
            stage: "explore.prepare",
            sourceName: source.bookSourceName,
            message: "准备分类发现",
            details: ["url": url, "page": String(page)]
        ))

        let request = requestBuilder.buildExploreRequest(
            source: source,
            exploreUrl: url,
            page: page,
            persistentValues: executionState.snapshot()
        )
        switch await loadWithOptionalWebViewFallback(request, source: source, stage: "explore.load") {
        case .success(let response):
            let transformedResponse = transformBodyIfNeeded(
                response,
                source: source,
                rules: [source.ruleExplore, source.ruleSearch],
                network: network,
                stateOverride: executionState,
                executionContext: executionContext
            )
            recordJavaScriptEvidence(source: source, stage: "explore", context: executionContext)
            guard !transformedResponse.body.isEmpty else {
                let error = SourceEngineError.empty("分类发现响应为空")
                await emitFailure(error, stage: "explore.empty", source: source, details: ["url": transformedResponse.url.absoluteString])
                return .failure(error)
            }
            var parser = SearchResultParser(executionContext: executionContext)
            parser.onBookVariables = { [weak self] bookURL, delta in
                self?.storeBookVariables(source: source, bookURL: bookURL, delta: delta)
            }
            let parsed = parser.parse(
                source: source,
                response: transformedResponse,
                ruleOverride: source.ruleExplore
            )
            if case .failure(let error) = parsed {
                await emitFailure(error, stage: "explore.parse", source: source, details: ["url": transformedResponse.url.absoluteString])
            }
            return parsed
        case .failure(let error):
            await emitFailure(error, stage: "explore.load", source: source, details: ["url": request.url.absoluteString])
            return .failure(error)
        }
    }

    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError> {
        let executionState = persistentState(for: source)
        restoreBookVariables(source: source, bookURL: book.bookUrl, into: executionState)
        let executionContext = RuleExecutionContext(persistentState: executionState, source: source, logHandler: { [diagnostics] message in
            Task { await diagnostics.emit(.init(level: .info, stage: "detail.js", sourceName: source.bookSourceName, message: message)) }
        })
        defer { executionContext.cleanUp() }
        executionContext.setExecutionStage("detail")
        attachVerificationCodeProvider(executionContext, source: source)
        executionContext.networkHandler = { [network] encoded in
            self.syncLoad(
                encoded: encoded,
                source: source,
                network: network,
                cookieHeader: executionContext.string(for: "cookieHeader"),
                persistentValues: executionState.snapshot(),
                persistentState: executionState
            )
        }
        executionContext.responseHandler = { [network] encoded in
            SynchronousSourceNetworkBridge.loadResponse(
                urlText: encoded,
                source: source,
                network: network,
                cookieHeader: executionContext.string(for: "cookieHeader"),
                persistentValues: executionState.snapshot(),
                persistentState: executionState
            )
        }
        let resolvedBookUrl = DynamicURLResolver.resolve(
            book.bookUrl,
            baseUrl: book.bookUrl.nilIfEmpty ?? source.cleanSourceURL,
            source: source,
            variables: ["book": book],
            context: executionContext
        )
        let request = requestBuilder.buildPageRequest(
            source: source,
            urlText: resolvedBookUrl,
            persistentValues: executionState.snapshot()
        )
        switch await loadWithOptionalWebViewFallback(request, source: source, stage: "detail.load") {
        case .success(let response):
            let transformedResponse = transformBodyIfNeeded(response, source: source, rules: [source.ruleBookInfo], network: network, stateOverride: executionState, executionContext: executionContext)
            recordJavaScriptEvidence(source: source, stage: "detail", context: executionContext)
            let parsed = BookDetailParser(executionContext: executionContext).parse(source: source, book: book, response: transformedResponse)
            if case .failure(let error) = parsed {
                await emitFailure(error, stage: "detail.parse", source: source, details: ["url": transformedResponse.url.absoluteString])
            }
            return parsed
        case .failure(let error):
            await emitFailure(error, stage: "detail.load", source: source, details: ["url": request.url.absoluteString])
            return .failure(error)
        }
    }

    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> {
        await getChapterList(source: source, book: book, maxPages: 30)
    }

    func getChapterList(source: BookSource, book: BookDetail, maxPages: Int) async -> Result<[BookChapter], SourceEngineError> {
        let executionState = persistentState(for: source)
        restoreBookVariables(source: source, bookURL: book.bookUrl, into: executionState)
        let executionContext = RuleExecutionContext(persistentState: executionState, source: source, logHandler: { [diagnostics] message in
            Task { await diagnostics.emit(.init(level: .info, stage: "toc.js", sourceName: source.bookSourceName, message: message)) }
        })
        defer { executionContext.cleanUp() }
        executionContext.setExecutionStage("toc")
        attachVerificationCodeProvider(executionContext, source: source)
        executionContext.networkHandler = { [network] encoded in
            self.syncLoad(
                encoded: encoded,
                source: source,
                network: network,
                cookieHeader: executionContext.string(for: "cookieHeader"),
                persistentValues: executionState.snapshot(),
                persistentState: executionState
            )
        }
        executionContext.responseHandler = { [network] encoded in
            SynchronousSourceNetworkBridge.loadResponse(
                urlText: encoded,
                source: source,
                network: network,
                cookieHeader: executionContext.string(for: "cookieHeader"),
                persistentValues: executionState.snapshot(),
                persistentState: executionState
            )
        }
        // Legado executes `ruleToc.preUpdateJs` before the TOC request.  The
        // script is a side-effect hook (`java.put`, `java.ajax`, cookie
        // refresh), so its return value is intentionally ignored; a failure
        // must not block the TOC, it only leaves a diagnostic.
        // `book.setReverseToc` is a per-run signal; the persistent store is
        // per-source, so clear the in-memory flag to make sure only this TOC's
        // preUpdateJs can flip the chapter order.
        executionContext.setValue(nil, for: "book.reverseToc")
        runTocPreUpdateJs(
            source: source,
            book: book,
            baseUrl: book.bookUrl.nilIfEmpty ?? book.tocUrl?.nilIfEmpty ?? source.cleanSourceURL,
            executionContext: executionContext
        )
        let tocURL = book.tocUrl?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? book.bookUrl
        let resolvedTocURL = DynamicURLResolver.resolve(
            tocURL,
            baseUrl: book.bookUrl.nilIfEmpty ?? book.tocUrl?.nilIfEmpty ?? source.cleanSourceURL,
            source: source,
            variables: ["book": book],
            context: executionContext
        )
        let request = requestBuilder.buildPageRequest(
            source: source,
            urlText: resolvedTocURL,
            persistentValues: executionState.snapshot()
        )
        switch await loadWithOptionalWebViewFallback(request, source: source, stage: "toc.load") {
        case .success(let response):
            let transformedResponse = transformBodyIfNeeded(response, source: source, rules: [source.ruleToc], network: network, stateOverride: executionState, executionContext: executionContext)
            recordJavaScriptEvidence(source: source, stage: "toc", context: executionContext)
            let parsed = parseChapterListPage(source: source, book: book, response: transformedResponse, executionContext: executionContext)
            if case .failure(let error) = parsed {
                await emitFailure(error, stage: "toc.parse", source: source, details: ["url": response.url.absoluteString])
                await emitPaginationStop(
                    source: source,
                    stage: "toc.pagination.stop",
                    reason: isEmptyPaginationError(error) ? "empty-page" : "parse-failure",
                    attemptedURL: response.url.absoluteString,
                    canonicalURL: SourcePaginationURLIdentity().canonical(response.url),
                    pagesLoaded: 0,
                    retainedItemCount: 0,
                    maxPages: maxPages
                )
            }
            guard case .success(let firstPage) = parsed else {
                return parsed.map { $0.chapters }
            }
            let result = await appendNextChapterListPages(
                firstPage,
                source: source,
                book: book,
                firstURL: response.url,
                maxPages: maxPages,
                executionContext: executionContext
            )
            switch result {
            case .success(let chapters):
                // `book.setReverseToc(true)` (recorded by the JS bridge during
                // preUpdateJs) restores reading order before titles are
                // formatted, so `formatJs` sees the final 1-based index.
                let ordered = applyReverseTocIfNeeded(chapters, executionContext: executionContext)
                let formatted = applyTocFormatJs(
                    ordered,
                    source: source,
                    executionContext: executionContext
                )
                recordJavaScriptEvidence(source: source, stage: "toc.format", context: executionContext)
                return .success(formatted)
            case .failure:
                return result
            }
        case .failure(let error):
            await emitFailure(error, stage: "toc.load", source: source, details: ["url": request.url.absoluteString])
            await emitPaginationStop(
                source: source,
                stage: "toc.pagination.stop",
                reason: "load-failure",
                attemptedURL: request.url.absoluteString,
                canonicalURL: SourcePaginationURLIdentity().canonical(request.url),
                pagesLoaded: 0,
                retainedItemCount: 0,
                maxPages: 30
            )
            return .failure(error)
        }
    }

    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> {
        // Match `appendNextContentPages`'s safety cap. Leaving the convenience
        // entry point at 8 silently truncated every paginated chapter after
        // eight pages, even though the paginator itself allowed 24.
        await getContent(source: source, chapter: chapter, maxPages: 24)
    }

    func getContent(source: BookSource, chapter: BookChapter, maxPages: Int) async -> Result<ChapterContent, SourceEngineError> {
        let executionState = persistentState(for: source)
        restoreBookVariables(source: source, bookURL: chapter.bookUrl, into: executionState)
        let executionContext = RuleExecutionContext(persistentState: executionState, source: source, logHandler: { [diagnostics] message in
            Task { await diagnostics.emit(.init(level: .info, stage: "content.js", sourceName: source.bookSourceName, message: message)) }
        })
        defer { executionContext.cleanUp() }
        executionContext.setExecutionStage("content")
        attachVerificationCodeProvider(executionContext, source: source)
        executionContext.networkHandler = { [network] encoded in
            self.syncLoad(
                encoded: encoded,
                source: source,
                network: network,
                cookieHeader: executionContext.string(for: "cookieHeader"),
                persistentValues: executionState.snapshot(),
                persistentState: executionState
            )
        }
        executionContext.responseHandler = { [network] encoded in
            SynchronousSourceNetworkBridge.loadResponse(
                urlText: encoded,
                source: source,
                network: network,
                cookieHeader: executionContext.string(for: "cookieHeader"),
                persistentValues: executionState.snapshot(),
                persistentState: executionState
            )
        }
        let resolvedChapterUrl = DynamicURLResolver.resolve(
            chapter.url,
            baseUrl: chapter.bookUrl.nilIfEmpty ?? source.cleanSourceURL,
            source: source,
            variables: ["chapter": chapter],
            context: executionContext
        )
        let request = requestBuilder.buildPageRequest(
            source: source,
            urlText: resolvedChapterUrl,
            baseURL: chapter.bookUrl.nilIfEmpty ?? source.bookSourceUrl,
            persistentValues: executionState.snapshot()
        )
        let globalPurifyRules = await purifyRules()
        switch await loadWithOptionalWebViewFallback(request, source: source, stage: "content.load") {
        case .success(let response):
            let transformedResponse = transformBodyIfNeeded(response, source: source, rules: [source.ruleContent], network: network, stateOverride: executionState, executionContext: executionContext)
            recordJavaScriptEvidence(source: source, stage: "content", context: executionContext)
            let parsed = parseContentPage(
                source: source,
                chapter: chapter,
                response: transformedResponse,
                globalPurifyRules: globalPurifyRules,
                executionContext: executionContext
            )
            if case .failure(let error) = parsed {
                await emitFailure(error, stage: "content.parse", source: source, details: ["url": response.url.absoluteString])
                await emitPaginationStop(
                    source: source,
                    stage: "content.pagination.stop",
                    reason: isEmptyPaginationError(error) ? "empty-page" : "parse-failure",
                    attemptedURL: response.url.absoluteString,
                    canonicalURL: SourcePaginationURLIdentity().canonical(response.url),
                    pagesLoaded: 0,
                    retainedItemCount: 0,
                    maxPages: maxPages
                )
            }
            guard case .success(let firstPage) = parsed else { return parsed }
            return await appendNextContentPages(
                firstPage,
                source: source,
                chapter: chapter,
                firstURL: response.url,
                maxPages: maxPages,
                globalPurifyRules: globalPurifyRules,
                executionContext: executionContext
            )
        case .failure(let error):
            await emitFailure(error, stage: "content.load", source: source, details: ["url": request.url.absoluteString])
            await emitPaginationStop(
                source: source,
                stage: "content.pagination.stop",
                reason: "load-failure",
                attemptedURL: request.url.absoluteString,
                canonicalURL: SourcePaginationURLIdentity().canonical(request.url),
                pagesLoaded: 0,
                retainedItemCount: 0,
                maxPages: maxPages
            )
            return .failure(error)
        }
    }

    func login(source: BookSource, credentials: [String: String]) async -> Result<SourceLoginVerification, SourceEngineError> {
        let cleaned = credentials.reduce(into: [String: String]()) { result, item in
            let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            result[key] = item.value
        }
        guard !cleaned.isEmpty else {
            return .failure(.invalidSource("登录信息为空"))
        }
        let state = persistentState(for: source)
        // Re-login replaces the previous account instead of merging into it.
        state.removePrefix(SourceLoginScript.loginInfoPrefix)
        for (name, value) in cleaned {
            state.put(value, for: SourceLoginScript.loginInfoKey(name))
        }

        guard let script = SourceLoginScript.script(from: source.loginUrl),
              !SourceLoginScript.isPageURL(source.loginUrl) else {
            // No JS login step: the credentials are already visible to
            // `source.getLoginInfoMap()` inside `@js:` rules.
            return await verifyLogin(source: source)
        }

        guard let baseURL = URL(string: source.bookSourceUrl),
              ["http", "https"].contains(baseURL.scheme?.lowercased() ?? "") else {
            return .failure(.invalidSource("书源 URL 无法用于登录"))
        }
        let cookieHeader = await cookieStore.cookieHeader(for: baseURL)
        let context = RuleExecutionContext(
            initialValues: [
                "source": source,
                "baseUrl": baseURL.absoluteString,
                "cookieHeader": cookieHeader ?? ""
            ],
            persistentState: state,
            networkHandler: { encoded in
                SynchronousSourceLoader().loadResponse(urlText: encoded, source: source, cookieHeader: cookieHeader)?.body ?? ""
            },
            responseHandler: { encoded in
                SynchronousSourceLoader().loadResponse(urlText: encoded, source: source, cookieHeader: cookieHeader)
            },
            logHandler: { [diagnostics] message in
                Task { await diagnostics.emit(.init(level: .info, stage: "login.js", sourceName: source.bookSourceName, message: message)) }
            }
        )
        context.setExecutionStage("login")
        defer { context.cleanUp() }
        let runtime = JSCoreRuntime(executionContext: context)
        switch runtime.evaluate(script, variables: [
            "source": source,
            "baseUrl": baseURL.absoluteString,
            "cookieHeader": cookieHeader ?? ""
        ]) {
        case .success:
            break
        case .failure(let error):
            return .failure(error)
        }
        return await verifyLogin(source: source)
    }

    func verifyLogin(source: BookSource) async -> Result<SourceLoginVerification, SourceEngineError> {
        guard let script = source.loginCheckJs?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return .success(SourceLoginVerification(status: .notConfigured, message: "未配置 loginCheckJs", cookiePresent: false))
        }
        guard let baseURL = URL(string: source.bookSourceUrl),
              ["http", "https"].contains(baseURL.scheme?.lowercased() ?? "") else {
            return .failure(.invalidSource("书源 URL 无法用于登录检查"))
        }
        let cookieHeader = await cookieStore.cookieHeader(for: baseURL)
        let context = RuleExecutionContext(
            initialValues: [
                "source": source,
                "baseUrl": baseURL.absoluteString,
                "cookieHeader": cookieHeader ?? ""
            ],
            persistentState: persistentState(for: source),
            networkHandler: { encoded in
                SynchronousSourceLoader().loadResponse(urlText: encoded, source: source, cookieHeader: cookieHeader)?.body ?? ""
            },
            responseHandler: { encoded in
                SynchronousSourceLoader().loadResponse(urlText: encoded, source: source, cookieHeader: cookieHeader)
            },
            logHandler: { [diagnostics] message in
                Task { await diagnostics.emit(.init(level: .info, stage: "loginCheck.js", sourceName: source.bookSourceName, message: message)) }
            }
        )
        context.setExecutionStage("login")
        defer { context.cleanUp() }
        let runtime = JSCoreRuntime(executionContext: context)
        let evaluated = runtime.evaluate(script, variables: [
            "source": source,
            "baseUrl": baseURL.absoluteString,
            "cookieHeader": cookieHeader ?? ""
        ])
        let value: String
        switch evaluated {
        case .success(let output):
            value = String(output).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        case .failure(let error):
            return .failure(error)
        }
        let normalized = value.lowercased()
        let status: SourceLoginVerification.Status
        if normalized.isEmpty || ["false", "0", "null", "undefined", "未登录", "请登录"].contains(normalized) {
            status = .requiresLogin
        } else if ["cloudflare", "captcha", "challenge", "安全验证", "人机验证"].contains(where: normalized.contains) {
            status = .verificationRequired
        } else if ["403", "429", "forbidden", "blocked", "拒绝访问"].contains(where: normalized.contains) {
            status = .blocked
        } else if ["true", "1", "ok", "success", "已登录", "登录成功"].contains(normalized) {
            status = .passed
        } else {
            status = .warning
        }
        return .success(SourceLoginVerification(
            status: status,
            message: value.isEmpty ? "loginCheckJs 返回空值" : "loginCheckJs 返回：\(value.prefix(160))",
            cookiePresent: !(cookieHeader?.isEmpty ?? true)
        ))
    }

    /// Repeats the transport when the URL option asked for `retry`
    /// (Legado `UrlOption.retry`).  A successful response short-circuits.
    private func loadWithRetry(_ request: SourceRequest, attempts: Int) async -> Result<SourceResponse, SourceEngineError> {
        // Legado `concurrentRate`：同一书源的搜索 / 目录 / 正文共用一个限流窗口，
        // 在真正发出请求前取号（ConcurrentRateLimiter.kt）。
        let rateRule = SourceRateRule(request.concurrentRate)
        let rateKey = request.rateLimitKey
        if let rateRule, let rateKey {
            await rateLimiter.acquire(key: rateKey, rule: rateRule)
        }
        defer {
            if let rateRule, let rateKey {
                rateLimiter.release(key: rateKey, rule: rateRule)
            }
        }

        var result = await network.load(request)
        var remaining = min(max(attempts, 0), 5)
        while remaining > 0 {
            if case .success = result { break }
            remaining -= 1
            result = await network.load(request)
        }
        return result
    }

    private func loadWithOptionalWebViewFallback(
        _ request: SourceRequest,
        source: BookSource,
        stage: String
    ) async -> Result<SourceResponse, SourceEngineError> {
        // Legado `webView` on the URL option skips the plain socket entirely
        // (AnalyzeUrl.kt L188); `retry` adds transport attempts (L187).
        let forcedWebView = request.webView && allowWebViewFallback && !SandboxEnvironment.isLiveContainer
        let primary: Result<SourceResponse, SourceEngineError>
        if forcedWebView {
            primary = .failure(.network("URL option requested WebView"))
        } else {
            primary = await loadWithRetry(request, attempts: request.retry)
        }
        if case .success(let rawResponse) = primary {
            let response = ResponseBodyDecoder().normalize(rawResponse, preferredCharset: request.expectedCharset)
            persistentState(for: source).ingestResponse(response)
            recordEvidence(source: source, stage: stage, request: request, response: response)
            await emitResponseObservation(response, request: request, source: source, stage: stage)
            // Nested Legado bridges must receive the complete response even
            // for HTTP errors so source JS can inspect status/headers/body and
            // decide how to recover. The top-level pipeline still reports
            // ordinary 4xx/5xx loads as failures when no WebView fallback is
            // configured.
            let needsWebViewFallback = shouldUseWebViewFallback(source: source, response: response, stage: stage)
            if (400...599).contains(response.statusCode), !needsWebViewFallback {
                return .failure(.network("HTTP \(response.statusCode)"))
            }
            if !needsWebViewFallback {
                return .success(response)
            }
        }
        let shouldFallback: Bool
        if forcedWebView {
            shouldFallback = true
        } else if case .success(let raw) = primary {
            let response = ResponseBodyDecoder().normalize(raw, preferredCharset: request.expectedCharset)
            shouldFallback = shouldUseWebViewFallback(source: source, response: response, stage: stage)
        } else {
            shouldFallback = shouldUseWebView(source: source)
        }
        guard shouldFallback else {
            if case .failure(let error) = primary {
                recordFailureEvidence(source: source, stage: stage, request: request, error: error)
            }
            return primary
        }

        await diagnostics.emit(.init(
            level: .info,
            stage: "\(stage).webview",
            sourceName: source.bookSourceName,
            message: "\u{5207}\u{6362} WebView fallback",
            details: ["url": request.url.absoluteString]
        ))

        let delay = webViewDelay(source: source)
        let assets = ruleWebViewAssets(source: source)
        let htmlResult = await WebViewFallback(cookieStore: cookieStore).load(
            url: request.url,
            delay: delay,
            javaScript: request.webJs ?? assets.javaScript,
            sourceRegex: assets.sourceRegex,
            overrideUrlRegex: assets.overrideUrlRegex
        )
        switch htmlResult {
        case .success(let html):
            let response = SourceResponse(
                url: request.url,
                statusCode: 200,
                headers: [:],
                body: html,
                data: Data(html.utf8)
            )
            recordEvidence(source: source, stage: stage, request: request, response: response)
            return .success(response)
        case .failure(let error):
            recordFailureEvidence(source: source, stage: stage, request: request, error: error)
            return .failure(error)
        }
    }

    func resetDiagnosticEvidence(sourceURL: String) {
        let key = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        evidenceLock.lock()
        evidence.removeValue(forKey: key)
        evidenceLock.unlock()
    }

    func diagnosticEvidence(sourceURL: String, stage: SourceDiagnosticStage) -> SourceDiagnosticEvidence? {
        let key = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        evidenceLock.lock()
        defer { evidenceLock.unlock() }
        return evidence[key]?[stage]
    }

    private func recordEvidence(
        source: BookSource,
        stage: String,
        request: SourceRequest,
        response: SourceResponse
    ) {
        let normalizedStage: SourceDiagnosticStage?
        if stage.lowercased().hasPrefix("search") {
            normalizedStage = .search
        } else if stage.lowercased().hasPrefix("detail") {
            normalizedStage = .detail
        } else if stage.lowercased().hasPrefix("toc") {
            normalizedStage = .toc
        } else if stage.lowercased().hasPrefix("content") || stage.lowercased().hasPrefix("payaction") {
            normalizedStage = .content
        } else {
            normalizedStage = nil
        }
        guard let normalizedStage else { return }
        let key = source.bookSourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        evidenceLock.lock()
        if evidence.count > 50 {
            evidence.removeAll()
        }
        let javascript = evidence[key]?[normalizedStage]?.javascript ?? []
        let ruleSummary: String? = {
            switch normalizedStage {
            case .search:
                return source.ruleSearch?.fields["bookList"].map { "bookList: \($0)" }
            case .detail:
                return source.ruleBookInfo?.fields["name"].map { "name: \($0)" }
            case .toc:
                return source.ruleToc?.fields["chapterList"].map { "chapterList: \($0)" }
            case .content:
                return source.ruleContent?.fields["content"].map { "content: \($0)" }
            }
        }()
        evidence[key, default: [:]][normalizedStage] = SourceDiagnosticEvidence(
            request: request,
            response: response,
            javascript: javascript,
            ruleSummary: ruleSummary
        )
        evidenceLock.unlock()
    }

    private func recordFailureEvidence(
        source: BookSource,
        stage: String,
        request: SourceRequest,
        error: SourceEngineError
    ) {
        let normalizedStage: SourceDiagnosticStage?
        if stage.lowercased().hasPrefix("search") {
            normalizedStage = .search
        } else if stage.lowercased().hasPrefix("detail") {
            normalizedStage = .detail
        } else if stage.lowercased().hasPrefix("toc") {
            normalizedStage = .toc
        } else if stage.lowercased().hasPrefix("content") || stage.lowercased().hasPrefix("payaction") {
            normalizedStage = .content
        } else {
            normalizedStage = nil
        }
        guard let normalizedStage else { return }
        let key = source.bookSourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        evidenceLock.lock()
        if evidence.count > 50 {
            evidence.removeAll()
        }
        let javascript = evidence[key]?[normalizedStage]?.javascript ?? []
        let ruleSummary: String? = {
            switch normalizedStage {
            case .search:
                return source.ruleSearch?.fields["bookList"].map { "bookList: \($0)" }
            case .detail:
                return source.ruleBookInfo?.fields["name"].map { "name: \($0)" }
            case .toc:
                return source.ruleToc?.fields["chapterList"].map { "chapterList: \($0)" }
            case .content:
                return source.ruleContent?.fields["content"].map { "content: \($0)" }
            }
        }()
        evidence[key, default: [:]][normalizedStage] = SourceDiagnosticEvidence(
            request: request,
            error: error,
            javascript: javascript,
            ruleSummary: ruleSummary
        )
        evidenceLock.unlock()
    }

    private func recordJavaScriptEvidence(
        source: BookSource,
        stage: String,
        context: RuleExecutionContext
    ) {
        let normalizedStage: SourceDiagnosticStage?
        if stage.lowercased().hasPrefix("search") { normalizedStage = .search }
        else if stage.lowercased().hasPrefix("detail") { normalizedStage = .detail }
        else if stage.lowercased().hasPrefix("toc") { normalizedStage = .toc }
        else if stage.lowercased().hasPrefix("content") || stage.lowercased().hasPrefix("payaction") { normalizedStage = .content }
        else { normalizedStage = nil }
        guard let normalizedStage else { return }
        let scripts = context.javascriptEvidenceSnapshot()
        let logs = context.logs()
        guard !scripts.isEmpty || !logs.isEmpty else { return }
        let key = source.bookSourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        evidenceLock.lock()
        if let existing = evidence[key]?[normalizedStage] {
            evidence[key]?[normalizedStage] = existing.with(javascript: scripts, executionLogs: logs)
        }
        evidenceLock.unlock()
    }

    private func shouldUseWebView(source: BookSource) -> Bool {
        guard !SandboxEnvironment.isLiveContainer && allowWebViewFallback else { return false }
        if source.raw["webView"]?.lowercased() == "true" { return true }
        if source.raw["bookSourceType"]?.lowercased().contains("web") == true { return true }
        if let webJs = source.ruleContent?.fields["webJs"], webJs.contains("webView") { return true }
        if let customConfig = source.customConfig, customConfig.contains("\"webView\": true") || customConfig.contains("\"webView\":true") { return true }
        return false
    }

    private func shouldUseWebViewFallback(source: BookSource, response: SourceResponse, stage: String = "") -> Bool {
        guard !SandboxEnvironment.isLiveContainer && allowWebViewFallback else { return false }
        if shouldUseWebView(source: source) { return true }
        // A source that declares sourceRegex/webJs fetches its real payload
        // from XHR/fetch inside the page. The plain HTTP response is only the
        // shell, so the content/toc stage must go through WebKit even when the
        // shell returns HTTP 200.
        if stage.lowercased().hasPrefix("content") || stage.lowercased().hasPrefix("toc") {
            let assets = ruleWebViewAssets(source: source)
            if assets.sourceRegex != nil || assets.javaScript != nil {
                return true
            }
        }
        let text = response.body.lowercased()
        if (400...599).contains(response.statusCode) && (text.isEmpty || response.statusCode == 403 || response.statusCode == 503) {
            return true
        }
        // Anti-bot bootstrap shells (七猫/梧桐 `var arg1=`, `getRenderData`,
        // cookie+reload) return HTTP 200 with no crawlable markup. The plain
        // socket cannot execute the script, so the stage must go through WebKit.
        if Self.looksLikeJavaScriptChallenge(response.body) { return true }
        // Hard challenge markers are unambiguous: they only appear on an
        // interstitial page. Brand strings such as "cloudflare" or "captcha"
        // also appear in ordinary footers and login widgets, so they count
        // only when the body carries no crawlable markup at all. Treating a
        // full result page as a challenge forces WebKit, whose simplified DOM
        // dropped every rule target: qunxs returned a 17K/15-item page over
        // HTTP yet parsed 0 nodes once the fallback kicked in.
        let hardChallengeMarkers = [
            "cf-challenge", "cf-browser-verification", "__cf_chl",
            "cf_chl_opt", "turnstile", "just a moment",
            "attention required", "ddos-guard", "百度安全验证", "人机验证"
        ]
        if hardChallengeMarkers.contains(where: { text.contains($0) }) { return true }
        let softMarkers = ["cloudflare", "captcha", "安全验证"]
        if softMarkers.contains(where: { text.contains($0) }) {
            return !Self.hasCrawlableMarkup(response.body)
        }
        return false
    }

    /// A challenge interstitial carries no crawlable list/detail structure.
    /// A real result page always exposes several links or list/table nodes, so
    /// the soft anti-bot markers above must not pre-empt it.
    static func hasCrawlableMarkup(_ body: String) -> Bool {
        let text = body.lowercased()
        let anchorCount = text.components(separatedBy: "<a ").count - 1
        if anchorCount >= 6 { return true }
        if text.contains("<article") || text.contains("<table") { return true }
        let listCount = text.components(separatedBy: "<li").count - 1
        return listCount >= 6
    }

    /// Body-only heuristic for pages that are pure anti-bot bootstrap.
    /// Kept separate from `shouldUseWebViewFallback` so the classifier can be
    /// unit-tested without a network stack or a `BookSource`.
    static func looksLikeJavaScriptChallenge(_ body: String) -> Bool {
        let text = body.lowercased()
        guard !text.isEmpty else { return false }
        if text.contains("var arg1=") || text.contains("getrenderdata") {
            return true
        }
        if text.contains("document.cookie"),
           text.contains("location.reload") || text.contains(".reload()"),
           !text.contains("<article"),
           !text.contains("<li") {
            return true
        }
        return false
    }

    /// `webJs` / `sourceRegex` / `overrideUrlRegex` live in `ruleContent` in
    /// the Legado schema; a few hand-written sources keep them at the root.
    func ruleWebViewAssets(source: BookSource) -> (javaScript: String?, sourceRegex: String?, overrideUrlRegex: String?) {
        let fields = source.ruleContent?.fields ?? [:]
        func value(_ key: String) -> String? {
            let raw = fields[key] ?? source.raw[key]
            let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let trimmed, !trimmed.isEmpty else { return nil }
            return trimmed
        }
        return (value("webJs"), value("sourceRegex"), value("overrideUrlRegex"))
    }

    private func webViewDelay(source: BookSource) -> TimeInterval {
        if let raw = source.raw["webViewDelayTime"], let value = Double(raw) {
            return max(0.5, min(value / 1000, 20))
        }
        return 3
    }

    private func transformBodyIfNeeded(
        _ response: SourceResponse,
        source: BookSource,
        rules: [SourceRule?] = [],
        network: SourceNetworkClient? = nil,
        stateOverride: RulePersistentState? = nil,
        executionContext sharedExecutionContext: RuleExecutionContext? = nil
    ) -> SourceResponse {
        var scripts: [String] = []
        if let sourceScript = bodyJSScript(source) { scripts.append(sourceScript) }
        for rule in rules {
            if let script = bodyJSScript(rule) { scripts.append(script) }
        }
        guard !scripts.isEmpty else { return response }
        let state = stateOverride ?? persistentState(for: source)
        let context: RuleExecutionContext
        if let sharedExecutionContext {
            context = sharedExecutionContext
            context.bind([
                "baseUrl": response.url.absoluteString,
                "source": source,
                "result": response.body,
                "html": response.body,
                "body": response.body
            ])
        } else {
            let localContext = RuleExecutionContext(
                initialValues: ["baseUrl": response.url.absoluteString, "source": source],
                persistentState: state,
                networkHandler: { encoded in
                    if let network {
                        return SynchronousSourceNetworkBridge.loadBody(
                            urlText: encoded,
                            source: source,
                            network: network,
                            cookieHeader: state.get("cookieHeader").nilIfEmpty,
                            persistentValues: state.snapshot(),
                            persistentState: state
                        )
                    }
                    return SynchronousSourceLoader().load(
                        urlText: encoded,
                        source: source,
                        cookieHeader: state.get("cookieHeader").nilIfEmpty,
                        persistentValues: state.snapshot(),
                        persistentState: state
                    )
                }
            )
            localContext.responseHandler = { encoded in
                if let network {
                    return SynchronousSourceNetworkBridge.loadResponse(
                        urlText: encoded,
                        source: source,
                        network: network,
                        cookieHeader: localContext.string(for: "cookieHeader"),
                        persistentValues: state.snapshot(),
                        persistentState: state
                    )
                }
                return SynchronousSourceLoader().loadResponse(
                    urlText: encoded,
                    source: source,
                    cookieHeader: localContext.string(for: "cookieHeader"),
                    persistentValues: state.snapshot(),
                    persistentState: state
                )
            }
            context = localContext
        }
        var output = response.body
        for script in scripts {
            let variables: [String: Any] = [
                "result": output,
                "html": output,
                "body": output,
                "baseUrl": response.url.absoluteString,
                "source": source
            ]
            let runtime = JSCoreRuntime(executionContext: context)
            let evaluated = runtime.evaluate(script, variables: variables)
            let result: Result<String, SourceEngineError>
            if case .failure(.javascript) = evaluated, script.contains("return") {
                result = runtime.evaluate("(function(){\(script)})()", variables: variables)
            } else {
                result = evaluated
            }
            guard case .success(let value) = result else { continue }
            let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty { output = value }
        }
        guard output != response.body else { return response }
        return SourceResponse(
            url: response.url,
            statusCode: response.statusCode,
            headers: response.headers,
            body: output,
            data: Data(output.utf8),
            encodedByteCount: response.encodedByteCount,
            bodyWasDecoded: response.bodyWasDecoded,
            contentEncodings: response.contentEncodings
        )
    }

    private func parseContentPage(
        source: BookSource,
        chapter: BookChapter,
        response: SourceResponse,
        globalPurifyRules: [String],
        executionContext: RuleExecutionContext = RuleExecutionContext()
    ) -> Result<ChapterContent, SourceEngineError> {
        return ContentParser(executionContext: executionContext).parse(
            source: source,
            chapter: chapter,
            response: response,
            globalPurifyRules: globalPurifyRules
        )
    }

    private func parseChapterListPage(
        source: BookSource,
        book: BookDetail,
        response: SourceResponse,
        inheritedVolume: String? = nil,
        executionContext: RuleExecutionContext = RuleExecutionContext()
    ) -> Result<ChapterListPage, SourceEngineError> {
        return ChapterListParser(executionContext: executionContext).parsePage(
            source: source,
            book: book,
            response: response,
            inheritedVolume: inheritedVolume
        )
    }

    /// Runs the Legado `ruleToc.preUpdateJs` hook once, immediately before the
    /// TOC page request.  Sources use it to refresh tokens/cookies through
    /// `java.put` + `java.ajax`; the script's return value has no defined
    /// meaning in Legado and is discarded here as well.  Errors are recorded
    /// as diagnostics and never abort the TOC flow.
    private func runTocPreUpdateJs(
        source: BookSource,
        book: BookDetail,
        baseUrl: String,
        executionContext: RuleExecutionContext
    ) {
        guard let raw = source.ruleToc?.fields["preUpdateJs"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return }

        var script = raw
        if script.hasPrefix("@js:") {
            script = String(script.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if script.hasPrefix("<js>"), script.hasSuffix("</js>") {
            script = String(script.dropFirst(4).dropLast(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !script.isEmpty else { return }

        let runtime = executionContext.jsRuntime(ajaxHandler: { urlText in
            executionContext.networkHandler?(urlText)
                ?? SynchronousSourceLoader().load(urlText: urlText, source: source)
        })
        let variables: [String: Any] = [
            "book": book,
            "baseUrl": baseUrl,
            "source": source
        ]
        var outcome = runtime.evaluate(script, variables: variables)
        // Same compatibility retry as `formatJs`: Legado sources often use a
        // top-level `return`, which a bare script rejects.
        if case .failure = outcome, script.contains("return") {
            outcome = runtime.evaluate("(function(){\n\(script)\n})()", variables: variables)
        }
        if case .failure(let error) = outcome {
            executionContext.log("toc.preUpdateJs failed: \(error)")
        }
    }

    /// Legado lets a TOC rule flip the whole chapter list with
    /// `book.setReverseToc(true)` (sources that list newest chapters first use
    /// it to restore reading order).  The JavaScript bridge records the flag as
    /// `book.reverseToc`; the engine applies it once the complete paginated TOC
    /// has been collected and before `formatJs` runs, so formatted titles use
    /// the final reading order and indices stay contiguous.  The flag is read
    /// from the current execution context only: it is a per-run signal, not a
    /// per-book setting,
    /// so one book cannot silently reverse another book of the same source.
    private func applyReverseTocIfNeeded(
        _ chapters: [BookChapter],
        executionContext: RuleExecutionContext
    ) -> [BookChapter] {
        guard chapters.count > 1 else { return chapters }
        let raw = executionContext.value(for: "book.reverseToc")
        guard Self.isTruthyFlag(raw) else { return chapters }
        return chapters.reversed().enumerated().map { offset, chapter in
            chapter.withIndex(offset)
        }
    }

    /// Accepts the shapes `book.setReverseToc` receives: a JS boolean, the
    /// stringified form the bridge persists, or NSNumber coming back through
    /// JavaScriptCore.
    private static func isTruthyFlag(_ value: Any?) -> Bool {
        guard let value, !(value is NSNull) else { return false }
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let text = value as? String {
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !["", "false", "0", "no", "null", "undefined"].contains(normalized)
        }
        return false
    }

    /// Legado runs `ruleToc.formatJs` once the complete TOC (including every
    /// pagination page) has been collected and chapter indices are final.
    /// The script receives 1-based `index`, `title`, `chapter`, and `gInt`;
    /// its return value replaces the chapter title.  A failure on one chapter
    /// must not discard the rest of the TOC, so each chapter falls back to its
    /// parsed title.
    private func applyTocFormatJs(
        _ chapters: [BookChapter],
        source: BookSource,
        executionContext: RuleExecutionContext
    ) -> [BookChapter] {
        guard let raw = source.ruleToc?.fields["formatJs"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return chapters }

        var script = raw
        if script.hasPrefix("@js:") {
            script = String(script.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if script.hasPrefix("<js>"), script.hasSuffix("</js>") {
            script = String(script.dropFirst(4).dropLast(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !script.isEmpty else { return chapters }

        let runtime = executionContext.jsRuntime(ajaxHandler: { urlText in
            executionContext.networkHandler?(urlText)
                ?? SynchronousSourceLoader().load(urlText: urlText, source: source)
        })

        return chapters.enumerated().map { offset, chapter in
            let variables: [String: Any] = [
                "gInt": 0,
                "index": offset + 1,
                "chapter": LegadoBookChapterBridge(chapter: chapter),
                "title": chapter.title
            ]
            var outcome = runtime.evaluate(script, variables: variables)
            // Legado sources occasionally use a top-level `return`.  A bare
            // script rejects it ("Illegal return statement"); retry once in a
            // function wrapper so those sources keep working.
            if case .failure = outcome, script.contains("return") {
                outcome = runtime.evaluate("(function(){\n\(script)\n})()", variables: variables)
            }
            guard case .success(let value) = outcome else { return chapter }
            let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title != "undefined", title != "null" else { return chapter }
            return chapter.withTitle(title)
        }
    }

    private func syncLoad(
        encoded: String,
        source: BookSource,
        network: SourceNetworkClient,
        cookieHeader: String? = nil,
        persistentValues: [String: String] = [:],
        persistentState: RulePersistentState? = nil
    ) -> String {
        // JavaScriptCore callbacks are synchronous. Calling async `network.load` and
        // waiting on a semaphore can deadlock when the callback is already running on
        // the cooperative executor, so use the dedicated synchronous loader here.
        return SynchronousSourceNetworkBridge.loadBody(
            urlText: encoded,
            source: source,
            network: network,
            cookieHeader: cookieHeader,
            persistentValues: persistentValues,
            persistentState: persistentState
        )
    }

    private func appendNextChapterListPages(
        _ firstPage: ChapterListPage,
        source: BookSource,
        book: BookDetail,
        firstURL: URL,
        maxPages: Int = 30,
        executionContext: RuleExecutionContext
    ) async -> Result<[BookChapter], SourceEngineError> {
        let urlIdentity = SourcePaginationURLIdentity()
        // Some APIs repeat the last item on every page.  Normalize and retain
        // the first occurrence before pagination so the reader never exposes
        // duplicate chapter rows, even when the duplicate URLs differ only by
        // case, fragments or percent-encoding.
        var chapters = deduplicatedChapters(firstPage.chapters, identity: urlIdentity)
        var inheritedVolume = firstPage.trailingVolume
        guard maxPages > 1 else {
            return chapters.isEmpty ? .failure(.empty("Chapter list is empty")) : .success(chapters)
        }
        var nextURLText = firstPage.nextTocUrl?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        var seenURLs: Set<String> = [urlIdentity.canonical(firstURL)]
        var pagesLoaded = 1
        var stopReason: String? = nextURLText == nil ? "no-next-url" : nil
        var attemptedURL = nextURLText
        var attemptedCanonicalURL = nextURLText.flatMap(urlIdentity.canonical)

        while let currentNext = nextURLText {
            attemptedURL = currentNext
            attemptedCanonicalURL = urlIdentity.canonical(currentNext)
            if pagesLoaded >= maxPages {
                stopReason = "max-pages"
                break
            }
            let request = requestBuilder.buildPageRequest(
                source: source,
                urlText: currentNext,
                persistentValues: persistentState(for: source).snapshot()
            )
            let absolute = request.url.absoluteString
            let canonicalURL = urlIdentity.canonical(request.url)
            attemptedURL = absolute
            attemptedCanonicalURL = canonicalURL
            guard !seenURLs.contains(canonicalURL) else {
                stopReason = "duplicate-url"
                break
            }
            seenURLs.insert(canonicalURL)

            switch await loadWithOptionalWebViewFallback(request, source: source, stage: "toc.next.load") {
            case .success(let response):
                let responseCanonicalURL = urlIdentity.canonical(response.url)
                // A redirect to a page already consumed by an earlier request
                // is a pagination loop.  The current request URL is already in
                // `seenURLs`, so only a *different* final URL is considered a
                // duplicate redirect target.
                if responseCanonicalURL != canonicalURL, seenURLs.contains(responseCanonicalURL) {
                    stopReason = "duplicate-final-url"
                    nextURLText = nil
                    continue
                }
                seenURLs.insert(responseCanonicalURL)
                let state = persistentState(for: source)
                let transformedResponse = transformBodyIfNeeded(response, source: source, rules: [source.ruleToc], network: network, stateOverride: state, executionContext: executionContext)
                switch parseChapterListPage(source: source, book: book, response: transformedResponse, inheritedVolume: inheritedVolume, executionContext: executionContext) {
                case .success(let page):
                    inheritedVolume = page.trailingVolume ?? inheritedVolume
                    let uniquePageChapters = page.chapters.filter { chapter in
                        let key = chapterURLIdentity(chapter.url, identity: urlIdentity)
                        return !chapters.contains { chapterURLIdentity($0.url, identity: urlIdentity) == key }
                    }
                    let offset = chapters.count
                    // Rebuild indices from the retained sequence rather than
                    // carrying the page-local index.  A page may contain
                    // duplicates (for example chapter 2 appears again on
                    // page 2); filtering it out must not leave a gap before
                    // the next unique chapter.
                    chapters.append(contentsOf: uniquePageChapters.enumerated().map { localIndex, chapter in
                        chapter.withIndex(offset + localIndex)
                    })
                    nextURLText = page.nextTocUrl?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    pagesLoaded += 1
                    stopReason = nextURLText == nil ? "no-next-url" : nil
                case .failure(let error):
                    await emitFailure(error, stage: "toc.next.parse", source: source, details: ["url": response.url.absoluteString])
                    stopReason = isEmptyPaginationError(error) ? "empty-page" : "parse-failure"
                    nextURLText = nil
                }
            case .failure(let error):
                await emitFailure(error, stage: "toc.next.load", source: source, details: ["url": absolute])
                stopReason = "load-failure"
                nextURLText = nil
            }
        }

        if let stopReason {
            await emitPaginationStop(
                source: source,
                stage: "toc.pagination.stop",
                reason: stopReason,
                attemptedURL: attemptedURL ?? firstURL.absoluteString,
                canonicalURL: attemptedCanonicalURL ?? urlIdentity.canonical(firstURL),
                pagesLoaded: pagesLoaded,
                retainedItemCount: chapters.count,
                maxPages: maxPages
            )
        }

        return chapters.isEmpty ? .failure(.empty("Chapter list is empty")) : .success(chapters)
    }

    /// Legado `ReadBookActivity.payAction()`: run the source's purchase rule
    /// inside the same JS context that chapter parsing uses (cookieHeader,
    /// persistent variables, `jsLib` prelude and the synchronous HTTP bridge),
    /// then classify the string result.
    func performPayAction(
        source: BookSource,
        chapter: BookChapter,
        payAction: String
    ) async -> Result<PayActionOutcome, SourceEngineError> {
        let rule = payAction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rule.isEmpty else { return .failure(.rule("购买操作规则为空")) }

        let executionState = persistentState(for: source)
        let executionContext = RuleExecutionContext(
            persistentState: executionState,
            source: source,
            logHandler: { [diagnostics] message in
                Task {
                    await diagnostics.emit(.init(
                        level: .info,
                        stage: "payAction.js",
                        sourceName: source.bookSourceName,
                        message: message
                    ))
                }
            }
        )
        defer { executionContext.cleanUp() }
        executionContext.setExecutionStage("payAction")
        attachVerificationCodeProvider(executionContext, source: source)
        executionContext.networkHandler = { [network] encoded in
            self.syncLoad(
                encoded: encoded,
                source: source,
                network: network,
                cookieHeader: executionContext.string(for: "cookieHeader"),
                persistentValues: executionState.snapshot(),
                persistentState: executionState
            )
        }
        executionContext.responseHandler = { [network] encoded in
            SynchronousSourceNetworkBridge.loadResponse(
                urlText: encoded,
                source: source,
                network: network,
                cookieHeader: executionContext.string(for: "cookieHeader"),
                persistentValues: executionState.snapshot(),
                persistentState: executionState
            )
        }

        let chapterMap: [String: Any] = [
            "title": chapter.title,
            "name": chapter.title,
            "url": chapter.url,
            "chapterUrl": chapter.url,
            "bookUrl": chapter.bookUrl,
            "index": chapter.index,
            "chapterIndex": chapter.index,
            "isVip": chapter.isVip,
            "isPay": chapter.isPay ?? false,
            "updateTime": chapter.updateTime ?? "",
            "volumeName": chapter.volumeName ?? "",
            "wordCount": chapter.wordCount ?? ""
        ]
        let variables: [String: Any] = [
            "source": source,
            "chapter": chapterMap,
            "title": chapter.title,
            "baseUrl": chapter.url,
            "result": ""
        ]
        let runtime = executionContext.jsRuntime { [network] encoded in
            self.syncLoad(
                encoded: encoded,
                source: source,
                network: network,
                cookieHeader: executionContext.string(for: "cookieHeader"),
                persistentValues: executionState.snapshot(),
                persistentState: executionState
            )
        }

        let outcome = PayActionPolicy.evaluate(rule: rule) { script in
            runtime.evaluate(script, variables: variables)
        }
        recordJavaScriptEvidence(source: source, stage: "payAction", context: executionContext)
        switch outcome {
        case .success(let value):
            return .success(value)
        case .failure(let error):
            await emitFailure(error, stage: "payAction", source: source, details: ["chapter": chapter.title])
            return .failure(error)
        }
    }

    private func appendNextContentPages(
        _ firstPage: ChapterContent,
        source: BookSource,
        chapter: BookChapter,
        firstURL: URL,
        // Eight pages cut long serialised chapters off mid-sentence on
        // sources that paginate every 1-2k characters. Keep a safety bound,
        // but high enough that a normal chapter always finishes.
        maxPages: Int = 24,
        globalPurifyRules: [String],
        executionContext: RuleExecutionContext
    ) async -> Result<ChapterContent, SourceEngineError> {
        guard maxPages > 1 else { return .success(firstPage) }
        var paragraphs = firstPage.paragraphs
        var nextURLText = firstPage.nextContentUrl?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let urlIdentity = SourcePaginationURLIdentity()
        var seenURLs: Set<String> = [urlIdentity.canonical(firstURL)]
        var finalNextURL = nextURLText
        var pagesLoaded = 1
        var stopReason: String? = nextURLText == nil ? "no-next-url" : nil
        var attemptedURL = nextURLText
        var attemptedCanonicalURL = nextURLText.flatMap(urlIdentity.canonical)

        while let currentNext = nextURLText {
            attemptedURL = currentNext
            attemptedCanonicalURL = urlIdentity.canonical(currentNext)
            if pagesLoaded >= maxPages {
                stopReason = "max-pages"
                // Keep the pending URL so the reader can continue from here
                // instead of treating the truncation as end-of-chapter.
                finalNextURL = currentNext
                break
            }
            let request = requestBuilder.buildPageRequest(
                source: source,
                urlText: currentNext,
                baseURL: chapter.bookUrl.nilIfEmpty ?? firstURL.absoluteString,
                persistentValues: persistentState(for: source).snapshot()
            )
            let absolute = request.url.absoluteString
            let canonicalURL = urlIdentity.canonical(request.url)
            attemptedURL = absolute
            attemptedCanonicalURL = canonicalURL
            guard !seenURLs.contains(canonicalURL) else {
                stopReason = "duplicate-url"
                finalNextURL = nil
                break
            }
            seenURLs.insert(canonicalURL)

            switch await loadWithOptionalWebViewFallback(request, source: source, stage: "content.next.load") {
            case .success(let response):
                let responseCanonicalURL = urlIdentity.canonical(response.url)
                if responseCanonicalURL != canonicalURL, seenURLs.contains(responseCanonicalURL) {
                    stopReason = "duplicate-final-url"
                    nextURLText = nil
                    finalNextURL = nil
                    continue
                }
                seenURLs.insert(responseCanonicalURL)
                let state = persistentState(for: source)
                let transformedResponse = transformBodyIfNeeded(response, source: source, rules: [source.ruleContent], network: network, stateOverride: state, executionContext: executionContext)
                switch parseContentPage(
                    source: source,
                    chapter: chapter,
                    response: transformedResponse,
                    globalPurifyRules: globalPurifyRules,
                    executionContext: executionContext
                ) {
                case .success(let nextPage):
                    appendUniqueParagraphs(nextPage.paragraphs, to: &paragraphs)
                    nextURLText = nextPage.nextContentUrl?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    finalNextURL = nextURLText
                    pagesLoaded += 1
                    stopReason = nextURLText == nil ? "no-next-url" : nil
                case .failure(let error):
                    await emitFailure(error, stage: "content.next.parse", source: source, details: ["url": response.url.absoluteString])
                    stopReason = isEmptyPaginationError(error) ? "empty-page" : "parse-failure"
                    nextURLText = nil
                    finalNextURL = currentNext
                }
            case .failure(let error):
                await emitFailure(error, stage: "content.next.load", source: source, details: ["url": absolute])
                stopReason = "load-failure"
                nextURLText = nil
                finalNextURL = currentNext
            }
        }

        if let stopReason {
            await emitPaginationStop(
                source: source,
                stage: "content.pagination.stop",
                reason: stopReason,
                attemptedURL: attemptedURL ?? firstURL.absoluteString,
                canonicalURL: attemptedCanonicalURL ?? urlIdentity.canonical(firstURL),
                pagesLoaded: pagesLoaded,
                retainedItemCount: paragraphs.count,
                maxPages: maxPages
            )
        }

        return .success(ChapterContent(
            chapter: firstPage.chapter,
            title: firstPage.title,
            paragraphs: paragraphs,
            nextContentUrl: finalNextURL,
            imageStyle: firstPage.imageStyle,
            payAction: firstPage.payAction
        ))
    }

    /// Paginated sources often repeat the last paragraph of page N at the top
    /// of page N+1 to make the split look seamless. Blind concatenation showed
    /// that paragraph twice in the reader.
    private func appendUniqueParagraphs(_ incoming: [String], to existing: inout [String]) {
        for paragraph in incoming {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if existing.last?.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed {
                continue
            }
            if existing.suffix(3).contains(where: {
                $0.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed
            }) {
                continue
            }
            existing.append(paragraph)
        }
    }

    private func chapterURLIdentity(_ value: String, identity: SourcePaginationURLIdentity) -> String {
        identity.canonical(value)
            ?? value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func deduplicatedChapters(
        _ values: [BookChapter],
        identity: SourcePaginationURLIdentity
    ) -> [BookChapter] {
        var seen: Set<String> = []
        var output: [BookChapter] = []
        output.reserveCapacity(values.count)
        for chapter in values {
            let key = chapterURLIdentity(chapter.url, identity: identity)
            guard seen.insert(key).inserted else { continue }
            output.append(chapter.withIndex(output.count))
        }
        return output
    }

    private func isEmptyPaginationError(_ error: SourceEngineError) -> Bool {
        guard case .empty = error else { return false }
        return true
    }

    private func emitPaginationStop(
        source: BookSource,
        stage: String,
        reason: String,
        attemptedURL: String,
        canonicalURL: String,
        pagesLoaded: Int,
        retainedItemCount: Int,
        maxPages: Int
    ) async {
        await diagnostics.emit(.init(
            level: .info,
            stage: stage,
            sourceName: source.bookSourceName,
            message: stage.hasPrefix("toc") ? "目录分页停止" : "正文分页停止",
            details: [
                "reason": reason,
                "url": attemptedURL,
                "attemptedURL": attemptedURL,
                "canonicalURL": canonicalURL,
                "pagesLoaded": String(pagesLoaded),
                "retainedItemCount": String(retainedItemCount),
                "maxPages": String(maxPages)
            ]
        ))
    }

    private func bodyJSScript(_ source: BookSource) -> String? {
        for key in ["bodyJs", "bodyjs", "bodyJS"] {
            if let value = source.raw[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        guard let customConfig = source.customConfig,
              let data = customConfig.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        for key in ["bodyJs", "bodyjs", "bodyJS"] {
            if let value = object[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private func bodyJSScript(_ rule: SourceRule?) -> String? {
        guard let rule else { return nil }
        for key in ["bodyJs", "bodyjs", "bodyJS"] {
            if let value = rule.fields[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func emitFailure(
        _ error: SourceEngineError,
        stage: String,
        source: BookSource,
        details: [String: String] = [:]
    ) async {
        await diagnostics.emit(.init(
            level: .warning,
            stage: stage,
            sourceName: source.bookSourceName,
            message: error.displayMessage,
            details: details
        ))
    }

    private func emitResponseObservation(
        _ response: SourceResponse,
        request: SourceRequest,
        source: BookSource,
        stage: String
    ) async {
        let contentType = response.headers.first {
            $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame
        }?.value ?? ""
        let hasCookie = response.headers.contains {
            $0.key.caseInsensitiveCompare("Set-Cookie") == .orderedSame
        }
        await diagnostics.emit(.init(
            level: .info,
            stage: "\(stage).response",
            sourceName: source.bookSourceName,
            message: "收到书源响应",
            details: [
                "method": request.method.rawValue,
                "url": response.url.absoluteString,
                "status": String(response.statusCode),
                "bytes": String(response.data.count),
                "contentType": contentType,
                "setCookie": hasCookie ? "present" : "absent"
            ]
        ))
    }

    /// Wires the synchronous Legado captcha bridge to the SwiftUI coordinator.
    /// Contexts created by unit tests have no source and never reach this path,
    /// so `java.getVerificationCode` stays deterministic in fixtures.
    private func attachVerificationCodeProvider(_ context: RuleExecutionContext, source: BookSource) {
        context.verificationCodeProvider = { [weak context] imageURL in
            guard let context else { return "" }
            return VerificationCodeCoordinator.requestSynchronously(
                imageURL: imageURL,
                sourceName: source.bookSourceName,
                stage: context.currentExecutionStage ?? "",
                baseURL: source.bookSourceUrl,
                cookieHeader: context.string(for: "cookieHeader")
            )
        }
    }
    /// Identity used to scope per-source persistent state (`loginInfo`, cookies,
    /// cached tokens). URL-less sources are legal while editing drafts, so fall
    /// back to a stable fingerprint of the raw rule instead of collapsing every
    /// draft into the same empty-string bucket.
    static func persistentStateKey(for source: BookSource) -> String {
        let url = source.bookSourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !url.isEmpty {
            return "url:" + url
        }
        var hash: UInt64 = 0xcbf29ce484222325
        func combine(_ value: String) {
            for byte in value.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x100000001b3
            }
            hash ^= 0x1f
            hash = hash &* 0x100000001b3
        }
        combine(source.bookSourceName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        combine(source.searchUrl ?? "")
        combine(source.exploreUrl ?? "")
        for key in source.raw.keys.sorted() {
            combine(key)
            combine(source.raw[key] ?? "")
        }
        return "draft:\(source.bookSourceName.lowercased())#\(String(format: "%016llx", hash))"
    }

    func persistentState(for source: BookSource) -> RulePersistentState {
        let key = Self.persistentStateKey(for: source)
        stateLock.lock()
        defer { stateLock.unlock() }
        if let state = states[key] {
            touchStateKeyLocked(key)
            return state
        }
        if states.count >= Self.maximumPersistentStates {
            evictLeastRecentlyUsedStateLocked()
        }
        let state = RulePersistentState()
        states[key] = state
        touchStateKeyLocked(key)
        return state
    }

    private func touchStateKeyLocked(_ key: String) {
        if let index = stateAccessOrder.firstIndex(of: key) {
            stateAccessOrder.remove(at: index)
        }
        stateAccessOrder.append(key)
    }

    /// Bounded LRU instead of `removeAll()`: clearing every source state threw
    /// away login cookies and cached tokens for all sources at once whenever
    /// the 101st source was opened.
    private func evictLeastRecentlyUsedStateLocked() {
        while states.count >= Self.maximumPersistentStates, let oldest = stateAccessOrder.first {
            stateAccessOrder.removeFirst()
            states.removeValue(forKey: oldest)
        }
        if states.count >= Self.maximumPersistentStates {
            states.removeAll()
            stateAccessOrder.removeAll()
        }
    }
}
