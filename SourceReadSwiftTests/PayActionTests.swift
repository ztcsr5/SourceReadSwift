import XCTest
@testable import SourceReadSwift

final class PayActionPolicyTests: XCTestCase {
    func testSegmentsSplitLiteralAndScript() {
        let segments = PayActionPolicy.segments(in: "https://pay.example.com/{{chapter.url}}?t={{title}}")
        XCTAssertEqual(segments, [
            .literal("https://pay.example.com/"),
            .script("chapter.url"),
            .literal("?t="),
            .script("title")
        ])
    }

    func testUnterminatedBraceStaysLiteral() {
        let segments = PayActionPolicy.segments(in: "https://pay.example.com/{{broken")
        XCTAssertEqual(segments, [.literal("https://pay.example.com/{{broken")])
    }

    func testTemplateEvaluatesEveryScriptSegment() {
        let result = PayActionPolicy.evaluate(rule: "https://pay.example.com/{{chapter.url}}?k={{title}}") { script in
            switch script {
            case "chapter.url": return .success("ch1")
            case "title": return .success("ChapterOne")
            default: return .failure(.javascript("unexpected script: \(script)"))
            }
        }
        guard case .success(.openURL(let url)) = result else {
            return XCTFail("expected openURL, got \(result)")
        }
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "pay.example.com")
        XCTAssertEqual(url.path, "/ch1")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "k" })?.value
        XCTAssertEqual(query, "ChapterOne")
    }

    func testRuleWithoutTemplateRunsAsSingleScript() {
        var executed: [String] = []
        let result = PayActionPolicy.evaluate(rule: "@js:doPurchase()") { script in
            executed.append(script)
            return .success("true")
        }
        XCTAssertEqual(executed, ["@js:doPurchase()"])
        guard case .success(.purchased) = result else {
            return XCTFail("expected purchased, got \(result)")
        }
    }

    func testAtJSTrueResultIsPurchased() {
        var executed: [String] = []
        let result = PayActionPolicy.evaluate(rule: "@js:return 'true'") { script in
            executed.append(script)
            return .success("true")
        }
        XCTAssertEqual(executed, ["@js:return 'true'"])
        guard case .success(.purchased) = result else {
            return XCTFail("expected purchased, got \(result)")
        }
    }

    func testJSBlockTrueResultIsPurchased() {
        var executed: [String] = []
        let result = PayActionPolicy.evaluate(rule: "<js>return 'true'</js>") { script in
            executed.append(script)
            return .success("true")
        }
        XCTAssertEqual(executed, ["<js>return 'true'</js>"])
        guard case .success(.purchased) = result else {
            return XCTFail("expected purchased, got \(result)")
        }
    }

    func testPureAbsoluteURLSkipsJavaScript() {
        var executed: [String] = []
        let result = PayActionPolicy.evaluate(rule: "https://pay.example.com/ch/1") { script in
            executed.append(script)
            return .failure(.javascript("a pure URL must not be executed as JavaScript"))
        }
        XCTAssertTrue(executed.isEmpty)
        guard case .success(.openURL(let url)) = result else {
            return XCTFail("expected openURL, got \(result)")
        }
        XCTAssertEqual(url.absoluteString, "https://pay.example.com/ch/1")
    }

    func testMalformedAbsoluteURLFailsWithoutJavaScript() {
        var executed = false
        let result = PayActionPolicy.evaluate(rule: "https://[::1/pay") { _ in
            executed = true
            return .success("true")
        }
        XCTAssertFalse(executed)
        guard case .failure(.rule(let message)) = result else {
            return XCTFail("expected a rule failure, got \(result)")
        }
        XCTAssertTrue(message.contains("URL 无效"))
    }

    func testClassifyAbsoluteURL() {
        guard case .openURL(let url) = PayActionPolicy.classify("  HTTPS://Pay.Example.com/x  ") else {
            return XCTFail("expected openURL")
        }
        XCTAssertEqual(url.scheme?.lowercased(), "https")
        XCTAssertEqual(url.host?.lowercased(), "pay.example.com")
        XCTAssertEqual(url.path, "/x")
    }

    func testClassifyTruthyValues() {
        // Legado `isTrue()`: everything except false/no/not/0/blank/null.
        for value in ["true", "1", "YES", "ok", "success", "已购买"] {
            XCTAssertEqual(PayActionPolicy.classify(value), .purchased, "expected truthy: \(value)")
        }
    }

    func testClassifyFalseValuesAreFailure() {
        for value in ["false", "NO", "not", "0", "null", "", "   "] {
            guard case .failed = PayActionPolicy.classify(value) else {
                return XCTFail("expected failure for \(value)")
            }
        }
    }

    func testScriptFailurePropagates() {
        let result = PayActionPolicy.evaluate(rule: "{{chapter.url}}") { _ in
            .failure(.javascript("boom"))
        }
        guard case .failure(let error) = result else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(error.displayMessage, "boom")
    }

    func testHTMLContentCarriesPayAction() {
        let source = BookSource(
            bookSourceName: "Test",
            bookSourceUrl: "https://example.com",
            ruleContent: SourceRule(fields: [
                "content": ".content@html",
                "payAction": "https://example.com/buy/{{chapter.url}}"
            ])
        )
        let chapter = BookChapter(
            title: "第一章",
            url: "https://example.com/book/1/1.html",
            bookUrl: "https://example.com/book/1",
            index: 0,
            isVip: true
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: [:],
            body: "<html><body><div class=\"content\"><p>正文第一段内容足够长用于解析</p></div></body></html>",
            data: Data()
        )

        let result = ContentParser().parse(source: source, chapter: chapter, response: response)

        guard case .success(let content) = result else {
            return XCTFail("expected parsed content")
        }
        XCTAssertEqual(content.payAction, "https://example.com/buy/{{chapter.url}}")
    }

    func testJSONContentCarriesPayAction() {
        let source = BookSource(
            bookSourceName: "API",
            bookSourceUrl: "https://api.example.com",
            ruleContent: SourceRule(fields: [
                "content": "data.content",
                "payAction": "@js:purchase(chapter)"
            ])
        )
        let chapter = BookChapter(
            title: "第一章",
            url: "https://api.example.com/chapter/1",
            bookUrl: "https://api.example.com/book/1",
            index: 0,
            isVip: true
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: ["content-type": "application/json"],
            body: #"{"data":{"content":"正文第一段内容足够长用于解析"}}"#,
            data: Data()
        )

        let result = ContentParser().parse(source: source, chapter: chapter, response: response)

        guard case .success(let content) = result else {
            return XCTFail("expected parsed content")
        }
        XCTAssertEqual(content.payAction, "@js:purchase(chapter)")
    }
}

@MainActor
final class PayActionCacheTests: XCTestCase {
    private func makeChapter() -> BookChapter {
        BookChapter(
            title: "第一章",
            url: "https://example.com/chapter/1",
            bookUrl: "https://example.com/book",
            index: 0,
            isVip: true
        )
    }

    func testCacheRoundTripPreservesPayAction() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = ChapterContentCachePersistence(fileManager: .default, rootURL: root)
        let store = ChapterContentCacheStore(persistence: persistence)
        let chapter = makeChapter()
        let content = ChapterContent(
            chapter: chapter,
            title: chapter.title,
            paragraphs: ["A"],
            nextContentUrl: nil,
            imageStyle: nil,
            payAction: "https://pay.example.com/{{chapter.url}}"
        )

        store.save(content, sourceURL: "https://source.example.com", purifyRules: [])

        let reloaded = ChapterContentCacheStore(persistence: persistence)
        XCTAssertEqual(
            reloaded.content(sourceURL: "https://source.example.com", chapter: chapter, purifyRules: [])?.payAction,
            "https://pay.example.com/{{chapter.url}}"
        )
        XCTAssertEqual(
            reloaded.staleContent(sourceURL: "https://source.example.com", chapter: chapter)?.payAction,
            "https://pay.example.com/{{chapter.url}}"
        )
        try? FileManager.default.removeItem(at: root)
    }

    func testInvalidateDropsOnlyThePurchasedChapter() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = ChapterContentCachePersistence(fileManager: .default, rootURL: root)
        let store = ChapterContentCacheStore(persistence: persistence)
        let chapter = makeChapter()
        let other = BookChapter(
            title: "第二章",
            url: "https://example.com/chapter/2",
            bookUrl: "https://example.com/book",
            index: 1,
            isVip: true
        )
        let sourceURL = "https://source.example.com"
        store.save(
            ChapterContent(chapter: chapter, title: chapter.title, paragraphs: ["old"], payAction: "@js:buy()"),
            sourceURL: sourceURL,
            purifyRules: []
        )
        store.save(
            ChapterContent(chapter: other, title: other.title, paragraphs: ["keep"], payAction: "@js:buy()"),
            sourceURL: sourceURL,
            purifyRules: []
        )

        store.invalidate(sourceURL: sourceURL, chapter: chapter)

        XCTAssertNil(store.content(sourceURL: sourceURL, chapter: chapter, purifyRules: []))
        XCTAssertNil(store.staleContent(sourceURL: sourceURL, chapter: chapter))
        XCTAssertEqual(store.content(sourceURL: sourceURL, chapter: other, purifyRules: [])?.paragraphs, ["keep"])

        let reloaded = ChapterContentCacheStore(persistence: persistence)
        XCTAssertNil(reloaded.staleContent(sourceURL: sourceURL, chapter: chapter))
        XCTAssertEqual(reloaded.staleContent(sourceURL: sourceURL, chapter: other)?.paragraphs, ["keep"])
        try? FileManager.default.removeItem(at: root)
    }

    func testLegacyCacheWithoutPayActionDecodes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let legacy = """
        [{"key":"s|c","sourceURL":"s","chapterURL":"c","bookURL":"b","chapterIndex":0,"title":"t","paragraphs":["p"],"purifySignature":"sig","cachedAt":"2026-01-01T00:00:00Z"}]
        """
        try legacy.data(using: .utf8)!.write(to: root.appendingPathComponent("chapter_content_cache.json"))

        let entries = try ChapterContentCachePersistence(fileManager: .default, rootURL: root).load()

        XCTAssertEqual(entries.count, 1)
        XCTAssertNil(entries.first?.payAction)
        try? FileManager.default.removeItem(at: root)
    }

    func testChapterContentCodableRoundTripPreservesPayAction() throws {
        let chapter = makeChapter()
        let content = ChapterContent(
            chapter: chapter,
            title: chapter.title,
            paragraphs: ["A", "B"],
            nextContentUrl: "https://example.com/chapter/2",
            imageStyle: "full",
            payAction: "@js:buy()"
        )

        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(ChapterContent.self, from: data)

        XCTAssertEqual(decoded, content)
        XCTAssertEqual(decoded.payAction, "@js:buy()")
    }
}
