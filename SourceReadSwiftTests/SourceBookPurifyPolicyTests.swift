import XCTest
@testable import SourceReadSwift

final class SourceBookPurifyPolicyTests: XCTestCase {
    func testConcurrentInheritedChoicesCannotOverwriteAuthoredChoice() {
        let preferences = BookPurifyPreferenceStore()
        let sourceURL = "https://purify.fixture"
        let bookURL = "https://purify.fixture/book/1"
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            if index == 50 {
                preferences.set(false, sourceURL: sourceURL, bookURL: bookURL)
            } else {
                _ = preferences.resolve(sourceURL: sourceURL, bookURL: bookURL, inherited: true)
            }
        }
        XCTAssertEqual(preferences.value(sourceURL: sourceURL, bookURL: bookURL), false)
        XCTAssertEqual(preferences.resolve(sourceURL: sourceURL, bookURL: bookURL, inherited: true), false)
        XCTAssertEqual(preferences.resolve(sourceURL: sourceURL, bookURL: bookURL + "2", inherited: true), true)
    }

    func testDetailPreferenceReachesDirectoryAndOnlyDisablesGlobalRules() async throws {
        let source = makeSource(detail: "@js:book.setUseReplaceRule(false); 'Fixture'")
        let engine = LegadoSourceEngine(network: PurifyPolicyFixtureNetwork(),
            cookieStore: SourceCookieStore(storageURL: nil), purifyRules: { ["GLOBAL##removed"] })
        let book = SearchBook(name: "Fixture", author: nil, coverUrl: nil,
            bookUrl: "https://purify.fixture/book/1", sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl)
        let detail = try await engine.getBookDetail(source: source, book: book).get()
        XCTAssertEqual(detail.useReplaceRule, false)
        let chapters = try await engine.getChapterList(source: source, book: detail).get()
        let chapter = try XCTUnwrap(chapters.first)
        XCTAssertEqual(chapter.useReplaceRule, false)
        let content = try await engine.getContent(source: source, chapter: chapter).get()
        XCTAssertEqual(content.paragraphs, ["LOCAL GLOBAL"])
        XCTAssertEqual(content.chapter.useReplaceRule, false)
    }

    func testContentPreferenceSurvivesRestartAndDoesNotLeakToOtherBooksOrSources() async throws {
        let suite = "SourceBookPurifyPolicyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = makeSource(content: "@js:if (chapter.index === 0) book.setUseReplaceRule(false); JSON.parse(result).content")
        let preferences = BookPurifyPreferenceStore(defaults: defaults)
        let engine = LegadoSourceEngine(network: PurifyPolicyFixtureNetwork(),
            cookieStore: SourceCookieStore(storageURL: nil), purifyRules: { ["GLOBAL##removed"] },
            purifyPreferences: preferences)
        let first = BookChapter(title: "第一章", url: "https://purify.fixture/chapter/1",
            bookUrl: "https://purify.fixture/book/1", index: 0)
        let firstContent = try await engine.getContent(source: source, chapter: first).get()
        XCTAssertEqual(firstContent.paragraphs, ["LOCAL GLOBAL"])
        let restored = BookPurifyPreferenceStore(defaults: defaults)
        let restartedEngine = LegadoSourceEngine(network: PurifyPolicyFixtureNetwork(),
            cookieStore: SourceCookieStore(storageURL: nil), purifyRules: { ["GLOBAL##removed"] },
            purifyPreferences: restored)
        let next = BookChapter(title: "第二章", url: "https://purify.fixture/chapter/2",
            bookUrl: first.bookUrl, index: 1)
        let nextContent = try await restartedEngine.getContent(source: source, chapter: next).get()
        XCTAssertEqual(nextContent.paragraphs, ["LOCAL GLOBAL"])
        let other = BookChapter(title: "另一书", url: next.url, bookUrl: "https://purify.fixture/book/2", index: 1)
        let otherContent = try await restartedEngine.getContent(source: source, chapter: other).get()
        XCTAssertEqual(otherContent.paragraphs, ["LOCAL removed"])
        XCTAssertNil(restored.value(sourceURL: "https://other-source.fixture", bookURL: first.bookUrl))
        XCTAssertEqual(restored.value(sourceURL: source.bookSourceUrl, bookURL: first.bookUrl), false)
    }

    func testNativeAndDictionaryBookMethodsKeepIndependentState() throws {
        let runtime = JSCoreRuntime()
        let book = LegadoSearchBookBridge(book: SearchBook(name: "Fixture", author: nil, coverUrl: nil,
            bookUrl: "/book/1", sourceName: "Fixture", sourceUrl: "https://purify.fixture", mediaKind: .text))
        XCTAssertEqual(try runtime.evaluate("book.setUseReplaceRule(false); book.getUseReplaceRule()",
            variables: ["book": book]).get(), "false")
        XCTAssertEqual(book.useReplaceRuleOverride, false)
        XCTAssertEqual(try runtime.evaluate("book.getUseReplaceRule()", variables: ["book": book]).get(), "false")
        XCTAssertEqual(try runtime.evaluate("book.setUseReplaceRule(false); book.getUseReplaceRule()",
            variables: ["book": ["type": 8]]).get(), "false")
        XCTAssertEqual(try runtime.evaluate("book.getUseReplaceRule()", variables: ["book": ["type": 8]]).get(), "true")
    }

    func testLateTitleAndNextPageRulesControlTheWholePage() throws {
        let chapter = BookChapter(title: "第一章", url: "https://purify.fixture/chapter/1",
            bookUrl: "https://purify.fixture/book/1", index: 0)
        for isJSON in [true, false] {
            for field in ["title", "nextContentUrl"] {
                let fields = ["content": isJSON ? "$.content" : "#content@html",
                    "replaceRegex": "SOURCE##LOCAL",
                    field: "@js:book.setUseReplaceRule(false); " + (field == "title" ? "'第一章'" : "''")]
                let source = BookSource(bookSourceName: "Late choice", bookSourceUrl: "https://purify.fixture",
                    ruleContent: .init(fields: fields))
                let body = isJSON ? #"{"content":"SOURCE GLOBAL"}"# : "<div id='content'>SOURCE GLOBAL</div>"
                let response = SourceResponse(url: URL(string: chapter.url)!, statusCode: 200,
                    headers: ["Content-Type": isJSON ? "application/json" : "text/html"],
                    body: body, data: Data(body.utf8))
                let content = try ContentParser().parse(source: source, chapter: chapter, response: response,
                    globalPurifyRules: ["GLOBAL##removed"]).get()
                XCTAssertEqual(content.paragraphs, ["LOCAL GLOBAL"], "\(field), JSON=\(isJSON)")
                XCTAssertEqual(content.chapter.useReplaceRule, false)
            }
        }
    }

    func testTextWidePurificationKeepsDirectMediaURLsUntouched() throws {
        for kind in [BookSourceKind.audio, .video] {
            let source = BookSource(bookSourceName: "Stream", bookSourceUrl: "https://purify.fixture",
                bookSourceType: kind.rawValue)
            let chapter = BookChapter(title: "第一章", url: "https://purify.fixture/media",
                bookUrl: "https://purify.fixture/book/1", index: 0, mediaKind: kind)
            let response = SourceResponse(url: URL(string: chapter.url)!, statusCode: 200,
                headers: ["Content-Type": kind == .audio ? "audio/mpeg" : "video/mp4"],
                body: "", data: Data([1]))
            let parsed = try ContentParser().parse(source: source, chapter: chapter, response: response,
                globalPurifyRules: ["(?s).*##"]).get()
            XCTAssertEqual(parsed.paragraphs, [chapter.url])
        }
    }

    @MainActor
    func testLastPageChoiceControlsTheWholeChapterWithoutReplayingSourceScripts() async throws {
        let cacheRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cacheRoot) }
        for finalChoice in [false, true] {
            let preferences = BookPurifyPreferenceStore()
            let source = BookSource(bookSourceName: "Paged choice", bookSourceUrl: "https://purify.fixture",
                ruleContent: .init(fields: [
                    "bodyJs": """
                        book.putVariable('bodyRuns', String(Number(book.getVariable('bodyRuns') || '0') + 1));
                        if (JSON.parse(result).page === 2) book.setUseReplaceRule(\(finalChoice));
                        result;
                        """,
                    "content": "$.content",
                    "nextContentUrl": "$.next",
                    "replaceRegex": """
                        @js:book.putVariable('sourceRuns', String(Number(book.getVariable('sourceRuns') || '0') + 1));
                        String(result).replace('SOURCE', 'LOCAL') + ' body=' + book.getVariable('bodyRuns')
                          + ' source=' + book.getVariable('sourceRuns');
                        """
                ]))
            let globalRules = ["@js:String(result).replace(/GLOBAL/g, 'removed') + '\\nGLOBAL_CALL'"]
            let engine = LegadoSourceEngine(network: PurifyPolicyFixtureNetwork(),
                cookieStore: SourceCookieStore(storageURL: nil), purifyRules: { globalRules },
                purifyPreferences: preferences)
            let chapter = BookChapter(title: "第一章", url: "https://purify.fixture/paged/1",
                bookUrl: "https://purify.fixture/paged-book/1", index: 0, useReplaceRule: !finalChoice)
            let content = try await engine.getContent(source: source, chapter: chapter).get()
            let word = finalChoice ? "removed" : "GLOBAL"
            var expected = ["LOCAL \(word) page-one body=1 source=1", "LOCAL \(word) page-two body=2 source=2"]
            if finalChoice { expected.append("GLOBAL_CALL") }
            XCTAssertEqual(content.paragraphs, expected)
            XCTAssertEqual(content.chapter.useReplaceRule, finalChoice)
            XCTAssertEqual(preferences.value(sourceURL: source.bookSourceUrl, bookURL: chapter.bookUrl), finalChoice)
            let cache = ChapterContentCacheStore(
                persistence: ChapterContentCachePersistence(rootURL: cacheRoot.appendingPathComponent(String(finalChoice))),
                purifyPreferences: preferences)
            cache.save(content, sourceURL: source.bookSourceUrl, purifyRules: globalRules)
            try await cache.flush()
            XCTAssertEqual(cache.content(sourceURL: source.bookSourceUrl, chapter: chapter,
                purifyRules: globalRules)?.paragraphs, expected)
        }
    }

    private func makeSource(detail: String = "$.name", content: String = "$.content") -> BookSource {
        BookSource(bookSourceName: "Purify fixture", bookSourceUrl: "https://purify.fixture",
            ruleBookInfo: .init(fields: ["name": detail, "tocUrl": "$.toc"]),
            ruleToc: .init(fields: ["chapterList": "$.chapters[*]", "chapterName": "$.title", "chapterUrl": "$.url"]),
            ruleContent: .init(fields: ["content": content, "replaceRegex": "SOURCE##LOCAL"]))
    }
}

private struct PurifyPolicyFixtureNetwork: SourceNetworkClient {
    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        let body: String
        switch request.url.path {
        case "/book/1": body = #"{"name":"Fixture","toc":"/toc/1"}"#
        case "/toc/1": body = #"{"chapters":[{"title":"第一章","url":"/chapter/1"}]}"#
        case "/chapter/1", "/chapter/2": body = #"{"content":"SOURCE GLOBAL"}"#
        case "/paged/1": body = #"{"page":1,"content":"SOURCE GLOBAL page-one","next":"/paged/2"}"#
        case "/paged/2": body = #"{"page":2,"content":"SOURCE GLOBAL page-two","next":""}"#
        default: return .failure(.network("Unexpected purification fixture route"))
        }
        return .success(SourceResponse(url: request.url, statusCode: 200,
            headers: ["Content-Type": "application/json"], body: body, data: Data(body.utf8)))
    }
}
