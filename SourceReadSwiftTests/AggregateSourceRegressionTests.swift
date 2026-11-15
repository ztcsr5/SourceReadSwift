import XCTest
@testable import SourceReadSwift

final class AggregateSourceRegressionTests: XCTestCase {
    func testPublisherUTCFormattingUsesPatternAndRawMillisecondOffset() throws {
        let rendered = try JSCoreRuntime().evaluate("""
        JSON.stringify([
          java.timeFormatUTC(86400000, 'yyyy-MM-dd HH:mm', 28800000),
          timeFormatUTC(86400000, 'yyyy-MM-dd HH:mm Z', -18000000),
          java.timeFormatUTC(86400000, 'yyyy-MM-dd HH:mm', 0),
          java.timeFormatUTC(0), java.timeFormatUTC(NaN, 'yyyy-MM-dd', 0)
        ])
        """).get()
        let values = try JSONDecoder().decode([String].self, from: Data(rendered.utf8))
        XCTAssertEqual(values, ["1970-01-02 08:00", "1970-01-01 19:00 -0500", "1970-01-02 00:00",
                                "1970-01-01 00:00:00", ""])
    }

    func testMediaFilteringAndAggregationKeepNovelAndComicSeparate() {
        let novel = SearchBook(name: "同名作品", author: "林川", coverUrl: nil, bookUrl: "https://example.invalid/novel",
            sourceName: "Aggregate", sourceUrl: "https://example.invalid", mediaKind: .text)
        let comic = SearchBook(name: novel.name, author: novel.author, coverUrl: nil, bookUrl: "https://example.invalid/comic",
            sourceName: novel.sourceName, sourceUrl: novel.sourceUrl, mediaKind: .comic)
        let kinds: [String: BookSourceKind] = [novel.sourceUrl: .text]
        let all = DiscoverViewModel.makeProjection([novel, comic], kinds: kinds, kind: nil, query: "", scope: .all)
        XCTAssertEqual(all.aggregated.count, 2)
        XCTAssertEqual(Set(all.aggregated.map(\.id)).count, 2)
        let comics = DiscoverViewModel.makeProjection([novel, comic], kinds: kinds, kind: .comic, query: "", scope: .all)
        XCTAssertEqual(comics.results, [comic])
    }

    @MainActor
    func testAggregatedEditionKeepsBothSourcesAndPrefersTheCopyAlreadyOnTheShelf() throws {
        let plain = SearchBook(name: "长舟", author: "许岸", coverUrl: nil, bookUrl: "https://plain.invalid/work",
                               sourceName: "Plain", sourceUrl: "https://plain.invalid")
        let covered = SearchBook(name: "《长舟》【全本】", author: "作者：许岸", coverUrl: "cover.jpg",
            bookUrl: "https://covered.invalid/novel/work", sourceName: "Covered", sourceUrl: "https://covered.invalid")
        let all = DiscoverViewModel.makeProjection([plain, covered], kinds: [:], kind: nil, query: "", scope: .all)
        XCTAssertEqual(all.aggregated.count, 1)
        let edition = try XCTUnwrap(all.aggregated.first)
        XCTAssertEqual(edition.sourceCount, 2)
        XCTAssertEqual(edition.sources, [plain, covered])
        XCTAssertEqual(edition.coverProvider?.bookUrl, covered.bookUrl, "Resolve relative cover URLs against their own provider")
        let shelf = DiscoverView.BookshelfMembership(books: [BookshelfBook(searchBook: covered)])
        XCTAssertEqual(shelf.preferredBook(for: edition), covered)
        XCTAssertEqual(DiscoverSearchAggregation.group([covered, plain], kinds: [:]).first?.id, edition.id)
    }

    func testUnverifiedAuthorsAndIdenticalTitlesFromDifferentAuthorsStaySeparate() {
        let known = SearchBook(name: "长舟", author: "许岸", coverUrl: nil, bookUrl: "https://a.invalid/1",
                               sourceName: "First", sourceUrl: "https://a.invalid")
        let anotherAuthor = SearchBook(name: "长舟", author: "陈平", coverUrl: nil, bookUrl: "https://a.invalid/2",
                                       sourceName: "First", sourceUrl: "https://a.invalid")
        let unknown = SearchBook(name: "长舟", author: "作者未知", coverUrl: nil, bookUrl: "https://b.invalid/1",
                                 sourceName: "Second", sourceUrl: "https://b.invalid")
        let noAuthor = SearchBook(name: "长舟", author: nil, coverUrl: nil, bookUrl: "https://c.invalid/1",
                                  sourceName: "Third", sourceUrl: "https://c.invalid")
        let bareLabel = SearchBook(name: "长舟", author: "作者", coverUrl: nil, bookUrl: "https://d.invalid/1",
                                   sourceName: "Fourth", sourceUrl: "https://d.invalid")
        let anotherBareLabel = SearchBook(name: "长舟", author: "作者", coverUrl: nil, bookUrl: "https://e.invalid/1",
                                          sourceName: "Fifth", sourceUrl: "https://e.invalid")
        XCTAssertEqual(DiscoverSearchAggregation.group([known, anotherAuthor, unknown, noAuthor, bareLabel, anotherBareLabel],
                                                       kinds: [:]).count, 6)
    }

    func testAuthorLabelsDoNotStripCharactersFromAnActualPenName() {
        let penName = SearchBook(name: "长舟", author: "作者说", coverUrl: nil, bookUrl: "https://a.invalid/3",
                                 sourceName: "First", sourceUrl: "https://a.invalid")
        let credited = SearchBook(name: "长舟", author: "作者：作者说 著", coverUrl: nil, bookUrl: "https://b.invalid/3",
                                  sourceName: "Second", sourceUrl: "https://b.invalid")
        let otherName = SearchBook(name: "长舟", author: "说", coverUrl: nil, bookUrl: "https://c.invalid/3",
                                   sourceName: "Third", sourceUrl: "https://c.invalid")
        let works = DiscoverSearchAggregation.group([penName, credited, otherName], kinds: [:])
        XCTAssertEqual(works.map(\.sources), [[penName, credited], [otherName]])
    }

    func testDynamicBookTypeSourcesAreIncludedForMediaSearch() {
        let mixed = BookSource(bookSourceName: "Mixed", bookSourceUrl: "https://example.invalid",
            ruleSearch: SourceRule(fields: ["bookUrl": "@js:book.type = 64; '/comic';"]))
        XCTAssertTrue(mixed.canSearch(mediaKind: .comic))
        let text = BookSource(bookSourceName: "Text", bookSourceUrl: "https://example.invalid/text")
        XCTAssertFalse(text.canSearch(mediaKind: .comic))
    }

    func testDiscoveryKeepsActionsAndInputsSeparateFromCategories() {
        let menu = SourceExploreMenuParser.parse("""
        [{"title":"当前模式：小说","type":"button"},
         {"title":"漫画","type":"button","action":"source.setVariable('comic')"},
         {"title":"关键字","type":"text","default":"三国"},
         {"title":"搜索","type":"button","action":"java.searchBook(infoMap['关键字'],source)"},
         {"title":"全部漫画","url":"/comic/{{page}}"}]
        """)
        XCTAssertEqual(menu.categories.map(\.title), ["全部漫画"])
        XCTAssertNil(menu.categories.first?.group, "Action labels must not become category groups")
        XCTAssertEqual(menu.controls.map(\.title), ["漫画", "关键字", "搜索"])
        XCTAssertEqual(menu.controls[1].defaultValue, "三国")
    }

    func testJavaScriptWithDoubleColonTextIsEvaluatedBeforeParsing() throws {
        let source = BookSource(bookSourceName: "Aggregate", bookSourceUrl: "https://example.invalid",
            exploreUrl: "@js:var label='分类::标题'; JSON.stringify([{title:label,url:'/list'}]);")
        let categories = ExploreCategoryParser.parse(exploreUrl: source.exploreUrl, source: source)
        XCTAssertEqual(categories.map(\.title), ["分类::标题"])
        XCTAssertEqual(categories.map(\.url), ["/list"])
    }

    func testDiscoveryActionAndSearchShareSourceVariableWithoutChangingItsFormat() async throws {
        let source = BookSource(bookSourceName: "Aggregate", bookSourceUrl: "https://example.invalid",
            searchUrl: "@js:'https://example.invalid/search?mode='+JSON.parse(source.getVariable()).mode+'&q={{key}}';",
            exploreUrl: "@js:var mode=JSON.parse(source.getVariable()||'{\"mode\":\"novel\"}').mode; JSON.stringify([{title:mode,url:'/list/'+mode}]);")
        let engine = LegadoSourceEngine()
        let initial = try await engine.exploreMenu(source: source).get()
        XCTAssertEqual(initial.categories.first?.title, "novel")
        let outcome = try await engine.performExploreAction(source: source,
            action: "source.setVariable(JSON.stringify({mode:'comic'}));java.refreshExplore();java.searchBook(infoMap['关键字'],source);",
            inputs: ["关键字": "三国"]).get()
        XCTAssertEqual(outcome.menu.categories.first?.url, "/list/comic")
        XCTAssertEqual(outcome.searchKeyword, "三国")
        let persisted = engine.persistentState(for: source)
        XCTAssertEqual(persisted.get("source.variable"), "{\"mode\":\"comic\"}")
        let url = try SearchURLResolver().resolve(source: source, keyword: "三国", page: 1, persistentState: persisted).get()
        XCTAssertTrue(url.contains("mode=comic"))
        XCTAssertFalse(url.contains("{{"))
        let other = BookSource(bookSourceName: "Other", bookSourceUrl: "https://other.invalid")
        XCTAssertTrue(engine.persistentState(for: other).get("source.variable").isEmpty)
    }

    func testSearchRowsKeepTheirOwnDynamicBookType() throws {
        let source = BookSource(bookSourceName: "Aggregate", bookSourceUrl: "https://example.invalid",
            ruleSearch: SourceRule(fields: ["bookList": "li", "name": "a@text",
                "bookUrl": "a@href@js:book.type=result.indexOf('comic')>=0?64:8;result"]))
        let books = try SearchResultParser().parse(source: source,
            response: response("<ul><li><a href='/comic/1'>漫画</a></li><li><a href='/novel/2'>小说</a></li></ul>")).get()
        XCTAssertEqual(books.map(\.mediaKind), [.comic, .text])
        XCTAssertEqual(books.count, 2)
    }

    func testJSONSearchAlsoRetainsDynamicTypeAndDoesNotLeakBetweenRows() throws {
        let source = BookSource(bookSourceName: "Aggregate", bookSourceUrl: "https://example.invalid",
            ruleSearch: SourceRule(fields: ["bookList": "$.items[*]", "name": "$.title",
                "bookUrl": "@js:book.type=result.media;'/book/'+result.id"]))
        let books = try SearchResultParser().parse(source: source,
            response: response(#"{"items":[{"id":1,"title":"漫画","media":64},{"id":2,"title":"听书","media":32}]}"#)).get()
        XCTAssertEqual(books.map(\.mediaKind), [.comic, .audio])
    }

    func testDetailBookTypeAndFullIntroductionSurviveParsing() throws {
        let source = BookSource(bookSourceName: "Aggregate", bookSourceUrl: "https://example.invalid",
            ruleBookInfo: SourceRule(fields: ["name": "h1@text", "intro": ".brief@html",
                "lastChapter": "@js:book.type=64;'第二话'"]))
        let book = SearchBook(name: "画册", author: nil, coverUrl: nil, bookUrl: "https://example.invalid/book/1",
            sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl)
        let intro = "第一段。<br>" + String(repeating: "完整简介不能截断。", count: 100)
        let detail = try BookDetailParser().parse(source: source, book: book,
            response: response("<h1>画册</h1><div class='brief'>\(intro)</div>")).get()
        XCTAssertEqual(detail.mediaKind, .comic)
        XCTAssertTrue(detail.intro?.hasSuffix("完整简介不能截断。") == true)
        XCTAssertGreaterThan(detail.intro?.count ?? 0, 900)
    }

    func testComicContentReceivesBookIdentityAndTypeAfterRestart() throws {
        let source = BookSource(bookSourceName: "Aggregate", bookSourceUrl: "https://example.invalid",
            ruleContent: SourceRule(fields: ["content": "@js:book.type===64&&book.bookUrl.indexOf('/book/1')>=0?'<img src=\"/page.png\">':''"]))
        let chapter = BookChapter(title: "第一话", url: "https://example.invalid/play/1", bookUrl: "https://example.invalid/book/1", index: 0)
        let content = try ContentParser().parse(source: source.resolvingMediaKind(.comic), chapter: chapter,
            response: response("<html><body>chapter shell</body></html>"), globalPurifyRules: []).get()
        XCTAssertEqual(ComicContentParser.parsePages(from: content).first?.url, "https://example.invalid/page.png")
        XCTAssertEqual(source.sourceKind, .text, "Reading one comic must not reclassify the entire aggregate source")
    }

    func testOptionalMediaKindSurvivesShelfEncodingAndLegacySearchDecoding() throws {
        let legacy = #"{"name":"旧书","bookUrl":"https://example.invalid/book/1","sourceName":"Aggregate","sourceUrl":"https://example.invalid"}"#
        let old = try JSONDecoder().decode(SearchBook.self, from: Data(legacy.utf8))
        XCTAssertNil(old.mediaKind)
        let comic = SearchBook(name: old.name, author: nil, coverUrl: nil, bookUrl: old.bookUrl,
            sourceName: old.sourceName, sourceUrl: old.sourceUrl, mediaKind: .comic)
        let shelf = BookshelfBook(searchBook: comic)
        let restored = try JSONDecoder().decode(BookshelfBook.self, from: JSONEncoder().encode(shelf))
        XCTAssertEqual(restored.asSearchBook.mediaKind, .comic)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(shelf)) as? [String: Any])
        object.removeValue(forKey: "mediaKind")
        XCTAssertNil(try JSONDecoder().decode(BookshelfBook.self,
            from: JSONSerialization.data(withJSONObject: object)).mediaKind)
    }

    func testDiscoveryCategoryRunsItsURLScriptBeforeRequestAndBindsItsPage() async throws {
        let source = BookSource(bookSourceName: "Fixture aggregate", bookSourceUrl: "Fixture aggregate",
            exploreUrl: #"@js:[{title:'Rank',url:'@js:categoryAddress(page)'}]"#,
            ruleExplore: SourceRule(fields: [
                "bookList": "@js:if (page !== 3) throw new Error('Missing category page'); result.items;",
                "name": "$.title", "bookUrl": "$.url"
            ]),
            raw: ["jsLib": #"""
            function categoryAddress(page) {
                return 'https://aggregate.invalid/rank?cursor={{cursorFor(page)}},' +
                    '{"method":"POST","body":"p={{page}}","headers":{"X-Category":"rank"}}';
            }
            function cursorFor(page) { return 'cursor-' + (page - 1); }
            """#])
        let transport = AggregateEntryNetwork { request in
            guard request.url.absoluteString == "https://aggregate.invalid/rank?cursor=cursor-2",
                  request.method == .post,
                  request.body == Data("p=3".utf8),
                  request.headers["X-Category"] == "rank" else {
                return .failure(.rule("Category request address, options or page were incorrect"))
            }
            return Self.entryResponse(request.url, title: "Ranked book")
        }
        let engine = LegadoSourceEngine(network: transport)
        engine.allowWebViewFallback = false
        let menu = try await engine.exploreMenu(source: source).get()
        let category = try XCTUnwrap(menu.categories.first)
        let matches = try await engine.exploreBooks(source: source, url: category.url, page: 3).get()
        XCTAssertEqual(matches.map(\.name), ["Ranked book"])
        let calls = await transport.callCount
        XCTAssertEqual(calls, 1)
    }

    func testSearchWithPlainURLBindsKeywordAndPageBeforeLoadingJavaScriptLibrary() async throws {
        let source = BookSource(bookSourceName: "Fixture aggregate", bookSourceUrl: "https://aggregate.invalid",
            searchUrl: "/search?q={{key}}&p={{page}}",
            ruleSearch: SourceRule(fields: ["bookList": "@js:selectResults(result);",
                "name": "$.title", "bookUrl": "$.url"]),
            raw: ["jsLib": """
            const requestedPage = page;
            const requestedKeyword = key;
            function selectResults(result) {
                if (requestedPage !== 2 || requestedKeyword !== 'origin') throw new Error('Missing search inputs');
                return result.items;
            }
            """])
        let transport = AggregateEntryNetwork { request in
            guard request.url.absoluteString == "https://aggregate.invalid/search?q=origin&p=2" else {
                return .failure(.rule("Search address did not contain the original keyword and page"))
            }
            return Self.entryResponse(request.url, title: "origin archive")
        }
        let engine = LegadoSourceEngine(network: transport)
        let matches = try await engine.searchBooks(source: source, keyword: "origin", page: 2).get()
        XCTAssertEqual(matches.map(\.name), ["origin archive"])
    }

    func testSearchWithMissingScriptAddressDoesNotRequestSourceHomepage() async {
        let source = BookSource(bookSourceName: "Fixture aggregate", bookSourceUrl: "https://aggregate.invalid",
            searchUrl: "@js:undefined")
        let transport = AggregateEntryNetwork { _ in .failure(.network("Unexpected HTTP request")) }
        let result = await LegadoSourceEngine(network: transport).searchBooks(source: source, keyword: "origin", page: 1)
        guard case .failure(.invalidSource) = result else { return XCTFail("Expected a missing search address") }
        let calls = await transport.callCount
        XCTAssertEqual(calls, 0)
    }

    func testFailedNestedSearchRequestIsNotRetriedAsAnEmptyScript() async {
        let source = BookSource(bookSourceName: "Fixture aggregate", bookSourceUrl: "https://aggregate.invalid",
            searchUrl: """
            @js:
            function address() { return java.ajax('https://aggregate.invalid/catalog'); }
            var response = address();
            if (response.code === 0) throw new Error('No HTTP response');
            'https://aggregate.invalid/unexpected-second-request';
            """)
        let transport = AggregateEntryNetwork { _ in .failure(.network("Fixture network unavailable")) }
        let result = await LegadoSourceEngine(network: transport).searchBooks(source: source, keyword: "origin", page: 1)
        guard case .failure(.network) = result else { return XCTFail("Expected the nested request failure") }
        let calls = await transport.callCount
        XCTAssertEqual(calls, 1)
    }

    func testInlineAggregateSearchPassesItsEnvelopeToScriptBeforeJSONPath() async throws {
        let source = BookSource(bookSourceName: "Fixture aggregate", bookSourceUrl: "Fixture aggregate",
            searchUrl: #"""
            <js>'data:;base64,' + java.base64Encode(JSON.stringify({term: key, literal: '{{page}}'})) + ',{"type":"fixture"}';</js>
            """#,
            ruleSearch: SourceRule(fields: [
                "bookList": "<js>lookup(JSON.parse(java.hexDecodeToString(result)));</js>$.items[*]",
                "name": "$.title", "bookUrl": "$.url"
            ]),
            raw: ["jsLib": #"""
            function lookup(request) {
                if (request.literal !== '{' + '{page}' + '}') throw new Error('Envelope changed');
                var address = 'https://aggregate.invalid/search?q=' + encodeURIComponent(request.term);
                return java.ajax(address + ',' + JSON.stringify({method: 'GET', body: '{}'}));
            }
            """#])
        let transport = AggregateEntryNetwork { request in
            guard request.url.absoluteString == "https://aggregate.invalid/search?q=origin" else {
                return .failure(.rule("Nested request did not get the decoded keyword"))
            }
            guard request.method == .get, request.body == nil else {
                return .success(SourceResponse(url: request.url, statusCode: 405, headers: ["Allow": "GET"],
                    body: "", data: Data()))
            }
            return Self.entryResponse(request.url, title: "origin archive")
        }
        let engine = LegadoSourceEngine(network: transport)
        let results = try await engine.searchBooks(source: source, keyword: "origin", page: 2).get()
        XCTAssertEqual(results.map(\.name), ["origin archive"])
        let calls = await transport.callCount
        XCTAssertEqual(calls, 2)
    }

    func testSourceHeaderScriptIsNotMisparsedAsLiteralHTTPHeaders() {
        let source = BookSource(bookSourceName: "Fixture aggregate", bookSourceUrl: "https://aggregate.invalid",
            header: #"@js:({ 'Accept-Language': 'zh-CN' })"#)
        let request = SourceRequestBuilder().buildPageRequest(source: source,
            urlText: #"https://aggregate.invalid/rank,{"headers":{"X-Category":"rank"}}"#)
        XCTAssertNil(request.headers["@js"])
        XCTAssertEqual(request.headers["X-Category"], "rank")
    }

    func testScriptedEntriesShareTransportBudgetWithoutExtendingOrdinarySearch() {
        let plain = BookSource(bookSourceName: "Plain", bookSourceUrl: "https://aggregate.invalid",
            searchUrl: "/search?q={{key}}")
        let scripted = BookSource(bookSourceName: "Fixture aggregate", bookSourceUrl: "Fixture aggregate",
            searchUrl: "<js>'/search?q='+encodeURIComponent(key)</js>",
            exploreUrl: "@js:[{title:'Rank',url:'/rank/{{page}}'}]")
        let scriptList = BookSource(bookSourceName: "Script list", bookSourceUrl: "https://aggregate.invalid",
            searchUrl: "/search?q={{key}}", ruleSearch: SourceRule(fields: ["bookList": "<js>result</js>$.books"]))
        XCTAssertEqual(SourceListingBudget.search(for: plain), 10)
        XCTAssertEqual(SourceListingBudget.search(for: scripted), 20)
        XCTAssertEqual(SourceListingBudget.search(for: scriptList), 20)
        XCTAssertEqual(SourceListingBudget.explore(for: plain, url: "/rank/{{page}}"), 12)
        XCTAssertEqual(SourceListingBudget.explore(for: scripted, url: "/rank/{{page}}"), 20)
    }

    private static func entryResponse(_ url: URL, title: String) -> Result<SourceResponse, SourceEngineError> {
        let body = """
        {"items":[{"title":"\(title)","url":"https://aggregate.invalid/book/1"}]}
        """
        return .success(SourceResponse(url: url, statusCode: 200, headers: ["Content-Type": "application/json"],
            body: body, data: Data(body.utf8)))
    }

    private func response(_ body: String) -> SourceResponse {
        SourceResponse(url: URL(string: "https://example.invalid/search")!, statusCode: 200,
            headers: [:], body: body, data: Data(body.utf8))
    }
}

private actor AggregateEntryNetwork: SourceNetworkClient {
    private(set) var callCount = 0
    private let respond: @Sendable (SourceRequest) -> Result<SourceResponse, SourceEngineError>

    init(respond: @escaping @Sendable (SourceRequest) -> Result<SourceResponse, SourceEngineError>) {
        self.respond = respond
    }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        callCount += 1
        if request.url.scheme == "data" { return await URLSessionSourceNetworkClient().load(request) }
        return respond(request)
    }
}
