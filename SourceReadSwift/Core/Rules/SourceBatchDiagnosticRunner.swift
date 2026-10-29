import Foundation

/// Executes source diagnostics through the same pipeline used by the reader.
///
/// The old Source Manager batch check compressed a deep check into one search
/// row and then appended a free-form string.  That made exported reports lose
/// the stage that actually failed.  This runner keeps one structured report
/// per source, including Search -> Detail -> TOC -> Content when deep checks
/// are enabled, while retaining a bounded fan-out for large source libraries.
struct SourceBatchDiagnosticRunner: Sendable {
    let engine: SourceEngine

    init(engine: SourceEngine) {
        self.engine = engine
    }

    /// Runs one source.  `deepCheck` uses the production four-stage pipeline;
    /// a shallow run intentionally records only Search for quick health scans.
    func run(
        source: BookSource,
        keyword: String,
        deepCheck: Bool,
        page: Int = 1,
        timeout: TimeInterval = 10
    ) async -> SourceDiagnosticReport {
        (engine as? SourceWebViewFallbackControllable)?.allowWebViewFallback = false
        let startedAt = Date()
        let cleanKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        (engine as? SourceDiagnosticEvidenceProvider)?.resetDiagnosticEvidence(sourceURL: source.bookSourceUrl)

        // Legado allows 发现页专用 sources: `searchUrl` is empty and books are
        // browsed from 发现.  The old check failed them with "searchUrl 为空"
        // and the one-tap cleanup then disabled working sources.
        if Self.isExploreOnly(source) {
            return await runExploreProbe(source: source, startedAt: startedAt, timeout: timeout)
        }

        guard !cleanKeyword.isEmpty else {
            return SourceDiagnosticReport(
                sourceName: source.bookSourceName,
                sourceURL: source.bookSourceUrl,
                keyword: cleanKeyword,
                startedAt: startedAt,
                steps: [SourceDiagnosticStep(
                    stage: .search,
                    status: .failed,
                    requestSummary: "keyword=",
                    responseSummary: "测试关键词为空",
                    failureClassification: "empty-keyword",
                    failureCode: .invalidInput
                )]
            )
        }

        if deepCheck {
            // The pipeline applies the timeout per stage.  Give the outer
            // guard enough room for all four stages plus a small scheduling
            // margin, so a slow source still returns a report instead of
            // disappearing from the batch.
            let outerTimeout = max(timeout * 4 + 1, 1)
            if let execution = await AsyncTimeout.run(seconds: outerTimeout, operation: {
                await self.engine.runPipelineReport(
                    source: source,
                    keyword: cleanKeyword,
                    page: page,
                    timeout: timeout
                )
            }) {
                let report = enrichedReport(execution.result.report)
                (self.engine as? SourceDiagnosticEvidenceProvider)?.resetDiagnosticEvidence(sourceURL: source.bookSourceUrl)
                return report
            }

            return timeoutReport(
                source: source,
                keyword: cleanKeyword,
                startedAt: startedAt,
                message: "完整链路超时（超过 " + String(Int(outerTimeout)) + " 秒）"
            )
        }

        let searchStarted = Date()
        let result = await AsyncTimeout.run(seconds: max(timeout, 0), operation: {
            await self.engine.searchBooks(source: source, keyword: cleanKeyword, page: page)
        }) ?? .failure(.network("搜索超时（超过 " + String(Int(timeout)) + " 秒）"))
        let elapsed = max(0, Int(Date().timeIntervalSince(searchStarted) * 1_000))

        let step: SourceDiagnosticStep
        switch result {
        case .success(let books):
            let isEmpty = books.isEmpty
            step = SourceDiagnosticStep(
                stage: .search,
                status: isEmpty ? .warning : .passed,
                requestSummary: "keyword=" + cleanKeyword + "&page=" + String(page),
                responseSummary: isEmpty ? "搜索结果为空" : "搜索结果 " + String(books.count) + " 条",
                matchCount: books.count,
                elapsedMilliseconds: elapsed,
                failureClassification: isEmpty ? "empty-result" : nil,
                failureCode: isEmpty ? .emptyResult : nil
            )
        case .failure(let error):
            step = SourceDiagnosticStep(
                stage: .search,
                status: SourceDiagnosticClassifier.status(message: error.displayMessage, stage: "search"),
                requestSummary: "keyword=" + cleanKeyword + "&page=" + String(page),
                responseSummary: error.displayMessage,
                elapsedMilliseconds: elapsed,
                failureClassification: String(describing: error),
                failureCode: SourceDiagnosticClassifier.kind(error: error, stage: "search")
            )
        }

        let report = enrichedReport(SourceDiagnosticReport(
            sourceName: source.bookSourceName,
            sourceURL: source.bookSourceUrl,
            keyword: cleanKeyword,
            startedAt: startedAt,
            steps: [step]
        ))
        (self.engine as? SourceDiagnosticEvidenceProvider)?.resetDiagnosticEvidence(sourceURL: source.bookSourceUrl)
        return report
    }

    private func enrichedReport(_ report: SourceDiagnosticReport) -> SourceDiagnosticReport {
        guard let provider = engine as? SourceDiagnosticEvidenceProvider else { return report }
        let steps = report.steps.map { step in
            guard let evidence = provider.diagnosticEvidence(sourceURL: report.sourceURL, stage: step.stage) else {
                return step
            }
            var status = step.status
            var summary = step.responseSummary
            var failureClass = step.failureClassification
            var failureCode = step.failureCode

            if status != .passed {
                if let sniffed = SourceDiagnosticClassifier.sniffSnippet(
                    snippet: evidence.responseSnippet,
                    statusCode: evidence.responseStatusCode,
                    decodedByteCount: evidence.responseDecodedByteCount,
                    stage: step.stage.rawValue
                ) {
                    status = sniffed.status
                    failureClass = sniffed.classification
                    failureCode = sniffed.kind
                    summary = sniffed.summary
                }
            }

            return SourceDiagnosticStep(
                id: step.id,
                stage: step.stage,
                status: status,
                requestSummary: step.requestSummary,
                responseSummary: summary,
                matchCount: step.matchCount,
                elapsedMilliseconds: step.elapsedMilliseconds,
                failureClassification: failureClass,
                requestMethod: evidence.requestMethod,
                requestBody: evidence.requestBody.map { $0.count > 1000 ? String($0.prefix(1000)) + "..." : $0 },
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
                executionLogs: Array(evidence.executionLogs.suffix(20)),
                retryCount: step.retryCount,
                failureCode: failureCode,
                retryable: step.retryable,
                responseSnippet: evidence.responseSnippet,
                ruleSummary: evidence.ruleSummary
            )
        }
        return SourceDiagnosticReport(
            id: report.id,
            sourceName: report.sourceName,
            sourceURL: report.sourceURL,
            keyword: report.keyword,
            startedAt: report.startedAt,
            steps: steps
        )
    }

    /// Runs all sources in bounded batches.  The optional callback is invoked
    /// on each completed source and is intentionally async so SwiftUI callers
    /// can update progress without blocking network tasks.
    func run(
        sources: [BookSource],
        keyword: String,
        deepCheck: Bool,
        page: Int = 1,
        timeout: TimeInterval = 10,
        batchSize: Int = SandboxEnvironment.recommendedBatchConcurrency,
        progress: (@Sendable (Int, SourceDiagnosticReport) async -> Void)? = nil
    ) async -> SourceDiagnosticBatchReport {
        let startedAt = Date()
        guard !sources.isEmpty else {
            return SourceDiagnosticBatchReport(
                startedAt: startedAt,
                finishedAt: Date(),
                keyword: keyword,
                reports: []
            )
        }

        let size = max(batchSize, 1)
        var reports: [SourceDiagnosticReport] = []
        reports.reserveCapacity(sources.count)
        var completed = 0

        var start = 0
        while start < sources.count {
            if Task.isCancelled { break }
            let end = Swift.min(start + size, sources.count)
            let batch = Array(sources[start..<end])
            await withTaskGroup(of: SourceDiagnosticReport.self) { group in
                for source in batch {
                    group.addTask {
                        await self.run(
                            source: source,
                            keyword: keyword,
                            deepCheck: deepCheck,
                            page: page,
                            timeout: timeout
                        )
                    }
                }
                for await report in group {
                    reports.append(report)
                    completed += 1
                    await progress?(completed, report)
                }
            }
            start = end
        }

        return SourceDiagnosticBatchReport(
            startedAt: startedAt,
            finishedAt: Date(),
            keyword: keyword,
            reports: reports
        )
    }

    /// True when the source has no search endpoint but does expose 发现分类.
    private static func isExploreOnly(_ source: BookSource) -> Bool {
        let search = (source.searchUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let explore = (source.exploreUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return search.isEmpty && !explore.isEmpty
    }

    /// Exercises the first 发现 category so explore-only sources get a real
    /// verdict instead of a "缺搜索地址" failure.
    private func runExploreProbe(
        source: BookSource,
        startedAt: Date,
        timeout: TimeInterval
    ) async -> SourceDiagnosticReport {
        let categories = ExploreCategoryParser.parse(exploreUrl: source.exploreUrl, source: source)
        guard let category = categories.first else {
            return SourceDiagnosticReport(
                sourceName: source.bookSourceName,
                sourceURL: source.bookSourceUrl,
                keyword: "",
                startedAt: startedAt,
                steps: [SourceDiagnosticStep(
                    stage: .search,
                    status: .warning,
                    requestSummary: "explore",
                    responseSummary: "书源没有 searchUrl，exploreUrl 也解析不出分类",
                    failureClassification: "explore-empty",
                    failureCode: .invalidSource
                )]
            )
        }
        let probeStarted = Date()
        let result = await AsyncTimeout.run(seconds: max(timeout, 0.1), operation: {
            await self.engine.exploreBooks(source: source, url: category.url, page: 1)
        }) ?? .failure(.network("发现页超时（超过 " + String(Int(timeout)) + " 秒）"))
        let elapsed = max(0, Int(Date().timeIntervalSince(probeStarted) * 1_000))
        switch result {
        case .success(let books):
            return SourceDiagnosticReport(
                sourceName: source.bookSourceName,
                sourceURL: source.bookSourceUrl,
                keyword: "",
                startedAt: startedAt,
                steps: [SourceDiagnosticStep(
                    stage: .search,
                    status: books.isEmpty ? .warning : .passed,
                    requestSummary: "explore=" + category.title,
                    responseSummary: "发现页「" + category.title + "」返回 " + String(books.count) + " 条",
                    matchCount: books.count,
                    elapsedMilliseconds: elapsed,
                    failureClassification: books.isEmpty ? "explore-empty-result" : nil,
                    failureCode: books.isEmpty ? .emptyResult : nil
                )]
            )
        case .failure(let error):
            return SourceDiagnosticReport(
                sourceName: source.bookSourceName,
                sourceURL: source.bookSourceUrl,
                keyword: "",
                startedAt: startedAt,
                steps: [SourceDiagnosticStep(
                    stage: .search,
                    status: SourceDiagnosticClassifier.status(message: error.displayMessage, stage: "search"),
                    requestSummary: "explore=" + category.title,
                    responseSummary: error.displayMessage,
                    elapsedMilliseconds: elapsed,
                    failureClassification: "explore",
                    failureCode: .network
                )]
            )
        }
    }

    private func timeoutReport(
        source: BookSource,
        keyword: String,
        startedAt: Date,
        message: String
    ) -> SourceDiagnosticReport {
        SourceDiagnosticReport(
            sourceName: source.bookSourceName,
            sourceURL: source.bookSourceUrl,
            keyword: keyword,
            startedAt: startedAt,
            steps: [SourceDiagnosticStep(
                stage: .search,
                status: .warning,
            requestSummary: "keyword=" + keyword,
                responseSummary: message,
                failureClassification: "timeout",
                failureCode: .timeout
            )]
        )
    }
}
