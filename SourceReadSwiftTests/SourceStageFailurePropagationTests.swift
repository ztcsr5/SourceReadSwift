import Foundation
import XCTest
@testable import SourceReadSwift

final class SourceStageFailurePropagationTests: XCTestCase {
    func testDetailInitFailureDoesNotReturnSearchMetadataOrRepeatItsRequest() async throws {
        for bootstrap in ["{}", "opaque fixture"] {
            for status in [200, 400, 401, 500, 502] {
                let network = StageFailureFixtureNetwork(bootstrap: bootstrap, statusCode: status)
                let source = makeSource()
                let result = await makeEngine(network).getBookDetail(source: source, book: makeBook(source))
                assertFailure(result, statusCode: status)
                let paths = await network.recordedPaths()
                XCTAssertEqual(paths, ["/bootstrap/detail", "/detail"], "A failed init must execute once")
            }
        }
    }

    func testContentFailureDoesNotRepeatItsRuleOrReturnFallbackText() async throws {
        for bootstrap in ["{}", #"{"content":"这是默认字段中的旧文本，不能覆盖明确的脚本请求失败。"}"#] {
            for status in [200, 400, 401, 500, 502] {
                let network = StageFailureFixtureNetwork(bootstrap: bootstrap, statusCode: status)
                let result = await makeEngine(network).getContent(source: makeSource(), chapter: makeChapter())
                assertFailure(result, statusCode: status)
                let paths = await network.recordedPaths()
                XCTAssertEqual(paths, ["/bootstrap/content", "/content"], "A failed content rule must execute once")
            }
        }
    }

    func testDetailInitCanRecoverAndReturnItsOwnValidContainer() async throws {
        let network = StageFailureFixtureNetwork(bootstrap: "{}", statusCode: 400, body: #"{"data":null}"#)
        let source = makeSource(detailInit: """
        @js: var remote = JSON.parse(java.ajax('https://stage.fixture.invalid/detail'));
        JSON.stringify(remote.data || {name:'恢复详情',tocUrl:'https://stage.fixture.invalid/catalog'});
        """)
        let detail = try await makeEngine(network).getBookDetail(source: source, book: makeBook(source)).get()
        XCTAssertEqual(detail.name, "恢复详情")
        XCTAssertEqual(detail.tocUrl, "https://stage.fixture.invalid/catalog")
        let paths = await network.recordedPaths()
        XCTAssertEqual(paths, ["/bootstrap/detail", "/detail"])
    }

    func testContentScriptCanRecoverAndReturnItsOwnValidText() async throws {
        let network = StageFailureFixtureNetwork(bootstrap: "{}", statusCode: 400, body: #"{"data":null}"#)
        let source = makeSource(contentRule: """
        @js: var remote = JSON.parse(java.ajax('https://stage.fixture.invalid/content'));
        remote.data ? remote.data.content : '恢复正文，人物沿着海岸继续走向下一座城。';
        """)
        let content = try await makeEngine(network).getContent(source: source, chapter: makeChapter()).get()
        XCTAssertEqual(content.paragraphs, ["恢复正文，人物沿着海岸继续走向下一座城。"])
        let paths = await network.recordedPaths()
        XCTAssertEqual(paths, ["/bootstrap/content", "/content"])
    }

    func testNoHTTPResponseDoesNotRepeatEitherStageRule() async throws {
        let source = makeSource()
        let detailNetwork = StageFailureFixtureNetwork(bootstrap: "{}", statusCode: nil)
        let detail = await makeEngine(detailNetwork).getBookDetail(source: source, book: makeBook(source))
        guard case .failure(.network(let detailMessage)) = detail else { return XCTFail("Expected transport failure: \(detail)") }
        XCTAssertTrue(detailMessage.contains("未收到可用响应"))
        let detailPaths = await detailNetwork.recordedPaths()
        XCTAssertEqual(detailPaths, ["/bootstrap/detail", "/detail"])

        let contentNetwork = StageFailureFixtureNetwork(bootstrap: "{}", statusCode: nil)
        let content = await makeEngine(contentNetwork).getContent(source: source, chapter: makeChapter())
        guard case .failure(.network(let contentMessage)) = content else { return XCTFail("Expected transport failure: \(content)") }
        XCTAssertTrue(contentMessage.contains("未收到可用响应"))
        let contentPaths = await contentNetwork.recordedPaths()
        XCTAssertEqual(contentPaths, ["/bootstrap/content", "/content"])
    }

    func testNewParserPageDoesNotReuseAnEarlierScriptFailure() throws {
        let source = makeSource(detailInit: "@js: result", contentRule: "$.content")
        let context = RuleExecutionContext(source: source)
        let response = SourceResponse(url: URL(string: source.bookSourceUrl)!, statusCode: 200,
            headers: ["Content-Type": "application/json"], body: #"{"content":"当前正文"}"#, data: Data())
        context.recordScriptRequestFailure(.network("previous page failure"))
        context.recordJavaScriptError("previous page exception")
        let detail = try BookDetailParser(executionContext: context).parse(source: source, book: makeBook(source), response: response).get()
        XCTAssertEqual(detail.name, "搜索结果旧名")
        context.recordScriptRequestFailure(.network("previous page failure"))
        context.recordJavaScriptError("previous page exception")
        let content = try ContentParser(executionContext: context).parse(source: source, chapter: makeChapter(), response: response).get()
        XCTAssertEqual(content.paragraphs, ["当前正文"])
    }

    func testOpaqueJSONContentInitRunsTopLevelReturnAndItsRequestOnce() throws {
        for contentRule in ["$.payload.content", "$['payload']['content']", "@Json:$.payload.content"] {
            let source = makeSource(contentRule: contentRule, contentInit: """
            @js:java.put('contentInitCount', String(Number(java.get('contentInitCount') || '0') + 1));
            var prose = String(java.ajax('https://stage.fixture.invalid/content'));
            return JSON.stringify({payload:{content:prose}});
            """)
            let context = RuleExecutionContext(source: source)
            var requests: [String] = []
            context.networkHandler = { address in
                requests.append(address)
                return "人物来到海边，继续沿着岸边走向远方。"
            }
            let response = SourceResponse(url: URL(string: makeChapter().url)!, statusCode: 200,
                headers: [:], body: "opaque content response", data: Data())

            let content = try ContentParser(executionContext: context).parse(source: source,
                chapter: makeChapter(), response: response).get()

            XCTAssertEqual(content.paragraphs, ["人物来到海边，继续沿着岸边走向远方。"], contentRule)
            XCTAssertEqual(requests, ["https://stage.fixture.invalid/content"], contentRule)
            XCTAssertEqual(context.get("contentInitCount"), "1", contentRule)
            XCTAssertNil(context.currentJavaScriptError, contentRule)
        }
    }

    func testOpaqueJSONContentInitFailureDoesNotRepeatItsRequest() async throws {
        for status in [200, 400, 401, 500, 502] {
            let network = StageFailureFixtureNetwork(bootstrap: "opaque content response", statusCode: status)
            let source = makeSource(contentRule: "$.content", contentInit: """
            @js:return JSON.parse(java.ajax('https://stage.fixture.invalid/content'));
            """)
            let result = await makeEngine(network).getContent(source: source, chapter: makeChapter())

            assertFailure(result, statusCode: status)
            let paths = await network.recordedPaths()
            XCTAssertEqual(paths, ["/bootstrap/content", "/content"], "A failed opaque init must execute once")
        }
    }

    func testOpaqueJSONContentInitCanReturnRootText() throws {
        let source = makeSource(contentRule: "$", contentInit: "@js:return '人物来到海边，继续沿着岸边走向远方。';")
        let response = SourceResponse(url: URL(string: makeChapter().url)!, statusCode: 200,
            headers: [:], body: "opaque content response", data: Data())

        let content = try ContentParser().parse(source: source, chapter: makeChapter(), response: response).get()

        XCTAssertEqual(content.paragraphs, ["人物来到海边，继续沿着岸边走向远方。"])
    }

    func testOpaqueJSONContentInitWithEmptyContentDoesNotRepeatItsRequest() throws {
        let source = makeSource(contentRule: "$.content", contentInit: """
        @js:java.put('contentInitCount', String(Number(java.get('contentInitCount') || '0') + 1));
        java.ajax('https://stage.fixture.invalid/content');
        JSON.stringify({content:''});
        """)
        let context = RuleExecutionContext(source: source)
        var requests: [String] = []
        context.networkHandler = { address in requests.append(address); return "" }
        let response = SourceResponse(url: URL(string: makeChapter().url)!, statusCode: 200,
            headers: [:], body: "opaque content response", data: Data())

        let result = ContentParser(executionContext: context).parse(source: source, chapter: makeChapter(), response: response)

        guard case .failure(.empty) = result else { return XCTFail("Expected empty content: \(result)") }
        XCTAssertEqual(requests, ["https://stage.fixture.invalid/content"])
        XCTAssertEqual(context.get("contentInitCount"), "1")
        XCTAssertNil(context.currentJavaScriptError)
    }

    func testHTMLContentInitKeepsItsElementScope() throws {
        let source = makeSource(contentRule: "@text", contentInit: "@js:result.select('#content')")
        let response = SourceResponse(url: URL(string: makeChapter().url)!, statusCode: 200,
            headers: ["Content-Type": "text/html"],
            body: "<html><body><aside>页面导航</aside><div id='content'>当前正文</div></body></html>",
            data: Data())

        let content = try ContentParser().parse(source: source, chapter: makeChapter(), response: response).get()

        XCTAssertEqual(content.paragraphs, ["当前正文"])
    }

    func testJSONContentTemplatesAndTheirTrailingTransformsRemainSupported() throws {
        let examples = [
            ("{{$.prose}}", "人物离开旧城，继续沿着海岸走向远方。"),
            ("正文：{{$.prose}}", "正文：人物离开旧城，继续沿着海岸走向远方。"),
            ("{{$.prose}}##旧城##新城", "人物离开新城，继续沿着海岸走向远方。"),
            ("{{$.prose}}@js:result.replace('旧城','新城')", "人物离开新城，继续沿着海岸走向远方。"),
            ("{{$.prose}}<js>result.replace('旧城','新城')</js>", "人物离开新城，继续沿着海岸走向远方。")
        ]
        let response = SourceResponse(url: URL(string: makeChapter().url)!, statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: #"{"prose":"人物离开旧城，继续沿着海岸走向远方。"}"#, data: Data())
        for (rule, expected) in examples {
            let content = try ContentParser().parse(source: makeSource(contentRule: rule),
                chapter: makeChapter(), response: response).get()
            XCTAssertEqual(content.paragraphs, [expected], rule)
        }
    }

    func testJSONContentPreservesArrayAndObjectText() throws {
        for body in [
            #"{"prose":[{"p":"第一段人物来到海边。"},{"text":"第二段海上升起了雾气。"}]}"#,
            #"{"prose":{"content":["第一段人物来到海边。","第二段海上升起了雾气。"]}}"#
        ] {
            let response = SourceResponse(url: URL(string: makeChapter().url)!, statusCode: 200,
                headers: ["Content-Type": "application/json"], body: body, data: Data())
            let content = try ContentParser().parse(source: makeSource(contentRule: "$.prose"),
                chapter: makeChapter(), response: response).get()
            XCTAssertEqual(content.paragraphs, ["第一段人物来到海边。", "第二段海上升起了雾气。"])
        }
    }

    func testContentTemplateScriptFailureRunsItsRequestOnce() async throws {
        let network = StageFailureFixtureNetwork(bootstrap: #"{"prose":"当前正文"}"#, statusCode: 500)
        let source = makeSource(contentRule: "{{$.prose}}@js:JSON.parse(java.ajax('https://stage.fixture.invalid/content')).content")
        let result = await makeEngine(network).getContent(source: source, chapter: makeChapter())
        assertFailure(result, statusCode: 500)
        let paths = await network.recordedPaths()
        XCTAssertEqual(paths, ["/bootstrap/content", "/content"])
    }

    func testContentJavaScriptWithEmbeddedTemplateKeepsObjectEvaluation() async throws {
        let network = StageFailureFixtureNetwork(bootstrap: #"{"field":"content"}"#, statusCode: 200,
            body: #"{"content":"人物来到海边，继续沿着岸边走向远方。"}"#)
        let source = makeSource(contentRule: "@js:JSON.parse(java.ajax('https://stage.fixture.invalid/content')).{{$.field}}")
        let content = try await makeEngine(network).getContent(source: source, chapter: makeChapter()).get()
        XCTAssertEqual(content.paragraphs, ["人物来到海边，继续沿着岸边走向远方。"])
        let paths = await network.recordedPaths()
        XCTAssertEqual(paths, ["/bootstrap/content", "/content"])
    }

    func testHTMLContentAndInitExceptionsDoNotReturnPageFallbackText() {
        let response = SourceResponse(url: URL(string: makeChapter().url)!, statusCode: 200,
            headers: ["Content-Type": "text/html"],
            body: "<html><body><div id='content'>这是页面中超过三十个字符的旧文本，明确的正文规则异常不能被这段默认容器文本覆盖。</div></body></html>",
            data: Data())
        let sources = [
            makeSource(contentRule: "@js:throw new Error('content fixture exception')"),
            makeSource(contentRule: "#content@text", contentInit: "@js:throw new Error('init fixture exception')")
        ]
        for source in sources {
            let result = ContentParser().parse(source: source, chapter: makeChapter(), response: response)
            guard case .failure(.javascript(let message)) = result else {
                XCTFail("Expected HTML script failure instead of fallback text: \(result)")
                continue
            }
            XCTAssertTrue(message.contains("fixture exception"), message)
        }
    }

    func testDetailHTMLInitFailureDoesNotReturnSearchMetadataAfterJSONFallback() {
        let source = makeSource(detailInit: """
        @js:var attempts = Number(java.get('htmlInitCount') || '0') + 1;
        java.put('htmlInitCount', String(attempts));
        if (attempts > 1) throw new Error('html init fixture exception');
        result;
        """)
        let context = RuleExecutionContext(source: source)
        let response = SourceResponse(url: URL(string: makeBook(source).bookUrl)!, statusCode: 200,
            headers: ["Content-Type": "text/html"],
            body: "<html><body><h1>页面旧书名</h1></body></html>", data: Data())
        let result = BookDetailParser(executionContext: context).parse(source: source, book: makeBook(source), response: response)
        guard case .failure(.javascript(let message)) = result else {
            return XCTFail("Expected HTML init failure instead of search metadata: \(result)")
        }
        XCTAssertTrue(message.contains("html init fixture exception"), message)
        XCTAssertEqual(context.get("htmlInitCount"), "2")
    }

    private func makeSource(detailInit: String? = nil, contentRule: String? = nil, contentInit: String? = nil) -> BookSource {
        var contentFields = [
            "content": contentRule ?? "@js: JSON.parse(java.ajax('https://stage.fixture.invalid/content')).data.content"
        ]
        contentFields["init"] = contentInit
        return BookSource(bookSourceName: "Stage failure fixture", bookSourceUrl: "https://stage.fixture.invalid",
            ruleBookInfo: SourceRule(fields: [
                "init": detailInit ?? "@js: JSON.parse(java.ajax('https://stage.fixture.invalid/detail')).data",
                "name": "$.name", "tocUrl": "$.tocUrl"
            ]),
            ruleContent: SourceRule(fields: contentFields))
    }

    private func makeBook(_ source: BookSource) -> SearchBook {
        SearchBook(name: "搜索结果旧名", author: nil, coverUrl: nil,
            bookUrl: "https://stage.fixture.invalid/bootstrap/detail",
            sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl)
    }

    private func makeChapter() -> BookChapter {
        BookChapter(title: "第一章", url: "https://stage.fixture.invalid/bootstrap/content",
            bookUrl: "https://stage.fixture.invalid/bootstrap/detail", index: 0)
    }

    private func makeEngine(_ network: StageFailureFixtureNetwork) -> LegadoSourceEngine {
        let engine = LegadoSourceEngine(network: network, cookieStore: SourceCookieStore(storageURL: nil),
            scriptCacheStore: SourceScriptCacheStore(isPersistent: false))
        engine.allowWebViewFallback = false
        return engine
    }

    private func assertFailure<Value>(_ result: Result<Value, SourceEngineError>, statusCode: Int,
                                      file: StaticString = #filePath, line: UInt = #line) {
        guard case .failure(let error) = result else { return XCTFail("Expected stage failure", file: file, line: line) }
        if statusCode == 200 {
            guard case .javascript = error else { return XCTFail("Expected JSON.parse failure: \(error)", file: file, line: line) }
        } else {
            guard case .network(let message) = error else { return XCTFail("Expected HTTP failure: \(error)", file: file, line: line) }
            XCTAssertTrue(message.contains("HTTP \(statusCode)"), message, file: file, line: line)
        }
    }
}

private actor StageFailureFixtureNetwork: SourceNetworkClient {
    private let bootstrap: String
    private let statusCode: Int?
    private let body: String
    private var paths: [String] = []

    init(bootstrap: String, statusCode: Int?, body: String = "<html><body>Fixture login required</body></html>") {
        self.bootstrap = bootstrap
        self.statusCode = statusCode
        self.body = body
    }

    func recordedPaths() -> [String] { paths }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        paths.append(request.url.path)
        guard request.url.host == "stage.fixture.invalid" else { return .failure(.network("Unexpected fixture host")) }
        let isBootstrap = request.url.path == "/bootstrap/detail" || request.url.path == "/bootstrap/content"
        guard isBootstrap || request.url.path == "/detail" || request.url.path == "/content" else {
            return .failure(.network("Unexpected fixture path"))
        }
        guard let status = isBootstrap ? 200 : statusCode else { return .failure(.network("Fixture transport failure")) }
        let responseBody = isBootstrap ? bootstrap : body
        return .success(SourceResponse(url: request.url, statusCode: status,
            headers: ["Content-Type": isBootstrap ? "application/json" : "text/html"],
            body: responseBody, data: Data(responseBody.utf8)))
    }
}
