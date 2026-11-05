import XCTest
@testable import SourceReadSwift

final class AggregateSourceRegressionTests: XCTestCase {
    func testMediaFilteringAndAggregationKeepNovelAndComicSeparate() {
        let novel = SearchBook(name: "同名作品", author: "作者", coverUrl: nil, bookUrl: "https://example.invalid/novel",
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

    private func response(_ body: String) -> SourceResponse {
        SourceResponse(url: URL(string: "https://example.invalid/search")!, statusCode: 200,
            headers: [:], body: body, data: Data(body.utf8))
    }
}
