import XCTest
@testable import SourceReadSwift

final class VerificationCodeCoordinatorTests: XCTestCase {

    private enum WaitError: Error {
        case timedOut
    }

    override func tearDown() async throws {
        await MainActor.run {
            if let request = VerificationCodeCoordinator.shared.request {
                VerificationCodeCoordinator.shared.cancel(id: request.id)
            }
        }
        try await super.tearDown()
    }

    // MARK: - URL resolution

    func testResolverKeepsAbsoluteURLAndJoinsRelativePath() {
        XCTAssertEqual(
            VerificationCodeURLResolver.resolve(
                imageURL: "captcha.png",
                baseURL: "https://example.com/path/"
            ),
            "https://example.com/path/captcha.png"
        )
        XCTAssertEqual(
            VerificationCodeURLResolver.resolve(
                imageURL: "/captcha.png",
                baseURL: "https://example.com/path/"
            ),
            "https://example.com/captcha.png"
        )
        XCTAssertEqual(
            VerificationCodeURLResolver.resolve(
                imageURL: "https://cdn.example.com/c.png?t=1",
                baseURL: "https://example.com/"
            ),
            "https://cdn.example.com/c.png?t=1"
        )
        XCTAssertEqual(
            VerificationCodeURLResolver.resolve(imageURL: "  ", baseURL: "https://example.com/"),
            ""
        )
    }

    // MARK: - Sheet lifecycle

    @MainActor
    func testSubmitReturnsTrimmedCode() async throws {
        let task = Task.detached { () -> String in
            VerificationCodeCoordinator.requestSynchronously(
                imageURL: "captcha.png",
                sourceName: "Fixture",
                stage: "search",
                baseURL: "https://example.com/path/",
                cookieHeader: "sid=abc",
                timeout: 5
            )
        }

        let request = try await waitForRequest()
        XCTAssertEqual(request.imageURL, "https://example.com/path/captcha.png")
        XCTAssertEqual(request.sourceName, "Fixture")
        XCTAssertEqual(request.stage, "search")
        XCTAssertEqual(request.cookieHeader, "sid=abc")

        VerificationCodeCoordinator.shared.submit(id: request.id, code: " 42 ")
        let value = await task.value
        XCTAssertEqual(value, "42")
        XCTAssertNil(VerificationCodeCoordinator.shared.request)
    }
    @MainActor
    func testCancelReturnsEmpty() async throws {
        let task = Task.detached { () -> String in
            VerificationCodeCoordinator.requestSynchronously(
                imageURL: "https://example.com/captcha.png",
                sourceName: "Fixture",
                stage: "toc",
                baseURL: "https://example.com/",
                cookieHeader: "",
                timeout: 5
            )
        }

        let request = try await waitForRequest()
        VerificationCodeCoordinator.shared.cancel(id: request.id)
        let value = await task.value
        XCTAssertEqual(value, "")
        XCTAssertNil(VerificationCodeCoordinator.shared.request)
    }

    @MainActor
    func testTimeoutReturnsEmptyAndClearsStaleRequest() async throws {
        let task = Task.detached { () -> String in
            VerificationCodeCoordinator.requestSynchronously(
                imageURL: "https://example.com/captcha.png",
                sourceName: "Fixture",
                stage: "content",
                baseURL: "https://example.com/",
                cookieHeader: "",
                timeout: 2.0
            )
        }

        _ = try await waitForRequest(timeout: 10)
        let value = await task.value
        XCTAssertEqual(value, "")

        // The timeout path cancels the sheet on the main actor; give that hop
        // a bounded window instead of asserting immediately.
        for _ in 0..<250 {
            if VerificationCodeCoordinator.shared.request == nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNil(VerificationCodeCoordinator.shared.request)
    }

    @MainActor
    func testMainThreadCallReturnsEmptyWithoutPresenting() {
        let start = Date()
        let value = VerificationCodeCoordinator.requestSynchronously(
            imageURL: "https://example.com/captcha.png",
            sourceName: "Fixture",
            stage: "search",
            baseURL: "https://example.com/",
            cookieHeader: "",
            timeout: 5
        )
        XCTAssertEqual(value, "")
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
        XCTAssertNil(VerificationCodeCoordinator.shared.request)
    }
    // MARK: - JavaScript bridge caching

    func testProviderCachesResolvedURLAcrossRelativeAndAbsoluteCalls() throws {
        let source = BookSource(
            bookSourceName: "Captcha fixture",
            bookSourceUrl: "https://fixture.local/path/"
        )
        let context = RuleExecutionContext(source: source)
        let counter = LockedCounter()
        context.verificationCodeProvider = { imageURL in
            counter.increment()
            XCTAssertEqual(imageURL, "https://fixture.local/path/captcha.png")
            return "42"
        }
        let runtime = JSCoreRuntime(executionContext: context)

        let result = runtime.evaluate(
            """
            JSON.stringify([
              java.getVerificationCode('captcha.png'),
              java.getVerificationCode('https://fixture.local/path/captcha.png'),
              java.getVerificationCode('captcha.png')
            ])
            """
        )
        guard case .success(let value) = result,
              let data = value.data(using: .utf8),
              let values = try JSONSerialization.jsonObject(with: data) as? [String] else {
            return XCTFail("expected captcha values: \(result)")
        }
        XCTAssertEqual(values, ["42", "42", "42"])
        XCTAssertEqual(counter.value, 1)
        XCTAssertFalse(context.logs().contains { $0.contains("verification-required") })
    }

    func testProviderFailureLogsVerificationRequired() throws {
        let source = BookSource(
            bookSourceName: "Captcha fixture",
            bookSourceUrl: "https://fixture.local/path/"
        )
        let context = RuleExecutionContext(source: source)
        context.verificationCodeProvider = { _ in "" }
        let runtime = JSCoreRuntime(executionContext: context)

        let result = runtime.evaluate("java.getVerificationCode('captcha.png')")
        guard case .success(let value) = result else {
            return XCTFail("expected empty captcha value: \(result)")
        }
        XCTAssertEqual(value, "")
        XCTAssertTrue(context.logs().contains { $0.contains("verification-required") })
    }

    // MARK: - Helpers

    @MainActor
    private func waitForRequest(timeout: TimeInterval = 2) async throws -> VerificationCodeRequest {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let request = VerificationCodeCoordinator.shared.request {
                return request
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("verification request was not presented before timeout")
        throw WaitError.timedOut
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock(); count += 1; lock.unlock()
    }
}