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

    func testHttpTTSVoiceStoreImportUpsertExportAndQueueLookaheadAndSentenceLocator() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tts_store_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let json = Data("""
        [
          {"id": "2048", "name": "清亮女声", "url": "https://tts.example.com/speak?text={{speakText}}", "header": "{\\"X-Token\\":\\"abc\\"}"},
          {"id": 4096, "name": "无效空白", "url": "   "}
        ]
        """.utf8)
        let imported = try HttpTTSVoiceStore.importJSON(json, into: dir)
        XCTAssertEqual(imported.added, 1)
        XCTAssertEqual(imported.voices.count, 1)
        let resolvedVoice = try XCTUnwrap(HttpTTSVoiceStore.voice(id: 2048, in: dir))
        XCTAssertEqual(resolvedVoice.name, "清亮女声")
        let req = try XCTUnwrap(resolvedVoice.resolveRequest(speakText: "测试", speakSpeed: 5))
        XCTAssertEqual(req.headers["X-Token"], "abc")

        let custom = HttpTTSVoice(id: 9001, name: "自建音色", url: "https://tts.example.com/v2?q={{speakText}}")
        _ = try HttpTTSVoiceStore.upsert(custom, in: dir)
        XCTAssertTrue(HttpTTSVoiceStore.allVoices(from: dir).contains(where: { $0.id == 9001 }))
        _ = try HttpTTSVoiceStore.remove(id: 9001, from: dir)
        XCTAssertFalse(HttpTTSVoiceStore.loadCustomVoices(from: dir).contains(where: { $0.id == 9001 }))

        var queue = ReaderSpeechQueue()
        queue.reset(title: "序", paragraphs: ["第一句", "第二句", "第三句"], startParagraphIndex: 0, includeTitle: false)
        _ = queue.dequeue()
        let lookahead = queue.lookaheadSegments(count: 2)
        XCTAssertEqual(lookahead.map(\.index), [1, 2])
        XCTAssertEqual(lookahead.map(\.text), ["第二句", "第三句"])

        let paragraph = "风起了。窗外下起了细雨！他点点头。"
        let nsParagraph = paragraph as NSString
        let targetWordRange = nsParagraph.range(of: "细雨")
        let sentence = try XCTUnwrap(ReaderSpeechSentenceLocator.sentenceRange(in: paragraph, around: targetWordRange))
        XCTAssertEqual(nsParagraph.substring(with: sentence), "窗外下起了细雨！")
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
