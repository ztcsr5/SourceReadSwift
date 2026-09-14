import XCTest
@testable import SourceReadSwift

final class SourceDiagnosticReportExporterTests: XCTestCase {

    private func makeSampleBatchReport() -> SourceDiagnosticBatchReport {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let finished = Date(timeIntervalSince1970: 1_700_000_030)

        let passReport = SourceDiagnosticReport(
            sourceName: "书源A-通过",
            sourceURL: "https://a.example.com",
            keyword: "修真",
            startedAt: started,
            steps: [
                SourceDiagnosticStep(stage: .search, status: .passed, matchCount: 10),
                SourceDiagnosticStep(stage: .detail, status: .passed),
                SourceDiagnosticStep(stage: .toc, status: .passed, matchCount: 100),
                SourceDiagnosticStep(stage: .content, status: .passed)
            ]
        )

        let timeoutReport = SourceDiagnosticReport(
            sourceName: "书源B-超时",
            sourceURL: "https://b.example.com",
            keyword: "修真",
            startedAt: started,
            steps: [
                SourceDiagnosticStep(
                    stage: .search,
                    status: .failed,
                    responseSummary: "The request timed out. 连接超时",
                    failureClassification: "network.timeout",
                    responseStatusCode: 504
                )
            ]
        )

        let shieldReport = SourceDiagnosticReport(
            sourceName: "书源C-CF盾",
            sourceURL: "https://c.example.com",
            keyword: "修真",
            startedAt: started,
            steps: [
                SourceDiagnosticStep(
                    stage: .search,
                    status: .verificationRequired,
                    responseSummary: "Cloudflare Turnstile challenge detected 人机验证",
                    failureClassification: "anti_bot.cloudflare",
                    responseStatusCode: 403
                )
            ]
        )

        return SourceDiagnosticBatchReport(
            startedAt: started,
            finishedAt: finished,
            keyword: "修真",
            reports: [passReport, timeoutReport, shieldReport]
        )
    }

    func testGenerateBriefSummaryText() {
        let batch = makeSampleBatchReport()
        let text = SourceDiagnosticReportExporter.generateBriefSummaryText(from: batch, totalCount: 3)

        XCTAssertTrue(text.contains("【轻阅】书源体检精简看板"))
        XCTAssertTrue(text.contains("测试关键词：《修真》"))
        XCTAssertTrue(text.contains("检测总数：3 / 3 个书源"))
        XCTAssertTrue(text.contains("综合通过率：33.3%"))
        XCTAssertTrue(text.contains("🟢 四级全绿 (PASS): 1 (33.3%)"))
        XCTAssertTrue(text.contains("🔴 访问失败 (FAIL): 1 (33.3%)"))
        XCTAssertTrue(text.contains("🟣 验证码/盾 (VERIFY): 1 (33.3%)"))
        XCTAssertTrue(text.contains("⚠️ 主要异常分类："))
        XCTAssertTrue(text.contains("域名失效 / 连接超时") || text.contains("Cloudflare / 反爬验证码拦截"))

        let lines = text.split(separator: "\n")
        XCTAssertLessThanOrEqual(lines.count, 35)
    }

    func testGenerateBriefSummaryTextWhenAllPassed() {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let passReport = SourceDiagnosticReport(
            sourceName: "书源A",
            sourceURL: "https://a.example.com",
            keyword: "完美",
            startedAt: started,
            steps: [SourceDiagnosticStep(stage: .search, status: .passed)]
        )
        let batch = SourceDiagnosticBatchReport(
            startedAt: started,
            finishedAt: started.addingTimeInterval(5),
            keyword: "完美",
            reports: [passReport]
        )

        let text = SourceDiagnosticReportExporter.generateBriefSummaryText(from: batch, totalCount: 1)
        XCTAssertTrue(text.contains("🎉 完美！所有被检测书源均通过测试"))
        XCTAssertTrue(text.contains("综合通过率：100.0%"))
    }

    func testGenerateMarkdownReport() {
        let batch = makeSampleBatchReport()
        let md = SourceDiagnosticReportExporter.generateMarkdownReport(from: batch, totalCount: 3)

        XCTAssertTrue(md.contains("# 📖 轻阅书源全身体检诊断报告"))
        XCTAssertTrue(md.contains("### 📊 状态分布看板"))
        XCTAssertTrue(md.contains("### 🛠️ 失败原因深度分类与排错指南"))
        XCTAssertTrue(md.contains("书源B-超时"))
        XCTAssertTrue(md.contains("书源C-CF盾"))
    }

    func testSaveToDocuments() throws {
        let batch = makeSampleBatchReport()
        let md = SourceDiagnosticReportExporter.generateMarkdownReport(from: batch)
        let jsonData = try batch.exportJSON()

        let (mdURL, jsonURL) = try SourceDiagnosticReportExporter.saveToDocuments(
            markdownText: md,
            jsonData: jsonData,
            reportDate: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: mdURL.path))
        XCTAssertTrue(mdURL.lastPathComponent.contains("轻阅书源体检报告_"))
        XCTAssertTrue(mdURL.lastPathComponent.hasSuffix(".md"))

        let json = try XCTUnwrap(jsonURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: json.path))
        XCTAssertTrue(json.lastPathComponent.contains("轻阅书源诊断数据_"))
        XCTAssertTrue(json.lastPathComponent.hasSuffix(".json"))
    }

    func testCreateExportFiles() {
        let (mdURL, jsonURL) = SourceDiagnosticReportExporter.createExportFiles(
            markdownText: "# Test Report",
            jsonData: Data("{\"status\":\"ok\"}".utf8)
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: mdURL.path))
        if let jsonURL {
            XCTAssertTrue(FileManager.default.fileExists(atPath: jsonURL.path))
        }
    }

    func testGenerateCSVReport() {
        let batch = makeSampleBatchReport()
        let csv = SourceDiagnosticReportExporter.generateCSVReport(from: batch)

        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"))
        XCTAssertTrue(csv.contains("书源名称,综合状态,测试关键词,四级全绿"))
        XCTAssertTrue(csv.contains("书源A-通过"))
        XCTAssertTrue(csv.contains("书源B-超时"))
        XCTAssertTrue(csv.contains("书源C-CF盾"))
    }
}
