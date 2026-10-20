import XCTest
@testable import SourceReadSwift

private final class FakeHttpTTSRequester: HttpTTSRequesting {
    private(set) var capturedRequest: URLRequest?
    private let result: (URLRequest) throws -> (Data, URLResponse)

    init(result: @escaping (URLRequest) throws -> (Data, URLResponse)) {
        self.result = result
    }

    func httpTTSData(for request: URLRequest) async throws -> (Data, URLResponse) {
        capturedRequest = request
        return try result(request)
    }
}

final class HttpTTSClientTests: XCTestCase {
    private let template = #"http://example.com/tts,{"method":"POST","headers":{"X-Test":"1"},"body":"tex={{java.encodeURI(java.encodeURI(speakText))}}&spd={{(speakSpeed + 5) / 10 + 4}}&per=4"}"#

    private func makeVoice(url: String? = nil) -> HttpTTSVoice {
        HttpTTSVoice(id: 1, name: "test", url: url ?? template)
    }

    private func response(
        for request: URLRequest,
        status: Int = 200,
        contentType: String = "audio/mpeg",
        data: Data
    ) throws -> (Data, URLResponse) {
        let url = try XCTUnwrap(request.url)
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType]
        ))
        return (data, response)
    }

    func testPostsTemplateBodyAndHeaders() async throws {
        let audio = Data([0xFF, 0xFB, 0x90, 0x64])
        let requester = FakeHttpTTSRequester { request in
            try self.response(for: request, data: audio)
        }
        let client = HttpTTSClient(requester: requester, timeout: 5)

        let result = try await client.synthesize(voice: makeVoice(), text: "你好", speed: 5)

        XCTAssertEqual(result, audio)
        let request = try XCTUnwrap(requester.capturedRequest)
        XCTAssertEqual(request.url?.absoluteString, "http://example.com/tts")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Test"), "1")
        let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8)
        XCTAssertNotNil(body)
        XCTAssertTrue(body?.contains("tex=") == true, "body: \(body ?? "nil")")
        XCTAssertTrue(body?.contains("&spd=5") == true, "body: \(body ?? "nil")")
        XCTAssertTrue(body?.contains("&per=4") == true, "body: \(body ?? "nil")")
    }

    func testHTTPErrorStatusThrows() async throws {
        let requester = FakeHttpTTSRequester { request in
            try self.response(for: request, status: 503, data: Data([0xFF]))
        }
        let client = HttpTTSClient(requester: requester, timeout: 5)

        do {
            _ = try await client.synthesize(voice: makeVoice(), text: "测试", speed: 5)
            XCTFail("expected httpStatus")
        } catch let error as HttpTTSError {
            XCTAssertEqual(error, .httpStatus(503))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testJSONContentTypeIsTreatedAsServerError() async throws {
        let payload = Data(#"{"err_msg":"quota exceeded"}"#.utf8)
        let requester = FakeHttpTTSRequester { request in
            try self.response(for: request, contentType: "application/json; charset=utf-8", data: payload)
        }
        let client = HttpTTSClient(requester: requester, timeout: 5)

        do {
            _ = try await client.synthesize(voice: makeVoice(), text: "测试", speed: 5)
            XCTFail("expected server error")
        } catch let error as HttpTTSError {
            XCTAssertEqual(error, .server(#"{"err_msg":"quota exceeded"}"#))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testJSONBodyWithOctetStreamIsRejectedBeforePlayback() async throws {
        let payload = Data(#"{"error":"bad request"}"#.utf8)
        let requester = FakeHttpTTSRequester { request in
            try self.response(for: request, contentType: "application/octet-stream", data: payload)
        }
        let client = HttpTTSClient(requester: requester, timeout: 5)

        do {
            _ = try await client.synthesize(voice: makeVoice(), text: "测试", speed: 5)
            XCTFail("expected server error")
        } catch let error as HttpTTSError {
            XCTAssertEqual(error, .server(#"{"error":"bad request"}"#))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testEmptyAudioThrows() async throws {
        let requester = FakeHttpTTSRequester { request in
            try self.response(for: request, data: Data())
        }
        let client = HttpTTSClient(requester: requester, timeout: 5)

        do {
            _ = try await client.synthesize(voice: makeVoice(), text: "测试", speed: 5)
            XCTFail("expected emptyAudio")
        } catch let error as HttpTTSError {
            XCTAssertEqual(error, .emptyAudio)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testEmptyTextDoesNotIssueRequest() async {
        let requester = FakeHttpTTSRequester { request in
            try self.response(for: request, data: Data([0xFF]))
        }
        let client = HttpTTSClient(requester: requester, timeout: 5)

        do {
            _ = try await client.synthesize(voice: makeVoice(), text: " \n\t ", speed: 5)
            XCTFail("expected emptyText")
        } catch let error as HttpTTSError {
            XCTAssertEqual(error, .emptyText)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertNil(requester.capturedRequest)
    }

    func testInvalidTemplateThrowsInvalidRequest() async {
        let requester = FakeHttpTTSRequester { request in
            try self.response(for: request, data: Data([0xFF]))
        }
        let client = HttpTTSClient(requester: requester, timeout: 5)

        do {
            _ = try await client.synthesize(voice: makeVoice(url: "http://[invalid"), text: "测试", speed: 5)
            XCTFail("expected invalidRequest")
        } catch let error as HttpTTSError {
            XCTAssertEqual(error, .invalidRequest)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertNil(requester.capturedRequest)
    }

    func testSpeedIsClampedToTemplateRange() async throws {
        let requester = FakeHttpTTSRequester { request in
            try self.response(for: request, data: Data([0xFF]))
        }
        let client = HttpTTSClient(requester: requester, timeout: 5)

        _ = try await client.synthesize(voice: makeVoice(), text: "测试", speed: 99)

        let request = try XCTUnwrap(requester.capturedRequest)
        let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8)
        XCTAssertTrue(body?.contains("&spd=5") == true, "body: \(body ?? "nil")")
    }
}
