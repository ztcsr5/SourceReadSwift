import XCTest
@testable import SourceReadSwift

final class SourceLoginFeedbackTests: XCTestCase {
    func testSavedCookiesNeverTurnAnUnknownLoginIntoSuccess() {
        for cookiePresent in [false, true] {
            let feedback = SourceLoginFeedback(verification: SourceLoginVerification(
                status: .notConfigured, message: "No check", cookiePresent: cookiePresent))
            XCTAssertEqual(feedback.tone, .warning)
            XCTAssertEqual(feedback.title, "登录状态尚未验证")
            XCTAssertTrue(feedback.message.contains("没有提供登录状态校验"))
        }
    }

    func testOnlyPassedVerdictGetsSuccessfulLoginFeedback() {
        let expected: [(SourceLoginVerification.Status, SourceLoginFeedback.Tone)] = [
            (.passed, .success), (.requiresLogin, .failure), (.verificationRequired, .warning),
            (.blocked, .failure), (.warning, .warning)
        ]
        for (status, tone) in expected {
            let feedback = SourceLoginFeedback(verification: SourceLoginVerification(
                status: status, message: "Authored verdict", cookiePresent: true))
            XCTAssertEqual(feedback.tone, tone)
            XCTAssertEqual(feedback.message, "Authored verdict")
        }
    }

    func testFailedLoginRemainsFailureEvenWhenCookiesExist() {
        let feedback = SourceLoginFeedback(verification: SourceLoginVerification(
            status: .requiresLogin, message: "账号或密码错误", cookiePresent: true))
        XCTAssertEqual(feedback.title, "登录未成功")
        XCTAssertEqual(feedback.tone, .failure)
        XCTAssertEqual(feedback.message, "账号或密码错误")
    }
}
