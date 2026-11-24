import Foundation
import XCTest
@testable import SourceReadSwift

/// Covers Legado TOC metadata that previously stopped at the parser boundary:
/// volume rows (`ruleToc.isVolume`), post-processing (`ruleToc.formatJs`), and
/// metadata retention across paginated TOC pages.
final class ChapterListMetadataTests: XCTestCase {
    func testHTMLVolumeRowsBecomeVolumeNamesAndAreNotChapters() async throws {
        let tocURL = "https://fixture.example/book/html-volume/toc"
        let source = BookSource(
            bookSourceName: "HTML volume fixture",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "chapterList": "div.catalog h3, div.catalog a",
                "chapterName": "h3.volume@text||a@text",
                "chapterUrl": "a@href",
                "isVolume": "h3.volume@text"
            ])
        )
        let network = ChapterFixtureNetworkClient(responses: [
            tocURL: """
                <html><body>
                  <div class="catalog">
                    <h3 class="volume">第一卷</h3>
                    <a href="/chapter/1">第一章</a>
                    <a href="/chapter/2">第二章</a>
                    <h3 class="volume">第二卷</h3>
                    <a href="/chapter/3">第三章</a>
                  </div>
                </body></html>
                """
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))

        XCTAssertEqual(chapters.map(\.title), ["第一章", "第二章", "第三章"])
        XCTAssertEqual(chapters.map(\.volumeName), ["第一卷", "第一卷", "第二卷"])
        XCTAssertEqual(chapters.map(\.index), [0, 1, 2])
    }

    func testHTMLCatalogExplainsMissingAndFilteredChapterLinks() throws {
        let tocURL = try XCTUnwrap(URL(string: "https://fixture.example/book/catalog/toc"))
        let source = BookSource(bookSourceName: "HTML empty catalog fixture", bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: ["chapterList": "a.chapter", "chapterName": "text", "chapterUrl": "href"]))
        let html = """
        <a class="chapter" href="/book/catalog/toc">返回</a>
        <a class="chapter">有标题，无链接</a>
        <a class="chapter" href="/chapter/3"></a>
        """
        let response = SourceResponse(url: tocURL, statusCode: 200,
            headers: ["Content-Type": "text/html"], body: html, data: Data(html.utf8))
        let parsed = ChapterListParser().parse(source: source, book: makeBook(tocURL: tocURL.absoluteString), response: response)
        guard case .failure(.empty(let summary)) = parsed else {
            return XCTFail("Expected rows with no readable chapter to fail")
        }
        XCTAssertTrue(summary.contains("标题为空 1，链接为空 1，链接被过滤 1"), summary)
    }

    func testLeadingAtBeforeNestedChapterFieldsReadsTheLinksInsideEachRow() throws {
        let tocURL = try XCTUnwrap(URL(string: "https://fixture.example/books/sample/catalog"))
        let source = BookSource(bookSourceName: "Nested catalog fixture", bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "chapterList": "class.block-list@tag.ul@tag.li", "chapterName": "@tag.a@text", "chapterUrl": "@tag.a@href"
            ]))
        let html = """
            <div class="block-list"><ul>
              <li>01 <a href="/read/1">First</a></li>
              <li>02 <a href="/read/2">Second</a></li>
            </ul></div>
            """
        let response = SourceResponse(url: tocURL, statusCode: 200,
            headers: ["Content-Type": "text/html"], body: html, data: Data(html.utf8))

        let chapters = try ChapterListParser().parse(source: source,
            book: makeBook(tocURL: tocURL.absoluteString), response: response).get()

        XCTAssertEqual(chapters.map(\.title), ["First", "Second"])
        XCTAssertEqual(chapters.map(\.url), ["https://fixture.example/read/1", "https://fixture.example/read/2"])
    }

    func testIndexedXPathCatalogAndRelativeRowFieldsKeepTheirOwnScope() throws {
        let tocURL = try XCTUnwrap(URL(string: "https://fixture.example/books/sample/catalog"))
        let source = BookSource(bookSourceName: "Scoped XPath fixture", bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "chapterList": "@XPath:(//div[@class='index'])[2]//dd",
                "chapterName": "@XPath: .//a/text()",
                "chapterUrl": ".//a/@href"
            ]))
        let html = """
        <aside><div class="index"><dl><dd><a href="/preview">Preview</a></dd></dl></div></aside>
        <main><div class="index"><dl>
            <dd><span>01</span><a href="/read/1">First</a></dd>
            <dd><span>02</span><a href="/read/2">Second</a></dd>
        </dl></div></main>
        <aside><dl><dd><a href="/wrong">Outside</a></dd></dl></aside>
        """
        let response = SourceResponse(url: tocURL, statusCode: 200, headers: ["Content-Type": "text/html"],
            body: html, data: Data(html.utf8))

        let chapters = try ChapterListParser().parse(source: source,
            book: makeBook(tocURL: tocURL.absoluteString), response: response).get()

        XCTAssertEqual(chapters.map(\.title), ["First", "Second"])
        XCTAssertEqual(chapters.map(\.url), ["https://fixture.example/read/1", "https://fixture.example/read/2"])
        let extractor = HtmlRuleExtractor()
        let roots = try extractor.select(html, baseUrl: tocURL, listRule: "(//div[@class='index'])[3]//dd")
        XCTAssertTrue(roots.isEmpty)
    }

    func testExplicitSingleChapterJSONCanReadTheCatalogPageItself() throws {
        let tocURL = try XCTUnwrap(URL(string: "https://fixture.example/book/one-page/"))
        let source = BookSource(bookSourceName: "Single-page comic fixture", bookSourceUrl: "https://fixture.example",
            bookSourceType: BookSourceKind.comic.rawValue,
            ruleToc: SourceRule(fields: ["chapterList": "@js:[{name: '完整一话', url: baseUrl}]",
                "chapterName": "$.name", "chapterUrl": "$.url"]),
            ruleContent: SourceRule(fields: ["content": "img.page@src"]))
        let response = SourceResponse(url: tocURL, statusCode: 200,
            headers: ["Content-Type": "text/html"], body: "<img class='page' src='/page-1.jpg'>", data: Data())
        let chapters = try unwrap(ChapterListParser().parse(source: source,
            book: makeBook(tocURL: tocURL.absoluteString), response: response))

        XCTAssertEqual(chapters.map(\.title), ["完整一话"])
        XCTAssertEqual(chapters.map(\.url), [tocURL.absoluteString])
        XCTAssertEqual(chapters.map(\.index), [0])
    }

    func testSingleChapterExceptionKeepsNavigationAndUnconfiguredContentFiltered() throws {
        let tocURL = try XCTUnwrap(URL(string: "https://fixture.example/book/navigation/toc"))
        let response = SourceResponse(url: tocURL, statusCode: 200,
            headers: ["Content-Type": "application/json"], body: "[{\"name\":\"完整一话\",\"url\":\"\(tocURL)\"}]", data: Data())
        for fields in [
            ["chapterList": "@js:[{name: '目录', url: baseUrl}]", "chapterName": "$.name", "chapterUrl": "$.url"],
            ["chapterList": "@js:[{name: '返回', url: baseUrl}]", "chapterName": "$.name", "chapterUrl": "$.url"],
            ["chapterList": "@js:[{name: '完整一话', url: baseUrl}]", "chapterName": "$.name"],
            ["chapterList": "$[*]", "chapterName": "$.name", "chapterUrl": "$.url"],
            ["chapterList": "@js:[{name: '完整一话', url: baseUrl}]", "chapterName": "$.name", "chapterUrl": "$.url", "nextTocUrl": "$.next"]
        ] {
            let source = BookSource(bookSourceName: "Navigation fixture", bookSourceUrl: "https://fixture.example",
                ruleToc: SourceRule(fields: fields), ruleContent: SourceRule(fields: ["content": "img.page@src"]))
            if case .success = ChapterListParser().parse(source: source,
                book: makeBook(tocURL: tocURL.absoluteString), response: response) {
                XCTFail("A navigation or implicit list must not become a same-page chapter: \(fields)")
            }
        }
        let source = BookSource(bookSourceName: "Missing content fixture", bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: ["chapterList": "@js:[{name: '完整一话', url: baseUrl}]",
                "chapterName": "$.name", "chapterUrl": "$.url"]))
        if case .success = ChapterListParser().parse(source: source,
            book: makeBook(tocURL: tocURL.absoluteString), response: response) {
            XCTFail("A source without a content rule must not get a same-page chapter")
        }
    }

    func testScriptedMultiChapterJSONStillFiltersCatalogSelfLinks() throws {
        let tocURL = try XCTUnwrap(URL(string: "https://fixture.example/book/multiple/toc"))
        let source = BookSource(bookSourceName: "Multi-chapter fixture", bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "chapterList": "@js:[{name: '本书', url: baseUrl}, {name: '第一话', url: '/chapter/1'}]",
                "chapterName": "$.name", "chapterUrl": "$.url"]),
            ruleContent: SourceRule(fields: ["content": "img.page@src"]))
        let response = SourceResponse(url: tocURL, statusCode: 200,
            headers: ["Content-Type": "text/html"], body: "<p>Catalog</p>", data: Data())
        let chapters = try unwrap(ChapterListParser().parse(source: source,
            book: makeBook(tocURL: tocURL.absoluteString), response: response))

        XCTAssertEqual(chapters.map(\.title), ["第一话"])
        XCTAssertEqual(chapters.map(\.url), ["https://fixture.example/chapter/1"])
    }

    func testScriptedHTMLCatalogKeepsOriginalLinksAndAddedRowsInOrder() throws {
        let tocURL = try XCTUnwrap(URL(string: "https://fixture.example/book/mixed/toc"))
        let source = BookSource(bookSourceName: "Mixed comic catalog", bookSourceUrl: "https://fixture.example",
            bookSourceType: BookSourceKind.comic.rawValue, ruleToc: SourceRule(fields: [
                "chapterList": """
                -.chaplist-box@li@a
                @js:
                Array.from(result).concat([{text: '第一话', href: '/read/1'}])
                """,
                "chapterName": "text", "chapterUrl": "href", "nextTocUrl": "a.next@href"
            ]))
        let html = """
        <ul class="chaplist-box">
          <li><a href="/read/3">第三话</a></li>
          <li><a href="/read/2">第二话</a></li>
        </ul>
        <a class="next" href="/book/mixed/toc?p=2">Next</a>
        """
        let response = SourceResponse(url: tocURL, statusCode: 200, headers: ["Content-Type": "text/html"],
                                      body: html, data: Data(html.utf8))
        let page = try ChapterListParser().parsePage(source: source, book: makeBook(tocURL: tocURL.absoluteString),
                                                    response: response).get()

        XCTAssertEqual(page.chapters.map(\.title), ["第一话", "第二话", "第三话"])
        XCTAssertEqual(page.chapters.map(\.url), (1...3).map { "https://fixture.example/read/\($0)" })
        XCTAssertEqual(page.chapters.map(\.index), [0, 1, 2])
        XCTAssertEqual(page.nextTocUrl, "https://fixture.example/book/mixed/toc?p=2")
    }

    func testScriptedHTMLCatalogDoesNotUndoAnExplicitlyEmptySelection() throws {
        let tocURL = try XCTUnwrap(URL(string: "https://fixture.example/book/empty/toc"))
        let source = BookSource(bookSourceName: "Filtered comic catalog", bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: ["chapterList": ".chapter-list@li@a<js>[]</js>",
                                        "chapterName": "text", "chapterUrl": "href"]))
        let html = "<ul class='chapter-list'><li><a href='/read/1'>Not selected</a></li></ul>"
        let response = SourceResponse(url: tocURL, statusCode: 200, headers: ["Content-Type": "text/html"],
                                      body: html, data: Data(html.utf8))

        XCTAssertThrowsError(try ChapterListParser().parse(source: source,
            book: makeBook(tocURL: tocURL.absoluteString), response: response).get()) { error in
            guard let sourceError = error as? SourceEngineError, case .empty = sourceError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testSelectOptionTOCUsesValueAttributeForChapterURL() async throws {
        let tocURL = "https://fixture.example/book/select-option/toc"
        let source = BookSource(
            bookSourceName: "select option fixture",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "chapterList": "option"
            ])
        )
        let network = ChapterFixtureNetworkClient(responses: [
            tocURL: """
                <html><body>
                  <select id="catalog">
                    <option value="/novel_1.html">第一章 陨落的天才</option>
                    <option value="/novel_2.html">第二章 斗气大陆</option>
                  </select>
                </body></html>
                """
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))

        XCTAssertEqual(chapters.map(\.title), ["第一章 陨落的天才", "第二章 斗气大陆"])
        XCTAssertEqual(chapters.map(\.url), [
            "https://fixture.example/novel_1.html",
            "https://fixture.example/novel_2.html"
        ])
    }

    func testJSONVolumeRowsSupportBooleanAndStringFlags() async throws {
        let tocURL = "https://fixture.example/book/json-volume/toc"
        let source = BookSource(
            bookSourceName: "JSON volume fixture",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "chapterList": "$.chapters[*]",
                "chapterName": "$.title",
                "chapterUrl": "$.url",
                "isVolume": "$.isVolume"
            ])
        )
        let network = ChapterFixtureNetworkClient(responses: [
            tocURL: #"""
                {"chapters":[
                  {"title":"第一卷","isVolume":true},
                  {"title":"第一章","url":"/chapter/1"},
                  {"title":"第二卷","isVolume":"true"},
                  {"title":"第二章","url":"/chapter/2"}
                ]}
                """#
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))

        XCTAssertEqual(chapters.map(\.title), ["第一章", "第二章"])
        XCTAssertEqual(chapters.map(\.volumeName), ["第一卷", "第二卷"])
        XCTAssertEqual(chapters.map(\.index), [0, 1])
    }

    func testBlankVolumeRuleDoesNotDiscardOrdinaryJSONChapters() async throws {
        let tocURL = "https://fixture.example/book/blank-volume/toc"
        let network = ChapterFixtureNetworkClient(responses: [
            tocURL: #"""
                {"chapters":[
                  {"title":"第一章","url":"/chapter/1","vip":false},
                  {"title":"第二章","url":"/chapter/2","vip":true}
                ]}
                """#
        ])
        let engine = LegadoSourceEngine(network: network)
        for blankRule in ["", " \t\n"] {
            let source = BookSource(bookSourceName: "Blank volume fixture", bookSourceUrl: "https://fixture.example",
                ruleToc: SourceRule(fields: ["chapterList": "$.chapters[*]", "chapterName": "$.title",
                    "chapterUrl": "$.url", "isVolume": blankRule, "isVip": "$.vip"]))
            let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))
            XCTAssertEqual(chapters.map(\.title), ["第一章", "第二章"])
            XCTAssertEqual(chapters.map(\.url), [
                "https://fixture.example/chapter/1", "https://fixture.example/chapter/2"
            ])
            XCTAssertEqual(chapters.map(\.volumeName), [nil, nil])
            XCTAssertEqual(chapters.map(\.isVip), [false, true])
        }
    }

    func testLargeScriptedDirectoryPreservesAllChaptersAndTheirIndependentMetadata() async throws {
        let tocURL = "https://fixture.example/book/long-scripted/toc"
        let chapterCount = 1_396
        let rawChapters = (1...chapterCount).map { ["idx": $0, "title": "章节 \($0)"] as [String: Any] }
        let response = try JSONSerialization.data(withJSONObject: ["chapters": rawChapters])
        let library = """
        const libraryOrigin = 'https://fixture.example';
        function chapterLink(row) { return libraryOrigin + '/chapter/' + row.idx; }
        function chapterMarker(row) { return '已更新 ' + row.idx; }
        """ + "\n/*" + String(repeating: "fixture ", count: 5_000) + "*/"
        let source = BookSource(bookSourceName: "Large directory fixture", bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: ["chapterList": "$.chapters[*]", "chapterName": "$.title",
                "chapterUrl": "@js:chapterLink(result)", "updateTime": "@js:chapterMarker(result)", "isVolume": ""]),
            raw: ["jsLib": library])
        let client = ChapterFixtureNetworkClient(responses: [tocURL: String(decoding: response, as: UTF8.self)])
        let chapters = try await unwrap(LegadoSourceEngine(network: client).getChapterList(source: source,
            book: makeBook(tocURL: tocURL)))
        XCTAssertEqual(chapters.count, chapterCount)
        XCTAssertEqual(Set(chapters.map(\.url)).count, chapterCount)
        XCTAssertEqual(chapters.first?.url, "https://fixture.example/chapter/1")
        XCTAssertEqual(chapters.last?.title, "章节 \(chapterCount)")
        XCTAssertEqual(chapters.last?.updateTime, "已更新 \(chapterCount)")
        XCTAssertEqual(client.requestedURLs, [tocURL])
    }

    func testAggregateDirectoryWith807ScriptedRowsFitsTheExistingStageDeadline() async throws {
        let tocURL = "https://fixture.example/book/aggregate-807/toc"
        let rawChapters = (1...807).map { ["idx": $0, "title": "章节 \($0)", "note": String(repeating: "fixture ", count: 24)] as [String: Any] }
        let response = try JSONSerialization.data(withJSONObject: ["data": rawChapters])
        let source = BookSource(bookSourceName: "Aggregate directory fixture", bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "chapterList": "@js:JSON.parse(result).data", "chapterName": "@js:rowTitle(result)",
                "chapterUrl": "@js:rowLink(result)", "updateTime": "@js:rowMarker(result)", "isVolume": ""
            ]), raw: ["jsLib": """
                var libraryInitializations = (typeof libraryInitializations === 'undefined' ? 0 : libraryInitializations) + 1;
                function rowTitle(row) { return row.title; }
                function rowLink(row) { return source.getUrl() + '/chapter/' + row.idx; }
                function rowMarker(row) { return libraryInitializations + ':' + row.idx; }
                """ + "\n/*" + String(repeating: "fixture ", count: 5_000) + "*/"])
        let client = ChapterFixtureNetworkClient(responses: [tocURL: String(decoding: response, as: UTF8.self)])
        let started = ProcessInfo.processInfo.systemUptime
        let chapters = try await unwrap(LegadoSourceEngine(network: client).getChapterList(source: source,
            book: makeBook(tocURL: tocURL)))
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        XCTAssertEqual(chapters.count, 807)
        XCTAssertEqual(chapters.map(\.title), (1...807).map { "章节 \($0)" })
        XCTAssertEqual(chapters.map(\.url), (1...807).map { "https://fixture.example/chapter/\($0)" })
        XCTAssertEqual(chapters.map(\.updateTime), (1...807).map { "1:\($0)" })
        XCTAssertEqual(client.requestedURLs, [tocURL])
        // The private source probe already limits each TOC attempt to 15 seconds.
        XCTAssertLessThan(elapsed, 15, "Offline aggregate TOC must not exhaust the existing live-stage deadline")
    }

    func testFormatJsRunsAfterPaginationWithOneBasedIndex() async throws {
        let tocURL = "https://fixture.example/book/format-js/toc"
        let source = BookSource(
            bookSourceName: "formatJs fixture",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "chapterList": "div.catalog a",
                "chapterName": "a@text",
                "chapterUrl": "a@href",
                "formatJs": "title + '（' + index + '）'"
            ])
        )
        let network = ChapterFixtureNetworkClient(responses: [
            tocURL: """
                <html><body><div class="catalog">
                  <a href="/chapter/1">第一章</a>
                  <a href="/chapter/2">第二章</a>
                </div></body></html>
                """
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))

        XCTAssertEqual(chapters.map(\.title), ["第一章（1）", "第二章（2）"])
        XCTAssertEqual(chapters.map(\.index), [0, 1])
    }

    func testPaginationPreservesUpdateTimeAndVolumeName() async throws {
        let tocURL = "https://fixture.example/book/paged/toc"
        let page2URL = "https://fixture.example/book/paged/toc?page=2"
        let source = BookSource(
            bookSourceName: "Paged metadata fixture",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "chapterList": "div.catalog a.chapter",
                "chapterName": "a@text",
                "chapterUrl": "a@href",
                "updateTime": "a@data-update",
                "volumeName": "a@data-volume",
                "nextTocUrl": "a.next@href"
            ])
        )
        let network = ChapterFixtureNetworkClient(responses: [
            tocURL: """
                <html><body>
                  <div class="catalog">
                    <a class="chapter" href="/chapter/1" data-update="2026-01-01" data-volume="第一卷">第一章</a>
                  </div>
                  <a class="next" href="\(page2URL)">下一页</a>
                </body></html>
                """,
            page2URL: """
                <html><body>
                  <div class="catalog">
                    <a class="chapter" href="/chapter/2" data-update="2026-01-02" data-volume="第二卷">第二章</a>
                  </div>
                </body></html>
                """
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))

        XCTAssertEqual(chapters.map(\.title), ["第一章", "第二章"])
        XCTAssertEqual(chapters.map(\.updateTime), ["2026-01-01", "2026-01-02"])
        XCTAssertEqual(chapters.map(\.volumeName), ["第一卷", "第二卷"])
        XCTAssertEqual(chapters.map(\.index), [0, 1])
        XCTAssertEqual(network.requestedURLs, [tocURL, page2URL])
    }

    func testVolumeHeaderOnlyChangesAtBoundaries() {
        let chapters = [
            BookChapter(title: "一", url: "u1", bookUrl: "b", index: 0, volumeName: "A"),
            BookChapter(title: "二", url: "u2", bookUrl: "b", index: 1, volumeName: "A"),
            BookChapter(title: "三", url: "u3", bookUrl: "b", index: 2, volumeName: "B"),
            BookChapter(title: "四", url: "u4", bookUrl: "b", index: 3, volumeName: nil)
        ]

        XCTAssertEqual(ChapterListPresenter.volumeHeader(at: 0, in: chapters), "A")
        XCTAssertNil(ChapterListPresenter.volumeHeader(at: 1, in: chapters))
        XCTAssertEqual(ChapterListPresenter.volumeHeader(at: 2, in: chapters), "B")
        XCTAssertNil(ChapterListPresenter.volumeHeader(at: 3, in: chapters))
    }

    func testPreUpdateJsRunsBeforeTocRequestAndSharesState() async throws {
        let tocURL = "https://fixture.example/book/pre-update/toc"
        let bootstrapURL = "https://fixture.example/api/toc-token"
        let source = BookSource(
            bookSourceName: "preUpdateJs fixture",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "preUpdateJs": "var payload = JSON.parse(java.ajax('" + bootstrapURL + "')); java.put('tocPath', payload.path)",
                "chapterList": "$.@get:tocPath[*]",
                "chapterName": "$.title",
                "chapterUrl": "$.url"
            ])
        )
        let network = ChapterFixtureNetworkClient(responses: [
            bootstrapURL: #"{"path":"chapters"}"#,
            tocURL: #"{"chapters":[{"title":"第一章","url":"/chapter/1"}]}"#
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))

        XCTAssertEqual(chapters.map(\.title), ["第一章"])
        XCTAssertEqual(network.requestedURLs, [bootstrapURL, tocURL])
    }

    func testPaginationInheritsVolumeFromPreviousPage() async throws {
        let tocURL = "https://fixture.example/book/paged-volume/toc"
        let page2URL = "https://fixture.example/book/paged-volume/toc?page=2"
        let source = BookSource(
            bookSourceName: "Paged volume fixture",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "chapterList": "div.catalog h3, div.catalog a",
                "chapterName": "h3.volume@text||a@text",
                "chapterUrl": "a@href",
                "isVolume": "h3.volume@text",
                "nextTocUrl": "a.next@href"
            ])
        )
        let network = ChapterFixtureNetworkClient(responses: [
            tocURL: """
                <html><body>
                  <div class="catalog">
                    <h3 class="volume">第一卷</h3>
                    <a href="/chapter/1">第一章</a>
                    <h3 class="volume">第二卷</h3>
                  </div>
                  <a class="next" href="\(page2URL)">下一页</a>
                </body></html>
                """,
            page2URL: """
                <html><body>
                  <div class="catalog">
                    <a href="/chapter/2">第二章</a>
                  </div>
                </body></html>
                """
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))

        XCTAssertEqual(chapters.map(\.title), ["第一章", "第二章"])
        XCTAssertEqual(chapters.map(\.volumeName), ["第一卷", "第二卷"])
        XCTAssertEqual(chapters.map(\.index), [0, 1])
        XCTAssertEqual(network.requestedURLs, [tocURL, page2URL])
    }

    func testHTMLFallbackRulesConsumeVolumeRowsAndInheritVolume() async throws {
        let tocURL = "https://fixture.example/book/html-fallback-volume/toc"
        let source = BookSource(
            bookSourceName: "HTML fallback volume fixture",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "chapterList": "div.catalog h3, div.catalog a",
                "chapterName": "span@text",
                "chapterUrl": "span@data-href",
                "isVolume": "h3.volume@text"
            ])
        )
        let network = ChapterFixtureNetworkClient(responses: [
            tocURL: """
                <html><body>
                  <div class="catalog">
                    <h3 class="volume">第一卷</h3>
                    <a href="/chapter/1">第一章</a>
                  </div>
                </body></html>
                """
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))

        XCTAssertEqual(chapters.map(\.title), ["第一章"])
        XCTAssertEqual(chapters.map(\.volumeName), ["第一卷"])
        XCTAssertEqual(chapters.map(\.index), [0])
    }

    func testReverseTocFlagReversesCollectedChapterList() async throws {
        let tocURL = "https://fixture.example/book/reversed/toc"
        let source = BookSource(
            bookSourceName: "reverseToc fixture",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "preUpdateJs": "book.setReverseToc(true)",
                "chapterList": "div.catalog a",
                "chapterName": "a@text",
                "chapterUrl": "a@href"
            ])
        )
        let network = ChapterFixtureNetworkClient(responses: [
            tocURL: """
                <html><body><div class="catalog">
                  <a href="/chapter/3">第三章</a>
                  <a href="/chapter/2">第二章</a>
                  <a href="/chapter/1">第一章</a>
                </div></body></html>
                """
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))

        XCTAssertEqual(chapters.map(\.title), ["第一章", "第二章", "第三章"])
        XCTAssertEqual(chapters.map(\.index), [0, 1, 2])
    }

    func testReverseTocFlagStaysOffWhenSourceDoesNotRequestIt() async throws {
        let tocURL = "https://fixture.example/book/not-reversed/toc"
        let source = BookSource(
            bookSourceName: "no reverseToc fixture",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "preUpdateJs": "book.setReverseToc(false)",
                "chapterList": "div.catalog a",
                "chapterName": "a@text",
                "chapterUrl": "a@href"
            ])
        )
        let network = ChapterFixtureNetworkClient(responses: [
            tocURL: """
                <html><body><div class="catalog">
                  <a href="/chapter/1">第一章</a>
                  <a href="/chapter/2">第二章</a>
                </div></body></html>
                """
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))

        XCTAssertEqual(chapters.map(\.title), ["第一章", "第二章"])
        XCTAssertEqual(chapters.map(\.index), [0, 1])
    }

    func testHTMLChapterWordCountIsParsedAndPreserved() async throws {
        let tocURL = "https://fixture.example/book/html-word-count/toc"
        let source = BookSource(
            bookSourceName: "HTML wordCount fixture",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "chapterList": "div.catalog a",
                "chapterName": "a@text",
                "chapterUrl": "a@href",
                "wordCount": "a@data-words"
            ])
        )
        let network = ChapterFixtureNetworkClient(responses: [
            tocURL: """
                <html><body><div class="catalog">
                  <a href="/chapter/1" data-words="3200字">第一章</a>
                  <a href="/chapter/2" data-words=" 4100字 ">第二章</a>
                  <a href="/chapter/3">第三章</a>
                </div></body></html>
                """
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))

        XCTAssertEqual(chapters.map(\.wordCount), ["3200字", "4100字", nil])
        XCTAssertEqual(ChapterListPresenter.wordCountLabel(chapters[0]), "3200字")
        XCTAssertEqual(ChapterListPresenter.metadataLabel(chapters[0]), "3200字")
    }

    func testJSONChapterWordCountSupportsNumberStringAndFallbackKeys() async throws {
        let tocURL = "https://fixture.example/book/json-word-count/toc"
        let source = BookSource(
            bookSourceName: "JSON wordCount fixture",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "chapterList": "$.chapters[*]",
                "chapterName": "$.title",
                "chapterUrl": "$.url"
            ])
        )
        let network = ChapterFixtureNetworkClient(responses: [
            tocURL: #"""
                {"chapters":[
                  {"title":"第一章","url":"/chapter/1","wordCount":3200},
                  {"title":"第二章","url":"/chapter/2","wordNum":"1.2万字"},
                  {"title":"第三章","url":"/chapter/3","words":"  800字  "}
                ]}
                """#
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))

        XCTAssertEqual(chapters.map(\.wordCount), ["3200", "1.2万字", "800字"])
    }

    func testBookChapterDecodesLegacyCacheWithoutWordCount() throws {
        let legacy = #"""
            {"title":"第一章","url":"https://fixture.example/1","bookUrl":"https://fixture.example/book","index":0,"isVip":false}
            """#
        let chapter = try JSONDecoder().decode(BookChapter.self, from: Data(legacy.utf8))
        XCTAssertNil(chapter.wordCount)
        XCTAssertNil(chapter.updateTime)
        XCTAssertNil(chapter.volumeName)
    }

    func testHTMLChapterIsPayIsParsedSeparatelyFromIsVip() async throws {
        let tocURL = "https://fixture.example/book/html-pay/toc"
        let source = BookSource(
            bookSourceName: "HTML isPay fixture",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "chapterList": "div.catalog a",
                "chapterName": "a@text",
                "chapterUrl": "a@href",
                "isVip": "a@data-vip",
                "isPay": "a@data-pay"
            ])
        )
        let network = ChapterFixtureNetworkClient(responses: [
            tocURL: """
                <html><body><div class="catalog">
                  <a href="/chapter/1" data-vip="true" data-pay="false">第一章</a>
                  <a href="/chapter/2" data-vip="true" data-pay="true">第二章</a>
                  <a href="/chapter/3" data-vip="false">第三章</a>
                </div></body></html>
                """
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))

        XCTAssertEqual(chapters.map(\.isVip), [true, true, false])
        XCTAssertEqual(chapters.map(\.isPay), [false, true, nil])
    }

    func testJSONChapterIsPaySupportsBooleanStringAndMissingValue() async throws {
        let tocURL = "https://fixture.example/book/json-pay/toc"
        let source = BookSource(
            bookSourceName: "JSON isPay fixture",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "chapterList": "$.chapters[*]",
                "chapterName": "$.title",
                "chapterUrl": "$.url",
                "isVip": "$.isVip",
                "isPay": "$.isPay"
            ])
        )
        let network = ChapterFixtureNetworkClient(responses: [
            tocURL: #"""
                {"chapters":[
                  {"title":"第一章","url":"/chapter/1","isVip":true,"isPay":false},
                  {"title":"第二章","url":"/chapter/2","isVip":true,"isPay":"true"},
                  {"title":"第三章","url":"/chapter/3","isVip":false}
                ]}
                """#
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))

        XCTAssertEqual(chapters.map(\.isVip), [true, true, false])
        XCTAssertEqual(chapters.map(\.isPay), [false, true, nil])
    }

    func testBookChapterDecodesLegacyCacheWithoutIsPay() throws {
        let legacy = #"""
            {"title":"第一章","url":"https://fixture.example/1","bookUrl":"https://fixture.example/book","index":0,"isVip":true}
            """#
        let chapter = try JSONDecoder().decode(BookChapter.self, from: Data(legacy.utf8))
        XCTAssertTrue(chapter.isVip)
        XCTAssertNil(chapter.isPay)

        let paid = BookChapter(
            title: "第二章",
            url: "https://fixture.example/2",
            bookUrl: "https://fixture.example/book",
            index: 1,
            isVip: true,
            isPay: true
        )
        let roundTrip = try JSONDecoder().decode(BookChapter.self, from: JSONEncoder().encode(paid))
        XCTAssertEqual(roundTrip.isPay, true)
        XCTAssertEqual(roundTrip.withIndex(5).isPay, true)
        XCTAssertEqual(roundTrip.withTitle("新标题").isPay, true)
    }

    private func makeBook(tocURL: String) -> BookDetail {
        BookDetail(
            name: "Fixture Book",
            author: "Fixture Author",
            coverUrl: nil,
            bookUrl: "https://fixture.example/book/fixture",
            tocUrl: tocURL,
            sourceName: "Fixture",
            sourceUrl: "https://fixture.example",
            intro: nil,
            latestChapter: nil
        )
    }

    private func unwrap<T>(_ result: Result<T, SourceEngineError>, file: StaticString = #filePath, line: UInt = #line) throws -> T {
        switch result {
        case .success(let value): return value
        case .failure(let error):
            XCTFail("source pipeline failed: \(error)", file: file, line: line)
            throw error
        }
    }
}

private final class ChapterFixtureNetworkClient: SourceNetworkClient, @unchecked Sendable {
    private let responses: [String: String]
    private let lock = NSLock()
    private var recordedURLs: [String] = []

    init(responses: [String: String]) {
        self.responses = responses
    }

    var requestedURLs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedURLs
    }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        lock.lock()
        recordedURLs.append(request.url.absoluteString)
        lock.unlock()
        guard let body = responses[request.url.absoluteString] else {
            return .failure(.network("fixture response missing for \(request.url.absoluteString)"))
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let contentType = trimmed.first == "{" || trimmed.first == "[" ? "application/json" : "text/html"
        return .success(SourceResponse(
            url: request.url,
            statusCode: 200,
            headers: ["Content-Type": contentType],
            body: body,
            data: Data(body.utf8)
        ))
    }
}
