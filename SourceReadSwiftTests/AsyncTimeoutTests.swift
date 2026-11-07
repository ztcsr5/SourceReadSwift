import Foundation
import XCTest
@testable import SourceReadSwift

final class AsyncTimeoutTests: XCTestCase {
    func testTimeoutReturnsBeforeAnUncooperativeOperationCompletes() async {
        await checkInterruptedOperation(shouldCancel: false)
    }

    func testCancellationReturnsBeforeAnUncooperativeOperationCompletes() async {
        await checkInterruptedOperation(shouldCancel: true)
    }

    func testSuccessfulOperationKeepsItsValue() async {
        let result = await AsyncTimeout.run(seconds: 1) { 42 }
        XCTAssertEqual(result, 42)
    }

    func testAlreadyCancelledCallerDoesNotStartNewWork() async {
        let start = HeldTimeoutValue()
        let unexpectedlyStarted = expectation(description: "cancelled work must not start")
        unexpectedlyStarted.isInverted = true
        let task = Task {
            _ = await start.read()
            return await AsyncTimeout.run(seconds: 1) {
                unexpectedlyStarted.fulfill()
                return 42
            }
        }
        task.cancel()
        start.release()
        _ = await task.value
        await fulfillment(of: [unexpectedlyStarted], timeout: 0.05)
    }

    private func checkInterruptedOperation(shouldCancel: Bool) async {
        let entered = expectation(description: "operation has started")
        let completed = expectation(description: "caller exits before operation releases")
        let held = HeldTimeoutValue(entered: entered)
        let task = Task {
            let result = await AsyncTimeout.run(seconds: shouldCancel ? 10 : 0.05) {
                await held.read()
            }
            completed.fulfill()
            return result
        }
        await fulfillment(of: [entered], timeout: 2)
        if shouldCancel { task.cancel() }
        await fulfillment(of: [completed], timeout: 1)
        // Always release the fixture after the assertion so a failing baseline cannot hang CI.
        held.release()
        let result = await task.value
        XCTAssertNil(result)
    }
}

private final class HeldTimeoutValue: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Int, Never>?
    private var isReleased = false
    private let entered: XCTestExpectation?

    init(entered: XCTestExpectation? = nil) { self.entered = entered }

    func read() async -> Int {
        await withCheckedContinuation { continuation in
            lock.lock()
            let released = isReleased
            if !released { self.continuation = continuation }
            lock.unlock()
            entered?.fulfill()
            if released { continuation.resume(returning: 42) }
        }
    }

    func release() {
        lock.lock()
        isReleased = true
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: 42)
    }
}
