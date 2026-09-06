import XCTest
@testable import SourceReadSwift

final class SourceDiagnosticRepairAdvisorTests: XCTestCase {
    func testAdviceMapsFailedStageToEditorFieldAndSafeSample() {
        let step = SourceDiagnosticStep(
            stage: .content,
            status: .failed,
            responseSummary: "正文选择器未命中",
            responseStatusCode: 200,
            requestHeaders: ["Cookie": "session=secret"],
            executionLogs: ["token=secret-token"],
            failureCode: .parsing
        )

        let advice = SourceDiagnosticRepairAdvisor.advice(for: step)

        XCTAssertEqual(advice.stage, .content)
        XCTAssertEqual(advice.fieldName, "ruleContent")
        XCTAssertTrue(advice.title.contains("正文"))
        XCTAssertFalse(advice.suggestedSample.contains("secret"))
        XCTAssertTrue(advice.actions.contains { $0.contains("选择器") })
        XCTAssertTrue(advice.compactSummary.contains("正文"))
        XCTAssertTrue(advice.compactSummary.contains("正文选择器未命中"))
    }

    func testAdviceKeepsStageSpecificNetworkGuidance() {
        let step = SourceDiagnosticStep(
            stage: .search,
            status: .failed,
            responseSummary: "搜索超时",
            failureCode: .timeout
        )

        let advice = SourceDiagnosticRepairAdvisor.advice(for: step)

        XCTAssertEqual(advice.fieldName, "ruleSearch")
        XCTAssertTrue(advice.actions.contains { $0.contains("搜索 URL") })
        XCTAssertTrue(advice.suggestedSample.contains("result"))
    }
}
