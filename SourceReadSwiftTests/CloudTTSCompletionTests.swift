import AVFoundation
import XCTest
@testable import SourceReadSwift

final class CloudTTSCompletionTests: XCTestCase {
    func testTimeoutReturnsWithoutWaitingForAReceiveCallback() async {
        await checkInterruptedReceive(shouldCancel: false)
    }

    func testCancellationReturnsWithoutWaitingForAReceiveCallback() async {
        await checkInterruptedReceive(shouldCancel: true)
    }

    func testStoppedPlayersIgnoreQueuedDelegateCallbacks() throws {
        let player = CloudTTSPlayer()
        // AVAudioPlayer's inherited empty initializer does not create a usable
        // audio item. Exercise a real decoded PCM item without playing it.
        let header: [UInt8] = [82,73,70,70,196,0,0,0,87,65,86,69,102,109,116,32,
                              16,0,0,0,1,0,1,0,64,31,0,0,128,62,0,0,2,0,16,0,
                              100,97,116,97,160,0,0,0]
        let oldPlayer = try AVAudioPlayer(data: Data(header) + Data(repeating: 0, count: 160))
        XCTAssertGreaterThan(oldPlayer.duration, 0)
        var callbacks = 0
        player.onFinish = { callbacks += 1 }
        player.onError = { _ in callbacks += 1 }
        player.stop()
        player.audioPlayerDidFinishPlaying(oldPlayer, successfully: true)
        player.audioPlayerDecodeErrorDidOccur(oldPlayer, error: nil)
        XCTAssertEqual(callbacks, 0, "An old audio item must not advance or stop a new reading session")
    }

    private func checkInterruptedReceive(shouldCancel: Bool) async {
        let entered = expectation(description: "socket waiting for audio")
        let completed = expectation(description: "synthesis exits before socket callback")
        let socket = HeldTTSSocket(entered: entered)
        let client = CloudTTSClient(factory: HeldTTSFactory(socket: socket), timeout: shouldCancel ? 10 : 0.05)
        let synthesis = Task { () -> Error? in
            defer { completed.fulfill() }
            do {
                _ = try await client.synthesize(text: "离线回归", credentials: CloudTTSCredentials(
                    appId: "fixture", apiKey: "fixture", apiSecret: "fixture"))
                return nil
            } catch { return error }
        }
        await fulfillment(of: [entered], timeout: 2)
        if shouldCancel { synthesis.cancel() }
        await fulfillment(of: [completed], timeout: 1)
        // Release even on failure so the regression cannot hang the whole test process.
        socket.finishReceive()
        let error = await synthesis.value
        if shouldCancel { XCTAssertTrue(error is CancellationError) }
        else { XCTAssertEqual(error as? XunfeiTTSError, .timeout) }
        XCTAssertTrue(socket.wasCancelled)
    }
}

private struct HeldTTSFactory: CloudTTSWebSocketFactory {
    let socket: HeldTTSSocket
    func makeWebSocket(url: URL) -> CloudTTSWebSocket { socket }
}

private final class HeldTTSSocket: CloudTTSWebSocket, @unchecked Sendable {
    private let entered: XCTestExpectation
    private let lock = NSLock()
    private var completion: ((Result<Data, Error>) -> Void)?
    private var cancelled = false

    init(entered: XCTestExpectation) { self.entered = entered }
    var wasCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func resume() {}
    func send(_ bytes: Data, completion: @escaping (Error?) -> Void) { completion(nil) }
    func receive(completion: @escaping (Result<Data, Error>) -> Void) {
        lock.lock(); self.completion = completion; lock.unlock()
        entered.fulfill()
    }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func finishReceive() {
        lock.lock(); let callback = completion; completion = nil; lock.unlock()
        callback?(.failure(XunfeiTTSError.connectionClosed))
    }
}
