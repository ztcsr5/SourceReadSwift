import XCTest
@testable import SourceReadSwift

final class CloudTTSProtocolTests: XCTestCase {

    func testXunfeiAuthURLGeneration() {
        let config = CloudTTSProtocol.XunfeiConfig(
            appId: "test_app_id",
            apiKey: "test_api_key_12345",
            apiSecret: "test_api_secret_67890",
            voiceName: "xiaoyan",
            speed: 55,
            volume: 60,
            pitch: 50
        )

        let fixedDate = Date(timeIntervalSince1970: 1700000000)
        guard let url = CloudTTSProtocol.createXunfeiAuthURL(config: config, date: fixedDate) else {
            return XCTFail("createXunfeiAuthURL returned nil")
        }

        XCTAssertEqual(url.scheme, "wss")
        XCTAssertEqual(url.host, "tts-api.xfyun.cn")
        XCTAssertEqual(url.path, "/v2/tts")

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return XCTFail("Failed to parse URLComponents")
        }

        let queryItems = components.queryItems ?? []
        XCTAssertNotNil(queryItems.first(where: { $0.name == "authorization" }))
        XCTAssertNotNil(queryItems.first(where: { $0.name == "date" }))
        XCTAssertEqual(queryItems.first(where: { $0.name == "host" })?.value, "tts-api.xfyun.cn")
    }

    func testSynthesisPayloadGeneration() {
        let config = CloudTTSProtocol.XunfeiConfig(
            appId: "app123",
            apiKey: "key123",
            apiSecret: "sec123"
        )

        guard let payloadData = CloudTTSProtocol.createSynthesisPayload(text: "你好，纸间阅读", config: config),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return XCTFail("Payload generation failed")
        }

        let common = json["common"] as? [String: Any]
        XCTAssertEqual(common?["app_id"] as? String, "app123")

        let business = json["business"] as? [String: Any]
        XCTAssertEqual(business?["vcn"] as? String, "xiaoyan")
        XCTAssertEqual(business?["auf"] as? String, "audio/L16;rate=16000")

        let data = json["data"] as? [String: Any]
        let textB64 = data?["text"] as? String
        XCTAssertNotNil(textB64)
        if let textB64 = textB64, let textData = Data(base64Encoded: textB64) {
            XCTAssertEqual(String(data: textData, encoding: .utf8), "你好，纸间阅读")
        }
    }
}
