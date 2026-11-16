import XCTest
import Combine
@testable import SourceReadSwift

final class SourceBrowserLoginCoordinatorTests: XCTestCase {
    override func tearDown() async throws {
        await MainActor.run {
            if let request = SourceBrowserLoginCoordinator.shared.request {
                SourceBrowserLoginCoordinator.shared.cancel(id: request.id)
            }
        }
        try await super.tearDown()
    }

    @MainActor
    func testWaitResumesOnlyAfterUserCompletesWithActualFinalURL() async throws {
        let completion = BrowserLoginObservation()
        let task = Task.detached {
            let value = SourceBrowserLoginCoordinator.requestSynchronously(
                url: URL(string: "https://login.fixture.invalid/sign-in")!, title: "登录", timeout: 5)
            completion.finish()
            return value
        }
        let request = try await waitForRequest()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(completion.isFinished, "Opening the browser must not continue the login script")
        XCTAssertEqual(request.url.path, "/sign-in")

        let finalURL = URL(string: "https://login.fixture.invalid/account")!
        let page = makePage(url: finalURL)
        SourceBrowserLoginCoordinator.shared.submit(id: request.id, response: page)
        let result = await task.value
        XCTAssertEqual(result?.url, finalURL)
        XCTAssertEqual(result?.body, page.body)
        XCTAssertEqual(result?.statusCode, 200)
        XCTAssertNil(SourceBrowserLoginCoordinator.shared.request)
    }

    @MainActor
    func testCompletionIsDeliveredOnceAndOldCancellationCannotCancelNextRequest() {
        let coordinator = SourceBrowserLoginCoordinator()
        let first = SourceBrowserLoginRequest(url: URL(string: "https://fixture.invalid/login")!, title: "登录")
        var returned: [SourceResponse?] = []
        coordinator.present(first) { returned.append($0) }
        coordinator.submit(id: first.id, response: makePage(url: first.url))
        coordinator.submit(id: first.id, response: makePage(url: first.url))
        coordinator.cancel(id: first.id)
        XCTAssertEqual(returned.count, 1)

        let next = SourceBrowserLoginRequest(url: first.url, title: "重新登录")
        coordinator.present(next) { returned.append($0) }
        coordinator.cancel(id: first.id)
        XCTAssertEqual(coordinator.request?.id, next.id)
        coordinator.cancel(id: next.id)
        XCTAssertEqual(returned.count, 2)
        XCTAssertNil(returned[1])
    }

    @MainActor
    func testCancelReturnsNoSuccessfulBrowserResult() async throws {
        let task = Task.detached {
            SourceBrowserLoginCoordinator.requestSynchronously(
                url: URL(string: "http://fixture.invalid:8080/login")!, title: "登录", timeout: 5)
        }
        let request = try await waitForRequest()
        SourceBrowserLoginCoordinator.shared.cancel(id: request.id)
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertNil(SourceBrowserLoginCoordinator.shared.request)
    }

    @MainActor
    func testTimeoutReleasesWaiterAndClosesRequest() async throws {
        let task = Task.detached {
            SourceBrowserLoginCoordinator.requestSynchronously(
                url: URL(string: "https://fixture.invalid/login")!, title: "登录", timeout: 0.3)
        }
        _ = try await waitForRequest()
        let result = await task.value
        XCTAssertNil(result)
        for _ in 0..<100 {
            if SourceBrowserLoginCoordinator.shared.request == nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNil(SourceBrowserLoginCoordinator.shared.request)
    }

    @MainActor
    func testMainThreadNeverBlocksWaitingForItsOwnBrowser() {
        XCTAssertNil(SourceBrowserLoginCoordinator.requestSynchronously(
            url: URL(string: "https://fixture.invalid/login")!, title: "登录"))
        XCTAssertNil(SourceBrowserLoginCoordinator.shared.request)
    }

    @MainActor
    func testOperationCancellationReleasesBrowserWaitingOnGCDWorker() async throws {
        let cancellation = SourceLoginCancellation()
        let completed = expectation(description: "GCD browser wait released by its operation token")
        let task = Task {
            await BlockingRuleExecutor.run {
                let result = SourceLoginCancellation.$current.withValue(cancellation) {
                    SourceBrowserLoginCoordinator.requestSynchronously(
                        url: URL(string: "https://login.fixture.invalid/sign-in")!, title: "登录", timeout: 5)
                }
                completed.fulfill()
                return result
            }
        }
        _ = try await waitForRequest()
        cancellation.cancel()
        await fulfillment(of: [completed], timeout: 1.5)
        let result = await task.value
        XCTAssertNil(result)
        for _ in 0..<100 {
            if SourceBrowserLoginCoordinator.shared.request == nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNil(SourceBrowserLoginCoordinator.shared.request)
    }

    @MainActor
    func testAlreadyCancelledOperationNeverPublishesABrowser() async {
        let cancellation = SourceLoginCancellation()
        cancellation.cancel()
        var published = 0
        let observer = SourceBrowserLoginCoordinator.shared.$request.sink {
            if $0 != nil { published += 1 }
        }
        defer { observer.cancel() }
        let result = await BlockingRuleExecutor.run {
            SourceLoginCancellation.$current.withValue(cancellation) {
                SourceBrowserLoginCoordinator.requestSynchronously(
                    url: URL(string: "https://login.fixture.invalid/sign-in")!, title: "登录", timeout: 0.2)
            }
        }
        XCTAssertNil(result)
        XCTAssertEqual(published, 0)
        XCTAssertNil(SourceBrowserLoginCoordinator.shared.request)
    }

    func testLoginDestinationAllowsHTTPWithoutRelaxingPublisherImport() throws {
        let destination = try SourceLoginBrowserAction.destination(
            from: #"{"address":"http://fixture.invalid:8080/login","waitsForResult":true}"#).get()
        XCTAssertEqual(destination, .web(URL(string: "http://fixture.invalid:8080/login")!, waitsForAndroidResult: true))
        XCTAssertNil(SourcePublisherLinks.secureWebURL("http://fixture.invalid/source.json"))
        XCTAssertNil(SourceLoginBrowserAction.loginWebURL("file:///private/example"))
        XCTAssertNil(SourceLoginBrowserAction.loginWebURL("https://user:password@fixture.invalid/"))
    }

    func testInAppWrapperContinuesOriginalAwaitCallWithoutReplayingEarlierEffects() throws {
        let context = RuleExecutionContext(source: BookSource(
            bookSourceName: "Browser fixture", bookSourceUrl: "https://fixture.invalid"))
        let runtime = JSCoreRuntime(executionContext: context)
        let wrapped = try XCTUnwrap(SourceLoginBrowserAction.wrap("""
        source.put('before', String(Number(source.get('before') || '0') + 1));
        var response = java.startBrowserAwait('https://fixture.invalid/login', '登录', false);
        source.put('after', response.url());
        source.put('page', response.body());
        """, waitsInApp: true))
        context.browserLoginProvider = { _, _ in
            SourceResponse(url: URL(string: "https://fixture.invalid/account")!, statusCode: 200,
                headers: [:], body: "<p>Account</p>", data: Data("<p>Account</p>".utf8))
        }
        XCTAssertEqual(try runtime.evaluate(wrapped).get(), "{}")
        XCTAssertEqual(context.get("source.variable.before"), "1")
        XCTAssertEqual(context.get("source.variable.after"), "https://fixture.invalid/account")
        XCTAssertEqual(context.get("source.variable.page"), "<p>Account</p>")
    }

    private func makePage(url: URL) -> SourceResponse {
        SourceResponse(url: url, statusCode: 200, headers: [:],
            body: "<p>Completed page</p>", data: Data("<p>Completed page</p>".utf8))
    }

    @MainActor
    private func waitForRequest() async throws -> SourceBrowserLoginRequest {
        for _ in 0..<250 {
            if let request = SourceBrowserLoginCoordinator.shared.request { return request }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Browser login request was not presented")
        throw BrowserLoginWaitError.timedOut
    }
}

private enum BrowserLoginWaitError: Error { case timedOut }

private final class BrowserLoginObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    var isFinished: Bool {
        lock.lock(); defer { lock.unlock() }
        return finished
    }

    func finish() {
        lock.lock(); finished = true; lock.unlock()
    }
}
