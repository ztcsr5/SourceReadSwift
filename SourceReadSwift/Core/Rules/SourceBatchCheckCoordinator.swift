import Foundation
import SwiftUI
import UIKit
import Combine

/// Global coordinator for running book source batch checks.
///
/// Decoupled from any single SwiftUI View or Sheet so that testing continues
/// uninterrupted when users navigate away, switch apps, or when the screen dims.
/// Includes background execution assertions (`UIBackgroundTaskIdentifier`),
/// periodic crash-resilient persistence to `last_batch_test_report.json`, and
/// progressive diagnostic recording across all four pipeline stages.
@MainActor
final class SourceBatchCheckCoordinator: ObservableObject {
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var checkedCount: Int = 0
    @Published private(set) var totalCount: Int = 0
    @Published private(set) var currentSourceName: String = ""
    @Published private(set) var passedCount: Int = 0
    @Published private(set) var searchPassedCount: Int = 0
    @Published private(set) var warningCount: Int = 0
    @Published private(set) var failedCount: Int = 0
    @Published private(set) var loginRequiredCount: Int = 0
    @Published private(set) var verificationRequiredCount: Int = 0
    @Published private(set) var blockedCount: Int = 0
    @Published private(set) var results: [SourceBatchCheckResult] = []
    private(set) var diagnosticReports: [String: SourceDiagnosticReport] = [:]
    @Published private(set) var lastSavedReport: SourceDiagnosticBatchReport? = nil
    @Published private(set) var startedAt: Date? = nil
    @Published private(set) var finishedAt: Date? = nil
    @Published private(set) var keyword: String = "斗破苍穹"
    @Published private(set) var deepCheck: Bool = true
    @Published var activeSources: [BookSource] = []

    private var activeSessionID = UUID()
    private var activeTask: Task<Void, Never>? = nil
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private let reportFileName = "last_batch_test_report.json"

    init() {
        loadLastSavedReport()
    }

    var progressFraction: Double {
        guard totalCount > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(checkedCount) / Double(totalCount)))
    }

    var summaryText: String {
        "已测 \(checkedCount)/\(totalCount) · 四级全绿 \(passedCount) · 搜书可用 \(searchPassedCount) · 异常 \(failedCount + loginRequiredCount + verificationRequiredCount + blockedCount)"
    }

    // MARK: - Lifecycle Controls

    func start(
        sources: [BookSource],
        keyword: String,
        deepCheck: Bool,
        engine: SourceEngine,
        healthStore: SourceHealthStore,
        historyStore: SourceDiagnosticHistoryStore
    ) {
        stop()

        let cleanKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sources.isEmpty, !cleanKeyword.isEmpty else { return }

        let sessionID = UUID()
        activeSessionID = sessionID
        activeSources = sources
        self.keyword = cleanKeyword
        self.deepCheck = deepCheck
        isRunning = true
        checkedCount = 0
        totalCount = sources.count
        currentSourceName = sources.first?.bookSourceName ?? ""
        passedCount = 0
        searchPassedCount = 0
        warningCount = 0
        failedCount = 0
        loginRequiredCount = 0
        verificationRequiredCount = 0
        blockedCount = 0
        results = []
        diagnosticReports = [:]
        startedAt = Date()
        finishedAt = nil

        beginBackgroundExecution()

        activeTask = Task { [weak self] in
            await self?.executeBatchCheck(
                sources: sources,
                keyword: cleanKeyword,
                deepCheck: deepCheck,
                sessionID: sessionID,
                engine: engine,
                healthStore: healthStore,
                historyStore: historyStore
            )
        }
    }

    func stop() {
        activeTask?.cancel()
        activeTask = nil
        if isRunning {
            isRunning = false
            finishedAt = Date()
            saveIncrementalReport()
        }
        endBackgroundExecution()
    }

    // MARK: - Batch Execution Loop

    private func executeBatchCheck(
        sources: [BookSource],
        keyword: String,
        deepCheck: Bool,
        sessionID: UUID,
        engine: SourceEngine,
        healthStore: SourceHealthStore,
        historyStore: SourceDiagnosticHistoryStore
    ) async {
        (engine as? SourceWebViewFallbackControllable)?.allowWebViewFallback = false
        defer {
            (engine as? SourceWebViewFallbackControllable)?.allowWebViewFallback = true
        }

        var pendingHealthRecords: [SourceHealthRecord] = []
        var pendingHistoryRecords: [SourceDiagnosticHistoryRecord] = []
        var pendingResults: [SourceBatchCheckResult] = []
        var lastCheckpointTime = Date()
        var lastUIUpdateTime = Date()
        var loopCount = 0

        var localChecked = 0
        var localPassed = 0
        var localSearchPassed = 0
        var localWarning = 0
        var localFailed = 0
        var localLoginRequired = 0
        var localVerificationRequired = 0
        var localBlocked = 0
        var latestSourceName = ""

        func syncUI() {
            guard self.checkedCount != localChecked || !pendingResults.isEmpty else { return }
            self.checkedCount = localChecked
            self.passedCount = localPassed
            self.searchPassedCount = localSearchPassed
            self.warningCount = localWarning
            self.failedCount = localFailed
            self.loginRequiredCount = localLoginRequired
            self.verificationRequiredCount = localVerificationRequired
            self.blockedCount = localBlocked
            self.currentSourceName = latestSourceName
            if !pendingResults.isEmpty {
                self.results.append(contentsOf: pendingResults)
                pendingResults.removeAll(keepingCapacity: true)
            }
        }

        func flushPending(isFinal: Bool = false) {
            if !pendingHealthRecords.isEmpty {
                healthStore.recordBatch(pendingHealthRecords, persistImmediately: isFinal)
                pendingHealthRecords.removeAll(keepingCapacity: true)
            }
            if !pendingHistoryRecords.isEmpty {
                historyStore.recordBatch(pendingHistoryRecords, persistImmediately: isFinal)
                pendingHistoryRecords.removeAll(keepingCapacity: true)
            }
            if isFinal {
                self.saveIncrementalReport()
            }
        }

        let concurrency = SandboxEnvironment.recommendedBatchConcurrency
        for batch in sources.chunked(into: concurrency) {
            guard !Task.isCancelled, activeSessionID == sessionID else { break }

            await withTaskGroup(of: BatchCheckOutcome.self) { group in
                for source in batch {
                    group.addTask {
                        await Self.evaluateSource(
                            source: source,
                            keyword: keyword,
                            engine: engine,
                            deepCheck: deepCheck
                        )
                    }
                }

                for await outcome in group {
                    guard !Task.isCancelled, self.activeSessionID == sessionID else {
                        group.cancelAll()
                        return
                    }

                    loopCount += 1
                    var result = outcome.result
                    if let report = outcome.diagnosticReport {
                        let status = SourceBatchCheckStatus(report.overallStatus)
                        let message = result.message.nilIfEmpty ?? Self.batchResultMessage(report: report, fallback: "书源未返回诊断摘要")
                        // Passed sources don't need duplicate report objects in results array
                        let retainedReport = report.overallStatus == .passed ? nil : report
                        result = SourceBatchCheckResult(
                            sourceName: result.sourceName,
                            sourceURL: result.sourceURL,
                            status: status,
                            message: message,
                            elapsedMilliseconds: result.elapsedMilliseconds,
                            resultCount: report.steps.first(where: { $0.stage == .search })?.matchCount ?? result.resultCount,
                            diagnosticReport: retainedReport
                        )
                    }

                    localChecked += 1
                    latestSourceName = outcome.source.bookSourceName
                    pendingResults.append(result)
                    if let report = outcome.diagnosticReport {
                        // Store lightweight version for passed sources to prune heavy JavaScript strings & logs
                        self.diagnosticReports[outcome.source.bookSourceUrl] = report.slimmedForBatchRetention()
                    }

                    // Count statistics locally
                    switch result.status {
                    case .passed: localPassed += 1
                    case .warning: localWarning += 1
                    case .failed: localFailed += 1
                    case .requiresLogin: localLoginRequired += 1
                    case .verificationRequired: localVerificationRequired += 1
                    case .blocked: localBlocked += 1
                    }

                    if result.resultCount > 0 {
                        localSearchPassed += 1
                    }

                    // Record health
                    pendingHealthRecords.append(SourceHealthRecord(
                        sourceURL: outcome.source.bookSourceUrl,
                        sourceName: outcome.source.bookSourceName,
                        status: result.status.healthStatus,
                        message: result.message,
                        keyword: keyword,
                        resultCount: outcome.resultCount,
                        testedAt: Date()
                    ))

                    // Record detailed diagnostic history stages
                    if let report = outcome.diagnosticReport {
                        for step in report.steps {
                            let stageName = "batch.\(step.stage.rawValue)"
                            let stepMessage = step.responseSummary ?? step.failureClassification ?? result.message
                            pendingHistoryRecords.append(SourceDiagnosticHistoryRecord(
                                sourceURL: outcome.source.bookSourceUrl,
                                sourceName: outcome.source.bookSourceName,
                                stage: stageName,
                                status: step.status,
                                message: stepMessage,
                                elapsedMilliseconds: step.elapsedMilliseconds,
                                resultCount: step.matchCount
                            ))
                        }
                    } else {
                        pendingHistoryRecords.append(SourceDiagnosticHistoryRecord(
                            sourceURL: outcome.source.bookSourceUrl,
                            sourceName: outcome.source.bookSourceName,
                            stage: "batch.search",
                            status: outcome.result.status.healthStatus,
                            message: outcome.result.message,
                            resultCount: outcome.resultCount
                        ))
                    }

                    if let login = outcome.login {
                        pendingHistoryRecords.append(SourceDiagnosticHistoryRecord(
                            sourceURL: result.sourceURL,
                            sourceName: result.sourceName,
                            stage: "batch.login",
                            status: login.status,
                            message: login.message
                        ))
                    }

                    let now = Date()
                    // Throttle SwiftUI mutations (every 250ms or 12 items) to keep the UI smooth and prevent Task floods
                    if now.timeIntervalSince(lastUIUpdateTime) >= 0.25 || pendingResults.count >= 12 {
                        lastUIUpdateTime = now
                        syncUI()
                    }

                    // Non-blocking background checkpoint at most once every 45 seconds
                    if now.timeIntervalSince(lastCheckpointTime) >= 45.0 {
                        lastCheckpointTime = now
                        flushPending(isFinal: false)
                        self.saveIncrementalReport()
                        URLCache.shared.removeAllCachedResponses()
                    }
                }
            }

            // Sync UI and release network cache per chunk
            syncUI()
            URLCache.shared.removeAllCachedResponses()
        }

        syncUI()
        flushPending(isFinal: true)
        healthStore.flushToDisk()
        historyStore.flushToDisk()
        URLCache.shared.removeAllCachedResponses()

        guard !Task.isCancelled, activeSessionID == sessionID else {
            endBackgroundExecution()
            return
        }

        // Sort results: errors first, then slowest, then by name
        results.sort { lhs, rhs in
            if lhs.status.priority != rhs.status.priority {
                return lhs.status.priority < rhs.status.priority
            }
            if lhs.elapsedMilliseconds != rhs.elapsedMilliseconds {
                return lhs.elapsedMilliseconds > rhs.elapsedMilliseconds
            }
            return lhs.sourceName.localizedCaseInsensitiveCompare(rhs.sourceName) == .orderedAscending
        }

        isRunning = false
        finishedAt = Date()
        saveIncrementalReport()
        endBackgroundExecution()
    }

    private static func evaluateSource(
        source: BookSource,
        keyword: String,
        engine: SourceEngine,
        deepCheck: Bool
    ) async -> BatchCheckOutcome {
        let startedAt = Date()
        var loginMessage = ""
        var login: BatchLoginOutcome?
        if source.loginCheckJs?.nilIfEmpty != nil {
            let loginResult = await AsyncTimeout.run(seconds: 10) {
                await engine.verifyLogin(source: source)
            } ?? .failure(.network("Login check timed out"))
            switch loginResult {
            case .success(let verification):
                loginMessage = "登录检查：\(verification.message)"
                login = BatchLoginOutcome(status: verification.status.healthStatus, message: verification.message)
            case .failure(let error):
                loginMessage = "登录检查失败：\(error.displayMessage)"
                login = BatchLoginOutcome(status: .warning, message: error.displayMessage)
            }
        }

        let report = await SourceBatchDiagnosticRunner(engine: engine).run(
            source: source,
            keyword: keyword,
            deepCheck: deepCheck,
            page: 1,
            timeout: 10
        )
        let searchStep = report.steps.first(where: { $0.stage == .search })
        let elapsed = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
        let baseStatus = SourceBatchCheckStatus(report.overallStatus)
        let message = [loginMessage, report.firstFailure?.responseSummary, searchStep?.responseSummary]
            .compactMap { $0?.nilIfEmpty }
            .first ?? batchResultMessage(report: report, fallback: "完成测试")

        return BatchCheckOutcome(
            source: source,
            result: SourceBatchCheckResult(
                sourceName: source.bookSourceName,
                sourceURL: source.bookSourceUrl,
                status: baseStatus,
                message: message,
                elapsedMilliseconds: elapsed,
                resultCount: searchStep?.matchCount ?? 0,
                diagnosticReport: report
            ),
            resultCount: searchStep?.matchCount ?? 0,
            login: login,
            diagnosticReport: report
        )
    }

    private static func batchResultMessage(report: SourceDiagnosticReport, fallback: String) -> String {
        if let failure = report.firstFailure {
            let advice = SourceDiagnosticRepairAdvisor.advice(for: failure)
            let classification = failure.failureClassification?.nilIfEmpty.map { " (\($0))" } ?? ""
            return "[\(failure.stage.title)失败] \(advice.title)\(classification)"
        }
        if let search = report.steps.first(where: { $0.stage == .search }), search.matchCount > 0 {
            return "全链路测试通过，搜索匹配 \(search.matchCount) 条"
        }
        return fallback
    }

    // MARK: - Background Task Handling

    private func beginBackgroundExecution() {
        endBackgroundExecution()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "SourceBatchCheckCoordinator") { [weak self] in
            Task { @MainActor [weak self] in
                self?.stop()
            }
        }
    }

    private func endBackgroundExecution() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }

    // MARK: - Persistence & Recovery

    func saveIncrementalReport() {
        let currentReports = Array(diagnosticReports.values)
        guard !currentReports.isEmpty else { return }
        let batchReport = SourceDiagnosticBatchReport(
            startedAt: startedAt ?? Date(),
            finishedAt: finishedAt ?? Date(),
            keyword: keyword,
            reports: currentReports
        )
        self.lastSavedReport = batchReport
        let fileName = self.reportFileName
        Task.detached(priority: .utility) {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(batchReport)
                let url = AppStorageDirectory.appStorageURL(fileName: fileName)
                try AppStorageDirectory.safeWrite(data, to: url)
            } catch {
                // Non-critical background save error
            }
        }
    }

    func loadLastSavedReport() {
        let url = AppStorageDirectory.appStorageURL(fileName: reportFileName)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let report = try? JSONDecoder().decode(SourceDiagnosticBatchReport.self, from: data) else {
            return
        }
        self.lastSavedReport = report
        self.keyword = report.keyword
        self.startedAt = report.startedAt
        self.finishedAt = report.finishedAt

        // Populate results list if idle
        if !isRunning && results.isEmpty {
            self.totalCount = report.totalCount
            self.checkedCount = report.totalCount
            self.passedCount = report.passedCount
            self.searchPassedCount = report.reports.filter { r in
                (r.steps.first(where: { $0.stage == .search })?.matchCount ?? 0) > 0
            }.count
            self.warningCount = report.warningCount
            self.failedCount = report.failedCount
            var reconstructed: [SourceBatchCheckResult] = []
            for item in report.reports {
                self.diagnosticReports[item.sourceURL] = item
                let searchStep = item.steps.first(where: { $0.stage == .search })
                reconstructed.append(SourceBatchCheckResult(
                    sourceName: item.sourceName,
                    sourceURL: item.sourceURL,
                    status: SourceBatchCheckStatus(item.overallStatus),
                    message: item.firstFailure?.responseSummary ?? searchStep?.responseSummary ?? "历史诊断记录",
                    elapsedMilliseconds: item.steps.compactMap(\.elapsedMilliseconds).reduce(0, +),
                    resultCount: searchStep?.matchCount ?? 0,
                    diagnosticReport: item
                ))
            }
            self.results = reconstructed
        }
    }
}

struct SourceBatchCheckResult: Identifiable, Sendable {
    let id = UUID()
    let sourceName: String
    let sourceURL: String
    let status: SourceBatchCheckStatus
    let message: String
    let elapsedMilliseconds: Int
    let resultCount: Int
    let diagnosticReport: SourceDiagnosticReport?

    init(
        sourceName: String,
        sourceURL: String,
        status: SourceBatchCheckStatus,
        message: String,
        elapsedMilliseconds: Int = 0,
        resultCount: Int = 0,
        diagnosticReport: SourceDiagnosticReport? = nil
    ) {
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.status = status
        self.message = message
        self.elapsedMilliseconds = max(0, elapsedMilliseconds)
        self.resultCount = max(0, resultCount)
        self.diagnosticReport = diagnosticReport
    }
}

enum SourceBatchCheckStatus: Equatable, Sendable {
    case passed
    case warning
    case failed
    case requiresLogin
    case verificationRequired
    case blocked

    var priority: Int {
        switch self {
        case .failed, .blocked, .verificationRequired, .requiresLogin: return 0
        case .warning: return 1
        case .passed: return 2
        }
    }

    init(_ status: SourceHealthStatus) {
        switch status {
        case .passed: self = .passed
        case .warning: self = .warning
        case .failed: self = .failed
        case .requiresLogin: self = .requiresLogin
        case .verificationRequired: self = .verificationRequired
        case .blocked: self = .blocked
        }
    }

    var healthStatus: SourceHealthStatus {
        switch self {
        case .passed: return .passed
        case .warning: return .warning
        case .failed: return .failed
        case .requiresLogin: return .requiresLogin
        case .verificationRequired: return .verificationRequired
        case .blocked: return .blocked
        }
    }

    var title: String {
        switch self {
        case .passed: return "PASS"
        case .warning: return "WARN"
        case .failed: return "FAIL"
        case .requiresLogin: return "LOGIN"
        case .verificationRequired: return "VERIFY"
        case .blocked: return "BLOCKED"
        }
    }

    var systemImage: String {
        switch self {
        case .passed: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.circle.fill"
        case .requiresLogin: return "person.crop.circle.badge.exclamationmark"
        case .verificationRequired: return "shield.lefthalf.filled.badge.exclamationmark"
        case .blocked: return "hand.raised.slash.fill"
        }
    }

    var color: Color {
        switch self {
        case .passed: return .green
        case .warning: return .orange
        case .failed: return .red
        case .requiresLogin: return .orange
        case .verificationRequired: return .purple
        case .blocked: return .red.opacity(0.8)
        }
    }
}

struct BatchLoginOutcome: Sendable {
    let status: SourceHealthStatus
    let message: String
}

struct BatchCheckOutcome: Sendable {
    let source: BookSource
    let result: SourceBatchCheckResult
    let resultCount: Int
    let login: BatchLoginOutcome?
    let diagnosticReport: SourceDiagnosticReport?
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        var result: [[Element]] = []
        result.reserveCapacity((count + size - 1) / size)
        var start = 0
        while start < count {
            let end = Swift.min(start + size, count)
            result.append(Array(self[start..<end]))
            start = end
        }
        return result
    }
}
