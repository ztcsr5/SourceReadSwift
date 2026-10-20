import XCTest
@testable import SourceReadSwift

private final class FakeCloudTTSWebSocket: CloudTTSWebSocket {
    var frames: [Result<Data, Error>]
    var sent: [Data] = []
    private(set) var didResume = false
    private(set) var didCancel = false

    init(frames: [Result<Data, Error>]) {
        self.frames = frames
    }

    func resume() {
        didResume = true
    }

    func send(_ data: Data, completion: @escaping (Error?) -> Void) {
        sent.append(data)
        completion(nil)
    }

    func receive(completion: @escaping (Result<Data, Error>) -> Void) {
        guard !frames.isEmpty else {
            completion(.failure(XunfeiTTSError.connectionClosed))
            return
        }
        completion(frames.removeFirst())
    }

    func cancel() {
        didCancel = true
    }
}

private final class FakeCloudTTSWebSocketFactory: CloudTTSWebSocketFactory {
    let socket: FakeCloudTTSWebSocket
    private(set) var requestedURL: URL?

    init(socket: FakeCloudTTSWebSocket) {
        self.socket = socket
    }

    func makeWebSocket(url: URL) -> CloudTTSWebSocket {
        requestedURL = url
        return socket
    }
}

final class CloudTTSClientTests: XCTestCase {

    private let credentials = CloudTTSCredentials(
        appId: "app123",
        apiKey: "key123",
        apiSecret: "secret123"
    )

    private func frame(_ json: String) -> Result<Data, Error> {
        .success(Data(json.utf8))
    }

    func testAccumulatesAudioAcrossFramesAndStopsAtFinal() async throws {
        let socket = FakeCloudTTSWebSocket(frames: [
            frame(#"{"code":0,"data":{"status":1,"audio":"YWI="}}"#),
            frame(#"{"code":0,"data":{"status":1,"audio":"Y2Q="}}"#),
            frame(#"{"code":0,"data":{"status":2,"audio":"ZWY="}}"#),
            frame(#"{"code":0,"data":{"status":1,"audio":"c2hvdWxkLW5vdC1iZS1yZWFk"}}"#)
        ])
        let factory = FakeCloudTTSWebSocketFactory(socket: socket)
        let client = CloudTTSClient(factory: factory, timeout: 5)

        let audio = try await client.synthesize(text: "你好", credentials: credentials)

        XCTAssertEqual(audio, Data([0x61, 0x62, 0x63, 0x64, 0x65, 0x66]))
        XCTAssertEqual(socket.sent.count, 1)
        XCTAssertTrue(socket.didResume)
        XCTAssertTrue(socket.didCancel)
        XCTAssertEqual(factory.requestedURL?.host, "tts-api.xfyun.cn")

        let payload = try XCTUnwrap(socket.sent.first)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
        XCTAssertEqual((json["common"] as? [String: Any])?["app_id"] as? String, "app123")
        let data = try XCTUnwrap(json["data"] as? [String: Any])
        let text = try XCTUnwrap(data["text"] as? String)
        XCTAssertEqual(String(data: try XCTUnwrap(Data(base64Encoded: text)), encoding: .utf8), "你好")
    }

    func testServerErrorCodeThrows() async {
        let socket = FakeCloudTTSWebSocket(frames: [
            frame(#"{"code":10105,"message":"illegal access"}"#)
        ])
        let client = CloudTTSClient(factory: FakeCloudTTSWebSocketFactory(socket: socket), timeout: 5)

        do {
            _ = try await client.synthesize(text: "x", credentials: credentials)
            XCTFail("expected server error")
        } catch let error as XunfeiTTSError {
            XCTAssertEqual(error, .server(code: 10105, message: "illegal access"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testFinalFrameWithoutAudioThrowsEmptyAudio() async {
        let socket = FakeCloudTTSWebSocket(frames: [
            frame(#"{"code":0,"data":{"status":2}}"#)
        ])
        let client = CloudTTSClient(factory: FakeCloudTTSWebSocketFactory(socket: socket), timeout: 5)

        do {
            _ = try await client.synthesize(text: "x", credentials: credentials)
            XCTFail("expected empty audio")
        } catch let error as XunfeiTTSError {
            XCTAssertEqual(error, .emptyAudio)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testMalformedFrameThrowsInvalidFrame() async {
        let socket = FakeCloudTTSWebSocket(frames: [
            .success(Data("not-json".utf8))
        ])
        let client = CloudTTSClient(factory: FakeCloudTTSWebSocketFactory(socket: socket), timeout: 5)

        do {
            _ = try await client.synthesize(text: "x", credentials: credentials)
            XCTFail("expected invalid frame")
        } catch let error as XunfeiTTSError {
            XCTAssertEqual(error, .invalidFrame)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testUnconfiguredCredentialsThrowBeforeConnecting() async {
        let socket = FakeCloudTTSWebSocket(frames: [])
        let factory = FakeCloudTTSWebSocketFactory(socket: socket)
        let client = CloudTTSClient(factory: factory, timeout: 5)

        do {
            _ = try await client.synthesize(text: "x", credentials: CloudTTSCredentials())
            XCTFail("expected not configured")
        } catch let error as XunfeiTTSError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertNil(factory.requestedURL)
    }
}
