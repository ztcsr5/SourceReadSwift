import Foundation

/// A deterministic Search → Detail → TOC → Content execution result.
///
/// The UI used to duplicate this chain in three different screens.  Keeping
/// the chain in one value type gives source diagnostics, rule previews and the
/// reader the same stage ordering and error semantics.  A successful prefix is
/// retained when a later stage fails so callers can show actionable evidence
/// instead of losing the useful part of the run.
struct SourcePipelineResult: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let sourceName: String
    let sourceURL: String
    let keyword: String
    let startedAt: Date
    let searchBooks: [SearchBook]
    let detail: BookDetail?
    let chapters: [BookChapter]
    let content: ChapterContent?
    let steps: [SourceDiagnosticStep]

    init(
        id: UUID = UUID(),
        sourceName: String,
        sourceURL: String,
        keyword: String,
        startedAt: Date = Date(),
        searchBooks: [SearchBook] = [],
        detail: BookDetail? = nil,
        chapters: [BookChapter] = [],
        content: ChapterContent? = nil,
        steps: [SourceDiagnosticStep] = []
    ) {
        self.id = id
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.keyword = keyword
        self.startedAt = startedAt
        self.searchBooks = searchBooks
        self.detail = detail
        self.chapters = chapters
        self.content = content
        self.steps = steps.sorted { lhs, rhs in
            guard let left = SourceDiagnosticStage.allCases.firstIndex(of: lhs.stage),
                  let right = SourceDiagnosticStage.allCases.firstIndex(of: rhs.stage) else { return false }
            return left < right
        }
    }

    var report: SourceDiagnosticReport {
        SourceDiagnosticReport(
            sourceName: sourceName,
            sourceURL: sourceURL,
            keyword: keyword,
            startedAt: startedAt,
            steps: steps
        )
    }

    var overallStatus: SourceHealthStatus { report.overallStatus }
    var isComplete: Bool {
        guard let content else { return false }
        return content.paragraphs.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && !chapters.isEmpty
            && detail != nil
            && !searchBooks.isEmpty
    }
}

/// The diagnostic-friendly form of a pipeline run. Unlike `Result`, this keeps
/// the successful prefix and every stage observation when a later stage fails.
struct SourcePipelineExecution: Sendable {
    let result: SourcePipelineResult
    let error: SourceEngineError?

    var isSuccess: Bool { error == nil }
}

extension SourceEngine {
    /// Runs the complete source chain with bounded per-stage timeouts.
    ///
    /// This is intentionally a protocol extension instead of a second engine:
    /// test doubles and future engines automatically get the same pipeline
    /// contract.  The first failure is returned with its diagnostic report in
    /// `SourcePipelineExecution`, while successful prefixes remain available to
    /// callers through the failure payload.
    func runPipelineExecution(
        source: BookSource,
        keyword: String,
        page: Int = 1,
        timeout: TimeInterval = 20
    ) async -> SourcePipelineExecution {
        let startedAt = Date()
        let cleanKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKeyword.isEmpty else {
            return SourcePipelineExecution(
                result: SourcePipelineResult(
                    sourceName: source.bookSourceName,
                    sourceURL: source.bookSourceUrl,
                    keyword: cleanKeyword,
                    startedAt: startedAt
                ),
                error: .invalidSource("测试关键词为空")
            )
        }

        var steps: [SourceDiagnosticStep] = []
        var searched: [SearchBook] = []
        var detail: BookDetail?
        var chapters: [BookChapter] = []
        var content: ChapterContent?

        func elapsed(_ start: Date) -> Int {
            max(0, Int(Date().timeIntervalSince(start) * 1_000))
        }

        func makeResult() -> SourcePipelineResult {
            SourcePipelineResult(
                sourceName: source.bookSourceName,
                sourceURL: source.bookSourceUrl,
                keyword: cleanKeyword,
                startedAt: startedAt,
                searchBooks: searched,
                detail: detail,
                chapters: chapters,
                content: content,
                steps: steps
            )
        }

        func failure(_ error: SourceEngineError, stage: SourceDiagnosticStage, start: Date, count: Int = 0) -> SourcePipelineExecution {
            let message = error.displayMessage
            steps.append(SourceDiagnosticStep(
                stage: stage,
                status: SourceDiagnosticClassifier.status(message: message, stage: stage.rawValue, resultCount: count),
                requestSummary: stage == .search ? "keyword=\(cleanKeyword)&page=\(page)" : nil,
                responseSummary: message,
                matchCount: count,
                elapsedMilliseconds: elapsed(start),
                failureClassification: String(describing: error),
                failureCode: SourceDiagnosticClassifier.kind(error: error, stage: stage.rawValue)
            ))
            return SourcePipelineExecution(result: makeResult(), error: error)
        }

        func isTransientNetworkFailure(_ error: SourceEngineError) -> Bool {
            let msg = error.displayMessage.lowercased()
            return msg.contains("超时") || msg.contains("timed out")
                || msg.contains("connection was lost") || msg.contains("connection lost")
                || msg.contains("502") || msg.contains("503") || msg.contains("520")
                || msg.contains("reset by peer")
        }

        let searchStarted = Date()
        var search = await AsyncTimeout.run(seconds: timeout) { await self.searchBooks(source: source, keyword: cleanKeyword, page: page) }
            ?? .failure(.network("搜索超时（超过 \(Int(timeout)) 秒）"))
        var searchRetried = false
        if case .failure(let error) = search, isTransientNetworkFailure(error) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            search = await AsyncTimeout.run(seconds: timeout) { await self.searchBooks(source: source, keyword: cleanKeyword, page: page) }
                ?? .failure(.network("搜索超时（超过 \(Int(timeout)) 秒）"))
            searchRetried = true
        }
        switch search {
        case .failure(let error):
            return failure(error, stage: .search, start: searchStarted)
        case .success(let books):
            searched = books
            if books.isEmpty {
                return failure(.empty("搜索结果为空"), stage: .search, start: searchStarted)
            }
            steps.append(SourceDiagnosticStep(
                stage: .search,
                status: .passed,
                requestSummary: "keyword=\(cleanKeyword)&page=\(page)",
                responseSummary: "搜索结果 \(books.count) 条",
                matchCount: books.count,
                elapsedMilliseconds: elapsed(searchStarted),
                failureClassification: nil,
                retryCount: searchRetried ? 1 : 0,
                failureCode: nil
            ))
            guard let first = books.first else { return failure(.empty("搜索结果为空"), stage: .search, start: searchStarted) }

            let detailStarted = Date()
            var detailResult = await AsyncTimeout.run(seconds: timeout) { await self.getBookDetail(source: source, book: first) }
                ?? .failure(.network("详情超时（超过 \(Int(timeout)) 秒）"))
            var detailRetried = false
            if case .failure(let error) = detailResult, isTransientNetworkFailure(error) {
                try? await Task.sleep(nanoseconds: 300_000_000)
                detailResult = await AsyncTimeout.run(seconds: timeout) { await self.getBookDetail(source: source, book: first) }
                    ?? .failure(.network("详情超时（超过 \(Int(timeout)) 秒）"))
                detailRetried = true
            }
            switch detailResult {
            case .failure(let error):
                return failure(error, stage: .detail, start: detailStarted, count: 0)
            case .success(let value):
                detail = value
                steps.append(SourceDiagnosticStep(
                    stage: .detail,
                    status: .passed,
                    requestSummary: value.bookUrl,
                    responseSummary: "详情：\(value.name)",
                    matchCount: 1,
                    elapsedMilliseconds: elapsed(detailStarted),
                    retryCount: detailRetried ? 1 : 0
                ))
            }
        }

        guard let detail else {
            return SourcePipelineExecution(result: makeResult(), error: .empty("详情结果为空"))
        }
        let tocStarted = Date()
        var tocResult = await AsyncTimeout.run(seconds: timeout) { await self.getChapterList(source: source, book: detail, maxPages: 1) }
            ?? .failure(.network("目录超时（超过 \(Int(timeout)) 秒）"))
        var tocRetried = false
        if case .failure(let error) = tocResult, isTransientNetworkFailure(error) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            tocResult = await AsyncTimeout.run(seconds: timeout) { await self.getChapterList(source: source, book: detail, maxPages: 1) }
                ?? .failure(.network("目录超时（超过 \(Int(timeout)) 秒）"))
            tocRetried = true
        }
        switch tocResult {
        case .failure(let error):
            return failure(error, stage: .toc, start: tocStarted)
        case .success(let value):
            chapters = Array(value.prefix(10))
            if value.isEmpty {
                return failure(.empty("目录为空"), stage: .toc, start: tocStarted)
            }
            steps.append(SourceDiagnosticStep(
                stage: .toc,
                status: .passed,
                requestSummary: detail.tocUrl ?? detail.bookUrl,
                responseSummary: "目录 \(value.count) 章",
                matchCount: value.count,
                elapsedMilliseconds: elapsed(tocStarted),
                failureClassification: nil,
                retryCount: tocRetried ? 1 : 0
            ))
        }

        guard let firstChapter = chapters.first else {
            return SourcePipelineExecution(result: makeResult(), error: .empty("目录为空"))
        }
        let contentStarted = Date()
        var contentResult = await AsyncTimeout.run(seconds: timeout) { await self.getContent(source: source, chapter: firstChapter, maxPages: 1) }
            ?? .failure(.network("正文超时（超过 \(Int(timeout)) 秒）"))
        var contentRetried = false
        if case .failure(let error) = contentResult, isTransientNetworkFailure(error) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            contentResult = await AsyncTimeout.run(seconds: timeout) { await self.getContent(source: source, chapter: firstChapter, maxPages: 1) }
                ?? .failure(.network("正文超时（超过 \(Int(timeout)) 秒）"))
            contentRetried = true
        }
        switch contentResult {
        case .failure(let error):
            return failure(error, stage: .content, start: contentStarted, count: 0)
        case .success(let value):
            content = value
            let isEmptyContent = value.paragraphs.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            steps.append(SourceDiagnosticStep(
                stage: .content,
                status: isEmptyContent ? .failed : .passed,
                requestSummary: firstChapter.url,
                responseSummary: "正文 \(value.paragraphs.count) 段",
                matchCount: value.paragraphs.count,
                elapsedMilliseconds: elapsed(contentStarted),
                failureClassification: isEmptyContent ? "empty-result" : nil,
                retryCount: contentRetried ? 1 : 0,
                failureCode: isEmptyContent ? .emptyResult : nil
            ))
            if isEmptyContent {
                return SourcePipelineExecution(result: makeResult(), error: .empty("正文为空"))
            }
            return SourcePipelineExecution(result: makeResult(), error: nil)
        }
    }

    /// Runs the same chain while retaining partial diagnostics for UI and
    /// export. Use this when the caller needs to explain which stage failed.
    func runPipelineReport(
        source: BookSource,
        keyword: String,
        page: Int = 1,
        timeout: TimeInterval = 20
    ) async -> SourcePipelineExecution {
        let execution = await runPipelineExecution(source: source, keyword: keyword, page: page, timeout: timeout)
        guard let provider = self as? SourceDiagnosticEvidenceProvider else { return execution }
        let report = execution.result.report
        let enrichedSteps = report.steps.map { step in
            guard let evidence = provider.diagnosticEvidence(sourceURL: report.sourceURL, stage: step.stage) else {
                return step
            }
            return SourceDiagnosticStep(
                id: step.id,
                stage: step.stage,
                status: step.status,
                requestSummary: step.requestSummary,
                responseSummary: step.responseSummary,
                matchCount: step.matchCount,
                elapsedMilliseconds: step.elapsedMilliseconds,
                failureClassification: step.failureClassification,
                requestMethod: evidence.requestMethod,
                requestBody: evidence.requestBody,
                requestHeaders: evidence.requestHeaders,
                responseStatusCode: evidence.responseStatusCode,
                responseHeaders: evidence.responseHeaders,
                cookieSummary: evidence.cookieSummary,
                finalURL: evidence.finalURL,
                responseEncodedByteCount: evidence.responseEncodedByteCount,
                responseDecodedByteCount: evidence.responseDecodedByteCount,
                responseContentEncodings: evidence.responseContentEncodings,
                responseWasDecoded: evidence.responseWasDecoded,
                javascript: evidence.javascript,
                executionLogs: evidence.executionLogs,
                retryCount: step.retryCount,
                failureCode: step.failureCode,
                retryable: step.retryable
            )
        }
        let enrichedResult = SourcePipelineResult(
            id: execution.result.id,
            sourceName: execution.result.sourceName,
            sourceURL: execution.result.sourceURL,
            keyword: execution.result.keyword,
            startedAt: execution.result.startedAt,
            searchBooks: execution.result.searchBooks,
            detail: execution.result.detail,
            chapters: execution.result.chapters,
            content: execution.result.content,
            steps: enrichedSteps
        )
        return SourcePipelineExecution(result: enrichedResult, error: execution.error)
    }

    /// Compatibility wrapper for callers that only need a conventional
    /// success/failure result.
    func runPipeline(
        source: BookSource,
        keyword: String,
        page: Int = 1,
        timeout: TimeInterval = 20
    ) async -> Result<SourcePipelineResult, SourceEngineError> {
        let execution = await runPipelineExecution(source: source, keyword: keyword, page: page, timeout: timeout)
        if let error = execution.error { return .failure(error) }
        return .success(execution.result)
    }
}
