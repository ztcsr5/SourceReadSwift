import XCTest
@testable import SourceReadSwift

final class BlockingRuleExecutorTests: XCTestCase {
    func testDiagnosticPolicySurvivesDispatchAndDoesNotLeakToTheNextRule() async {
        let diagnostic = await SourceRequestContext.$isDiagnostic.withValue(true) {
            await BlockingRuleExecutor.run { SourceRequestContext.isDiagnostic }
        }
        let ordinary = await BlockingRuleExecutor.run { SourceRequestContext.isDiagnostic }
        XCTAssertTrue(diagnostic)
        XCTAssertFalse(ordinary)
    }

    func testTimedOutInjectedNetworkRequestIsCancelledInsteadOfRunningAfterTheRuleReturns() async throws {
        let started = expectation(description: "The injected transport entered load before the deadline")
        let cancelled = expectation(description: "Timeout cancels the already-running transport")
        let network = HeldRuleNetwork(started: started, cancelled: cancelled)
        let source = BookSource(bookSourceName: "timeout fixture", bookSourceUrl: "https://held-rule.invalid")
        async let response = BlockingRuleExecutor.run {
            // Under simulator load a 20 ms deadline can cancel the detached
            // producer before load() runs. That is not in-flight cancellation.
            SynchronousSourceNetworkBridge.loadResult(urlText: "https://held-rule.invalid/chapter",
                source: source, network: network, timeout: 1)
        }
        await fulfillment(of: [started], timeout: 2)
        let result = await response
        XCTAssertNil(result)
        await fulfillment(of: [cancelled], timeout: 2)
    }

    func testTimedOutURLSessionRequestStopsItsTransport() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HeldRuleURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let address = try XCTUnwrap(URL(string: "https://held-rule.invalid/\(UUID().uuidString)"))
        let loader = SynchronousSourceLoader(session: session)
        let source = BookSource(bookSourceName: "timeout fixture", bookSourceUrl: "https://held-rule.invalid")
        let result = await BlockingRuleExecutor.run {
            loader.loadResponse(urlText: address.absoluteString, source: source, timeout: 0.02)
        }
        XCTAssertNil(result)
        for _ in 0..<200 {
            if HeldRuleURLProtocol.stopped(address) == 1 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(HeldRuleURLProtocol.stopped(address), 1)
    }

    func testParallelBlockingRulesLeaveTheirAsyncNetworkProducersRunnable() async {
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0..<16 {
                group.addTask {
                    await BlockingRuleExecutor.run {
                        let semaphore = DispatchSemaphore(value: 0)
                        Task.detached { semaphore.signal() }
                        return BlockingRuleExecutor.isOnRuleQueue
                            && !Thread.isMainThread && semaphore.wait(timeout: .now() + 2) == .success
                    }
                }
            }
            var completed: [Bool] = []
            for await result in group { completed.append(result) }
            return completed
        }
        XCTAssertEqual(results.count, 16)
        XCTAssertTrue(results.allSatisfy { $0 }, "Blocking JS callers cannot occupy the producers' cooperative executor")
    }
}

private actor HeldRuleNetwork: SourceNetworkClient {
    private let started: XCTestExpectation
    private let cancelled: XCTestExpectation

    init(started: XCTestExpectation, cancelled: XCTestExpectation) {
        self.started = started
        self.cancelled = cancelled
    }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        started.fulfill()
        do {
            try await Task.sleep(nanoseconds: 30_000_000_000)
            return .failure(.network("Fixture did not receive cancellation"))
        } catch {
            cancelled.fulfill()
            return .failure(.network("Fixture cancelled"))
        }
    }
}

private final class HeldRuleURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var stops: [URL: Int] = [:]
    static func stopped(_ address: URL) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return stops[address, default: 0]
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "held-rule.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {
        guard let address = request.url else { return }
        Self.lock.lock()
        Self.stops[address, default: 0] += 1
        Self.lock.unlock()
    }
}
