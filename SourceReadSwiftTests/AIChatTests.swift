import XCTest
import SwiftUI
@testable import SourceReadSwift

final class AIChatTests: XCTestCase {
    private let config = AIChatConfiguration(endpoint: "https://ai.example/v1/chat/completions", model: "user-selected-model", supportsImages: false)

    func testEndpointValidationAndCredentialIsolation() throws {
        for endpoint in ["http://ai.example/chat", "https://user:pass@ai.example/chat", "https://ai.example/chat?key=secret", "https://ai.example/chat#secret", "file:///private/key"] {
            XCTAssertNil(AIChatConfiguration(endpoint: endpoint).validatedURL)
        }
        let memory = AIChatMemorySecrets(), credentials = AIChatCredentials(store: memory)
        try credentials.save("TEST-KEY", for: config)
        XCTAssertEqual(credentials.key(for: config), "TEST-KEY")
        var other = config; other.endpoint = "https://other.example/v1/chat/completions"
        XCTAssertNil(credentials.key(for: other))
        other = config; other.endpoint += "/different"
        XCTAssertNil(credentials.key(for: other), "Key is bound to the exact endpoint, not just a host")
        let persisted = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
        XCTAssertFalse(persisted.contains("TEST-KEY"))
        try credentials.remove(for: config); XCTAssertNil(credentials.key(for: config))
        XCTAssertThrowsError(try credentials.save("key\nInjected", for: config))
    }

    func testOnlyExplicitAttachmentsEnterRequestAndNoCookieHandling() throws {
        let request = try AIChatClient.request(config: config, key: "TEST-KEY", messages: [
            .init(role: .user, text: "修改这个书源", attachments: [.init(name: "选中的源.json", payload: .text("{\"name\":\"ONLY-SELECTED\"}"))])
        ])
        XCTAssertEqual(request.url, config.validatedURL)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        let data = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, config.model)
        XCTAssertEqual(body["stream"] as? Bool, false)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertTrue((messages[0]["content"] as? String ?? "").contains("资料"))
        XCTAssertTrue((messages[1]["content"] as? String ?? "").contains("ONLY-SELECTED"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("TEST-KEY"))
    }

    func testStructuredSecretScrubbingPreservesRuleAndReferer() throws {
        let input = #"{"bookSourceName":"test","header":"{\"Cookie\":\"PRIVATE-COOKIE\",\"Authorization\":\"PRIVATE-AUTH\",\"Referer\":\"https://site.example/\"}","api_key":"PRIVATE-KEY","ruleContent":{"content":"@css:#content@text"},"nested":[{"access_token":"PRIVATE-TOKEN","safe":"kept"}]}"#
        let output = AIChatAttachmentPrivacy.scrubJSON(input)
        for secret in ["PRIVATE-COOKIE", "PRIVATE-AUTH", "PRIVATE-KEY", "PRIVATE-TOKEN"] { XCTAssertFalse(output.contains(secret)) }
        XCTAssertTrue(output.contains("Referer")); XCTAssertTrue(output.contains("@css:#content@text")); XCTAssertTrue(output.contains("kept"))
        XCTAssertEqual(AIChatAttachmentPrivacy.scrubJSON("arbitrary prose"), "arbitrary prose", "Unknown text is for explicit preview, not silently rewritten")
    }

    func testImagesRequireExplicitCapabilityAndBoundedPayload() throws {
        let image = AIChatAttachment(name: "image.jpg", payload: .jpeg(Data([0xff, 0xd8, 0xff, 0x00])))
        XCTAssertThrowsError(try AIChatClient.request(config: config, key: "key", messages: [.init(role: .user, text: "看图", attachments: [image])]))
        var vision = config; vision.supportsImages = true
        let request = try AIChatClient.request(config: vision, key: "key", messages: [.init(role: .user, text: "看图", attachments: [image])])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let parts = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
        let imageURL = try XCTUnwrap(parts.last?["image_url"] as? [String: Any])
        XCTAssertTrue((imageURL["url"] as? String ?? "").hasPrefix("data:image/jpeg;base64,"))
        let tooLarge = AIChatAttachment(name: "large.txt", payload: .text(String(repeating: "a", count: 2_000_001)))
        XCTAssertThrowsError(try AIChatClient.request(config: config, key: "key", messages: [.init(role: .user, text: "x", attachments: [tooLarge])]))
        XCTAssertThrowsError(try AIChatClient.request(config: config, key: "key", messages: (0..<41).map { _ in .init(role: .user, text: "x") }))
        XCTAssertThrowsError(try AIChatClient.request(config: config, key: "key", messages: [.init(role: .user, text: String(repeating: "x", count: 6_000_001))]))
    }

    func testReplyUsesInjectedTransportAndHandlesErrorWithoutProviderBodyLeak() async throws {
        let success = AIChatFixtureTransport(status: 200, data: Data(#"{"choices":[{"message":{"content":"规则建议，不会自动执行"}}]}"#.utf8))
        let reply = try await AIChatClient(transport: success).reply(config: config, key: "key", messages: [.init(role: .user, text: "hello")])
        XCTAssertEqual(reply, "规则建议，不会自动执行")
        let calls = await success.callCount; XCTAssertEqual(calls, 1)
        let failure = AIChatFixtureTransport(status: 401, data: Data("PRIVATE-PROVIDER-ERROR".utf8))
        do { _ = try await AIChatClient(transport: failure).reply(config: config, key: "key", messages: [.init(role: .user, text: "hello")]); XCTFail("Expected HTTP error") }
        catch { XCTAssertEqual(error as? AIChatFailure, .http(401)); XCTAssertFalse(error.localizedDescription.contains("PRIVATE-PROVIDER-ERROR")) }
        let failedCalls = await failure.callCount; XCTAssertEqual(failedCalls, 1, "No hidden retries")
    }

    func testRejectsEmptyMalformedAndOversizedReplies() async throws {
        for data in [Data("not-json".utf8), Data(#"{"choices":[]}"#.utf8), Data(repeating: 0, count: AIChatURLTransport.responseLimit + 1)] {
            do {
                _ = try await AIChatClient(transport: AIChatFixtureTransport(status: 200, data: data)).reply(config: config, key: "key", messages: [.init(role: .user, text: "hello")])
                XCTFail("Malformed/empty/oversized replies cannot be success")
            } catch { XCTAssertTrue(error is AIChatFailure) }
        }
    }

    @MainActor func testPreviewMakesNoNetworkCallAndStopDiscardsLateCompletion() async throws {
        let transport = AIChatFixtureTransport(status: 200, data: Data(#"{"choices":[{"message":{"content":"late"}}]}"#.utf8), delay: 100_000_000)
        let session = AIChatSession(client: AIChatClient(transport: transport))
        let credentials = AIChatCredentials(store: AIChatMemorySecrets()); try credentials.save("key", for: config)
        let preview = try session.prepare(text: "question", attachments: [], config: config, credentials: credentials)
        let before = await transport.callCount; XCTAssertEqual(before, 0)
        XCTAssertTrue(session.messages.isEmpty); XCTAssertFalse(session.isSending)
        session.send(preview)
        try await Task.sleep(nanoseconds: 20_000_000)
        session.stop(); session.clear()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(session.messages.isEmpty, "Late/cancelled reply must not resurrect a cleared conversation")
        XCTAssertFalse(session.isSending)
    }

    func testSourceReviewAcceptsExactlyOneSourceAndNeverImports() throws {
        let source = BookSource(bookSourceName: "示例", bookSourceUrl: "https://novel.example", ruleToc: .init(fields: ["chapterList": "a"]), ruleContent: .init(fields: ["content": "#content"]))
        let text = String(decoding: try JSONEncoder().encode(source), as: UTF8.self)
        XCTAssertEqual(try AIGeneratedSourceDecoder.decode("建议如下：\n```json\n" + text + "\n``` ").bookSourceName, "示例")
        XCTAssertThrowsError(try AIGeneratedSourceDecoder.decode("{}"))
        XCTAssertThrowsError(try AIGeneratedSourceDecoder.decode("[\(text),\(text)]"))
        let invalid = BookSource(bookSourceName: "示例", bookSourceUrl: "file:///private/data", ruleToc: source.ruleToc, ruleContent: source.ruleContent)
        XCTAssertThrowsError(try AIGeneratedSourceDecoder.decode(String(decoding: try JSONEncoder().encode(invalid), as: UTF8.self)))
    }

    @MainActor func testFileAttachmentLoaderBoundsTextAndResizesImages() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("source.json")
        try Data(#"{"Cookie":"PRIVATE","safe":"rule"}"#.utf8).write(to: file)
        let attachment = try AIChatAttachmentLoader.load(file)
        guard case .text(let text) = attachment.payload else { return XCTFail("Expected text") }
        XCTAssertFalse(text.contains("PRIVATE")); XCTAssertTrue(text.contains("rule"))
        try Data(repeating: 0x61, count: 2_000_001).write(to: file)
        XCTAssertThrowsError(try AIChatAttachmentLoader.load(file))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1800), format: format).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1800))
        }
        let picture = folder.appendingPathComponent("image.jpg")
        try XCTUnwrap(image.jpegData(compressionQuality: 0.6)).write(to: picture)
        guard case .jpeg(let bytes) = try AIChatAttachmentLoader.load(picture).payload,
              let result = UIImage(data: bytes) else { return XCTFail("Expected redrawn JPEG") }
        XCTAssertLessThanOrEqual(max(result.size.width, result.size.height), 1280)
        XCTAssertLessThanOrEqual(bytes.count, 2_000_000)
    }

    @MainActor func testAIEntryRendersAtNarrowAndNormalWidthsWithoutNetworkConfiguration() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = AppState(sourceStore: SourceStore(persistence: SourcePersistence(rootURL: folder)))
        for width: CGFloat in [320, 390] {
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
            window.frame = UIScreen.main.bounds
            let container = UIViewController()
            let host = UIHostingController(rootView: NavigationStack { AIChatView().environmentObject(app) })
            window.rootViewController = container; window.makeKeyAndVisible()
            container.addChild(host); container.view.addSubview(host.view)
            host.view.frame = CGRect(x: 0, y: 0, width: width, height: 844); host.didMove(toParent: container)
            try await Task.sleep(nanoseconds: 300_000_000)
            host.view.layoutIfNeeded()
            XCTAssertEqual(host.view.bounds.width, width, accuracy: 1)
            XCTAssertEqual(host.view.bounds.height, 844, accuracy: 1)
            let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = "release117-ai-entry-\(Int(width))"; attachment.lifetime = .keepAlways; add(attachment)
            window.isHidden = true
        }
    }
}

private final class AIChatMemorySecrets: SecretStoring {
    private var values: [String: String] = [:]
    func set(_ value: String, for key: String) throws { values[key] = value }
    func value(for key: String) -> String? { values[key] }
    func removeValue(for key: String) throws { values.removeValue(forKey: key) }
}

private actor AIChatFixtureTransport: AIChatTransport {
    let status: Int
    let data: Data
    let delay: UInt64
    private(set) var callCount = 0
    init(status: Int, data: Data, delay: UInt64 = 0) { self.status = status; self.data = data; self.delay = delay }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        callCount += 1
        if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
