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
        await SourceRequestContext.$isDiagnostic.withValue(true) {
            await runIsolated(source: source, keyword: keyword, deepCheck: deepCheck, page: page, timeout: timeout)
        }
    }

    private func runIsolated(source: BookSource, keyword: String, deepCheck: Bool,
                             page: Int, timeout: TimeInterval) async -> SourceDiagnosticReport {
        let startedAt = Date()
        let browsesCategories = !source.hasSearchEntry && source.hasExploreEntry
        let cleanKeyword = browsesCategories ? "" : keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        (engine as? SourceDiagnosticEvidenceProvider)?.resetDiagnosticEvidence(sourceURL: source.bookSourceUrl)

        guard browsesCategories || !cleanKeyword.isEmpty else {
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

        let listing = browsesCategories ? "寻书分类" : "搜索"
        let requestSummary = browsesCategories ? "explore&page=\(page)" : "keyword=\(cleanKeyword)&page=\(page)"
        let searchStarted = Date()
        let result = await AsyncTimeout.run(seconds: max(timeout, 0), operation: {
            await self.engine.listForPipeline(source: source, keyword: cleanKeyword, page: page)
        }) ?? .failure(.network("\(listing)超时"))
        let elapsed = max(0, Int(Date().timeIntervalSince(searchStarted) * 1_000))

        let step: SourceDiagnosticStep
        switch result {
        case .success(let books):
            let isEmpty = books.isEmpty
            step = SourceDiagnosticStep(
                stage: .search,
                status: isEmpty ? .warning : .passed,
                requestSummary: requestSummary,
                responseSummary: isEmpty ? "\(listing)结果为空" : "\(listing)结果 \(books.count) 条",
                matchCount: books.count,
                elapsedMilliseconds: elapsed,
                failureClassification: isEmpty ? "empty-result" : nil,
                failureCode: isEmpty ? .emptyResult : nil
            )
        case .failure(let error):
            step = SourceDiagnosticStep(
                stage: .search,
                status: SourceDiagnosticClassifier.status(message: error.displayMessage, stage: "search"),
                requestSummary: requestSummary,
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

            if status != .passed, step.responseSummary != SourceChapterNotice.updateMessage {
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

        // Refill a slot as soon as it finishes. Fixed batches made every fast
        // source wait for the slowest timeout before any new probe could start.
        await withTaskGroup(of: SourceDiagnosticReport.self) { group in
            var iterator = sources.makeIterator()
            func submit(_ source: BookSource) {
                group.addTask {
                    await self.run(source: source, keyword: keyword, deepCheck: deepCheck,
                                   page: page, timeout: timeout)
                }
            }
            for _ in 0..<min(size, sources.count) {
                if Task.isCancelled { break }
                if let source = iterator.next() { submit(source) }
            }
            while let report = await group.next() {
                if Task.isCancelled { group.cancelAll(); break }
                reports.append(report)
                completed += 1
                await progress?(completed, report)
                if let source = iterator.next() { submit(source) }
            }
        }

        return SourceDiagnosticBatchReport(
            startedAt: startedAt,
            finishedAt: Date(),
            keyword: keyword,
            reports: reports
        )
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
                requestSummary: keyword.isEmpty ? "explore" : "keyword=" + keyword,
                responseSummary: message,
                failureClassification: "timeout",
                failureCode: .timeout
            )]
        )
    }
}
